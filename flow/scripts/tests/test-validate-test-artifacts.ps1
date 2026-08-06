$ErrorActionPreference = 'Stop'
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
    & powershell.exe -NoProfile -File $guard -SystemTestRepo $work -ChangeName valid -Mode design -CanonicalRevision $revision
    if ($LASTEXITCODE -ne 0) { throw 'Expected valid fixture to pass artifact guard.' }

    New-Fixture 'invalid' $true
    & powershell.exe -NoProfile -File $guard -SystemTestRepo $work -ChangeName invalid -Mode design -CanonicalRevision $revision
    if ($LASTEXITCODE -eq 0) { throw 'Expected polluted DDL fixture to fail artifact guard.' }

    New-Fixture 'unsafe-cleanup' $false
    Set-Content -LiteralPath (Join-Path $work 'changes\unsafe-cleanup\fixtures\cleanup.sql') -Encoding utf8 -NoNewline -Value "-- fixture marker reserved by IDS`nDELETE FROM t;"
    & powershell.exe -NoProfile -File $guard -SystemTestRepo $work -ChangeName unsafe-cleanup -Mode design -CanonicalRevision $revision
    if ($LASTEXITCODE -eq 0) { throw 'Expected cleanup without WHERE to fail artifact guard.' }

    New-Fixture 'missing-authorization' $false
    Set-Content -LiteralPath (Join-Path $work 'changes\missing-authorization\manifest.yaml') -Encoding utf8 -NoNewline -Value '{"stage":"design","testCasesContract":{"path":"test-cases.generated.json"}}'
    & powershell.exe -NoProfile -File $guard -SystemTestRepo $work -ChangeName missing-authorization -Mode design -CanonicalRevision $revision
    if ($LASTEXITCODE -eq 0) { throw 'Expected manifest without testAuthorization to fail artifact guard.' }
    Write-Output 'validate-test-artifacts positive and pollution/DDL negative cases passed.'
} finally {
    if (Test-Path -LiteralPath $work) { Remove-Item -LiteralPath $work -Recurse -Force }
}
