$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSScriptRoot))
$source = Join-Path $repoRoot 'flow\templates\system-test'
$root = Join-Path ([IO.Path]::GetTempPath()) ('flow harness-' + [guid]::NewGuid().ToString('N'))

function Write-Utf8([string]$Path, [string]$Value) {
  [IO.File]::WriteAllText($Path, $Value, [Text.UTF8Encoding]::new($false))
}

function Assert-Rejected([scriptblock]$Action, [string]$Pattern, [string]$Label) {
  $rejected = $false
  try { & $Action | Out-Null }
  catch { $rejected = $_.Exception.Message -match $Pattern }
  if (-not $rejected) { throw "negative case was not rejected: $Label" }
}

function New-IsolationMarker([string]$HarnessRoot, [string]$Token, [string]$Revision) {
  $bytes = [Text.Encoding]::UTF8.GetBytes($Token); $sha = [Security.Cryptography.SHA256]::Create()
  try { $tokenHash = -join ($sha.ComputeHash($bytes) | ForEach-Object { $_.ToString('x2') }) } finally { $sha.Dispose() }
  @{ schemaVersion=1; harnessRoot=[IO.Path]::GetFullPath($HarnessRoot); harnessRevision=$Revision; tokenSha256=$tokenHash } | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $HarnessRoot '.harness-self-test-isolation.json') -Encoding utf8
}

function Copy-Baseline([string]$Name) {
  $destination = Join-Path ([IO.Path]::GetTempPath()) ("flow harness-$Name-" + [guid]::NewGuid().ToString('N'))
  Copy-Item -LiteralPath $root -Destination $destination -Recurse
  return $destination
}

$mutationRoots = [System.Collections.Generic.List[string]]::new()
try {
  Copy-Item -LiteralPath $source -Destination $root -Recurse
  $selfTest = Join-Path $root 'self-test\invoke-harness-self-test.ps1'
  $certifier = Join-Path $root 'scripts\harness-certification.ps1'
  $report = Join-Path $root 'self-test\result.json'
  $certification = Join-Path $root 'self-test\certification.json'

  & $selfTest -HarnessRoot $root -ReportPath $report -RuntimeExecutable 'powershell.exe'
  $selfTestResult = Get-Content -LiteralPath $report -Raw -Encoding UTF8 | ConvertFrom-Json
  if ($selfTestResult.schemaVersion -ne 2 -or $selfTestResult.result -ne 'PASS') { throw 'executable harness self-test did not pass' }
  $required = @('normal-run','sut-startup-failure','mysql-unavailable','postgres-unavailable','redis-unavailable','wiremock-unmatched','seed-failure','cleanup-failure','maven-arguments','maven-execution-failure','surefire-missing','utf8-log','interrupted-run','evidence-missing')
  foreach ($id in $required) {
    $case = @($selfTestResult.scenarios | Where-Object { $_.id -eq $id })
    if ($case.Count -ne 1 -or $case[0].result -ne 'PASS' -or [string]::IsNullOrWhiteSpace([string]$case[0].phase) -or [string]::IsNullOrWhiteSpace([string]$case[0].classification)) { throw "missing executable self-test result: $id" }
    foreach ($property in @('rawEvidencePath','runnerOutputPath')) {
      $path = Join-Path $root ([string]$case[0].$property)
      if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "self-test evidence missing: $id $property" }
    }
  }
  $cleanupCase = @($selfTestResult.scenarios | Where-Object { $_.id -eq 'cleanup-failure' })[0]
  if ($cleanupCase.cleanup.succeeded -or -not $cleanupCase.cleanup.retainedState) { throw 'cleanup failure retention was not observed' }
  $mavenArguments = Join-Path $root 'self-test\artifacts\maven-arguments\runtime\raw\maven-arguments.json'
  if (-not (Test-Path -LiteralPath $mavenArguments -PathType Leaf)) { throw 'Maven argument evidence was not produced by the runner adapter' }
  $utf8Log = Join-Path $root 'self-test\artifacts\utf8-log\runtime\logs\utf8.log'
  if ((Get-Content -LiteralPath $utf8Log -Raw -Encoding UTF8).Length -lt 4) { throw 'UTF-8 evidence was not preserved' }
  $surefireIndex = Get-Content -LiteralPath (Join-Path $root 'self-test\artifacts\surefire-missing\evidence\current\index.md') -Raw -Encoding UTF8
  if ($surefireIndex -notmatch 'junit: unavailable') { throw 'missing Surefire report was not observed' }

  & $certifier certify -HarnessRoot $root -CertificationPath $certification -SelfTestReport $report -HarnessVersion 'test'
  & $certifier verify -HarnessRoot $root -CertificationPath $certification

  $evidenceMutation = Copy-Baseline 'evidence-mutation'; $mutationRoots.Add($evidenceMutation)
  $evidenceCertifier = Join-Path $evidenceMutation 'scripts\harness-certification.ps1'
  $evidenceCertification = Join-Path $evidenceMutation 'self-test\certification.json'
  $certificationJson = Get-Content -LiteralPath $evidenceCertification -Raw -Encoding UTF8 | ConvertFrom-Json
  $evidencePath = Join-Path $evidenceMutation ([string]$certificationJson.scenarioEvidence[0].path)
  Remove-Item -LiteralPath $evidencePath -Force
  Assert-Rejected { & $evidenceCertifier verify -HarnessRoot $evidenceMutation -CertificationPath $evidenceCertification } 'missing|inventory' 'deleted raw evidence'

  $classificationMutation = Copy-Baseline 'classification-mutation'; $mutationRoots.Add($classificationMutation)
  $classificationReportPath = Join-Path $classificationMutation 'self-test\result.json'
  $classificationReport = Get-Content -LiteralPath $classificationReportPath -Raw -Encoding UTF8 | ConvertFrom-Json
  @($classificationReport.scenarios | Where-Object { $_.id -eq 'mysql-unavailable' })[0].classification = 'TEST_HARNESS'
  Write-Utf8 $classificationReportPath ($classificationReport | ConvertTo-Json -Depth 10)
  Assert-Rejected { & (Join-Path $classificationMutation 'scripts\harness-certification.ps1') certify -HarnessRoot $classificationMutation -CertificationPath (Join-Path $classificationMutation 'self-test\mutated-certification.json') -SelfTestReport $classificationReportPath } 'expectation' 'classification drift'

  $runnerBypass = Copy-Baseline 'runner-bypass'; $mutationRoots.Add($runnerBypass)
  $structuredPath = Join-Path $runnerBypass 'self-test\artifacts\normal-run\structured-result.json'
  $structured = Get-Content -LiteralPath $structuredPath -Raw -Encoding UTF8 | ConvertFrom-Json
  $structured.phase = 'FORGED'
  Write-Utf8 $structuredPath ($structured | ConvertTo-Json -Depth 8)
  Assert-Rejected { & (Join-Path $runnerBypass 'scripts\harness-certification.ps1') certify -HarnessRoot $runnerBypass -CertificationPath (Join-Path $runnerBypass 'self-test\forged-certification.json') -SelfTestReport (Join-Path $runnerBypass 'self-test\result.json') } 'not bound' 'runner bypass'

  $staleMutation = Copy-Baseline 'stale-mutation'; $mutationRoots.Add($staleMutation)
  Add-Content -LiteralPath (Join-Path $staleMutation 'scripts\system-test.ps1') -Value '# mutation invalidates certification'
  Assert-Rejected { & (Join-Path $staleMutation 'scripts\harness-certification.ps1') verify -HarnessRoot $staleMutation -CertificationPath (Join-Path $staleMutation 'self-test\certification.json') } 'stale|mismatch' 'stale certification'

  $runner = Join-Path $root 'scripts\system-test.ps1'
  $adapter = Join-Path $root 'self-test\harness-self-test-adapter.ps1'
  $oldPreference = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
  try { $bypassOutput = @(& powershell.exe -NoProfile -ExecutionPolicy Bypass -File $runner run -Change 'missing' -HarnessAdapterPath $adapter 2>&1); $bypassExit = $LASTEXITCODE }
  finally { $ErrorActionPreference = $oldPreference }
  if ($bypassExit -eq 0 -or ($bypassOutput -join "`n") -notmatch 'explicit harness self-test mode') { throw 'runner accepted adapter injection outside self-test mode' }

  # The production runner accepts self-test only from the isolated wrapper contract.
  $token = 'boundary-token'; $revision = (& $certifier revision -HarnessRoot $root | Select-Object -Last 1).Trim(); $reservedChange = '__flow_internal_harness_self_test__-normal-run'
  Assert-Rejected { & $runner run -Change 'business-change' -Suite api -HarnessSelfTest -HarnessAdapterPath $adapter -HarnessSelfTestScenario normal-run -HarnessSelfTestToken $token } 'reserved internal change name' 'business change cannot enter self-test mode'
  Assert-Rejected { & $runner run -Change $reservedChange -Suite api -ExecutionMode orchestrated -HarnessSelfTest -HarnessAdapterPath $adapter -HarnessSelfTestScenario normal-run -HarnessSelfTestToken $token } 'orchestrated mode cannot' 'orchestrated self-test'
  New-IsolationMarker $root $token $revision
  $alternateAdapter = Join-Path $root 'self-test\alternate-adapter.ps1'; Copy-Item -LiteralPath $adapter -Destination $alternateAdapter
  Assert-Rejected { & $runner run -Change $reservedChange -Suite api -HarnessSelfTest -HarnessAdapterPath $alternateAdapter -HarnessSelfTestScenario normal-run -HarnessSelfTestToken $token } 'exact canonical' 'non-canonical adapter'
  Assert-Rejected { & $runner run -Change $reservedChange -Suite api -HarnessSelfTest -HarnessAdapterPath $adapter -HarnessSelfTestScenario normal-run } 'token is missing or invalid' 'missing isolation token'
  Add-Content -LiteralPath $adapter -Value '# adapter mutation'
  Assert-Rejected { & $runner run -Change $reservedChange -Suite api -HarnessSelfTest -HarnessAdapterPath $adapter -HarnessSelfTestScenario normal-run -HarnessSelfTestToken $token } 'not bound to the current harness revision' 'modified adapter'
  Remove-Item -LiteralPath (Join-Path $root '.harness-self-test-isolation.json') -Force
  $formalRunner = Join-Path $source 'scripts\system-test.ps1'; $formalAdapter = Join-Path $source 'self-test\harness-self-test-adapter.ps1'
  Assert-Rejected { & $formalRunner run -Change $reservedChange -Suite api -HarnessSelfTest -HarnessAdapterPath $formalAdapter -HarnessSelfTestScenario normal-run -HarnessSelfTestToken $token } 'isolated temporary harness copy' 'formal harness workspace'

  Write-Output 'harness certification tests passed'
}
finally {
  foreach ($path in @($mutationRoots) + @($root)) {
    if (-not [string]::IsNullOrWhiteSpace($path) -and (Test-Path -LiteralPath $path)) {
      $resolved = [IO.Path]::GetFullPath($path)
      $temp = [IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\')
      if ($resolved.StartsWith($temp + '\', [StringComparison]::OrdinalIgnoreCase)) { Remove-Item -LiteralPath $resolved -Recurse -Force }
    }
  }
}
