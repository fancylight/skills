[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)] [string]$TestCasesPath,
    [ValidateSet('design', 'implementation', 'result')] [string]$Mode = 'design',
    [string]$CanonicalRevision,
    [string]$ManifestPath,
    [string]$DerivedContractPath,
    [string]$TestPlanPath,
    [string]$JavaSourceRoot,
    [string]$EvidenceRoot,
    [string]$PreviousTestCasesPath,
    [string]$PreviousTestRevision,
    [string]$DesignVerifierReportPath,
    [string]$ControllerStatePath,
    [string]$TrustedVerifierIdentity,
    [switch]$Generate
)

$ErrorActionPreference = 'Stop'
$errors = [System.Collections.Generic.List[string]]::new()
$startMarker = '<!-- FLOW_TEST_CASES_GENERATED:START -->'
$endMarker = '<!-- FLOW_TEST_CASES_GENERATED:END -->'
$utf8NoBom = New-Object System.Text.UTF8Encoding($false)

function Add-ValidationError([string]$Message) { [void]$script:errors.Add($Message) }
function Test-HasField($Object, [string]$Name) {
    if ($null -eq $Object) { return $false }
    if ($Object -is [System.Collections.IDictionary]) { return $Object.Contains($Name) }
    return $null -ne $Object.PSObject.Properties[$Name]
}
function Get-Field($Object, [string]$Name) {
    if (-not (Test-HasField $Object $Name)) { return $null }
    if ($Object -is [System.Collections.IDictionary]) { return $Object[$Name] }
    return $Object.PSObject.Properties[$Name].Value
}
function Get-Sha256Bytes([byte[]]$Bytes) {
    $sha = [Security.Cryptography.SHA256]::Create()
    try { return (-join ($sha.ComputeHash($Bytes) | ForEach-Object { $_.ToString('x2') })) }
    finally { $sha.Dispose() }
}
function Get-Sha256String([string]$Value) { return Get-Sha256Bytes ([Text.Encoding]::UTF8.GetBytes($Value)) }
function Get-FileSha256([string]$Path) {
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return $null }
    return Get-Sha256Bytes ([IO.File]::ReadAllBytes($Path))
}
function Assert-Revision([string]$Revision, [string]$Label) {
    if ([string]::IsNullOrWhiteSpace($Revision) -or $Revision -notmatch '^[0-9a-fA-F]{40,64}$') {
        Add-ValidationError "$Label must be a full Git revision"
    }
}
function Test-Unfinished([string]$Value) {
    return [string]::IsNullOrWhiteSpace($Value) -or $Value -match '(?i)(TODO|TBD|待填写|未知|unknown|<[^>]+>)'
}
function Convert-StrictString([string]$Value, [int]$LineNumber) {
    $value = $Value.Trim()
    if ([string]::IsNullOrWhiteSpace($value)) { throw "line $LineNumber has an empty scalar" }
    if (($value.StartsWith('"') -and $value.EndsWith('"')) -or ($value.StartsWith("'") -and $value.EndsWith("'"))) {
        if ($value.Length -lt 2) { throw "line $LineNumber has malformed quotes" }
        return $value.Substring(1, $value.Length - 2)
    }
    if ($value -match '[\[\]{}]|^[-&*!|>]|\s+#') { throw "line $LineNumber contains unsupported or malformed YAML scalar syntax" }
    return $value
}
function Convert-StrictArray([string]$Value, [int]$LineNumber) {
    $value = $Value.Trim()
    if (-not ($value.StartsWith('[') -and $value.EndsWith(']'))) { throw "line $LineNumber must be an inline YAML list" }
    $inner = $value.Substring(1, $value.Length - 2).Trim()
    if ([string]::IsNullOrWhiteSpace($inner)) { return [pscustomobject]@{ __yamlList = @() } }
    $items = [System.Collections.Generic.List[string]]::new()
    foreach ($part in ($inner -split ',')) {
        if ([string]::IsNullOrWhiteSpace($part)) { throw "line $LineNumber contains an empty list item" }
        [void]$items.Add((Convert-StrictString $part $LineNumber))
    }
    return [pscustomobject]@{ __yamlList = @($items) }
}
function Add-UniqueField($Target, [string]$Key, $Value, [int]$LineNumber) {
    if ($Target.Contains($Key)) { throw "line $LineNumber repeats field '$Key'" }
    $Target[$Key] = $Value
}
function Read-StrictTestCases([string]$Path) {
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { throw "test-cases source not found: $Path" }
    $raw = Get-Content -LiteralPath $Path -Raw -Encoding utf8
    if ([string]::IsNullOrWhiteSpace($raw)) { throw 'test-cases source is empty' }
    $root = [ordered]@{}
    $scenarios = [System.Collections.Generic.List[object]]::new()
    $current = $null
    $section = $null
    $inScenarios = $false
    $lineNumber = 0
    foreach ($line in ($raw -split "`r?`n")) {
        $lineNumber++
        if ($line -match "`t") { throw "line $lineNumber contains a tab; only spaces are allowed" }
        if ([string]::IsNullOrWhiteSpace($line) -or $line.TrimStart().StartsWith('#') -or $line.Trim() -eq '---') { continue }
        $indent = $line.Length - $line.TrimStart(' ').Length
        $trimmed = $line.Trim()
        if ($indent -eq 0) {
            if ($trimmed -notmatch '^([A-Za-z][A-Za-z0-9]*)\s*:\s*(.*)$') { throw "line $lineNumber is malformed YAML" }
            $key = $Matches[1]; $value = $Matches[2]
            if ($key -notin @('schemaVersion','scenarios')) { throw "line $lineNumber contains unknown root field '$key'" }
            if ($key -eq 'schemaVersion') {
                if ($value -notmatch '^\d+$') { throw "line $lineNumber schemaVersion must be an integer" }
                Add-UniqueField $root $key ([int]$value) $lineNumber
            } else {
                if (-not [string]::IsNullOrWhiteSpace($value)) { throw "line $lineNumber scenarios must be a YAML list" }
                if ($root.Contains('scenarios')) { throw "line $lineNumber repeats field 'scenarios'" }
                $root['scenarios'] = $null
                $inScenarios = $true
            }
            $section = $null
            continue
        }
        if ($indent -eq 2) {
            if (-not $inScenarios -or $trimmed -notmatch '^-\s+id\s*:\s*(.+)$') { throw "line $lineNumber must start a scenario with '- id:'" }
            if ($null -ne $current) { [void]$scenarios.Add([pscustomobject]$current) }
            $current = [ordered]@{}
            Add-UniqueField $current 'id' (Convert-StrictString $Matches[1] $lineNumber) $lineNumber
            $section = $null
            continue
        }
        if ($indent -eq 4) {
            if ($null -eq $current -or $trimmed -notmatch '^([A-Za-z][A-Za-z0-9]*)\s*:\s*(.*)$') { throw "line $lineNumber has invalid scenario nesting" }
            $key = $Matches[1]; $value = $Matches[2]
            $allowed = @('acceptance','required','suite','integration','testClass','testMethod','reportClass','filter','externalEvidence','setup','action','assertions','cleanup','observability')
            if ($key -notin $allowed) { throw "line $lineNumber contains unknown scenario field '$key'" }
            if ($key -in @('setup','action','assertions','observability')) {
                if (-not [string]::IsNullOrWhiteSpace($value)) { throw "line $lineNumber field '$key' must be a structured mapping" }
                $mapping = [ordered]@{}
                Add-UniqueField $current $key $mapping $lineNumber
                $section = $key
            } else {
                $section = $null
                if ($key -eq 'required') {
                    if ($value -notmatch '^(?i:true|false)$') { throw "line $lineNumber required must be boolean" }
                    Add-UniqueField $current $key ([bool]::Parse($value)) $lineNumber
                } elseif ($key -in @('externalEvidence','cleanup')) {
                    Add-UniqueField $current $key (Convert-StrictArray $value $lineNumber) $lineNumber
                } else {
                    Add-UniqueField $current $key (Convert-StrictString $value $lineNumber) $lineNumber
                }
            }
            continue
        }
        if ($indent -eq 6) {
            if ($null -eq $current -or [string]::IsNullOrWhiteSpace($section) -or $trimmed -notmatch '^([A-Za-z][A-Za-z0-9]*)\s*:\s*(.*)$') { throw "line $lineNumber has invalid nested mapping" }
            $key = $Matches[1]; $value = $Matches[2]
            $allowedBySection = @{
                setup = @('fixtures'); action = @('method','path'); assertions = @('response','database','sideEffects'); observability = @('correlationField','allowedEvidence')
            }
            if ($key -notin $allowedBySection[$section]) { throw "line $lineNumber contains unknown '$section' field '$key'" }
            $mapping = Get-Field $current $section
            if ($section -in @('setup','assertions') -or ($section -eq 'observability' -and $key -eq 'allowedEvidence')) {
                Add-UniqueField $mapping $key (Convert-StrictArray $value $lineNumber) $lineNumber
            } else {
                Add-UniqueField $mapping $key (Convert-StrictString $value $lineNumber) $lineNumber
            }
            continue
        }
        throw "line $lineNumber has unsupported indentation $indent"
    }
    if ($null -ne $current) { [void]$scenarios.Add([pscustomobject]$current) }
    if (-not $root.Contains('scenarios')) { throw "root field 'scenarios' is required" }
    $root['scenarios'] = @($scenarios)
    return [pscustomobject]$root
}
function Assert-RequiredFields($Object, [string[]]$Fields, [string]$Label) {
    foreach ($field in $Fields) { if (-not (Test-HasField $Object $field)) { Add-ValidationError "$Label is missing $field" } }
}
function Get-StringList($Value, [string]$Label, [bool]$AllowEmpty) {
    if (-not (Test-HasField $Value '__yamlList')) { Add-ValidationError "$Label must be a list"; return @() }
    $items = @(Get-Field $Value '__yamlList')
    if (-not $AllowEmpty -and $items.Count -eq 0) { Add-ValidationError "$Label must not be empty" }
    foreach ($item in $items) {
        if ($item -isnot [string] -or (Test-Unfinished ([string]$item))) { Add-ValidationError "$Label contains an invalid or unfinished item" }
    }
    return @($items | ForEach-Object { [string]$_ })
}
function Get-ScenarioMap($Document) {
    $map = @{}
    foreach ($scenario in @(Get-Field $Document 'scenarios')) {
        $id = [string](Get-Field $scenario 'id')
        if ([string]::IsNullOrWhiteSpace($id)) { Add-ValidationError 'scenario is missing id'; continue }
        if ($map.ContainsKey($id)) { Add-ValidationError "duplicate scenario id: $id"; continue }
        $map[$id] = $scenario
    }
    return $map
}
function Test-EvidencePath([string]$Root, [string]$Relative, [string]$Label) {
    if ([IO.Path]::IsPathRooted($Relative) -or $Relative -match '(^|[\\/])\.\.([\\/]|$)') { Add-ValidationError "$Label must be a safe relative path: $Relative"; return }
    if ($Root -and -not (Test-Path -LiteralPath (Join-Path $Root $Relative) -PathType Leaf)) { Add-ValidationError "$Label is stale: $Relative" }
}
function Test-DocumentSchema($Document) {
    if ($null -eq $Document) { return @{} }
    Assert-RequiredFields $Document @('schemaVersion','scenarios') 'test-cases root'
    if ((Get-Field $Document 'schemaVersion') -ne 1) { Add-ValidationError 'schemaVersion must be 1' }
    $scenarios = @(Get-Field $Document 'scenarios')
    if ($scenarios.Count -eq 0) { Add-ValidationError 'test-cases must contain at least one scenario' }
    $map = Get-ScenarioMap $Document
    foreach ($scenario in $scenarios) {
        $id = [string](Get-Field $scenario 'id')
        $fields = @('id','acceptance','required','suite','integration','externalEvidence','setup','action','assertions','cleanup','observability')
        Assert-RequiredFields $scenario $fields "scenario $id"
        foreach ($field in @('id','acceptance','suite')) {
            $value = Get-Field $scenario $field
            if ($value -isnot [string] -or (Test-Unfinished ([string]$value))) { Add-ValidationError "scenario $id has invalid or unfinished $field" }
        }
        if ($id -and $id -notmatch '^[A-Za-z0-9][A-Za-z0-9._-]*$') { Add-ValidationError "invalid stable scenario id: $id" }
        if ((Get-Field $scenario 'required') -isnot [bool]) { Add-ValidationError "scenario $id required must be boolean" }
        $integration = [string](Get-Field $scenario 'integration')
        if ($integration -notin @('Y','N')) { Add-ValidationError "scenario $id integration must be Y or N" }
        if ($integration -eq 'Y') {
            foreach ($field in @('testClass','testMethod','reportClass','filter')) {
                if (-not (Test-HasField $scenario $field) -or (Get-Field $scenario $field) -isnot [string] -or (Test-Unfinished ([string](Get-Field $scenario $field)))) {
                    Add-ValidationError "integration=Y scenario $id has invalid or missing $field"
                }
            }
        } else {
            foreach ($field in @('testClass','testMethod','reportClass','filter')) {
                if (Test-HasField $scenario $field) { Add-ValidationError "integration=N scenario $id must not declare executable field $field" }
            }
        }
        $setup = Get-Field $scenario 'setup'; $action = Get-Field $scenario 'action'; $assertions = Get-Field $scenario 'assertions'; $observability = Get-Field $scenario 'observability'
        Assert-RequiredFields $setup @('fixtures') "scenario $id setup"
        Assert-RequiredFields $action @('method','path') "scenario $id action"
        Assert-RequiredFields $assertions @('response','database','sideEffects') "scenario $id assertions"
        Assert-RequiredFields $observability @('correlationField','allowedEvidence') "scenario $id observability"
        [void](Get-StringList (Get-Field $setup 'fixtures') "scenario $id setup.fixtures" $false)
        foreach ($field in @('method','path')) { if ((Get-Field $action $field) -isnot [string] -or (Test-Unfinished ([string](Get-Field $action $field)))) { Add-ValidationError "scenario $id action.$field is invalid" } }
        if ([string](Get-Field $action 'method') -notmatch '^[A-Z]+$') { Add-ValidationError "scenario $id action.method must be an uppercase HTTP method" }
        if ([string](Get-Field $action 'path') -notmatch '^/\S*$') { Add-ValidationError "scenario $id action.path must be an absolute request path" }
        foreach ($field in @('response','database','sideEffects')) { [void](Get-StringList (Get-Field $assertions $field) "scenario $id assertions.$field" $true) }
        [void](Get-StringList (Get-Field $scenario 'cleanup') "scenario $id cleanup" $false)
        if ((Get-Field $observability 'correlationField') -isnot [string] -or (Test-Unfinished ([string](Get-Field $observability 'correlationField')))) { Add-ValidationError "scenario $id observability.correlationField is invalid" }
        $ordinary = @(Get-StringList (Get-Field $observability 'allowedEvidence') "scenario $id observability.allowedEvidence" $false)
        $external = @(Get-StringList (Get-Field $scenario 'externalEvidence') "scenario $id externalEvidence" $true)
        if ($integration -eq 'N' -and $external.Count -eq 0) { Add-ValidationError "integration=N scenario $id requires externalEvidence" }
        foreach ($path in $ordinary) { Test-EvidencePath $EvidenceRoot $path "ordinary evidence for $id" }
        foreach ($path in $external) { Test-EvidencePath $EvidenceRoot $path "external evidence for $id" }
    }
    return $map
}
function ConvertTo-CanonicalObject($Value) {
    if ($null -eq $Value) { return $null }
    if ($Value -is [string] -or $Value -is [bool] -or $Value -is [ValueType]) { return $Value }
    if ($Value -is [System.Collections.IDictionary]) {
        $ordered = [ordered]@{}
        foreach ($key in @($Value.Keys | Sort-Object)) { $ordered[[string]$key] = ConvertTo-CanonicalObject $Value[$key] }
        return [pscustomobject]$ordered
    }
    if ($Value -is [System.Collections.IEnumerable] -and $Value -isnot [string]) { return @($Value | ForEach-Object { ConvertTo-CanonicalObject $_ }) }
    $ordered = [ordered]@{}
    foreach ($property in @($Value.PSObject.Properties | Sort-Object Name)) { $ordered[$property.Name] = ConvertTo-CanonicalObject $property.Value }
    return [pscustomobject]$ordered
}
function ConvertTo-CanonicalJson($Value) { return (ConvertTo-CanonicalObject $Value | ConvertTo-Json -Depth 20 -Compress) }
function Read-JsonFile([string]$Path, [string]$Label) {
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { Add-ValidationError "$Label not found: $Path"; return $null }
    try { return Get-Content -LiteralPath $Path -Raw -Encoding utf8 | ConvertFrom-Json }
    catch { Add-ValidationError "$Label is not valid JSON: $($_.Exception.Message)"; return $null }
}
function Find-ByteSequence([byte[]]$Bytes, [byte[]]$Needle) {
    $positions = [System.Collections.Generic.List[int]]::new()
    for ($i = 0; $i -le $Bytes.Length - $Needle.Length; $i++) {
        $match = $true
        for ($j = 0; $j -lt $Needle.Length; $j++) { if ($Bytes[$i + $j] -ne $Needle[$j]) { $match = $false; break } }
        if ($match) { [void]$positions.Add($i) }
    }
    return @($positions)
}
function Get-PlanParts([string]$Path) {
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { Add-ValidationError "test-plan not found: $Path"; return $null }
    $bytes = [IO.File]::ReadAllBytes($Path)
    $startBytes = [Text.Encoding]::UTF8.GetBytes($startMarker); $endBytes = [Text.Encoding]::UTF8.GetBytes($endMarker)
    $starts = @(Find-ByteSequence $bytes $startBytes); $ends = @(Find-ByteSequence $bytes $endBytes)
    if ($starts.Count -ne 1 -or $ends.Count -ne 1 -or $ends[0] -le $starts[0]) { Add-ValidationError 'test-plan must contain exactly one ordered generated region'; return $null }
    $prefixLength = $starts[0] + $startBytes.Length
    $middleLength = $ends[0] - $prefixLength
    $suffixLength = $bytes.Length - $ends[0]
    $prefix = New-Object byte[] $prefixLength; if ($prefixLength -gt 0) { [Array]::Copy($bytes, 0, $prefix, 0, $prefixLength) }
    $middle = New-Object byte[] $middleLength; if ($middleLength -gt 0) { [Array]::Copy($bytes, $prefixLength, $middle, 0, $middleLength) }
    $suffix = New-Object byte[] $suffixLength; if ($suffixLength -gt 0) { [Array]::Copy($bytes, $ends[0], $suffix, 0, $suffixLength) }
    $outside = New-Object byte[] ($prefix.Length + $suffix.Length)
    [Array]::Copy($prefix, 0, $outside, 0, $prefix.Length); [Array]::Copy($suffix, 0, $outside, $prefix.Length, $suffix.Length)
    $outsideText = [Text.Encoding]::UTF8.GetString($outside)
    if ($outsideText -match '(?im)^\s*\|\s*(?:AC-[^|]*|场景\s*ID|scenario\s*ID)\s*\|' -or $outsideText -match '(?i)requiredScenarioCount|expectedTestMethodCount') {
        Add-ValidationError 'test-plan contains a second executable scenario mapping or count outside the generated region'
    }
    $newline = if ([Text.Encoding]::UTF8.GetString($bytes).Contains("`r`n")) { "`r`n" } else { "`n" }
    return [pscustomobject]@{ bytes=$bytes; prefix=$prefix; middle=$middle; suffix=$suffix; outsideHash=(Get-Sha256Bytes $outside); newline=$newline }
}
function Get-GeneratedPlanText($Document) {
    $lines = [System.Collections.Generic.List[string]]::new()
    [void]$lines.Add('| 场景 ID | 验收 | Required | Integration | Suite | Java 绑定 | Action | Filter | Report | Evidence |')
    [void]$lines.Add('|---|---|---|---|---|---|---|---|---|---|')
    foreach ($scenario in @((Get-Field $Document 'scenarios') | Sort-Object { [string](Get-Field $_ 'id') })) {
        $id = [string](Get-Field $scenario 'id'); $action = Get-Field $scenario 'action'; $observability = Get-Field $scenario 'observability'
        $ordinary = @(Get-StringList (Get-Field $observability 'allowedEvidence') "scenario $id observability.allowedEvidence" $true) -join ', '; $external = @(Get-StringList (Get-Field $scenario 'externalEvidence') "scenario $id externalEvidence" $true) -join ', '
        $evidence = if ([string]::IsNullOrWhiteSpace($external)) { $ordinary } else { "$ordinary; external: $external" }
        $required = ([string](Get-Field $scenario 'required')).ToLowerInvariant()
        $java = if ((Get-Field $scenario 'integration') -eq 'Y') { "$((Get-Field $scenario 'testClass'))#$((Get-Field $scenario 'testMethod'))" } else { 'external-only' }
        $actionText = "$((Get-Field $action 'method')) $((Get-Field $action 'path'))"
        $filter = if ((Get-Field $scenario 'integration') -eq 'Y') { [string](Get-Field $scenario 'filter') } else { '-' }
        $report = if ((Get-Field $scenario 'integration') -eq 'Y') { [string](Get-Field $scenario 'reportClass') } else { '-' }
        [void]$lines.Add("| $id | $((Get-Field $scenario 'acceptance')) | $required | $((Get-Field $scenario 'integration')) | $((Get-Field $scenario 'suite')) | $java | $actionText | $filter | $report | $evidence |")
    }
    return ($lines -join "`n")
}
function Write-AtomicBytes([string]$Path, [byte[]]$Bytes) {
    $directory = Split-Path -Parent ([IO.Path]::GetFullPath($Path))
    if (-not (Test-Path -LiteralPath $directory -PathType Container)) { [void](New-Item -ItemType Directory -Path $directory -Force) }
    $temporary = Join-Path $directory ('.test-cases-' + [guid]::NewGuid().ToString('N') + '.tmp')
    try { [IO.File]::WriteAllBytes($temporary, $Bytes); Move-Item -LiteralPath $temporary -Destination $Path -Force }
    finally { if (Test-Path -LiteralPath $temporary) { Remove-Item -LiteralPath $temporary -Force } }
}
function Write-GeneratedPlanRegion([string]$Path, [string]$GeneratedText, $Parts) {
    $middleBytes = [Text.Encoding]::UTF8.GetBytes($Parts.newline + $GeneratedText.Replace("`n", $Parts.newline) + $Parts.newline)
    $output = New-Object byte[] ($Parts.prefix.Length + $middleBytes.Length + $Parts.suffix.Length)
    [Array]::Copy($Parts.prefix, 0, $output, 0, $Parts.prefix.Length)
    [Array]::Copy($middleBytes, 0, $output, $Parts.prefix.Length, $middleBytes.Length)
    [Array]::Copy($Parts.suffix, 0, $output, $Parts.prefix.Length + $middleBytes.Length, $Parts.suffix.Length)
    Write-AtomicBytes $Path $output
}
function New-DerivedContract($Document, [string]$SourceHash, [string]$Revision, [string]$PlanOutsideHash) {
    $sorted = @((Get-Field $Document 'scenarios') | Sort-Object { [string](Get-Field $_ 'id') })
    return [pscustomobject][ordered]@{
        schemaVersion = 1
        kind = 'flow-test-cases-derived'
        source = [pscustomobject][ordered]@{ path=[IO.Path]::GetFileName($TestCasesPath); sha256=$SourceHash; canonicalRevision=$Revision; testPlanOutsideSha256=$PlanOutsideHash }
        scenarioCount = $sorted.Count
        requiredScenarioCount = @($sorted | Where-Object { (Get-Field $_ 'required') -eq $true }).Count
        expectedTestMethodCount = @($sorted | Where-Object { (Get-Field $_ 'integration') -eq 'Y' }).Count
        integrationDecisions = @($sorted | ForEach-Object { [pscustomobject][ordered]@{ id=[string](Get-Field $_ 'id'); acceptance=[string](Get-Field $_ 'acceptance'); required=[bool](Get-Field $_ 'required'); integration=[string](Get-Field $_ 'integration') } })
        runnerFilters = @($sorted | Where-Object { (Get-Field $_ 'integration') -eq 'Y' } | ForEach-Object { [pscustomobject][ordered]@{ id=[string](Get-Field $_ 'id'); filter=[string](Get-Field $_ 'filter') } })
        expectedReportClasses = @($sorted | Where-Object { (Get-Field $_ 'integration') -eq 'Y' } | ForEach-Object { [string](Get-Field $_ 'reportClass') } | Sort-Object -Unique)
        evidenceIndex = @($sorted | ForEach-Object { $o=Get-Field $_ 'observability'; [pscustomobject][ordered]@{ id=[string](Get-Field $_ 'id'); required=[bool](Get-Field $_ 'required'); allowedEvidence=@(Get-StringList (Get-Field $o 'allowedEvidence') "scenario $((Get-Field $_ 'id')) observability.allowedEvidence" $true); externalEvidence=@(Get-StringList (Get-Field $_ 'externalEvidence') "scenario $((Get-Field $_ 'id')) externalEvidence" $true) } })
        failureObservability = @($sorted | ForEach-Object {
            $o=Get-Field $_ 'observability'; $isExecutable=(Get-Field $_ 'integration') -eq 'Y'
            $testClass=if($isExecutable){[string](Get-Field $_ 'testClass')}else{$null}; $testMethod=if($isExecutable){[string](Get-Field $_ 'testMethod')}else{$null}
            [pscustomobject][ordered]@{ id=[string](Get-Field $_ 'id'); testClass=$testClass; testMethod=$testMethod; correlationField=[string](Get-Field $o 'correlationField'); allowedEvidence=@(Get-StringList (Get-Field $o 'allowedEvidence') "scenario $((Get-Field $_ 'id')) observability.allowedEvidence" $true); externalEvidence=@(Get-StringList (Get-Field $_ 'externalEvidence') "scenario $((Get-Field $_ 'id')) externalEvidence" $true); defaultCategory='UNDETERMINED' }
        })
    }
}
function Test-ManifestPointer($Manifest, [string]$ExpectedContractPath) {
    if ($null -eq $Manifest) { return }
    $legacy = @('scenarioCount','requiredScenarioCount','expectedTestMethodCount','expectedReportClasses','integrationDecisions','runnerFilters','filters','evidence','evidenceIndex','failureObservability')
    foreach ($field in $legacy) { if (Test-HasField $Manifest $field) { Add-ValidationError "manifest contains legacy derived field '$field'; migrate it to the canonical sidecar" } }
    $pointer = Get-Field $Manifest 'testCasesContract'
    if ($null -eq $pointer) { Add-ValidationError 'manifest must declare testCasesContract.path'; return }
    $properties = @($pointer.PSObject.Properties.Name)
    foreach ($property in $properties) { if ($property -ne 'path') { Add-ValidationError "manifest testCasesContract contains unknown field '$property'" } }
    $relative = [string](Get-Field $pointer 'path')
    if ([string]::IsNullOrWhiteSpace($relative) -or [IO.Path]::IsPathRooted($relative) -or $relative -match '(^|[\\/])\.\.([\\/]|$)') { Add-ValidationError 'manifest testCasesContract.path must be a safe relative path'; return }
    $resolved = [IO.Path]::GetFullPath((Join-Path (Split-Path -Parent $ManifestPath) $relative))
    if ($ExpectedContractPath -and $resolved -ne [IO.Path]::GetFullPath($ExpectedContractPath)) { Add-ValidationError 'manifest testCasesContract.path does not identify the supplied derived contract' }
}
function Get-StateIntegrityHash($State) {
    $previous = $State.integrityHash; $State.integrityHash = ''
    try { return Get-Sha256String ($State | ConvertTo-Json -Depth 16 -Compress) }
    finally { $State.integrityHash = $previous }
}
function Test-RequiredRemovalEvidence($PreviousDocument, $CurrentMap, [string]$PreviousHash, [string]$CurrentHash) {
    $removed = @()
    foreach ($scenario in @(Get-Field $PreviousDocument 'scenarios')) {
        $id = [string](Get-Field $scenario 'id')
        if ((Get-Field $scenario 'required') -eq $true -and -not $CurrentMap.ContainsKey($id)) { $removed += $id }
    }
    if ($removed.Count -eq 0) { return }
    Assert-Revision $PreviousTestRevision 'previous test revision'; Assert-Revision $CanonicalRevision 'current test revision'
    if ([string]::IsNullOrWhiteSpace($DesignVerifierReportPath) -or [string]::IsNullOrWhiteSpace($ControllerStatePath) -or [string]::IsNullOrWhiteSpace($TrustedVerifierIdentity)) {
        Add-ValidationError "required scenarios removed without trusted design verifier evidence: $($removed -join ', ')"; return
    }
    $report = Read-JsonFile $DesignVerifierReportPath 'design verifier report'; $state = Read-JsonFile $ControllerStatePath 'controller state'
    if ($null -eq $report -or $null -eq $state) { return }
    $reportFields = @('schemaVersion','result','mode','verifierId','previousTestRevision','currentTestRevision','previousSourceSha256','currentSourceSha256','summary')
    foreach ($field in $reportFields) { if (-not (Test-HasField $report $field)) { Add-ValidationError "design verifier report is missing $field" } }
    foreach ($property in @($report.PSObject.Properties.Name)) { if ($property -notin $reportFields) { Add-ValidationError "design verifier report contains unknown field '$property'" } }
    if ([string]::IsNullOrWhiteSpace([string]$state.integrityHash) -or $state.integrityHash -ne (Get-StateIntegrityHash $state)) { Add-ValidationError 'controller state integrity hash is invalid'; return }
    $summaryFacts = [pscustomobject][ordered]@{ previousTestRevision=$PreviousTestRevision; currentTestRevision=$CanonicalRevision; previousSourceSha256=$PreviousHash; currentSourceSha256=$CurrentHash }
    $expectedSummary = 'required-scenario-removal:' + (Get-Sha256String (ConvertTo-CanonicalJson $summaryFacts))
    if ($report.schemaVersion -ne 1 -or $report.result -ne 'PASS' -or $report.mode -ne 'design' -or $report.verifierId -ne $TrustedVerifierIdentity -or
        $report.previousTestRevision -ne $PreviousTestRevision -or $report.currentTestRevision -ne $CanonicalRevision -or
        $report.previousSourceSha256 -ne $PreviousHash -or $report.currentSourceSha256 -ne $CurrentHash -or $report.summary -ne $expectedSummary) {
        Add-ValidationError 'design verifier report is forged, stale, or not bound to the required removal'; return
    }
    if ($state.phase -ne 'TEST_DESIGN_VERIFIED' -or $state.revisions.test -ne $CanonicalRevision -or $state.verifier.identity -ne $TrustedVerifierIdentity -or
        $state.verifier.mode -ne 'design' -or $state.verifier.testRevision -ne $CanonicalRevision -or $state.verifier.summaryHash -ne (Get-Sha256String $expectedSummary)) {
        Add-ValidationError 'controller state does not attest the supplied design verifier PASS'
    }
}
function Test-JavaBindings($Document) {
    if (-not (Test-Path -LiteralPath $JavaSourceRoot -PathType Container)) { Add-ValidationError "Java source root not found: $JavaSourceRoot"; return }
    $allScenarios = Get-ScenarioMap $Document; $map = @{}; $bindings = @{}
    foreach ($id in $allScenarios.Keys) { if ((Get-Field $allScenarios[$id] 'integration') -eq 'Y') { $map[$id] = $allScenarios[$id] } }
    foreach ($file in @(Get-ChildItem -LiteralPath $JavaSourceRoot -Recurse -File -Filter '*.java')) {
        $raw = Get-Content -LiteralPath $file.FullName -Raw -Encoding utf8
        $packageMatch = [regex]::Match($raw, '(?m)^\s*package\s+(?<package>[A-Za-z_][A-Za-z0-9_.]*)\s*;')
        $packageName = if ($packageMatch.Success) { $packageMatch.Groups['package'].Value } else { '' }
        $classes = @([regex]::Matches($raw, '(?m)\b(?:class|record|interface)\s+(?<class>[A-Za-z_][A-Za-z0-9_]*)'))
        $annotations = @([regex]::Matches($raw, '@TestScenarioId\s*\(\s*["''](?<id>[^"'']+)["'']\s*\)'))
        for ($i = 0; $i -lt $annotations.Count; $i++) {
            $annotation = $annotations[$i]; $end = if ($i + 1 -lt $annotations.Count) { $annotations[$i + 1].Index } else { $raw.Length }
            $tail = $raw.Substring($annotation.Index + $annotation.Length, $end - ($annotation.Index + $annotation.Length))
            $methodPattern = '(?s)^\s*(?:(?:/\*.*?\*/|//[^\r\n]*(?:\r?\n|$)|@[A-Za-z_][A-Za-z0-9_.]*(?:\s*\([^)]*\))?)\s*)*(?:(?:public|protected|private|static|final|synchronized|abstract|native|strictfp|default)\s+)*(?:[A-Za-z_$][A-Za-z0-9_$.<>\[\],?]*\s+)+(?<method>[A-Za-z_$][A-Za-z0-9_$]*)\s*\('
            $methodMatch = [regex]::Match($tail, $methodPattern)
            $id = $annotation.Groups['id'].Value
            if (-not $methodMatch.Success) { Add-ValidationError "Java scenario annotation is not attached to a test method: $id"; continue }
            $classCandidates = @($classes | Where-Object { $_.Index -lt $annotation.Index })
            if ($classCandidates.Count -eq 0) { Add-ValidationError "Java scenario annotation has no containing class: $id"; continue }
            $className = $classCandidates[-1].Groups['class'].Value
            $qualifiedClass = if ($packageName) { "$packageName.$className" } else { $className }
            if ($bindings.ContainsKey($id)) { Add-ValidationError "scenario id bound by multiple Java methods: $id"; continue }
            $bindings[$id] = [pscustomobject]@{ class=$qualifiedClass; method=$methodMatch.Groups['method'].Value }
            if (-not $map.ContainsKey($id)) { Add-ValidationError "Java method references unknown scenario id: $id" }
        }
    }
    foreach ($id in $map.Keys) {
        if (-not $bindings.ContainsKey($id)) { Add-ValidationError "Java method is not bound to scenario id: $id"; continue }
        $scenario = $map[$id]; $binding = $bindings[$id]
        if ($binding.class -ne [string](Get-Field $scenario 'testClass')) { Add-ValidationError "Java test class drift for $id" }
        if ($binding.method -ne [string](Get-Field $scenario 'testMethod')) { Add-ValidationError "Java method drift for $id" }
    }
}

$document = $null
try { $document = Read-StrictTestCases $TestCasesPath }
catch { Add-ValidationError "strict YAML parse failed: $($_.Exception.Message)" }
$sourceHash = Get-FileSha256 $TestCasesPath
$scenarioMap = if ($null -ne $document) { Test-DocumentSchema $document } else { @{} }

$previousDocument = $null
if ($PreviousTestCasesPath) {
    try { $previousDocument = Read-StrictTestCases $PreviousTestCasesPath; [void](Test-DocumentSchema $previousDocument) }
    catch { Add-ValidationError "previous test-cases strict YAML parse failed: $($_.Exception.Message)" }
    if ($null -ne $previousDocument) { Test-RequiredRemovalEvidence $previousDocument $scenarioMap (Get-FileSha256 $PreviousTestCasesPath) $sourceHash }
}

$needsDerived = $Generate -or $ManifestPath -or $DerivedContractPath -or $TestPlanPath
if ($needsDerived) { Assert-Revision $CanonicalRevision 'canonical revision' }
$manifest = if ($ManifestPath) { Read-JsonFile $ManifestPath 'manifest' } else { $null }
if ($ManifestPath) { Test-ManifestPointer $manifest $DerivedContractPath }
$planParts = if ($TestPlanPath) { Get-PlanParts $TestPlanPath } else { $null }
$derived = if ($null -ne $document -and $null -ne $planParts -and $CanonicalRevision) { New-DerivedContract $document $sourceHash $CanonicalRevision $planParts.outsideHash } else { $null }
$generatedPlan = if ($null -ne $document) { Get-GeneratedPlanText $document } else { $null }

if ($Generate) {
    if (-not $ManifestPath -or -not $DerivedContractPath -or -not $TestPlanPath) { Add-ValidationError 'generation requires ManifestPath, DerivedContractPath, and TestPlanPath' }
    if ($errors.Count -eq 0) {
        Write-GeneratedPlanRegion $TestPlanPath $generatedPlan $planParts
        $json = $derived | ConvertTo-Json -Depth 20
        Write-AtomicBytes $DerivedContractPath $utf8NoBom.GetBytes($json)
        $planParts = Get-PlanParts $TestPlanPath
    }
}

if ($null -ne $derived -and $DerivedContractPath) {
    $actualDerived = Read-JsonFile $DerivedContractPath 'derived test-cases contract'
    if ($null -ne $actualDerived -and (ConvertTo-CanonicalJson $actualDerived) -ne (ConvertTo-CanonicalJson $derived)) { Add-ValidationError 'derived contract drift from canonical test-cases source/revision/test-plan' }
}
if ($null -ne $planParts -and $null -ne $generatedPlan) {
    $expectedMiddle = $planParts.newline + $generatedPlan.Replace("`n", $planParts.newline) + $planParts.newline
    if ([Text.Encoding]::UTF8.GetString($planParts.middle) -ne $expectedMiddle) { Add-ValidationError 'test-plan generated region drift from canonical test-cases source' }
}
if ($JavaSourceRoot -and $Mode -in @('implementation','result') -and $null -ne $document) { Test-JavaBindings $document }

if ($errors.Count -gt 0) {
    Write-Output '[TEST_CASES_RESULT] ERROR'
    $errors | ForEach-Object { Write-Output "- $_" }
    exit 1
}
Write-Output '[TEST_CASES_RESULT] PASS'
Write-Output "source_sha256: $sourceHash"
Write-Output "canonical_revision: $CanonicalRevision"
Write-Output "mode: $Mode"
Write-Output 'derived_contract: verified-or-not-requested'
exit 0
