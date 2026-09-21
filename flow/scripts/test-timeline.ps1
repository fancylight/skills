# Observation only: never grants execution, changes controller state or awards PASS.
function Get-TimelineMarkdown($Timeline) {
    $lines=@('<!-- FLOW_TIMELINE:START -->','','## 测试交付全过程耗时','',
        "总墙钟：$($Timeline.wallSeconds) 秒；暂停：$($Timeline.pausedSeconds) 秒；中断或未分类：$($Timeline.unclassifiedSeconds) 秒。",'',
        '阶段与运行细分不可重复相加；没有记录的历史时间不推测。','')
    foreach($name in @($Timeline.stageElapsed.Keys)){$lines+="- ${name}：$($Timeline.stageElapsed[$name].seconds) 秒，进入 $($Timeline.stageElapsed[$name].visits) 次"}
    foreach($item in @($Timeline.interventions)){$lines+="- 用户介入 $($item.category)：$($item.reason)"}
    $lines+=@('',"本周期交付状态：$($Timeline.outcome)（不改变测试判定）",'<!-- FLOW_TIMELINE:END -->')
    return ($lines -join "`n")
}
function Invoke-TestTimeline {
    [CmdletBinding()]
    param([string]$StatePath,[string]$Action='summary',[string]$Stage,[string]$Reason,
        [string]$EventId,[string]$Reference,[string]$Intervention,[string]$Outcome,
        [string]$CycleId,[string]$SessionId,[datetime]$Now=[datetime]::UtcNow)
    $lock=$null
    try {
        if ($Action -notin @('enter','pause','resume','finish','summary')) { throw 'Unknown timeline action' }
        $directory=Split-Path -Parent ([IO.Path]::GetFullPath($StatePath))
        $path=Join-Path $directory 'test-timeline.jsonl'
        if ($Action -ne 'summary') {
            [void][IO.Directory]::CreateDirectory($directory)
            $lock=[IO.File]::Open("$path.lock",'OpenOrCreate','ReadWrite','None')
        }
        $events=@(); $missing=0
        if (Test-Path -LiteralPath $path) {
            foreach ($line in [IO.File]::ReadAllLines($path)) {
                try { if ($line.Trim()) { $options=@{}; if((Get-Command ConvertFrom-Json).Parameters.ContainsKey('DateKind')){$options.DateKind='String'}; $events+=($line|ConvertFrom-Json @options) } } catch { $missing++ }
            }
        }
        if (-not $SessionId) { $SessionId=$env:CODEX_THREAD_ID }
        if (-not $SessionId) { $SessionId="process-$PID" }
        $latest=if($events.Count){$events[-1]}else{$null}
        if (-not $CycleId) { $CycleId=if($latest){[string]$latest.cycleId}else{[guid]::NewGuid().ToString('N')} }
        if ($Action -ne 'summary') {
            if (-not $EventId) { $EventId=[guid]::NewGuid().ToString('N') }
            if (-not @($events|Where-Object eventId -eq $EventId).Count) {
                $cycleEvents=@($events|Where-Object cycleId -eq $CycleId)
                if ($cycleEvents.Count -and $cycleEvents[-1].action -eq 'finish' -and -not ($Action -eq 'resume' -and $cycleEvents[-1].outcome -eq 'partial')) { throw 'Finished cycle: resume partial delivery, or use an explicit new CycleId for newly authorized scope' }
                if ($Action -eq 'enter' -and $Stage -notin @('business','technical','review','implementation','preparation','execution','repair','delivery')) { throw 'A valid stage is required' }
                if ($Intervention -and $Intervention -notin @('business','permission-budget','framework','user-change')) { throw 'Unknown intervention category' }
                if ($Action -eq 'finish' -and $Outcome -notin @('complete','partial','cancelled')) { throw 'finish requires complete, partial or cancelled' }
                if ($Action -in @('pause','resume','finish') -and -not $cycleEvents.Count) { throw 'Enter a stage before pausing, resuming or finishing' }
                $effectiveStage=if($Stage){$Stage}elseif($cycleEvents.Count){$cycleEvents[-1].stage}else{''}
                $event=[ordered]@{schemaVersion=1;eventId=$EventId;cycleId=$CycleId;parentCycleId=$(if($latest -and $latest.cycleId -ne $CycleId){$latest.cycleId}else{$null});at=$Now.ToUniversalTime().ToString('o');action=$Action;stage=$effectiveStage;reason=$Reason;reference=$Reference;intervention=$Intervention;outcome=$Outcome;sessionId=$SessionId}
                # Preserve an incomplete last line after a crash without concatenating a new event to it.
                if ((Test-Path $path) -and (Get-Item $path).Length -gt 0 -and -not [IO.File]::ReadAllText($path).EndsWith("`n")) { [IO.File]::AppendAllText($path,"`n",[Text.UTF8Encoding]::new($false)) }
                [IO.File]::AppendAllText($path,(($event|ConvertTo-Json -Compress)+"`n"),[Text.UTF8Encoding]::new($false))
                $events+=[pscustomobject]$event
            }
        }
        $selected=@($events|Where-Object cycleId -eq $CycleId)
        $stages=[ordered]@{}; $paused=0.0; $unclassified=0.0; $interventions=@(); $wall=0.0
        for($i=0;$i -lt $selected.Count;$i++) {
            $current=$selected[$i]; $next=if($i+1 -lt $selected.Count){$selected[$i+1]}else{$null}
            $start=[datetime]::Parse([string]$current.at).ToUniversalTime()
            $end=if($next){[datetime]::Parse([string]$next.at).ToUniversalTime()}else{$Now.ToUniversalTime()}
            $seconds=[math]::Max(0,($end-$start).TotalSeconds)
            if($current.intervention){$interventions+=@{category=$current.intervention;reason=$current.reason;at=$current.at}}
            if($current.action -eq 'finish'){
                if($current.outcome -eq 'partial' -and $next){$paused+=$seconds}
                continue
            }
            if($current.action -eq 'pause'){$paused+=$seconds}
            elseif(-not $next -or $next.sessionId -ne $current.sessionId){$unclassified+=$seconds}
            else {
                if(-not $stages.Contains($current.stage)){$stages[$current.stage]=@{seconds=0.0;visits=0}}
                $stages[$current.stage].seconds+=$seconds
            }
            if($current.action -eq 'enter') {
                if(-not $stages.Contains($current.stage)){$stages[$current.stage]=@{seconds=0.0;visits=0}}
                $stages[$current.stage].visits++
            }
        }
        if($selected.Count){
            $end=if($selected[-1].action -eq 'finish'){[datetime]::Parse([string]$selected[-1].at).ToUniversalTime()}else{$Now.ToUniversalTime()}
            $wall=[math]::Max(0,($end-[datetime]::Parse([string]$selected[0].at).ToUniversalTime()).TotalSeconds)
        }
        [pscustomobject]@{cycleId=$CycleId;startedAt=$(if($selected.Count){$selected[0].at}else{$null});wallSeconds=$wall;stageElapsed=$stages;pausedSeconds=$paused;unclassifiedSeconds=$unclassified;missingRecords=$missing;interventions=$interventions;outcome=$(if($selected.Count){$selected[-1].outcome}else{$null});note='Stage elapsed is not model active time; open/interrupted intervals are unclassified. Runtime substeps are contained, not additive.'}
    } catch { Write-Warning "Timeline unavailable; testing may continue: $($_.Exception.Message)" }
    finally { if($lock){$lock.Dispose()} }
}
