$ErrorActionPreference = 'Stop'
$powershellExecutable = (Get-Process -Id $PID).Path
$scriptRoot = Split-Path -Parent $PSScriptRoot
$guard = Join-Path $scriptRoot 'validate-test-artifacts.ps1'
$testCasesValidator = Join-Path $scriptRoot 'validate-test-cases.ps1'
$work = Join-Path ([IO.Path]::GetTempPath()) ("flow-artifact-guard-" + [guid]::NewGuid().ToString('N'))
$revision = '1111111111111111111111111111111111111111'

function New-Fixture([string]$Name, [bool]$Invalid) {
    $change = Join-Path $work "changes\$Name"
    $fixtures = Join-Path $change 'fixtures'
    New-Item -ItemType Directory -Force -Path $fixtures | Out-Null
    Set-Content -LiteralPath (Join-Path $change 'test-design.md') -Encoding utf8 -NoNewline -Value "# Test design`n`nPlanned polling timeout is 60 seconds with a 500 ms interval; these are design parameters."
    Set-Content -LiteralPath (Join-Path $change 'test-plan.md') -Encoding utf8 -NoNewline -Value ("> system-test path: $work`n<!-- FLOW_TEST_CASES_GENERATED:START -->`n<!-- generated -->`n<!-- FLOW_TEST_CASES_GENERATED:END -->`nmanual notes")
    Set-Content -LiteralPath (Join-Path $change 'manifest.yaml') -Encoding utf8 -NoNewline -Value '{"stage":"design","testAuthorization":{"ceiling":"design","grantedBy":"user"},"configurationSource":"user-confirmed","requiredEndpoints":["database"],"connectivityProbe":"SELECT 1","ownership":"environment-owner","requiredEnvBySuite":{"api":["API_URL"]},"wireMockContracts":[],"fixtureSchema":{"engine":"mysql"},"runner":{"command":["mvn","test"]},"testCasesContract":{"path":"test-cases.generated.json"}}'
    Set-Content -LiteralPath (Join-Path $change 'test-cases.yaml') -Encoding utf8 -NoNewline -Value @'
schemaVersion: 1
scenarios:
  - id: AC-1-S1
    acceptance: AC-1
    required: true
    suite: api
    integration: Y
    business:
      purpose: 创建记录后按规则保存数量
      preconditions: 数量必须大于0且每次请求只创建一行
      inputs: 数量7，标识fixture
      steps: 提交创建请求后查询该标识并核对记录数
      expected: 恰好一行且数量7，无额外副作用
      oracle: 需求AC-1指定数量原样保存；预期直接来自输入7
      counterexamples: 数量0应拒绝且没有新增行
      evidenceBoundary: Y验证请求到持久化；其他依赖不在本例范围
    testClass: com.example.ExampleIT
    testMethod: executesScenario
    reportClass: com.example.ExampleReport
    filter: AC-1-S1
    externalEvidence: []
    setup:
      fixtures: [fixture]
    action:
      method: POST
      path: /example
    assertions:
      response: [success]
      database: [row-created]
      sideEffects: [none-unexpected]
    cleanup: [fixture]
    observability:
      correlationField: X-Test-Scenario
      allowedEvidence: [reports/example.xml]
'@
    & $testCasesValidator -TestCasesPath (Join-Path $change 'test-cases.yaml') -CanonicalRevision $revision -ManifestPath (Join-Path $change 'manifest.yaml') -DerivedContractPath (Join-Path $change 'test-cases.generated.json') -TestPlanPath (Join-Path $change 'test-plan.md') -Generate | Out-Null
    if ($LASTEXITCODE -ne 0) { throw "Failed to generate canonical test-cases fixture: $Name" }
    Set-Content -LiteralPath (Join-Path $fixtures 'ids.yaml') -Encoding utf8 -NoNewline -Value 'fixture_marker: FLOW_TEST_1'
    Set-Content -LiteralPath (Join-Path $fixtures 'seed.sql') -Encoding utf8 -NoNewline -Value "INSERT INTO t (marker) VALUES ('FLOW_TEST_1');"
    $cleanup = "-- fixture marker reserved by IDS`nDELETE FROM t WHERE marker = 'FLOW_TEST_1';"
    if ($Invalid) { $cleanup += "`nExit code: 0`nCREATE TABLE accidental (id INT);" }
    Set-Content -LiteralPath (Join-Path $fixtures 'cleanup.sql') -Encoding utf8 -NoNewline -Value $cleanup
}

try {
    New-Fixture 'valid' $false
    & $powershellExecutable -NoProfile -File $guard -SystemTestRepo $work -ChangeName valid -Mode design -CanonicalRevision $revision
    if ($LASTEXITCODE -ne 0) { throw 'Expected valid fixture to pass artifact guard.' }

    # Design stage and user ceiling are independent; pure technical mapping is not complete design.
    foreach ($ceiling in @('implementation','execution','result')) {
        New-Fixture "initial-$ceiling" $false
        $authManifest = Join-Path $work "changes/initial-$ceiling/manifest.yaml"
        (Get-Content $authManifest -Raw -Encoding utf8).Replace('"ceiling":"design"', ('"ceiling":"' + $ceiling + '"')) | Set-Content $authManifest -Encoding utf8
        & $powershellExecutable -NoProfile -File $guard -SystemTestRepo $work -ChangeName "initial-$ceiling" -Mode design -CanonicalRevision $revision
        if ($LASTEXITCODE -ne 0) { throw "Design with initial $ceiling authorization must pass." }
    }
    New-Fixture 'technical-only' $false
    $techDir = Join-Path $work 'changes/technical-only'
    $techSource = Join-Path $techDir 'test-cases.yaml'
    [regex]::Replace((Get-Content $techSource -Raw -Encoding utf8), '(?ms)^    business:.*?(?=^    testClass:)', '') | Set-Content $techSource -Encoding utf8
    & $testCasesValidator -TestCasesPath $techSource -CanonicalRevision $revision -ManifestPath (Join-Path $techDir 'manifest.yaml') -DerivedContractPath (Join-Path $techDir 'test-cases.generated.json') -TestPlanPath (Join-Path $techDir 'test-plan.md') -Generate | Out-Null
    if ($LASTEXITCODE -ne 0) { throw 'Legacy technical source must still parse.' }
    & $powershellExecutable -NoProfile -File $guard -SystemTestRepo $work -ChangeName technical-only -Mode design -CanonicalRevision $revision
    if ($LASTEXITCODE -eq 0) { throw 'Pure technical mapping must not pass formal design.' }

    New-Fixture 'valid-v2' $false
    $v2ManifestPath = Join-Path $work 'changes/valid-v2/manifest.yaml'
    $v2 = [ordered]@{schemaVersion=2;stage='design';testAuthorization=@{ceiling='design';grantedBy='user'};testCasesContract=@{path='test-cases.generated.json'};environment=@{id='local';descriptor='config/environments/local.json'};configuration=@{ownership='human';targets=@(@{application='sample';profile='dev'})};suts=@(@{id='sample'});harness=@{revision='fixture'};runner=@{command=@('mvn','test')}}
    $v2 | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $v2ManifestPath -Encoding utf8
    $v2ResolvedPath = Join-Path $work 'changes/valid-v2/resolved-manifest.json'
    @{sourceManifestSchemaVersion=2;inputs=@{manifest=@{sha256=(Get-FileHash -LiteralPath $v2ManifestPath).Hash.ToLowerInvariant()}}} | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $v2ResolvedPath -Encoding utf8
    & $powershellExecutable -NoProfile -File $guard -SystemTestRepo $work -ChangeName valid-v2 -Mode design -CanonicalRevision $revision
    if ($LASTEXITCODE -ne 0) { throw 'Expected v2 fixture without legacy configuration fields to pass.' }
    @{sourceManifestSchemaVersion=2;inputs=@{manifest=@{sha256='drifted'}}} | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $v2ResolvedPath -Encoding utf8
    & $powershellExecutable -NoProfile -File $guard -SystemTestRepo $work -ChangeName valid-v2 -Mode design -CanonicalRevision $revision
    if ($LASTEXITCODE -eq 0) { throw 'Expected resolved v2 input drift to fail.' }

    $validJava = Join-Path $work 'backend-tests\src\test\java\com\example\valid'
    New-Item -ItemType Directory -Force -Path $validJava | Out-Null
    Set-Content -LiteralPath (Join-Path $validJava 'ExampleIT.java') -Encoding utf8 -NoNewline -Value @'
package com.example;
class ExampleIT {
    @TestScenarioId("AC-1-S1")
    void executesScenario() {}
}
'@
    $unrelatedJava = Join-Path $work 'backend-tests\src\test\java\com\example\other-change'
    New-Item -ItemType Directory -Force -Path $unrelatedJava | Out-Null
    Set-Content -LiteralPath (Join-Path $unrelatedJava 'OtherIT.java') -Encoding utf8 -NoNewline -Value @'
package com.example;
class OtherIT {
    @TestScenarioId("AC-1-S1")
    void duplicateFromAnotherChange() {}
    @TestScenarioId("AC-99-S1")
    void unrelatedScenario() {}
}
'@
    & $powershellExecutable -NoProfile -File $guard -SystemTestRepo $work -ChangeName valid -Mode implementation -CanonicalRevision $revision
    if ($LASTEXITCODE -ne 0) { throw 'Expected implementation guard to scan only the change-scoped Java source directory.' }

    New-Fixture 'invalid' $true
    & $powershellExecutable -NoProfile -File $guard -SystemTestRepo $work -ChangeName invalid -Mode design -CanonicalRevision $revision
    if ($LASTEXITCODE -eq 0) { throw 'Expected polluted DDL fixture to fail artifact guard.' }

    New-Fixture 'unsafe-cleanup' $false
    Set-Content -LiteralPath (Join-Path $work 'changes\unsafe-cleanup\fixtures\cleanup.sql') -Encoding utf8 -NoNewline -Value "-- fixture marker reserved by IDS`nDELETE FROM t;"
    & $powershellExecutable -NoProfile -File $guard -SystemTestRepo $work -ChangeName unsafe-cleanup -Mode design -CanonicalRevision $revision
    if ($LASTEXITCODE -eq 0) { throw 'Expected cleanup without WHERE to fail artifact guard.' }

    New-Fixture 'missing-authorization' $false
    Set-Content -LiteralPath (Join-Path $work 'changes\missing-authorization\manifest.yaml') -Encoding utf8 -NoNewline -Value '{"stage":"design","testCasesContract":{"path":"test-cases.generated.json"}}'
    & $powershellExecutable -NoProfile -File $guard -SystemTestRepo $work -ChangeName missing-authorization -Mode design -CanonicalRevision $revision
    if ($LASTEXITCODE -eq 0) { throw 'Expected manifest without testAuthorization to fail artifact guard.' }
    Write-Output 'validate-test-artifacts positive and pollution/DDL negative cases passed.'
} finally {
    if (Test-Path -LiteralPath $work) { Remove-Item -LiteralPath $work -Recurse -Force }
}
