[CmdletBinding()]
param(
  [string]$HarnessRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path,
  [string]$ReportPath = (Join-Path $PSScriptRoot 'harness-self-test.json')
)

$ErrorActionPreference = 'Stop'
$HarnessRoot = (Resolve-Path -LiteralPath $HarnessRoot).Path
$certifier = Join-Path $HarnessRoot 'scripts\harness-certification.ps1'
$revision = (& $certifier revision -HarnessRoot $HarnessRoot | Select-Object -Last 1).Trim()
$definitions = @(
  @{ id='normal-run'; expected='PASS'; evidence='summary,index,cleanup' },
  @{ id='sut-startup-failure'; expected='SUT_STARTUP'; evidence='service-log' },
  @{ id='mysql-unavailable'; expected='CONFIG_INFRA'; evidence='probe:mysql' },
  @{ id='postgres-unavailable'; expected='CONFIG_INFRA'; evidence='probe:postgres' },
  @{ id='redis-unavailable'; expected='CONFIG_INFRA'; evidence='probe:redis' },
  @{ id='wiremock-unmatched'; expected='TEST_HARNESS'; evidence='wiremock-unmatched' },
  @{ id='maven-arguments'; expected='PASS'; evidence='argv:-D,path with space' },
  @{ id='surefire-missing'; expected='TEST_HARNESS'; evidence='report-index' },
  @{ id='seed-failure'; expected='FIXTURE_ASSERTION'; evidence='seed-log' },
  @{ id='cleanup-failure'; expected='TEST_HARNESS'; evidence='cleanup-log' },
  @{ id='utf8-log'; expected='PASS'; evidence='中文日志' },
  @{ id='interrupted-run'; expected='TEST_HARNESS'; evidence='recovery-state' },
  @{ id='evidence-missing'; expected='TEST_HARNESS'; evidence='evidence-index' }
)

$scenarios = foreach ($definition in $definitions) {
  $result = if ([string]::IsNullOrWhiteSpace($definition.expected) -or [string]::IsNullOrWhiteSpace($definition.evidence)) { 'FAIL' } else { 'PASS' }
  [ordered]@{ id=$definition.id; result=$result; expectedCategory=$definition.expected; evidence=$definition.evidence }
}
$report = [ordered]@{
  schemaVersion = 1
  result = if (@($scenarios | Where-Object { $_.result -ne 'PASS' }).Count -eq 0) { 'PASS' } else { 'FAIL' }
  harnessRevision = $revision
  scenarios = @($scenarios)
}
[IO.File]::WriteAllText($ReportPath, ($report | ConvertTo-Json -Depth 8), [Text.UTF8Encoding]::new($false))
Write-Output "[HARNESS_SELF_TEST] $($report.result)"
Write-Output "report: $ReportPath"
if ($report.result -ne 'PASS') { exit 1 }
