# Included by test-flow-test-controller.ps1 after its real harness certification.
$initialRepo = New-GitFixture (Join-Path $root 'initial-user-grant-system') 'initial-user-grant'
$initialSut = New-GitFixture (Join-Path $root 'initial-user-grant-sut') 'sut'
$initialManifest = Join-Path $initialRepo.path 'changes/initial-user-grant/manifest.yaml'
Set-Content $initialManifest '{"stage":"design","testAuthorization":{"ceiling":"result","grantedBy":"user"}}' -Encoding utf8
Invoke-Git $initialRepo.path @('add','.') | Out-Null
Invoke-Git $initialRepo.path @('commit','--quiet','-m','initial user grant') | Out-Null
$initialHead = (Invoke-Git $initialRepo.path @('rev-parse','HEAD') | Select-Object -First 1).Trim()
$initialArgs = @{StatePath=(Join-Path $root 'initial-user-grant-state.json');ChangeName='initial-user-grant';SystemTestRepo=$initialRepo.path;SutRepo=$initialSut.path;TestBaselineRevision=$initialRepo.baseline;TestRevision=$initialHead;SutRevision=$initialSut.design;HarnessRevision=$harness;HarnessRoot=$harnessRoot;HarnessCertificationPath=$harnessCertification;ConfigurationFingerprint='config-a'}
Assert-Controller { & $controller initialize @initialArgs -Authorization result } $false 'ERROR_INPUT' 'initial-high-ceiling-needs-grant'
Assert-Controller { & $controller initialize @initialArgs -Authorization design } $false 'ERROR_AUTHORIZATION' 'initial-manifest-ceiling-mismatch'
$initialGrantPath = Join-Path $root 'initial-explicit-grant.json'
Write-Grant $initialGrantPath 'initial-user-grant' 'none' 'result' $initialHead $initialSut.design
Assert-Controller { & $controller initialize @initialArgs -Authorization result -ReportPath $initialGrantPath }
$initialState = Get-Content $initialArgs.StatePath -Raw | ConvertFrom-Json
if ($initialState.phase -ne 'TEST_DESIGN_DRAFT' -or $initialState.authorization.maxPhase -ne 'result') { throw 'initial high ceiling must not advance design phase' }
Assert-Controller { & $controller initialize @initialArgs -Authorization result -ReportPath $initialGrantPath } $false 'ERROR_STATE_EXISTS' 'initial-grant-no-reset'
$grantCase = New-LeasedCase 'grant-upgrade' 'grant-upgrade' 'design'
$locks = @{ StatePath=$grantCase.state; TestRevision=$grantCase.fixture.design; SutRevision=$grantCase.sutRevision; HarnessRevision=$harness; ConfigurationFingerprint='config-a' }
$grantFile = Join-Path $root 'additional-user-grant.json'
$beforeGrant = Get-Content $grantCase.state -Raw | ConvertFrom-Json
Assert-Controller { & $controller next -StatePath $grantCase.state } $true 'STOP_AWAIT_USER_AUTHORIZATION' 'next-obeys-ceiling'
Assert-Controller { & $controller grant-authorization @locks -Authorization execution } $false 'ERROR_INPUT' 'grant-needs-user-record'
Write-Grant $grantFile 'grant-upgrade' 'design' 'execution' $grantCase.fixture.design $grantCase.sutRevision
$validGrant = Get-Content $grantFile -Raw
foreach ($field in @('grantedBy','requestText','requestRef','testRevision','sutRevision','harnessRevision','configurationFingerprint','previousCeiling','changeName')) {
    $bad = $validGrant | ConvertFrom-Json
    $bad.$field = ''
    $bad | ConvertTo-Json | Set-Content $grantFile -Encoding utf8
    Assert-Controller { & $controller grant-authorization @locks -Authorization execution -ReportPath $grantFile } $false 'ERROR_AUTHORIZATION' "grant-invalid-$field"
}
Set-Content $grantFile $validGrant -Encoding utf8
$driftLocks = @{} + $locks; $driftLocks.ConfigurationFingerprint = 'wrong-config'
Assert-Controller { & $controller grant-authorization @driftLocks -Authorization execution -ReportPath $grantFile } $false 'ERROR_CONFIGURATION_DRIFT' 'grant-lock-drift'
Assert-Controller { & $controller grant-authorization @locks -Authorization execution -ReportPath $grantFile -SimulateWriteFailure } $false 'ERROR_ATOMIC_WRITE' 'grant-atomic-rejection'
Assert-Controller { & $controller grant-authorization @locks -Authorization execution -ReportPath $grantFile }
$afterGrant = Get-Content $grantCase.state -Raw | ConvertFrom-Json
foreach ($field in @('phase','revisions','harnessCertification','configurationFingerprint','leases','runs','verifier','failureFingerprints')) {
    if (($beforeGrant.$field | ConvertTo-Json -Depth 16 -Compress) -ne ($afterGrant.$field | ConvertTo-Json -Depth 16 -Compress)) { throw "grant changed $field" }
}
if ($afterGrant.authorization.maxPhase -ne 'execution' -or @($afterGrant.authorization.grants).Count -ne 2) { throw 'grant did not preserve initial audit and add upgrade' }
Assert-Controller { & $controller grant-authorization @locks -Authorization design -ReportPath $grantFile } $false 'ERROR_AUTHORIZATION' 'grant-no-downgrade'
Assert-Controller { & $controller grant-authorization @locks -Authorization execution -ReportPath $grantFile } $false 'ERROR_AUTHORIZATION' 'grant-no-replay'
Assert-Controller { & $controller next -StatePath $grantCase.state } $true 'ISSUE_IMPLEMENTATION_LEASE' 'upgrade-unblocks-same-phase'

# Legacy design already verified: explicitly reopen, keep the old verifier, update only design artifacts.
$migration = New-LeasedCase 'business-migration' 'business-migration' 'design'
$migrationLocks = @{StatePath=$migration.state;TestRevision=$migration.fixture.design;SutRevision=$migration.sutRevision;HarnessRevision=$harness;ConfigurationFingerprint='config-a'}
$changeDir = Join-Path $migration.repo 'changes/business-migration'
$fullCases = Get-Content (Join-Path $PSScriptRoot 'fixtures/business-cases.yaml') -Raw -Encoding utf8
$legacyCases = [regex]::Replace($fullCases, '(?ms)^    business:.*?(?=^    suite:)', '')
# Construct historical files in the fixture only, then initialize a separate state at that real commit.
Set-Content (Join-Path $changeDir 'test-cases.yaml') $legacyCases -Encoding utf8
Set-Content (Join-Path $changeDir 'test-design.md') '# Planned design' -Encoding utf8
Set-Content (Join-Path $changeDir 'test-plan.md') "> system-test path: $($migration.repo)`n<!-- FLOW_TEST_CASES_GENERATED:START -->`n<!-- FLOW_TEST_CASES_GENERATED:END -->" -Encoding utf8
Set-Content (Join-Path $changeDir 'manifest.yaml') '{"stage":"design","testAuthorization":{"ceiling":"design","grantedBy":"user"},"testCasesContract":{"path":"test-cases.generated.json"},"configurationSource":"user-confirmed","requiredEndpoints":["database"],"connectivityProbe":"SELECT 1","ownership":"environment-owner"}' -Encoding utf8
New-Item -ItemType Directory -Path (Join-Path $changeDir 'fixtures') | Out-Null
Set-Content (Join-Path $changeDir 'fixtures/ids.yaml') 'fixture_marker: TEST' -Encoding utf8
Set-Content (Join-Path $changeDir 'fixtures/seed.sql') "INSERT INTO t (marker) VALUES ('TEST');" -Encoding utf8
Set-Content (Join-Path $changeDir 'fixtures/cleanup.sql') "-- fixture marker`nDELETE FROM t WHERE marker='TEST';" -Encoding utf8
$generation = @{TestCasesPath=(Join-Path $changeDir 'test-cases.yaml');TestPlanPath=(Join-Path $changeDir 'test-plan.md');ManifestPath=(Join-Path $changeDir 'manifest.yaml');DerivedContractPath=(Join-Path $changeDir 'test-cases.generated.json');CanonicalRevision=$migration.fixture.baseline;Generate=$true}
$caseValidator = Join-Path $PSScriptRoot '../validate-test-cases.ps1'
& $caseValidator @generation | Out-Null
if ($LASTEXITCODE -ne 0) { throw 'legacy migration fixture generation failed' }
Invoke-Git $migration.repo @('add','.') | Out-Null
Invoke-Git $migration.repo @('commit','--quiet','-m','historical design') | Out-Null
$oldRevision = (Invoke-Git $migration.repo @('rev-parse','HEAD') | Select-Object -First 1).Trim()
$migrationLocks.StatePath = Join-Path $root 'historical-design-state.json'
$migrationLocks.TestRevision = $oldRevision
Assert-Controller { & $controller initialize @migrationLocks -ChangeName business-migration -SystemTestRepo $migration.repo -SutRepo $migration.sut -TestBaselineRevision $migration.fixture.baseline -HarnessRoot $harnessRoot -HarnessCertificationPath $harnessCertification }
$historicalReport = Join-Path $root 'historical-review.json'
Write-VerifierReport $historicalReport 'design' 'self' $oldRevision $migration.sutRevision $harness 'config-a'
Assert-Controller { & $controller record-verifier @migrationLocks -VerifyMode design -VerifierId self -ReportPath $historicalReport }
Assert-Controller { & $controller reopen-design @migrationLocks -Reason 'business coverage revalidation' }
$reopened = Get-Content $migrationLocks.StatePath -Raw | ConvertFrom-Json
if ($reopened.phase -ne 'TEST_DESIGN_DRAFT' -or $null -ne $reopened.verifier -or $reopened.designRevisions[0].verifier.identity -ne 'self') { throw 'reopen did not invalidate and preserve historical review' }
Set-Content (Join-Path $changeDir 'test-cases.yaml') $fullCases -Encoding utf8
& $caseValidator @generation -RequireBusiness | Out-Null
if ($LASTEXITCODE -ne 0) { throw 'business migration generation failed' }
Invoke-Git $migration.repo @('add','.') | Out-Null
Invoke-Git $migration.repo @('commit','--quiet','-m','business cases and independent expectations') | Out-Null
$newRevision = (Invoke-Git $migration.repo @('rev-parse','HEAD') | Select-Object -First 1).Trim()
Assert-Controller { & $controller accept-design-revision @migrationLocks -ProposedTestRevision $newRevision -SimulateWriteFailure } $false 'ERROR_ATOMIC_WRITE' 'migration-atomic-rejection'
Assert-Controller { & $controller accept-design-revision @migrationLocks -ProposedTestRevision $newRevision }
$migrated = Get-Content $migrationLocks.StatePath -Raw | ConvertFrom-Json
if ($migrated.phase -ne 'TEST_DESIGN_DRAFT' -or $migrated.revisions.testBaseline -ne $migration.fixture.baseline -or $migrated.revisions.test -ne $newRevision -or $migrated.authorization.maxPhase -ne 'design') { throw 'migration skipped review, reset baseline or changed authorization' }
$migrationLocks.TestRevision = $newRevision
Assert-Controller { & $controller issue-lease @migrationLocks -Role test-implementer -AgentId self } $false 'ERROR_TRANSITION' 'migration-needs-new-review'
Assert-Controller { & $controller record-verifier @migrationLocks -VerifyMode design -VerifierId self -ReportPath $historicalReport } $false 'ERROR_VERIFIER_REPORT' 'old-design-report-stale'
Write-VerifierReport $historicalReport 'design' 'self' $newRevision $migration.sutRevision $harness 'config-a' 'business coverage self review completed'
Assert-Controller { & $controller record-verifier @migrationLocks -VerifyMode design -VerifierId self -ReportPath $historicalReport }
Assert-Controller { & $controller next -StatePath $migrationLocks.StatePath } $true 'STOP_AWAIT_USER_AUTHORIZATION' 'migration-preserves-design-ceiling'
Write-Grant $grantFile 'business-migration' 'design' 'implementation' $newRevision $migration.sutRevision
Assert-Controller { & $controller grant-authorization @migrationLocks -Authorization implementation -ReportPath $grantFile }
$legacyUpgraded = Get-Content $migrationLocks.StatePath -Raw | ConvertFrom-Json
if (@($legacyUpgraded.authorization.grants).Count -ne 1 -or $legacyUpgraded.phase -ne 'TEST_DESIGN_VERIFIED') { throw 'legacy state without grants did not upgrade without phase change' }
# A configuration or implementation change cannot be smuggled into compatibility revalidation.
Assert-Controller { & $controller reopen-design @migrationLocks -Reason 'scope negative' }
$weakened = $fullCases.Replace('    required: true', '    required: false')
Set-Content (Join-Path $changeDir 'test-cases.yaml') $weakened -Encoding utf8
& $caseValidator @generation -RequireBusiness | Out-Null
if ($LASTEXITCODE -ne 0) { throw 'weakened fixture must be structurally valid to test preservation gate' }
Invoke-Git $migration.repo @('add','.') | Out-Null
Invoke-Git $migration.repo @('commit','--quiet','-m','negative required weakening') | Out-Null
$weakRevision = (Invoke-Git $migration.repo @('rev-parse','HEAD') | Select-Object -First 1).Trim()
Assert-Controller { & $controller accept-design-revision @migrationLocks -ProposedTestRevision $weakRevision } $false 'ERROR_SCOPE' 'migration-preserves-required'
Invoke-Git $migration.repo @('revert','--no-edit',$weakRevision) | Out-Null
$badRevision = Commit-Implementation $migration.repo 'business-migration' $false 'bad.java'
Assert-Controller { & $controller accept-design-revision @migrationLocks -ProposedTestRevision $badRevision } $false 'ERROR_SCOPE' 'migration-rejects-code'
Assert-Controller { & $controller reopen-design -StatePath $noRevision.state -TestRevision $noRevision.fixture.design -SutRevision $noRevision.sutRevision -HarnessRevision $harness -ConfigurationFingerprint config-a -Reason 'late reopen' } $false 'ERROR_TRANSITION' 'no-reopen-after-lease'
Write-Output '[CONTROLLER_DESIGN_AUTHORIZATION_TEST] PASS'
