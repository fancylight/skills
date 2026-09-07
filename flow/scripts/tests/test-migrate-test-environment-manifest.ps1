$ErrorActionPreference = 'Stop'
$migration = Join-Path (Split-Path -Parent $PSScriptRoot) 'migrate-test-environment-manifest.ps1'
$root = Join-Path ([IO.Path]::GetTempPath()) ('flow-manifest-migration-' + [guid]::NewGuid().ToString('N'))

function Write-Json([string]$Path, $Value) {
    $parent = Split-Path -Parent $Path
    if (-not (Test-Path -LiteralPath $parent)) { [void](New-Item -ItemType Directory -Path $parent -Force) }
    [IO.File]::WriteAllText($Path, ($Value | ConvertTo-Json -Depth 16), [Text.UTF8Encoding]::new($false))
}

function New-Fixture([string]$Name) {
    $testRoot = Join-Path $root $Name
    $change = Join-Path $testRoot 'changes\sample'
    [void](New-Item -ItemType Directory -Path $change -Force)
    $legacy = [ordered]@{
        schemaVersion=1; stage='design'; defaultSuites=@('api'); testCasesContract=[ordered]@{ path='changes/sample/test-cases.yaml' }
        configuration=[ordered]@{ source='.env.local'; ownership='human'; requiredEndpoints=@('http://127.0.0.1:18888'); probes=[ordered]@{ kind='http' } }
    }
    $spec = [ordered]@{
        schemaVersion=1; environment=[ordered]@{ id='local'; descriptor='config/environments/local.json' }
        configuration=[ordered]@{ targets=@([ordered]@{ application='sample-sut'; profile='dev'; relativeFile='config/sample-sut/application-dev.yml'; endpoint='/sample-sut/dev'; sutEvidence=[ordered]@{ kind='log-pattern'; patternId='config-consumption' } }) }
        suts=@([ordered]@{ id='sample-sut'; repository='${ORCH_ROOT}/sample-sut'; revision=('a' * 40); lifecycle='managed'; startContract='config/services/sample-sut/start-system-test.ps1'; healthProbe='sut-health' })
        harness=[ordered]@{ revision=('b' * 64) }
        runner=[ordered]@{ workingDirectory='${TEST_ROOT}'; command=@('powershell.exe','-NoProfile','-File','scripts/run-suite.ps1'); failureCategory='SUT_BUSINESS' }
    }
    $legacyPath = Join-Path $change 'manifest-v1.json'
    $specPath = Join-Path $change 'migration-spec.json'
    Write-Json $legacyPath $legacy; Write-Json $specPath $spec
    return [pscustomobject]@{ root=$testRoot; legacy=$legacyPath; spec=$specPath; output=(Join-Path $change 'manifest-v2.json') }
}

function Invoke-Migration($Fixture, [string]$Output = '') {
    $target = if ([string]::IsNullOrWhiteSpace($Output)) { $Fixture.output } else { $Output }
    $lines = @(& powershell.exe -NoProfile -ExecutionPolicy Bypass -File $migration -SystemTestRepo $Fixture.root -LegacyManifestPath $Fixture.legacy -MigrationSpecPath $Fixture.spec -OutputPath $target 2>&1)
    return [pscustomobject]@{ exitCode=$LASTEXITCODE; output=($lines -join "`n"); path=$target }
}

function Assert-Error($Result, [string]$Code, [string]$Label) {
    if ($Result.exitCode -eq 0 -or $Result.output -notmatch [regex]::Escape("code: $Code")) { throw "$Label expected $Code`n$($Result.output)" }
}

try {
    $valid = New-Fixture 'valid'
    $validResult = Invoke-Migration $valid
    if ($validResult.exitCode -ne 0) { throw "valid migration failed`n$($validResult.output)" }
    $value = Get-Content -LiteralPath $valid.output -Raw -Encoding utf8 | ConvertFrom-Json
    if ([int]$value.schemaVersion -ne 2 -or [string]$value.configuration.environmentFile -ne '.env.local' -or [string]$value.environment.id -ne 'local') { throw 'migrated environment contract is incomplete' }
    if ([string]$value.testCasesContract.path -ne 'changes/sample/test-cases.yaml' -or @($value.defaultSuites).Count -ne 1) { throw 'non-environment test contract was not preserved' }
    if ($value.configuration.PSObject.Properties.Name -contains 'requiredEndpoints') { throw 'legacy configuration fields leaked into v2 output' }

    $existing = New-Fixture 'existing-output'
    Set-Content -LiteralPath $existing.output -Encoding utf8 -NoNewline -Value '{}'
    Assert-Error (Invoke-Migration $existing) 'OUTPUT_ALREADY_EXISTS' 'existing output'

    $alreadyV2 = New-Fixture 'already-v2'
    $legacyValue = Get-Content -LiteralPath $alreadyV2.legacy -Raw -Encoding utf8 | ConvertFrom-Json
    $legacyValue.schemaVersion = 2
    $legacyValue | Add-Member -NotePropertyName environment -NotePropertyValue ([ordered]@{ id='local' })
    Write-Json $alreadyV2.legacy $legacyValue
    Assert-Error (Invoke-Migration $alreadyV2) 'ALREADY_V2' 'already v2'

    $invalidSpec = New-Fixture 'invalid-spec'
    $specValue = Get-Content -LiteralPath $invalidSpec.spec -Raw -Encoding utf8 | ConvertFrom-Json
    $specValue.suts = @()
    Write-Json $invalidSpec.spec $specValue
    Assert-Error (Invoke-Migration $invalidSpec) 'INVALID_MIGRATION_SPEC' 'missing explicit SUT mapping'

    $literal = New-Fixture 'literal-sensitive'
    $specValue = Get-Content -LiteralPath $literal.spec -Raw -Encoding utf8 | ConvertFrom-Json
    $specValue.runner | Add-Member -NotePropertyName credential -NotePropertyValue 'literal-value'
    Write-Json $literal.spec $specValue
    Assert-Error (Invoke-Migration $literal) 'ERROR_SECRET_INPUT' 'literal sensitive migration value'

    $pathConflict = New-Fixture 'path-conflict'
    Assert-Error (Invoke-Migration $pathConflict (Join-Path $root 'outside.json')) 'PATH_CONFLICT' 'output path conflict'

    Write-Output '[TEST_ENVIRONMENT_MIGRATION_SELF_TEST] PASS'
    Write-Output 'cases: explicit migration, preservation, no overwrite, already-v2, missing mapping, sensitive value, path scope'
} finally {
    if (Test-Path -LiteralPath $root) { Remove-Item -LiteralPath $root -Recurse -Force }
}
