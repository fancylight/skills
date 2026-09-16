$ErrorActionPreference = 'Stop'
$repositoryRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$resolver = Join-Path (Split-Path -Parent $PSScriptRoot) 'resolve-test-environment.ps1'
$runtime = Join-Path $repositoryRoot 'templates\system-test\scripts\run-resolved-environment.ps1'
$root = Join-Path ([IO.Path]::GetTempPath()) ('flow-runtime-v2-' + [guid]::NewGuid().ToString('N'))

function Write-Json([string]$Path, $Value) {
    $parent = Split-Path -Parent $Path
    if (-not (Test-Path -LiteralPath $parent)) { [void](New-Item -ItemType Directory -Path $parent -Force) }
    [IO.File]::WriteAllText($Path, ($Value | ConvertTo-Json -Depth 16), [Text.UTF8Encoding]::new($false))
}

function Initialize-Git([string]$Path) {
    [void](New-Item -ItemType Directory -Path $Path -Force)
    & git -C $Path init --quiet
    & git -C $Path config user.email runtime-v2@example.invalid
    & git -C $Path config user.name runtime-v2-tests
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
    $listener.Start()
    try { return ([Net.IPEndPoint]$listener.LocalEndpoint).Port } finally { $listener.Stop() }
}

function Test-PortAvailable([int]$Port) {
    $listener = $null
    try {
        $listener = [Net.Sockets.TcpListener]::new([Net.IPAddress]::Loopback, $Port)
        $listener.Start()
        return $true
    } catch { return $false } finally { if ($null -ne $listener) { try { $listener.Stop() } catch {} } }
}

$serverScript = @'
param(
    [ValidateSet('provider','sut')] [string]$Mode,
    [int]$Port,
    [string]$Application = 'sample-sut',
    [string]$Profile = 'dev',
    [ValidateSet('good','mismatch','missing','health-fail')] [string]$TargetMode = 'good',
    [switch]$NoEvidence,
    [string]$SensitiveValue = ''
)
$ErrorActionPreference = 'Stop'
if ($Mode -eq 'sut') {
    if (-not $NoEvidence) { Write-Output "CONFIG_CONSUMED $Application/$Profile" }
    if (-not [string]::IsNullOrWhiteSpace($SensitiveValue)) { Write-Output "credential=$SensitiveValue" }
}
$listener = [Net.Sockets.TcpListener]::new([Net.IPAddress]::Loopback, $Port)
$listener.Start()
try {
    while ($true) {
        $client = $listener.AcceptTcpClient()
        try {
            $stream = $client.GetStream()
            $reader = [IO.StreamReader]::new($stream, [Text.Encoding]::ASCII, $false, 1024, $true)
            $requestLine = $reader.ReadLine()
            while (-not [string]::IsNullOrEmpty($reader.ReadLine())) {}
            $path = if ($requestLine -match '^\S+\s+(\S+)') { $matches[1] } else { '/' }
            $status = 200
            $body = '{"status":"UP"}'
            if ($Mode -eq 'provider' -and $path -eq '/actuator/health' -and $TargetMode -eq 'health-fail') {
                $status = 503; $body = '{"status":"DOWN"}'
            } elseif ($Mode -eq 'provider' -and $path -eq "/$Application/$Profile") {
                if ($TargetMode -eq 'missing') { $status = 404; $body = '{"error":"missing"}' }
                elseif ($TargetMode -eq 'mismatch') { $body = '{"name":"wrong","profiles":["dev"],"propertySources":[]}' }
                else { $body = "{`"name`":`"$Application`",`"profiles`":[`"$Profile`"],`"propertySources`":[]}" }
            } elseif ($Mode -eq 'provider' -and $path -match '^/(sample-sut-[2-4])/dev$') {
                $body = "{`"name`":`"$($matches[1])`",`"profiles`":[`"dev`"],`"propertySources`":[]}"
            } elseif ($path -ne '/actuator/health') { $status = 404; $body = '{"error":"not-found"}' }
            $reason = if ($status -eq 200) { 'OK' } else { 'Not Found' }
            $bytes = [Text.Encoding]::UTF8.GetBytes($body)
            $header = "HTTP/1.1 $status $reason`r`nContent-Type: application/json`r`nContent-Length: $($bytes.Length)`r`nConnection: close`r`n`r`n"
            $headerBytes = [Text.Encoding]::ASCII.GetBytes($header)
            $stream.Write($headerBytes, 0, $headerBytes.Length)
            $stream.Write($bytes, 0, $bytes.Length)
        } finally { $client.Dispose() }
    }
} finally { $listener.Stop() }
'@

function New-Fixture([string]$Name, [string]$TargetMode = 'good', [bool]$EmitEvidence = $true, [int]$SuiteExit = 0, [string]$SensitiveValue = '', [int]$SuiteDelaySeconds = 0, [int]$SutCount = 1) {
    $orch = Join-Path $root $Name
    $testRepo = Join-Path $orch 'system-test'
    $providerRepo = Join-Path $orch 'config-provider'
    $sutRepo = Join-Path $orch 'sample-sut'
    Initialize-Git $providerRepo; Initialize-Git $sutRepo; Initialize-Git $testRepo
    $providerPort = Get-FreePort
    $sutPort = Get-FreePort

    [void](New-Item -ItemType Directory -Path (Join-Path $providerRepo 'src\main\resources') -Force)
    [void](New-Item -ItemType Directory -Path (Join-Path $providerRepo 'config\sample-sut') -Force)
    [void](New-Item -ItemType Directory -Path (Join-Path $providerRepo 'scripts') -Force)
    Set-Content -LiteralPath (Join-Path $providerRepo 'pom.xml') -Encoding utf8 -NoNewline -Value '<project />'
    Set-Content -LiteralPath (Join-Path $providerRepo 'src\main\resources\application-native.yml') -Encoding utf8 -NoNewline -Value 'spring: {}'
    Set-Content -LiteralPath (Join-Path $providerRepo 'config\sample-sut\application-dev.yml') -Encoding utf8 -NoNewline -Value 'feature: enabled'
    Set-Content -LiteralPath (Join-Path $providerRepo 'scripts\fake-http.ps1') -Encoding utf8 -NoNewline -Value $serverScript
    Set-Content -LiteralPath (Join-Path $providerRepo 'scripts\start-native.ps1') -Encoding utf8 -NoNewline -Value $serverScript
    $providerRevision = Commit-All $providerRepo 'provider fixture'

    Set-Content -LiteralPath (Join-Path $sutRepo 'README.md') -Encoding utf8 -NoNewline -Value 'sut fixture'
    Set-Content -LiteralPath (Join-Path $sutRepo 'fake-http.ps1') -Encoding utf8 -NoNewline -Value $serverScript
    $sutRevision = Commit-All $sutRepo 'sut fixture'

    [void](New-Item -ItemType Directory -Path (Join-Path $testRepo 'config\environments') -Force)
    [void](New-Item -ItemType Directory -Path (Join-Path $testRepo 'config\services\sample-sut') -Force)
    [void](New-Item -ItemType Directory -Path (Join-Path $testRepo 'changes\sample') -Force)
    [void](New-Item -ItemType Directory -Path (Join-Path $testRepo 'scripts') -Force)
    $sutServerScript = $serverScript.Replace("[ValidateSet('provider','sut')] [string]`$Mode,", "[ValidateSet('provider','sut')] [string]`$Mode = 'sut',").Replace('[int]$Port,', "[int]`$Port = $sutPort,")
    if (-not $EmitEvidence) { $sutServerScript = $sutServerScript.Replace('[switch]$NoEvidence,', '[switch]$NoEvidence = $true,') }
    if (-not [string]::IsNullOrWhiteSpace($SensitiveValue)) { $sutServerScript = $sutServerScript.Replace("[string]`$SensitiveValue = ''", "[string]`$SensitiveValue = '$SensitiveValue'") }
    Set-Content -LiteralPath (Join-Path $testRepo 'config\services\sample-sut\start-system-test.ps1') -Encoding utf8 -NoNewline -Value $sutServerScript
    Set-Content -LiteralPath (Join-Path $testRepo 'scripts\run-suite.ps1') -Encoding utf8 -NoNewline -Value "Write-Output 'suite'; Start-Sleep -Seconds $SuiteDelaySeconds; exit $SuiteExit"

    $descriptor = [ordered]@{
        schemaVersion=1; id='local'; playbook='docs/local-integration-playbook.md'
        configurationProvider=[ordered]@{ kind='spring-config-native'; repository='${ORCH_ROOT}/config-provider'; baseUri="http://127.0.0.1:$providerPort"; configRoot='config'; serviceRef='config-provider' }
        resources=@([ordered]@{ id='config-provider'; kind='configuration-provider'; lifecycle='managed'; executable='powershell.exe'; arguments=@('-NoProfile','-ExecutionPolicy','Bypass','-File','scripts/start-native.ps1','-Mode','provider','-Port',[string]$providerPort,'-TargetMode',$TargetMode); workingDirectory='${ORCH_ROOT}/config-provider'; port=$providerPort; readinessProbe='provider-health'; identityProbe='provider-identity'; dependsOn=@() })
        probes=@(
            [ordered]@{ id='provider-identity'; stage='runtime'; kind='http'; method='GET'; url="http://127.0.0.1:$providerPort/sample-sut/dev"; expectStatus=200; expectBodyRegex='"name":"sample-sut"'; failureCategory='CONFIG_INFRA' },
            [ordered]@{ id='provider-health'; stage='runtime'; kind='http'; method='GET'; url="http://127.0.0.1:$providerPort/actuator/health"; expectStatus=200; failureCategory='CONFIG_INFRA' },
            [ordered]@{ id='sut-health'; stage='runtime'; kind='http'; method='GET'; url="http://127.0.0.1:$sutPort/actuator/health"; expectStatus=200; failureCategory='CONFIG_INFRA' }
        )
        evidenceContracts=@([ordered]@{ id='config-consumption'; kind='log-regex'; pattern='CONFIG_CONSUMED\s+sample-sut/dev' })
    }
    Write-Json (Join-Path $testRepo 'config\environments\local.json') $descriptor
    $manifest = [ordered]@{
        schemaVersion=2; stage='design'; environment=[ordered]@{ id='local'; descriptor='config/environments/local.json' }
        configuration=[ordered]@{ environmentFile='.env.local'; ownership='human'; targets=@([ordered]@{ application='sample-sut'; profile='dev'; relativeFile='config/sample-sut/application-dev.yml'; endpoint='/sample-sut/dev'; sutEvidence=[ordered]@{ kind='log-pattern'; patternId='config-consumption' } }) }
        suts=@([ordered]@{ id='sample-sut'; repository='${ORCH_ROOT}/sample-sut'; revision=$sutRevision; lifecycle='managed'; startContract='config/services/sample-sut/start-system-test.ps1'; healthProbe='sut-health' })
        harness=[ordered]@{ revision=('b' * 64) }
        runner=[ordered]@{ workingDirectory='${TEST_ROOT}'; command=@('powershell.exe','-NoProfile','-ExecutionPolicy','Bypass','-File','scripts/run-suite.ps1'); failureCategory='SUT_BUSINESS' }
    }
    $manifestPath = Join-Path $testRepo 'changes\sample\manifest.json'
    for ($sutIndex = 2; $sutIndex -le $SutCount; $sutIndex++) {
        $extraId = "sample-sut-$sutIndex"
        $extraRepo = Join-Path $orch $extraId
        Initialize-Git $extraRepo
        Set-Content -LiteralPath (Join-Path $extraRepo 'README.md') -Value $extraId
        $extraRevision = Commit-All $extraRepo 'additional SUT fixture'
        $extraPort = Get-FreePort
        $extraConfig = Join-Path $providerRepo "config/$extraId"
        $extraStart = Join-Path $testRepo "config/services/$extraId"
        [void](New-Item -ItemType Directory -Path $extraConfig,$extraStart -Force)
        Set-Content -LiteralPath (Join-Path $extraConfig 'application-dev.yml') -Value 'feature: enabled'
        $extraScript = $sutServerScript.Replace("'sample-sut'", "'$extraId'").Replace("[int]`$Port = $sutPort,", "[int]`$Port = $extraPort,")
        Set-Content -LiteralPath (Join-Path $extraStart 'start-system-test.ps1') -Value $extraScript
        $manifest.configuration.targets += [ordered]@{ application=$extraId; profile='dev'; relativeFile="config/$extraId/application-dev.yml"; endpoint="/$extraId/dev"; sutEvidence=@{ kind='log-pattern'; patternId="consumption-$extraId" } }
        $manifest.suts += [ordered]@{ id=$extraId; repository=('${ORCH_ROOT}/' + $extraId); revision=$extraRevision; lifecycle='managed'; startContract="config/services/$extraId/start-system-test.ps1"; healthProbe="health-$extraId" }
        $descriptor.probes += [ordered]@{ id="health-$extraId"; stage='runtime'; kind='http'; url="http://127.0.0.1:$extraPort/actuator/health"; expectStatus=200; failureCategory='CONFIG_INFRA' }
        $descriptor.evidenceContracts += [ordered]@{ id="consumption-$extraId"; kind='log-regex'; pattern="CONFIG_CONSUMED\s+$extraId/dev" }
    }
    if ($SutCount -gt 1) {
        [void](Commit-All $providerRepo 'additional configuration targets')
        Write-Json (Join-Path $testRepo 'config/environments/local.json') $descriptor
    }
    Write-Json $manifestPath $manifest
    Set-Content -LiteralPath (Join-Path $testRepo '.env.local') -Encoding utf8 -NoNewline -Value $(if ([string]::IsNullOrWhiteSpace($SensitiveValue)) { '' } else { "FIXTURE_VALUE=$SensitiveValue" })
    [void](Commit-All $testRepo 'runtime design')
    $resolvedPath = Join-Path $testRepo 'changes\sample\resolved-manifest.json'
    $resolveOutput = @(& $resolver -OrchRoot $orch -SystemTestRepo $testRepo -ManifestPath $manifestPath -OutputPath $resolvedPath 2>&1)
    if ($LASTEXITCODE -ne 0) { throw "resolver failed: $($resolveOutput -join ' | ')" }
    $resolved = Get-Content -LiteralPath $resolvedPath -Raw -Encoding utf8 | ConvertFrom-Json
    return [pscustomobject]@{ orch=$orch; testRepo=$testRepo; providerRepo=$providerRepo; providerPort=$providerPort; sutPort=$sutPort; resolved=$resolvedPath; fingerprint=[string]$resolved.configurationFingerprint; report=(Join-Path $orch 'runtime-result.json') }
}

function Invoke-Runtime($Fixture) {
    $lines = @(& powershell.exe -NoProfile -ExecutionPolicy Bypass -File $runtime -ResolvedManifestPath $Fixture.resolved -ExpectedFingerprint $Fixture.fingerprint -OutputPath $Fixture.report -ProbeTimeoutMs 500 -StartupTimeoutMs 4500 2>&1)
    $report = if (Test-Path -LiteralPath $Fixture.report) { Get-Content -LiteralPath $Fixture.report -Raw -Encoding utf8 | ConvertFrom-Json } else { $null }
    return [pscustomobject]@{ exitCode=$LASTEXITCODE; output=($lines -join "`n"); report=$report }
}

function Resolve-Fixture($Fixture) {
    $manifestPath = Join-Path $Fixture.testRepo 'changes/sample/manifest.json'
    $lines = @(& $resolver -OrchRoot $Fixture.orch -SystemTestRepo $Fixture.testRepo -ManifestPath $manifestPath -OutputPath $Fixture.resolved 2>&1)
    if ($LASTEXITCODE -ne 0) { throw "fixture resolution failed: $($lines -join ' | ')" }
    $Fixture.fingerprint = [string](Get-Content -LiteralPath $Fixture.resolved -Raw | ConvertFrom-Json).configurationFingerprint
}

function Assert-Result($Actual, [string]$Expected, [string]$Category, [string]$Label) {
    if ($null -eq $Actual.report -or [string]$Actual.report.result -ne $Expected -or [string]$Actual.report.failureCategory -ne $Category) {
        throw "$Label expected $Expected/$Category`n$($Actual.output)"
    }
}

function Enable-CertifiedHarness($Fixture) {
    $templateRoot = Join-Path $repositoryRoot 'templates\system-test'
    foreach ($item in Get-ChildItem -LiteralPath $templateRoot -Force) {
        Copy-Item -LiteralPath $item.FullName -Destination $Fixture.testRepo -Recurse -Force
    }
    Copy-Item -LiteralPath (Join-Path $Fixture.testRepo 'changes\sample\manifest.json') -Destination (Join-Path $Fixture.testRepo 'changes\sample\manifest.yaml') -Force
    $certifiedHarness = Join-Path $Fixture.orch 'certified harness'
    Copy-Item -LiteralPath $templateRoot -Destination $certifiedHarness -Recurse
    $selfTest = Join-Path $certifiedHarness 'self-test\invoke-harness-self-test.ps1'
    $certifier = Join-Path $certifiedHarness 'scripts\harness-certification.ps1'
    $selfTestReport = Join-Path $certifiedHarness 'self-test\v2-dispatch-self-test.json'
    $sourceCertification = Join-Path $certifiedHarness 'self-test\v2-dispatch-certification.json'
    $selfTestOutput = @(& $selfTest -HarnessRoot $certifiedHarness -ReportPath $selfTestReport -RuntimeExecutable 'powershell.exe' 2>&1)
    if ($LASTEXITCODE -ne 0) { throw "v2 dispatch harness self-test failed: $($selfTestOutput -join ' | ')" }
    & $certifier certify -HarnessRoot $certifiedHarness -CertificationPath $sourceCertification -SelfTestReport $selfTestReport -HarnessVersion 'v2-dispatch-test' | Out-Null
    if ($LASTEXITCODE -ne 0) { throw 'v2 dispatch harness certification failed' }
    Copy-Item -LiteralPath (Join-Path $certifiedHarness 'self-test') -Destination $Fixture.testRepo -Recurse -Force
    $certification = Join-Path $Fixture.testRepo 'self-test\v2-dispatch-certification.json'
    return $certification
}

try {
    $happy = New-Fixture 'happy'
    Assert-Result (Invoke-Runtime $happy) 'PASS' 'NONE' 'happy path'
    $multi = New-Fixture 'four-sut-target-association' -SutCount 4
    $multiResult = Invoke-Runtime $multi
    Assert-Result $multiResult 'PASS' 'NONE' 'four SUT target association'
    if (@($multiResult.report.steps | Where-Object { $_.phase -eq 'configuration-consumption' }).Count -ne 4) { throw 'Configuration evidence was not associated once per SUT' }

    $providerFailure = New-Fixture 'provider-health-failure' 'health-fail'
    Assert-Result (Invoke-Runtime $providerFailure) 'BLOCKED' 'CONFIG_INFRA' 'provider readiness failure'

    $sourceDrift = New-Fixture 'source-drift'
    Set-Content -LiteralPath (Join-Path $sourceDrift.providerRepo 'config\sample-sut\application-dev.yml') -Encoding utf8 -NoNewline -Value 'feature: drifted'
    Assert-Result (Invoke-Runtime $sourceDrift) 'BLOCKED' 'CONFIG_INFRA' 'source drift recheck'

    $targetMismatch = New-Fixture 'target-mismatch' 'mismatch'
    Assert-Result (Invoke-Runtime $targetMismatch) 'BLOCKED' 'CONFIG_INFRA' 'target identity mismatch'

    $missingEvidence = New-Fixture 'missing-evidence' 'good' $false
    Assert-Result (Invoke-Runtime $missingEvidence) 'BLOCKED' 'CONFIG_INFRA' 'missing consumption evidence'

    $suiteFailure = New-Fixture 'suite-failure' 'good' $true 7
    $suiteFixtureText = Get-Content -LiteralPath (Join-Path $suiteFailure.testRepo 'scripts\run-suite.ps1') -Raw -Encoding utf8
    if ($suiteFixtureText -notmatch 'exit 7') { throw "suite failure fixture was not generated correctly: $suiteFixtureText" }
    Assert-Result (Invoke-Runtime $suiteFailure) 'BLOCKED' 'SUT_BUSINESS' 'suite failure attribution'

    $reuse = New-Fixture 'reuse'
    $reuseStdout = Join-Path $reuse.orch 'reused-provider.stdout.log'
    $reuseStderr = Join-Path $reuse.orch 'reused-provider.stderr.log'
    $reuseProcess = Start-Process -FilePath 'powershell.exe' -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File scripts/start-native.ps1 -Mode provider -Port $($reuse.providerPort)" -WorkingDirectory $reuse.providerRepo -RedirectStandardOutput $reuseStdout -RedirectStandardError $reuseStderr -PassThru -WindowStyle Hidden
    Start-Sleep -Milliseconds 700
    try {
        $reuseResult = Invoke-Runtime $reuse
        Assert-Result $reuseResult 'PASS' 'NONE' 'reused provider'
        if ($reuseProcess.HasExited) { throw 'reused provider was stopped by runtime cleanup' }
        if (@($reuseResult.report.steps | Where-Object { $_.stepId -eq 'resource-config-provider' -and $_.detail -match 'reused' }).Count -ne 1) { throw 'reused provider ownership was not reported' }
    } finally { if (-not $reuseProcess.HasExited) { Stop-Process -Id $reuseProcess.Id -Force } }

    $sensitive = 'runtime-sensitive-value-92731'
    $redaction = New-Fixture 'redaction' 'good' $true 0 $sensitive
    $redactionResult = Invoke-Runtime $redaction
    Assert-Result $redactionResult 'PASS' 'NONE' 'redaction path'
    $evidenceText = (Get-Content -LiteralPath $redaction.report -Raw -Encoding utf8) + $redactionResult.output
    foreach ($log in Get-ChildItem -LiteralPath (Join-Path $redaction.orch 'logs') -File) { $evidenceText += Get-Content -LiteralPath $log.FullName -Raw }
    if ($evidenceText.Contains($sensitive)) { throw 'runtime evidence leaked an environment value' }

    $interrupted = New-Fixture 'interrupted' 'good' $true 0 '' 30
    $interruptState = Join-Path $interrupted.orch 'runtime-state.json'
    $interruptStdout = Join-Path $interrupted.orch 'runtime.stdout.log'
    $interruptStderr = Join-Path $interrupted.orch 'runtime.stderr.log'
    $interruptArgs = "-NoProfile -ExecutionPolicy Bypass -File `"$runtime`" -ResolvedManifestPath `"$($interrupted.resolved)`" -ExpectedFingerprint $($interrupted.fingerprint) -OutputPath `"$($interrupted.report)`" -StatePath `"$interruptState`" -ProbeTimeoutMs 500 -StartupTimeoutMs 4500"
    # Start-Process does not apply pwsh's native-command PSModulePath cleanup.
    # Give the PS5 child its own built-in modules instead of PS7-only modules.
    $savedModulePath=$env:PSModulePath
    try {
        $env:PSModulePath=(Join-Path $env:WINDIR 'System32/WindowsPowerShell/v1.0/Modules')+';'+$savedModulePath
        $runtimeProcess = Start-Process -FilePath 'powershell.exe' -ArgumentList $interruptArgs -RedirectStandardOutput $interruptStdout -RedirectStandardError $interruptStderr -PassThru -WindowStyle Hidden
    } finally { $env:PSModulePath=$savedModulePath }
    $deadline = [DateTime]::UtcNow.AddSeconds(12)
    $ownedCount = 0
    do {
        Start-Sleep -Milliseconds 200
        if (Test-Path -LiteralPath $interruptState -PathType Leaf) {
            try { $ownedCount = @((Get-Content -LiteralPath $interruptState -Raw -Encoding utf8 | ConvertFrom-Json).processes).Count } catch { $ownedCount = 0 }
        }
    } while ($ownedCount -lt 3 -and -not $runtimeProcess.HasExited -and [DateTime]::UtcNow -lt $deadline)
    if ($ownedCount -lt 3) { throw 'interruption fixture did not persist provider/SUT/suite ownership' }
    Stop-Process -Id $runtimeProcess.Id -Force
    $cleanupReport = Join-Path $interrupted.orch 'cleanup-result.json'
    $cleanupOutput = @(& powershell.exe -NoProfile -ExecutionPolicy Bypass -File $runtime -Command cleanup -OutputPath $cleanupReport -StatePath $interruptState 2>&1)
    if ($LASTEXITCODE -ne 0 -or (Test-Path -LiteralPath $interruptState)) { throw "interrupted cleanup recovery failed: $($cleanupOutput -join ' | ')" }
    if (-not (Test-PortAvailable $interrupted.providerPort) -or -not (Test-PortAvailable $interrupted.sutPort)) { throw 'interrupted cleanup left a declared service port occupied' }

    $prepareFailure = New-Fixture 'prepare-failure'
    $prepareManifestPath = Join-Path $prepareFailure.testRepo 'changes/sample/manifest.json'
    $prepareManifest = Get-Content -LiteralPath $prepareManifestPath -Raw | ConvertFrom-Json
    $prepareManifest.runner | Add-Member -NotePropertyName prepare -NotePropertyValue @('powershell.exe','-NoProfile','-File','scripts/prepare.ps1')
    Set-Content -LiteralPath (Join-Path $prepareFailure.testRepo 'scripts/prepare.ps1') -Value "Write-Output 'mapping registration rejected: 409'; exit 23"
    Write-Json $prepareManifestPath $prepareManifest
    Resolve-Fixture $prepareFailure
    $prepareResult = Invoke-Runtime $prepareFailure
    Assert-Result $prepareResult 'BLOCKED' 'TEST_HARNESS' 'prepare failure'
    if (@($prepareResult.report.steps | Where-Object { $_.phase -in @('sut-start','suite') }).Count -gt 0) { throw 'Failed preparation entered the business lifecycle' }
    if ((Get-Content -LiteralPath (Join-Path $prepareFailure.orch 'logs/fixture-prepare.stdout.log') -Raw) -notmatch '409') { throw 'First contract failure response was lost' }
    Set-Content -LiteralPath (Join-Path $prepareFailure.testRepo 'scripts/prepare.ps1') -Value "Write-Output 'existing schema lacks required columns'; exit 78"
    $prepareInfraResult = Invoke-Runtime $prepareFailure
    Assert-Result $prepareInfraResult 'BLOCKED' 'CONFIG_INFRA' 'prepare environmental prerequisite'
    if (@($prepareInfraResult.report.steps | Where-Object { $_.phase -in @('sut-start','suite') }).Count -gt 0) { throw 'Missing environment prerequisite entered the business lifecycle' }

    $timeout = New-Fixture 'hard-timeout' 'good' $true 0 '' 30
    $timeoutStart = [DateTime]::UtcNow
    $timeoutOutput = @(& powershell.exe -NoProfile -ExecutionPolicy Bypass -File $runtime -ResolvedManifestPath $timeout.resolved -ExpectedFingerprint $timeout.fingerprint -OutputPath $timeout.report -StartupTimeoutMs 4500 -SuiteTimeoutMs 500 2>&1)
    $timeoutReport = Get-Content -LiteralPath $timeout.report -Raw | ConvertFrom-Json
    if ($timeoutReport.result -ne 'BLOCKED' -or $timeoutReport.summary -notmatch 'runtime limit' -or ([DateTime]::UtcNow - $timeoutStart).TotalSeconds -gt 20) { throw 'Suite hard timeout did not terminate the owned command' }
    if (-not (Test-PortAvailable $timeout.providerPort) -or -not (Test-PortAvailable $timeout.sutPort)) { throw 'Timeout leaked service processes' }

    $previousDeadline=$env:FLOW_EXECUTION_DEADLINE
    try {
        $env:FLOW_EXECUTION_DEADLINE=[DateTime]::UtcNow.AddSeconds(90).ToString('o')
        $expired=Invoke-Runtime $timeout
        Assert-Result $expired 'BLOCKED' 'BUDGET_EXHAUSTED' 'persistent deadline reserves cleanup'
        if (@($expired.report.steps | Where-Object { $_.phase -in @('sut-start','suite') }).Count) {throw 'expired budget launched a suite'}
    } finally { $env:FLOW_EXECUTION_DEADLINE=$previousDeadline }

    $doubleFailure=New-Fixture 'business-and-cleanup' 'good' $true 1
    $doubleManifest=Join-Path $doubleFailure.testRepo 'changes/sample/manifest.json'
    $doubleConfig=Get-Content $doubleManifest -Raw | ConvertFrom-Json
    $doubleConfig.runner | Add-Member -Force -NotePropertyName prepare -NotePropertyValue @('powershell.exe','-NoProfile','-Command','exit 0')
    $doubleConfig.runner | Add-Member -Force -NotePropertyName cleanup -NotePropertyValue @('powershell.exe','-NoProfile','-Command','exit 1')
    Write-Json $doubleManifest $doubleConfig
    Resolve-Fixture $doubleFailure
    $doubleResult=Invoke-Runtime $doubleFailure
    Assert-Result $doubleResult 'BLOCKED' 'SUT_BUSINESS' 'cleanup preserves original business failure'
    if (-not $doubleResult.report.primaryFailure -or @($doubleResult.report.steps | Where-Object { $_.phase -eq 'cleanup' -and $_.result -ne 'PASS' }).Count -eq 0) {throw 'lost one of the two failures'}

    $external = New-Fixture 'external-provider'
    $externalDescriptorPath = Join-Path $external.testRepo 'config/environments/local.json'
    $externalDescriptor = Get-Content -LiteralPath $externalDescriptorPath -Raw | ConvertFrom-Json
    $externalDescriptor.resources[0].lifecycle = 'external'
    $externalDescriptor.resources[0].executable = 'must-never-be-executed.exe'
    $externalDescriptor.resources[0] | Add-Member -NotePropertyName preflightProbe -NotePropertyValue 'provider-health'
    $externalDescriptor.probes[0].stage = 'preflight'
    ($externalDescriptor.probes | Where-Object { $_.id -eq 'provider-health' }).stage = 'preflight'
    Write-Json $externalDescriptorPath $externalDescriptor
    Resolve-Fixture $external
    $externalProcess = Start-Process -FilePath 'powershell.exe' -ArgumentList "-NoProfile -File scripts/start-native.ps1 -Mode provider -Port $($external.providerPort)" -WorkingDirectory $external.providerRepo -PassThru -WindowStyle Hidden
    try {
        Start-Sleep -Milliseconds 700
        Assert-Result (Invoke-Runtime $external) 'PASS' 'NONE' 'external provider'
        if ($externalProcess.HasExited) { throw 'Runtime terminated an external process' }
    } finally { if (-not $externalProcess.HasExited) { Stop-Process -Id $externalProcess.Id -Force } }

    $dispatch = New-Fixture 'system-test-v2-dispatch'
    $certification = Enable-CertifiedHarness $dispatch
    $systemTestRunner = Join-Path $dispatch.testRepo 'scripts\system-test.ps1'
    $structuredDispatch = Join-Path $dispatch.orch 'system-test-structured.json'
    $dispatchOutput = @(& powershell.exe -NoProfile -ExecutionPolicy Bypass -File $systemTestRunner run -Change sample -ExecutionMode standalone -EnvFile .env.local -HarnessCertificationPath $certification -StructuredResultPath $structuredDispatch 2>&1)
    if ($LASTEXITCODE -ne 0 -or ($dispatchOutput -join "`n") -notmatch '\[SYSTEM_TEST_RESULT\] PASS') { throw "v2 system-test dispatch failed: $($dispatchOutput -join ' | ')" }
    $dispatchStructured = Get-Content -LiteralPath $structuredDispatch -Raw -Encoding utf8 | ConvertFrom-Json
    if ([string]$dispatchStructured.status -ne 'PASS' -or -not (Test-Path -LiteralPath ([string]$dispatchStructured.rawEvidencePath) -PathType Leaf)) { throw 'v2 system-test dispatch evidence is incomplete' }
    $oldPreference = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
    try { $missingFingerprintOutput = @(& powershell.exe -NoProfile -ExecutionPolicy Bypass -File $systemTestRunner run -Change sample -ExecutionMode orchestrated -EnvFile .env.local -HarnessCertificationPath $certification 2>&1); $missingFingerprintExit = $LASTEXITCODE }
    finally { $ErrorActionPreference = $oldPreference }
    if ($missingFingerprintExit -eq 0 -or ($missingFingerprintOutput -join "`n") -notmatch 'requires the controller configuration fingerprint') { throw 'orchestrated v2 dispatch accepted a missing controller fingerprint' }

    $selectedRoot = Join-Path $dispatch.testRepo 'changes/sample'
    $selectedSource = Join-Path $selectedRoot 'test-cases.yaml'
    Set-Content -LiteralPath $selectedSource -Value 'scenarios: [SMOKE-1, FULL-1]'
    Write-Json (Join-Path $selectedRoot 'test-cases.generated.json') ([ordered]@{
        kind='flow-test-cases-derived'; source=@{ path='test-cases.yaml'; sha256=(Get-FileHash $selectedSource).Hash.ToLowerInvariant() }
        runnerFilters=@(@{ id='SMOKE-1'; filter='example.SmokeTest#complete' })
        failureObservability=@(@{ id='SMOKE-1'; testClass='example.SmokeTest'; testMethod='complete' })
    })
    $selectedManifest = Get-Content -LiteralPath (Join-Path $selectedRoot 'manifest.json') -Raw | ConvertFrom-Json
    $selectedManifest | Add-Member -NotePropertyName testCasesContract -NotePropertyValue @{ path='test-cases.generated.json' }
    $selectedManifest.runner.command = @('powershell.exe','-NoProfile','-File','scripts/run-selected.ps1','-Filter','${FLOW_TEST_FILTER}','-ReportDirectory','${FLOW_TEST_REPORT_DIR}')
    $selectedScript = @'
param([string]$Filter, [string]$ReportDirectory)
if ($Filter -ne 'example.SmokeTest#complete') { exit 27 }
[void](New-Item -ItemType Directory -Path $ReportDirectory -Force)
Set-Content -LiteralPath (Join-Path $ReportDirectory 'TEST-example.SmokeTest.xml') -Value '<testsuite><testcase classname="example.SmokeTest" name="complete" /></testsuite>'
'@
    Set-Content -LiteralPath (Join-Path $dispatch.testRepo 'scripts/run-selected.ps1') -Value $selectedScript
    Write-Json (Join-Path $selectedRoot 'manifest.json') $selectedManifest
    Write-Json (Join-Path $selectedRoot 'manifest.yaml') $selectedManifest
    Resolve-Fixture $dispatch
    $selectionOutput = @(& powershell.exe -NoProfile -ExecutionPolicy Bypass -File $systemTestRunner run -Change sample -ExecutionMode standalone -ScenarioIds SMOKE-1 -EnvFile .env.local -HarnessCertificationPath $certification -StructuredResultPath $structuredDispatch 2>&1)
    if ($LASTEXITCODE -ne 0) { throw "Selected v2 dispatch failed: $($selectionOutput -join ' | ')" }
    $selectionResult = Get-Content -LiteralPath $structuredDispatch -Raw | ConvertFrom-Json
    if ($selectionResult.fullSuite -or $selectionResult.counts.passed -ne 1 -or $selectionResult.scenarioIds[0] -ne 'SMOKE-1' -or $selectionResult.rawEvidencePath -notmatch '[\\/]runs[\\/]') { throw 'Selected v2 dispatch returned an invalid full/partial result' }
    $rawSelectedResult = Get-Content -LiteralPath (Join-Path (Split-Path -Parent $selectionResult.rawEvidencePath) 'runtime-result.json') -Raw | ConvertFrom-Json
    if ($rawSelectedResult.fullSuite -or $rawSelectedResult.scenarioIds[0] -ne 'SMOKE-1') { throw 'Raw runtime evidence omitted its partial scope' }
    # Exercise the actual formal runner with a registered, integrity-protected
    # synthetic controller receipt. The fixture XML is not business evidence.
    $registeredPath=Join-Path $dispatch.orch 'registered-state.json'
    $formalOutput=Join-Path $dispatch.orch 'formal-slice.json'
    $registered=[ordered]@{phase='TEST_EXECUTING';changeName='sample';repositories=@{systemTest=$dispatch.testRepo};activeRun=@{runId='formal-fixture';executionKey='fixture-binding';scenarioIds=@('SMOKE-1');deadlineUtc=[DateTime]::UtcNow.AddMinutes(30).ToString('o');evidence=$formalOutput};integrityHash=''}
    $sha=[Security.Cryptography.SHA256]::Create()
    try { $registered.integrityHash=-join ($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes(($registered | ConvertTo-Json -Depth 16 -Compress))) | ForEach-Object {$_.ToString('x2')}) } finally { $sha.Dispose() }
    Write-Json $registeredPath $registered
    $savedExecution=@{}
    $executionValues=@{FLOW_EXECUTION_STATE=$registeredPath;FLOW_EXECUTION_RUN='formal-fixture';FLOW_EXECUTION_KEY='fixture-binding';FLOW_EXECUTION_DEADLINE=$registered.activeRun.deadlineUtc}
    try {
        foreach($key in $executionValues.Keys){$savedExecution[$key]=[Environment]::GetEnvironmentVariable($key);[Environment]::SetEnvironmentVariable($key,$executionValues[$key])}
        $formalLines=@(& powershell.exe -NoProfile -ExecutionPolicy Bypass -File $systemTestRunner run -Change sample -ExecutionMode orchestrated -ScenarioIds SMOKE-1 -ConfigurationFingerprint $dispatch.fingerprint -EnvFile .env.local -HarnessCertificationPath $certification -StructuredResultPath $formalOutput 2>&1)
        if ($LASTEXITCODE -ne 0) {throw "Formal slice failed: $($formalLines -join ' | ')"}
        $formal=Get-Content $formalOutput -Raw|ConvertFrom-Json
        if($formal.flowRunId -ne 'formal-fixture' -or $formal.executionKey -ne 'fixture-binding' -or $formal.fullSuite -or $formal.counts.passed -ne 1){throw 'formal selected evidence binding lost'}
        $originalHash=(Get-FileHash $formalOutput).Hash
        $oldPreference=$ErrorActionPreference;$ErrorActionPreference='Continue'
        try {$repeat=@(& powershell.exe -NoProfile -ExecutionPolicy Bypass -File $systemTestRunner run -Change sample -ExecutionMode orchestrated -ScenarioIds SMOKE-1 -ConfigurationFingerprint $dispatch.fingerprint -EnvFile .env.local -HarnessCertificationPath $certification -StructuredResultPath $formalOutput 2>&1)} finally {$ErrorActionPreference=$oldPreference}
        if($LASTEXITCODE -eq 0 -or ($repeat -join ' ') -notmatch 'already dispatched' -or (Get-FileHash $formalOutput).Hash -ne $originalHash){throw 'registered interruption retry redelivered/overwrote evidence'}
    } finally {foreach($key in $savedExecution.Keys){[Environment]::SetEnvironmentVariable($key,$savedExecution[$key])}}
    $selectedManifest.runner | Add-Member -NotePropertyName prepare -NotePropertyValue @('powershell.exe','-NoProfile','-File','scripts/precondition.ps1')
    Set-Content -LiteralPath (Join-Path $dispatch.testRepo 'scripts/precondition.ps1') -Value 'exit 78'
    Write-Json (Join-Path $selectedRoot 'manifest.json') $selectedManifest
    Write-Json (Join-Path $selectedRoot 'manifest.yaml') $selectedManifest
    Resolve-Fixture $dispatch
    $oldPreference = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
    try { $blockedSelectionOutput = @(& powershell.exe -NoProfile -ExecutionPolicy Bypass -File $systemTestRunner run -Change sample -ExecutionMode standalone -ScenarioIds SMOKE-1 -EnvFile .env.local -HarnessCertificationPath $certification -StructuredResultPath $structuredDispatch 2>&1) }
    finally { $ErrorActionPreference = $oldPreference }
    $blockedSelection = Get-Content -LiteralPath $structuredDispatch -Raw | ConvertFrom-Json
    if ($blockedSelection.status -ne 'BLOCKED' -or $blockedSelection.counts.observedTests -ne 0 -or $blockedSelection.counts.failed -ne 0 -or $blockedSelection.counts.expectedMethodCount -ne 1 -or $blockedSelection.counts.reportAvailability -ne 'NOT_EXECUTED') { throw 'Precondition failure fabricated executed test counts' }

    $allPassed=$true
    Write-Output '[RESOLVED_ENVIRONMENT_RUNTIME_SELF_TEST] PASS'
    Write-Output 'cases: happy, provider readiness failure, source drift, target identity mismatch, missing consumption evidence, suite attribution, reuse ownership, redaction, interrupted recovery, prepare failure, hard timeout, external ownership, certified system-test v2 dispatch'
} finally {
    if ($allPassed -and [Environment]::GetEnvironmentVariable('FLOW_KEEP_RUNTIME_FIXTURES') -ne '1' -and (Test-Path -LiteralPath $root)) {
        Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue
    } else { Write-Output "fixtures: $root" }
}
