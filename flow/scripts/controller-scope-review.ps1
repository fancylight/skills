# Loaded by the controller only; uses its canonical Git, lock and atomic-write helpers.
function Record-ImplementationScopeReview($State) {
    Require-Ceiling $State 'implementation'
    if ($State.phase -ne 'TEST_IMPLEMENTING' -or $State.activeRun -or @($State.runs).Count -gt 0) {
        Stop-Controller 'ERROR_TRANSITION' 'scope review requires implementation before any run'
    }
    $lease = @($State.leases | Where-Object { $_.active -and $_.leaseId -eq $LeaseId -and $_.agentId -eq $AgentId -and $_.role -eq 'test-implementer' })
    if ($lease.Count -ne 1 -or [DateTimeOffset]::Parse($lease[0].expiresAt).UtcDateTime -le [DateTime]::UtcNow) {
        Stop-Controller 'ERROR_LEASE_INVALID' 'current implementation owner and unexpired lease required'
    }
    $report = Read-StructuredJson $ReportPath 'scope design review'
    $previous = [string]$State.revisions.designRevision
    $proposed = Resolve-GitRevision $State.repositories.systemTest $ProposedTestRevision
    if ($proposed -ne (Get-GitHead $State.repositories.systemTest) -or $proposed -eq $previous) {
        Stop-Controller 'ERROR_REVISION_DRIFT' 'scope review must bind a new canonical HEAD'
    }
    Assert-GitWorktreeClean $State.repositories.systemTest
    $diff = Get-GitDiffInfo $State.repositories.systemTest $lease[0].implementationBaseRevision $proposed
    $allowed = @(Get-EffectiveLeaseAuthorizedPaths $State $lease[0])
    foreach ($file in $diff.changedFiles) {
        if (-not (@($allowed | Where-Object { $file -like $_ }).Count -gt 0)) { Stop-Controller 'ERROR_SCOPE' 'scope review cannot expand repository/path authority' }
    }
    if ($report.schemaVersion -ne 1 -or $report.result -ne 'PASS' -or $report.mode -ne 'design-scope' -or
        [string]::IsNullOrWhiteSpace($VerifierId) -or $report.verifierId -ne $VerifierId -or
        $report.grantedBy -ne 'user' -or [string]::IsNullOrWhiteSpace($report.requestText) -or [string]::IsNullOrWhiteSpace($report.requestRef) -or
        [string]::IsNullOrWhiteSpace($report.summary) -or $report.changeName -ne $State.changeName -or
        $report.previousTestRevision -ne $previous -or $report.testRevision -ne $proposed -or
        $report.canonicalRevision -ne $State.revisions.testBaseline -or $report.sutRevision -ne $State.revisions.sut -or
        $report.harnessRevision -ne $State.revisions.harness -or $report.configurationFingerprint -ne $State.configurationFingerprint -or
        $report.diffHash -ne $diff.diffHash) { Stop-Controller 'ERROR_SCOPE_REVIEW' 'scope review is missing user intent, semantic review, or current bindings' }
    $source = "changes/$($State.changeName)/test-cases.yaml"
    $oldText = (@(Get-GitOutput $State.repositories.systemTest @('show', "${previous}:$source")) -join "`n") + "`n"
    $currentPath = Join-Path $State.repositories.systemTest $source
    if ($report.previousSourceSha256 -ne (Get-StringHash $oldText) -or $report.currentSourceSha256 -ne (Get-FileHashValue $currentPath)) {
        Stop-Controller 'ERROR_SCOPE_REVIEW' 'canonical source hashes differ from reviewed inputs'
    }
    $temporary = Join-Path ([IO.Path]::GetTempPath()) ('flow-scope-' + [guid]::NewGuid().ToString('N') + '.yaml')
    try {
        [IO.File]::WriteAllText($temporary, $oldText, [Text.UTF8Encoding]::new($false))
        $validator = Join-Path $PSScriptRoot 'validate-test-cases.ps1'
        $oldOutput = @(& $validator -TestCasesPath $temporary -Mode business -ExportJson)
        if ($LASTEXITCODE -ne 0) { Stop-Controller 'ERROR_SCOPE_REVIEW' 'previous canonical source is invalid' }
        $newOutput = @(& $validator -TestCasesPath $currentPath -Mode business -RequireBusiness -ExportJson)
        if ($LASTEXITCODE -ne 0) { Stop-Controller 'ERROR_SCOPE_REVIEW' 'current canonical business source is invalid' }
        $oldCases = ($oldOutput -join "`n") | ConvertFrom-Json
        $newCases = ($newOutput -join "`n") | ConvertFrom-Json
        $newIds = @($newCases.scenarios | ForEach-Object { $_.id })
        $removed = @($oldCases.scenarios | Where-Object { $_.required -eq $true -and $_.id -notin $newIds } | ForEach-Object { $_.id } | Sort-Object)
        if (($removed -join "`n") -ne (@($report.removedScenarioIds | Sort-Object) -join "`n")) {
            Stop-Controller 'ERROR_SCOPE_REVIEW' 'declared exclusions must exactly match removed required scenarios'
        }
        foreach ($oldCase in @($oldCases.scenarios | Where-Object { $_.required -eq $true -and $_.id -in $newIds })) {
            $retained = @($newCases.scenarios | Where-Object { $_.id -eq $oldCase.id })[0]
            if ($retained.required -ne $true -or ($oldCase.integration -eq 'Y' -and $retained.integration -ne 'Y')) {
                Stop-Controller 'ERROR_SCOPE_REVIEW' 'retained required scenarios cannot be silently weakened'
            }
        }
    } finally { if (Test-Path -LiteralPath $temporary) { Remove-Item -LiteralPath $temporary -Force } }
    if ($null -eq $State.PSObject.Properties['scopeDesignReviews']) { $State | Add-Member -NotePropertyName scopeDesignReviews -NotePropertyValue @() }
    if (@($State.scopeDesignReviews | Where-Object { $_.testRevision -eq $proposed }).Count -gt 0) {
        Stop-Controller 'ERROR_SCOPE_REVIEW' 'scope review already recorded for this revision'
    }
    $State.scopeDesignReviews += [pscustomobject]@{
        at=[DateTime]::UtcNow.ToString('o'); verifierId=$VerifierId; testRevision=$proposed; previousTestRevision=$previous
        canonicalRevision=$State.revisions.testBaseline; sutRevision=$State.revisions.sut; harnessRevision=$State.revisions.harness
        configurationFingerprint=$State.configurationFingerprint; currentSourceSha256=$report.currentSourceSha256
        previousSourceSha256=$report.previousSourceSha256; removedScenarioIds=@($removed); diffHash=$diff.diffHash
        reportSha256=(Get-FileHashValue $ReportPath); summaryHash=(Get-StringHash $report.summary)
        grantedBy='user'; requestText=$report.requestText; requestRef=$report.requestRef
    }
    Add-History $State $State.phase $State.phase 'recorded user-authorized scope design review; no execution gate advanced'
    Write-State $State
    Write-Output '[FLOW_CONTROLLER] PASS'
}
