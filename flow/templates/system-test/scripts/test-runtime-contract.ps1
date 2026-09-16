# Shared runtime input and selected-scenario rules. No configuration values are emitted.
function Get-TestConfigurationContentHash([string]$Path, [string]$Ownership, [string]$Repository) {
    $humanLocal = $false
    if ($Ownership -eq 'human' -and -not [string]::IsNullOrWhiteSpace($Repository)) {
        $ignored = @(& git -C $Repository check-ignore -- $Path 2>$null)
        $humanLocal = $LASTEXITCODE -eq 0 -and $ignored.Count -gt 0
    }
    if (-not $humanLocal) {
        $content = Get-Content -LiteralPath $Path -Raw -Encoding utf8
        if ($content -match '(?i)\b[a-z][a-z0-9+.-]*://[^\s/:@]+:[^\s/@]+@') { throw 'ERROR_SECRET_INPUT: configuration template contains an inline credential' }
        $pattern = '(?im)^\s*(?:password|passwd|token|cookie|secret|credential|app[-_.]?secret|secret[-_.]?key|jdbc[-_.]?url|connection[-_.]?string)\s*:\s*(?<value>[^\r\n]*)\r?$'
        foreach ($match in [regex]::Matches($content, $pattern)) {
            $value = $match.Groups['value'].Value.Trim().Trim('"', "'")
            if ($value -and $value -notmatch '^\$\{[A-Z][A-Z0-9_]*\}$') { throw 'ERROR_SECRET_INPUT: configuration template requires references' }
        }
    }
    # Hash the complete file, including local values, so changing a credential invalidates the snapshot.
    return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
}

function Get-TestStateIntegrityHashFromRaw([string]$Raw) {
    # Caller parses valid JSON first. Preserve the writer's escaping and number
    # spelling; PS 5 and 7 serialize identical objects differently.
    $parts=[regex]::Matches($Raw,'"(?:\\.|[^"\\])*"|[^\s]')
    $builder=[Text.StringBuilder]::new(); $depth=0; $blank=$false; $previous=''; $found=0
    foreach($part in $parts) {
        $value=$part.Value
        if($blank -and $value -ne ':') { [void]$builder.Append('""'); $blank=$false }
        else {
            [void]$builder.Append($value)
            if($depth -eq 1 -and $value -eq '"integrityHash"' -and $previous -in @('{',',')) { $blank=$true; $found++ }
        }
        if($value -in @('{','[')){$depth++} elseif($value -in @('}',']')){$depth--}
        $previous=$value
    }
    if($found -ne 1 -or $blank){throw 'State must contain exactly one root integrityHash'}
    $sha=[Security.Cryptography.SHA256]::Create()
    try{return -join($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($builder.ToString()))|ForEach-Object{$_.ToString('x2')})}finally{$sha.Dispose()}
}

function Protect-TestRuntimeText([string]$Text, [string[]]$SensitiveValues = @()) {
    $safe = $Text
    foreach ($value in @($SensitiveValues | Where-Object { $_ } | Sort-Object Length -Descending -Unique)) {
        $safe = $safe.Replace($value, '<redacted>')
    }
    $safe = [regex]::Replace($safe, '(?i)(?:Bearer\s+)[A-Za-z0-9._~+/=-]+', 'Bearer <redacted>')
    $safe = [regex]::Replace($safe, '(?i)\b[a-z][a-z0-9+.-]*://[^\s/:@]+:[^\s/@]+@', '<redacted-uri>@')
    $safe = [regex]::Replace($safe, '(?im)((?:password|passwd|token|cookie|secret|credential|username|app[-_.]?secret|secret[-_.]?key)\s*[=:]\s*)[^\s,;}]+', '${1}<redacted>')
    return $safe
}

function Get-TestSensitiveValues($Targets) {
    $values = [System.Collections.Generic.List[string]]::new()
    foreach ($target in @($Targets)) {
        foreach ($line in Get-Content -LiteralPath ([string]$target.absoluteFile) -Encoding utf8) {
            if ($line -match '(?i)^\s*(?:password|passwd|token|cookie|secret|credential|username|app[-_.]?secret|secret[-_.]?key)\s*:\s*(.+)$') {
                $value = $matches[1].Trim().Trim('"', "'")
                if ($value -and $value -notmatch '^\$\{') { $values.Add($value) }
            }
        }
    }
    return @($values)
}

function Get-TestScenarioSelection([string]$ChangeRoot, [string]$DerivedPath, [string[]]$ScenarioIds) {
    if (@($ScenarioIds).Count -eq 0 -or @($ScenarioIds | Where-Object { [string]::IsNullOrWhiteSpace($_) }).Count -gt 0) { throw 'SCENARIO_SELECTION_EMPTY' }
    $ids = @($ScenarioIds | Sort-Object -Unique)
    if ($ids.Count -ne $ScenarioIds.Count) { throw 'SCENARIO_SELECTION_DUPLICATE' }
    $root = [IO.Path]::GetFullPath($ChangeRoot).TrimEnd('\','/')
    $path = [IO.Path]::GetFullPath((Join-Path $root $DerivedPath))
    if (-not $path.StartsWith($root + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)) { throw 'SCENARIO_SELECTION_PATH' }
    $contract = Get-Content -LiteralPath $path -Raw -Encoding utf8 | ConvertFrom-Json
    if ($contract.kind -ne 'flow-test-cases-derived') { throw 'SCENARIO_SELECTION_CONTRACT' }
    $source = [IO.Path]::GetFullPath((Join-Path $root ([string]$contract.source.path)))
    if (-not $source.StartsWith($root + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)) { throw 'SCENARIO_SELECTION_PATH' }
    if ((Get-FileHash -LiteralPath $source -Algorithm SHA256).Hash.ToLowerInvariant() -ne [string]$contract.source.sha256) { throw 'SCENARIO_SELECTION_SOURCE_DRIFT' }
    $selected = [System.Collections.Generic.List[object]]::new()
    foreach ($id in $ids) {
        $filter = @($contract.runnerFilters | Where-Object { $_.id -eq $id })
        $method = @($contract.failureObservability | Where-Object { $_.id -eq $id })
        if ($filter.Count -ne 1 -or $method.Count -ne 1 -or [string]::IsNullOrWhiteSpace([string]$filter[0].filter)) { throw "SCENARIO_SELECTION_UNKNOWN: $id" }
        $expected = [string]$method[0].testClass + '#' + [string]$method[0].testMethod
        if ([string]$filter[0].filter -ne $expected -or $expected -match '[*?]') { throw "SCENARIO_SELECTION_FILTER: $id" }
        $selected.Add([ordered]@{ id=$id; filter=$expected; testClass=[string]$method[0].testClass; testMethod=[string]$method[0].testMethod })
    }
    return [ordered]@{ schemaVersion=1; fullSuite=$false; scenarioIds=$ids; methods=@($selected); expectedMethodCount=$selected.Count; filter=(@($selected | ForEach-Object { $_.filter }) -join ','); sourceSha256=[string]$contract.source.sha256 }
}

function Get-SelectedTestResults($Selection, [string]$ReportDirectory, [switch]$AllowNonPassing) {
    $cases = [System.Collections.Generic.List[object]]::new()
    $classes = @($Selection.methods | ForEach-Object { $_.testClass } | Sort-Object -Unique)
    foreach ($class in $classes) {
        $path = Join-Path $ReportDirectory "TEST-$class.xml"
        if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "SCENARIO_REPORT_MISSING: $class" }
        [xml]$xml = Get-Content -LiteralPath $path -Raw -Encoding utf8
        foreach ($case in @($xml.SelectNodes('/testsuite/testcase'))) { $cases.Add($case) }
    }
    $passed = 0; $failed = 0; $skipped = 0
    foreach ($case in $cases) {
        $belongs = @($Selection.methods | Where-Object { $case.classname -eq $_.testClass -and ($case.name -eq $_.testMethod -or $case.name.StartsWith($_.testMethod + '(') -or $case.name.StartsWith($_.testMethod + '[')) })
        if ($belongs.Count -ne 1) { throw 'SCENARIO_REPORT_OUTSIDE_SELECTION' }
    }
    foreach ($method in @($Selection.methods)) {
        $matches = @($cases | Where-Object { $_.classname -eq $method.testClass -and ($_.name -eq $method.testMethod -or $_.name.StartsWith($method.testMethod + '(') -or $_.name.StartsWith($method.testMethod + '[')) })
        if ($matches.Count -eq 0) { throw "SCENARIO_ZERO_MATCH: $($method.id)" }
        foreach ($case in $matches) {
            if ($null -ne $case.failure -or $null -ne $case.error) { $failed++ }
            elseif ($null -ne $case.skipped) { $skipped++ }
            else { $passed++ }
        }
    }
    if (-not $AllowNonPassing -and ($failed -gt 0 -or $skipped -gt 0)) { throw "SCENARIO_NOT_PASSED: failed=$failed skipped=$skipped" }
    return [ordered]@{ passed=$passed; failed=$failed; skipped=$skipped; expectedMethodCount=$Selection.expectedMethodCount; fullSuite=$false }
}
