[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)] [string]$TestCasesPath,
    [ValidateSet('design', 'implementation', 'result')] [string]$Mode = 'design',
    [string]$ManifestPath,
    [string]$JavaSourceRoot,
    [string]$EvidenceRoot,
    [string]$PreviousTestCasesPath,
    [switch]$DesignVerifyPassed,
    [string]$GenerateManifestPath
)

$ErrorActionPreference = 'Stop'
$errors = New-Object System.Collections.Generic.List[string]

function Add-ValidationError([string]$Message) { [void]$errors.Add($Message) }
function Get-Field($Object, [string]$Name) {
    if ($null -eq $Object) { return $null }
    if ($Object -is [System.Collections.IDictionary]) { return $Object[$Name] }
    $property = $Object.PSObject.Properties[$Name]
    if ($null -eq $property) { return $null }
    return $property.Value
}
function Convert-Scalar([string]$Value) {
    $value = $Value.Trim()
    if ($value -match '^#') { return $null }
    if (($value.StartsWith('"') -and $value.EndsWith('"')) -or ($value.StartsWith("'") -and $value.EndsWith("'"))) {
        return $value.Substring(1, $value.Length - 2)
    }
    if ($value.StartsWith('[') -and $value.EndsWith(']')) {
        $inner = $value.Substring(1, $value.Length - 2).Trim()
        if ([string]::IsNullOrWhiteSpace($inner)) { return @() }
        return @($inner -split ',' | ForEach-Object { Convert-Scalar $_ })
    }
    if ($value -match '^(?i:true|yes)$') { return $true }
    if ($value -match '^(?i:false|no)$') { return $false }
    if ($value -match '^-?\d+$') { return [int]$value }
    return $value
}
function Read-TestCases([string]$Path) {
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { Add-ValidationError "test-cases source not found: $Path"; return $null }
    $raw = Get-Content -LiteralPath $Path -Raw -Encoding utf8
    if ([string]::IsNullOrWhiteSpace($raw)) { Add-ValidationError 'test-cases source is empty'; return $null }
    if ($raw.TrimStart().StartsWith('{')) {
        try { return $raw | ConvertFrom-Json } catch { Add-ValidationError "test-cases JSON/YAML parse failed: $($_.Exception.Message)"; return $null }
    }
    $root = [ordered]@{ scenarios = @() }
    $scenarioRows = New-Object System.Collections.ArrayList
    $inScenarios = $false
    $current = $null
    foreach ($line in ($raw -split "`r?`n")) {
        if ([string]::IsNullOrWhiteSpace($line) -or $line.TrimStart().StartsWith('#') -or $line.Trim() -eq '---') { continue }
        if ($line -match '^\s*scenarios\s*:\s*$') { $inScenarios = $true; continue }
        if ($inScenarios -and $line -match '^\s*-\s+id\s*:\s*(.+?)\s*$') {
            if ($null -ne $current) { [void]$scenarioRows.Add([pscustomobject]$current) }
            $current = [ordered]@{ id = Convert-Scalar $Matches[1] }
            continue
        }
        if ($inScenarios -and $line -match '^\s*-\s+') {
            if ($null -ne $current) { [void]$scenarioRows.Add([pscustomobject]$current) }
            $current = [ordered]@{}
            Add-ValidationError 'scenario entry is missing id'
            continue
        }
        if ($line -match '^\s*([A-Za-z][A-Za-z0-9_-]*)\s*:\s*(.*?)\s*$') {
            $key = $Matches[1]; $value = Convert-Scalar $Matches[2]
            if ($inScenarios -and $null -ne $current) { $current[$key] = $value }
            else { $root[$key] = $value }
        }
    }
    if ($null -ne $current) { [void]$scenarioRows.Add([pscustomobject]$current) }
    $root.scenarios = @($scenarioRows)
    return [pscustomobject]$root
}
function Get-StringArray($Value) {
    if ($null -eq $Value) { return @() }
    if ($Value -is [System.Array]) { return @($Value | ForEach-Object { [string]$_ }) }
    return @([string]$Value)
}
function Get-SourceHash([string]$Path) {
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return $null }
    return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
}
function Get-ScenarioMap($Document) {
    $scenarios = @(Get-Field $Document 'scenarios')
    $map = @{}
    foreach ($scenario in $scenarios) {
        $id = [string](Get-Field $scenario 'id')
        if ([string]::IsNullOrWhiteSpace($id)) { Add-ValidationError 'scenario is missing id'; continue }
        if ($map.ContainsKey($id)) { Add-ValidationError "duplicate scenario id: $id"; continue }
        $map[$id] = $scenario
    }
    return $map
}
function Compare-StringSets([string[]]$Expected, [string[]]$Actual, [string]$Label) {
    $left = @($Expected | Sort-Object -Unique); $right = @($Actual | Sort-Object -Unique)
    if ((@($left) -join "`n") -ne (@($right) -join "`n")) { Add-ValidationError "$Label drift: expected [$($left -join ', ')] actual [$($right -join ', ')]" }
}

$document = Read-TestCases $TestCasesPath
if ($null -ne $document) {
    if ((Get-Field $document 'schemaVersion') -ne 1) { Add-ValidationError 'schemaVersion must be 1' }
    if ([string](Get-Field $document 'sourceOfTruth') -ne 'test-cases.yaml') { Add-ValidationError 'sourceOfTruth must be test-cases.yaml' }
    $scenarios = @(Get-Field $document 'scenarios')
    if ($scenarios.Count -eq 0) { Add-ValidationError 'test-cases must contain at least one scenario' }
    $map = Get-ScenarioMap $document
    foreach ($scenario in $scenarios) {
        $id = [string](Get-Field $scenario 'id')
        if ([string]::IsNullOrWhiteSpace($id)) { continue }
        if ($id -notmatch '^[A-Za-z0-9][A-Za-z0-9._-]*$') { Add-ValidationError "invalid stable scenario id: $id" }
        foreach ($field in @('acceptance','suite','integration','testClass','testMethod','reportClass','filter','setup','action','assertions','cleanup','observability')) {
            $rawFieldValue = Get-Field $scenario $field
            $isListField = $field -in @('assertions','observability')
            if ($isListField) {
                $items = @(Get-StringArray $rawFieldValue)
                if ($items.Count -eq 0 -or ($items.Count -eq 1 -and [string]::IsNullOrWhiteSpace($items[0]))) { Add-ValidationError "scenario $id is missing $field" }
                foreach ($item in $items) {
                    if ([string]$item -match '(?i)(<change-id>|<acceptance-id>|<system-test-class>|<stable-test-method>|<report-class>|TODO|TBD|待填写|未知|unknown)') {
                        Add-ValidationError "scenario $id contains unfinished $field"
                    }
                }
                continue
            }
            $fieldValue = [string]$rawFieldValue
            if ([string]::IsNullOrWhiteSpace($fieldValue)) { Add-ValidationError "scenario $id is missing $field" }
            if ($fieldValue -match '(?i)(<change-id>|<acceptance-id>|<system-test-class>|<stable-test-method>|<report-class>|TODO|TBD|待填写|未知|unknown)') {
                Add-ValidationError "scenario $id contains unfinished $field"
            }
        }
        $required = Get-Field $scenario 'required'
        if ($required -isnot [bool]) { Add-ValidationError "scenario $id required must be boolean" }
        $evidence = @(Get-StringArray (Get-Field $scenario 'evidence'))
        if ($required -eq $true -and $evidence.Count -eq 0) { Add-ValidationError "required scenario $id has no evidence contract" }
        $integration = [string](Get-Field $scenario 'integration')
        $external = @(Get-StringArray (Get-Field $scenario 'externalEvidence'))
        if ($integration -match '^(?i:N|integration-N)$' -and $external.Count -eq 0) { Add-ValidationError "integration-N scenario $id requires external evidence" }
        if ($EvidenceRoot) {
            foreach ($path in $evidence) {
                if (-not (Test-Path -LiteralPath (Join-Path $EvidenceRoot $path))) { Add-ValidationError "stale evidence for ${id}: $path" }
            }
        }
    }
    $sourceHash = Get-SourceHash $TestCasesPath

    if ($PreviousTestCasesPath) {
        $previous = Read-TestCases $PreviousTestCasesPath
        if ($null -ne $previous) {
            $previousMap = Get-ScenarioMap $previous
            foreach ($oldId in $previousMap.Keys) {
                if ((Get-Field $previousMap[$oldId] 'required') -eq $true -and -not $map.ContainsKey($oldId) -and -not $DesignVerifyPassed) {
                    Add-ValidationError "required scenario removed without design verify: $oldId"
                }
            }
        }
    }

    if ($JavaSourceRoot -and ($Mode -eq 'implementation' -or $Mode -eq 'result')) {
        if (-not (Test-Path -LiteralPath $JavaSourceRoot -PathType Container)) { Add-ValidationError "Java source root not found: $JavaSourceRoot" }
        else {
            $bound = @{}
            foreach ($file in @(Get-ChildItem -LiteralPath $JavaSourceRoot -Recurse -File -Filter '*.java')) {
                $raw = Get-Content -LiteralPath $file.FullName -Raw -Encoding utf8
                $classMatch = [regex]::Match($raw, '(?m)\bclass\s+(?<class>[A-Za-z_][A-Za-z0-9_]*)')
                $className = if ($classMatch.Success) { $classMatch.Groups['class'].Value } else { '' }
                $pattern = '(?s)@TestScenarioId\s*\(\s*["''](?<id>[^"'']+)["'']\s*\)(?<body>.{0,500}?)\b(?<method>[A-Za-z_][A-Za-z0-9_]*)\s*\('
                foreach ($match in [regex]::Matches($raw, $pattern)) {
                    $id = $match.Groups['id'].Value; $method = $match.Groups['method'].Value
                    if ($bound.ContainsKey($id)) { Add-ValidationError "scenario id bound by multiple Java methods: $id" }
                    $bound[$id] = [pscustomobject]@{ class=$className; method=$method; file=$file.FullName }
                    if (-not $map.ContainsKey($id)) { Add-ValidationError "Java method references unknown scenario id: $id" }
                }
            }
            foreach ($id in $map.Keys) {
                $scenario = $map[$id]
                if (-not $bound.ContainsKey($id)) { Add-ValidationError "Java method is not bound to scenario id: $id"; continue }
                $binding = $bound[$id]
                if ($binding.method -ne [string](Get-Field $scenario 'testMethod')) { Add-ValidationError "Java method drift for ${id}: expected $((Get-Field $scenario 'testMethod')) actual $($binding.method)" }
                $expectedClass = [string](Get-Field $scenario 'testClass')
                if ($expectedClass -notmatch [regex]::Escape($binding.class) -and $binding.class -notmatch [regex]::Escape(($expectedClass -split '\.')[-1])) { Add-ValidationError "Java test class drift for $id" }
            }
        }
    }

    $manifestData = [ordered]@{
        schemaVersion = 1; scenarioSource = [IO.Path]::GetFileName($TestCasesPath); scenarioSourceSha256 = $sourceHash
        scenarioCount = $scenarios.Count; requiredScenarioCount = @($scenarios | Where-Object { (Get-Field $_ 'required') -eq $true }).Count
        expectedTestMethodCount = $scenarios.Count
        expectedReportClasses = @($scenarios | ForEach-Object { [string](Get-Field $_ 'reportClass') } | Sort-Object -Unique)
        filters = @($scenarios | ForEach-Object { [pscustomobject]@{ id=[string](Get-Field $_ 'id'); filter=[string](Get-Field $_ 'filter') } } | Sort-Object id)
        evidence = @($scenarios | ForEach-Object { [pscustomobject]@{ id=[string](Get-Field $_ 'id'); required=@(Get-StringArray (Get-Field $_ 'evidence')); external=@(Get-StringArray (Get-Field $_ 'externalEvidence')) } } | Sort-Object id)
    }
    if ($GenerateManifestPath) {
        $manifestData | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $GenerateManifestPath -Encoding utf8
    }
    if ($ManifestPath) {
        if (-not (Test-Path -LiteralPath $ManifestPath -PathType Leaf)) { Add-ValidationError "manifest not found: $ManifestPath" }
        else {
            try { $manifest = Read-TestCases $ManifestPath } catch { $manifest = $null; Add-ValidationError "manifest parse failed: $($_.Exception.Message)" }
            if ($null -ne $manifest) {
                foreach ($field in @('scenarioCount','requiredScenarioCount','expectedTestMethodCount')) {
                    if ((Get-Field $manifest $field) -ne (Get-Field $manifestData $field)) { Add-ValidationError "manifest $field drift" }
                }
                if ([string](Get-Field $manifest 'scenarioSourceSha256') -ne $sourceHash) { Add-ValidationError 'manifest scenario source hash drift' }
                if ([string](Get-Field $manifest 'scenarioSource') -ne [string](Get-Field $manifestData 'scenarioSource')) { Add-ValidationError 'manifest scenario source drift' }
                Compare-StringSets (Get-StringArray (Get-Field $manifestData 'expectedReportClasses')) (Get-StringArray (Get-Field $manifest 'expectedReportClasses')) 'manifest report classes'
                $manifestFilters = @(Get-Field $manifest 'filters')
                foreach ($expected in @(Get-Field $manifestData 'filters')) {
                    $actual = @($manifestFilters | Where-Object { [string](Get-Field $_ 'id') -eq [string](Get-Field $expected 'id') } | Select-Object -First 1)
                    if ($actual.Count -ne 1 -or [string](Get-Field $actual[0] 'filter') -ne [string](Get-Field $expected 'filter')) { Add-ValidationError "manifest filter drift for $((Get-Field $expected 'id'))" }
                }
                $manifestEvidence = @(Get-Field $manifest 'evidence')
                foreach ($expected in @(Get-Field $manifestData 'evidence')) {
                    $actual = @($manifestEvidence | Where-Object { [string](Get-Field $_ 'id') -eq [string](Get-Field $expected 'id') } | Select-Object -First 1)
                    if ($actual.Count -ne 1) { Add-ValidationError "manifest evidence drift for $((Get-Field $expected 'id'))"; continue }
                    Compare-StringSets (Get-StringArray (Get-Field $expected 'required')) (Get-StringArray (Get-Field $actual[0] 'required')) "manifest evidence for $((Get-Field $expected 'id'))"
                    Compare-StringSets (Get-StringArray (Get-Field $expected 'external')) (Get-StringArray (Get-Field $actual[0] 'external')) "manifest external evidence for $((Get-Field $expected 'id'))"
                }
            }
        }
    }
}

if ($errors.Count -gt 0) {
    Write-Output '[TEST_CASES_RESULT] ERROR'
    $errors | ForEach-Object { Write-Output "- $_" }
    exit 1
}
Write-Output '[TEST_CASES_RESULT] PASS'
Write-Output "source_sha256: $(Get-SourceHash $TestCasesPath)"
Write-Output "mode: $Mode"
Write-Output 'manifest_consistency: verified-or-not-requested'
exit 0
