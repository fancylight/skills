[CmdletBinding()]
param(
  [Parameter(Mandatory=$true)] [string]$TestRoot,
  [Parameter(Mandatory=$true)] [string]$Change,
  [Parameter(Mandatory=$true)] [ValidateSet('PASS','FAIL','BLOCKED')] [string]$Status,
  [string[]]$Suites = @(),
  [string]$Message = '',
  [int]$Passed = 0,
  [int]$Failed = 0,
  [int]$Skipped = 0
)

$ErrorActionPreference = 'Stop'
$TestRoot = (Resolve-Path -LiteralPath $TestRoot).Path
$evidenceRoot = Join-Path $TestRoot "changes\$Change\evidence"
$current = Join-Path $evidenceRoot 'current'
$manifestPath = Join-Path $TestRoot "changes\$Change\manifest.yaml"
$reportDir = Join-Path $TestRoot 'backend-tests\target\surefire-reports'
$runtimeDir = Join-Path $TestRoot ".runtime\$Change"

function ConvertTo-SafeEvidenceText([string]$Text) {
  if ($null -eq $Text) { return '' }
  $safe = $Text -replace '(?i)((password|pwd|token|secret)\s*[=:]\s*)[^\s,;]+', '$1<redacted>'
  return $safe -replace '(?i)jdbc:[^\s"'']+', '<redacted-jdbc-url>'
}

function Copy-EvidenceFiles([string]$Source, [string]$Destination, [string]$Filter = '*') {
  New-Item -ItemType Directory -Force -Path $Destination | Out-Null
  if (-not (Test-Path -LiteralPath $Source)) { return @() }
  $files = @(Get-ChildItem -LiteralPath $Source -File -Filter $Filter -ErrorAction SilentlyContinue)
  foreach ($file in $files) { Copy-Item -LiteralPath $file.FullName -Destination (Join-Path $Destination $file.Name) -Force }
  return $files
}

function Get-TriageRule($Manifest, [string]$ClassName, [string]$MethodName) {
  if ($null -eq $Manifest -or $null -eq $Manifest.failureObservability) { return $null }
  foreach ($rule in @($Manifest.failureObservability)) {
    if ($rule.testClass -and $rule.testClass -ne $ClassName) { continue }
    if ($rule.testMethod -and $rule.testMethod -ne $MethodName) { continue }
    return $rule
  }
  return $null
}

function Get-JunitFailures($Manifest, [string]$Directory) {
  $items = [System.Collections.Generic.List[object]]::new()
  foreach ($report in @(Get-ChildItem -LiteralPath $Directory -Filter 'TEST-*.xml' -File -ErrorAction SilentlyContinue)) {
    try { [xml]$xml = Get-Content -LiteralPath $report.FullName -Raw -Encoding UTF8 } catch { continue }
    foreach ($testCase in @($xml.testsuite.testcase)) {
      $nodes = @($testCase.failure) + @($testCase.error) | Where-Object { $null -ne $_ }
      foreach ($node in $nodes) {
        $className = [string]$testCase.classname
        $methodName = [string]$testCase.name
        $rule = Get-TriageRule $Manifest $className $methodName
        $category = if ($rule -and $rule.category) { [string]$rule.category } else { 'UNDETERMINED' }
        if ($category -notin @('CONFIG_INFRA','TEST_HARNESS','DATA_SCHEMA_CONTRACT','SUT_BUSINESS','UNDETERMINED')) { $category = 'UNDETERMINED' }
        $certainty = if ($rule -and $rule.certainty -eq 'confirmed') { 'confirmed' } else { 'suspected' }
        $scenario = if ($rule -and $rule.scenarioId) { [string]$rule.scenarioId } else { 'unmapped' }
        $message = ConvertTo-SafeEvidenceText (([string]$node.message) + ' ' + ([string]$node.'#text'))
        $items.Add([pscustomobject]@{ scenario=$scenario; method="$className#$methodName"; category=$category; certainty=$certainty; evidence="junit/$($report.Name)"; message=$message })
      }
    }
  }
  return $items.ToArray()
}

New-Item -ItemType Directory -Force -Path $current | Out-Null
$junit = Copy-EvidenceFiles $reportDir (Join-Path $current 'junit') 'TEST-*.xml'
$logs = Copy-EvidenceFiles (Join-Path $runtimeDir 'logs') (Join-Path $current 'logs') '*'
$wiremock = Copy-EvidenceFiles (Join-Path $runtimeDir 'wiremock') (Join-Path $current 'wiremock') '*'
$db = Copy-EvidenceFiles (Join-Path $runtimeDir 'db') (Join-Path $current 'db') '*'
$manifest = if (Test-Path -LiteralPath $manifestPath) { Get-Content -LiteralPath $manifestPath -Raw -Encoding UTF8 | ConvertFrom-Json } else { $null }
$failures = if ($junit.Count -gt 0) { Get-JunitFailures $manifest $reportDir } else { @() }
$failureCount = @($failures).Count
$rawStatus = if ($junit.Count -gt 0) { 'available' } else { 'unavailable' }
$safeMessage = ConvertTo-SafeEvidenceText $Message
$failureRef = if ($Status -in @('FAIL','BLOCKED')) { 'failure-report.md' } else { 'none' }

$index = @(
  '# System Test Evidence Index',
  '',
  "- status: $Status",
  "- suites: $($Suites -join ',')",
  "- junit: $rawStatus",
  "- junit_reports: $($junit.Count)",
  "- log_files: $($logs.Count)",
  "- wiremock_files: $($wiremock.Count)",
  "- db_files: $($db.Count)",
  '- summary: ../summary.md',
  "- failure_report: $failureRef"
) -join "`n"
Set-Content -LiteralPath (Join-Path $current 'index.md') -Value $index -Encoding UTF8

if ($Status -in @('FAIL','BLOCKED')) {
  $rows = if ($failureCount -gt 0) {
    @($failures | ForEach-Object { "| $($_.scenario) | $($_.method) | $($_.category) | $($_.certainty) | $($_.evidence) | $(($_.message -replace '\|', '\\|')) |" })
  } else {
    @('| unmapped | unavailable | UNDETERMINED | suspected | none | Raw report was not produced; collect only read-only diagnostics. |')
  }
  $report = @(
    '# Integration Test Failure Triage',
    '',
    '- revisions and manifest hash: see ../summary.md',
    "- JUnit executed: $rawStatus",
    "- passed / failed / skipped: $Passed / $Failed / $Skipped",
    "- first runner error: $safeMessage",
    '',
    '## Failures',
    '',
    '| Scenario | Test method | Category | Certainty | First evidence | Summary |',
    '|---|---|---|---|---|---|'
  ) + $rows + @(
    '',
    '## Undetermined boundary',
    '',
    '- UNDETERMINED permits only read-only diagnostic evidence; do not guess a business defect or auto-modify code, configuration, or fixtures.',
    '- Only SUT_BUSINESS with confirmed certainty may seed a separate business Flow.',
    '- Do not rerun the current revision. Any repair or diagnostic improvement requires a new revision and implementation verify.'
  )
  Set-Content -LiteralPath (Join-Path $current 'failure-report.md') -Value ($report -join "`n") -Encoding UTF8
}

Write-Output '[TEST_EVIDENCE_INDEX] PASS'
Write-Output "path: $current"
Write-Output "junit: $rawStatus"
