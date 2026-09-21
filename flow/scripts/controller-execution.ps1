# Functions are loaded inside the canonical controller. All writes use its signed,
# atomic state; reports are immutable attachments, never an alternative state file.
function Save-ExecutionEvidence([string]$Path) {
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { Stop-Controller 'ERROR_EVIDENCE' "Missing evidence: $Path" }
    $hash = Get-FileHashValue $Path
    $dir = Join-Path (Split-Path -Parent $StatePath) 'execution-evidence'
    [void](New-Item -ItemType Directory -Force -Path $dir)
    $target = Join-Path $dir $hash
    if (Test-Path -LiteralPath $target) {
        if ((Get-FileHashValue $target) -ne $hash) { Stop-Controller 'ERROR_EVIDENCE' 'Archived evidence was changed' }
    } else { Copy-Item -LiteralPath $Path -Destination $target }
    return [pscustomobject]@{ path=(Get-CanonicalPath $Path); archive=$target; sha256=$hash }
}
function Get-ExecutionBinding($State) {
    $repo = [string]$State.repositories.systemTest
    Assert-HarnessRepairWorktreeClean $repo ([string]$State.changeName)
    $manifestPath = Join-Path $repo "changes/$($State.changeName)/manifest.yaml"
    $resolvedPath = Join-Path $repo "changes/$($State.changeName)/resolved-manifest.json"
    # Manifests can contain secret *references*. Read locally, never archive or
    # print their values; the binding exposes only hashes and revisions.
    $manifest = Get-Content -LiteralPath $manifestPath -Raw -Encoding utf8 | ConvertFrom-Json
    Assert-ExecutionSutClean ([string]$State.repositories.sut) @($manifest.nonBuildInputs)
    $resolved = Get-Content -LiteralPath $resolvedPath -Raw -Encoding utf8 | ConvertFrom-Json
    if ([int]$manifest.schemaVersion -ne 2) { Stop-Controller 'ERROR_EXECUTION_MANIFEST' 'Slices require the v2 runner contract' }
    $contractPath = Join-Path (Split-Path -Parent $manifestPath) ([string]$manifest.testCasesContract.path)
    $contract = Read-StructuredJson $contractPath 'scenario contract'
    $all = @($contract.runnerFilters | ForEach-Object { [string]$_.id } | Sort-Object -Unique)
    if ($all.Count -eq 0) { Stop-Controller 'ERROR_EXECUTION_SCOPE' 'No canonical scenarios' }
    . (Join-Path $repo 'scripts/test-runtime-contract.ps1')
    # Revalidate the canonical source hash and every exact method mapping.
    $null = Get-TestScenarioSelection (Split-Path -Parent $manifestPath) ([string]$manifest.testCasesContract.path) $all
    $certifier=Join-Path $State.harnessCertification.root 'scripts/harness-certification.ps1'
    $harnessRevision=(& $certifier revision -HarnessRoot $State.harnessCertification.root | Select-Object -Last 1).Trim()
    $cert = Assert-HarnessCertification $State.harnessCertification.root $State.harnessCertification.path $harnessRevision
    $binding = [pscustomobject]@{
        test=(Get-GitHead $repo); sut=(Get-GitHead ([string]$State.repositories.sut)); harness=$harnessRevision
        configuration=[string]$resolved.configurationFingerprint; resolvedHash=(Get-FileHashValue $resolvedPath)
        contractHash=(Get-FileHashValue $contractPath); allScenarioIds=$all; certification=$cert.certificationHash
        buildInputReviewHash=(Get-StringHash (@($manifest.nonBuildInputs) | ConvertTo-Json -Depth 8 -Compress))
        environmentInputs=(Get-ExecutionEnvironmentInputs $State $resolved)
    }
    if($State.repositoryBindingKey){$binding | Add-Member -NotePropertyName repositoryBindingKey -NotePropertyValue $State.repositoryBindingKey}
    return $binding
}
function Get-ExecutionKey($Binding) { return Get-StringHash ($Binding | ConvertTo-Json -Depth 8 -Compress) }
function Assert-ExecutionSutClean([string]$Repository, [object[]]$NonBuildInputs=@()) {
    foreach ($line in @(Get-GitOutput $Repository @('status','--porcelain=v1','--untracked-files=all'))) {
        if ([string]::IsNullOrWhiteSpace($line)) { continue }
        # Runtime logs are retained, never deleted or mistaken for source changes.
        if ($line -match '^\?\? logs/.+\.log$') { continue }
        # Only exact reviewed content can be excluded, never a wildcard or extension.
        # Git may quote unusual names: leave them unresolved rather than misclassify.
        $relative=$line.Substring(3).Replace('\','/')
        $full=Join-Path $Repository $relative
        $exclusion=@($NonBuildInputs | Where-Object {
            $_ -and $_.path -eq $relative -and $_.repository -eq $Repository -and
            $_.reason -and $_.evidencePath -and $_.sha256 -and
            (Test-Path -LiteralPath $_.evidencePath -PathType Leaf)
        } | Select-Object -First 1)
        if($exclusion.Count -and (Test-Path -LiteralPath $full -PathType Leaf) -and
            (Get-FileHashValue $full) -eq $exclusion[0].sha256) { continue }
        Stop-Controller 'ERROR_SCOPE_WORKTREE_DIRTY' "Build-input relevance unresolved: $line. Inspect build inputs; preserve unrelated files and record exact nonBuildInputs content with review evidence in the manifest. Do not clean the repository."
    }
}
function Set-ExecutionLocks($State,$Binding) {
    $State.revisions.test=$Binding.test; $State.revisions.sut=$Binding.sut; $State.revisions.harness=$Binding.harness
    $State.configurationFingerprint=$Binding.configuration
    $State.harnessCertification.certificationHash=$Binding.certification
    foreach ($lease in @($State.leases)) { $lease.active=$false }
}
function Get-ExecutionEnvironmentInputs($State,$Resolved) {
    . (Join-Path $State.repositories.systemTest 'scripts/test-runtime-contract.ps1')
    $inputs=@()
    foreach ($sut in @($Resolved.suts | Where-Object { $_ })) {
        if ((Get-CanonicalPath $sut.repository) -ne (Get-CanonicalPath $State.repositories.sut)) { $inputs += "sut:$($sut.id):$(Get-GitHead $sut.repository)" }
    }
    $provider=$Resolved.configuration.provider
    foreach ($repo in @($provider.repository,$provider.configurationRepository | Where-Object {$_} | Sort-Object -Unique)) { $inputs += "provider:$(Get-GitHead $repo)" }
    foreach ($target in @($Resolved.configuration.targets | Where-Object { $_ })) {
        $inputs += "target:$($target.application):$(Get-TestConfigurationContentHash $target.absoluteFile $Resolved.configuration.ownership $provider.configurationRepository)"
    }
    return Get-StringHash ($inputs -join "`n")
}
function Assert-ExecutionScope($State,[string]$Previous,[string]$Current) {
    if (-not $Previous -or $Previous -eq $Current) { return }
    $diff=Get-GitDiffInfo $State.repositories.systemTest $Previous $Current
    foreach ($file in $diff.changedFiles) {
        # Certified harness recovery already owns self-test; other paths keep
        # the existing implementation guard, never gain business write access.
        if ($file -like 'self-test/*') { continue }
        $output=@(& (Join-Path $PSScriptRoot 'test-scope-guard.ps1') -AuthorizedRepo $State.repositories.systemTest -TargetPath (Join-Path $State.repositories.systemTest $file) -Stage apply -Action write)
        if ($LASTEXITCODE -ne 0) { Stop-Controller 'ERROR_SCOPE' ($output -join ' ') }
    }
}
function Assert-ExecutionTime($State) {
    if ([DateTime]::UtcNow -ge [DateTime]::Parse($State.execution.deadlineUtc).ToUniversalTime().AddSeconds(-120)) {
        Stop-Controller 'ERROR_BUDGET_EXHAUSTED' 'No new work: reserve the final two minutes for owned-resource cleanup. Report verified scope; only an explicit user budget grant can extend the deadline.'
    }
}
function Assert-ExecutionCurrent($State) {
    if ((Get-ExecutionKey (Get-ExecutionBinding $State)) -ne [string]$State.execution.key) {
        Stop-Controller 'ERROR_EXECUTION_DRIFT' 'Candidate changed. Use resume with repair evidence and an impact review; previous results remain in history.'
    }
}
function Get-DevelopmentBinding($State) {
    $root=Join-Path $State.repositories.systemTest "changes/$($State.changeName)"
    $files=@('test-design.md','test-plan.md','test-cases.yaml','manifest.yaml')
    $hashes=@(); $missing=@()
    foreach($name in $files) {
        $path=Join-Path $root $name
        if(Test-Path -LiteralPath $path -PathType Leaf){$hashes += "$($name):$(Get-FileHashValue $path)"}
        else{$missing += $name; $hashes += "$($name):MISSING"}
    }
    $sut=Get-GitHead $State.repositories.sut
    return [pscustomobject]@{key=(Get-StringHash (($hashes -join '|')+'|'+$sut));sut=$sut;test=(Get-GitHead $State.repositories.systemTest);missing=$missing}
}
function Assert-DevelopmentReview($State) {
    if(-not $State.execution.development){return}
    $current=Get-DevelopmentBinding $State
    if(-not $State.execution.development.designReview -or $current.key -ne $State.execution.development.designKey){
        Stop-Controller 'ERROR_DESIGN_REVIEW_REQUIRED' 'Review current design via flow-test.ps1 review-design before accepting the executable candidate; old budget does not block design work.'
    }
}
function Get-ExecutionSummary($State) {
    $cycle = $State.execution
    if ($null -eq $cycle) { return [pscustomobject]@{ next='prepare'; phase=$State.phase } }
    $development=$cycle.development
    $designCurrent=if($development){Get-DevelopmentBinding $State}else{$null}
    $drift=$false
    if ($cycle.binding) {
        $resolved=Join-Path $State.repositories.systemTest "changes/$($State.changeName)/resolved-manifest.json"
        $drift=((Get-GitHead $State.repositories.systemTest) -ne $cycle.binding.test -or (Get-GitHead $State.repositories.sut) -ne $cycle.binding.sut -or -not (Test-Path -LiteralPath $resolved))
        if (-not $drift) { $drift=(Get-FileHashValue $resolved) -ne $cycle.binding.resolvedHash }
        if (-not $drift) {
            try { $resolvedObject=Get-Content -LiteralPath $resolved -Raw -Encoding utf8 | ConvertFrom-Json; $drift=(Get-ExecutionEnvironmentInputs $State $resolvedObject) -ne $cycle.binding.environmentInputs }
            catch { $drift=$true }
        }
        foreach ($kind in @('systemTest','sut')) {
            $changes=@(Get-GitOutput $State.repositories.$kind @('status','--porcelain=v1','--untracked-files=all'))
            foreach ($line in $changes) {
                if ($line.Length -lt 4) {continue}
                if ($kind -eq 'sut' -and $line -match '^\?\? logs/.+\.log$') {continue}
                $path=$line.Substring(3).Trim().Replace('\','/')
                if ($kind -ne 'systemTest' -or $path -notlike "changes/$($State.changeName)/evidence/*") { $drift=$true }
            }
        }
    }
    if($cycle.repositoryBindingPending){$drift=$true}
    $rows = @($cycle.binding.allScenarioIds | Where-Object { $_ } | ForEach-Object {
        $id = $_
        $matching = @($State.runs | Where-Object { $_.executionKey -eq $cycle.key -and $id -in @($_.scenarioIds) })
        $last = $matching | Select-Object -Last 1
        if (-not $last) {
            $reuse=@($cycle.reuses | Where-Object { $_.key -eq $cycle.key -and $_.scenarioId -eq $id }) | Select-Object -Last 1
            if ($reuse) { $last=@($State.runs | Where-Object { $_.runId -eq $reuse.runId }) | Select-Object -Last 1 }
        }
        $verified = @($cycle.resultReviews | Where-Object { $_.runId -eq $last.runId }).Count -gt 0
        $result = if ($null -eq $last) { 'PENDING' } elseif ($last.result -ne 'pass') { 'FAIL' } elseif (-not $verified) { 'AWAITING_REVIEW' } else { 'PASS' }
        if ($drift -and $last) { $result='STALE' }
        [pscustomobject]@{ id=$id; result=$result; evidence=$last.evidence }
    })
    if($development -and -not $development.accepted){$drift=$true; foreach($row in $rows){$row.result='STALE'}}
    $complete=($rows.Count -gt 0 -and @($rows | Where-Object { $_.result -ne 'PASS' }).Count -eq 0)
    $selectedComplete=(@($cycle.selected).Count -gt 0 -and @($rows | Where-Object { $_.id -in @($cycle.selected) -and $_.result -ne 'PASS' }).Count -eq 0)
    $selectionHash=(Get-StringHash (@($cycle.selected | Sort-Object) -join ',')).Substring(0,12)
    $inputRoot=Join-Path (Split-Path -Parent $StatePath) 'execution-evidence'
    [pscustomobject]@{
        development=$development; designBinding=$designCurrent
        designReviewInputPath=$(if($designCurrent){Join-Path $inputRoot "design-$($designCurrent.key)-$($designCurrent.test).json"}else{$null})
        developmentNext=$(if(-not $development){'revise-with-user-request'}elseif(-not $development.designReview -or $development.designKey -ne $designCurrent.key){'review-design'}elseif(-not $development.accepted){'implement-then-resume'}else{'candidate-accepted'})
        phase=$State.phase; deadlineUtc=$cycle.deadlineUtc
        remainingSeconds=[Math]::Max(0,[int]([DateTime]::Parse($cycle.deadlineUtc).ToUniversalTime()-[DateTime]::UtcNow).TotalSeconds)
        binding=$cycle.binding; bindingKey=$cycle.key; candidateDrift=$drift; selected=$cycle.selected; scenarios=$rows
        reviewInputPath=(Join-Path $inputRoot "review-$($cycle.key)-$selectionHash.json")
        repairInputPath=(Join-Path $inputRoot "repair-$($cycle.key).json")
        pendingResultReviews=@($State.runs | Where-Object { $_.executionKey -eq $cycle.key -and $_.result -eq 'pass' } | Where-Object { $id=$_.runId; @($cycle.resultReviews | Where-Object { $_.runId -eq $id }).Count -eq 0 } | ForEach-Object { [pscustomobject]@{runId=$_.runId;path=(Join-Path $inputRoot "result-$($_.runId).json");evidence=$_.evidence.archive} })
        complete=$complete
        activeRun=$State.activeRun; cleanupRequired=$cycle.cleanupRequired
        issues=@($cycle.repairs)+@($State.runs | Where-Object { $_.executionKey -and $_.result -ne 'pass' } | ForEach-Object { [pscustomobject]@{reason="Run $($_.runId): $($_.failureCategory) $($_.primaryFailure.summary)";evidence=$_.evidence} })
        timings=@($State.runs | Where-Object { $_.executionKey } | Select-Object runId,startedAt,at,durationSeconds,stages,firstBusinessAssertionAt)
        invalidations=@($cycle.invalidations); next=$(if ($State.activeRun) {'recover-active-run'} elseif ($cycle.cleanupRequired) {'restore-owned-resources'} elseif ($complete) {'complete'} elseif (@($rows | Where-Object {$_.result -eq 'AWAITING_REVIEW'}).Count) {'review-results'} elseif ([DateTime]::UtcNow -ge [DateTime]::Parse($cycle.deadlineUtc).ToUniversalTime().AddSeconds(-120)) {'budget-exhausted'} elseif ($drift -or -not $cycle.binding -or $State.phase -in @('TEST_EXECUTED_FAIL','TEST_ENVIRONMENT_FAILED')) {'resume'} elseif ($selectedComplete) {'select-next-slice'} elseif (-not $cycle.review) {'review-selected-slice'} else {'advance'})
    }
}
function Rebind-TestRepositories($State,$Report) {
    if($Report.grantedBy -ne 'user' -or -not $Report.requestRef -or -not $Report.requestText -or -not $Report.reason){Stop-Controller 'ERROR_REBIND_AUTHORIZATION' 'Reference the existing user instruction to use/organize these worktrees; no new confirmation is needed'}
    $moves=@()
    foreach($item in @(@{field='systemTestRepository';role='systemTest'},@{field='sutRepository';role='sut'})){
        $value=$Report.($item.field)
        if(-not $value){continue}
        $old=Get-CanonicalGitRepo $State.repositories.($item.role)
        $target=Get-CanonicalGitRepo ([string]$value)
        if($old -eq $target){continue}
        $oldCommon=(@(Get-GitOutput $old @('rev-parse','--path-format=absolute','--git-common-dir')) -join '').Trim()
        $newCommon=(@(Get-GitOutput $target @('rev-parse','--path-format=absolute','--git-common-dir')) -join '').Trim()
        if((Get-CanonicalPath $oldCommon) -ne (Get-CanonicalPath $newCommon)){Stop-Controller 'ERROR_REPOSITORY_IDENTITY' 'Target must be an existing worktree of the same Git repository'}
        if($item.role -eq 'systemTest' -and -not (Test-Path -LiteralPath (Join-Path $target "changes/$($State.changeName)") -PathType Container)){Stop-Controller 'ERROR_CHANGE_DIRECTORY' 'Target test worktree lacks this change; restore its reviewed artifacts before rebinding'}
        $moves += [pscustomobject]@{role=$item.role;previous=$old;target=$target;head=(Get-GitHead $target)}
    }
    if(-not $moves.Count){return}
    if($State.activeRun -or $State.execution.cleanupRequired){Stop-Controller 'ERROR_ACTIVE_RUN' 'Recover the current run before rebinding; old run ownership must remain unchanged'}
    foreach($repo in @($State.repositories.systemTest)+@($moves | Where-Object {$_.role -eq 'systemTest'} | ForEach-Object {$_.target})){
        if(Test-Path -LiteralPath (Join-Path $repo ".runtime/$($State.changeName)/v2-owned-processes.json")){Stop-Controller 'ERROR_CLEANUP_REQUIRED' 'An owned-process registry remains in the source or target test worktree; recover those resources first'}
    }
    $proof=Save-ExecutionEvidence $ReportPath
    foreach($move in $moves){
        if($move.role -eq 'systemTest' -and (Test-PathWithin $State.harnessCertification.root $move.previous)){
            $oldRoot=Get-CanonicalPath $State.harnessCertification.root
            $newRoot=$move.target+$oldRoot.Substring($move.previous.Length)
            $oldReceipt=Get-CanonicalPath $State.harnessCertification.path
            $newReceipt=$newRoot+$oldReceipt.Substring($oldRoot.Length)
            # Copy only immutable certification evidence, never overwrite target files.
            # Full certification is still verified by prepare/resume against target code.
            if((Test-Path -LiteralPath $oldReceipt -PathType Leaf) -and (Test-PathWithin $oldReceipt $oldRoot)){
                $cert=Read-StructuredJson $oldReceipt 'existing harness certification'
                $paths=@($oldReceipt)+@(Join-Path $oldRoot $cert.selfTestReportPath)+@($cert.scenarioEvidence | ForEach-Object {Join-Path $oldRoot $_.path})
                foreach($source in $paths){
                    $source=Get-CanonicalPath $source
                    if(-not (Test-PathWithin $source $oldRoot)){Stop-Controller 'ERROR_EVIDENCE' 'Certification evidence escapes its old harness root'}
                    $destination=$newRoot+$source.Substring($oldRoot.Length)
                    if((Test-Path -LiteralPath $source -PathType Leaf) -and -not (Test-Path -LiteralPath $destination)){
                        [void](New-Item -ItemType Directory -Force -Path (Split-Path -Parent $destination))
                        Copy-Item -LiteralPath $source -Destination $destination
                    }
                }
            }
            $State.harnessCertification.root=$newRoot;$State.harnessCertification.path=$newReceipt
        }
        $State.repositories.($move.role)=$move.target
        Add-History $State $State.phase $State.phase ("rebound " + $move.role + ': ' + $move.previous + ' -> ' + $move.target)
    }
    if(-not $State.PSObject.Properties['repositoryBindings']){$State | Add-Member -NotePropertyName repositoryBindings -NotePropertyValue @()}
    $State.repositoryBindings += [pscustomobject]@{at=[DateTime]::UtcNow.ToString('o');requestRef=$Report.requestRef;moves=$moves;evidence=$proof}
    $State | Add-Member -Force -NotePropertyName repositoryBindingKey -NotePropertyValue (Get-StringHash ($State.repositories|ConvertTo-Json -Compress))
    $State.verifier=$null
    foreach($lease in @($State.leases)){$lease.active=$false}
    if($State.execution){
        $State.execution.review=$null
        if($State.execution.development){$State.execution.development.accepted=$false}
        $State.execution | Add-Member -Force -NotePropertyName repositoryBindingPending -NotePropertyValue $true
    }
    Write-State $State
}
function Invoke-Execution($State) {
    if ($Action -eq 'status') { Get-ExecutionSummary $State | ConvertTo-Json -Depth 16; return }
    if ($Action -eq 'rebind') {
        $report=Read-StructuredJson $ReportPath 'worktree binding request'
        Rebind-TestRepositories $State $report
        Get-ExecutionSummary $State | ConvertTo-Json -Depth 16; return
    }
    if ($Action -eq 'prepare') {
        if ($State.PSObject.Properties['execution']) { Get-ExecutionSummary $State | ConvertTo-Json -Depth 16; return }
        Require-Ceiling $State 'execution'
        if ($State.activeRun) { Stop-Controller 'ERROR_ACTIVE_RUN' 'Recover the existing run before preparation; do not redeliver input' }
        # Persist time before any potentially slow verification. Failed preparation
        # remains budgeted and is resumed, never initialized with a new deadline.
        $cycle = [pscustomobject]@{ startedAt=[DateTime]::UtcNow.ToString('o'); deadlineUtc=[DateTime]::UtcNow.AddMinutes(30).ToString('o'); binding=$null; key=''; selected=@(); review=$null; cleanupRequired=$false; repairs=@(); invalidations=@(); imports=@(); resultReviews=@(); reuses=@() }
        $State | Add-Member -NotePropertyName execution -NotePropertyValue $cycle
        $cycle | Add-Member -NotePropertyName initialTestRevision -NotePropertyValue (Get-GitHead $State.repositories.systemTest)
        Write-State $State
        $binding = Get-ExecutionBinding $State
        Assert-ExecutionScope $State $cycle.initialTestRevision $binding.test
        $cycle.binding=$binding; $cycle.key=Get-ExecutionKey $binding
        $cycle.selected=@($ScenarioIds | Sort-Object -Unique)
        if ($cycle.selected.Count -eq 0 -or @($cycle.selected | Where-Object { $_ -notin $binding.allScenarioIds }).Count) { Stop-Controller 'ERROR_EXECUTION_SCOPE' 'Select a nonempty subset of canonical scenario IDs, then resume' }
        Set-ExecutionLocks $State $binding
        Set-Phase $State 'TEST_IMPLEMENTED' 'prepared runtime candidate; selected reviews required'
        Write-State $State
        Get-ExecutionSummary $State | ConvertTo-Json -Depth 16; return
    }
    if (-not $State.PSObject.Properties['execution']) { Stop-Controller 'ERROR_EXECUTION_ENTRY' 'Run prepare first' }
    $cycle = $State.execution
    if ($Action -eq 'revise') {
        Require-Ceiling $State 'design'
        $report=Read-StructuredJson $ReportPath 'authorized development request'
        if($report.grantedBy -ne 'user' -or -not $report.requestRef -or -not $report.requestText -or -not $report.reason){Stop-Controller 'ERROR_DEVELOPMENT_AUTHORIZATION' 'Supply the actual user request authorizing new design/development; exhausted retries are not a new request.'}
        if($cycle.development -and $cycle.development.requestRef -eq $report.requestRef){Get-ExecutionSummary $State | ConvertTo-Json -Depth 16;return}
        if(-not $cycle.PSObject.Properties['developmentHistory']){$cycle | Add-Member -NotePropertyName developmentHistory -NotePropertyValue @()}
        if(@($cycle.developmentHistory | Where-Object {$_.requestRef -eq $report.requestRef}).Count){Stop-Controller 'ERROR_DEVELOPMENT_REPLAY' 'This development request was already used.'}
        if($report.sutRepository -or $report.systemTestRepository){Rebind-TestRepositories $State $report}
        if($cycle.development){$cycle.developmentHistory += $cycle.development}
        $cycle | Add-Member -Force -NotePropertyName development -NotePropertyValue ([pscustomobject]@{requestRef=$report.requestRef;request=(Save-ExecutionEvidence $ReportPath);openedAt=[DateTime]::UtcNow.ToString('o');designKey=$null;designReview=$null;accepted=$false;executionRequestRef=$null})
        Add-History $State $State.phase $State.phase 'authorized development reopened; execution budget and active resources preserved'
        Write-State $State;Get-ExecutionSummary $State | ConvertTo-Json -Depth 16;return
    }
    if ($Action -eq 'review-design') {
        Require-Ceiling $State 'design'
        if(-not $cycle.development){Stop-Controller 'ERROR_DEVELOPMENT_AUTHORIZATION' 'Use revise with the actual user request first'}
        $binding=Get-DevelopmentBinding $State
        $report=Read-StructuredJson $ReportPath 'development design review'
        if(@($binding.missing).Count -or $report.designKey -ne $binding.key -or $report.testRevision -ne $binding.test -or $report.sutRevision -ne $binding.sut -or
           $report.result -ne 'PASS' -or $report.review -notin @('self','independent') -or -not $report.reviewer -or -not $report.summary -or
           -not $report.counterexample -or $report.staticValidation.result -ne 'PASS' -or @($report.staticValidation.evidencePaths).Count -eq 0 -or @($report.evidencePaths).Count -eq 0){
            Stop-Controller 'ERROR_DESIGN_REVIEW' 'Need complete design artifacts, current revisions/key, actual semantic review and static validation evidence; no environment or runtime budget required.'
        }
        foreach($path in @($report.evidencePaths)+@($report.staticValidation.evidencePaths)){$null=Save-ExecutionEvidence $path}
        $cycle.development.designKey=$binding.key;$cycle.development.designReview=Save-ExecutionEvidence $ReportPath
        $cycle.development.accepted=$false
        Add-History $State $State.phase $State.phase 'current development design reviewed; no implementation, environment or result PASS granted'
        Write-State $State;Get-ExecutionSummary $State | ConvertTo-Json -Depth 16;return
    }
    if ($Action -eq 'result') {
        Require-Ceiling $State 'result'
        Assert-ExecutionCurrent $State
        $report=Read-StructuredJson $ReportPath 'result semantic review'
        $run=@($State.runs | Where-Object { $_.runId -eq $report.runId -and $_.executionKey -eq $cycle.key })
        if ($run.Count -ne 1 -or $run[0].result -ne 'pass' -or $cycle.cleanupRequired) { Stop-Controller 'ERROR_RESULT_REVIEW' 'Need one current passing run with complete cleanup' }
        if ($report.result -ne 'PASS' -or $report.bindingKey -ne $cycle.key -or $report.review -notin @('self','independent') -or -not $report.reviewer -or -not $report.summary -or @($report.evidencePaths).Count -eq 0) { Stop-Controller 'ERROR_RESULT_REVIEW' 'Provide actual semantic result review for the current candidate' }
        foreach ($path in @($report.evidencePaths)) { $null=Save-ExecutionEvidence $path }
        if ((Get-FileHashValue $run[0].evidence.archive) -ne $run[0].evidence.sha256) { Stop-Controller 'ERROR_EVIDENCE' 'Original run evidence changed' }
        $cycle.resultReviews += [pscustomobject]@{ runId=$report.runId; at=[DateTime]::UtcNow.ToString('o'); evidence=(Save-ExecutionEvidence $ReportPath) }
        $summary=Get-ExecutionSummary $State
        if ($summary.complete) { Set-Phase $State 'TEST_RESULT_VERIFIED' 'all canonical scenarios have current reviewed results' }
        Write-State $State; Get-ExecutionSummary $State | ConvertTo-Json -Depth 16; return
    }
    if ($Action -eq 'import') {
        $historical=Read-StructuredJson $EvidencePath 'historical structured result'
        $historicalStatus=if($historical.status){$historical.status}else{$historical.result}
        if ([int]$historical.schemaVersion -lt 1 -or $historicalStatus -notin @('PASS','FAIL','BLOCKED') -or (-not $historical.counts -and -not $historical.steps)) { Stop-Controller 'ERROR_HISTORY_FORMAT' 'Import requires a versioned structured runtime result with status and counts/steps; it remains unverified' }
        $evidence = Save-ExecutionEvidence $EvidencePath
        $cycle.imports += [pscustomobject]@{ evidence=$evidence; importedAt=[DateTime]::UtcNow.ToString('o'); status='HISTORICAL_UNVERIFIED' }
        Write-State $State; Write-Output '[FLOW_CONTROLLER] PASS history indexed; no formal PASS awarded'; return
    }
    if ($Action -eq 'resume') {
        $report = Read-StructuredJson $ReportPath 'repair / impact review'
        if (-not $report.reason -or @($report.evidencePaths).Count -eq 0 -or $report.review -notin @('self','independent') -or $report.result -ne 'PASS') { Stop-Controller 'ERROR_REPAIR_EVIDENCE' 'Provide a passing impact review, reason, review identity, and actual repair/diagnosis evidence paths' }
        $evidence = @($report.evidencePaths | ForEach-Object { Save-ExecutionEvidence $_ })
        if ($State.activeRun) {
            if (-not $report.interruptedRunDiagnosis -or $report.cleanupRestored -ne $true) { Stop-Controller 'ERROR_ACTIVE_RUN' 'Do not redeliver: reconcile original evidence and restore this run resources first' }
            $ownedPath=Join-Path $State.repositories.systemTest ".runtime/$($State.changeName)/v2-owned-processes.json"
            if (Test-Path -LiteralPath $ownedPath) { Stop-Controller 'ERROR_CLEANUP_REQUIRED' "Recover the owned process registry first: $ownedPath" }
            $run=$State.activeRun
            $State.runs += [pscustomobject]@{runId=$run.runId;executionKey=$run.executionKey;scenarioIds=@($run.scenarioIds);result='interrupted';evidence=(Save-ExecutionEvidence $ReportPath);startedAt=$run.startedAt;at=[DateTime]::UtcNow.ToString('o');failureCategory='INTERRUPTED';durationSeconds=[int]([DateTime]::UtcNow-[DateTime]::Parse($run.startedAt).ToUniversalTime()).TotalSeconds}
            $State.activeRun=$null
            $cycle.cleanupRequired=$false
            Set-Phase $State 'TEST_EXECUTED_FAIL' 'interruption reconciled without repeating delivery'
            Write-State $State
        }
        if ($cycle.cleanupRequired -and $report.cleanupRestored -ne $true) { Stop-Controller 'ERROR_CLEANUP_REQUIRED' 'Restore only this run resources and supply cleanup evidence first' }
        if ($report.budgetGrant) {
            $grant = $report.budgetGrant
            if ($grant.grantedBy -ne 'user' -or -not $grant.requestRef -or -not $grant.requestText -or [int]$grant.minutes -le 0) { Stop-Controller 'ERROR_BUDGET_GRANT' 'Extension needs an explicit positive user grant with original request reference and text' }
            $previousGrants = @($cycle.repairs | Where-Object { $_.budgetRequestRef -eq $grant.requestRef })
            $previousGrants += @($cycle.budgetHistory | Where-Object { $_.requestRef -eq $grant.requestRef })
            if ($previousGrants.Count) { Stop-Controller 'ERROR_BUDGET_GRANT' 'A budget request cannot be replayed' }
            if($grant.kind -eq 'new-cycle') {
                Assert-DevelopmentReview $State
                if(-not $cycle.development -or $grant.developmentRequestRef -ne $cycle.development.requestRef -or $cycle.cleanupRequired -or $State.activeRun){Stop-Controller 'ERROR_BUDGET_GRANT' 'A new execution cycle needs the current reviewed development request and completed cleanup.'}
                if(-not $cycle.PSObject.Properties['budgetHistory']){$cycle | Add-Member -NotePropertyName budgetHistory -NotePropertyValue @()}
                $cycle.budgetHistory += [pscustomobject]@{startedAt=$cycle.startedAt;deadlineUtc=$cycle.deadlineUtc;requestRef=$grant.requestRef;evidence=(Save-ExecutionEvidence $ReportPath)}
                $cycle.startedAt=[DateTime]::UtcNow.ToString('o')
                $cycle.deadlineUtc=[DateTime]::UtcNow.AddMinutes([int]$grant.minutes).ToString('o')
                $cycle.development.executionRequestRef=$grant.requestRef
                # Persist before candidate validation: failed preparation also consumes time.
                Write-State $State
            } else {
                $cycle.deadlineUtc=[DateTime]::Parse($cycle.deadlineUtc).ToUniversalTime().AddMinutes([int]$grant.minutes).ToString('o')
            }
        }
        if ([DateTime]::UtcNow -ge [DateTime]::Parse($cycle.deadlineUtc).ToUniversalTime().AddSeconds(-120)) {
            if ($report.cleanupRestored -eq $true) {
                $cycle.cleanupRequired=$false
                $cycle.repairs += [pscustomobject]@{at=[DateTime]::UtcNow.ToString('o');reason=$report.reason;evidence=$evidence;review=(Save-ExecutionEvidence $ReportPath)}
                Write-State $State; Get-ExecutionSummary $State | ConvertTo-Json -Depth 16; return
            }
            if(-not $cycle.development){Assert-ExecutionTime $State}
        }
        Assert-DevelopmentReview $State
        $binding = Get-ExecutionBinding $State
        $scopeBase=$State.revisions.test
        if (-not $cycle.binding) {
            if (-not $cycle.PSObject.Properties['initialTestRevision']) {
                # Recover an interrupted preparation made by the first cycle
                # format. Reflog observation is anchored to the persisted start,
                # never to the new HEAD; legacy histories need not be ancestors.
                $started=[DateTime]::Parse($cycle.startedAt).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ')
                $initial=(@(Get-GitOutput $State.repositories.systemTest @('rev-parse','--verify',"HEAD@{$started}"))|Select-Object -First 1).Trim()
                $cycle | Add-Member -NotePropertyName initialTestRevision -NotePropertyValue $initial
                Add-History $State $State.phase $State.phase "recovered preparation baseline from reflog at $started"
            }
            $scopeBase=$cycle.initialTestRevision
        }
        Assert-ExecutionScope $State $scopeBase $binding.test
        $newKey = Get-ExecutionKey $binding
        $selected = if ($ScenarioIds -and $ScenarioIds.Count -gt 0) { @($ScenarioIds | Sort-Object -Unique) } else { @($cycle.selected) }
        if ($selected.Count -eq 0 -or @($selected | Where-Object { $_ -notin $binding.allScenarioIds }).Count) { Stop-Controller 'ERROR_EXECUTION_SCOPE' 'Unknown/empty selection' }
        if ($newKey -ne $cycle.key) {
            if (-not $report.impactAnalysis -or $report.approvedScope -ne $true) { Stop-Controller 'ERROR_IMPACT_REVIEW' 'Changed candidates need impact analysis and confirmation they remain inside user-approved scope; business repairs must receive business review' }
            if ($cycle.binding -and $binding.sut -ne $cycle.binding.sut -and -not $report.businessReviewPath) { Stop-Controller 'ERROR_BUSINESS_REVIEW' 'Business revision changed: return to business repair/review in this conversation' }
            if ($report.businessReviewPath) {
                $businessReview=Read-StructuredJson $report.businessReviewPath 'business repair review'
                if ($businessReview.result -ne 'PASS' -or $businessReview.sutRevision -ne $binding.sut -or $businessReview.review -notin @('self','independent') -or @($businessReview.evidencePaths).Count -eq 0) { Stop-Controller 'ERROR_BUSINESS_REVIEW' 'Business review must attest the actual repaired revision with evidence' }
                foreach ($path in @($businessReview.evidencePaths)) { $null=Save-ExecutionEvidence $path }
                $null = Save-ExecutionEvidence $report.businessReviewPath
            }
            if ($cycle.binding -and (@($binding.allScenarioIds) -join ',') -ne (@($cycle.binding.allScenarioIds) -join ',')) {
                if ($report.scopeGrant.grantedBy -ne 'user' -or -not $report.scopeGrant.requestRef -or -not $report.scopeGrant.requestText) { Stop-Controller 'ERROR_SCOPE_GRANT' 'Changed required scope needs the actual previously approved user request, not an inferred waiver' }
            }
            foreach ($reuse in @($report.reuse | Where-Object { $_ })) {
                # Only the immediately previous candidate can supply reuse. A
                # complete dependency map must have been reviewed BEFORE its run.
                $prior=@($State.runs | Where-Object { $_.runId -eq $reuse.runId -and $_.executionKey -eq $cycle.key -and $_.result -eq 'pass' -and $reuse.scenarioId -in @($_.scenarioIds) })
                if ($prior.Count -ne 1 -or -not $reuse.rationale -or @($cycle.resultReviews | Where-Object { $_.runId -eq $reuse.runId }).Count -eq 0) { Stop-Controller 'ERROR_UNPROVEN_REUSE' 'Reuse requires a reviewed passing prior run and a reason' }
                if ($binding.configuration -ne $cycle.binding.configuration -or $binding.resolvedHash -ne $cycle.binding.resolvedHash -or $binding.environmentInputs -ne $cycle.binding.environmentInputs -or $binding.harness -ne $cycle.binding.harness -or $binding.contractHash -ne $cycle.binding.contractHash) { Stop-Controller 'ERROR_UNPROVEN_REUSE' 'Environment, harness or scenario contract changed; rerun affected evidence' }
                $oldReview=Read-StructuredJson $prior[0].review.archive 'original slice review'
                $dependencies=$oldReview.dependencies.($reuse.scenarioId)
                if ($dependencies.completeReviewed -ne $true -or @($dependencies.test).Count -eq 0 -or @($dependencies.sut).Count -eq 0) { Stop-Controller 'ERROR_UNPROVEN_REUSE' 'Original review lacks a complete explicit dependency map' }
                foreach ($kind in @('test','sut')) {
                    $repository=if ($kind -eq 'test') { $State.repositories.systemTest } else { $State.repositories.sut }
                    $diff=Get-GitDiffInfo $repository $cycle.binding.$kind $binding.$kind
                    foreach ($file in $diff.changedFiles) {
                        foreach ($pattern in @($dependencies.$kind)) { if ($file -like $pattern) { Stop-Controller 'ERROR_UNPROVEN_REUSE' "Changed dependency: $kind/$file" } }
                    }
                }
                $cycle.reuses += [pscustomobject]@{key=$newKey;scenarioId=$reuse.scenarioId;runId=$reuse.runId;proof=(Save-ExecutionEvidence $ReportPath)}
            }
            $cycle.invalidations += [pscustomobject]@{ previousKey=$cycle.key; nextKey=$newKey; reason=$report.impactAnalysis; at=[DateTime]::UtcNow.ToString('o') }
            # Conservative default: all checks expire. No inferred dependency reuse.
            $cycle.binding=$binding; $cycle.key=$newKey
        }
        if($cycle.development){
            $cycle.development.accepted=$true
            if($report.budgetGrant.kind -eq 'new-cycle'){$cycle.development.executionRequestRef=$report.budgetGrant.requestRef}
        }
        if($cycle.PSObject.Properties['repositoryBindingPending']){$cycle.repositoryBindingPending=$false}
        $cycle.selected=@($selected); $cycle.review=$null; $cycle.cleanupRequired=$false
        Set-ExecutionLocks $State $binding
        if ($report.rootCause -and $report.appliedRepair -and $report.repairReview -eq 'PASS') {
            $repairHash=Get-FileHashValue $ReportPath
            if (@($cycle.repairs | Where-Object { $_.review.sha256 -eq $repairHash }).Count) { Stop-Controller 'ERROR_REPAIR_REPLAY' 'This repair evidence already granted a retry; investigate the repeated cause' }
            $cycle | Add-Member -Force -NotePropertyName retryPermit -NotePropertyValue (Save-ExecutionEvidence $ReportPath)
        }
        $cycle.repairs += [pscustomobject]@{ at=[DateTime]::UtcNow.ToString('o'); reason=$report.reason; evidence=$evidence; review=(Save-ExecutionEvidence $ReportPath); budgetRequestRef=$report.budgetGrant.requestRef }
        $State.verifier=$null
        Set-Phase $State 'TEST_IMPLEMENTED' 'candidate/scope resumed; selected gates require review'
        Write-State $State; Get-ExecutionSummary $State | ConvertTo-Json -Depth 16; return
    }
    if ($Action -eq 'review') {
        $report = Read-StructuredJson $ReportPath 'slice review'
        Assert-ExecutionCurrent $State
        Assert-ExecutionTime $State
        if ($State.phase -notin @('TEST_IMPLEMENTED','TEST_IMPLEMENTATION_VERIFIED')) { Stop-Controller 'ERROR_REPAIR_REQUIRED' 'Use resume with diagnosis and repair evidence before reviewing another attempt' }
        if ($report.bindingKey -ne $cycle.key -or $report.review -notin @('self','independent') -or $report.result -ne 'PASS' -or -not $report.reviewer) { Stop-Controller 'ERROR_SLICE_REVIEW' 'A reviewer must provide PASS for this exact binding; structure validation is not semantic review' }
        if ((@($report.scenarioIds | Sort-Object) -join ',') -ne (@($cycle.selected | Sort-Object) -join ',')) { Stop-Controller 'ERROR_SLICE_SCOPE' 'Review selection must exactly match prepared selection' }
        foreach ($gate in @('design','implementation','environment')) {
            $item = $report.$gate
            if ($item.result -ne 'PASS' -or -not $item.summary -or @($item.evidencePaths).Count -eq 0) { Stop-Controller 'ERROR_SLICE_REVIEW' "Missing actual $gate review and evidence" }
            foreach ($path in @($item.evidencePaths)) { $null=Save-ExecutionEvidence $path }
        }
        if (-not $report.counterexample -or -not $report.waitCondition -or [int]$report.estimatedSeconds -le 0) { Stop-Controller 'ERROR_SLICE_REVIEW' 'Explain discriminating counterexample, correlated completion condition, and measured/estimated execution cost' }
        $cycle.review=Save-ExecutionEvidence $ReportPath
        Set-Phase $State 'TEST_IMPLEMENTATION_VERIFIED' 'reviewed selected slice only; machine environment check follows'
        Write-State $State; Write-Output '[FLOW_CONTROLLER] PASS selected slice reviewed'; return
    }
    if ($Action -eq 'environment') {
        Assert-ExecutionCurrent $State
        $report=Read-StructuredJson $ReportPath 'environment verification'
        if (-not $cycle.review -or $State.phase -ne 'TEST_IMPLEMENTATION_VERIFIED' -or $report.mode -ne 'environment' -or $report.result -notin @('PASS','BLOCKED','FAIL') -or
            $report.testRevision -ne $cycle.binding.test -or $report.sutRevision -ne $cycle.binding.sut -or $report.harnessRevision -ne $cycle.binding.harness -or $report.configurationFingerprint -ne $cycle.binding.configuration -or @($report.steps).Count -eq 0) {
            Stop-Controller 'ERROR_ENVIRONMENT_REPORT' 'Need the actual environment verifier report for this candidate'
        }
        $cycle | Add-Member -Force -NotePropertyName environment -NotePropertyValue (Save-ExecutionEvidence $ReportPath)
        if ($report.result -ne 'PASS') {
            $cycle.repairs += [pscustomobject]@{at=[DateTime]::UtcNow.ToString('o');reason='Environment preflight failed; diagnose the recorded failing checks before resume';evidence=$cycle.environment}
            Set-Phase $State 'TEST_ENVIRONMENT_FAILED' 'preflight failure preserved; resume requires repair evidence'
            Write-State $State; Write-Output '[FLOW_CONTROLLER] BLOCKED environment failed; use resume with repair evidence'; return
        }
        Set-Phase $State 'TEST_ENVIRONMENT_VERIFIED' 'deterministic environment checks passed for selected candidate'
        Write-State $State; Write-Output '[FLOW_CONTROLLER] PASS environment verified'; return
    }
    if ($Action -eq 'start') {
        if($cycle.development -and -not $cycle.development.accepted){Stop-Controller 'ERROR_CANDIDATE_NOT_ACCEPTED' 'Development is open; complete design/implementation and resume before execution'}
        Require-Ceiling $State 'execution'; Assert-DevelopmentReview $State; Assert-ExecutionTime $State; Assert-ExecutionCurrent $State
        if($cycle.development -and -not $cycle.development.executionRequestRef){Stop-Controller 'ERROR_EXECUTION_AUTHORIZATION' 'New development requires explicit new-cycle execution authorization; design/implementation approval alone cannot start tests'}
        if($cycle.repositoryBindingPending){Stop-Controller 'ERROR_REBIND_PENDING' 'Accept the target candidate via resume and revalidate environment before execution'}
        if ($State.activeRun -or $cycle.cleanupRequired -or -not $cycle.review -or $State.phase -ne 'TEST_ENVIRONMENT_VERIFIED') { Stop-Controller 'ERROR_SLICE_NOT_READY' 'Active run, incomplete cleanup, or missing selected review/environment check; no input was delivered' }
        $selectionKey=(@($cycle.selected | Sort-Object) -join ',')
        if (@($State.runs | Where-Object { $_.executionKey -eq $cycle.key -and (@($_.scenarioIds | Sort-Object) -join ',') -eq $selectionKey }).Count -and -not $cycle.retryPermit) { Stop-Controller 'ERROR_REPEAT_WITHOUT_CHANGE' 'Same candidate and selection already ran. Diagnose and provide an actual reviewed repair; increasing timeout/restarting is not a repair.' }
        $review = Read-StructuredJson $cycle.review.archive 'archived review'
        if ([int]$review.estimatedSeconds -gt ([DateTime]::Parse($cycle.deadlineUtc).ToUniversalTime().AddSeconds(-120)-[DateTime]::UtcNow).TotalSeconds) { Stop-Controller 'ERROR_BUDGET_ESTIMATE' 'Selected work cannot fit remaining budget; reduce selection with reviewed scope' }
        $runId=[guid]::NewGuid().ToString('N')
        $State.activeRun=[pscustomobject]@{runId=$runId; executionKey=$cycle.key; scenarioIds=@($cycle.selected); review=$cycle.review; startedAt=[DateTime]::UtcNow.ToString('o'); deadlineUtc=$cycle.deadlineUtc; evidence=(Join-Path (Split-Path -Parent $StatePath) "execution-evidence/$runId/runner-result.json")}
        if ($cycle.PSObject.Properties['retryPermit']) { $cycle.retryPermit=$null }
        Set-Phase $State 'TEST_EXECUTING' 'selected run registered before any input'
        Write-State $State; $State.activeRun | ConvertTo-Json -Depth 8; return
    }
    if ($Action -eq 'finish') {
        if (-not $State.activeRun) { Stop-Controller 'ERROR_ACTIVE_RUN' 'No active run to reconcile' }
        $run=$State.activeRun
        if ((Get-CanonicalPath $ReportPath) -ne (Get-CanonicalPath $run.evidence)) { Stop-Controller 'ERROR_RUN_EVIDENCE' 'Result must come from the registered run output path' }
        $report=Read-StructuredJson $ReportPath 'runner result'
        if ($report.flowRunId -ne $run.runId -or $report.executionKey -ne $run.executionKey -or (@($report.scenarioIds | Sort-Object) -join ',') -ne (@($run.scenarioIds | Sort-Object) -join ',')) { Stop-Controller 'ERROR_RUN_EVIDENCE' 'Result run/binding/selection mismatch' }
        $saved=Save-ExecutionEvidence $ReportPath
        $stages=@(); $firstAssertion=$null
        if ($report.counts.raw -and (Test-Path -LiteralPath $report.counts.raw -PathType Leaf) -and (Test-PathWithin $report.counts.raw (Join-Path $State.repositories.systemTest "changes/$($State.changeName)/evidence"))) {
            $runtime=Read-StructuredJson $report.counts.raw 'runtime timing evidence'
            $firstAssertion=@($runtime.businessMetrics | Where-Object { $_.kind -eq 'assertion' -and $_.scenarioId -in $run.scenarioIds } | Sort-Object at | Select-Object -First 1)
            $firstAssertion=if($firstAssertion.Count){$firstAssertion[0].at}else{$null}
            $stages=@($runtime.steps | Where-Object { $_.elapsedSeconds -ge 0 } | Group-Object phase | ForEach-Object { [pscustomobject]@{phase=$_.Name;seconds=[Math]::Round(($_.Group | Measure-Object elapsedSeconds -Sum).Sum,3)} })
        }
        $cycle.cleanupRequired=($report.cleanup.succeeded -ne $true -or $report.cleanup.retainedState -eq $true)
        $passed=($report.status -eq 'PASS' -and -not $cycle.cleanupRequired -and [int]$report.counts.failed -eq 0 -and [int]$report.counts.skipped -eq 0 -and [int]$report.counts.passed -gt 0)
        $State.runs += [pscustomobject]@{ runId=$run.runId; executionKey=$run.executionKey; scenarioIds=@($run.scenarioIds); review=$run.review; result=$(if ($passed) {'pass'} else {'fail'}); evidence=$saved; startedAt=$run.startedAt; firstBusinessAssertionAt=$firstAssertion; at=[DateTime]::UtcNow.ToString('o'); durationSeconds=[int]([DateTime]::UtcNow-[DateTime]::Parse($run.startedAt).ToUniversalTime()).TotalSeconds; stages=$stages; primaryFailure=$report.primaryFailure; failureCategory=$report.classification; cleanupRequired=$cycle.cleanupRequired }
        $State.activeRun=$null
        Set-Phase $State $(if ($passed) {'TEST_EXECUTED_PASS'} else {'TEST_EXECUTED_FAIL'}) 'selected run reconciled; result semantic review still required'
        Write-State $State; Get-ExecutionSummary $State | ConvertTo-Json -Depth 16; return
    }
    Stop-Controller 'ERROR_EXECUTION_ACTION' 'Unsupported execution action'
}
