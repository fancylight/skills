[CmdletBinding()]
param(
  [Parameter(Position=0, Mandatory=$true)]
  [ValidateSet('revision','manifest','verify','certify')]
  [string]$Command,
  [string]$HarnessRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path,
  [string]$CertificationPath = '',
  [string]$SelfTestReport = '',
  [string]$HarnessVersion = '1'
)

$ErrorActionPreference = 'Stop'
$HarnessRoot = (Resolve-Path -LiteralPath $HarnessRoot).Path
if ([string]::IsNullOrWhiteSpace($CertificationPath)) { $CertificationPath = Join-Path $HarnessRoot 'self-test\harness-certification.json' }
$requiredScenarios = @('normal-run','sut-startup-failure','mysql-unavailable','postgres-unavailable','redis-unavailable','wiremock-unmatched','seed-failure','cleanup-failure','maven-arguments','maven-execution-failure','surefire-missing','utf8-log','interrupted-run','evidence-missing')
$scenarioExpectations = @{
  'normal-run'=@{ exitCode=0; status='PASS'; phase='RUNNER_COMPLETED'; classification='NONE'; cleanupSucceeded=$true; retainedState=$false }
  'sut-startup-failure'=@{ exitCode=1; status='FAIL'; phase='RUNNER_FAILED'; classification='TEST_HARNESS'; cleanupSucceeded=$true; retainedState=$false }
  'mysql-unavailable'=@{ exitCode=1; status='BLOCKED'; phase='RUNNER_BLOCKED'; classification='CONFIG_INFRA'; cleanupSucceeded=$true; retainedState=$false }
  'postgres-unavailable'=@{ exitCode=1; status='BLOCKED'; phase='RUNNER_BLOCKED'; classification='CONFIG_INFRA'; cleanupSucceeded=$true; retainedState=$false }
  'redis-unavailable'=@{ exitCode=1; status='BLOCKED'; phase='RUNNER_BLOCKED'; classification='CONFIG_INFRA'; cleanupSucceeded=$true; retainedState=$false }
  'wiremock-unmatched'=@{ exitCode=1; status='FAIL'; phase='RUNNER_FAILED'; classification='TEST_HARNESS'; cleanupSucceeded=$true; retainedState=$false }
  'seed-failure'=@{ exitCode=1; status='FAIL'; phase='RUNNER_FAILED'; classification='FIXTURE_ASSERTION'; cleanupSucceeded=$true; retainedState=$false }
  'cleanup-failure'=@{ exitCode=1; status='FAIL'; phase='RUNNER_FAILED'; classification='TEST_HARNESS'; cleanupSucceeded=$false; retainedState=$true }
  'maven-arguments'=@{ exitCode=0; status='PASS'; phase='RUNNER_COMPLETED'; classification='NONE'; cleanupSucceeded=$true; retainedState=$false }
  'maven-execution-failure'=@{ exitCode=1; status='FAIL'; phase='RUNNER_FAILED'; classification='TEST_HARNESS'; cleanupSucceeded=$true; retainedState=$false }
  'surefire-missing'=@{ exitCode=1; status='FAIL'; phase='RUNNER_FAILED'; classification='TEST_HARNESS'; cleanupSucceeded=$true; retainedState=$false }
  'utf8-log'=@{ exitCode=0; status='PASS'; phase='RUNNER_COMPLETED'; classification='NONE'; cleanupSucceeded=$true; retainedState=$false }
  'interrupted-run'=@{ exitCode=1; status='FAIL'; phase='RUNNER_FAILED'; classification='TEST_HARNESS'; cleanupSucceeded=$true; retainedState=$false }
  'evidence-missing'=@{ exitCode=1; status='FAIL'; phase='RUNNER_FAILED'; classification='TEST_HARNESS'; cleanupSucceeded=$true; retainedState=$false }
}

function Get-Hash([string]$Path) { return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant() }

function Test-PathWithin([string]$Child, [string]$Parent) {
  $childPath = [IO.Path]::GetFullPath($Child)
  $parentPath = [IO.Path]::GetFullPath($Parent).TrimEnd('\','/')
  return $childPath.StartsWith($parentPath + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)
}

function Resolve-ControlledPath([string]$RelativePath) {
  if ([string]::IsNullOrWhiteSpace($RelativePath) -or [IO.Path]::IsPathRooted($RelativePath)) { throw "Certification path must be relative: $RelativePath" }
  $path = [IO.Path]::GetFullPath((Join-Path $HarnessRoot $RelativePath))
  if (-not (Test-PathWithin $path $HarnessRoot)) { throw "Certification path escapes harness root: $RelativePath" }
  return $path
}

function Get-RelativePath([string]$Path) {
  $full = [IO.Path]::GetFullPath($Path)
  if (-not (Test-PathWithin $full $HarnessRoot)) { throw "Evidence is outside harness root: $Path" }
  return $full.Substring($HarnessRoot.TrimEnd('\','/').Length + 1).Replace('\','/')
}

function Get-HarnessFiles {
  $relativePaths = @('scripts/system-test.ps1','scripts/collect-failure-evidence.ps1','scripts/harness-certification.ps1','self-test/invoke-harness-self-test.ps1','self-test/harness-self-test-adapter.ps1')
  $items = @()
  foreach ($relativePath in $relativePaths) {
    $path = Resolve-ControlledPath $relativePath
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "Harness file missing: $relativePath" }
    $items += [pscustomobject]@{ path=$relativePath; sha256=(Get-Hash $path) }
  }
  return $items
}

function Get-HarnessRevision($Files) {
  $canonical = @($Files | Sort-Object path | ForEach-Object { "$($_.path)`n$($_.sha256)" }) -join "`n"
  $sha = [Security.Cryptography.SHA256]::Create()
  try { return (-join ($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($canonical)) | ForEach-Object { $_.ToString('x2') })) }
  finally { $sha.Dispose() }
}

function Read-Json([string]$Path, [string]$Label) {
  if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { throw "$Label missing: $Path" }
  try { return Get-Content -LiteralPath $Path -Raw -Encoding UTF8 | ConvertFrom-Json }
  catch { throw "$Label is not valid JSON: $Path" }
}

function Assert-SelfTestReport($Report, [string]$Revision) {
  if ($Report.schemaVersion -ne 2 -or $Report.result -ne 'PASS' -or $Report.harnessRevision -ne $Revision) { throw 'Harness self-test report is incomplete, failed, or bound to another revision.' }
  $scenarios = @($Report.scenarios)
  if ($scenarios.Count -ne $requiredScenarios.Count) { throw 'Harness self-test scenario set is incomplete.' }
  foreach ($id in $requiredScenarios) {
    $scenario = @($scenarios | Where-Object { $_.id -eq $id })
    if ($scenario.Count -ne 1 -or $scenario[0].result -ne 'PASS') { throw "Harness self-test scenario did not pass: $id" }
    if ([string]::IsNullOrWhiteSpace([string]$scenario[0].status) -or [string]::IsNullOrWhiteSpace([string]$scenario[0].phase) -or [string]::IsNullOrWhiteSpace([string]$scenario[0].classification)) { throw "Harness self-test result fields are incomplete: $id" }
    if ($null -eq $scenario[0].cleanup -or $null -eq $scenario[0].cleanup.succeeded -or $null -eq $scenario[0].cleanup.retainedState) { throw "Harness cleanup result is incomplete: $id" }
    foreach ($property in @('rawEvidencePath','runnerOutputPath')) {
      $path = Resolve-ControlledPath ([string]$scenario[0].$property)
      if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "Harness scenario evidence missing: $id $property" }
    }
    $expected = $scenarioExpectations[$id]
    if ([int]$scenario[0].exitCode -ne [int]$expected.exitCode -or $scenario[0].status -ne $expected.status -or $scenario[0].phase -ne $expected.phase -or $scenario[0].classification -ne $expected.classification -or [bool]$scenario[0].cleanup.succeeded -ne [bool]$expected.cleanupSucceeded -or [bool]$scenario[0].cleanup.retainedState -ne [bool]$expected.retainedState) {
      throw "Harness self-test observed result differs from the controlled expectation: $id"
    }
    $runnerOutput = Get-Content -LiteralPath (Resolve-ControlledPath ([string]$scenario[0].runnerOutputPath)) -Raw -Encoding UTF8
    if ($runnerOutput -notmatch '\[SYSTEM_TEST_RESULT\]') { throw "Harness scenario did not execute the runner completion path: $id" }
    $structuredPath = Resolve-ControlledPath ("self-test/artifacts/$id/structured-result.json")
    $structured = Read-Json $structuredPath "Harness scenario structured result $id"
    if ($structured.scenario -ne $id -or [int]$structured.exitCode -ne [int]$scenario[0].exitCode -or $structured.status -ne $scenario[0].status -or $structured.phase -ne $scenario[0].phase -or $structured.classification -ne $scenario[0].classification) {
      throw "Harness report is not bound to its runner structured result: $id"
    }
  }
}

function Get-ScenarioEvidence($Report) {
  $inventory = @()
  foreach ($scenario in @($Report.scenarios)) {
    $artifactRoot = Resolve-ControlledPath ("self-test/artifacts/$($scenario.id)")
    if (-not (Test-Path -LiteralPath $artifactRoot -PathType Container)) { throw "Harness scenario artifact directory missing: $($scenario.id)" }
    foreach ($file in @(Get-ChildItem -LiteralPath $artifactRoot -File -Recurse | Sort-Object FullName)) {
      $inventory += [pscustomobject]@{ scenarioId=[string]$scenario.id; path=(Get-RelativePath $file.FullName); sha256=(Get-Hash $file.FullName) }
    }
  }
  return $inventory
}

function Assert-Certification {
  $certification = Read-Json $CertificationPath 'Harness certification'
  $files = @(Get-HarnessFiles)
  $revision = Get-HarnessRevision $files
  if ($certification.schemaVersion -ne 2 -or $certification.result -ne 'PASS') { throw 'Harness certification is not a structured PASS.' }
  if ($certification.harnessRevision -ne $revision) { throw 'Harness certification is stale for the current harness revision.' }
  if ([string]::IsNullOrWhiteSpace([string]$certification.harnessVersion)) { throw 'Harness certification version is missing.' }
  $reportedFiles = @($certification.files)
  if ($reportedFiles.Count -ne $files.Count) { throw 'Harness certification file set differs from the controlled harness file set.' }
  foreach ($file in $files) {
    $match = @($reportedFiles | Where-Object { $_.path -eq $file.path })
    if ($match.Count -ne 1 -or $match[0].sha256 -ne $file.sha256) { throw "Harness certification file hash mismatch: $($file.path)" }
  }
  $reportPath = Resolve-ControlledPath ([string]$certification.selfTestReportPath)
  if ((Get-Hash $reportPath) -ne $certification.selfTestReportHash) { throw 'Harness self-test report hash mismatch.' }
  $report = Read-Json $reportPath 'Harness self-test report'
  Assert-SelfTestReport $report $revision
  $reportedEvidence = @($certification.scenarioEvidence)
  if ($reportedEvidence.Count -eq 0) { throw 'Harness certification has no scenario evidence.' }
  foreach ($item in $reportedEvidence) {
    $path = Resolve-ControlledPath ([string]$item.path)
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "Certified scenario evidence missing: $($item.path)" }
    if ((Get-Hash $path) -ne $item.sha256) { throw "Certified scenario evidence hash mismatch: $($item.path)" }
  }
  $actualEvidence = @(Get-ScenarioEvidence $report)
  if ($actualEvidence.Count -ne $reportedEvidence.Count) { throw 'Certified scenario evidence inventory differs from actual artifacts.' }
  foreach ($item in $actualEvidence) {
    $match = @($reportedEvidence | Where-Object { $_.scenarioId -eq $item.scenarioId -and $_.path -eq $item.path })
    if ($match.Count -ne 1 -or $match[0].sha256 -ne $item.sha256) { throw "Certified scenario evidence inventory mismatch: $($item.path)" }
  }
  Write-Output '[HARNESS_CERTIFICATION] PASS'
  Write-Output "harness_revision: $revision"
}

$files = @(Get-HarnessFiles)
$revision = Get-HarnessRevision $files
switch ($Command) {
  'revision' { Write-Output $revision }
  'verify' { Assert-Certification }
  'certify' {
    if ([string]::IsNullOrWhiteSpace($SelfTestReport)) { throw 'A harness self-test report is required for certification.' }
    $reportPath = [IO.Path]::GetFullPath($SelfTestReport)
    if (-not (Test-PathWithin $reportPath $HarnessRoot)) { throw 'Harness self-test report must be inside the harness root.' }
    $report = Read-Json $reportPath 'Harness self-test report'
    Assert-SelfTestReport $report $revision
    $evidence = @(Get-ScenarioEvidence $report)
    $directory = Split-Path -Parent $CertificationPath
    if (-not (Test-Path -LiteralPath $directory)) { [void](New-Item -ItemType Directory -Path $directory -Force) }
    $certification = [ordered]@{
      schemaVersion=2; result='PASS'; harnessVersion=$HarnessVersion; harnessRevision=$revision
      selfTestReportPath=(Get-RelativePath $reportPath); selfTestReportHash=(Get-Hash $reportPath)
      files=$files; scenarioEvidence=$evidence; certifiedAt=[DateTime]::UtcNow.ToString('o')
    }
    [IO.File]::WriteAllText($CertificationPath, ($certification | ConvertTo-Json -Depth 10), [Text.UTF8Encoding]::new($false))
    Assert-Certification
  }
}
exit 0
