# Project-local Docker policy. Configuration/SUT lifecycle remains owned by the existing runner.
function Find-ProjectEnvironmentPolicy($Resolved) {
    $found = @()
    foreach ($origin in @($Resolved.runner.workingDirectory, $Resolved.configuration.provider.repository, $env:FLOW_ORCH_ROOT)) {
        if (-not $origin) { continue }
        $dir = [IO.DirectoryInfo]::new([IO.Path]::GetFullPath([string]$origin))
        while ($null -ne $dir) {
            $candidate = Join-Path $dir.FullName '.flow/test-environment.json'
            if (Test-Path -LiteralPath $candidate -PathType Leaf) { $found += $candidate; break }
            $dir = $dir.Parent
        }
    }
    $found = @($found | Select-Object -Unique)
    if ($found.Count -gt 1) { throw 'Conflicting project environment policies; use the correct project/work directory.' }
    if ($found.Count) { return $found[0] }
    return ''
}

function Invoke-ProjectDocker([string[]]$Arguments) {
    $timeout = 10000
    if ($env:FLOW_EXECUTION_DEADLINE) {
        $remaining = ([datetime]::Parse($env:FLOW_EXECUTION_DEADLINE).ToUniversalTime().AddSeconds(-120) - [datetime]::UtcNow).TotalMilliseconds
        if ($remaining -le 0) { throw 'Execution budget exhausted; do not start environment work.' }
        $timeout = [int][Math]::Min($timeout, $remaining)
    }
    $out = [IO.Path]::GetTempFileName(); $err = [IO.Path]::GetTempFileName()
    try {
        $process = Start-Process -FilePath 'docker' -ArgumentList $Arguments -WindowStyle Hidden -PassThru -RedirectStandardOutput $out -RedirectStandardError $err
        if (-not $process.WaitForExit($timeout)) { $process.Kill(); throw 'Docker command timed out; inspect Docker Desktop, do not create a replacement instance.' }
        if ($process.ExitCode -ne 0) { throw "Docker $($Arguments[0]) failed; inspect the named existing container." }
        return [IO.File]::ReadAllText($out)
    } finally { Remove-Item -LiteralPath $out,$err -Force -ErrorAction SilentlyContinue }
}

function Invoke-ProjectEnvironmentPrepare {
    param($Resolved, [string]$PolicyPath, [switch]$Ensure, [scriptblock]$Docker = { param($Arguments) Invoke-ProjectDocker $Arguments })
    $started = [datetime]::UtcNow
    $policy = Get-Content -LiteralPath $PolicyPath -Raw -Encoding UTF8 | ConvertFrom-Json
    if ($policy.schemaVersion -ne 1) { throw 'Unsupported project environment policy version.' }
    $issues = [Collections.Generic.List[object]]::new()
    $items = [Collections.Generic.List[object]]::new()
    $pending = @()
    # Configuration source is stable; the provider's traced build checkout may legitimately differ.
    $provider = [IO.Path]::GetFullPath([string]$Resolved.configuration.provider.configurationRepository).TrimEnd('\','/')
    $expectedProvider = [IO.Path]::GetFullPath([string]$policy.configurationRepository).TrimEnd('\','/')
    if ($provider -ne $expectedProvider) { $issues.Add(@{resource='config-center'; reason='Unexpected configuration provider repository'; nextAction='Use the project config-center and regenerate the resolved environment.'}) }
    foreach ($resource in @($Resolved.resources)) {
        if ($resource.kind -eq 'configuration-provider') { continue }
        $matches = @($policy.middleware | Where-Object { $_.kind -eq $resource.kind })
        if ($matches.Count -ne 1 -or $resource.lifecycle -ne 'external') {
            $issues.Add(@{resource=$resource.id; reason='Resource is not an approved external middleware'; nextAction='Declare an existing approved dependency; do not create a container.'}); continue
        }
        $entry = $matches[0]
        if ([string]$entry.container -notmatch '^[a-zA-Z0-9][a-zA-Z0-9_.-]*$') { throw 'Invalid approved container name.' }
        $probe = @($Resolved.probes | Where-Object { $_.id -eq $resource.preflightProbe })
        $validEndpoint = $false
        if ($probe.Count -eq 1) {
            try {
                if ($probe[0].kind -eq 'http') { $uri = [uri]$probe[0].url; $hostName = $uri.Host; $port = $uri.Port }
                else { $hostName = [string]$probe[0].host; $port = [int]$probe[0].port }
                $validEndpoint = $hostName -in @('localhost','127.0.0.1','::1') -and $port -eq [int]$entry.hostPort
            } catch { $validEndpoint = $false }
        }
        if (-not $validEndpoint) {
            $issues.Add(@{resource=$resource.id; reason='Endpoint differs from approved container binding'; nextAction="Use $($entry.container) on local port $($entry.hostPort); correct the configuration and re-resolve it, never silently redirect."}); continue
        }
        try {
            $containers = @((& $Docker @('inspect',[string]$entry.container)) | ConvertFrom-Json)
            if ($containers.Count -ne 1) { throw 'Container identity ambiguous.' }
            $container = $containers[0]
            if ([string]$container.Name -ne ('/' + $entry.container)) { throw 'Container name mismatch.' }
            $bindings = @($container.HostConfig.PortBindings.([string]$entry.containerPort) | Where-Object { [int]$_.HostPort -eq [int]$entry.hostPort })
            if (-not $bindings.Count) { throw 'Container published port differs from approved binding.' }
            $action = if ($container.State.Running) { 'reuse' } else { 'start-existing' }
            $items.Add(@{resource=$resource.id; container=$entry.container; containerId=$container.Id; action=$action})
            if (-not $container.State.Running) { $pending += $entry }
        } catch {
            $issues.Add(@{resource=$resource.id; reason=$_.Exception.Message; nextAction="Inspect existing container $($entry.container); do not run docker create/run/compose up or substitute another instance."})
        }
    }
    # Validate the entire selection before making any change. Shared containers never enter cleanup ownership.
    if ($Ensure -and -not $issues.Count) {
        foreach ($entry in $pending) {
            try {
                $null = & $Docker @('start',[string]$entry.container)
                $container = @((& $Docker @('inspect',[string]$entry.container)) | ConvertFrom-Json)[0]
                if (-not $container.State.Running) { throw 'Existing container exited after start.' }
            } catch { $issues.Add(@{resource=$entry.kind; reason=$_.Exception.Message; nextAction='Diagnose this existing container; preserve its data and do not create a replacement.'}); break }
        }
    }
    return [pscustomobject]@{
        result=$(if ($issues.Count) {'ACTION_REQUIRED'} elseif ($pending.Count -and -not $Ensure) {'PREPARATION_REQUIRED'} else {'INPUTS_ACCEPTED'})
        policyPath=$PolicyPath; policyHash=(Get-FileHash -LiteralPath $PolicyPath).Hash
        elapsedSeconds=([datetime]::UtcNow-$started).TotalSeconds; middleware=@($items.ToArray()); issues=@($issues.ToArray())
        readiness='Pending runner protocol probes, config-center targets, WireMock contracts and SUT/consumer checks; not business PASS.'
    }
}
