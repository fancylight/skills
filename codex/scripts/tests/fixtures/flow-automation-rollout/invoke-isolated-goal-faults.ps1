[CmdletBinding()]
param(
  [Parameter(Mandatory=$true)] [string]$ControllerPath,
  [Parameter(Mandatory=$true)] [string]$OutputPath
)

$ErrorActionPreference = 'Stop'
$root = Join-Path ([IO.Path]::GetTempPath()) ('flow-goal-faults-' + [guid]::NewGuid().ToString('N'))
[void](New-Item -ItemType Directory -Path $root -Force)
$observations = [System.Collections.Generic.List[object]]::new()

function Invoke-Git([string]$Repository, [string[]]$Arguments) {
  $output = @(& git -C $Repository @Arguments 2>&1)
  if ($LASTEXITCODE -ne 0) { throw "git failed: $($Arguments -join ' ')" }
  return $output
}

function New-Repository([string]$Path, [string]$ChangeName) {
  [void](New-Item -ItemType Directory -Path $Path -Force)
  Invoke-Git $Path @('init','--quiet') | Out-Null
  Invoke-Git $Path @('config','user.email','rollout@example.invalid') | Out-Null
  Invoke-Git $Path @('config','user.name','rollout-fixture') | Out-Null
  [IO.File]::WriteAllText((Join-Path $Path 'README.md'), 'baseline', [Text.UTF8Encoding]::new($false))
  Invoke-Git $Path @('add','.') | Out-Null; Invoke-Git $Path @('commit','--quiet','-m','baseline') | Out-Null
  $baseline = (Invoke-Git $Path @('rev-parse','HEAD') | Select-Object -First 1).Trim()
  $changeRoot = Join-Path $Path "changes\$ChangeName"; [void](New-Item -ItemType Directory -Path $changeRoot -Force)
  [IO.File]::WriteAllText((Join-Path $changeRoot 'design.md'), 'design', [Text.UTF8Encoding]::new($false))
  Invoke-Git $Path @('add','.'); Invoke-Git $Path @('commit','--quiet','-m','design')
  return [pscustomobject]@{ baseline=$baseline; design=(Invoke-Git $Path @('rev-parse','HEAD') | Select-Object -First 1).Trim() }
}

function Get-Hash([string]$Path) {
  if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return 'missing' }
  return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
}

function Get-TextHash([string]$Text) {
  $sha = [Security.Cryptography.SHA256]::Create()
  try { return (-join ($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($Text)) | ForEach-Object { $_.ToString('x2') })) }
  finally { $sha.Dispose() }
}

function Invoke-Observed([string]$Id, [scriptblock]$Action, [string]$Expected) {
  $oldPreference = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
  try { $output = @(& $Action 2>&1 | ForEach-Object { [string]$_ }) }
  finally { $ErrorActionPreference = $oldPreference }
  $text = $output -join "`n"
  $matched = $text -match [regex]::Escape($Expected)
  $observations.Add([ordered]@{ id=$Id; executedAt=[DateTime]::UtcNow.ToString('o'); expected=$Expected; observed=$(if ($matched) { $Expected } else { 'UNEXPECTED' }); outputHash=(Get-TextHash $text); output=@($output) })
  if (-not $matched) { throw "fault injection did not reach expected controller result: $Id" }
}

function Write-Report([string]$Path, [string]$Mode, [string]$TestRevision, [string]$SutRevision, [string]$HarnessRevision, [string]$Config, [string]$Base = '') {
  $report = [ordered]@{ result='PASS'; mode=$Mode; verifierId='isolated-verifier'; testRevision=$TestRevision; sutRevision=$SutRevision; harnessRevision=$HarnessRevision; configurationFingerprint=$Config; summary='safe verification summary' }
  if ($Base) { $report.implementationBaseRevision=$Base }
  [IO.File]::WriteAllText($Path, ($report | ConvertTo-Json), [Text.UTF8Encoding]::new($false))
}

try {
  $change='isolated-change'; $system=Join-Path $root 'system'; $sut=Join-Path $root 'sut'; $systemFixture=New-Repository $system $change; $sutFixture=New-Repository $sut 'sut-change'
  $harnessRoot=Join-Path $root 'harness'; [void](New-Item -ItemType Directory -Path $harnessRoot -Force); $runner=Join-Path $harnessRoot 'runner.ps1'; [IO.File]::WriteAllText($runner,'Write-Output runner',[Text.UTF8Encoding]::new($false)); $runnerHash=Get-Hash $runner
  $certification=Join-Path $harnessRoot 'certification.json'; [IO.File]::WriteAllText($certification, (@{ schemaVersion=1; result='PASS'; harnessRevision='harness-fixture'; files=@(@{path='runner.ps1';sha256=$runnerHash}) } | ConvertTo-Json -Depth 6), [Text.UTF8Encoding]::new($false))
  $state=Join-Path $root 'state.json'; $designReport=Join-Path $root 'design-report.json'; Write-Report $designReport 'design' $systemFixture.design $sutFixture.design 'harness-fixture' 'config-fixture'
  & $ControllerPath initialize -StatePath $state -ChangeName $change -SystemTestRepo $system -SutRepo $sut -TestBaselineRevision $systemFixture.baseline -TestRevision $systemFixture.design -SutRevision $sutFixture.design -HarnessRevision 'harness-fixture' -HarnessRoot $harnessRoot -HarnessCertificationPath $certification -ConfigurationFingerprint 'config-fixture' -Authorization result | Out-Null
  & $ControllerPath record-verifier -StatePath $state -VerifyMode design -TestRevision $systemFixture.design -SutRevision $sutFixture.design -HarnessRevision 'harness-fixture' -ConfigurationFingerprint 'config-fixture' -ReportPath $designReport -VerifierId 'isolated-verifier' | Out-Null
  $designState=Join-Path $root 'design-state.json'; Copy-Item -LiteralPath $state -Destination $designState
  & $ControllerPath issue-lease -StatePath $state -TestRevision $systemFixture.design -SutRevision $sutFixture.design -HarnessRevision 'harness-fixture' -ConfigurationFingerprint 'config-fixture' -Role test-implementer -AgentId isolated-agent | Out-Null
  $leasedState=Join-Path $root 'leased-state.json'; Copy-Item -LiteralPath $state -Destination $leasedState
  $lease=(Get-Content -LiteralPath $state -Raw -Encoding UTF8 | ConvertFrom-Json).leases[0]

  $oldPreference=$ErrorActionPreference; $ErrorActionPreference='Continue'; try { & powershell.exe -NoProfile -Command 'exit 73'; $agentExit=$LASTEXITCODE } finally { $ErrorActionPreference=$oldPreference }
  if ($agentExit -ne 73) { throw 'controlled agent exit did not execute' }
  $agentState=Join-Path $root 'agent-exit-state.json'; Copy-Item $leasedState $agentState
  Invoke-Observed 'agent-abnormal-exit' { & $ControllerPath next -StatePath $agentState } 'next: AWAIT_IMPLEMENTATION_RESULT'
  $beforeRecovery=Get-Hash $agentState; Invoke-Observed 'duplicate-recovery' { & $ControllerPath next -StatePath $agentState } 'next: AWAIT_IMPLEMENTATION_RESULT'; if ((Get-Hash $agentState) -ne $beforeRecovery) { throw 'read-only duplicate recovery changed state' }
  Invoke-Observed 'duplicate-lease-resume' { & $ControllerPath issue-lease -StatePath $agentState -TestRevision $systemFixture.design -SutRevision $sutFixture.design -HarnessRevision 'harness-fixture' -ConfigurationFingerprint 'config-fixture' -Role test-implementer -AgentId replacement-agent } 'ERROR_TRANSITION'

  $staleState=Join-Path $root 'stale-state.json'; Copy-Item $designState $staleState
  & $ControllerPath issue-lease -StatePath $staleState -TestRevision $systemFixture.design -SutRevision $sutFixture.design -HarnessRevision 'harness-fixture' -ConfigurationFingerprint 'config-fixture' -Role test-implementer -AgentId stale-agent -LeaseMinutes -1 | Out-Null
  $staleLease=(Get-Content -LiteralPath $staleState -Raw -Encoding UTF8 | ConvertFrom-Json).leases[0]
  Invoke-Observed 'stale-lease' { & $ControllerPath validate-lease -StatePath $staleState -LeaseId $staleLease.leaseId -AgentId stale-agent -Role test-implementer -Capabilities read -TargetPath (Join-Path $system "changes\$change\test.java") } 'ERROR_LEASE_INVALID'

  $implementationFile=Join-Path $system "changes\$change\test.java"; [IO.File]::WriteAllText($implementationFile,'implementation',[Text.UTF8Encoding]::new($false)); Invoke-Git $system @('add','.'); Invoke-Git $system @('commit','--quiet','-m','implementation'); $implementationRevision=(Invoke-Git $system @('rev-parse','HEAD') | Select-Object -First 1).Trim()
  $changed=@(Invoke-Git $system @('diff','--name-only',$systemFixture.design,$implementationRevision)); $diffText=@(Invoke-Git $system @('diff','--no-ext-diff','--binary','--full-index',$systemFixture.design,$implementationRevision)) -join "`n"; $diffHash=Get-TextHash $diffText
  $scope=Join-Path $root 'scope.json'; [IO.File]::WriteAllText($scope, (@{result='PASS';baselineRevision=$systemFixture.design;currentRevision=$implementationRevision;repository=[IO.Path]::GetFullPath($system);changedFiles=$changed;diffHash=$diffHash}|ConvertTo-Json), [Text.UTF8Encoding]::new($false))
  $implementationResult=Join-Path $root 'implementation-result.json'; [IO.File]::WriteAllText($implementationResult, (@{result='PASS';testRevision=$implementationRevision;implementationBaseRevision=$systemFixture.design}|ConvertTo-Json), [Text.UTF8Encoding]::new($false))
  & $ControllerPath accept-result -StatePath $state -ProposedTestRevision $implementationRevision -SutRevision $sutFixture.design -HarnessRevision 'harness-fixture' -ConfigurationFingerprint 'config-fixture' -ReportPath $implementationResult -ScopeGuardReportPath $scope | Out-Null
  $implementationReport=Join-Path $root 'implementation-report.json'; Write-Report $implementationReport 'implementation' $implementationRevision $sutFixture.design 'harness-fixture' 'config-fixture' $systemFixture.design
  & $ControllerPath record-verifier -StatePath $state -VerifyMode implementation -TestRevision $implementationRevision -SutRevision $sutFixture.design -HarnessRevision 'harness-fixture' -ConfigurationFingerprint 'config-fixture' -ReportPath $implementationReport -VerifierId isolated-verifier | Out-Null
  $environmentReport=Join-Path $root 'environment-report.json'; Write-Report $environmentReport 'environment' $implementationRevision $sutFixture.design 'harness-fixture' 'config-fixture'
  & $ControllerPath record-verifier -StatePath $state -VerifyMode environment -TestRevision $implementationRevision -SutRevision $sutFixture.design -HarnessRevision 'harness-fixture' -ConfigurationFingerprint 'config-fixture' -ReportPath $environmentReport -VerifierId isolated-verifier | Out-Null
  $environmentState=Join-Path $root 'environment-state.json'; Copy-Item $state $environmentState

  $duplicateRunnerState=Join-Path $root 'duplicate-runner-state.json'; Copy-Item $environmentState $duplicateRunnerState
  & $ControllerPath start-run -StatePath $duplicateRunnerState -TestRevision $implementationRevision -SutRevision $sutFixture.design -HarnessRevision 'harness-fixture' -ConfigurationFingerprint 'config-fixture' | Out-Null
  Invoke-Observed 'duplicate-runner' { & $ControllerPath start-run -StatePath $duplicateRunnerState -TestRevision $implementationRevision -SutRevision $sutFixture.design -HarnessRevision 'harness-fixture' -ConfigurationFingerprint 'config-fixture' } 'ERROR_RUN_DUPLICATE'

  $missingEvidenceState=Join-Path $root 'missing-evidence-state.json'; Copy-Item $environmentState $missingEvidenceState
  & $ControllerPath start-run -StatePath $missingEvidenceState -TestRevision $implementationRevision -SutRevision $sutFixture.design -HarnessRevision 'harness-fixture' -ConfigurationFingerprint 'config-fixture' | Out-Null
  Invoke-Observed 'evidence-missing' { & $ControllerPath record-run -StatePath $missingEvidenceState -RunResult pass -EvidencePath (Join-Path $root 'missing-evidence') -TestRevision $implementationRevision -SutRevision $sutFixture.design -HarnessRevision 'harness-fixture' -ConfigurationFingerprint 'config-fixture' } 'ERROR_INPUT'

  $failedRunState=Join-Path $root 'failed-run-state.json'; Copy-Item $environmentState $failedRunState; $evidence=Join-Path $root 'failure-evidence'; [void](New-Item -ItemType Directory -Path $evidence -Force)
  & $ControllerPath start-run -StatePath $failedRunState -TestRevision $implementationRevision -SutRevision $sutFixture.design -HarnessRevision 'harness-fixture' -ConfigurationFingerprint 'config-fixture' | Out-Null
  & $ControllerPath record-run -StatePath $failedRunState -RunResult fail -EvidencePath $evidence -TestRevision $implementationRevision -SutRevision $sutFixture.design -HarnessRevision 'harness-fixture' -ConfigurationFingerprint 'config-fixture' | Out-Null
  Invoke-Observed 'runner-failure-next' { & $ControllerPath next -StatePath $failedRunState } 'next: BLOCKED'
  $resultReport=Join-Path $root 'result-report.json'; Write-Report $resultReport 'result' $implementationRevision $sutFixture.design 'harness-fixture' 'config-fixture'
  Invoke-Observed 'runner-failure-result-entry' { & $ControllerPath record-verifier -StatePath $failedRunState -VerifyMode result -TestRevision $implementationRevision -SutRevision $sutFixture.design -HarnessRevision 'harness-fixture' -ConfigurationFingerprint 'config-fixture' -ReportPath $resultReport -VerifierId isolated-verifier } 'ERROR_VERIFIER_REVISION'

  [IO.File]::WriteAllText((Join-Path $sut 'drift.txt'),'drift',[Text.UTF8Encoding]::new($false)); Invoke-Git $sut @('add','.'); Invoke-Git $sut @('commit','--quiet','-m','drift')
  $driftState=Join-Path $root 'drift-state.json'; Copy-Item $leasedState $driftState
  Invoke-Observed 'revision-drift' { & $ControllerPath issue-lease -StatePath $driftState -TestRevision $systemFixture.design -SutRevision $sutFixture.design -HarnessRevision 'harness-fixture' -ConfigurationFingerprint 'config-fixture' -Role test-implementer -AgentId drift-agent } 'ERROR_REVISION_DRIFT'

  $report=[ordered]@{ schemaVersion=1; result='PASS'; isolationRootHash=(Get-TextHash $root); controllerHash=(Get-Hash $ControllerPath); generatedAt=[DateTime]::UtcNow.ToString('o'); observations=@($observations) }
  $directory=Split-Path -Parent $OutputPath; if (-not (Test-Path $directory)) { [void](New-Item -ItemType Directory -Path $directory -Force) }
  [IO.File]::WriteAllText($OutputPath, ($report | ConvertTo-Json -Depth 10), [Text.UTF8Encoding]::new($false))
  Write-Output '[ISOLATED_GOAL_FAULTS] PASS'
}
finally {
  if (Test-Path -LiteralPath $root) { Remove-Item -LiteralPath $root -Recurse -Force }
}
