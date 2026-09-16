# Controller contract tests. Synthetic runner receipts test state transitions;
# they are not evidence that a business scenario or semantic review passed.
# A data-level counterexample demonstrates why equal-ID fixtures are self-proving.
# These are generic ownership/resource concepts, not a variable-name checker.
$rows=@(@{id='expected';owner=101;resource=202},@{id='interference';owner=202;resource=303})
$expected=@($rows | Where-Object { $_.owner -eq 101 } | ForEach-Object { $_.id })
$incorrect=@($rows | Where-Object { $_.owner -eq 202 } | ForEach-Object { $_.id })
if (($expected -join ',') -eq ($incorrect -join ',')) {throw 'counterexample cannot distinguish the incorrect implementation'}
$selfProving=@(@{id='masked';owner=202;resource=202})
if (@($selfProving | Where-Object { $_.owner -eq $_.resource }).Count -ne 1) {throw 'self-proving fixture demonstration invalid'}
$slice=New-LeasedCase 'slice' 'slice-change'
$changeRoot=Join-Path $slice.repo 'changes/slice-change'
[void](New-Item -ItemType Directory -Force -Path (Join-Path $slice.repo 'scripts'))
Copy-Item -LiteralPath (Join-Path $harnessSource 'scripts/test-runtime-contract.ps1') -Destination (Join-Path $slice.repo 'scripts/test-runtime-contract.ps1')
$casesPath=Join-Path $changeRoot 'test-cases.yaml'
Set-Content -LiteralPath $casesPath -Value 'canonical fixture' -Encoding utf8
$caseHash=(Get-FileHash $casesPath -Algorithm SHA256).Hash.ToLowerInvariant()
@{kind='flow-test-cases-derived';source=@{path='test-cases.yaml';sha256=$caseHash};runnerFilters=@(@{id='first';filter='sample.Test#first'},@{id='second';filter='sample.Test#second'});failureObservability=@(@{id='first';testClass='sample.Test';testMethod='first'},@{id='second';testClass='sample.Test';testMethod='second'})} | ConvertTo-Json -Depth 8 | Set-Content (Join-Path $changeRoot 'contract.json') -Encoding utf8
@{schemaVersion=2;testCasesContract=@{path='contract.json'}} | ConvertTo-Json | Set-Content (Join-Path $changeRoot 'manifest.yaml') -Encoding utf8
@{configurationFingerprint='config-a'} | ConvertTo-Json | Set-Content (Join-Path $changeRoot 'resolved-manifest.json') -Encoding utf8
Invoke-Git $slice.repo @('add','.') | Out-Null
Invoke-Git $slice.repo @('commit','--quiet','-m','fixture') | Out-Null
Assert-Controller { & $controller execution -Action prepare -StatePath $slice.state -ScenarioIds first } $true 'bindingKey' 'prepare-slice'
$prepared=Get-Content $slice.state -Raw | ConvertFrom-Json
$deadline=$prepared.execution.deadlineUtc
Assert-Controller { & $controller execution -Action prepare -StatePath $slice.state -ScenarioIds second } $true 'bindingKey' 'idempotent-prepare'
if ((Get-Content $slice.state -Raw | ConvertFrom-Json).execution.deadlineUtc -ne $deadline) {throw 'prepare reset budget'}
Assert-Controller { & $controller start-run -StatePath $slice.state } $false 'ERROR_EXECUTION_ENTRY' 'legacy-cannot-bypass'
Assert-Controller { & $controller execution -Action start -StatePath $slice.state } $false 'ERROR_SLICE_NOT_READY' 'fields-do-not-award-review'
$reviewPath=Join-Path $root 'slice-review.json'
$review=@{bindingKey=$prepared.execution.key;review='self';reviewer='fixture';result='REJECT';scenarioIds=@('first');counterexample='Distinct identity values expose the incorrect comparison';waitCondition='Own correlated result';estimatedSeconds=1}
$review.dependencies=@{first=@{completeReviewed=$true;test=@('scripts/*','changes/slice-change/test-cases.yaml','changes/slice-change/manifest.yaml');sut=@('changes/*')}}
foreach($gate in @('design','implementation','environment')){$review[$gate]=@{result='PASS';summary='fixture review';evidencePaths=@($casesPath)}}
$review | ConvertTo-Json -Depth 8 | Set-Content $reviewPath -Encoding utf8
Assert-Controller { & $controller execution -Action review -StatePath $slice.state -ReportPath $reviewPath } $false 'ERROR_SLICE_REVIEW' 'semantic-reject-wins-over-complete-fields'
$review.result='PASS'
$review | ConvertTo-Json -Depth 8 | Set-Content $reviewPath -Encoding utf8
Assert-Controller { & $controller execution -Action review -StatePath $slice.state -ReportPath $reviewPath }
$environmentPath=Join-Path $root 'slice-environment.json'
$binding=$prepared.execution.binding
@{mode='environment';result='BLOCKED';testRevision=$binding.test;sutRevision=$binding.sut;harnessRevision=$binding.harness;configurationFingerprint=$binding.configuration;steps=@(@{result='BLOCKED';detail='missing artifact'})} | ConvertTo-Json -Depth 6 | Set-Content $environmentPath -Encoding utf8
Assert-Controller { & $controller execution -Action environment -StatePath $slice.state -ReportPath $environmentPath } $true 'BLOCKED' 'environment-failure-preserved'
Assert-Controller { & $controller execution -Action status -StatePath $slice.state } $true 'resume' 'environment-failure-next-action'
Assert-Controller { & $controller execution -Action review -StatePath $slice.state -ReportPath $reviewPath } $false 'ERROR_REPAIR_REQUIRED' 'review-cannot-clear-failure'
$envRepair=Join-Path $root 'environment-repair.json'
@{result='PASS';review='self';reason='restored missing artifact';evidencePaths=@($environmentPath)} | ConvertTo-Json | Set-Content $envRepair -Encoding utf8
Assert-Controller { & $controller execution -Action resume -StatePath $slice.state -ReportPath $envRepair } $true 'review-selected-slice' 'environment-repair-resumes'
Assert-Controller { & $controller execution -Action review -StatePath $slice.state -ReportPath $reviewPath }
@{mode='environment';result='PASS';testRevision=$binding.test;sutRevision=$binding.sut;harnessRevision=$binding.harness;configurationFingerprint=$binding.configuration;steps=@(@{result='PASS'})} | ConvertTo-Json -Depth 6 | Set-Content $environmentPath -Encoding utf8
Assert-Controller { & $controller execution -Action environment -StatePath $slice.state -ReportPath $environmentPath }
Assert-Controller { & $controller execution -Action start -StatePath $slice.state } $true 'runId' 'registered-slice'
Assert-Controller { & $controller execution -Action start -StatePath $slice.state } $false 'ERROR_SLICE_NOT_READY' 'no-duplicate-delivery'
$running=Get-Content $slice.state -Raw | ConvertFrom-Json
$active=$running.activeRun
[void](New-Item -ItemType Directory -Force -Path (Split-Path -Parent $active.evidence))
@{flowRunId=$active.runId;executionKey=$active.executionKey;scenarioIds=@('first');status='PASS';classification='NONE';cleanup=@{succeeded=$true;retainedState=$false};counts=@{passed=1;failed=0;skipped=0}} | ConvertTo-Json -Depth 8 | Set-Content $active.evidence -Encoding utf8
Assert-Controller { & $controller execution -Action finish -StatePath $slice.state -ReportPath $active.evidence } $true 'AWAITING_REVIEW' 'runner-not-semantic-pass'
$resultReview=Join-Path $root 'slice-result-review.json'
@{runId=$active.runId;bindingKey=$active.executionKey;review='self';reviewer='fixture';result='PASS';summary='fixture result review';evidencePaths=@($active.evidence)} | ConvertTo-Json -Depth 6 | Set-Content $resultReview -Encoding utf8
Assert-Controller { & $controller execution -Action result -StatePath $slice.state -ReportPath $resultReview } $true 'PENDING' 'partial-not-full-pass'
$summary=(& $controller execution -Action status -StatePath $slice.state | Out-String) | ConvertFrom-Json
if ($summary.complete -or $summary.scenarios[0].result -ne 'PASS' -or $summary.scenarios[1].result -ne 'PENDING') {throw 'slice leaked PASS to unrun scope'}
Assert-Controller { & $controller execution -Action start -StatePath $slice.state } $false 'ERROR_SLICE_NOT_READY' 'no-blind-rerun'
$repairPath=Join-Path $root 'slice-repair.json'
$repair=@{result='PASS';reason='Corrected unrelated fixture';review='self';evidencePaths=@($casesPath);impactAnalysis='Reviewed dependency map excludes the unrelated fixture';approvedScope=$true;reuse=@(@{scenarioId='first';runId=$active.runId;rationale='Explicit prior dependencies unchanged'})}
$repair | ConvertTo-Json -Depth 6 | Set-Content $repairPath -Encoding utf8
Set-Content (Join-Path $changeRoot 'fixture.txt') 'fixed' -Encoding utf8
Invoke-Git $slice.repo @('add','.') | Out-Null
Invoke-Git $slice.repo @('commit','--quiet','-m','repair fixture') | Out-Null
Assert-Controller { & $controller execution -Action resume -StatePath $slice.state -ReportPath $repairPath -ScenarioIds first } $true 'PENDING' 'fixture-repair-resumes'
$reusedSummary=(& $controller execution -Action status -StatePath $slice.state | Out-String)|ConvertFrom-Json
if($reusedSummary.scenarios[0].result -ne 'PASS' -or $reusedSummary.complete){throw 'proven dependency reuse failed or became full PASS'}
@{configurationFingerprint='config-b'}|ConvertTo-Json|Set-Content (Join-Path $changeRoot 'resolved-manifest.json') -Encoding utf8
Invoke-Git $slice.repo @('add','.')|Out-Null
Invoke-Git $slice.repo @('commit','--quiet','-m','repair configuration')|Out-Null
Assert-Controller { & $controller execution -Action review -StatePath $slice.state -ReportPath $reviewPath } $false 'ERROR_EXECUTION_DRIFT' 'old-review-cannot-cover-new-config'
Assert-Controller { & $controller execution -Action resume -StatePath $slice.state -ReportPath $repairPath } $false 'ERROR_UNPROVEN_REUSE' 'reuse-cannot-cross-environment'
$repair.Remove('reuse')
$repair|ConvertTo-Json -Depth 6|Set-Content $repairPath -Encoding utf8
Assert-Controller { & $controller execution -Action resume -StatePath $slice.state -ReportPath $repairPath } $true 'PENDING' 'configuration-repair-resumes'
Set-Content (Join-Path $slice.sut 'README.md') 'business repair' -Encoding utf8
Invoke-Git $slice.sut @('add','.')|Out-Null
Invoke-Git $slice.sut @('commit','--quiet','-m','business repair')|Out-Null
Assert-Controller { & $controller execution -Action resume -StatePath $slice.state -ReportPath $repairPath } $false 'ERROR_BUSINESS_REVIEW' 'business-change-needs-business-review'
$businessPath=Join-Path $root 'business-review.json'
@{result='PASS';review='self';sutRevision=(Invoke-Git $slice.sut @('rev-parse','HEAD')|Select-Object -First 1).Trim();evidencePaths=@($casesPath)}|ConvertTo-Json -Depth 6|Set-Content $businessPath -Encoding utf8
$repair.businessReviewPath=$businessPath
$repair|ConvertTo-Json -Depth 6|Set-Content $repairPath -Encoding utf8
Assert-Controller { & $controller execution -Action resume -StatePath $slice.state -ReportPath $repairPath } $true 'PENDING' 'reviewed-business-repair-resumes'
$resumed=Get-Content $slice.state -Raw | ConvertFrom-Json
if ($resumed.execution.deadlineUtc -ne $deadline -or $resumed.runs.Count -ne 1 -or $resumed.execution.review) {throw 'repair lost history/budget or retained stale review'}
$review.bindingKey=$resumed.execution.key
$review | ConvertTo-Json -Depth 8 | Set-Content $reviewPath -Encoding utf8
Assert-Controller { & $controller execution -Action review -StatePath $slice.state -ReportPath $reviewPath }
$binding=$resumed.execution.binding
@{mode='environment';result='PASS';testRevision=$binding.test;sutRevision=$binding.sut;harnessRevision=$binding.harness;configurationFingerprint=$binding.configuration;steps=@(@{result='PASS'})} | ConvertTo-Json -Depth 6 | Set-Content $environmentPath -Encoding utf8
Assert-Controller { & $controller execution -Action environment -StatePath $slice.state -ReportPath $environmentPath }
Assert-Controller { & $controller execution -Action start -StatePath $slice.state } $true 'runId' 'interruption-fixture-registered'
Assert-Controller { & $controller execution -Action resume -StatePath $slice.state -ReportPath $repairPath } $false 'ERROR_ACTIVE_RUN' 'interruption-needs-diagnosis'
$repair.interruptedRunDiagnosis='Synthetic process ended before receipt; no second delivery'
$repair.cleanupRestored=$true
$repair|ConvertTo-Json -Depth 6|Set-Content $repairPath -Encoding utf8
Assert-Controller { & $controller execution -Action resume -StatePath $slice.state -ReportPath $repairPath } $true 'review-selected-slice' 'interrupted-run-reconciled'
$resumed=Get-Content $slice.state -Raw | ConvertFrom-Json
if($resumed.activeRun -or $resumed.runs.Count -ne 2 -or $resumed.runs[-1].result -ne 'interrupted' -or $resumed.execution.deadlineUtc -ne $deadline){throw 'interruption lost history or reset budget'}
$resumed.execution.deadlineUtc=[DateTime]::UtcNow.AddSeconds(90).ToString('o')
Re-sign-State $slice.state $resumed
Assert-Controller { & $controller execution -Action start -StatePath $slice.state } $false 'ERROR_BUDGET_EXHAUSTED' 'cleanup-reservation'
Assert-Controller { & $controller execution -Action prepare -StatePath $slice.state } $true 'budget-exhausted' 'entry-cannot-renew-budget'
