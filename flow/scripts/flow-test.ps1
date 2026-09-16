[CmdletBinding()]
param(
    [Parameter(Mandatory=$true,Position=0)] [ValidateSet('prepare','advance','resume','status')] [string]$Command,
    [Parameter(Mandatory=$true)] [string]$StatePath,
    [string[]]$ScenarioIds,
    [string]$ReviewPath,
    [string]$ResultReviewPath,
    [string]$RepairPath,
    [string]$ImportEvidencePath
)
$ErrorActionPreference='Stop'
$controller=Join-Path $PSScriptRoot 'flow-test-controller.ps1'
function Read-ExecutionJson([string]$Raw) {
    if ((Get-Command ConvertFrom-Json).Parameters.ContainsKey('DateKind')) { return $Raw | ConvertFrom-Json -DateKind String }
    return $Raw | ConvertFrom-Json
}
function Write-ReviewInput([string]$Path,$Value) {
    if (-not $Path -or (Test-Path -LiteralPath $Path)) { return }
    [void](New-Item -ItemType Directory -Force -Path (Split-Path -Parent $Path))
    [IO.File]::WriteAllText($Path,($Value|ConvertTo-Json -Depth 12),[Text.UTF8Encoding]::new($false))
}
function Invoke-Controller([string]$Action, [hashtable]$Extra=@{}) {
    $lines=@(& $controller execution -Action $Action -StatePath $StatePath @Extra)
    if ($LASTEXITCODE -ne 0 -or @($lines | Where-Object { "$_" -match '^\[FLOW_CONTROLLER\] ERROR' }).Count) { throw ($lines -join "`n") }
    return $lines
}
# Serialize the facade for the whole run. The lock is released by the OS on crash;
# the persisted activeRun prevents a second invocation from delivering input again.
$lockPath=[IO.Path]::GetFullPath($StatePath)+'.execution.lock'
$lock=$null
try {
    if ($Command -ne 'status') { $lock=[IO.File]::Open($lockPath,'OpenOrCreate','ReadWrite','None') }
    switch ($Command) {
        'status' { Invoke-Controller 'status'; break }
        'prepare' { Invoke-Controller 'prepare' @{ScenarioIds=$ScenarioIds}; break }
        'resume' {
            if ($ImportEvidencePath) { Invoke-Controller 'import' @{EvidencePath=$ImportEvidencePath}; break }
            $state=Read-ExecutionJson (Get-Content -LiteralPath $StatePath -Raw -Encoding utf8)
            if ($state.activeRun) {
                if (Test-Path -LiteralPath $state.activeRun.evidence -PathType Leaf) { Invoke-Controller 'finish' @{ReportPath=[string]$state.activeRun.evidence}; break }
                if (-not $RepairPath) { throw "Active run $($state.activeRun.runId) has no final result. Inspect its owned resources and raw evidence; do not redeliver." }
            }
            Invoke-Controller 'resume' @{ReportPath=$RepairPath;ScenarioIds=$ScenarioIds}; break
        }
        'advance' {
            if ($ResultReviewPath) { Invoke-Controller 'result' @{ReportPath=$ResultReviewPath}; break }
            $candidate=Read-ExecutionJson (Get-Content -LiteralPath $StatePath -Raw -Encoding utf8)
            if (-not $candidate.execution -or [DateTime]::UtcNow -ge [DateTime]::Parse($candidate.execution.deadlineUtc).ToUniversalTime().AddSeconds(-120)) { throw 'Execution budget exhausted; only result review, status and owned-resource recovery are allowed.' }
            if ($candidate.phase -in @('TEST_EXECUTED_FAIL','TEST_ENVIRONMENT_FAILED')) { throw 'Recorded failure requires resume with diagnosis and repair evidence before another attempt.' }
            $candidateRoot=Join-Path $candidate.repositories.systemTest "changes/$($candidate.changeName)"
            if ($ReviewPath) {
                $manifest=Read-ExecutionJson (Get-Content -LiteralPath (Join-Path $candidateRoot 'manifest.yaml') -Raw -Encoding utf8)
                $derivedPath=Join-Path $candidateRoot $manifest.testCasesContract.path
                $derived=Read-ExecutionJson (Get-Content -LiteralPath $derivedPath -Raw -Encoding utf8)
                $validation=@(& (Join-Path $PSScriptRoot 'validate-test-cases.ps1') -TestCasesPath (Join-Path $candidateRoot $derived.source.path) -Mode implementation -CanonicalRevision $derived.source.canonicalRevision -ManifestPath (Join-Path $candidateRoot 'manifest.yaml') -DerivedContractPath $derivedPath -TestPlanPath (Join-Path $candidateRoot 'test-plan.md') -JavaSourceRoot (Join-Path $candidate.repositories.systemTest 'backend-tests/src/test') -ScenarioIds @($candidate.execution.selected))
                if ($LASTEXITCODE -ne 0) { throw ($validation -join "`n") }
                Invoke-Controller 'review' @{ReportPath=$ReviewPath} | Out-Host
            }
            $candidate=Read-ExecutionJson (Get-Content -LiteralPath $StatePath -Raw -Encoding utf8)
            if ($candidate.phase -eq 'TEST_IMPLEMENTATION_VERIFIED') {
                $environmentPath=Join-Path (Split-Path -Parent $StatePath) ('execution-evidence/environment-'+[guid]::NewGuid().ToString('N')+'.json')
                $output=@(& (Join-Path $PSScriptRoot 'validate-test-environment.ps1') -ResolvedManifestPath (Join-Path $candidateRoot 'resolved-manifest.json') -StatePath $StatePath -OutputPath $environmentPath -VerifierId 'flow-test-preflight' -ControllerPath $controller)
                $environmentExit=$LASTEXITCODE
                Invoke-Controller 'environment' @{ReportPath=$environmentPath} | Out-Host
                if ($environmentExit -ne 0) { throw ($output -join "`n") }
            }
            $run=Read-ExecutionJson (Invoke-Controller 'start' | Out-String)
            $state=Read-ExecutionJson (Get-Content -LiteralPath $StatePath -Raw -Encoding utf8)
            $repo=[string]$state.repositories.systemTest
            $runner=Join-Path $repo 'scripts/system-test.ps1'
            $saved=@{}
            $values=@{FLOW_EXECUTION_STATE=[IO.Path]::GetFullPath($StatePath);FLOW_EXECUTION_RUN=[string]$run.runId;FLOW_EXECUTION_KEY=[string]$run.executionKey;FLOW_EXECUTION_DEADLINE=[string]$run.deadlineUtc}
            foreach ($key in $values.Keys) { $saved[$key]=[Environment]::GetEnvironmentVariable($key); [Environment]::SetEnvironmentVariable($key,$values[$key]) }
            $runnerError=$null
            try {
                $manifest=Get-Content -LiteralPath (Join-Path $repo "changes/$($state.changeName)/resolved-manifest.json") -Raw -Encoding utf8 | ConvertFrom-Json
                & $runner run -Change $state.changeName -Suite api -ExecutionMode orchestrated -ScenarioIds @($run.scenarioIds) -ConfigurationFingerprint $state.execution.binding.configuration -EnvFile $manifest.configuration.environmentFile -HarnessCertificationPath $state.harnessCertification.path -StructuredResultPath $run.evidence
            } catch { $runnerError=$_ } finally { foreach ($key in $saved.Keys) { [Environment]::SetEnvironmentVariable($key,$saved[$key]) } }
            # Even failed runs must be reconciled; missing output remains active.
            Invoke-Controller 'finish' @{ReportPath=[string]$run.evidence}
            if ($runnerError) { throw "Run failed and was recorded: $($runnerError.Exception.Message)" }
            break
        }
    }
} finally {
    if ($lock) {
        try {
            $summaryText=Invoke-Controller 'status' | Out-String
            $summary=Read-ExecutionJson $summaryText
            if ($summary.bindingKey) {
                $review=[ordered]@{bindingKey=$summary.bindingKey;scenarioIds=@($summary.selected);review='self';reviewer='current-agent';result='PENDING';counterexample='';waitCondition='';estimatedSeconds=0}
                foreach($gate in @('design','implementation','environment')){$review[$gate]=@{result='PENDING';summary='';evidencePaths=@()}}
                Write-ReviewInput $summary.reviewInputPath $review
                Write-ReviewInput $summary.repairInputPath @{result='PENDING';review='self';reason='';impactAnalysis='';approvedScope=$false;evidencePaths=@()}
                foreach($pending in @($summary.pendingResultReviews)){
                    Write-ReviewInput $pending.path @{runId=$pending.runId;bindingKey=$summary.bindingKey;review='self';reviewer='current-agent';result='PENDING';summary='';evidencePaths=@($pending.evidence)}
                }
            }
            $directory=Split-Path -Parent ([IO.Path]::GetFullPath($StatePath))
            [IO.File]::WriteAllText((Join-Path $directory 'execution-summary.json'),$summaryText,[Text.UTF8Encoding]::new($false))
            $lines=@('# 当前集成测试执行摘要','','本文件由 flow-test.ps1 从唯一 controller state 生成；历史日志不改变当前结论。','',
                "截止时间（UTC）：$($summary.deadlineUtc)；剩余 $($summary.remainingSeconds) 秒。",'',
                '## 业务场景验证进度','','| 场景 | 当前结果 |','|---|---|')
            foreach ($row in @($summary.scenarios)) { $lines += "| $($row.id) | $($row.result) |" }
            $lines+=@('','## 发现的问题','')
            foreach ($issue in @($summary.issues)) { $lines += "- $($issue.reason)" }
            $lines+=@('','## 各次运行耗时','')
            foreach ($timing in @($summary.timings)) {
                $lines += "- $($timing.runId)：$($timing.durationSeconds) 秒"
                foreach($stage in @($timing.stages)) { $lines += "- $($timing.runId) / $($stage.phase)：$($stage.seconds) 秒" }
            }
            $lines+=@('','## 当前阻断','',"下一动作：$($summary.next)；需要清理：$($summary.cleanupRequired)；候选漂移：$($summary.candidateDrift)。",'',"全量已审核通过：$($summary.complete)。未执行、陈旧或未完成审核的场景均不计为通过。")
            [IO.File]::WriteAllText((Join-Path $directory 'execution-summary.md'),($lines -join "`n"),[Text.UTF8Encoding]::new($false))
        } catch { Write-Warning "Current summary could not be generated: $($_.Exception.Message)" }
        $lock.Dispose()
    }
}
