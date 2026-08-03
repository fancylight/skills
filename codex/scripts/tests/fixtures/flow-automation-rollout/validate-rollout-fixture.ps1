$ErrorActionPreference = 'Stop'
$path = Join-Path $PSScriptRoot 'cases.json'
$cases = Get-Content -LiteralPath $path -Raw -Encoding UTF8 | ConvertFrom-Json
if ($cases.schemaVersion -ne 2) { throw 'unsupported rollout fixture schema' }
if (@($cases.batchB).Count -ne 11) { throw 'incident replay matrix must contain 11 cases' }
if (@($cases.batchC).Count -ne 5) { throw 'forward matrix must contain 5 cases' }
if (@($cases.batchD).Count -ne 3) { throw 'shadow matrix must contain 3 cases' }
if (@($cases.batchE).Count -ne 7) { throw 'goal fault matrix must contain 7 cases' }
foreach ($batch in @($cases.batchB, $cases.batchC, $cases.batchD, $cases.batchE)) {
  $ids = @($batch | ForEach-Object { $_.id })
  if (@($ids | Sort-Object -Unique).Count -ne $ids.Count) { throw 'fixture IDs must be unique within each batch' }
}
$repoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSScriptRoot))))
function Get-Hash([string]$FilePath) { return (Get-FileHash -LiteralPath $FilePath -Algorithm SHA256).Hash.ToLowerInvariant() }
function Assert-Tracked([string]$FilePath) {
  $relative = [IO.Path]::GetFullPath($FilePath).Substring([IO.Path]::GetFullPath($repoRoot).TrimEnd('\').Length + 1).Replace('\','/')
  & git -C $repoRoot ls-files --error-unmatch -- $relative 2>$null | Out-Null
  if ($LASTEXITCODE -ne 0) { throw "execution evidence is not Git tracked: $relative" }
}
foreach ($batch in @($cases.batchB, $cases.batchC, $cases.batchD, $cases.batchE)) {
  foreach ($case in @($batch)) {
    if ([string]::IsNullOrWhiteSpace([string]$case.executionEvidence)) { throw "execution evidence is required: $($case.id)" }
    $evidencePath = Join-Path $repoRoot ([string]$case.executionEvidence)
    if (-not (Test-Path -LiteralPath $evidencePath -PathType Leaf)) { throw "execution evidence is missing: $($case.id)" }
    Assert-Tracked $evidencePath
  }
}
foreach ($property in $cases.batchA.PSObject.Properties) {
  $testPath = Join-Path $repoRoot $property.Value
  if (-not (Test-Path -LiteralPath $testPath -PathType Leaf)) { throw "missing deterministic test: $($property.Value)" }
}
$gates = Get-Content -LiteralPath (Join-Path $repoRoot 'docs\case-studies\evidence\flow-automation-wp7\environment-gates.json') -Raw -Encoding UTF8 | ConvertFrom-Json
if ($gates.rolloutResult -ne 'BLOCKED_FOR_CONTROLLED_ROLLOUT' -or $gates.realForwardRunner.runnerExecuted -or $gates.powerShell7.available) { throw 'environment gate report does not preserve the real rollout blockers' }
if (-not $gates.controlledHarnessForward.revalidationRequired -or $gates.controlledHarnessForward.sourceRevisionStatus -ne 'STALE_REQUIRES_REVALIDATION') { throw 'WP7 must mark the previous harness revision as requiring revalidation' }
$goalEvidence = Get-Content -LiteralPath (Join-Path $repoRoot 'docs\case-studies\evidence\flow-automation-wp7\goal-faults.json') -Raw -Encoding UTF8 | ConvertFrom-Json
if ($goalEvidence.result -ne 'PASS' -or @($goalEvidence.observations).Count -lt 9) { throw 'isolated goal fault execution evidence is incomplete' }
$shadowEvidence = Get-Content -LiteralPath (Join-Path $repoRoot 'docs\case-studies\evidence\flow-automation-wp7\shadow\report.json') -Raw -Encoding UTF8 | ConvertFrom-Json
if ($shadowEvidence.result -ne 'PASS' -or $shadowEvidence.observationCount -ne 3) { throw 'real shadow observation evidence is incomplete' }
$evidenceRoot = Join-Path $repoRoot 'docs\case-studies\evidence\flow-automation-wp7'
$deterministic = Get-Content -LiteralPath (Join-Path $evidenceRoot 'deterministic\report.json') -Raw -Encoding UTF8 | ConvertFrom-Json
foreach ($test in @($deterministic.tests)) {
  $logPath = Join-Path (Join-Path $evidenceRoot 'deterministic') ([string]$test.log)
  if (-not (Test-Path -LiteralPath $logPath -PathType Leaf) -or (Get-Hash $logPath) -ne $test.logHash) { throw "deterministic log is missing or stale: $($test.id)" }
  Assert-Tracked $logPath
}
$harnessRoot = Join-Path $evidenceRoot 'harness'
$certification = Get-Content -LiteralPath (Join-Path $harnessRoot 'self-test\certification.json') -Raw -Encoding UTF8 | ConvertFrom-Json
$selfTestReport = Join-Path $harnessRoot ([string]$certification.selfTestReportPath)
if ((Get-Hash $selfTestReport) -ne $certification.selfTestReportHash) { throw 'recorded harness self-test report hash mismatch' }
foreach ($item in @($certification.scenarioEvidence)) {
  $itemPath = Join-Path $harnessRoot ([string]$item.path)
  if (-not (Test-Path -LiteralPath $itemPath -PathType Leaf) -or (Get-Hash $itemPath) -ne $item.sha256) { throw "recorded harness evidence is missing or stale: $($item.path)" }
  Assert-Tracked $itemPath
}
if ([string]::IsNullOrWhiteSpace([string]$cases.rollback)) { throw 'rollback description is required' }
$raw = Get-Content -LiteralPath $path -Raw -Encoding UTF8
if ($raw -match '(?i)([A-Z]:\\|/Users/|[A-Z]{2,}-\d{4,}|"(?:change|service|project)Name"\s*:)') { throw 'rollout fixture leaked a real locator or case identifier' }
$evidenceRaw = Get-ChildItem -LiteralPath $evidenceRoot -File -Recurse | ForEach-Object { Get-Content -LiteralPath $_.FullName -Raw -Encoding UTF8 }
if (($evidenceRaw -join "`n") -match '(?i)[A-Z]:\\Users\\[^\\]+\\AppData\\Local\\Temp') { throw 'rollout evidence leaked an absolute temporary path' }
Write-Output 'flow automation rollout fixture validated'
