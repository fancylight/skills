[CmdletBinding()]
param(
  [string]$HarnessRoot = '',
  [string]$ReportPath = '',
  [string]$RuntimeExecutable = 'powershell.exe',
  [string]$ArtifactRoot = ''
)

$ErrorActionPreference = 'Stop'
$scriptDirectory = Split-Path -Parent $MyInvocation.MyCommand.Path
if ([string]::IsNullOrWhiteSpace($HarnessRoot)) { $HarnessRoot = (Resolve-Path (Join-Path $scriptDirectory '..')).Path }
$HarnessRoot = (Resolve-Path -LiteralPath $HarnessRoot).Path
if ([string]::IsNullOrWhiteSpace($ReportPath)) { $ReportPath = Join-Path $scriptDirectory 'harness-self-test.json' }
if ([string]::IsNullOrWhiteSpace($ArtifactRoot)) { $ArtifactRoot = Join-Path $scriptDirectory 'artifacts' }
$runner = Join-Path $HarnessRoot 'scripts\system-test.ps1'
$adapter = Join-Path $HarnessRoot 'self-test\harness-self-test-adapter.ps1'
$certifier = Join-Path $HarnessRoot 'scripts\harness-certification.ps1'
foreach ($path in @($runner,$adapter,$certifier)) {
  if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "Harness self-test dependency missing: $path" }
}
if (-not (Get-Command $RuntimeExecutable -ErrorAction SilentlyContinue)) { throw "Harness self-test runtime not found: $RuntimeExecutable" }

function Write-Utf8([string]$Path, [string]$Value) {
  $directory = Split-Path -Parent $Path
  if (-not (Test-Path -LiteralPath $directory)) { [void](New-Item -ItemType Directory -Path $directory -Force) }
  [IO.File]::WriteAllText($Path, $Value, [Text.UTF8Encoding]::new($false))
}

function Copy-ScenarioArtifacts([string]$Change, [string]$ScenarioId, [string]$RunnerOutputPath, [string]$ResultPath) {
  $destination = Join-Path $ArtifactRoot $ScenarioId
  if (Test-Path -LiteralPath $destination) { Remove-Item -LiteralPath $destination -Recurse -Force }
  [void](New-Item -ItemType Directory -Path $destination -Force)
  Copy-Item -LiteralPath $RunnerOutputPath -Destination (Join-Path $destination 'runner-output.log') -Force
  Copy-Item -LiteralPath $ResultPath -Destination (Join-Path $destination 'structured-result.json') -Force
  $evidence = Join-Path $HarnessRoot "changes\$Change\evidence"
  if (Test-Path -LiteralPath $evidence) { Copy-Item -LiteralPath $evidence -Destination (Join-Path $destination 'evidence') -Recurse -Force }
  $runtime = Join-Path $HarnessRoot ".runtime\$Change"
  if (Test-Path -LiteralPath $runtime) { Copy-Item -LiteralPath $runtime -Destination (Join-Path $destination 'runtime') -Recurse -Force }
  return $destination
}

function Remove-ScenarioRuntime([string]$Change) {
  foreach ($path in @((Join-Path $HarnessRoot "changes\$Change"),(Join-Path $HarnessRoot ".runtime\$Change"))) {
    if (Test-Path -LiteralPath $path) { Remove-Item -LiteralPath $path -Recurse -Force }
  }
}

$definitions = @(
  @{ id='normal-run'; exitCode=0; status='PASS'; phase='RUNNER_COMPLETED'; category='NONE'; cleanupSucceeded=$true; retained=$false },
  @{ id='sut-startup-failure'; exitCode=1; status='FAIL'; phase='RUNNER_FAILED'; category='TEST_HARNESS'; cleanupSucceeded=$true; retained=$false },
  @{ id='mysql-unavailable'; exitCode=1; status='BLOCKED'; phase='RUNNER_BLOCKED'; category='CONFIG_INFRA'; cleanupSucceeded=$true; retained=$false },
  @{ id='postgres-unavailable'; exitCode=1; status='BLOCKED'; phase='RUNNER_BLOCKED'; category='CONFIG_INFRA'; cleanupSucceeded=$true; retained=$false },
  @{ id='redis-unavailable'; exitCode=1; status='BLOCKED'; phase='RUNNER_BLOCKED'; category='CONFIG_INFRA'; cleanupSucceeded=$true; retained=$false },
  @{ id='wiremock-unmatched'; exitCode=1; status='FAIL'; phase='RUNNER_FAILED'; category='TEST_HARNESS'; cleanupSucceeded=$true; retained=$false },
  @{ id='seed-failure'; exitCode=1; status='FAIL'; phase='RUNNER_FAILED'; category='FIXTURE_ASSERTION'; cleanupSucceeded=$true; retained=$false },
  @{ id='cleanup-failure'; exitCode=1; status='FAIL'; phase='RUNNER_FAILED'; category='TEST_HARNESS'; cleanupSucceeded=$false; retained=$true },
  @{ id='maven-arguments'; exitCode=0; status='PASS'; phase='RUNNER_COMPLETED'; category='NONE'; cleanupSucceeded=$true; retained=$false },
  @{ id='maven-execution-failure'; exitCode=1; status='FAIL'; phase='RUNNER_FAILED'; category='TEST_HARNESS'; cleanupSucceeded=$true; retained=$false },
  @{ id='surefire-missing'; exitCode=1; status='FAIL'; phase='RUNNER_FAILED'; category='TEST_HARNESS'; cleanupSucceeded=$true; retained=$false },
  @{ id='utf8-log'; exitCode=0; status='PASS'; phase='RUNNER_COMPLETED'; category='NONE'; cleanupSucceeded=$true; retained=$false },
  @{ id='interrupted-run'; exitCode=1; status='FAIL'; phase='RUNNER_FAILED'; category='TEST_HARNESS'; cleanupSucceeded=$true; retained=$false },
  @{ id='evidence-missing'; exitCode=1; status='FAIL'; phase='RUNNER_FAILED'; category='TEST_HARNESS'; cleanupSucceeded=$true; retained=$false }
)

if (Test-Path -LiteralPath $ArtifactRoot) { Remove-Item -LiteralPath $ArtifactRoot -Recurse -Force }
[void](New-Item -ItemType Directory -Path $ArtifactRoot -Force)
Write-Utf8 (Join-Path $HarnessRoot '.env.local') "HARNESS_SELF_TEST=true`n"
$revision = (& $certifier revision -HarnessRoot $HarnessRoot | Select-Object -Last 1).Trim()
$scenarios = @()

foreach ($definition in $definitions) {
  $change = 'harness-self-test-' + $definition.id
  Remove-ScenarioRuntime $change
  $changeRoot = Join-Path $HarnessRoot "changes\$change"
  [void](New-Item -ItemType Directory -Path $changeRoot -Force)
  $manifest = [ordered]@{
    configuration=[ordered]@{ source='.env.local'; ownership='harness'; requiredEndpoints=@('sut'); probes=[ordered]@{ sut='GET /health' } }
    requiredEnvBySuite=[ordered]@{ api=@() }
    defaultSuites=@('api')
    apiTestFilter='*Test'
    composeProfiles=@()
    data=[ordered]@{ seeds=@('fixtures/seed.sql'); cleanups=@('fixtures/cleanup.sql') }
    requiredEvidence=@(".runtime/$change/raw/runner.json")
  }
  Write-Utf8 (Join-Path $changeRoot 'manifest.yaml') ($manifest | ConvertTo-Json -Depth 8)
  $working = Join-Path $ArtifactRoot ('working-' + $definition.id)
  [void](New-Item -ItemType Directory -Path $working -Force)
  $structuredResult = Join-Path $working 'structured-result.json'
  $runnerOutput = Join-Path $working 'runner-output.log'
  $arguments = @(
    '-NoProfile','-ExecutionPolicy','Bypass','-File',$runner,'run','-Change',$change,'-Suite','api',
    '-ExecutionMode','standalone','-EnvFile','.env.local','-HarnessSelfTest','-HarnessAdapterPath',$adapter,
    '-HarnessSelfTestScenario',$definition.id,'-StructuredResultPath',$structuredResult
  )
  $oldPreference = $ErrorActionPreference
  $ErrorActionPreference = 'Continue'
  try {
    $output = @(& $RuntimeExecutable @arguments 2>&1)
    $observedExitCode = $LASTEXITCODE
  } finally {
    $ErrorActionPreference = $oldPreference
  }
  Write-Utf8 $runnerOutput (($output | ForEach-Object { [string]$_ }) -join "`r`n")

  $errors = [System.Collections.Generic.List[string]]::new()
  if (-not (Test-Path -LiteralPath $structuredResult -PathType Leaf)) {
    $errors.Add('runner did not produce structured result')
    $observed = [pscustomobject]@{ status='MISSING'; phase='MISSING'; classification='MISSING'; cleanup=[pscustomobject]@{ succeeded=$false; retainedState=$false } }
  } else {
    try { $observed = Get-Content -LiteralPath $structuredResult -Raw -Encoding UTF8 | ConvertFrom-Json }
    catch { $errors.Add('runner structured result is invalid JSON'); $observed = [pscustomobject]@{ status='INVALID'; phase='INVALID'; classification='INVALID'; cleanup=[pscustomobject]@{ succeeded=$false; retainedState=$false } } }
  }
  if ($observedExitCode -ne $definition.exitCode) { $errors.Add("exit code $observedExitCode did not equal $($definition.exitCode)") }
  if ($observed.status -ne $definition.status) { $errors.Add("status $($observed.status) did not equal $($definition.status)") }
  if ($observed.phase -ne $definition.phase) { $errors.Add("phase $($observed.phase) did not equal $($definition.phase)") }
  if ($observed.classification -ne $definition.category) { $errors.Add("classification $($observed.classification) did not equal $($definition.category)") }
  if ([bool]$observed.cleanup.succeeded -ne [bool]$definition.cleanupSucceeded) { $errors.Add('cleanup success state differs') }
  if ([bool]$observed.cleanup.retainedState -ne [bool]$definition.retained) { $errors.Add('retention state differs') }
  if (($output -join "`n") -notmatch '\[SYSTEM_TEST_RESULT\]') { $errors.Add('runner completion marker is missing') }

  if (Test-Path -LiteralPath $structuredResult) {
    $scenarioArtifact = Copy-ScenarioArtifacts $change $definition.id $runnerOutput $structuredResult
    $rawEvidenceFile = Join-Path $scenarioArtifact 'evidence\current\index.md'
    $rawEvidencePath = "self-test/artifacts/$($definition.id)/evidence/current/index.md"
    $runnerEvidencePath = "self-test/artifacts/$($definition.id)/runner-output.log"
    if (-not (Test-Path -LiteralPath $rawEvidenceFile -PathType Leaf)) { $errors.Add('raw evidence index is missing') }
  } else {
    $rawEvidencePath = ''
    $runnerEvidencePath = $runnerOutput
  }
  $scenarios += [ordered]@{
    id=$definition.id
    result=$(if ($errors.Count -eq 0) { 'PASS' } else { 'FAIL' })
    exitCode=$observedExitCode
    status=[string]$observed.status
    phase=[string]$observed.phase
    classification=[string]$observed.classification
    rawEvidencePath=$rawEvidencePath
    runnerOutputPath=$runnerEvidencePath
    cleanup=[ordered]@{ succeeded=[bool]$observed.cleanup.succeeded; retainedState=[bool]$observed.cleanup.retainedState }
    errors=@($errors)
  }
  Remove-ScenarioRuntime $change
  if (Test-Path -LiteralPath $working) { Remove-Item -LiteralPath $working -Recurse -Force }
}

$report = [ordered]@{
  schemaVersion=2
  result=$(if (@($scenarios | Where-Object { $_.result -ne 'PASS' }).Count -eq 0) { 'PASS' } else { 'FAIL' })
  harnessRevision=$revision
  runtimeExecutable=$RuntimeExecutable
  generatedAt=[DateTime]::UtcNow.ToString('o')
  scenarios=$scenarios
}
Write-Utf8 $ReportPath ($report | ConvertTo-Json -Depth 10)
Write-Output "[HARNESS_SELF_TEST] $($report.result)"
Write-Output "report: $ReportPath"
if ($report.result -ne 'PASS') { exit 1 }
