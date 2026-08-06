$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSScriptRoot))
$sourceHarness = Join-Path $repoRoot 'flow\templates\system-test'
$controller = Join-Path $repoRoot 'flow\scripts\flow-test-controller.ps1'
$root = Join-Path ([IO.Path]::GetTempPath()) ('wp5-wp6 contract-' + [guid]::NewGuid().ToString('N'))

function Invoke-Git([string]$Repository, [string[]]$Arguments) {
  $output = @(& git -C $Repository @Arguments 2>&1)
  if ($LASTEXITCODE -ne 0) { throw "git command failed: $($Arguments -join ' ')`n$($output -join [Environment]::NewLine)" }
  return $output
}
function New-GitRepository([string]$Path, [string]$Change) {
  New-Item -ItemType Directory -Path $Path -Force | Out-Null
  Invoke-Git $Path @('init','--quiet') | Out-Null
  Invoke-Git $Path @('config','user.email','contract@example.invalid') | Out-Null
  Invoke-Git $Path @('config','user.name','contract-test') | Out-Null
  Set-Content -LiteralPath (Join-Path $Path 'README.md') -Value 'baseline' -Encoding utf8
  Invoke-Git $Path @('add','.') | Out-Null; Invoke-Git $Path @('commit','--quiet','-m','baseline') | Out-Null
  $baseline = (Invoke-Git $Path @('rev-parse','HEAD') | Select-Object -First 1).Trim()
  $changePath = Join-Path $Path "changes\$Change"; New-Item -ItemType Directory -Path $changePath -Force | Out-Null
  Set-Content -LiteralPath (Join-Path $changePath 'design.md') -Value 'design' -Encoding utf8
  Invoke-Git $Path @('add','.') | Out-Null; Invoke-Git $Path @('commit','--quiet','-m','design') | Out-Null
  [pscustomobject]@{ baseline=$baseline; design=(Invoke-Git $Path @('rev-parse','HEAD') | Select-Object -First 1).Trim() }
}
function Get-DiffHash([string]$Repository, [string]$Baseline, [string]$Current) {
  $text = (@(Invoke-Git $Repository @('diff','--no-ext-diff','--binary','--full-index',$Baseline,$Current)) -join "`n")
  $sha = [Security.Cryptography.SHA256]::Create(); try { return -join ($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($text)) | ForEach-Object { $_.ToString('x2') }) } finally { $sha.Dispose() }
}
function Write-Verifier([string]$Path, [string]$Mode, [string]$Test, [string]$Sut, [string]$Harness, [string]$Config, [string]$Base = '') {
  $report = [ordered]@{ result='PASS'; mode=$Mode; verifierId='contract-verifier'; testRevision=$Test; sutRevision=$Sut; harnessRevision=$Harness; configurationFingerprint=$Config; summary='contract verification passed' }
  if ($Base) { $report.implementationBaseRevision = $Base }
  [IO.File]::WriteAllText($Path, ($report | ConvertTo-Json -Depth 8), [Text.UTF8Encoding]::new($false))
}
function Assert-Controller([scriptblock]$Call, [bool]$Pass, [string]$Marker) {
  $output = @(& $Call 2>&1)
  if ($Pass -ne ($LASTEXITCODE -eq 0) -or ($output -join "`n") -notmatch [regex]::Escape($Marker)) { throw "unexpected controller result: $($output -join [Environment]::NewLine)" }
}

try {
  New-Item -ItemType Directory -Path $root -Force | Out-Null
  $harness = Join-Path $root 'isolated harness copy'; Copy-Item -LiteralPath $sourceHarness -Destination $harness -Recurse
  $selfTest = Join-Path $harness 'self-test\invoke-harness-self-test.ps1'; $certifier = Join-Path $harness 'scripts\harness-certification.ps1'
  $report = Join-Path $harness 'self-test\contract-self-test.json'; $certification = Join-Path $harness 'self-test\contract-certification.json'
  & $selfTest -HarnessRoot $harness -ReportPath $report -RuntimeExecutable powershell.exe
  if ((Get-Content -LiteralPath $report -Raw -Encoding utf8 | ConvertFrom-Json).result -ne 'PASS') { throw 'real harness self-test did not pass' }
  & $certifier certify -HarnessRoot $harness -CertificationPath $certification -SelfTestReport $report -HarnessVersion contract
  if ($LASTEXITCODE -ne 0) { throw 'formal schemaVersion=2 certification did not pass' }
  $certificationJson = Get-Content -LiteralPath $certification -Raw -Encoding utf8 | ConvertFrom-Json
  if ($certificationJson.schemaVersion -ne 2) { throw 'formal certifier did not generate schemaVersion=2' }
  $revision = (& $certifier revision -HarnessRoot $harness | Select-Object -Last 1).Trim()

  $change = 'contract-change'; $system = Join-Path $root 'system-test-repo'; $sut = Join-Path $root 'sut-repo'
  $systemRevisions = New-GitRepository $system $change; $sutRevisions = New-GitRepository $sut 'sut-contract'
  $state = Join-Path $root 'automation-state.json'; $config = 'contract-config'
  $designReport = Join-Path $root 'design.json'; Write-Verifier $designReport design $systemRevisions.design $sutRevisions.design $revision $config
  Assert-Controller { & $controller initialize -StatePath $state -ChangeName $change -SystemTestRepo $system -SutRepo $sut -TestBaselineRevision $systemRevisions.baseline -TestRevision $systemRevisions.design -SutRevision $sutRevisions.design -HarnessRevision $revision -HarnessRoot $harness -HarnessCertificationPath $certification -ConfigurationFingerprint $config -Authorization result } $true '[FLOW_CONTROLLER] PASS'
  Assert-Controller { & $controller record-verifier -StatePath $state -VerifyMode design -TestRevision $systemRevisions.design -SutRevision $sutRevisions.design -HarnessRevision $revision -ConfigurationFingerprint $config -ReportPath $designReport -VerifierId contract-verifier } $true '[FLOW_CONTROLLER] PASS'
  Assert-Controller { & $controller issue-lease -StatePath $state -TestRevision $systemRevisions.design -SutRevision $sutRevisions.design -HarnessRevision $revision -ConfigurationFingerprint $config -Role test-implementer -AgentId contract-agent } $true '[FLOW_CONTROLLER] PASS'
  Set-Content -LiteralPath (Join-Path $system "changes\$change\test.java") -Value 'implementation' -Encoding utf8
  Invoke-Git $system @('add','.') | Out-Null; Invoke-Git $system @('commit','--quiet','-m','implementation') | Out-Null
  $implementation = (Invoke-Git $system @('rev-parse','HEAD') | Select-Object -First 1).Trim()
  $scope = Join-Path $root 'scope.json'; $implementationResult = Join-Path $root 'implementation.json'
  $changed = @(Invoke-Git $system @('diff','--name-only','--diff-filter=ACDMRTUXB',$systemRevisions.design,$implementation) | ForEach-Object { $_.Trim().Replace('\','/') } | Where-Object { $_ })
  @{ result='PASS'; baselineRevision=$systemRevisions.design; currentRevision=$implementation; repository=[IO.Path]::GetFullPath($system); changedFiles=$changed; diffHash=(Get-DiffHash $system $systemRevisions.design $implementation) } | ConvertTo-Json | Set-Content -LiteralPath $scope -Encoding utf8
  @{ result='PASS'; testRevision=$implementation; implementationBaseRevision=$systemRevisions.design } | ConvertTo-Json | Set-Content -LiteralPath $implementationResult -Encoding utf8
  Assert-Controller { & $controller accept-result -StatePath $state -ProposedTestRevision $implementation -SutRevision $sutRevisions.design -HarnessRevision $revision -ConfigurationFingerprint $config -ReportPath $implementationResult -ScopeGuardReportPath $scope } $true '[FLOW_CONTROLLER] PASS'
  $implementationReport = Join-Path $root 'implementation-verifier.json'; Write-Verifier $implementationReport implementation $implementation $sutRevisions.design $revision $config $systemRevisions.design
  Assert-Controller { & $controller record-verifier -StatePath $state -VerifyMode implementation -TestRevision $implementation -SutRevision $sutRevisions.design -HarnessRevision $revision -ConfigurationFingerprint $config -ReportPath $implementationReport -VerifierId contract-verifier } $true '[FLOW_CONTROLLER] PASS'
  $environmentReport = Join-Path $root 'environment-verifier.json'; Write-Verifier $environmentReport environment $implementation $sutRevisions.design $revision $config
  Assert-Controller { & $controller record-verifier -StatePath $state -VerifyMode environment -TestRevision $implementation -SutRevision $sutRevisions.design -HarnessRevision $revision -ConfigurationFingerprint $config -ReportPath $environmentReport -VerifierId contract-verifier } $true '[FLOW_CONTROLLER] PASS'
  Assert-Controller { & $controller start-run -StatePath $state -TestRevision $implementation -SutRevision $sutRevisions.design -HarnessRevision $revision -ConfigurationFingerprint $config } $true '[FLOW_CONTROLLER] PASS'

  $oldCertification = Join-Path $harness 'self-test\legacy-schema-v1.json'
  @{ schemaVersion=1; result='PASS'; harnessRevision=$revision; files=@() } | ConvertTo-Json | Set-Content -LiteralPath $oldCertification -Encoding utf8
  Assert-Controller { & $controller initialize -StatePath (Join-Path $root 'legacy-state.json') -ChangeName legacy-change -SystemTestRepo $system -SutRepo $sut -TestBaselineRevision $systemRevisions.baseline -TestRevision $implementation -SutRevision $sutRevisions.design -HarnessRevision $revision -HarnessRoot $harness -HarnessCertificationPath $oldCertification -ConfigurationFingerprint $config -Authorization result } $false 'ERROR_HARNESS_UNCERTIFIED'
  Add-Content -LiteralPath (Join-Path $harness 'scripts\system-test.ps1') -Value '# contract mutation'
  $verifyFailed = $false
  try { $verifyOutput = @(& $certifier verify -HarnessRoot $harness -CertificationPath $certification 2>&1) } catch { $verifyOutput = @($_); $verifyFailed = $true }
  if (-not $verifyFailed -and $LASTEXITCODE -eq 0) { throw "modified harness remained certified: $($verifyOutput -join [Environment]::NewLine)" }
  Assert-Controller { & $controller start-run -StatePath $state -TestRevision $implementation -SutRevision $sutRevisions.design -HarnessRevision $revision -ConfigurationFingerprint $config } $false 'ERROR_HARNESS_UNCERTIFIED'
  Write-Output 'WP5-WP6 integration contract tests passed'
} finally {
  if (Test-Path -LiteralPath $root) { Remove-Item -LiteralPath $root -Recurse -Force }
}
