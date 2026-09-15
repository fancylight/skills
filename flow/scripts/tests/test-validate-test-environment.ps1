$ErrorActionPreference = 'Stop'
$scriptRoot = Split-Path -Parent $PSScriptRoot
$resolver = Join-Path $scriptRoot 'resolve-test-environment.ps1'
$verifier = Join-Path $scriptRoot 'validate-test-environment.ps1'
$controller = Join-Path $scriptRoot 'flow-test-controller.ps1'
$root = Join-Path ([IO.Path]::GetTempPath()) ('flow-environment-preflight-' + [guid]::NewGuid().ToString('N'))

function Write-Json([string]$Path, $Value) {
    $parent = Split-Path -Parent $Path
    if (-not (Test-Path -LiteralPath $parent)) { [void](New-Item -ItemType Directory -Path $parent -Force) }
    [IO.File]::WriteAllText($Path, ($Value | ConvertTo-Json -Depth 16), [Text.UTF8Encoding]::new($false))
}

function Initialize-Git([string]$Path) {
    [void](New-Item -ItemType Directory -Path $Path -Force)
    & git -C $Path init --quiet
    & git -C $Path config user.email environment-preflight@example.invalid
    & git -C $Path config user.name environment-preflight-tests
    & git -C $Path config core.autocrlf false
}

function Commit-All([string]$Path, [string]$Message) {
    & git -C $Path add .
    & git -C $Path commit --quiet -m $Message
    if ($LASTEXITCODE -ne 0) { throw "git commit failed: $Path" }
    return (& git -C $Path rev-parse HEAD).Trim().ToLowerInvariant()
}

function Get-FreePort {
    $listener = [Net.Sockets.TcpListener]::new([Net.IPAddress]::Loopback, 0)
    try { $listener.Start(); return ([Net.IPEndPoint]$listener.LocalEndpoint).Port }
    finally { $listener.Stop() }
}

function Start-Listener([int]$Port) {
    $listener = [Net.Sockets.TcpListener]::new([Net.IPAddress]::Loopback, $Port)
    $listener.Start()
    return $listener
}

function Get-StateHash($State) {
    $State.integrityHash = ''
    $bytes = [Text.Encoding]::UTF8.GetBytes(($State | ConvertTo-Json -Depth 16 -Compress))
    $sha = [Security.Cryptography.SHA256]::Create()
    try { return -join ($sha.ComputeHash($bytes) | ForEach-Object { $_.ToString('x2') }) }
    finally { $sha.Dispose() }
}

function Write-State([string]$Path, $State) {
    $State.integrityHash = Get-StateHash $State
    Write-Json $Path $State
}

function New-Fixture([string]$Name, [bool]$ProvideDatabase = $true, [bool]$ProvideCredential = $true, [bool]$LiteralProbe = $false, [bool]$MultiSut = $false) {
    $orch = Join-Path $root $Name
    $testRepo = Join-Path $orch 'system-test'
    $providerRepo = Join-Path $orch 'config-provider'
    $sutRepo = Join-Path $orch 'sample-sut'
    Initialize-Git $providerRepo; Initialize-Git $sutRepo; Initialize-Git $testRepo

    [void](New-Item -ItemType Directory -Path (Join-Path $providerRepo 'src\main\resources') -Force)
    [void](New-Item -ItemType Directory -Path (Join-Path $providerRepo 'config\sample-sut') -Force)
    [void](New-Item -ItemType Directory -Path (Join-Path $providerRepo 'scripts') -Force)
    Set-Content -LiteralPath (Join-Path $providerRepo 'pom.xml') -Encoding utf8 -NoNewline -Value '<project />'
    Set-Content -LiteralPath (Join-Path $providerRepo 'src\main\resources\application-native.yml') -Encoding utf8 -NoNewline -Value 'spring: {}'
    Set-Content -LiteralPath (Join-Path $providerRepo 'scripts\start-native.ps1') -Encoding utf8 -NoNewline -Value "Write-Output 'fixture'"
    Set-Content -LiteralPath (Join-Path $providerRepo 'config\sample-sut\application-dev.yml') -Encoding utf8 -NoNewline -Value "spring:`n  datasource:`n    username: test_user`n    password: `${DATABASE_CREDENTIAL}"
    if ($MultiSut) {
        foreach ($application in @('sample-module', 'second-sut')) {
            [void](New-Item -ItemType Directory -Path (Join-Path $providerRepo "config/$application") -Force)
            Copy-Item -LiteralPath (Join-Path $providerRepo 'config/sample-sut/application-dev.yml') -Destination (Join-Path $providerRepo "config/$application/application-dev.yml")
        }
    }
    $providerRevision = Commit-All $providerRepo 'provider baseline'

    Set-Content -LiteralPath (Join-Path $sutRepo 'README.md') -Encoding utf8 -NoNewline -Value 'sample sut'
    $sutRevision = Commit-All $sutRepo 'sut baseline'

    $managedPort = Get-FreePort
    $externalPort = Get-FreePort
    [void](New-Item -ItemType Directory -Path (Join-Path $testRepo 'config\environments') -Force)
    [void](New-Item -ItemType Directory -Path (Join-Path $testRepo 'config\services\sample-sut') -Force)
    [void](New-Item -ItemType Directory -Path (Join-Path $testRepo 'changes\sample') -Force)
    [void](New-Item -ItemType Directory -Path (Join-Path $testRepo 'scripts') -Force)
    Set-Content -LiteralPath (Join-Path $testRepo 'config\services\sample-sut\start-system-test.ps1') -Encoding utf8 -NoNewline -Value "Write-Output 'fixture'"
    Set-Content -LiteralPath (Join-Path $testRepo 'scripts\run-suite.ps1') -Encoding utf8 -NoNewline -Value "exit 0"
    $descriptor = [ordered]@{
        schemaVersion=1; id='local'; playbook='docs/local-integration-playbook.md'
        configurationProvider=[ordered]@{ kind='spring-config-native'; repository='${ORCH_ROOT}/config-provider'; baseUri="http://127.0.0.1:$managedPort"; configRoot='config'; serviceRef='config-provider' }
        resources=@(
            [ordered]@{ id='config-provider'; kind='configuration-provider'; lifecycle='managed'; executable='powershell.exe'; arguments=@('-NoProfile','-File','scripts/start-native.ps1'); workingDirectory='${ORCH_ROOT}/config-provider'; port=$managedPort; readinessProbe='config-provider-health'; dependsOn=@() },
            [ordered]@{ id='database'; kind='database'; lifecycle='external'; preflightProbe='database-connectivity'; dependsOn=@() }
        )
        probes=@(
            [ordered]@{ id='config-provider-health'; stage='runtime'; kind='http'; method='GET'; url="http://127.0.0.1:$managedPort/actuator/health"; expectStatus=200; failureCategory='CONFIG_INFRA' },
            [ordered]@{ id='database-connectivity'; stage='preflight'; kind='tcp'; hostRef='DATABASE_HOST'; portRef='DATABASE_PORT'; failureCategory='DATA_SCHEMA_CONTRACT' },
            [ordered]@{ id='sample-sut-health'; stage='runtime'; kind='http'; method='GET'; url='http://127.0.0.1:17845/actuator/health'; expectStatus=200; failureCategory='CONFIG_INFRA' }
        )
        evidenceContracts=@([ordered]@{ id='property-source'; kind='log-regex'; pattern='CONFIG_CONSUMED\\s+sample-sut/dev' })
    }
    if ($LiteralProbe) {
        $descriptor.probes[1].Remove('hostRef'); $descriptor.probes[1].Remove('portRef')
        $descriptor.probes[1].host = '127.0.0.1'; $descriptor.probes[1].port = $externalPort
    }
    $descriptorPath = Join-Path $testRepo 'config\environments\local.json'
    Write-Json $descriptorPath $descriptor
    $manifest = [ordered]@{
        schemaVersion=2; stage='design'; environment=[ordered]@{ id='local'; descriptor='config/environments/local.json' }
        configuration=[ordered]@{ environmentFile='.env.local'; ownership='human'; targets=@([ordered]@{ application='sample-sut'; profile='dev'; relativeFile='config/sample-sut/application-dev.yml'; endpoint='/sample-sut/dev'; sutEvidence=[ordered]@{ kind='log-pattern'; patternId='property-source' } }) }
        suts=@([ordered]@{ id='sample-sut'; repository='${ORCH_ROOT}/sample-sut'; revision=$sutRevision; lifecycle='managed'; startContract='config/services/sample-sut/start-system-test.ps1'; healthProbe='sample-sut-health' })
        harness=[ordered]@{ revision=('a' * 64) }
        runner=[ordered]@{ workingDirectory='${TEST_ROOT}'; command=@('powershell.exe','-NoProfile','-File','scripts/run-suite.ps1'); failureCategory='SUT_BUSINESS' }
    }
    $secondSutRepo = Join-Path $orch 'second-sut'
    if ($MultiSut) {
        Initialize-Git $secondSutRepo
        Copy-Item -LiteralPath (Join-Path $sutRepo 'README.md') -Destination (Join-Path $secondSutRepo 'README.md')
        $secondRevision = Commit-All $secondSutRepo 'second baseline'
        foreach ($application in @('sample-module', 'second-sut')) {
            $manifest.configuration.targets += [ordered]@{ application=$application; profile='dev'; relativeFile="config/$application/application-dev.yml"; endpoint="/$application/dev"; sutEvidence=[ordered]@{ kind='log-pattern'; patternId='property-source' } }
            $manifest.suts += [ordered]@{ id=$application; repository=$(if ($application -eq 'sample-module') { $sutRepo } else { $secondSutRepo }); revision=$(if ($application -eq 'sample-module') { $sutRevision } else { $secondRevision }); lifecycle='managed'; startContract='config/services/sample-sut/start-system-test.ps1'; healthProbe='sample-sut-health' }
        }
    }
    $manifestPath = Join-Path $testRepo 'changes\sample\manifest.yaml'
    Write-Json $manifestPath $manifest
    [void](Commit-All $testRepo 'design inputs')
    $resolvedPath = Join-Path $testRepo 'changes\sample\resolved-manifest.json'
    $resolveOutput = @(& $resolver -OrchRoot $orch -SystemTestRepo $testRepo -ManifestPath $manifestPath -OutputPath $resolvedPath 2>&1)
    if ($LASTEXITCODE -ne 0) { throw "resolver fixture failed: $($resolveOutput -join ' | ')" }
    $testRevision = Commit-All $testRepo 'resolved design'
    $resolved = Get-Content -LiteralPath $resolvedPath -Raw -Encoding utf8 | ConvertFrom-Json
    $environmentLines = @()
    if ($ProvideDatabase) { $environmentLines += 'DATABASE_HOST=127.0.0.1', "DATABASE_PORT=$externalPort" }
    if ($ProvideCredential) { $environmentLines += 'DATABASE_CREDENTIAL=fixture-value-never-report' }
    Set-Content -LiteralPath (Join-Path $testRepo '.env.local') -Encoding utf8 -Value ($environmentLines -join "`n")
    $statePath = Join-Path $orch 'automation-state.json'
    $state = [ordered]@{
        schemaVersion=1; changeName='sample'; phase='TEST_IMPLEMENTATION_VERIFIED'; authorization=[ordered]@{ maxPhase='result' }
        repositories=[ordered]@{ systemTest=[IO.Path]::GetFullPath($testRepo); sut=[IO.Path]::GetFullPath($sutRepo) }
        revisions=[ordered]@{ designRevision=$testRevision; testBaseRevision=$testRevision; testBaseline=$testRevision; test=$testRevision; sut=$sutRevision; harness=('a' * 64) }
        configurationFingerprint=[string]$resolved.configurationFingerprint; harnessCertification=$null; leases=@(); runs=@(); failureFingerprints=@(); activeRun=$null; scopeVerification=$null; verifier=$null
        history=@(); createdAt=[DateTime]::UtcNow.ToString('o'); updatedAt=[DateTime]::UtcNow.ToString('o'); integrityHash=''
    }
    Write-State $statePath $state
    return [pscustomobject]@{ orch=$orch; testRepo=$testRepo; providerRepo=$providerRepo; sutRepo=$sutRepo; descriptor=$descriptorPath; manifest=$manifestPath; resolved=$resolvedPath; state=$statePath; report=(Join-Path $orch 'environment-report.json'); managedPort=$managedPort; externalPort=$externalPort; testRevision=$testRevision; sutRevision=$sutRevision; fingerprint=[string]$resolved.configurationFingerprint; harness=('a' * 64) }
}

function Invoke-Verifier($Fixture) {
    $output = @(& $verifier -ResolvedManifestPath $Fixture.resolved -StatePath $Fixture.state -OutputPath $Fixture.report -VerifierId 'environment-verifier' -ProbeTimeoutMs 600 2>&1)
    return [pscustomobject]@{ exitCode=$LASTEXITCODE; output=($output -join "`n"); report=$Fixture.report }
}

function Assert-Pass($Result, [string]$Label) {
    if ($Result.exitCode -ne 0 -or $Result.output -notmatch '\[TEST_ENVIRONMENT_VERIFIER\] PASS') { throw "$Label expected PASS`n$($Result.output)" }
}

function Assert-Blocked($Result, [string]$Category, [string]$Label) {
    if ($Result.exitCode -eq 0 -or $Result.output -notmatch '\[TEST_ENVIRONMENT_VERIFIER\] BLOCKED') { throw "$Label expected BLOCKED`n$($Result.output)" }
    $report = Get-Content -LiteralPath $Result.report -Raw -Encoding utf8 | ConvertFrom-Json
    if (@($report.steps | Where-Object { $_.result -ne 'PASS' -and $_.category -eq $Category }).Count -eq 0) { throw "$Label expected category $Category" }
}

try {
    $valid = New-Fixture 'valid'
    $external = Start-Listener $valid.externalPort
    try { $validResult = Invoke-Verifier $valid } finally { $external.Stop() }
    Assert-Pass $validResult 'valid preflight'
    $rawValidReport = Get-Content -LiteralPath $valid.report -Raw -Encoding utf8
    if ($rawValidReport -match 'fixture-value-never-report|DATABASE_CREDENTIAL|(?i)password|token|secret') { throw 'environment report leaked sensitive input or forbidden vocabulary' }
    $controllerOutput = @(& $controller record-verifier -StatePath $valid.state -VerifyMode environment -TestRevision $valid.testRevision -SutRevision $valid.sutRevision -HarnessRevision $valid.harness -ConfigurationFingerprint $valid.fingerprint -ReportPath $valid.report -VerifierId environment-verifier 2>&1)
    if ($LASTEXITCODE -ne 0 -or ($controllerOutput -join "`n") -notmatch '\[FLOW_CONTROLLER\] PASS') { throw "controller rejected environment report: $($controllerOutput -join ' | ')" }
    if ((Get-Content -LiteralPath $valid.state -Raw -Encoding utf8 | ConvertFrom-Json).phase -ne 'TEST_ENVIRONMENT_VERIFIED') { throw 'controller did not advance environment phase' }

    $multi = New-Fixture 'multi-literal' $false $true $true $true
    $external = Start-Listener $multi.externalPort
    try { $multiResult = Invoke-Verifier $multi } finally { $external.Stop() }
    Assert-Pass $multiResult 'literal TCP and three services across two repositories'
    $multiReport = Get-Content -LiteralPath $multi.report -Raw -Encoding utf8 | ConvertFrom-Json
    if (@($multiReport.steps | Where-Object { $_.stepId -eq 'sut-revision' -and $_.result -eq 'PASS' }).Count -ne 3) { throw 'all three SUTs must be verified' }
    Set-Content -LiteralPath (Join-Path $multi.orch 'second-sut/drift.txt') -Encoding utf8 -Value 'drift'
    [void](Commit-All (Join-Path $multi.orch 'second-sut') 'secondary drift')
    $external = Start-Listener $multi.externalPort
    try { $secondaryResult = Invoke-Verifier $multi } finally { $external.Stop() }
    Assert-Blocked $secondaryResult 'CONFIG_INFRA' 'secondary SUT revision drift'
    $secondaryReport = Get-Content -LiteralPath $multi.report -Raw -Encoding utf8 | ConvertFrom-Json
    if (@($secondaryReport.steps | Where-Object { $_.stepId -eq 'sut-revision' -and $_.resourceId -eq 'second-sut' -and $_.result -eq 'BLOCKED' }).Count -ne 1) { throw 'secondary revision must be independently rejected' }

    $missingPrimary = New-Fixture 'missing-primary'
    $state = Get-Content -LiteralPath $missingPrimary.state -Raw -Encoding utf8 | ConvertFrom-Json
    $state.repositories.sut = $missingPrimary.providerRepo
    Write-State $missingPrimary.state $state
    Assert-Blocked (Invoke-Verifier $missingPrimary) 'TEST_HARNESS' 'missing controller primary'

    $literalDown = New-Fixture 'literal-down' $false $true $true
    Assert-Blocked (Invoke-Verifier $literalDown) 'DATA_SCHEMA_CONTRACT' 'unavailable literal TCP endpoint'

    $externalDown = New-Fixture 'external-down'
    Assert-Blocked (Invoke-Verifier $externalDown) 'DATA_SCHEMA_CONTRACT' 'unavailable external dependency'

    $managedOccupied = New-Fixture 'managed-occupied'
    $external = Start-Listener $managedOccupied.externalPort
    $managed = Start-Listener $managedOccupied.managedPort
    try { $occupiedResult = Invoke-Verifier $managedOccupied } finally { $managed.Stop(); $external.Stop() }
    Assert-Blocked $occupiedResult 'CONFIG_INFRA' 'occupied managed port'

    $missingReference = New-Fixture 'missing-reference' $true $false
    $external = Start-Listener $missingReference.externalPort
    try { $referenceResult = Invoke-Verifier $missingReference } finally { $external.Stop() }
    Assert-Blocked $referenceResult 'CONFIG_INFRA' 'missing required reference'
    if ((Get-Content -LiteralPath $missingReference.report -Raw -Encoding utf8) -match 'DATABASE_CREDENTIAL|(?i)password|token|secret') { throw 'blocked report leaked reference identity or forbidden vocabulary' }

    $inputDrift = New-Fixture 'input-drift'
    Add-Content -LiteralPath $inputDrift.descriptor -Encoding utf8 -Value ' '
    Assert-Blocked (Invoke-Verifier $inputDrift) 'CONFIG_INFRA' 'descriptor drift'

    $providerDrift = New-Fixture 'provider-drift'
    Set-Content -LiteralPath (Join-Path $providerDrift.providerRepo 'drift.txt') -Encoding utf8 -Value 'drift'
    [void](Commit-All $providerDrift.providerRepo 'provider drift')
    Assert-Blocked (Invoke-Verifier $providerDrift) 'CONFIG_INFRA' 'provider revision drift'

    $resolvedTamper = New-Fixture 'resolved-tamper'
    $resolvedValue = Get-Content -LiteralPath $resolvedTamper.resolved -Raw -Encoding utf8 | ConvertFrom-Json
    $resolvedValue.resources[0].port = Get-FreePort
    Write-Json $resolvedTamper.resolved $resolvedValue
    Assert-Blocked (Invoke-Verifier $resolvedTamper) 'CONFIG_INFRA' 'resolved execution contract tamper'

    $missingStart = New-Fixture 'missing-start'
    Remove-Item -LiteralPath (Join-Path $missingStart.providerRepo 'scripts\start-native.ps1') -Force
    Assert-Blocked (Invoke-Verifier $missingStart) 'CONFIG_INFRA' 'missing managed start script'

    $phaseMismatch = New-Fixture 'phase-mismatch'
    $state = Get-Content -LiteralPath $phaseMismatch.state -Raw -Encoding utf8 | ConvertFrom-Json
    $state.phase = 'TEST_DESIGN_VERIFIED'; Write-State $phaseMismatch.state $state
    Assert-Blocked (Invoke-Verifier $phaseMismatch) 'TEST_HARNESS' 'controller phase mismatch'

    Write-Output '[TEST_ENVIRONMENT_PREFLIGHT_SELF_TEST] PASS'
    Write-Output 'cases: controller acceptance, external unavailable, managed port occupied, missing reference, input/provider/resolved drift, missing start contract, phase mismatch'
} finally {
    $resolvedRoot = [IO.Path]::GetFullPath($root)
    $tempRoot = [IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\', '/')
    if (-not $resolvedRoot.StartsWith($tempRoot + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase) -or
        [IO.Path]::GetFileName($resolvedRoot) -notlike 'flow-environment-preflight-*') { throw 'Unsafe temporary test cleanup target' }
    if (Test-Path -LiteralPath $resolvedRoot) { Remove-Item -LiteralPath $resolvedRoot -Recurse -Force }
}
