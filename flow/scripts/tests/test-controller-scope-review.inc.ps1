# Real Git/user grant/design/lease; no production state or service involved.
$scopeFixture = New-GitFixture (Join-Path $root 'scope-review-system') 'scope-review'
$scopeSut = New-GitFixture (Join-Path $root 'scope-review-sut') 'sut'
$scopeDirectory = Join-Path $scopeFixture.path 'changes/scope-review'
$scopeCases = Join-Path $scopeDirectory 'test-cases.yaml'
$scopeOriginal = (Get-Content (Join-Path $PSScriptRoot 'fixtures/business-cases.yaml') -Raw).Replace("`r`n", "`n").TrimEnd() + "`n"
[IO.File]::WriteAllText($scopeCases, $scopeOriginal, [Text.UTF8Encoding]::new($false))
Invoke-Git $scopeFixture.path @('add','.') | Out-Null
Invoke-Git $scopeFixture.path @('commit','--quiet','-m','scope design') | Out-Null
$scopeDesign = (Invoke-Git $scopeFixture.path @('rev-parse','HEAD') | Select-Object -First 1).Trim()
$scopeStatePath = Join-Path $root 'scope-review-state.json'
$scopeGrantPath = Join-Path $root 'scope-review-grant.json'
Write-Grant $scopeGrantPath 'scope-review' 'none' 'result' $scopeDesign $scopeSut.design
$scopeLocks = @{StatePath=$scopeStatePath;SutRevision=$scopeSut.design;HarnessRevision=$harness;ConfigurationFingerprint='config-a'}
Assert-Controller { & $controller initialize @scopeLocks -ChangeName scope-review -SystemTestRepo $scopeFixture.path -SutRepo $scopeSut.path -TestBaselineRevision $scopeFixture.baseline -TestRevision $scopeDesign -Authorization result -ReportPath $scopeGrantPath -HarnessRoot $harnessRoot -HarnessCertificationPath $harnessCertification }
$scopeDesignReport = Join-Path $root 'scope-design-review.json'
Write-VerifierReport $scopeDesignReport 'design' 'self' $scopeDesign $scopeSut.design $harness 'config-a'
Assert-Controller { & $controller record-verifier @scopeLocks -TestRevision $scopeDesign -VerifyMode design -VerifierId self -ReportPath $scopeDesignReport }
Assert-Controller { & $controller issue-lease @scopeLocks -TestRevision $scopeDesign -Role test-implementer -AgentId self }
$scopeBefore = Get-Content $scopeStatePath -Raw | ConvertFrom-Json
$scopeLease = $scopeBefore.leases[0]
$scopePreviousFile = Join-Path $root 'scope-previous.yaml'
[IO.File]::WriteAllText($scopePreviousFile, $scopeOriginal, [Text.UTF8Encoding]::new($false))
$scopeNewSource = 'schemaVersion: 1' + "`nscenarios:`n" + $scopeOriginal.Substring($scopeOriginal.IndexOf('  - id: AC-2-S1'))
[IO.File]::WriteAllText($scopeCases, $scopeNewSource, [Text.UTF8Encoding]::new($false))
Invoke-Git $scopeFixture.path @('add','.') | Out-Null
Invoke-Git $scopeFixture.path @('commit','--quiet','-m','user removes first scenario') | Out-Null
$scopeProposed = (Invoke-Git $scopeFixture.path @('rev-parse','HEAD') | Select-Object -First 1).Trim()
$scopeDiff = Get-DiffFixture $scopeFixture.path $scopeDesign $scopeProposed
$scopeReportPath = Join-Path $root 'scope-report.json'
$scopeReport = [ordered]@{
    schemaVersion=1;result='PASS';mode='design-scope';verifierId='self';grantedBy='user';requestRef='fixture-user-turn';requestText='Exclude the first scenario from this acceptance'
    changeName='scope-review';previousTestRevision=$scopeDesign;testRevision=$scopeProposed;canonicalRevision=$scopeFixture.baseline
    sutRevision=$scopeSut.design;harnessRevision=$harness;configurationFingerprint='config-a';summary='self: preserve remaining business expectations and explicitly exclude removed consumer acceptance'
    previousSourceSha256=(Get-FileHash $scopePreviousFile -Algorithm SHA256).Hash.ToLowerInvariant();currentSourceSha256=(Get-FileHash $scopeCases -Algorithm SHA256).Hash.ToLowerInvariant()
    removedScenarioIds=@('AC-1-S1');diffHash=$scopeDiff.diffHash
}
$scopeReport | ConvertTo-Json -Depth 8 | Set-Content $scopeReportPath -Encoding utf8
$scopeArgs = @{} + $scopeLocks
$scopeArgs.LeaseId=$scopeLease.leaseId; $scopeArgs.AgentId='self'; $scopeArgs.VerifierId='self'; $scopeArgs.ProposedTestRevision=$scopeProposed; $scopeArgs.ReportPath=$scopeReportPath
foreach ($field in @('grantedBy','requestText','requestRef','currentSourceSha256','previousSourceSha256','diffHash','testRevision','canonicalRevision')) {
    $badScope = $scopeReport | ConvertTo-Json -Depth 8 | ConvertFrom-Json
    $badScope.$field=''
    $badScope | ConvertTo-Json -Depth 8 | Set-Content $scopeReportPath -Encoding utf8
    Assert-Controller { & $controller record-scope-review @scopeArgs } $false 'ERROR_SCOPE_REVIEW' "scope-rejects-$field"
}
$scopeReport | ConvertTo-Json -Depth 8 | Set-Content $scopeReportPath -Encoding utf8
$wrongScopeOwner = @{} + $scopeArgs; $wrongScopeOwner.AgentId='different'
Assert-Controller { & $controller record-scope-review @wrongScopeOwner } $false 'ERROR_LEASE_INVALID' 'scope-owner'
Assert-Controller { & $controller record-scope-review @scopeArgs -SimulateWriteFailure } $false 'ERROR_ATOMIC_WRITE' 'scope-atomic'
Assert-Controller { & $controller record-scope-review @scopeArgs }
$scopeAfter = Get-Content $scopeStatePath -Raw | ConvertFrom-Json
foreach ($field in @('phase','authorization','revisions','leases','verifier','runs','failureFingerprints','activeRun','configurationFingerprint')) {
    if (($scopeBefore.$field | ConvertTo-Json -Depth 16 -Compress) -ne ($scopeAfter.$field | ConvertTo-Json -Depth 16 -Compress)) { throw "scope audit changed $field" }
}
if (@($scopeAfter.scopeDesignReviews).Count -ne 1) { throw 'scope audit not persisted' }
Assert-Controller { & $controller record-scope-review @scopeArgs } $false 'ERROR_SCOPE_REVIEW' 'scope-no-replay'
$scopeValidation = @{
    TestCasesPath=$scopeCases;Mode='business';PreviousTestCasesPath=$scopePreviousFile;PreviousTestRevision=$scopeDesign
    CanonicalRevision=$scopeFixture.baseline;DesignVerifierReportPath=$scopeReportPath;ControllerStatePath=$scopeStatePath;TrustedVerifierIdentity='self'
}
$scopeValidator = Join-Path $PSScriptRoot '../validate-test-cases.ps1'
& $scopeValidator @scopeValidation | Out-Null
if ($LASTEXITCODE -ne 0) { throw 'scope removal attestation was not consumable' }
$tamperedScope = Get-Content $scopeReportPath -Raw | ConvertFrom-Json
$tamperedScope.requestText='different request'
$tamperedScope | ConvertTo-Json -Depth 8 | Set-Content $scopeReportPath -Encoding utf8
& $scopeValidator @scopeValidation | Out-Null
if ($LASTEXITCODE -eq 0) { throw 'modified scope report accepted' }
Write-Output '[CONTROLLER_SCOPE_REVIEW_TEST] PASS'
