$ErrorActionPreference = 'Stop'
$scriptRoot = Split-Path -Parent $PSScriptRoot
$resolver = Join-Path $scriptRoot 'resolve-test-environment.ps1'
$root = Join-Path ([IO.Path]::GetTempPath()) ('flow-environment-resolver-' + [guid]::NewGuid().ToString('N'))

function Write-Json([string]$Path, $Value) {
    $parent = Split-Path -Parent $Path
    if (-not (Test-Path -LiteralPath $parent)) { [void](New-Item -ItemType Directory -Path $parent -Force) }
    [IO.File]::WriteAllText($Path, ($Value | ConvertTo-Json -Depth 16), [Text.UTF8Encoding]::new($false))
}

function Initialize-Git([string]$Path) {
    [void](New-Item -ItemType Directory -Path $Path -Force)
    & git -C $Path init --quiet
    & git -C $Path config user.email environment-resolver@example.invalid
    & git -C $Path config user.name environment-resolver-tests
    & git -C $Path config core.autocrlf false
}

function Commit-All([string]$Path, [string]$Message) {
    & git -C $Path add .
    & git -C $Path commit --quiet -m $Message
    if ($LASTEXITCODE -ne 0) { throw "git commit failed: $Path" }
    return (& git -C $Path rev-parse HEAD).Trim().ToLowerInvariant()
}

function New-Fixture([string]$Name) {
    $orch = Join-Path $root $Name
    $testRepo = Join-Path $orch 'system-test'
    $providerRepo = Join-Path $orch 'config-provider'
    $sutRepo = Join-Path $orch 'sample-sut'
    Initialize-Git $providerRepo
    Initialize-Git $sutRepo
    Initialize-Git $testRepo

    [void](New-Item -ItemType Directory -Path (Join-Path $providerRepo 'src\main\resources') -Force)
    [void](New-Item -ItemType Directory -Path (Join-Path $providerRepo 'config\sample-sut') -Force)
    Set-Content -LiteralPath (Join-Path $providerRepo 'pom.xml') -Encoding utf8 -NoNewline -Value '<project />'
    Set-Content -LiteralPath (Join-Path $providerRepo 'src\main\resources\application-native.yml') -Encoding utf8 -NoNewline -Value 'spring: {}'
    Set-Content -LiteralPath (Join-Path $providerRepo 'config\sample-sut\application-dev.yml') -Encoding utf8 -NoNewline -Value "spring:`n  datasource:`n    username: test_user`n    password: `${MYSQL_PASSWORD}"
    $providerRevision = Commit-All $providerRepo 'provider baseline'

    Set-Content -LiteralPath (Join-Path $sutRepo 'README.md') -Encoding utf8 -NoNewline -Value 'worker fixture'
    $sutRevision = Commit-All $sutRepo 'sut baseline'

    [void](New-Item -ItemType Directory -Path (Join-Path $testRepo 'config\environments') -Force)
    [void](New-Item -ItemType Directory -Path (Join-Path $testRepo 'config\services\sample-sut') -Force)
    [void](New-Item -ItemType Directory -Path (Join-Path $testRepo 'changes\sample') -Force)
    [void](New-Item -ItemType Directory -Path (Join-Path $testRepo 'scripts') -Force)
    Set-Content -LiteralPath (Join-Path $testRepo 'config\services\sample-sut\start-system-test.ps1') -Encoding utf8 -NoNewline -Value "Write-Output 'fixture'"
    Set-Content -LiteralPath (Join-Path $testRepo 'scripts\run-suite.ps1') -Encoding utf8 -NoNewline -Value "exit 0"

    $descriptor = [ordered]@{
        schemaVersion=1; id='local'; playbook='docs/local-integration-playbook.md'
        configurationProvider=[ordered]@{
            kind='spring-config-native'; repository='${ORCH_ROOT}/config-provider'; baseUri='http://127.0.0.1:18888'
            configRoot='config'; serviceRef='config-provider'
        }
        resources=@(
            [ordered]@{
                id='config-provider'; kind='configuration-provider'; lifecycle='managed'; executable='powershell.exe'
                arguments=@('-NoProfile','-File','scripts/start-native.ps1'); workingDirectory='${ORCH_ROOT}/config-provider'
                port=18888; readinessProbe='config-provider-health'; dependsOn=@()
            },
            [ordered]@{ id='mysql'; kind='database'; lifecycle='external'; preflightProbe='mysql-connectivity'; dependsOn=@() }
        )
        probes=@(
            [ordered]@{ id='config-provider-health'; stage='runtime'; kind='http'; method='GET'; url='http://127.0.0.1:18888/actuator/health'; expectStatus=200; failureCategory='CONFIG_INFRA' },
            [ordered]@{ id='mysql-connectivity'; stage='preflight'; kind='tcp'; hostRef='MYSQL_HOST'; portRef='MYSQL_PORT'; failureCategory='DATA_SCHEMA_CONTRACT' },
            [ordered]@{ id='sample-sut-health'; stage='runtime'; kind='http'; method='GET'; url='http://127.0.0.1:17845/actuator/health'; expectStatus=200; failureCategory='CONFIG_INFRA' }
        )
        evidenceContracts=@([ordered]@{ id='spring-config-property-source'; kind='log-regex'; pattern='CONFIG_CONSUMED\\s+sample-sut/dev' })
    }
    $descriptorPath = Join-Path $testRepo 'config\environments\local.json'
    Write-Json $descriptorPath $descriptor

    $manifest = [ordered]@{
        schemaVersion=2; stage='design'
        environment=[ordered]@{ id='local'; descriptor='config/environments/local.json' }
        configuration=[ordered]@{
            environmentFile='.env.local'; ownership='human'
            targets=@([ordered]@{
                application='sample-sut'; profile='dev'; relativeFile='config/sample-sut/application-dev.yml'; endpoint='/sample-sut/dev'
                sutEvidence=[ordered]@{ kind='log-pattern'; patternId='spring-config-property-source' }
            })
        }
        suts=@([ordered]@{
            id='sample-sut'; repository='${ORCH_ROOT}/sample-sut'; revision=$sutRevision; lifecycle='managed'
            startContract='config/services/sample-sut/start-system-test.ps1'; healthProbe='sample-sut-health'
        })
        harness=[ordered]@{ revision=('a' * 64) }
        runner=[ordered]@{ workingDirectory='${TEST_ROOT}'; command=@('powershell.exe','-NoProfile','-File','scripts/run-suite.ps1'); failureCategory='SUT_BUSINESS' }
    }
    $manifestPath = Join-Path $testRepo 'changes\sample\manifest.yaml'
    Write-Json $manifestPath $manifest
    $testRevision = Commit-All $testRepo 'test design baseline'
    return [pscustomobject]@{
        orch=$orch; testRepo=$testRepo; providerRepo=$providerRepo; sutRepo=$sutRepo; descriptor=$descriptorPath; manifest=$manifestPath
        output=(Join-Path $testRepo 'changes\sample\resolved-manifest.json'); providerRevision=$providerRevision; sutRevision=$sutRevision; testRevision=$testRevision
    }
}

function Invoke-Resolver($Fixture, [string]$Output = '') {
    $target = if ([string]::IsNullOrWhiteSpace($Output)) { $Fixture.output } else { $Output }
    $lines = @(& powershell.exe -NoProfile -ExecutionPolicy Bypass -File $resolver -OrchRoot $Fixture.orch -SystemTestRepo $Fixture.testRepo -ManifestPath $Fixture.manifest -OutputPath $target 2>&1)
    return [pscustomobject]@{ exitCode=$LASTEXITCODE; output=($lines -join "`n"); path=$target }
}

function Assert-Pass($Result, [string]$Label) {
    if ($Result.exitCode -ne 0 -or $Result.output -notmatch '\[TEST_ENVIRONMENT_RESOLVER\] PASS') { throw "$Label expected PASS`n$($Result.output)" }
}

function Assert-Error($Result, [string]$Code, [string]$Label) {
    if ($Result.exitCode -eq 0 -or $Result.output -notmatch [regex]::Escape("code: $Code")) { throw "$Label expected $Code`n$($Result.output)" }
}

try {
    $valid = New-Fixture 'valid'
    $first = Invoke-Resolver $valid
    Assert-Pass $first 'valid fixture'
    $secondPath = Join-Path $valid.testRepo 'changes\sample\resolved-manifest-second.json'
    $second = Invoke-Resolver $valid $secondPath
    Assert-Pass $second 'deterministic fixture'
    $firstValue = Get-Content -LiteralPath $first.path -Raw -Encoding utf8 | ConvertFrom-Json
    $secondValue = Get-Content -LiteralPath $second.path -Raw -Encoding utf8 | ConvertFrom-Json
    if ($firstValue.configurationFingerprint -ne $secondValue.configurationFingerprint) { throw 'same inputs produced different configuration fingerprints' }
    if (@($firstValue.cleanupPlan) -contains 'mysql') { throw 'external resource leaked into cleanup plan' }
    if (@($firstValue.cleanupPlan) -notcontains 'config-provider') { throw 'managed resource is missing from cleanup plan' }

    $nativeStartup = New-Fixture 'native-startup-contract'
    Remove-Item -LiteralPath (Join-Path $nativeStartup.providerRepo 'src/main/resources/application-native.yml') -Force
    [void](Commit-All $nativeStartup.providerRepo 'native configuration supplied at startup')
    Assert-Pass (Invoke-Resolver $nativeStartup) 'native startup without a source profile file'

    $gitBackend = New-Fixture 'git-backend'
    $configurationRepo = Join-Path $gitBackend.orch 'configuration-content'
    Initialize-Git $configurationRepo
    [void](New-Item -ItemType Directory -Path (Join-Path $configurationRepo 'test') -Force)
    Set-Content -LiteralPath (Join-Path $configurationRepo 'test\sample-sut-dev.yml') -Encoding utf8 -NoNewline -Value 'feature: enabled'
    $configurationRevision = Commit-All $configurationRepo 'configuration baseline'
    $descriptor = Get-Content -LiteralPath $gitBackend.descriptor -Raw -Encoding utf8 | ConvertFrom-Json
    $descriptor.configurationProvider.kind = 'spring-config-git'
    $descriptor.configurationProvider | Add-Member -NotePropertyName configurationRepository -NotePropertyValue '${ORCH_ROOT}/configuration-content'
    $descriptor.configurationProvider.configRoot = 'test'
    Write-Json $gitBackend.descriptor $descriptor
    $manifest = Get-Content -LiteralPath $gitBackend.manifest -Raw -Encoding utf8 | ConvertFrom-Json
    $manifest.configuration.targets[0].relativeFile = 'test/sample-sut-dev.yml'
    Write-Json $gitBackend.manifest $manifest
    $gitBackendResult = Invoke-Resolver $gitBackend
    Assert-Pass $gitBackendResult 'spring-config-git fixture'
    $gitBackendResolved = Get-Content -LiteralPath $gitBackendResult.path -Raw -Encoding utf8 | ConvertFrom-Json
    if ([string]$gitBackendResolved.configuration.provider.configurationRevision -ne $configurationRevision) { throw 'configuration content revision was not locked independently' }

    $missingDescriptor = New-Fixture 'missing-descriptor'
    $manifest = Get-Content -LiteralPath $missingDescriptor.manifest -Raw -Encoding utf8 | ConvertFrom-Json
    $manifest.environment.descriptor = 'config/environments/missing.json'
    Write-Json $missingDescriptor.manifest $manifest
    Assert-Error (Invoke-Resolver $missingDescriptor) 'MISSING_ENVIRONMENT_DESCRIPTOR' 'missing descriptor'

    $missingProvider = New-Fixture 'missing-provider'
    $descriptor = Get-Content -LiteralPath $missingProvider.descriptor -Raw -Encoding utf8 | ConvertFrom-Json
    $descriptor.configurationProvider.repository = '${ORCH_ROOT}/absent-config-provider'
    Write-Json $missingProvider.descriptor $descriptor
    Assert-Error (Invoke-Resolver $missingProvider) 'MISSING_PROVIDER_REPOSITORY' 'missing provider'

    $targetMismatch = New-Fixture 'target-mismatch'
    $manifest = Get-Content -LiteralPath $targetMismatch.manifest -Raw -Encoding utf8 | ConvertFrom-Json
    $manifest.configuration.targets[0].endpoint = '/wrong/dev'
    Write-Json $targetMismatch.manifest $manifest
    Assert-Error (Invoke-Resolver $targetMismatch) 'CONFIG_TARGET_MISMATCH' 'target mismatch'

    $pathConflict = New-Fixture 'path-conflict'
    $manifest = Get-Content -LiteralPath $pathConflict.manifest -Raw -Encoding utf8 | ConvertFrom-Json
    $manifest.environment.descriptor = '../outside.json'
    Write-Json $pathConflict.manifest $manifest
    Assert-Error (Invoke-Resolver $pathConflict) 'PATH_CONFLICT' 'descriptor path conflict'

    $cycle = New-Fixture 'cycle'
    $descriptor = Get-Content -LiteralPath $cycle.descriptor -Raw -Encoding utf8 | ConvertFrom-Json
    $descriptor.resources[0].dependsOn = @('mysql')
    $descriptor.resources[1].dependsOn = @('config-provider')
    Write-Json $cycle.descriptor $descriptor
    Assert-Error (Invoke-Resolver $cycle) 'RESOURCE_DEPENDENCY_CYCLE' 'resource cycle'

    $invalidManaged = New-Fixture 'invalid-managed'
    $descriptor = Get-Content -LiteralPath $invalidManaged.descriptor -Raw -Encoding utf8 | ConvertFrom-Json
    $descriptor.resources[0].arguments = $null
    Write-Json $invalidManaged.descriptor $descriptor
    Assert-Error (Invoke-Resolver $invalidManaged) 'INVALID_RESOURCE' 'managed resource contract'

    $freeTextProbe = New-Fixture 'free-text-probe'
    $descriptor = Get-Content -LiteralPath $freeTextProbe.descriptor -Raw -Encoding utf8 | ConvertFrom-Json
    $descriptor.probes[0] | Add-Member -NotePropertyName command -NotePropertyValue 'curl health'
    Write-Json $freeTextProbe.descriptor $descriptor
    Assert-Error (Invoke-Resolver $freeTextProbe) 'INVALID_PROBE' 'free-text probe'

    $secret = New-Fixture 'secret'
    Set-Content -LiteralPath (Join-Path $secret.providerRepo 'config\sample-sut\application-dev.yml') -Encoding utf8 -NoNewline -Value "spring:`n  datasource:`n    password: literal-secret"
    Assert-Error (Invoke-Resolver $secret) 'ERROR_SECRET_INPUT' 'literal secret'

    $camelCaseSecret = New-Fixture 'camel-case-secret'
    Set-Content -LiteralPath (Join-Path $camelCaseSecret.providerRepo 'config\sample-sut\application-dev.yml') -Encoding utf8 -NoNewline -Value "integration:`n  appSecret: literal-value`n  secret-key: literal-value"
    Assert-Error (Invoke-Resolver $camelCaseSecret) 'ERROR_SECRET_INPUT' 'camelCase and kebab secret keys'

    $drift = New-Fixture 'revision-drift'
    $manifest = Get-Content -LiteralPath $drift.manifest -Raw -Encoding utf8 | ConvertFrom-Json
    $manifest.suts[0].revision = ('b' * 40)
    Write-Json $drift.manifest $manifest
    Assert-Error (Invoke-Resolver $drift) 'ERROR_REVISION_DRIFT' 'SUT revision drift'

    $legacy = New-Fixture 'legacy-field'
    $manifest = Get-Content -LiteralPath $legacy.manifest -Raw -Encoding utf8 | ConvertFrom-Json
    $manifest | Add-Member -NotePropertyName configurationSource -NotePropertyValue '.env.local'
    Write-Json $legacy.manifest $manifest
    Assert-Error (Invoke-Resolver $legacy) 'AMBIGUOUS_CONFIGURATION_SCHEMA' 'legacy field'

    $environmentPath = New-Fixture 'environment-path'
    $manifest = Get-Content -LiteralPath $environmentPath.manifest -Raw -Encoding utf8 | ConvertFrom-Json
    $manifest.configuration.environmentFile = '../outside.env'
    Write-Json $environmentPath.manifest $manifest
    Assert-Error (Invoke-Resolver $environmentPath) 'PATH_CONFLICT' 'environment file path conflict'

    $missingEvidence = New-Fixture 'missing-evidence-contract'
    $descriptor = Get-Content -LiteralPath $missingEvidence.descriptor -Raw -Encoding utf8 | ConvertFrom-Json
    $descriptor.evidenceContracts = @()
    Write-Json $missingEvidence.descriptor $descriptor
    Assert-Error (Invoke-Resolver $missingEvidence) 'INVALID_EVIDENCE_CONTRACT' 'missing evidence contract'

    $invalidRunner = New-Fixture 'invalid-runner'
    $manifest = Get-Content -LiteralPath $invalidRunner.manifest -Raw -Encoding utf8 | ConvertFrom-Json
    $manifest.runner.command = 'powershell.exe -File scripts/run-suite.ps1'
    Write-Json $invalidRunner.manifest $manifest
    Assert-Error (Invoke-Resolver $invalidRunner) 'INVALID_TEST_RUNNER' 'free-text runner command'

    Write-Output '[TEST_ENVIRONMENT_RESOLVER_SELF_TEST] PASS'
    Write-Output 'cases: valid, deterministic, spring-config-git, missing descriptor/provider, target mismatch, path conflict, cycle, managed contract, probe schema, secret variants, revision drift, legacy ambiguity, environment path, evidence contract, runner command'
} finally {
    if (Test-Path -LiteralPath $root) { Remove-Item -LiteralPath $root -Recurse -Force }
}
