$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot '../test-timeline.ps1')
$root=Join-Path ([IO.Path]::GetTempPath()) ('flow-timeline-'+[guid]::NewGuid().ToString('N'))
$state=Join-Path $root 'automation-state.yaml'
$start=[datetime]'2026-09-21T00:00:00Z'
function Check($ok,$message){if(-not $ok){throw $message}}
try {
    $common=@{StatePath=$state;SessionId='one';CycleId='cycle'}
    $null=Invoke-TestTimeline @common -Action enter -Stage business -EventId a -Now $start
    $null=Invoke-TestTimeline @common -Action enter -Stage technical -EventId b -Now $start.AddSeconds(10)
    $null=Invoke-TestTimeline @common -Action enter -Stage technical -EventId b -Now $start.AddSeconds(15)
    $null=Invoke-TestTimeline @common -Action pause -Intervention framework -Reason binding -EventId c -Now $start.AddSeconds(20)
    $null=Invoke-TestTimeline @common -Action resume -EventId d -Now $start.AddSeconds(30)
    $common.SessionId='after-restart'
    $null=Invoke-TestTimeline @common -Action enter -Stage repair -EventId e -Now $start.AddSeconds(50)
    $s=Invoke-TestTimeline @common -Action finish -Outcome partial -EventId f -Now $start.AddSeconds(60)
    Check ($s.wallSeconds -eq 60) 'wall time excludes paused or interrupted time'
    Check ($s.pausedSeconds -eq 10 -and $s.unclassifiedSeconds -eq 20) 'interruption attributed as active work'
    Check ($s.stageElapsed.business.seconds -eq 10 -and $s.stageElapsed.technical.seconds -eq 10) 'stage timing or duplicate event wrong'
    Check ($s.interventions.Count -eq 1 -and $s.outcome -eq 'partial') 'intervention/outcome lost'
    Check (-not (Test-Path $state)) 'timeline created controller state'
    $later=Invoke-TestTimeline @common -Now $start.AddSeconds(100)
    Check ($later.wallSeconds -eq 60) 'finished cycle keeps growing'
    $warnings=@(); $null=Invoke-TestTimeline @common -Action enter -Stage business -WarningVariable warnings
    Check ($warnings.Count -gt 0) 'finished cycle silently reopened'
    $s=Invoke-TestTimeline @common -Action resume -EventId resumed -Now $start.AddSeconds(80)
    Check ($s.wallSeconds -eq 80 -and $s.pausedSeconds -eq 30) 'partial delivery recovery reset original cycle'
    $null=Invoke-TestTimeline @common -Action finish -Outcome partial -EventId finishedAgain -Now $start.AddSeconds(90)
    $s=Invoke-TestTimeline -StatePath $state -Action enter -Stage business -CycleId next -EventId g -SessionId two -Now $start.AddSeconds(100)
    Check ($s.wallSeconds -eq 0) 'new explicit cycle did not start'
    [IO.File]::AppendAllText((Join-Path $root 'test-timeline.jsonl'),'{broken')
    $s=Invoke-TestTimeline -StatePath $state -Action pause -EventId h -Now $start.AddSeconds(110)
    Check ($s.missingRecords -eq 1) 'partial record not reported'
    $s=Invoke-TestTimeline -StatePath $state -Now $start.AddSeconds(120)
    Check ($s.missingRecords -eq 1 -and $s.pausedSeconds -eq 10) 'partial line swallowed next event'
    $held=[IO.File]::Open((Join-Path $root 'test-timeline.jsonl.lock'),'OpenOrCreate','ReadWrite','None')
    try { $warnings=@(); $null=Invoke-TestTimeline -StatePath $state -Action resume -WarningVariable warnings; Check ($warnings.Count -gt 0) 'lock collision not surfaced' } finally {$held.Dispose()}
    [IO.File]::WriteAllText((Join-Path $root 'execution-summary.json'),'{"complete":false,"scenarios":[{"id":"unrun","result":"PENDING"}]}')
    [IO.File]::WriteAllText((Join-Path $root 'execution-summary.md'),'Existing business results')
    & (Join-Path $PSScriptRoot '../flow-test.ps1') timeline -StatePath $state -TimelineAction finish -Outcome partial -EventId cli-finish | Out-Null
    Check ($LASTEXITCODE -eq 0) 'facade observation should not fail testing'
    $presentation=Get-Content (Join-Path $root 'execution-summary.json') -Raw | ConvertFrom-Json
    Check (-not $presentation.complete -and $presentation.scenarios[0].result -eq 'PENDING' -and $presentation.timeline.outcome -eq 'partial') 'summary refresh changed business outcome or lost finish time'
    Check ((Get-Content (Join-Path $root 'execution-summary.md') -Raw).Contains('FLOW_TIMELINE:START')) 'final timing not shown in existing summary'
    '[TEST_TIMELINE] PASS'
} finally {
    if (([IO.Path]::GetFullPath($root)).StartsWith([IO.Path]::GetFullPath([IO.Path]::GetTempPath()))) {Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue}
}
