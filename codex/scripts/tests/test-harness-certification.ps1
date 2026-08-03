$ErrorActionPreference = 'Stop'
$source = Join-Path (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)) 'flow\templates\system-test'
if (-not (Test-Path -LiteralPath $source)) {
  $source = Join-Path (Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSScriptRoot))) 'flow\templates\system-test'
}
$root = Join-Path ([IO.Path]::GetTempPath()) ('flow-harness-' + [guid]::NewGuid().ToString('N'))
try {
  Copy-Item -LiteralPath $source -Destination $root -Recurse
  $selfTest = Join-Path $root 'self-test\invoke-harness-self-test.ps1'
  $certifier = Join-Path $root 'scripts\harness-certification.ps1'
  $report = Join-Path $root 'self-test\result.json'
  $certification = Join-Path $root 'self-test\certification.json'
  & $selfTest -HarnessRoot $root -ReportPath $report
  $selfTestResult = Get-Content -LiteralPath $report -Raw -Encoding UTF8 | ConvertFrom-Json
  $required = @('normal-run','sut-startup-failure','mysql-unavailable','postgres-unavailable','redis-unavailable','wiremock-unmatched','maven-arguments','surefire-missing','seed-failure','cleanup-failure','utf8-log','interrupted-run','evidence-missing')
  foreach ($id in $required) {
    $case = @($selfTestResult.scenarios | Where-Object { $_.id -eq $id })
    if ($case.Count -ne 1 -or $case[0].result -ne 'PASS' -or [string]::IsNullOrWhiteSpace([string]$case[0].evidence)) { throw "missing structured self-test result: $id" }
  }
  & $certifier certify -HarnessRoot $root -CertificationPath $certification -SelfTestReport $report -HarnessVersion 'test'
  & $certifier verify -HarnessRoot $root -CertificationPath $certification
  Add-Content -LiteralPath (Join-Path $root 'scripts\system-test.ps1') -Value '# mutation invalidates certification'
  $rejected = $false
  try { & $certifier verify -HarnessRoot $root -CertificationPath $certification | Out-Null }
  catch { $rejected = $_.Exception.Message -match 'stale|mismatch' }
  if (-not $rejected) { throw 'changed harness did not invalidate certification' }
  $runner = Get-Content -LiteralPath (Join-Path $source 'scripts\system-test.ps1') -Raw -Encoding UTF8
  foreach ($marker in @('STOP_AWAIT_HUMAN_CONFIGURATION','ownership -eq ''human''','Invoke-ReliableCleanup','Assert-HarnessCertification')) {
    if (-not $runner.Contains($marker)) { throw "runner routing marker missing: $marker" }
  }
  Write-Output 'harness certification tests passed'
}
finally { Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue }
