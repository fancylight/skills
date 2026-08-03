$ErrorActionPreference = 'Stop'
$controller = Join-Path (Split-Path -Parent $PSScriptRoot) 'flow-test-controller.ps1'
$root = Join-Path ([IO.Path]::GetTempPath()) ('flow-controller-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $root -Force | Out-Null
$harnessRoot = Join-Path $root 'harness'
New-Item -ItemType Directory -Path $harnessRoot -Force | Out-Null
$harnessFile = Join-Path $harnessRoot 'runner.ps1'
Set-Content -LiteralPath $harnessFile -Value 'Write-Output harness' -Encoding utf8
$harnessCertification = Join-Path $harnessRoot 'certification.json'
$harnessFileHash = (Get-FileHash -LiteralPath $harnessFile -Algorithm SHA256).Hash.ToLowerInvariant()
@{ schemaVersion=1; result='PASS'; harnessRevision='harness-a'; files=@(@{ path='runner.ps1'; sha256=$harnessFileHash }) } | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $harnessCertification -Encoding utf8

function Invoke-Git([string]$Repository, [string[]]$Arguments) {
    $output = @(& git -C $Repository @Arguments 2>&1)
    if ($LASTEXITCODE -ne 0) { throw "git command failed: $($Arguments -join ' ')`n$($output -join [Environment]::NewLine)" }
    return $output
}
function New-GitFixture([string]$Path, [string]$ChangeName) {
    New-Item -ItemType Directory -Path $Path -Force | Out-Null
    Invoke-Git $Path @('init', '--quiet') | Out-Null
    Invoke-Git $Path @('config', 'user.email', 'controller-tests@example.invalid') | Out-Null
    Invoke-Git $Path @('config', 'user.name', 'controller-tests') | Out-Null
    Set-Content -LiteralPath (Join-Path $Path 'README.md') -Value 'baseline' -Encoding utf8
    Invoke-Git $Path @('add', '.') | Out-Null
    Invoke-Git $Path @('commit', '--quiet', '-m', 'baseline') | Out-Null
    $baseline = (Invoke-Git $Path @('rev-parse', 'HEAD') | Select-Object -First 1).Trim()
    $changeDir = Join-Path $Path "changes\$ChangeName"
    New-Item -ItemType Directory -Path $changeDir -Force | Out-Null
    Set-Content -LiteralPath (Join-Path $changeDir 'design.md') -Value 'design' -Encoding utf8
    Invoke-Git $Path @('add', '.') | Out-Null
    Invoke-Git $Path @('commit', '--quiet', '-m', 'design') | Out-Null
    $design = (Invoke-Git $Path @('rev-parse', 'HEAD') | Select-Object -First 1).Trim()
    [pscustomobject]@{ path = $Path; change = $ChangeName; baseline = $baseline; design = $design }
}
function Commit-Implementation([string]$Repository, [string]$ChangeName, [bool]$IncludeOutOfScope = $false, [string]$FileName = 'test.java') {
    $changeDir = Join-Path $Repository "changes\$ChangeName"
    Set-Content -LiteralPath (Join-Path $changeDir $FileName) -Value ('implementation-' + [guid]::NewGuid().ToString('N')) -Encoding utf8
    if ($IncludeOutOfScope) { Set-Content -LiteralPath (Join-Path $Repository 'outside.txt') -Value 'out-of-scope' -Encoding utf8 }
    Invoke-Git $Repository @('add', '.') | Out-Null
    Invoke-Git $Repository @('commit', '--quiet', '-m', 'implementation') | Out-Null
    return (Invoke-Git $Repository @('rev-parse', 'HEAD') | Select-Object -First 1).Trim()
}
function Get-DiffFixture([string]$Repository, [string]$Baseline, [string]$Current) {
    $changed = @(Invoke-Git $Repository @('diff', '--name-only', '--diff-filter=ACDMRTUXB', $Baseline, $Current) | ForEach-Object { $_.Trim().Replace('\','/') } | Where-Object { $_ })
    $diffText = (@(Invoke-Git $Repository @('diff', '--no-ext-diff', '--binary', '--full-index', $Baseline, $Current)) -join "`n")
    $bytes = [Text.Encoding]::UTF8.GetBytes($diffText); $sha = [Security.Cryptography.SHA256]::Create()
    try { $hash = (-join ($sha.ComputeHash($bytes) | ForEach-Object { $_.ToString('x2') })) } finally { $sha.Dispose() }
    [pscustomobject]@{ changedFiles = @($changed | Sort-Object -Unique); diffHash = $hash }
}
 $script:assertCount = 0
function Assert-Controller([scriptblock]$Call, [bool]$ExpectPass = $true, [string]$Marker = 'PASS', [string]$Name = 'controller') {
    $script:assertCount++
    if ($Name -eq 'controller') { $Name = "controller-$script:assertCount" }
    $output = & $Call 2>&1
    $ok = @($output | Where-Object { $_ -match '^\[FLOW_CONTROLLER\] ERROR' }).Count -eq 0
    if ($ok -ne $ExpectPass -or -not (@($output | Where-Object { $_ -match [regex]::Escape($Marker) }).Count -gt 0)) { throw "Unexpected controller result ($Name): $($output -join [Environment]::NewLine)" }
}
function Write-VerifierReport([string]$Path, [string]$Mode, [string]$Identity, [string]$Test, [string]$Sut, [string]$Harness, [string]$Config, [string]$Summary = 'verification passed', [string]$Base = '') {
    $report = [ordered]@{ result='PASS'; mode=$Mode; verifierId=$Identity; testRevision=$Test; sutRevision=$Sut; harnessRevision=$Harness; configurationFingerprint=$Config; summary=$Summary }
    if ($Base) { $report.implementationBaseRevision = $Base }
    $report | ConvertTo-Json | Set-Content -LiteralPath $Path -Encoding utf8
}
function Re-sign-State([string]$Path, $StateObject) {
    $StateObject.integrityHash = ''
    $bytes = [Text.Encoding]::UTF8.GetBytes(($StateObject | ConvertTo-Json -Depth 16 -Compress)); $sha = [Security.Cryptography.SHA256]::Create()
    try { $StateObject.integrityHash = (-join ($sha.ComputeHash($bytes) | ForEach-Object { $_.ToString('x2') })) } finally { $sha.Dispose() }
    $StateObject | ConvertTo-Json -Depth 16 | Set-Content -LiteralPath $Path -Encoding utf8
}
function New-LeasedCase([string]$Name, [string]$ChangeName = 'sample-change', [string]$Authorization = 'result', [int]$LeaseMinutes = 30) {
    $repo = Join-Path $root "$Name-system"; $sut = Join-Path $root "$Name-sut"; $state = Join-Path $root "$Name-state.json"
    $fixture = New-GitFixture $repo $ChangeName; $sutFixture = New-GitFixture $sut ($Name + '-sut')
    $designReport = Join-Path $root ('design-' + [guid]::NewGuid().ToString('N') + '.json')
    Write-VerifierReport $designReport 'design' 'verifier-a' $fixture.design $sutFixture.design 'harness-a' 'config-a'
    Assert-Controller { & $controller initialize -StatePath $state -ChangeName $ChangeName -SystemTestRepo $repo -SutRepo $sut -TestBaselineRevision $fixture.baseline -TestRevision $fixture.design -SutRevision $sutFixture.design -HarnessRevision harness-a -HarnessRoot $harnessRoot -HarnessCertificationPath $harnessCertification -ConfigurationFingerprint config-a -Authorization $Authorization }
    Assert-Controller { & $controller record-verifier -StatePath $state -VerifyMode design -TestRevision $fixture.design -SutRevision $sutFixture.design -HarnessRevision harness-a -ConfigurationFingerprint config-a -ReportPath $designReport -VerifierId verifier-a }
    if ($Authorization -eq 'design') {
        Assert-Controller { & $controller issue-lease -StatePath $state -TestRevision $fixture.design -SutRevision $sutFixture.design -HarnessRevision harness-a -ConfigurationFingerprint config-a -Role test-implementer -AgentId agent-a } $false 'ERROR_AUTHORIZATION' "$Name-authorization-ceiling"
    } else {
        Assert-Controller { & $controller issue-lease -StatePath $state -TestRevision $fixture.design -SutRevision $sutFixture.design -HarnessRevision harness-a -ConfigurationFingerprint config-a -Role test-implementer -AgentId agent-a -LeaseMinutes $LeaseMinutes }
    }
    [pscustomobject]@{ repo=$repo; sut=$sut; state=$state; fixture=$fixture; sutFixture=$sutFixture; designReport=$designReport; sutRevision=$sutFixture.design; harness='harness-a'; config='config-a' }
}
try {
    $system = Join-Path $root 'system-test'; $sut = Join-Path $root 'sut'; $state = Join-Path $root 'automation-state.json'
    $fixture = New-GitFixture $system 'sample-change'; $sutFixture = New-GitFixture $sut 'sample-sut'
    $designReport = Join-Path $root 'design.json'; $implementationReport = Join-Path $root 'implementation.json'; $environmentReport = Join-Path $root 'environment.json'; $resultReport = Join-Path $root 'result.json'; $scope = Join-Path $root 'scope.json'; $evidence = Join-Path $root 'evidence'; New-Item -ItemType Directory -Path $evidence -Force | Out-Null
    $harness = 'harness-a'; $config = 'config-a'; $sutRevision = $sutFixture.design

    # Real lifecycle: design commit -> initialize -> lease -> implementation commit -> accept.
    Write-VerifierReport $designReport 'design' 'verifier-a' $fixture.design $sutRevision $harness $config
    Assert-Controller { & $controller initialize -StatePath $state -ChangeName sample-change -SystemTestRepo $system -SutRepo $sut -TestBaselineRevision $fixture.baseline -TestRevision $fixture.design -SutRevision $sutRevision -HarnessRevision $harness -HarnessRoot $harnessRoot -HarnessCertificationPath $harnessCertification -ConfigurationFingerprint $config -Authorization result }
    $initialized = Get-Content $state -Raw | ConvertFrom-Json
    if ($initialized.revisions.designRevision -ne $fixture.design -or $initialized.revisions.testBaseRevision -ne $fixture.design) { throw 'initialize did not lock design/test base revision' }
    Assert-Controller { & $controller record-verifier -StatePath $state -VerifyMode design -TestRevision $fixture.design -SutRevision $sutRevision -HarnessRevision $harness -ConfigurationFingerprint $config -ReportPath $designReport -VerifierId verifier-a }
    Assert-Controller { & $controller issue-lease -StatePath $state -TestRevision $fixture.design -SutRevision $sutRevision -HarnessRevision $harness -ConfigurationFingerprint $config -Role test-implementer -AgentId agent-a }
    $lease = (Get-Content $state -Raw | ConvertFrom-Json).leases[0]
    if ($lease.implementationBaseRevision -ne $fixture.design) { throw 'lease did not record implementation base revision' }
    Assert-Controller { & $controller validate-lease -StatePath $state -LeaseId $lease.leaseId -AgentId agent-a -Role test-implementer -Capabilities write-test-artifact -TargetPath (Join-Path $system 'changes/sample-change/test.java') }
    Assert-Controller { & $controller validate-lease -StatePath $state -LeaseId $lease.leaseId -AgentId agent-a -Role test-implementer -Capabilities start-service -TargetPath (Join-Path $system 'changes/sample-change/test.java') } $false 'ERROR_CAPABILITY_FORBIDDEN' 'forbidden-capability'
    Assert-Controller { & $controller validate-lease -StatePath $state -LeaseId $lease.leaseId -AgentId agent-a -Capabilities write-test-artifact -TargetPath (Join-Path $system 'backend-tests/src/test/foo/sample-change/Test.java') }
    Assert-Controller { & $controller validate-lease -StatePath $state -LeaseId $lease.leaseId -AgentId agent-a -Capabilities write-test-artifact -TargetPath (Join-Path $system 'backend-tests/src/test/sample-change/Test.java') }
    $implementationRevision = Commit-Implementation $system 'sample-change'
    $diff = Get-DiffFixture $system $fixture.design $implementationRevision
    Write-VerifierReport $implementationReport 'implementation' 'verifier-a' $implementationRevision $sutRevision $harness $config 'implementation verification passed' $fixture.design
    @{ result='PASS'; baselineRevision=$fixture.design; currentRevision=$implementationRevision; repository=[IO.Path]::GetFullPath($system); changedFiles=$diff.changedFiles; diffHash=$diff.diffHash; scopePass=$false } | ConvertTo-Json | Set-Content -LiteralPath $scope -Encoding utf8
    @{ result='PASS'; testRevision=$implementationRevision; implementationBaseRevision=$fixture.design; scopePass=$false } | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $root 'implementation-result.json') -Encoding utf8
    Assert-Controller { & $controller accept-result -StatePath $state -ProposedTestRevision $implementationRevision -SutRevision $sutRevision -HarnessRevision $harness -ConfigurationFingerprint $config -ReportPath (Join-Path $root 'implementation-result.json') -ScopeGuardReportPath $scope }
    $accepted = Get-Content $state -Raw | ConvertFrom-Json
    if ($accepted.revisions.test -ne $implementationRevision -or $accepted.scopeVerification.baselineRevision -ne $fixture.design) { throw 'accept-result did not atomically advance test revision from lease base' }
    Assert-Controller { & $controller record-verifier -StatePath $state -VerifyMode implementation -TestRevision $fixture.design -SutRevision $sutRevision -HarnessRevision $harness -ConfigurationFingerprint $config -ReportPath $implementationReport -VerifierId verifier-a } $false 'ERROR_REVISION_DRIFT' 'old-test-revision-verifier'
    Assert-Controller { & $controller record-verifier -StatePath $state -VerifyMode implementation -TestRevision $implementationRevision -SutRevision $sutRevision -HarnessRevision $harness -ConfigurationFingerprint $config -ReportPath $implementationReport -VerifierId verifier-a }
    Write-VerifierReport $environmentReport 'environment' 'verifier-a' $implementationRevision $sutRevision $harness $config
    Assert-Controller { & $controller record-verifier -StatePath $state -VerifyMode environment -TestRevision $implementationRevision -SutRevision $sutRevision -HarnessRevision $harness -ConfigurationFingerprint $config -ReportPath $environmentReport -VerifierId verifier-a }
    Assert-Controller { & $controller start-run -StatePath $state -TestRevision $implementationRevision -SutRevision $sutRevision -HarnessRevision $harness -ConfigurationFingerprint $config }
    Assert-Controller { & $controller record-run -StatePath $state -RunResult pass -EvidencePath $evidence -TestRevision $implementationRevision -SutRevision $sutRevision -HarnessRevision $harness -ConfigurationFingerprint $config }
    Write-VerifierReport $resultReport 'result' 'verifier-a' $implementationRevision $sutRevision $harness $config
    Assert-Controller { & $controller record-verifier -StatePath $state -VerifyMode result -TestRevision $implementationRevision -SutRevision $sutRevision -HarnessRevision $harness -ConfigurationFingerprint $config -ReportPath $resultReport -VerifierId verifier-a }
    $final = Get-Content $state -Raw | ConvertFrom-Json
    if ($final.phase -ne 'TEST_RESULT_VERIFIED' -or $final.runs[0].testRevision -ne $implementationRevision) { throw 'downstream lifecycle did not bind accepted test revision' }
    if ((Get-Content $state -Raw) -match 'verification passed|password|token|connectionstring') { throw 'unsafe verifier data entered state' }
    Assert-Controller { & $controller start-run -StatePath $state -TestRevision $implementationRevision -SutRevision $sutRevision -HarnessRevision $harness -ConfigurationFingerprint $config } $false 'ERROR_RUN_DUPLICATE' 'duplicate-run-after-result'
    Assert-Controller { & $controller start-run -StatePath $state -TestRevision $implementationRevision -SutRevision $sutRevision -HarnessRevision $harness -ConfigurationFingerprint wrong-config } $false 'ERROR_CONFIGURATION_DRIFT' 'runner-configuration-drift'
    Set-Content -LiteralPath $harnessFile -Value 'Write-Output changed' -Encoding utf8
    Assert-Controller { & $controller start-run -StatePath $state -TestRevision $implementationRevision -SutRevision $sutRevision -HarnessRevision $harness -ConfigurationFingerprint $config } $false 'ERROR_HARNESS_UNCERTIFIED' 'stale-harness-certification'
    Set-Content -LiteralPath $harnessFile -Value 'Write-Output harness' -Encoding utf8

    $uncertifiedState = Join-Path $root 'uncertified-state.json'
    Assert-Controller { & $controller initialize -StatePath $uncertifiedState -ChangeName uncertified -SystemTestRepo $system -SutRepo $sut -TestBaselineRevision $fixture.baseline -TestRevision $implementationRevision -SutRevision $sutRevision -HarnessRevision unknown-harness -HarnessRoot $harnessRoot -HarnessCertificationPath $harnessCertification -ConfigurationFingerprint $config -Authorization result } $false 'ERROR_HARNESS_UNCERTIFIED' 'uncertified-harness-revision'

    # Authorization and revision-lock negatives.
    $ceiling = New-LeasedCase 'ceiling' 'ceiling-change' 'design'
    Assert-Controller { & $controller record-verifier -StatePath $ceiling.state -VerifyMode implementation -TestRevision $ceiling.fixture.design -SutRevision $ceiling.sutRevision -HarnessRevision $ceiling.harness -ConfigurationFingerprint $ceiling.config -ReportPath $implementationReport -VerifierId verifier-a } $false 'ERROR_AUTHORIZATION' 'authorization-ceiling'

    $noRevision = New-LeasedCase 'no-revision'
    $emptyDiff = Get-DiffFixture $noRevision.repo $noRevision.fixture.design $noRevision.fixture.design
    $noScope = Join-Path $root 'no-revision-scope.json'; $noResult = Join-Path $root 'no-revision-result.json'
    @{ result='PASS'; baselineRevision=$noRevision.fixture.design; currentRevision=$noRevision.fixture.design; repository=$noRevision.repo; changedFiles=@(); diffHash=$emptyDiff.diffHash } | ConvertTo-Json | Set-Content $noScope -Encoding utf8
    @{ result='PASS'; testRevision=$noRevision.fixture.design; implementationBaseRevision=$noRevision.fixture.design } | ConvertTo-Json | Set-Content $noResult -Encoding utf8
    Assert-Controller { & $controller accept-result -StatePath $noRevision.state -ProposedTestRevision $noRevision.fixture.design -SutRevision $noRevision.sutRevision -HarnessRevision $noRevision.harness -ConfigurationFingerprint $noRevision.config -ReportPath $noResult -ScopeGuardReportPath $noScope } $false 'ERROR_NO_IMPLEMENTATION_REVISION' 'no-new-revision'

    $notHead = New-LeasedCase 'not-head'
    $first = Commit-Implementation $notHead.repo 'sample-change'; $second = Commit-Implementation $notHead.repo 'sample-change' $false 'test-2.java'; $notHeadDiff = Get-DiffFixture $notHead.repo $notHead.fixture.design $first
    $notHeadScope = Join-Path $root 'not-head-scope.json'; $notHeadResult = Join-Path $root 'not-head-result.json'
    @{ result='PASS'; baselineRevision=$notHead.fixture.design; currentRevision=$first; repository=$notHead.repo; changedFiles=$notHeadDiff.changedFiles; diffHash=$notHeadDiff.diffHash } | ConvertTo-Json | Set-Content $notHeadScope -Encoding utf8
    @{ result='PASS'; testRevision=$first; implementationBaseRevision=$notHead.fixture.design } | ConvertTo-Json | Set-Content $notHeadResult -Encoding utf8
    Assert-Controller { & $controller accept-result -StatePath $notHead.state -ProposedTestRevision $first -SutRevision $notHead.sutRevision -HarnessRevision $notHead.harness -ConfigurationFingerprint $notHead.config -ReportPath $notHeadResult -ScopeGuardReportPath $notHeadScope } $false 'ERROR_REVISION_DRIFT' 'proposed-not-head'

    $nonDesc = New-LeasedCase 'non-descendant'; Invoke-Git $nonDesc.repo @('checkout', '--quiet', $nonDesc.fixture.baseline) | Out-Null; Set-Content (Join-Path $nonDesc.repo 'unrelated.txt') 'unrelated' -Encoding utf8; Invoke-Git $nonDesc.repo @('add', '.') | Out-Null; Invoke-Git $nonDesc.repo @('commit', '--quiet', '-m', 'unrelated') | Out-Null; $unrelated = (Invoke-Git $nonDesc.repo @('rev-parse', 'HEAD') | Select-Object -First 1).Trim()
    $nonDiff = Get-DiffFixture $nonDesc.repo $nonDesc.fixture.design $unrelated
    $nonScope = Join-Path $root 'non-desc-scope.json'; $nonResult = Join-Path $root 'non-desc-result.json'
    @{ result='PASS'; baselineRevision=$nonDesc.fixture.design; currentRevision=$unrelated; repository=$nonDesc.repo; changedFiles=$nonDiff.changedFiles; diffHash=$nonDiff.diffHash } | ConvertTo-Json | Set-Content $nonScope -Encoding utf8
    @{ result='PASS'; testRevision=$unrelated; implementationBaseRevision=$nonDesc.fixture.design } | ConvertTo-Json | Set-Content $nonResult -Encoding utf8
    Assert-Controller { & $controller accept-result -StatePath $nonDesc.state -ProposedTestRevision $unrelated -SutRevision $nonDesc.sutRevision -HarnessRevision $nonDesc.harness -ConfigurationFingerprint $nonDesc.config -ReportPath $nonResult -ScopeGuardReportPath $nonScope } $false 'ERROR_REVISION_ANCESTRY' 'non-descendant'

    foreach ($kind in @('unstaged','staged','untracked')) {
        $dirty = New-LeasedCase "dirty-$kind"; $dirtyRevision = Commit-Implementation $dirty.repo 'sample-change'; $dirtyDiff = Get-DiffFixture $dirty.repo $dirty.fixture.design $dirtyRevision
        if ($kind -eq 'unstaged') { Add-Content (Join-Path $dirty.repo 'changes/sample-change/test.java') 'dirty' }
        elseif ($kind -eq 'staged') { Set-Content (Join-Path $dirty.repo 'changes/sample-change/staged.java') 'staged' -Encoding utf8; Invoke-Git $dirty.repo @('add', '.') | Out-Null }
        else { Set-Content (Join-Path $dirty.repo 'untracked.txt') 'untracked' -Encoding utf8 }
        $dirtyScope = Join-Path $root "$kind-scope.json"; $dirtyResult = Join-Path $root "$kind-result.json"
        @{ result='PASS'; baselineRevision=$dirty.fixture.design; currentRevision=$dirtyRevision; repository=$dirty.repo; changedFiles=$dirtyDiff.changedFiles; diffHash=$dirtyDiff.diffHash } | ConvertTo-Json | Set-Content $dirtyScope -Encoding utf8
        @{ result='PASS'; testRevision=$dirtyRevision; implementationBaseRevision=$dirty.fixture.design } | ConvertTo-Json | Set-Content $dirtyResult -Encoding utf8
        Assert-Controller { & $controller accept-result -StatePath $dirty.state -ProposedTestRevision $dirtyRevision -SutRevision $dirty.sutRevision -HarnessRevision $dirty.harness -ConfigurationFingerprint $dirty.config -ReportPath $dirtyResult -ScopeGuardReportPath $dirtyScope } $false 'ERROR_SCOPE_WORKTREE_DIRTY' "dirty-$kind"
    }

    $out = New-LeasedCase 'out-of-scope'; $outRevision = Commit-Implementation $out.repo 'sample-change' $true; $outDiff = Get-DiffFixture $out.repo $out.fixture.design $outRevision; $outScope = Join-Path $root 'out-scope.json'; $outResult = Join-Path $root 'out-result.json'
    @{ result='PASS'; baselineRevision=$out.fixture.design; currentRevision=$outRevision; repository=$out.repo; changedFiles=$outDiff.changedFiles; diffHash=$outDiff.diffHash } | ConvertTo-Json | Set-Content $outScope -Encoding utf8
    @{ result='PASS'; testRevision=$outRevision; implementationBaseRevision=$out.fixture.design } | ConvertTo-Json | Set-Content $outResult -Encoding utf8
    Assert-Controller { & $controller accept-result -StatePath $out.state -ProposedTestRevision $outRevision -SutRevision $out.sutRevision -HarnessRevision $out.harness -ConfigurationFingerprint $out.config -ReportPath $outResult -ScopeGuardReportPath $outScope } $false 'ERROR_SCOPE' 'out-of-scope-diff'

    $fake = New-LeasedCase 'fake-scope'; $fakeRevision = Commit-Implementation $fake.repo 'sample-change'; $fakeDiff = Get-DiffFixture $fake.repo $fake.fixture.design $fakeRevision; $fakeScope = Join-Path $root 'fake-scope.json'; $fakeResult = Join-Path $root 'fake-result.json'
    @{ result='PASS'; scopePass=$true } | ConvertTo-Json | Set-Content $fakeScope -Encoding utf8; @{ result='PASS'; testRevision=$fakeRevision; implementationBaseRevision=$fake.fixture.design } | ConvertTo-Json | Set-Content $fakeResult -Encoding utf8
    Assert-Controller { & $controller accept-result -StatePath $fake.state -ProposedTestRevision $fakeRevision -SutRevision $fake.sutRevision -HarnessRevision $fake.harness -ConfigurationFingerprint $fake.config -ReportPath $fakeResult -ScopeGuardReportPath $fakeScope } $false 'ERROR_SCOPE' 'forged-scope-pass'
    @{ result='PASS'; baselineRevision=$fake.fixture.design; currentRevision=$fakeRevision; repository=$fake.repo; changedFiles=$fakeDiff.changedFiles; diffHash=('0' * 64) } | ConvertTo-Json | Set-Content $fakeScope -Encoding utf8
    Assert-Controller { & $controller accept-result -StatePath $fake.state -ProposedTestRevision $fakeRevision -SutRevision $fake.sutRevision -HarnessRevision $fake.harness -ConfigurationFingerprint $fake.config -ReportPath $fakeResult -ScopeGuardReportPath $fakeScope } $false 'ERROR_SCOPE_DIFF_HASH' 'diff-hash-mismatch'

    $sutDrift = New-LeasedCase 'sut-drift'; Set-Content (Join-Path $sutDrift.sut 'drift.txt') 'drift' -Encoding utf8; Invoke-Git $sutDrift.sut @('add', '.') | Out-Null; Invoke-Git $sutDrift.sut @('commit', '--quiet', '-m', 'sut drift') | Out-Null
    Assert-Controller { & $controller issue-lease -StatePath $sutDrift.state -TestRevision $sutDrift.fixture.design -SutRevision $sutDrift.sutRevision -HarnessRevision $sutDrift.harness -ConfigurationFingerprint $sutDrift.config -Role test-implementer -AgentId agent-a } $false 'ERROR_REVISION_DRIFT' 'sut-head-drift'

    $secretRepo = Join-Path $root 'secret-system'; $secretSut = Join-Path $root 'secret-sut'; $secretFixture = New-GitFixture $secretRepo 'safe-change'; $secretSutFixture = New-GitFixture $secretSut 'safe-sut-change'; $secretState = Join-Path $root 'secret-state.json'; $secretReport = Join-Path $root 'verifier-input.json'; Write-VerifierReport $secretReport 'design' 'verifier-a' $secretFixture.design $secretSutFixture.design $harness $config 'password=must-not-enter-state'; Assert-Controller { & $controller initialize -StatePath $secretState -ChangeName safe-change -SystemTestRepo $secretRepo -SutRepo $secretSut -TestBaselineRevision $secretFixture.baseline -TestRevision $secretFixture.design -SutRevision $secretSutFixture.design -HarnessRevision $harness -HarnessRoot $harnessRoot -HarnessCertificationPath $harnessCertification -ConfigurationFingerprint $config -Authorization result }; Assert-Controller { & $controller record-verifier -StatePath $secretState -VerifyMode design -TestRevision $secretFixture.design -SutRevision $secretSutFixture.design -HarnessRevision $harness -ConfigurationFingerprint $config -ReportPath $secretReport -VerifierId verifier-a } $false 'ERROR_SECRET_INPUT' 'secret-summary'
    $secretText = Get-Content $secretState -Raw; if ($secretText -match '(?i)password|token|connectionstring') { throw 'secret appeared in state' }

    $expired = New-LeasedCase 'expired' 'expired-change' 'result' -1; $expiredLease = (Get-Content $expired.state -Raw | ConvertFrom-Json).leases[0]
    Assert-Controller { & $controller validate-lease -StatePath $expired.state -LeaseId $expiredLease.leaseId -AgentId agent-a -Role test-implementer -Capabilities read -TargetPath (Join-Path $expired.repo 'changes/expired-change/test.java') } $false 'ERROR_LEASE_INVALID' 'expired-lease'

    $atomic = New-LeasedCase 'atomic'; $atomicRevision = Commit-Implementation $atomic.repo 'sample-change'; $atomicDiff = Get-DiffFixture $atomic.repo $atomic.fixture.design $atomicRevision; $atomicScope = Join-Path $root 'atomic-scope.json'; $atomicResult = Join-Path $root 'atomic-result.json'; @{ result='PASS'; baselineRevision=$atomic.fixture.design; currentRevision=$atomicRevision; repository=$atomic.repo; changedFiles=$atomicDiff.changedFiles; diffHash=$atomicDiff.diffHash } | ConvertTo-Json | Set-Content $atomicScope -Encoding utf8; @{ result='PASS'; testRevision=$atomicRevision; implementationBaseRevision=$atomic.fixture.design } | ConvertTo-Json | Set-Content $atomicResult -Encoding utf8
    Assert-Controller { & $controller accept-result -StatePath $atomic.state -ProposedTestRevision $atomicRevision -SutRevision $atomic.sutRevision -HarnessRevision $atomic.harness -ConfigurationFingerprint $atomic.config -ReportPath $atomicResult -ScopeGuardReportPath $atomicScope -SimulateWriteFailure } $false 'ERROR_ATOMIC_WRITE' 'accept-write-failure'
    $atomicBefore = (Get-Content $atomic.state -Raw | ConvertFrom-Json).revisions.test; if ($atomicBefore -ne $atomic.fixture.design) { throw 'failed atomic accept changed state' }

    # Backup recovery and corrupted-state guard.
    $tampered = Get-Content $state -Raw | ConvertFrom-Json; $tampered.phase = 'TEST_EXECUTING'; $tampered | ConvertTo-Json -Depth 16 | Set-Content $state -Encoding utf8
    Assert-Controller { & $controller status -StatePath $state } $true '"phase":  "TEST_RESULT_VERIFIED"' 'backup-recovery'
    Set-Content $state '{ bad json' -Encoding utf8; Set-Content "$state.bak" '{ bad backup' -Encoding utf8
    Assert-Controller { & $controller status -StatePath $state } $false 'ERROR_STATE_CORRUPT' 'corrupt-state'
    Write-Output 'flow-test-controller tests passed'
} finally { Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue }
