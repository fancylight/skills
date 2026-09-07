[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)] [string]$OrchRoot,
    [Parameter(Mandatory = $true)] [string]$SystemTestRepo,
    [Parameter(Mandatory = $true)] [string]$ManifestPath,
    [Parameter(Mandatory = $true)] [string]$OutputPath
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot '../templates/system-test/scripts/test-runtime-contract.ps1')

function Stop-Resolver([string]$Code, [string]$Message) {
    Write-Output '[TEST_ENVIRONMENT_RESOLVER] ERROR'
    Write-Output "code: $Code"
    Write-Output "message: $Message"
    exit 1
}

function Get-CanonicalPath([string]$Path) {
    return [IO.Path]::GetFullPath($Path).TrimEnd([IO.Path]::DirectorySeparatorChar, [IO.Path]::AltDirectorySeparatorChar)
}

function Test-PathWithin([string]$Child, [string]$Parent, [bool]$AllowEqual = $true) {
    $childPath = Get-CanonicalPath $Child
    $parentPath = Get-CanonicalPath $Parent
    if ($AllowEqual -and $childPath.Equals($parentPath, [StringComparison]::OrdinalIgnoreCase)) { return $true }
    return $childPath.StartsWith($parentPath + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)
}

function Read-JsonFile([string]$Path, [string]$Code, [string]$Label) {
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { Stop-Resolver $Code "$Label not found: $Path" }
    try { return Get-Content -LiteralPath $Path -Raw -Encoding utf8 | ConvertFrom-Json }
    catch { Stop-Resolver 'INVALID_JSON' "$Label is not valid JSON: $Path" }
}

function Get-FileHashLower([string]$Path) {
    return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
}

function Get-StringHash([string]$Value) {
    $sha = [Security.Cryptography.SHA256]::Create()
    try { return -join ($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($Value)) | ForEach-Object { $_.ToString('x2') }) }
    finally { $sha.Dispose() }
}

function Get-GitHead([string]$Repository, [string]$Code, [string]$Label) {
    if (-not (Test-Path -LiteralPath (Join-Path $Repository '.git'))) { Stop-Resolver $Code "$Label is not a Git repository: $Repository" }
    $head = @(& git -C $Repository rev-parse HEAD 2>$null)
    if ($LASTEXITCODE -ne 0 -or $head.Count -eq 0 -or [string]::IsNullOrWhiteSpace([string]$head[0])) {
        Stop-Resolver $Code "$Label revision is unavailable: $Repository"
    }
    return ([string]$head[0]).Trim().ToLowerInvariant()
}

function Expand-PathToken([string]$Value, [string]$OrchestratorRoot, [string]$TestRoot) {
    if ([string]::IsNullOrWhiteSpace($Value)) { return '' }
    $expanded = $Value.Replace('${ORCH_ROOT}', $OrchestratorRoot).Replace('${TEST_ROOT}', $TestRoot)
    if ($expanded -match '\$\{[^}]+\}') { Stop-Resolver 'UNRESOLVED_PATH_TOKEN' "path contains an unresolved token: $Value" }
    return Get-CanonicalPath $expanded
}

function Test-IsSecretReference([string]$Value) {
    return $Value -match '^\$\{[A-Z][A-Z0-9_]*\}$'
}

function Assert-NoJsonSecrets($Value, [string]$Location) {
    if ($null -eq $Value) { return }
    if ($Value -is [string]) {
        if ($Value -match '(?i)\b[a-z][a-z0-9+.-]*://[^\s/:@]+:[^\s/@]+@') {
            Stop-Resolver 'ERROR_SECRET_INPUT' "credential-bearing URI found in $Location"
        }
        if ($Value -match '(?i)(?:--?)?(?:password|passwd|token|cookie|secret|credential|jdbc.?url|connection.?string)\s*[=:]\s*(?!\$\{[A-Z][A-Z0-9_]*\}$)\S+') {
            Stop-Resolver 'ERROR_SECRET_INPUT' "literal sensitive argument found in $Location"
        }
        return
    }
    if ($Value -is [ValueType]) { return }
    if ($Value -is [System.Collections.IDictionary]) {
        foreach ($key in @($Value.Keys)) { Assert-NoJsonSecrets $Value[$key] "$Location.$key" }
        return
    }
    if ($Value -is [System.Collections.IEnumerable] -and -not ($Value -is [pscustomobject])) {
        foreach ($item in $Value) { Assert-NoJsonSecrets $item $Location }
        return
    }
    if (-not ($Value -is [pscustomobject])) { return }
    foreach ($property in @($Value.PSObject.Properties)) {
        $propertyLocation = "$Location.$($property.Name)"
        if ($property.Name -match '(?i)(password|passwd|token|cookie|secret|credential|jdbc.?url|connection.?string)$') {
            $text = [string]$property.Value
            if (-not [string]::IsNullOrWhiteSpace($text) -and -not (Test-IsSecretReference $text)) {
                Stop-Resolver 'ERROR_SECRET_INPUT' "sensitive value must be a secret reference at $propertyLocation"
            }
        }
        Assert-NoJsonSecrets $property.Value $propertyLocation
    }
}

function Get-RedactedContentHash([string]$Path) {
    try { return Get-TestConfigurationContentHash $Path ([string]$manifest.configuration.ownership) $configurationRepo }
    catch { Stop-Resolver 'ERROR_SECRET_INPUT' 'configuration target requires references unless it is a Git-ignored human local input' }
}

function Get-ProbeMap($Descriptor) {
    $map = @{}
    foreach ($probe in @($Descriptor.probes)) {
        if ($probe -is [string] -or [string]::IsNullOrWhiteSpace([string]$probe.id)) {
            Stop-Resolver 'INVALID_PROBE' 'each probe must be a structured object with an id'
        }
        if ($map.ContainsKey([string]$probe.id)) { Stop-Resolver 'INVALID_PROBE' "duplicate probe id: $($probe.id)" }
        if ([string]$probe.stage -notin @('preflight', 'runtime')) { Stop-Resolver 'INVALID_PROBE' "invalid probe stage: $($probe.id)" }
        if ([string]$probe.kind -notin @('http', 'tcp', 'sql', 'log')) { Stop-Resolver 'INVALID_PROBE' "unsupported probe kind: $($probe.id)" }
        if ([string]::IsNullOrWhiteSpace([string]$probe.failureCategory)) { Stop-Resolver 'INVALID_PROBE' "probe failureCategory is required: $($probe.id)" }
        if ($probe.PSObject.Properties.Name -contains 'command') { Stop-Resolver 'INVALID_PROBE' "free-text probe command is forbidden: $($probe.id)" }
        $map[[string]$probe.id] = $probe
    }
    return $map
}

function Get-EvidenceContractMap($Descriptor) {
    $map = @{}
    foreach ($contract in @($Descriptor.evidenceContracts)) {
        $id = [string]$contract.id
        if ([string]::IsNullOrWhiteSpace($id) -or $map.ContainsKey($id)) {
            Stop-Resolver 'INVALID_EVIDENCE_CONTRACT' "evidence contract id is missing or duplicated: $id"
        }
        if ([string]$contract.kind -ne 'log-regex' -or [string]::IsNullOrWhiteSpace([string]$contract.pattern)) {
            Stop-Resolver 'INVALID_EVIDENCE_CONTRACT' "P3 supports only log-regex evidence contracts with a pattern: $id"
        }
        try { [void][regex]::new([string]$contract.pattern) }
        catch { Stop-Resolver 'INVALID_EVIDENCE_CONTRACT' "evidence contract regex is invalid: $id" }
        $map[$id] = $contract
    }
    return $map
}

function Get-ResourceOrder($Resources, $ProbeMap, [string]$OrchestratorRoot, [string]$TestRoot) {
    $map = @{}
    $dependencies = @{}
    foreach ($resource in @($Resources)) {
        $id = [string]$resource.id
        if ([string]::IsNullOrWhiteSpace($id) -or $map.ContainsKey($id)) { Stop-Resolver 'INVALID_RESOURCE' "resource id is missing or duplicated: $id" }
        if ([string]$resource.lifecycle -notin @('managed', 'external')) { Stop-Resolver 'INVALID_RESOURCE' "resource lifecycle must be managed or external: $id" }
        if ($resource.PSObject.Properties.Name -contains 'command') { Stop-Resolver 'INVALID_RESOURCE' "free-text resource command is forbidden: $id" }
        if ([string]$resource.lifecycle -eq 'managed') {
            if ([string]::IsNullOrWhiteSpace([string]$resource.executable) -or $resource.arguments -is [string] -or $null -eq $resource.arguments) {
                Stop-Resolver 'INVALID_RESOURCE' "managed resource requires executable and token-array arguments: $id"
            }
            if ([string]::IsNullOrWhiteSpace([string]$resource.workingDirectory) -or [int]$resource.port -le 0) {
                Stop-Resolver 'INVALID_RESOURCE' "managed resource requires workingDirectory and port: $id"
            }
            foreach ($argument in @($resource.arguments)) {
                if ([string]$argument -match '(?i)^--?(?:password|passwd|token|cookie|secret|credential|jdbc.?url|connection.?string)(?:$|[=:])') {
                    Stop-Resolver 'ERROR_SECRET_INPUT' "managed resource must not pass sensitive values in arguments: $id"
                }
            }
            $workingDirectory = Expand-PathToken ([string]$resource.workingDirectory) $OrchestratorRoot $TestRoot
            if (-not (Test-PathWithin $workingDirectory $OrchestratorRoot) -or -not (Test-Path -LiteralPath $workingDirectory -PathType Container)) {
                Stop-Resolver 'PATH_CONFLICT' "managed resource workingDirectory is unavailable or outside the orchestrator root: $id"
            }
            $probeId = [string]$resource.readinessProbe
            if ([string]::IsNullOrWhiteSpace($probeId) -or -not $ProbeMap.ContainsKey($probeId) -or [string]$ProbeMap[$probeId].stage -ne 'runtime') {
                Stop-Resolver 'INVALID_RESOURCE' "managed resource requires a runtime readiness probe: $id"
            }
        } else {
            if ($resource.PSObject.Properties.Name -contains 'cleanup') { Stop-Resolver 'INVALID_RESOURCE' "external resource must not declare cleanup: $id" }
            $preflightProbeId = [string]$resource.preflightProbe
            if ([string]::IsNullOrWhiteSpace($preflightProbeId) -or -not $ProbeMap.ContainsKey($preflightProbeId) -or [string]$ProbeMap[$preflightProbeId].stage -ne 'preflight') {
                Stop-Resolver 'INVALID_RESOURCE' "external resource requires a preflight probe: $id"
            }
        }
        if (-not [string]::IsNullOrWhiteSpace([string]$resource.identityProbe) -and -not $ProbeMap.ContainsKey([string]$resource.identityProbe)) { Stop-Resolver 'INVALID_RESOURCE' "unknown identity probe: $id" }
        $map[$id] = $resource
        $dependencies[$id] = @($resource.dependsOn | ForEach-Object { [string]$_ })
    }
    foreach ($id in @($map.Keys)) {
        foreach ($dependency in @($dependencies[$id])) {
            if (-not $map.ContainsKey($dependency)) { Stop-Resolver 'INVALID_RESOURCE' "resource $id depends on unknown resource $dependency" }
        }
    }
    $remaining = @{}
    foreach ($id in @($map.Keys)) { $remaining[$id] = @($dependencies[$id]) }
    $order = [System.Collections.Generic.List[string]]::new()
    while ($remaining.Count -gt 0) {
        $ready = @($remaining.Keys | Where-Object { @($remaining[$_]).Count -eq 0 } | Sort-Object)
        if ($ready.Count -eq 0) { Stop-Resolver 'RESOURCE_DEPENDENCY_CYCLE' "resource dependency cycle: $(@($remaining.Keys | Sort-Object) -join ', ')" }
        foreach ($id in $ready) {
            $order.Add($id)
            [void]$remaining.Remove($id)
            foreach ($other in @($remaining.Keys)) { $remaining[$other] = @($remaining[$other] | Where-Object { $_ -ne $id }) }
        }
    }
    return @($order)
}

$orch = Get-CanonicalPath $OrchRoot
$testRepo = Get-CanonicalPath $SystemTestRepo
$manifestFile = Get-CanonicalPath $ManifestPath
$resolvedOutput = Get-CanonicalPath $OutputPath

if (-not (Test-Path -LiteralPath $orch -PathType Container)) { Stop-Resolver 'MISSING_ORCHESTRATOR_ROOT' "orchestrator root not found: $orch" }
if (-not (Test-Path -LiteralPath $testRepo -PathType Container)) { Stop-Resolver 'MISSING_TEST_PLATFORM' "system-test repository not found: $testRepo" }
if (-not (Test-PathWithin $testRepo $orch)) { Stop-Resolver 'PATH_CONFLICT' 'system-test repository must be inside the orchestrator root' }
if (-not (Test-PathWithin $manifestFile $testRepo)) { Stop-Resolver 'PATH_CONFLICT' 'change manifest must be inside the system-test repository' }

$systemTestInputRevision = Get-GitHead $testRepo 'INVALID_TEST_PLATFORM' 'system-test repository'
$manifest = Read-JsonFile $manifestFile 'MISSING_CHANGE_MANIFEST' 'change manifest'
Assert-NoJsonSecrets $manifest 'manifest'

if ([int]$manifest.schemaVersion -ne 2) { Stop-Resolver 'UNSUPPORTED_MANIFEST_SCHEMA' 'change manifest schemaVersion must be 2' }
foreach ($legacyField in @('configurationSource', 'requiredEndpoints', 'connectivityProbe', 'ownership')) {
    if ($manifest.PSObject.Properties.Name -contains $legacyField) { Stop-Resolver 'AMBIGUOUS_CONFIGURATION_SCHEMA' "legacy field is not accepted in v2: $legacyField" }
}
if ($null -eq $manifest.environment -or [string]::IsNullOrWhiteSpace([string]$manifest.environment.id) -or [string]::IsNullOrWhiteSpace([string]$manifest.environment.descriptor)) {
    Stop-Resolver 'MISSING_ENVIRONMENT_DESCRIPTOR' 'manifest environment id and descriptor are required'
}
if ([IO.Path]::IsPathRooted([string]$manifest.environment.descriptor)) { Stop-Resolver 'PATH_CONFLICT' 'environment descriptor must use a system-test-relative path' }

$descriptorFile = Expand-PathToken (Join-Path $testRepo ([string]$manifest.environment.descriptor)) $orch $testRepo
if (-not (Test-PathWithin $descriptorFile $testRepo)) { Stop-Resolver 'PATH_CONFLICT' 'environment descriptor must be inside the system-test repository' }
$descriptor = Read-JsonFile $descriptorFile 'MISSING_ENVIRONMENT_DESCRIPTOR' 'environment descriptor'
Assert-NoJsonSecrets $descriptor 'environmentDescriptor'
if ([int]$descriptor.schemaVersion -ne 1 -or [string]$descriptor.id -ne [string]$manifest.environment.id) {
    Stop-Resolver 'INVALID_ENVIRONMENT_DESCRIPTOR' 'environment descriptor schemaVersion/id does not match the manifest'
}

$probeMap = Get-ProbeMap $descriptor
$evidenceContractMap = Get-EvidenceContractMap $descriptor
$resourceOrder = Get-ResourceOrder $descriptor.resources $probeMap $orch $testRepo
$resourceMap = @{}
foreach ($resource in @($descriptor.resources)) { $resourceMap[[string]$resource.id] = $resource }

$provider = $descriptor.configurationProvider
if ($null -eq $provider -or [string]$provider.kind -notin @('spring-config-native','spring-config-git')) { Stop-Resolver 'UNSUPPORTED_PROVIDER' 'supported providers are spring-config-native and spring-config-git' }
if ([string]::IsNullOrWhiteSpace([string]$provider.repository) -or [string]::IsNullOrWhiteSpace([string]$provider.configRoot)) { Stop-Resolver 'INVALID_PROVIDER_REPOSITORY' 'configuration provider repository and configRoot are required' }
if ([string]::IsNullOrWhiteSpace([string]$provider.serviceRef) -or -not $resourceMap.ContainsKey([string]$provider.serviceRef)) {
    Stop-Resolver 'INVALID_PROVIDER_REPOSITORY' 'configuration provider serviceRef must identify a declared resource'
}
$providerResource = $resourceMap[[string]$provider.serviceRef]
if ([string]$providerResource.kind -ne 'configuration-provider') { Stop-Resolver 'INVALID_PROVIDER_REPOSITORY' 'provider serviceRef must identify a configuration-provider resource' }
$providerRepo = Expand-PathToken ([string]$provider.repository) $orch $testRepo
if (-not (Test-PathWithin $providerRepo $orch)) { Stop-Resolver 'PATH_CONFLICT' 'configuration provider repository must be inside the orchestrator root' }
if (-not (Test-Path -LiteralPath $providerRepo -PathType Container)) { Stop-Resolver 'MISSING_PROVIDER_REPOSITORY' "configuration provider repository not found: $providerRepo" }
$providerRevision = Get-GitHead $providerRepo 'INVALID_PROVIDER_REPOSITORY' 'configuration provider repository'
$buildFiles = @('pom.xml', 'build.gradle', 'build.gradle.kts') | ForEach-Object { Join-Path $providerRepo $_ } | Where-Object { Test-Path -LiteralPath $_ -PathType Leaf }
if (@($buildFiles).Count -eq 0) { Stop-Resolver 'INVALID_PROVIDER_REPOSITORY' 'configuration provider service repository requires pom.xml or a Gradle build file' }
# Native mode may be supplied by the managed startup contract (profile + search locations).
# It does not require an application-native file in the committed service source.
$configurationRepo = if ([string]::IsNullOrWhiteSpace([string]$provider.configurationRepository)) { $providerRepo } else { Expand-PathToken ([string]$provider.configurationRepository) $orch $testRepo }
if (-not (Test-PathWithin $configurationRepo $orch) -or -not (Test-Path -LiteralPath $configurationRepo -PathType Container)) {
    Stop-Resolver 'MISSING_CONFIGURATION_REPOSITORY' 'configuration content repository is missing or outside the orchestrator root'
}
$configurationRevision = Get-GitHead $configurationRepo 'INVALID_CONFIGURATION_REPOSITORY' 'configuration content repository'
$configRoot = Get-CanonicalPath (Join-Path $configurationRepo ([string]$provider.configRoot))
if (-not (Test-PathWithin $configRoot $configurationRepo) -or -not (Test-Path -LiteralPath $configRoot -PathType Container)) {
    Stop-Resolver 'INVALID_CONFIGURATION_REPOSITORY' 'configuration provider configRoot is missing or outside its content repository'
}

if ($null -eq $manifest.configuration -or [string]::IsNullOrWhiteSpace([string]$manifest.configuration.environmentFile) -or [string]$manifest.configuration.ownership -notin @('human', 'harness')) {
    Stop-Resolver 'INVALID_CONFIGURATION' 'configuration.environmentFile and ownership=human|harness are required'
}
$environmentFileValue = [string]$manifest.configuration.environmentFile
if ([IO.Path]::IsPathRooted($environmentFileValue) -or $environmentFileValue -match '\$\{[^}]+\}') { Stop-Resolver 'PATH_CONFLICT' 'configuration.environmentFile must be a system-test-relative path without tokens' }
$environmentFilePath = Get-CanonicalPath (Join-Path $testRepo $environmentFileValue)
if (-not (Test-PathWithin $environmentFilePath $testRepo)) { Stop-Resolver 'PATH_CONFLICT' 'configuration.environmentFile must remain inside system-test' }
$resolvedTargets = [System.Collections.Generic.List[object]]::new()
foreach ($target in @($manifest.configuration.targets)) {
    $application = [string]$target.application
    $profile = [string]$target.profile
    $relative = ([string]$target.relativeFile).Replace('\', '/')
    $configRootRelative = ([string]$provider.configRoot).Replace('\', '/').Trim('/')
    if ([string]$provider.kind -eq 'spring-config-native') {
        $expectedYml = "$configRootRelative/$application/application-$profile.yml"
        $expectedYaml = "$configRootRelative/$application/application-$profile.yaml"
    } else {
        $expectedYml = "$configRootRelative/$application-$profile.yml"
        $expectedYaml = "$configRootRelative/$application-$profile.yaml"
    }
    if ([string]::IsNullOrWhiteSpace($application) -or [string]::IsNullOrWhiteSpace($profile) -or $relative -notin @($expectedYml, $expectedYaml) -or [string]$target.endpoint -ne "/$application/$profile") {
        Stop-Resolver 'CONFIG_TARGET_MISMATCH' "configuration target application/profile/path/endpoint mismatch: $application/$profile"
    }
    if ($null -eq $target.sutEvidence -or [string]$target.sutEvidence.kind -ne 'log-pattern' -or
        [string]::IsNullOrWhiteSpace([string]$target.sutEvidence.patternId) -or -not $evidenceContractMap.ContainsKey([string]$target.sutEvidence.patternId)) {
        Stop-Resolver 'INVALID_EVIDENCE_CONTRACT' "configuration target must reference a declared log evidence contract: $application/$profile"
    }
    $targetFile = Get-CanonicalPath (Join-Path $configurationRepo $relative)
    if (-not (Test-PathWithin $targetFile $configRoot)) { Stop-Resolver 'PATH_CONFLICT' "configuration target is outside configRoot: $relative" }
    if (-not (Test-Path -LiteralPath $targetFile -PathType Leaf)) { Stop-Resolver 'MISSING_CONFIG_TARGET' "configuration target not found: $relative" }
    $resolvedTargets.Add([ordered]@{
        application=$application; profile=$profile; relativeFile=$relative; absoluteFile=$targetFile
        endpoint=[string]$target.endpoint; contentHash=(Get-RedactedContentHash $targetFile); sutEvidence=$target.sutEvidence
    })
}
if ($resolvedTargets.Count -eq 0) { Stop-Resolver 'MISSING_CONFIG_TARGET' 'at least one configuration target is required' }

$resolvedSuts = [System.Collections.Generic.List[object]]::new()
foreach ($sut in @($manifest.suts)) {
    $sutId = [string]$sut.id
    $sutRepo = Expand-PathToken ([string]$sut.repository) $orch $testRepo
    if (-not (Test-PathWithin $sutRepo $orch) -or -not (Test-Path -LiteralPath $sutRepo -PathType Container)) { Stop-Resolver 'PATH_CONFLICT' "SUT repository is unavailable or outside the orchestrator root: $sutId" }
    $actualRevision = Get-GitHead $sutRepo 'INVALID_SUT_REPOSITORY' "SUT $sutId"
    if ([string]::IsNullOrWhiteSpace([string]$sut.revision) -or $actualRevision -ne ([string]$sut.revision).ToLowerInvariant()) { Stop-Resolver 'ERROR_REVISION_DRIFT' "SUT revision differs from the manifest: $sutId" }
    if ([string]$sut.lifecycle -ne 'managed') { Stop-Resolver 'INVALID_SUT_START_CONTRACT' "P1 requires managed SUT lifecycle: $sutId" }
    if ([IO.Path]::IsPathRooted([string]$sut.startContract)) { Stop-Resolver 'PATH_CONFLICT' "SUT start contract must be system-test-relative: $sutId" }
    $startContract = Get-CanonicalPath (Join-Path $testRepo ([string]$sut.startContract))
    if (-not (Test-PathWithin $startContract $testRepo) -or -not (Test-Path -LiteralPath $startContract -PathType Leaf)) { Stop-Resolver 'INVALID_SUT_START_CONTRACT' "SUT start contract is missing or outside system-test: $sutId" }
    if ([string]::IsNullOrWhiteSpace([string]$sut.healthProbe) -or -not $probeMap.ContainsKey([string]$sut.healthProbe) -or [string]$probeMap[[string]$sut.healthProbe].stage -ne 'runtime') {
        Stop-Resolver 'INVALID_SUT_START_CONTRACT' "SUT requires a runtime health probe: $sutId"
    }
    if (@($resolvedTargets | Where-Object { $_.application -eq $sutId }).Count -eq 0) { Stop-Resolver 'INVALID_SUT_CONFIGURATION' "SUT requires its own configuration target: $sutId" }
    $resolvedSuts.Add([ordered]@{
        id=$sutId; repository=$sutRepo; revision=$actualRevision; lifecycle=[string]$sut.lifecycle
        startContract=$startContract; healthProbe=[string]$sut.healthProbe
    })
}
if ($resolvedSuts.Count -eq 0) { Stop-Resolver 'INVALID_SUT_REPOSITORY' 'at least one SUT is required' }
if ($null -eq $manifest.harness -or [string]::IsNullOrWhiteSpace([string]$manifest.harness.revision)) { Stop-Resolver 'MISSING_HARNESS_REVISION' 'manifest harness.revision is required' }

if ($null -eq $manifest.runner -or $manifest.runner.command -is [string] -or @($manifest.runner.command).Count -eq 0 -or
    [string]::IsNullOrWhiteSpace([string]$manifest.runner.workingDirectory)) {
    Stop-Resolver 'INVALID_TEST_RUNNER' 'runner requires a workingDirectory and token-array command'
}
$runnerWorkingDirectory = Expand-PathToken ([string]$manifest.runner.workingDirectory) $orch $testRepo
if (-not (Test-PathWithin $runnerWorkingDirectory $testRepo) -or -not (Test-Path -LiteralPath $runnerWorkingDirectory -PathType Container)) {
    Stop-Resolver 'PATH_CONFLICT' 'runner workingDirectory must exist inside system-test'
}
$runnerCommand = @($manifest.runner.command | ForEach-Object { [string]$_ })
foreach ($token in $runnerCommand) {
    if ([string]::IsNullOrWhiteSpace($token)) { Stop-Resolver 'INVALID_TEST_RUNNER' 'runner command contains an empty token' }
}
$runnerFileIndex = [Array]::IndexOf([object[]]$runnerCommand, '-File')
if ($runnerFileIndex -ge 0) {
    if ($runnerFileIndex + 1 -ge $runnerCommand.Count) { Stop-Resolver 'INVALID_TEST_RUNNER' 'runner -File requires a script path token' }
    $runnerScript = Get-CanonicalPath (Join-Path $runnerWorkingDirectory $runnerCommand[$runnerFileIndex + 1])
    if (-not (Test-PathWithin $runnerScript $runnerWorkingDirectory) -or -not (Test-Path -LiteralPath $runnerScript -PathType Leaf)) {
        Stop-Resolver 'INVALID_TEST_RUNNER' 'runner script is missing or outside its working directory'
    }
}
$runnerFailureCategory = if ([string]::IsNullOrWhiteSpace([string]$manifest.runner.failureCategory)) { 'SUT_BUSINESS' } else { [string]$manifest.runner.failureCategory }
foreach ($hook in @('prepare','cleanup')) {
    if ($null -eq $manifest.runner.$hook) { continue }
    if ($manifest.runner.$hook -is [string] -or @($manifest.runner.$hook).Count -eq 0 -or @($manifest.runner.$hook | Where-Object { [string]::IsNullOrWhiteSpace([string]$_) }).Count -gt 0) {
        Stop-Resolver 'INVALID_TEST_RUNNER' "runner $hook must be a nonempty token-array command"
    }
}

$resolvedResources = [System.Collections.Generic.List[object]]::new()
foreach ($resourceId in $resourceOrder) {
    $resource = $resourceMap[$resourceId]
    $workingDirectory = if ([string]$resource.lifecycle -eq 'managed') { Expand-PathToken ([string]$resource.workingDirectory) $orch $testRepo } else { $null }
    $resolvedResources.Add([ordered]@{
        id=$resourceId; kind=[string]$resource.kind; lifecycle=[string]$resource.lifecycle; dependsOn=@($resource.dependsOn)
        executable=$resource.executable; arguments=@($resource.arguments); workingDirectory=$workingDirectory; port=$resource.port
        readinessProbe=$resource.readinessProbe; preflightProbe=$resource.preflightProbe; identityProbe=$resource.identityProbe
    })
}

$manifestHash = Get-FileHashLower $manifestFile
$descriptorHash = Get-FileHashLower $descriptorFile
$cleanupPlan = @($resolvedResources | Where-Object { $_.lifecycle -eq 'managed' } | ForEach-Object { $_.id })
$executionContract = [ordered]@{
    configurationInput=[ordered]@{ ownership=[string]$manifest.configuration.ownership; environmentFile=$environmentFileValue.Replace('\', '/') }
    provider=[ordered]@{ kind=[string]$provider.kind; repository=$providerRepo; configurationRepository=$configurationRepo; baseUri=[string]$provider.baseUri; configRoot=$configRoot; serviceRef=[string]$provider.serviceRef }
    resources=@($resolvedResources); executionOrder=@($resourceOrder); cleanupPlan=$cleanupPlan; probes=@($descriptor.probes)
    evidenceContracts=@($descriptor.evidenceContracts)
    suts=@($resolvedSuts | ForEach-Object { [ordered]@{ id=$_.id; repository=$_.repository; lifecycle=$_.lifecycle; startContract=$_.startContract; healthProbe=$_.healthProbe } })
    runner=[ordered]@{ workingDirectory=$runnerWorkingDirectory; command=$runnerCommand; failureCategory=$runnerFailureCategory; prepare=@($manifest.runner.prepare); cleanup=@($manifest.runner.cleanup) }
}
$executionContractHash = Get-StringHash ($executionContract | ConvertTo-Json -Depth 16 -Compress)
$fingerprintInput = [ordered]@{
    manifest=[ordered]@{ path=$manifestFile; sha256=$manifestHash }
    environment=[ordered]@{ path=$descriptorFile; sha256=$descriptorHash; id=[string]$descriptor.id }
    revisions=[ordered]@{ provider=$providerRevision; configuration=$configurationRevision; harness=[string]$manifest.harness.revision; suts=@($resolvedSuts | ForEach-Object { [ordered]@{ id=$_.id; revision=$_.revision } }) }
    targets=@($resolvedTargets | ForEach-Object { [ordered]@{ application=$_.application; profile=$_.profile; relativeFile=$_.relativeFile; contentHash=$_.contentHash } })
    executionContractHash=$executionContractHash
}
$fingerprint = Get-StringHash ($fingerprintInput | ConvertTo-Json -Depth 12 -Compress)
$resolved = [ordered]@{
    schemaVersion=1
    sourceManifestSchemaVersion=2
    environment=[ordered]@{ id=[string]$descriptor.id; descriptor=$descriptorFile; playbook=$descriptor.playbook }
    configuration=[ordered]@{
        environmentFile=$environmentFileValue.Replace('\', '/'); ownership=[string]$manifest.configuration.ownership
        provider=[ordered]@{ kind=[string]$provider.kind; repository=$providerRepo; revision=$providerRevision; configurationRepository=$configurationRepo; configurationRevision=$configurationRevision; baseUri=[string]$provider.baseUri; configRoot=$configRoot; serviceRef=[string]$provider.serviceRef }
        targets=@($resolvedTargets)
    }
    resources=@($resolvedResources)
    executionOrder=@($resourceOrder)
    cleanupPlan=$cleanupPlan
    probes=@($descriptor.probes)
    evidenceContracts=@($descriptor.evidenceContracts)
    suts=@($resolvedSuts)
    runner=[ordered]@{ workingDirectory=$runnerWorkingDirectory; command=$runnerCommand; failureCategory=$runnerFailureCategory; prepare=@($manifest.runner.prepare); cleanup=@($manifest.runner.cleanup) }
    revisions=[ordered]@{ designInputRevision=$systemTestInputRevision; harness=[string]$manifest.harness.revision }
    inputs=[ordered]@{ manifest=[ordered]@{ path=$manifestFile; sha256=$manifestHash }; descriptor=[ordered]@{ path=$descriptorFile; sha256=$descriptorHash } }
    executionContractHash=$executionContractHash
    configurationFingerprint=$fingerprint
}

Assert-NoJsonSecrets $resolved 'resolvedManifest'
$outputParent = Split-Path -Parent $resolvedOutput
if ([string]::IsNullOrWhiteSpace($outputParent) -or -not (Test-PathWithin $resolvedOutput $testRepo)) { Stop-Resolver 'PATH_CONFLICT' 'resolved manifest output must be inside the system-test repository' }
if (-not (Test-Path -LiteralPath $outputParent -PathType Container)) { [void](New-Item -ItemType Directory -Path $outputParent -Force) }
[IO.File]::WriteAllText($resolvedOutput, ($resolved | ConvertTo-Json -Depth 16), [Text.UTF8Encoding]::new($false))

Write-Output '[TEST_ENVIRONMENT_RESOLVER] PASS'
Write-Output "environment: $($descriptor.id)"
Write-Output "configuration_fingerprint: $fingerprint"
Write-Output "output: $resolvedOutput"
