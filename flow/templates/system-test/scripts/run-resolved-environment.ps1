[CmdletBinding()]
param(
    [ValidateSet('run','cleanup')] [string]$Command = 'run',
    [string]$ResolvedManifestPath,
    [string]$ExpectedFingerprint,
    [Parameter(Mandatory = $true)] [string]$OutputPath,
    [string]$StatePath = '',
    [int]$ProbeTimeoutMs = 1000,
    [int]$StartupTimeoutMs = 120000,
    [int]$SuiteTimeoutMs = 600000
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'test-runtime-contract.ps1')
$steps = [System.Collections.Generic.List[object]]::new()
$ownedProcesses = [System.Collections.Generic.List[object]]::new()
$environmentRestore = @{}
$environmentValues = @{}
$result = 'BLOCKED'
$failureCategory = 'TEST_HARNESS'
$summary = 'resolved environment run did not complete'
$runtimeStatePath = ''
$sensitiveValues = @()
$logDirectory = ''
$prepareAttempted = $false
$cleanupMode = $false
$primaryFailure = $null
$stepClock=[DateTime]::UtcNow

function Get-BudgetTimeout([int]$Requested) {
    if (-not $env:FLOW_EXECUTION_DEADLINE) { return $Requested }
    $deadline = [DateTime]::Parse($env:FLOW_EXECUTION_DEADLINE).ToUniversalTime()
    if (-not $script:cleanupMode) { $deadline=$deadline.AddSeconds(-120) }
    $remaining=[int][Math]::Floor(($deadline-[DateTime]::UtcNow).TotalMilliseconds)
    if ($remaining -le 0) { Stop-Run 'BUDGET_EXHAUSTED' 'Total execution deadline reached; no new operation is permitted' }
    return [Math]::Min($Requested,$remaining)
}

function Get-CanonicalPath([string]$Path) {
    return [IO.Path]::GetFullPath($Path).TrimEnd([IO.Path]::DirectorySeparatorChar, [IO.Path]::AltDirectorySeparatorChar)
}

function Get-StringHash([string]$Value) {
    $sha = [Security.Cryptography.SHA256]::Create()
    try { return -join ($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($Value)) | ForEach-Object { $_.ToString('x2') }) }
    finally { $sha.Dispose() }
}

function Get-FileHashLower([string]$Path) {
    return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
}

function Get-GitHead([string]$Repository) {
    if (-not (Test-Path -LiteralPath (Join-Path $Repository '.git'))) { return '' }
    $head = @(& git -C $Repository rev-parse HEAD 2>$null)
    if ($LASTEXITCODE -ne 0 -or $head.Count -eq 0) { return '' }
    return ([string]$head[0]).Trim().ToLowerInvariant()
}

function Get-RedactedContentHash([string]$Path) {
    return Get-TestConfigurationContentHash $Path ([string]$resolved.configuration.ownership) ([string]$resolved.configuration.provider.configurationRepository)
}

function Add-Step([string]$Id, [string]$Phase, [string]$StepResult, [string]$Category, [string]$Detail, [string]$ResourceId = '') {
    $now=[DateTime]::UtcNow
    $steps.Add([ordered]@{ stepId=$Id; phase=$Phase; resourceId=$ResourceId; result=$StepResult; category=$Category; detail=$Detail; finishedAt=$now.ToString('o'); elapsedSeconds=[Math]::Round(($now-$script:stepClock).TotalSeconds,3) })
    $script:stepClock=$now
}

function Write-OwnedState {
    if ([string]::IsNullOrWhiteSpace($runtimeStatePath)) { return }
    $records = @($ownedProcesses | ForEach-Object {
        [ordered]@{ id=[string]$_.id; pid=[int]$_.process.Id; startedAtUtc=$_.startedAtUtc }
    })
    $state = [ordered]@{ schemaVersion=1; configurationFingerprint=$ExpectedFingerprint; processes=$records }
    $parent = Split-Path -Parent $runtimeStatePath
    if (-not (Test-Path -LiteralPath $parent -PathType Container)) { [void](New-Item -ItemType Directory -Path $parent -Force) }
    [IO.File]::WriteAllText($runtimeStatePath, ($state | ConvertTo-Json -Depth 8), [Text.UTF8Encoding]::new($false))
}

function Stop-OwnedRecord($Record) {
    $process = Get-Process -Id ([int]$Record.pid) -ErrorAction SilentlyContinue
    if ($null -eq $process) { return $true }
    try { $actualStart = $process.StartTime.ToUniversalTime() } catch { return $false }
    $expectedStart = [DateTime]::Parse([string]$Record.startedAtUtc).ToUniversalTime()
    if ($actualStart.Ticks -ne $expectedStart.Ticks) { return $false }
    try {
        & taskkill.exe /PID $process.Id /T /F 2>$null | Out-Null
        [void]$process.WaitForExit(3000)
        return $null -eq (Get-Process -Id $process.Id -ErrorAction SilentlyContinue)
    } catch { return $false }
}

function Stop-Run([string]$Category, [string]$Message) {
    $script:failureCategory = $Category
    throw $Message
}

function Read-EnvironmentFile([string]$Path) {
    $values = @{}
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return $values }
    foreach ($line in Get-Content -LiteralPath $Path -Encoding utf8) {
        if ($line -match '^\s*#' -or $line -notmatch '^\s*([A-Za-z_][A-Za-z0-9_]*)\s*=') { continue }
        $name = $matches[1]
        $values[$name] = $line.Substring($line.IndexOf('=') + 1).Trim().Trim('"', "'")
    }
    return $values
}

function Protect-Text([string]$Value) {
    return Protect-TestRuntimeText $Value @($sensitiveValues + @($environmentValues.Values))
}


function Test-PortAvailable([int]$Port) {
    $listener = $null
    try {
        $listener = [Net.Sockets.TcpListener]::new([Net.IPAddress]::Loopback, $Port)
        $listener.Start()
        return $true
    } catch { return $false } finally { if ($null -ne $listener) { try { $listener.Stop() } catch {} } }
}

function Test-Tcp([string]$HostName, [int]$Port, [int]$TimeoutMs) {
    $client = [Net.Sockets.TcpClient]::new()
    try {
        $async = $client.BeginConnect($HostName, $Port, $null, $null)
        if (-not $async.AsyncWaitHandle.WaitOne($TimeoutMs, $false)) { return $false }
        $client.EndConnect($async)
        return $true
    } catch { return $false } finally { $client.Dispose() }
}

function Invoke-Probe($Probe) {
    $null=Get-BudgetTimeout $ProbeTimeoutMs
    if ([string]$Probe.kind -eq 'http') {
        try {
            $response = Invoke-WebRequest -UseBasicParsing -Uri ([string]$Probe.url) -Method $(if ([string]::IsNullOrWhiteSpace([string]$Probe.method)) { 'GET' } else { [string]$Probe.method }) -TimeoutSec ([Math]::Max(1, [Math]::Ceiling($ProbeTimeoutMs / 1000.0)))
            $expected = if ([int]$Probe.expectStatus -gt 0) { [int]$Probe.expectStatus } else { 200 }
            return [int]$response.StatusCode -eq $expected -and ([string]::IsNullOrWhiteSpace([string]$Probe.expectBodyRegex) -or [string]$response.Content -match [string]$Probe.expectBodyRegex)
        } catch { return $false }
    }
    if ([string]$Probe.kind -eq 'tcp') {
        $hostValue = if (-not [string]::IsNullOrWhiteSpace([string]$Probe.hostRef)) { [Environment]::GetEnvironmentVariable([string]$Probe.hostRef) } else { [string]$Probe.host }
        $portText = if (-not [string]::IsNullOrWhiteSpace([string]$Probe.portRef)) { [Environment]::GetEnvironmentVariable([string]$Probe.portRef) } else { [string]$Probe.port }
        $port = 0
        return [int]::TryParse($portText, [ref]$port) -and (Test-Tcp $hostValue $port $ProbeTimeoutMs)
    }
    return $false
}

function Wait-Probe($Probe, [int]$TimeoutMs, $OwnedProcess=$null) {
    $deadline = [DateTime]::UtcNow.AddMilliseconds((Get-BudgetTimeout $TimeoutMs))
    do {
        if ($null -ne $OwnedProcess) { $OwnedProcess.Refresh(); if ($OwnedProcess.HasExited) { return $false } }
        if (Invoke-Probe $Probe) { return $true }
        Start-Sleep -Milliseconds 200
    } while ([DateTime]::UtcNow -lt $deadline)
    return $false
}

function Quote-Argument([string]$Value) {
    if ($Value -notmatch '[\s"]') { return $Value }
    return '"' + $Value.Replace('"', '\"') + '"'
}

function Start-OwnedProcess([string]$Id, [string]$Executable, $Arguments, [string]$WorkingDirectory, [string]$LogDirectory) {
    $null=Get-BudgetTimeout $StartupTimeoutMs
    $stdout = Join-Path $LogDirectory "$Id.stdout.log"
    $stderr = Join-Path $LogDirectory "$Id.stderr.log"
    $argumentLine = (@($Arguments | ForEach-Object { Quote-Argument ([string]$_) }) -join ' ')
    try {
        $process = Start-Process -FilePath $Executable -ArgumentList $argumentLine -WorkingDirectory $WorkingDirectory -RedirectStandardOutput $stdout -RedirectStandardError $stderr -PassThru -WindowStyle Hidden
    } catch { Stop-Run 'CONFIG_INFRA' "could not start $Id" }
    $record = [ordered]@{ id=$Id; process=$process; startedAtUtc=$process.StartTime.ToUniversalTime().ToString('o'); stdout=$stdout; stderr=$stderr }
    $ownedProcesses.Add($record)
    Write-OwnedState
    return $record
}

function Invoke-OwnedCommand([string]$Id, [string]$Executable, $Arguments, [string]$WorkingDirectory, [string]$LogDirectory) {
    $operationTimeout=Get-BudgetTimeout $SuiteTimeoutMs
    $stdout = Join-Path $LogDirectory "$Id.stdout.log"
    $stderr = Join-Path $LogDirectory "$Id.stderr.log"
    $info = [Diagnostics.ProcessStartInfo]::new()
    $info.FileName = $Executable
    $info.Arguments = (@($Arguments | ForEach-Object { Quote-Argument ([string]$_) }) -join ' ')
    $info.WorkingDirectory = $WorkingDirectory
    $info.UseShellExecute = $false
    $info.CreateNoWindow = $true
    $info.RedirectStandardOutput = $true
    $info.RedirectStandardError = $true
    $process = [Diagnostics.Process]::new()
    $process.StartInfo = $info
    if (-not $process.Start()) { Stop-Run 'TEST_HARNESS' "could not start $Id" }
    $record = [ordered]@{ id=$Id; process=$process; startedAtUtc=$process.StartTime.ToUniversalTime().ToString('o'); stdout=$stdout; stderr=$stderr }
    $ownedProcesses.Add($record)
    Write-OwnedState
    $stdoutTask = $process.StandardOutput.ReadToEndAsync()
    $stderrTask = $process.StandardError.ReadToEndAsync()
    $finished = $process.WaitForExit($operationTimeout)
    if (-not $finished) {
        if (-not (Stop-OwnedRecord ([ordered]@{ pid=$process.Id; startedAtUtc=$record.startedAtUtc }))) { Stop-Run 'CONFIG_INFRA' "timed-out owned command could not be stopped: $Id" }
    }
    if (-not $stdoutTask.Wait(3000) -or -not $stderrTask.Wait(3000)) { Stop-Run 'TEST_HARNESS' "command left output streams open; startup contracts must wait for children: $Id" }
    [IO.File]::WriteAllText($stdout, $stdoutTask.Result, [Text.UTF8Encoding]::new($false))
    [IO.File]::WriteAllText($stderr, $stderrTask.Result, [Text.UTF8Encoding]::new($false))
    if (-not $finished) { Stop-Run 'TEST_HARNESS' "command exceeded its runtime limit: $Id" }
    return [int]$process.ExitCode
}

function Get-ProbeById($Resolved, [string]$Id) {
    return @($Resolved.probes | Where-Object { [string]$_.id -eq $Id } | Select-Object -First 1)[0]
}

function Assert-ContractIntegrity($Resolved) {
    $contract = [ordered]@{
        configurationInput=[ordered]@{ ownership=[string]$Resolved.configuration.ownership; environmentFile=[string]$Resolved.configuration.environmentFile }
        provider=[ordered]@{
            kind=[string]$Resolved.configuration.provider.kind; repository=[string]$Resolved.configuration.provider.repository; configurationRepository=[string]$Resolved.configuration.provider.configurationRepository
            baseUri=[string]$Resolved.configuration.provider.baseUri; configRoot=[string]$Resolved.configuration.provider.configRoot
            serviceRef=[string]$Resolved.configuration.provider.serviceRef
        }
        resources=@($Resolved.resources); executionOrder=@($Resolved.executionOrder); cleanupPlan=@($Resolved.cleanupPlan); probes=@($Resolved.probes)
        evidenceContracts=@($Resolved.evidenceContracts)
        suts=@($Resolved.suts | ForEach-Object { [ordered]@{ id=$_.id; repository=$_.repository; lifecycle=$_.lifecycle; startContract=$_.startContract; healthProbe=$_.healthProbe } })
        runner=[ordered]@{ workingDirectory=[string]$Resolved.runner.workingDirectory; command=@($Resolved.runner.command); failureCategory=[string]$Resolved.runner.failureCategory; prepare=@($Resolved.runner.prepare); cleanup=@($Resolved.runner.cleanup) }
    }
    $contractHash = Get-StringHash ($contract | ConvertTo-Json -Depth 16 -Compress)
    $fingerprintInput = [ordered]@{
        manifest=[ordered]@{ path=[string]$Resolved.inputs.manifest.path; sha256=[string]$Resolved.inputs.manifest.sha256 }
        environment=[ordered]@{ path=[string]$Resolved.inputs.descriptor.path; sha256=[string]$Resolved.inputs.descriptor.sha256; id=[string]$Resolved.environment.id }
        revisions=[ordered]@{
            provider=[string]$Resolved.configuration.provider.revision; configuration=[string]$Resolved.configuration.provider.configurationRevision; harness=[string]$Resolved.revisions.harness
            suts=@($Resolved.suts | ForEach-Object { [ordered]@{ id=$_.id; revision=$_.revision } })
        }
        targets=@($Resolved.configuration.targets | ForEach-Object { [ordered]@{ application=$_.application; profile=$_.profile; relativeFile=$_.relativeFile; contentHash=$_.contentHash } })
        executionContractHash=$contractHash
    }
    $fingerprint = Get-StringHash ($fingerprintInput | ConvertTo-Json -Depth 12 -Compress)
    return $contractHash -eq [string]$Resolved.executionContractHash -and $fingerprint -eq [string]$Resolved.configurationFingerprint -and $fingerprint -eq $ExpectedFingerprint
}

$outputFullPath = Get-CanonicalPath $OutputPath
$outputDirectory = Split-Path -Parent $outputFullPath
if (-not (Test-Path -LiteralPath $outputDirectory -PathType Container)) { [void](New-Item -ItemType Directory -Path $outputDirectory -Force) }
$runtimeStatePath = if ([string]::IsNullOrWhiteSpace($StatePath)) { Join-Path (Split-Path -Parent $outputFullPath) '.resolved-environment-state.json' } else { Get-CanonicalPath $StatePath }
if ($Command -eq 'cleanup') {
    $cleanupSteps = [System.Collections.Generic.List[object]]::new()
    $cleanupPass = $true
    if (Test-Path -LiteralPath $runtimeStatePath -PathType Leaf) {
        try { $staleState = Get-Content -LiteralPath $runtimeStatePath -Raw -Encoding utf8 | ConvertFrom-Json }
        catch { $staleState = $null; $cleanupPass = $false }
        if ($null -ne $staleState -and [int]$staleState.schemaVersion -eq 1) {
            $staleProcesses = @($staleState.processes)
            for ($staleIndex = $staleProcesses.Count - 1; $staleIndex -ge 0; $staleIndex--) {
                $record = $staleProcesses[$staleIndex]
                $stopped = Stop-OwnedRecord $record
                $cleanupSteps.Add([ordered]@{ stepId=("cleanup-" + [string]$record.id); result=$(if ($stopped) { 'PASS' } else { 'BLOCKED' }); category=$(if ($stopped) { 'NONE' } else { 'CONFIG_INFRA' }) })
                if (-not $stopped) { $cleanupPass = $false }
            }
        }
        if ($cleanupPass) { Remove-Item -LiteralPath $runtimeStatePath -Force }
    }
    $cleanupReport = [ordered]@{ schemaVersion=1; result=$(if ($cleanupPass) { 'PASS' } else { 'BLOCKED' }); mode='resolved-environment-cleanup'; steps=@($cleanupSteps) }
    [IO.File]::WriteAllText($outputFullPath, ($cleanupReport | ConvertTo-Json -Depth 8), [Text.UTF8Encoding]::new($false))
    if ($cleanupPass) { Write-Output '[RESOLVED_ENVIRONMENT_CLEANUP] PASS'; exit 0 }
    Write-Output '[RESOLVED_ENVIRONMENT_CLEANUP] BLOCKED'; exit 1
}

if ([string]::IsNullOrWhiteSpace($ResolvedManifestPath) -or [string]::IsNullOrWhiteSpace($ExpectedFingerprint)) {
    throw 'run requires ResolvedManifestPath and ExpectedFingerprint'
}

try {
    $resolvedPath = Get-CanonicalPath $ResolvedManifestPath
    $resolved = Get-Content -LiteralPath $resolvedPath -Raw -Encoding utf8 | ConvertFrom-Json
    if ([int]$resolved.schemaVersion -ne 1 -or [int]$resolved.sourceManifestSchemaVersion -ne 2 -or -not (Assert-ContractIntegrity $resolved)) {
        Stop-Run 'TEST_HARNESS' 'resolved manifest integrity or expected fingerprint check failed'
    }
    Add-Step 'resolved-contract' 'preflight' 'PASS' 'NONE' 'resolved contract and expected fingerprint are locked'

    foreach ($inputName in @('manifest','descriptor')) {
        $input = $resolved.inputs.$inputName
        if (-not (Test-Path -LiteralPath ([string]$input.path) -PathType Leaf) -or (Get-FileHashLower ([string]$input.path)) -ne [string]$input.sha256) {
            Stop-Run 'CONFIG_INFRA' "$inputName input drifted after environment verification"
        }
    }
    if ((Get-GitHead ([string]$resolved.configuration.provider.repository)) -ne [string]$resolved.configuration.provider.revision) {
        Stop-Run 'CONFIG_INFRA' 'configuration provider revision drifted after environment verification'
    }
    if ((Get-GitHead ([string]$resolved.configuration.provider.configurationRepository)) -ne [string]$resolved.configuration.provider.configurationRevision) {
        Stop-Run 'CONFIG_INFRA' 'configuration content revision drifted after environment verification'
    }
    foreach ($sut in @($resolved.suts)) {
        if ((Get-GitHead ([string]$sut.repository)) -ne [string]$sut.revision) { Stop-Run 'CONFIG_INFRA' "SUT revision drifted after environment verification: $($sut.id)" }
    }
    foreach ($target in @($resolved.configuration.targets)) {
        try { $actualTargetHash = if (Test-Path -LiteralPath ([string]$target.absoluteFile) -PathType Leaf) { Get-RedactedContentHash ([string]$target.absoluteFile) } else { '' } }
        catch { Stop-Run 'CONFIG_INFRA' "configuration target became unsafe after environment verification: $($target.application)/$($target.profile)" }
        if ([string]::IsNullOrWhiteSpace($actualTargetHash) -or $actualTargetHash -ne [string]$target.contentHash) {
            Stop-Run 'CONFIG_INFRA' "configuration target drifted after environment verification: $($target.application)/$($target.profile)"
        }
    }
    Add-Step 'source-lock' 'preflight' 'PASS' 'NONE' 'input hashes and provider/SUT revisions remain locked'

    $testRoot = Get-CanonicalPath ([string]$resolved.runner.workingDirectory)
    $environmentFile = Get-CanonicalPath (Join-Path $testRoot ([string]$resolved.configuration.environmentFile))
    $environmentValues = Read-EnvironmentFile $environmentFile
    foreach ($name in @($environmentValues.Keys)) {
        $environmentRestore[$name] = [Environment]::GetEnvironmentVariable($name)
        [Environment]::SetEnvironmentVariable($name, [string]$environmentValues[$name])
    }
    Add-Step 'runtime-environment' 'preflight' 'PASS' 'NONE' 'runtime references loaded without recording values'

    $outputParent = Split-Path -Parent (Get-CanonicalPath $OutputPath)
    if (-not (Test-Path -LiteralPath $outputParent -PathType Container)) { [void](New-Item -ItemType Directory -Path $outputParent -Force) }
    $sensitiveValues = @(Get-TestSensitiveValues $resolved.configuration.targets)
    $logDirectory = Join-Path ([IO.Path]::GetTempPath()) ('.flow-runtime-' + [guid]::NewGuid().ToString('N'))
    [void](New-Item -ItemType Directory -Path $logDirectory -Force)

    foreach ($resourceId in @($resolved.executionOrder)) {
        $null=Get-BudgetTimeout $StartupTimeoutMs
        $resource = @($resolved.resources | Where-Object { [string]$_.id -eq [string]$resourceId } | Select-Object -First 1)[0]
        if ([string]$resource.lifecycle -eq 'external') {
            $probe = Get-ProbeById $resolved ([string]$resource.preflightProbe)
            if ($null -eq $probe -or -not (Invoke-Probe $probe)) { Stop-Run ([string]$probe.failureCategory) "external resource preflight failed: $resourceId" }
            Add-Step "resource-$resourceId" 'resource-start' 'PASS' 'NONE' 'external resource is reachable and remains externally owned' ([string]$resourceId)
            continue
        }
        $probe = Get-ProbeById $resolved ([string]$resource.readinessProbe)
        if (-not (Test-PortAvailable ([int]$resource.port))) {
            $identityProbe = if ([string]::IsNullOrWhiteSpace([string]$resource.identityProbe)) { $null } else { Get-ProbeById $resolved ([string]$resource.identityProbe) }
            if ($null -eq $identityProbe -or -not (Invoke-Probe $identityProbe)) { Stop-Run 'CONFIG_INFRA' "occupied resource identity could not be confirmed: $resourceId" }
            if ($null -eq $probe -or -not (Invoke-Probe $probe)) { Stop-Run 'CONFIG_INFRA' "managed resource port is occupied by an unhealthy endpoint: $resourceId" }
            Add-Step "resource-$resourceId" 'resource-start' 'PASS' 'NONE' 'healthy existing instance reused; ownership not acquired' ([string]$resourceId)
            continue
        }
        [void](Start-OwnedProcess ([string]$resource.id) ([string]$resource.executable) @($resource.arguments) ([string]$resource.workingDirectory) $logDirectory)
        if ($null -eq $probe -or -not (Wait-Probe $probe $StartupTimeoutMs)) { Stop-Run 'CONFIG_INFRA' "managed resource readiness failed: $resourceId" }
        Add-Step "resource-$resourceId" 'resource-start' 'PASS' 'NONE' 'managed resource created and ready' ([string]$resourceId)
    }

    foreach ($target in @($resolved.configuration.targets)) {
        $uri = ([string]$resolved.configuration.provider.baseUri).TrimEnd('/') + [string]$target.endpoint
        try {
            $response = Invoke-RestMethod -Uri $uri -Method Get -TimeoutSec ([Math]::Max(1, [Math]::Ceiling($ProbeTimeoutMs / 1000.0)))
            $profileMatch = @($response.profiles | Where-Object { [string]$_ -eq [string]$target.profile }).Count -gt 0
            if ([string]$response.name -ne [string]$target.application -or -not $profileMatch) { throw 'identity mismatch' }
        } catch { Stop-Run 'CONFIG_INFRA' "configuration provider target endpoint failed identity validation: $($target.application)/$($target.profile)" }
        Add-Step "target-$($target.application)-$($target.profile)" 'configuration' 'PASS' 'NONE' 'provider returned the expected application/profile identity'
    }

    if (@($resolved.runner.prepare | Where-Object { $_ }).Count -gt 0) {
        $prepareAttempted = $true
        $prepare = @($resolved.runner.prepare)
        $prepareExit = Invoke-OwnedCommand 'fixture-prepare' ([string]$prepare[0]) @($prepare | Select-Object -Skip 1) $testRoot $logDirectory
        if ($prepareExit -ne 0) { Stop-Run $(if ($prepareExit -eq 78) { 'CONFIG_INFRA' } else { 'TEST_HARNESS' }) "fixture contract preparation failed (exit code $prepareExit)" }
        Add-Step 'fixture-prepare' 'prepare' 'PASS' 'NONE' 'fixture contracts registered and verified before SUT startup'
    }
    foreach ($sut in @($resolved.suts)) {
        $health = Get-ProbeById $resolved ([string]$sut.healthProbe)
        $sutPort = if ([string]$health.kind -eq 'http') { ([uri]$health.url).Port } else { [int]$health.port }
        if ($sutPort -gt 0 -and -not (Test-PortAvailable $sutPort)) { Stop-Run 'CONFIG_INFRA' "SUT port is occupied; ownership cannot be acquired: $($sut.id)" }
        $sutDeadline = [DateTime]::UtcNow.AddMilliseconds((Get-BudgetTimeout $StartupTimeoutMs))
        $sutRecord = Start-OwnedProcess ("sut-" + [string]$sut.id) 'powershell.exe' @('-NoProfile','-ExecutionPolicy','Bypass','-File',[string]$sut.startContract) ([string]$sut.repository) $logDirectory
        $probe = Get-ProbeById $resolved ([string]$sut.healthProbe)
        if ($null -eq $probe -or -not (Wait-Probe $probe $StartupTimeoutMs $sutRecord.process)) { Stop-Run 'CONFIG_INFRA' "SUT health probe failed or owned startup process exited: $($sut.id); inspect its stdout/stderr evidence" }
        Add-Step "sut-$($sut.id)-health" 'sut-start' 'PASS' 'NONE' 'SUT created and healthy' ([string]$sut.id)

        foreach ($target in @($resolved.configuration.targets | Where-Object { $_.application -eq $sut.id })) {
            $contractId = [string]$target.sutEvidence.patternId
            $contract = @($resolved.evidenceContracts | Where-Object { [string]$_.id -eq $contractId } | Select-Object -First 1)[0]
            $deadline = $sutDeadline
            $matched = $false
            do {
                $content = ''
                if (Test-Path -LiteralPath $sutRecord.stdout -PathType Leaf) { $content += Get-Content -LiteralPath $sutRecord.stdout -Raw -Encoding utf8 }
                if (Test-Path -LiteralPath $sutRecord.stderr -PathType Leaf) { $content += Get-Content -LiteralPath $sutRecord.stderr -Raw -Encoding utf8 }
                if ($null -ne $contract -and $content -match [string]$contract.pattern) { $matched = $true; break }
                Start-Sleep -Milliseconds 200
            } while ([DateTime]::UtcNow -lt $deadline)
            if (-not $matched) { Stop-Run 'CONFIG_INFRA' "SUT configuration-consumption evidence was not observed: $contractId" }
            Add-Step "evidence-$contractId" 'configuration-consumption' 'PASS' 'NONE' 'declared configuration-consumption evidence was observed' ([string]$sut.id)
        }
    }

    $runnerCommand = @($resolved.runner.command | ForEach-Object {
        $token = [string]$_
        foreach ($name in @('FLOW_TEST_FILTER','FLOW_TEST_REPORT_DIR','FLOW_TEST_EVIDENCE_DIR','FLOW_RUN_ID','FLOW_SCENARIO_IDS','FLOW_RESOLVED_MANIFEST')) {
            $placeholder = '${' + $name + '}'
            if ($token.Contains($placeholder)) {
                $value = [Environment]::GetEnvironmentVariable($name)
                if ([string]::IsNullOrWhiteSpace($value)) { Stop-Run 'TEST_HARNESS' "required runner input is empty: $name" }
                $token = $token.Replace($placeholder, $value)
            }
        }
        if ($token -match '\$\{') { Stop-Run 'TEST_HARNESS' 'runner command contains unresolved input' }
        $token
    })
    $suiteExitCode = Invoke-OwnedCommand 'test-suite' ([string]$runnerCommand[0]) @($runnerCommand | Select-Object -Skip 1) ([string]$resolved.runner.workingDirectory) $logDirectory
    if ($suiteExitCode -ne 0) { Stop-Run ([string]$resolved.runner.failureCategory) "test suite exited with code $suiteExitCode" }
    Add-Step 'test-suite' 'suite' 'PASS' 'NONE' "test suite completed successfully (exit code $suiteExitCode)"
    $result = 'PASS'
    $failureCategory = 'NONE'
    $summary = 'resolved environment lifecycle and test suite passed'
} catch {
    $message = Protect-Text $_.Exception.Message
    Add-Step 'runtime-failure' 'runtime' 'BLOCKED' $failureCategory $message
    $summary = $message
    $primaryFailure=[ordered]@{category=$failureCategory;summary=$message}
} finally {
    $cleanupMode=$true
    if ($prepareAttempted -and @($resolved.runner.cleanup | Where-Object { $_ }).Count -gt 0) {
        try {
            $cleanup = @($resolved.runner.cleanup)
            $cleanupExit = Invoke-OwnedCommand 'fixture-cleanup' ([string]$cleanup[0]) @($cleanup | Select-Object -Skip 1) $testRoot $logDirectory
            if ($cleanupExit -ne 0) { throw 'fixture cleanup failed' }
            Add-Step 'fixture-cleanup' 'cleanup' 'PASS' 'NONE' 'run-scoped fixture cleanup completed'
        } catch {
            Add-Step 'fixture-cleanup' 'cleanup' 'BLOCKED' 'TEST_HARNESS' 'run-scoped fixture cleanup failed'
            $result = 'BLOCKED'
            if (-not $primaryFailure) { $failureCategory = 'TEST_HARNESS'; $summary='run-scoped fixture cleanup failed' }
        }
    }
    for ($processIndex = $ownedProcesses.Count - 1; $processIndex -ge 0; $processIndex--) {
        $record = $ownedProcesses[$processIndex]
        try {
            $stateRecord = [ordered]@{ pid=[int]$record.process.Id; startedAtUtc=$record.startedAtUtc }
            if (-not (Stop-OwnedRecord $stateRecord)) { throw 'process identity changed or stop failed' }
            Add-Step ("cleanup-" + [string]$record.id) 'cleanup' 'PASS' 'NONE' 'process created by this run was stopped' ([string]$record.id)
        } catch {
            Add-Step ("cleanup-" + [string]$record.id) 'cleanup' 'BLOCKED' 'CONFIG_INFRA' 'owned process cleanup failed' ([string]$record.id)
            $result = 'BLOCKED'
            if (-not $primaryFailure) { $failureCategory = 'CONFIG_INFRA'; $summary = 'owned process cleanup failed' }
        }
    }
    if ($result -eq 'PASS' -or @($steps | Where-Object { $_.phase -eq 'cleanup' -and $_.result -ne 'PASS' }).Count -eq 0) {
        if (Test-Path -LiteralPath $runtimeStatePath -PathType Leaf) { Remove-Item -LiteralPath $runtimeStatePath -Force }
    }
    foreach ($name in @($environmentRestore.Keys)) { [Environment]::SetEnvironmentVariable($name, $environmentRestore[$name]) }
    if ($logDirectory -and (Test-Path -LiteralPath $logDirectory -PathType Container)) {
        $safeLogs = Join-Path $outputDirectory 'logs'
        [void](New-Item -ItemType Directory -Path $safeLogs -Force)
        foreach ($rawLog in Get-ChildItem -LiteralPath $logDirectory -File) {
            [IO.File]::WriteAllText((Join-Path $safeLogs $rawLog.Name), (Protect-Text (Get-Content -LiteralPath $rawLog.FullName -Raw)), [Text.UTF8Encoding]::new($false))
            Remove-Item -LiteralPath $rawLog.FullName -Force
        }
        Remove-Item -LiteralPath $logDirectory -Force
    }
    $report = [ordered]@{
        schemaVersion=1; result=$result; mode='resolved-environment-runtime'; configurationFingerprint=$ExpectedFingerprint
        fullSuite=[string]::IsNullOrWhiteSpace([Environment]::GetEnvironmentVariable('FLOW_SCENARIO_IDS'))
        scenarioIds=@(([string][Environment]::GetEnvironmentVariable('FLOW_SCENARIO_IDS')).Split(',') | Where-Object { $_ })
        failureCategory=$failureCategory; summary=(Protect-Text $summary); primaryFailure=$primaryFailure; steps=@($steps)
    }
    $parent = Split-Path -Parent (Get-CanonicalPath $OutputPath)
    if (-not (Test-Path -LiteralPath $parent -PathType Container)) { [void](New-Item -ItemType Directory -Path $parent -Force) }
    [IO.File]::WriteAllText((Get-CanonicalPath $OutputPath), ($report | ConvertTo-Json -Depth 16), [Text.UTF8Encoding]::new($false))
}

if ($result -eq 'PASS') {
    Write-Output '[RESOLVED_ENVIRONMENT_RUNTIME] PASS'
    Write-Output "report: $(Get-CanonicalPath $OutputPath)"
    exit 0
}
Write-Output '[RESOLVED_ENVIRONMENT_RUNTIME] BLOCKED'
Write-Output "category: $failureCategory"
Write-Output "report: $(Get-CanonicalPath $OutputPath)"
exit 1
