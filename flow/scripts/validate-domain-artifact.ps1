param(
    [Parameter(Mandatory = $true)]
    [string]$DomainModelPath
)

$ErrorActionPreference = 'Stop'

function New-UtfString([int[]]$CodePoints) { return -join ($CodePoints | ForEach-Object { [char]$_ }) }
function Add-Issue([string]$Message) { $script:errors += $Message }
function Get-Table([string[]]$Lines, [string]$Column) {
    $header = -1; $needle = "| $Column |"
    $inFence = $false
    for ($i = 0; $i -lt $Lines.Count; $i++) {
        $candidate = $Lines[$i].Trim()
        if ($candidate -match '^```') { $inFence = -not $inFence; continue }
        if (-not $inFence -and $candidate.Contains($needle)) { $header = $i; break }
    }
    if ($header -lt 0 -or $header + 1 -ge $Lines.Count) { return $null }
    $rows = @()
    for ($i = $header + 2; $i -lt $Lines.Count; $i++) {
        $line = $Lines[$i].Trim()
        if (-not $line.StartsWith('|')) { break }
        $rows += $line
    }
    return $rows
}
function Get-TableAfterHeading([string[]]$Lines, [string]$Heading, [string]$Column) {
    $start = -1
    for ($i = 0; $i -lt $Lines.Count; $i++) { if ($Lines[$i].Trim() -eq "## $Heading") { $start = $i; break } }
    if ($start -lt 0) { return $null }
    $header = -1; $needle = "| $Column |"; $inFence = $false
    for ($i = $start + 1; $i -lt $Lines.Count; $i++) {
        $candidate = $Lines[$i].Trim()
        if ($candidate -match '^```') { $inFence = -not $inFence; continue }
        if (-not $inFence -and $candidate.Contains($needle)) { $header = $i; break }
    }
    if ($header -lt 0 -or $header + 1 -ge $Lines.Count) { return $null }
    $rows = @()
    for ($i = $header + 2; $i -lt $Lines.Count; $i++) { $line = $Lines[$i].Trim(); if (-not $line.StartsWith('|')) { break }; $rows += $line }
    return $rows
}
function Split-Ids([string]$Value) { return @($Value -split '[,;\s]+' | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }) }
function Get-MarkdownTableDataRows([string[]]$Lines) {
    $rows = @()
    $inTable = $false
    $inFence = $false
    foreach ($rawLine in $Lines) {
        $line = $rawLine.Trim()
        if ($line -match '^```') { $inFence = -not $inFence; $inTable = $false; continue }
        if ($inFence) { continue }
        if (-not $line.StartsWith('|')) { $inTable = $false; continue }
        if ($line -match '^\|[\s|:-]+\|$') { $inTable = $true; continue }
        if ($inTable) { $rows += $line }
    }
    return $rows
}
function Test-Incomplete([string]$Value) {
    if ([string]::IsNullOrWhiteSpace($Value)) { return $true }
    $tokens = @('TODO', 'TBD', 'unknown', (New-UtfString @(24453,22635,20889)), (New-UtfString @(26410,30693)), (New-UtfString @(24453,34917,20805)))
    if ($Value -match '(?i)\b(todo|tbd|unknown)\b' -or $Value -match '\{[^}]*\}') { return $true }
    foreach ($token in $tokens) { if ($Value.IndexOf($token, [StringComparison]::OrdinalIgnoreCase) -ge 0) { return $true } }
    return $false
}
function Test-SelfEvidence([string]$Value) {
    if ($Value -match '(?i)overview[\s-]*design|current[\s-]*plan|implementation[\s-]*(assumption|idea|design)|agent[\s-]*(inference|推断)') { return $true }
    $tokens = @((New-UtfString @(27010,35201,35774,35745)), (New-UtfString @(24403,21069,26041,26696)),
        (New-UtfString @(23454,29616,35774,24819)), ('agent ' + (New-UtfString @(25512,26029))))
    foreach ($token in $tokens) { if ($Value.IndexOf($token, [StringComparison]::OrdinalIgnoreCase) -ge 0) { return $true } }
    return $false
}

if (-not (Test-Path -LiteralPath $DomainModelPath -PathType Leaf)) {
    Write-Output "[ERROR] DV.1: domain model not found: $DomainModelPath"; Write-Output '[DOMAIN_ARTIFACT_RESULT] ERROR'; exit 1
}

$lines = @(Get-Content -LiteralPath $DomainModelPath -Encoding utf8)
$errors = @()
$requiredSections = @(
    (New-UtfString @(21464,26356,20915,31574,28857)), (New-UtfString @(39046,22495,23454,20307,19982,20851,31995)),
    (New-UtfString @(39046,22495,20107,23454)), (New-UtfString @(34920,19982,23383,27573,35821,20041)),
    (New-UtfString @(36523,20221,12289,21807,19968,24615,12289,32858,21512,19982,35206,30422,35268,21017)),
    (New-UtfString @(29366,24577,19982,36716,25442)), (New-UtfString @(36755,20837,12289,23384,20648,19982,36755,20986,36716,25442)),
    (New-UtfString @(27491,20363,12289,36793,30028,19982,21453,20363)), (New-UtfString @(35777,25454,32034,24341)),
    (New-UtfString @(20914,31361,19982,26410,20915,38382,39064))
)
foreach ($section in $requiredSections) {
    if (-not (@($lines | Where-Object { $_.Trim() -eq "## $section" }).Count -eq 1)) { Add-Issue "DV.1: missing or duplicate required section $section" }
}
if (-not (@($lines | Where-Object { $_.Trim().StartsWith('## DOMAIN_DRAFT') }).Count -eq 1)) { Add-Issue 'DV.1: missing or duplicate DOMAIN_DRAFT checkpoint section' }
$tableDataRows = Get-MarkdownTableDataRows $lines
foreach ($line in $tableDataRows) { if (Test-Incomplete $line) { Add-Issue 'DV.2: incomplete placeholder, TODO, TBD, or unknown table field is forbidden'; break } }

$decisions = Get-Table $lines 'Decision ID'; $facts = Get-Table $lines 'Fact ID'; $evidence = Get-Table $lines 'Evidence ID'
if ($null -eq $decisions) { Add-Issue 'DV.1: missing Decision ID table' }
if ($null -eq $facts) { Add-Issue 'DV.2: missing Fact ID table' }
if ($null -eq $evidence) { Add-Issue 'DV.3: missing Evidence ID index' }
if ($null -eq $decisions) { $decisions = @() }
if ($null -eq $facts) { $facts = @() }
if ($null -eq $evidence) { $evidence = @() }

$decisionIds = @{}; foreach ($raw in @($decisions)) {
    $row = @($raw.Trim('|').Split('|') | ForEach-Object { $_.Trim() })
    if ($row.Count -lt 5 -or $row[0] -notmatch '^DP-[0-9]+$') { Add-Issue 'DV.1: invalid Decision ID row'; continue }
    if ($decisionIds.ContainsKey($row[0])) { Add-Issue "DV.1: duplicate Decision ID $($row[0])" }
    $decisionIds[$row[0]] = $row
    if (Test-Incomplete $row[2]) { Add-Issue "DV.1: Decision ID $($row[0]) lacks required Fact ID" }
    if ($row[4] -ne 'resolved') { Add-Issue "DV.8: Decision ID $($row[0]) is not resolved" }
}

$factIds = @{}; foreach ($raw in @($facts)) {
    $row = @($raw.Trim('|').Split('|') | ForEach-Object { $_.Trim() })
    if ($row.Count -lt 7 -or $row[0] -notmatch '^DF-[0-9]+$') { Add-Issue 'DV.2: invalid Fact ID row'; continue }
    if ($factIds.ContainsKey($row[0])) { Add-Issue "DV.2: duplicate Fact ID $($row[0])" }
    $factIds[$row[0]] = $row
    foreach ($i in @(2,3,4,5,6)) { if (Test-Incomplete $row[$i]) { Add-Issue "DV.2: Fact ID $($row[0]) has incomplete required field" } }
    foreach ($id in (Split-Ids $row[6])) { if (-not $decisionIds.ContainsKey($id)) { Add-Issue "DV.1: Fact ID $($row[0]) references unknown Decision ID $id" } }
    foreach ($id in (Split-Ids $row[5])) { if ($id -notmatch '^EV-[0-9]+$') { Add-Issue "DV.3: Fact ID $($row[0]) evidence must only contain EV-* IDs" } }
}
foreach ($pair in $decisionIds.GetEnumerator()) {
    foreach ($factId in (Split-Ids $pair.Value[2])) {
        if (-not $factIds.ContainsKey($factId)) { Add-Issue "DV.1: Decision ID $($pair.Key) requires unknown Fact ID $factId"; continue }
        if (-not ((Split-Ids $factIds[$factId][6]) -contains $pair.Key)) { Add-Issue "DV.1: Decision ID $($pair.Key) requires Fact ID $factId but the Fact does not point back to the Decision" }
    }
}
foreach ($pair in $factIds.GetEnumerator()) {
    foreach ($decisionId in (Split-Ids $pair.Value[6])) {
        if ($decisionIds.ContainsKey($decisionId) -and -not ((Split-Ids $decisionIds[$decisionId][2]) -contains $pair.Key)) {
            Add-Issue "DV.1: Fact ID $($pair.Key) points to Decision ID $decisionId but the Decision does not require the Fact"
        }
    }
}

$evidenceIds = @{}; foreach ($raw in @($evidence)) {
    $row = @($raw.Trim('|').Split('|') | ForEach-Object { $_.Trim() })
    if ($row.Count -lt 6 -or $row[0] -notmatch '^EV-[0-9]+$') { Add-Issue 'DV.3: invalid Evidence ID row'; continue }
    if ($evidenceIds.ContainsKey($row[0])) { Add-Issue "DV.3: duplicate Evidence ID $($row[0])" }
    $evidenceIds[$row[0]] = $row
    if ($row[1] -notin @('E1','E2','E3','E4')) { Add-Issue "DV.3: Evidence ID $($row[0]) has invalid level" }
    $invalidEvidenceSource = (Test-Incomplete $row[2]) -or (Test-Incomplete $row[3]) -or (Test-SelfEvidence $row[2]) -or (Test-SelfEvidence $row[3])
    if ($invalidEvidenceSource) { Add-Issue "DV.3: Evidence ID $($row[0]) has invalid source or locator" }
    foreach ($factId in (Split-Ids $row[4])) { if (-not $factIds.ContainsKey($factId)) { Add-Issue "DV.3: Evidence ID $($row[0]) supports unknown Fact ID $factId" } }
    if ($row[1] -eq 'E4' -and -not [string]::IsNullOrWhiteSpace($row[4]) -and $row[4] -ne 'none') { Add-Issue "DV.3: E4 Evidence ID $($row[0]) may only appear in unresolved questions" }
}
$unresolvedHeading = New-UtfString @(20914,31361,19982,26410,20915,38382,39064)
$unresolvedRows = Get-TableAfterHeading $lines $unresolvedHeading 'Evidence ID'
foreach ($pair in $evidenceIds.GetEnumerator()) {
    $inOpenUnresolvedQuestion = @($unresolvedRows | Where-Object {
        $cells = @($_.Trim('|').Split('|') | ForEach-Object { $_.Trim() })
        $cells.Count -ge 6 -and (Split-Ids $cells[4]) -contains $pair.Key -and $cells[5] -in @('open', 'blocked')
    }).Count -gt 0
    if ($pair.Value[1] -eq 'E4' -and -not $inOpenUnresolvedQuestion) {
        Add-Issue "DV.3: E4 Evidence ID $($pair.Key) is not recorded in an unresolved question"
    }
}
foreach ($pair in $factIds.GetEnumerator()) {
    $levels = @()
    foreach ($evidenceId in (Split-Ids $pair.Value[5])) {
        if (-not $evidenceIds.ContainsKey($evidenceId)) { Add-Issue "DV.3: Fact ID $($pair.Key) references unknown Evidence ID $evidenceId"; continue }
        $level = $evidenceIds[$evidenceId][1]; $levels += $level
        if ($level -eq 'E4') { Add-Issue "DV.3: Fact ID $($pair.Key) cannot use E4 evidence" }
    }
    if (@($levels | Where-Object { $_ -in @('E1','E2') }).Count -eq 0) { Add-Issue "DV.3: Fact ID $($pair.Key) lacks E1/E2 evidence" }
}

foreach ($line in $lines) {
    $cells = @($line.Trim().Trim('|').Split('|') | ForEach-Object { $_.Trim() })
    if ($cells.Count -ge 6 -and $cells[-1] -in @('open','blocked')) { Add-Issue "DV.6: unresolved conflict affects $($cells[2])" }
}
foreach ($message in $errors) { Write-Output "[ERROR] $message" }
if ($errors.Count -gt 0) { Write-Output '[DOMAIN_ARTIFACT_RESULT] ERROR'; exit 1 }
$hash = (Get-FileHash -LiteralPath $DomainModelPath -Algorithm SHA256).Hash.ToLowerInvariant()
Write-Output '[PASS] DV.1-DV.3,DV.6,DV.8: deterministic domain artifact checks passed'
Write-Output '[DOMAIN_ARTIFACT_RESULT] PASS'; Write-Output "domain_model_sha256: $hash"
