[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)] [string]$ResolvedManifestPath,
    [Parameter(Mandatory = $true)] [string]$StatePath,
    [Parameter(Mandatory = $true)] [string]$OutputPath,
    [Parameter(Mandatory = $true)] [string]$VerifierId,
    [string]$ControllerPath = '',
    [ValidateRange(100, 30000)] [int]$ProbeTimeoutMs = 1500
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot '../templates/system-test/scripts/test-runtime-contract.ps1')
if ([string]::IsNullOrWhiteSpace($ControllerPath)) { $ControllerPath = Join-Path $PSScriptRoot 'flow-test-controller.ps1' }
$steps = [System.Collections.Generic.List[object]]::new()
$blockers = [System.Collections.Generic.List[string]]::new()
$script:state = $null
$script:resolved = $null

function Get-CanonicalPath([string]$Path) {
    return [IO.Path]::GetFullPath($Path).TrimEnd([IO.Path]::DirectorySeparatorChar, [IO.Path]::AltDirectorySeparatorChar)
}

function Test-PathWithin([string]$Child, [string]$Parent, [bool]$AllowEqual = $true) {
    $childPath = Get-CanonicalPath $Child
    $parentPath = Get-CanonicalPath $Parent
    if ($AllowEqual -and $childPath.Equals($parentPath, [StringComparison]::OrdinalIgnoreCase)) { return $true }
    return $childPath.StartsWith($parentPath + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)
}

function Add-Step([string]$Id, [string]$Phase, [string]$Result, [string]$Category, [string]$Detail, [string]$Resource = '') {
    $steps.Add([ordered]@{ stepId=$Id; phase=$Phase; resourceId=$Resource; result=$Result; category=$Category; detail=$Detail })
    if ($Result -ne 'PASS') { $blockers.Add("${Id}: $Detail") }
}

function Read-Json([string]$Path, [string]$Label) {
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { throw "$Label not found: $Path" }
    try { return Get-Content -LiteralPath $Path -Raw -Encoding utf8 | ConvertFrom-Json }
    catch { throw "$Label is not valid JSON: $Path" }
}

function Get-FileHashLower([string]$Path) {
    return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
}

function Get-StringHash([string]$Value) {
    $sha = [Security.Cryptography.SHA256]::Create()
    try { return -join ($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($Value)) | ForEach-Object { $_.ToString('x2') }) }
    finally { $sha.Dispose() }
}

function Get-RedactedContentHash([string]$Path) {
    return Get-TestConfigurationContentHash $Path ([string]$resolved.configuration.ownership) ([string]$resolved.configuration.provider.configurationRepository)
}

function Get-GitHead([string]$Repository) {
    if (-not (Test-Path -LiteralPath (Join-Path $Repository '.git'))) { return '' }
    $head = @(& git -C $Repository rev-parse HEAD 2>$null)
    if ($LASTEXITCODE -ne 0 -or $head.Count -eq 0) { return '' }
    return ([string]$head[0]).Trim().ToLowerInvariant()
}

function Read-EnvironmentFile([string]$Path) {
    $values = @{}
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return $values }
    foreach ($line in Get-Content -LiteralPath $Path -Encoding utf8) {
        if ($line -match '^\s*#' -or $line -notmatch '^\s*([A-Za-z_][A-Za-z0-9_]*)\s*=') { continue }
        $name = $matches[1]
        $value = $line.Substring($line.IndexOf('=') + 1).Trim().Trim('"', "'")
        $values[$name] = $value
    }
    return $values
}

function Get-ReferenceValue([string]$Name, $EnvironmentValues) {
    $processValue = [Environment]::GetEnvironmentVariable($Name)
    if (-not [string]::IsNullOrWhiteSpace($processValue)) { return $processValue }
    if ($EnvironmentValues.ContainsKey($Name)) { return [string]$EnvironmentValues[$Name] }
    return ''
}

function Test-Tcp([string]$HostName, [int]$Port, [int]$TimeoutMs) {
    $client = New-Object System.Net.Sockets.TcpClient
    try {
        $async = $client.BeginConnect($HostName, $Port, $null, $null)
        if (-not $async.AsyncWaitHandle.WaitOne($TimeoutMs, $false)) { return $false }
        $client.EndConnect($async)
        return $true
    } catch { return $false } finally { $client.Dispose() }
}

function Test-PortAvailable([int]$Port) {
    $listener = $null
    try {
        $listener = [Net.Sockets.TcpListener]::new([Net.IPAddress]::Loopback, $Port)
        $listener.Start()
        return $true
    } catch { return $false } finally { if ($null -ne $listener) { try { $listener.Stop() } catch {} } }
}

function Test-Http([string]$Url, [int]$ExpectStatus, [int]$TimeoutMs) {
    try {
        $response = Invoke-WebRequest -UseBasicParsing -Uri $Url -TimeoutSec ([Math]::Max(1, [Math]::Ceiling($TimeoutMs / 1000.0)))
        return [int]$response.StatusCode -eq $ExpectStatus
    } catch { return $false }
}

function Resolve-Executable([string]$Executable, [string]$WorkingDirectory) {
    if ([IO.Path]::IsPathRooted($Executable)) { return $(if (Test-Path -LiteralPath $Executable -PathType Leaf) { Get-CanonicalPath $Executable } else { '' }) }
    $local = Join-Path $WorkingDirectory $Executable
    if (Test-Path -LiteralPath $local -PathType Leaf) { return Get-CanonicalPath $local }
    $command = Get-Command $Executable -ErrorAction SilentlyContinue | Select-Object -First 1
    return $(if ($null -ne $command) { [string]$command.Source } else { '' })
}

function Write-ReportAndExit([bool]$Pass, [string]$Summary) {
    $result = if ($Pass) { 'PASS' } else { 'BLOCKED' }
    $report = [ordered]@{
        schemaVersion=1; result=$result; mode='environment'; verifierId=$VerifierId
        testRevision=$(if ($null -ne $script:state) { [string]$script:state.revisions.test } else { '' })
        sutRevision=$(if ($null -ne $script:state) { [string]$script:state.revisions.sut } else { '' })
        harnessRevision=$(if ($null -ne $script:state) { [string]$script:state.revisions.harness } else { '' })
        configurationFingerprint=$(if ($null -ne $script:state) { [string]$script:state.configurationFingerprint } else { '' })
        summary=$Summary; steps=@($steps); blockers=@($blockers)
    }
    $parent = Split-Path -Parent (Get-CanonicalPath $OutputPath)
    if (-not (Test-Path -LiteralPath $parent -PathType Container)) { [void](New-Item -ItemType Directory -Path $parent -Force) }
    [IO.File]::WriteAllText((Get-CanonicalPath $OutputPath), ($report | ConvertTo-Json -Depth 16), [Text.UTF8Encoding]::new($false))
    if ($Pass) {
        Write-Output '[TEST_ENVIRONMENT_VERIFIER] PASS'
        Write-Output "report: $(Get-CanonicalPath $OutputPath)"
        exit 0
    }
    Write-Output '[TEST_ENVIRONMENT_VERIFIER] BLOCKED'
    foreach ($blocker in $blockers) { Write-Output "- $blocker" }
    Write-Output "report: $(Get-CanonicalPath $OutputPath)"
    exit 1
}

try {
    if ([string]::IsNullOrWhiteSpace($VerifierId) -or $VerifierId -match '(?i)(password|token|secret|cookie|connectionstring)') { throw 'verifier identity is missing or sensitive' }
    $resolvedPath = Get-CanonicalPath $ResolvedManifestPath
    $controller = Get-CanonicalPath $ControllerPath
    if (-not (Test-Path -LiteralPath $controller -PathType Leaf)) { throw "controller not found: $controller" }
    $script:resolved = Read-Json $resolvedPath 'resolved manifest'
    if ([int]$resolved.schemaVersion -ne 1 -or [int]$resolved.sourceManifestSchemaVersion -ne 2) { throw 'unsupported resolved manifest schema' }

    $statusOutput = @(& $controller status -StatePath (Get-CanonicalPath $StatePath) 2>&1)
    if ($LASTEXITCODE -ne 0 -or @($statusOutput | Where-Object { [string]$_ -match '^\[FLOW_CONTROLLER\] ERROR' }).Count -gt 0) { throw "controller state is unavailable: $($statusOutput -join ' | ')" }
    $script:state = ($statusOutput -join "`n") | ConvertFrom-Json
    if ([string]$state.phase -ne 'TEST_IMPLEMENTATION_VERIFIED') { throw "controller phase must be TEST_IMPLEMENTATION_VERIFIED, actual: $($state.phase)" }
    if ([string]$state.configurationFingerprint -ne [string]$resolved.configurationFingerprint) {
        Add-Step 'controller-binding' 'preflight' 'BLOCKED' 'CONFIG_INFRA' 'resolved configuration fingerprint differs from controller state'
    } else { Add-Step 'controller-binding' 'preflight' 'PASS' 'NONE' 'controller fingerprint and phase are valid' }

    $executionContract = [ordered]@{
        configurationInput=[ordered]@{ ownership=[string]$resolved.configuration.ownership; environmentFile=[string]$resolved.configuration.environmentFile }
        provider=[ordered]@{
            kind=[string]$resolved.configuration.provider.kind; repository=[string]$resolved.configuration.provider.repository; configurationRepository=[string]$resolved.configuration.provider.configurationRepository
            baseUri=[string]$resolved.configuration.provider.baseUri; configRoot=[string]$resolved.configuration.provider.configRoot
            serviceRef=[string]$resolved.configuration.provider.serviceRef
        }
        resources=@($resolved.resources); executionOrder=@($resolved.executionOrder); cleanupPlan=@($resolved.cleanupPlan); probes=@($resolved.probes)
        evidenceContracts=@($resolved.evidenceContracts)
        suts=@($resolved.suts | ForEach-Object { [ordered]@{ id=$_.id; repository=$_.repository; lifecycle=$_.lifecycle; startContract=$_.startContract; healthProbe=$_.healthProbe } })
        runner=[ordered]@{ workingDirectory=[string]$resolved.runner.workingDirectory; command=@($resolved.runner.command); failureCategory=[string]$resolved.runner.failureCategory; prepare=@($resolved.runner.prepare); cleanup=@($resolved.runner.cleanup) }
    }
    $actualExecutionContractHash = Get-StringHash ($executionContract | ConvertTo-Json -Depth 16 -Compress)
    $fingerprintInput = [ordered]@{
        manifest=[ordered]@{ path=[string]$resolved.inputs.manifest.path; sha256=[string]$resolved.inputs.manifest.sha256 }
        environment=[ordered]@{ path=[string]$resolved.inputs.descriptor.path; sha256=[string]$resolved.inputs.descriptor.sha256; id=[string]$resolved.environment.id }
        revisions=[ordered]@{
            provider=[string]$resolved.configuration.provider.revision; configuration=[string]$resolved.configuration.provider.configurationRevision; harness=[string]$resolved.revisions.harness
            suts=@($resolved.suts | ForEach-Object { [ordered]@{ id=$_.id; revision=$_.revision } })
        }
        targets=@($resolved.configuration.targets | ForEach-Object { [ordered]@{ application=$_.application; profile=$_.profile; relativeFile=$_.relativeFile; contentHash=$_.contentHash } })
        executionContractHash=$actualExecutionContractHash
    }
    $actualFingerprint = Get-StringHash ($fingerprintInput | ConvertTo-Json -Depth 12 -Compress)
    if ($actualExecutionContractHash -ne [string]$resolved.executionContractHash -or $actualFingerprint -ne [string]$resolved.configurationFingerprint) {
        Add-Step 'resolved-contract-integrity' 'preflight' 'BLOCKED' 'CONFIG_INFRA' 'resolved execution contract or fingerprint is not internally consistent'
    } else { Add-Step 'resolved-contract-integrity' 'preflight' 'PASS' 'NONE' 'resolved execution contract and fingerprint are internally consistent' }

    $systemTestRepo = Get-CanonicalPath ([string]$state.repositories.systemTest)
    $currentTestRevision = Get-GitHead $systemTestRepo
    if ($currentTestRevision -ne [string]$state.revisions.test) { Add-Step 'system-test-revision' 'preflight' 'BLOCKED' 'TEST_HARNESS' 'system-test repository revision differs from controller state' }
    else { Add-Step 'system-test-revision' 'preflight' 'PASS' 'NONE' 'system-test revision is locked' }
    if (-not (Test-PathWithin $resolvedPath $systemTestRepo)) { Add-Step 'resolved-manifest-scope' 'preflight' 'BLOCKED' 'TEST_HARNESS' 'resolved manifest is outside the canonical system-test repository' }
    else { Add-Step 'resolved-manifest-scope' 'preflight' 'PASS' 'NONE' 'resolved manifest is inside the canonical system-test repository' }

    foreach ($inputName in @('manifest', 'descriptor')) {
        $input = $resolved.inputs.$inputName
        $inputPath = Get-CanonicalPath ([string]$input.path)
        if (-not (Test-PathWithin $inputPath $systemTestRepo) -or -not (Test-Path -LiteralPath $inputPath -PathType Leaf) -or (Get-FileHashLower $inputPath) -ne [string]$input.sha256) {
            Add-Step "input-$inputName" 'preflight' 'BLOCKED' 'CONFIG_INFRA' "$inputName path or hash drifted"
        } else { Add-Step "input-$inputName" 'preflight' 'PASS' 'NONE' "$inputName hash is unchanged" }
    }

    $providerRepo = Get-CanonicalPath ([string]$resolved.configuration.provider.repository)
    $providerRevision = Get-GitHead $providerRepo
    if ($providerRevision -ne [string]$resolved.configuration.provider.revision) { Add-Step 'provider-revision' 'preflight' 'BLOCKED' 'CONFIG_INFRA' 'configuration provider revision drifted' 'configuration-provider' }
    else { Add-Step 'provider-revision' 'preflight' 'PASS' 'NONE' 'configuration provider revision is locked' 'configuration-provider' }
    $configurationRepo = Get-CanonicalPath ([string]$resolved.configuration.provider.configurationRepository)
    $configurationRevision = Get-GitHead $configurationRepo
    if ($configurationRevision -ne [string]$resolved.configuration.provider.configurationRevision) { Add-Step 'configuration-revision' 'preflight' 'BLOCKED' 'CONFIG_INFRA' 'configuration content revision drifted' 'configuration-provider' }
    else { Add-Step 'configuration-revision' 'preflight' 'PASS' 'NONE' 'configuration content revision is locked' 'configuration-provider' }

    if (@($resolved.suts).Count -ne 1) { Add-Step 'controller-topology' 'preflight' 'BLOCKED' 'TEST_HARNESS' 'current controller supports exactly one SUT repository' }
    else {
        $sut = @($resolved.suts)[0]
        $sutRepo = Get-CanonicalPath ([string]$sut.repository)
        $actualSutRevision = Get-GitHead $sutRepo
        $stateSutRepo = Get-CanonicalPath ([string]$state.repositories.sut)
        if ($sutRepo -ne $stateSutRepo -or $actualSutRevision -ne [string]$state.revisions.sut -or [string]$sut.revision -ne [string]$state.revisions.sut) {
            Add-Step 'sut-revision' 'preflight' 'BLOCKED' 'CONFIG_INFRA' 'SUT repository or revision differs from controller state' ([string]$sut.id)
        } else { Add-Step 'sut-revision' 'preflight' 'PASS' 'NONE' 'SUT repository and revision are locked' ([string]$sut.id) }
        if (-not (Test-Path -LiteralPath ([string]$sut.startContract) -PathType Leaf)) { Add-Step 'sut-start-contract' 'preflight' 'BLOCKED' 'CONFIG_INFRA' 'SUT start contract is missing' ([string]$sut.id) }
        else { Add-Step 'sut-start-contract' 'preflight' 'PASS' 'NONE' 'SUT start contract exists' ([string]$sut.id) }
    }

    foreach ($target in @($resolved.configuration.targets)) {
        $targetPath = Get-CanonicalPath ([string]$target.absoluteFile)
        try { $actualHash = Get-RedactedContentHash $targetPath } catch { $actualHash = ''; Add-Step "target-$($target.application)-$($target.profile)" 'preflight' 'BLOCKED' 'CONFIG_INFRA' $_.Exception.Message }
        if ($actualHash) {
            if (-not (Test-PathWithin $targetPath ([string]$resolved.configuration.provider.configRoot)) -or $actualHash -ne [string]$target.contentHash) {
                Add-Step "target-$($target.application)-$($target.profile)" 'preflight' 'BLOCKED' 'CONFIG_INFRA' 'configuration target path or content drifted'
            } else { Add-Step "target-$($target.application)-$($target.profile)" 'preflight' 'PASS' 'NONE' 'configuration target hash is unchanged' }
        }
    }

    $environmentFile = Get-CanonicalPath (Join-Path $systemTestRepo ([string]$resolved.configuration.environmentFile))
    if (-not (Test-PathWithin $environmentFile $systemTestRepo) -or -not (Test-Path -LiteralPath $environmentFile -PathType Leaf)) {
        Add-Step 'environment-file' 'preflight' 'BLOCKED' 'CONFIG_INFRA' 'environment file is missing or outside system-test'
        $environmentValues = @{}
    } else {
        $environmentValues = Read-EnvironmentFile $environmentFile
        Add-Step 'environment-file' 'preflight' 'PASS' 'NONE' 'environment file exists; values were not recorded'
    }

    $requiredRefs = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    foreach ($probe in @($resolved.probes | Where-Object { $_.stage -eq 'preflight' })) {
        foreach ($name in @('hostRef','portRef','urlRef','connectionRef','clientRef')) {
            if ($probe.PSObject.Properties.Name -contains $name -and -not [string]::IsNullOrWhiteSpace([string]$probe.$name)) { [void]$requiredRefs.Add([string]$probe.$name) }
        }
    }
    foreach ($target in @($resolved.configuration.targets)) {
        if (Test-Path -LiteralPath ([string]$target.absoluteFile) -PathType Leaf) {
            $content = Get-Content -LiteralPath ([string]$target.absoluteFile) -Raw -Encoding utf8
            foreach ($match in [regex]::Matches($content, '\$\{(?<name>[A-Z][A-Z0-9_]*)\}')) { [void]$requiredRefs.Add($match.Groups['name'].Value) }
        }
    }
    foreach ($reference in @($requiredRefs | Sort-Object)) {
        $referenceId = (Get-StringHash $reference).Substring(0, 12)
        if ([string]::IsNullOrWhiteSpace((Get-ReferenceValue $reference $environmentValues))) { Add-Step "reference-$referenceId" 'preflight' 'BLOCKED' 'CONFIG_INFRA' 'required reference is not provided' }
        else { Add-Step "reference-$referenceId" 'preflight' 'PASS' 'NONE' 'required reference is provided' }
    }

    foreach ($resource in @($resolved.resources)) {
        $resourceId = [string]$resource.id
        if ([string]$resource.lifecycle -eq 'managed') {
            $workingDirectory = Get-CanonicalPath ([string]$resource.workingDirectory)
            $executable = Resolve-Executable ([string]$resource.executable) $workingDirectory
            if ([string]::IsNullOrWhiteSpace($executable)) { Add-Step "managed-tool-$resourceId" 'preflight' 'BLOCKED' 'CONFIG_INFRA' 'managed executable is unavailable' $resourceId }
            else {
                $argumentList = @($resource.arguments)
                $fileIndex = [Array]::IndexOf([object[]]$argumentList, '-File')
                if ($fileIndex -ge 0 -and $fileIndex + 1 -lt $argumentList.Count) {
                    $scriptPath = Get-CanonicalPath (Join-Path $workingDirectory ([string]$argumentList[$fileIndex + 1]))
                    if (-not (Test-PathWithin $scriptPath $workingDirectory) -or -not (Test-Path -LiteralPath $scriptPath -PathType Leaf)) { Add-Step "managed-tool-$resourceId" 'preflight' 'BLOCKED' 'CONFIG_INFRA' 'managed start script is missing or outside working directory' $resourceId }
                    else { Add-Step "managed-tool-$resourceId" 'preflight' 'PASS' 'NONE' 'managed executable and start script exist' $resourceId }
                } else { Add-Step "managed-tool-$resourceId" 'preflight' 'PASS' 'NONE' 'managed executable exists' $resourceId }
            }
            if (-not (Test-PortAvailable ([int]$resource.port))) { Add-Step "managed-port-$resourceId" 'preflight' 'BLOCKED' 'CONFIG_INFRA' "managed port is already occupied: $($resource.port)" $resourceId }
            else { Add-Step "managed-port-$resourceId" 'preflight' 'PASS' 'NONE' "managed port is available: $($resource.port)" $resourceId }
        }
    }

    foreach ($probe in @($resolved.probes | Where-Object { $_.stage -eq 'preflight' })) {
        $probeId = [string]$probe.id
        if ([string]$probe.kind -eq 'tcp') {
            $hostValue = Get-ReferenceValue ([string]$probe.hostRef) $environmentValues
            $portValue = Get-ReferenceValue ([string]$probe.portRef) $environmentValues
            $port = 0
            $validPort = [int]::TryParse($portValue, [ref]$port) -and $port -gt 0 -and $port -le 65535
            $passed = -not [string]::IsNullOrWhiteSpace($hostValue) -and $validPort -and (Test-Tcp $hostValue $port $ProbeTimeoutMs)
        } elseif ([string]$probe.kind -eq 'http') {
            $url = if (-not [string]::IsNullOrWhiteSpace([string]$probe.urlRef)) { Get-ReferenceValue ([string]$probe.urlRef) $environmentValues } else { [string]$probe.url }
            $expectStatus = if ([int]$probe.expectStatus -gt 0) { [int]$probe.expectStatus } else { 200 }
            $passed = -not [string]::IsNullOrWhiteSpace($url) -and (Test-Http $url $expectStatus $ProbeTimeoutMs)
        } else { $passed = $false }
        if ($passed) { Add-Step "probe-$probeId" 'preflight' 'PASS' 'NONE' 'external preflight probe passed' $probeId }
        else { Add-Step "probe-$probeId" 'preflight' 'BLOCKED' ([string]$probe.failureCategory) 'external preflight probe failed or is unsupported' $probeId }
    }

    Write-ReportAndExit ($blockers.Count -eq 0) $(if ($blockers.Count -eq 0) { "environment preflight passed ($($steps.Count) steps)" } else { "environment preflight blocked ($($blockers.Count) blockers)" })
} catch {
    Add-Step 'verifier-internal' 'preflight' 'BLOCKED' 'TEST_HARNESS' $_.Exception.Message
    Write-ReportAndExit $false 'environment preflight could not complete'
}
