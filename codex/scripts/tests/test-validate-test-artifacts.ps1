$ErrorActionPreference = 'Stop'
$scriptRoot = Split-Path -Parent $PSScriptRoot
$guard = Join-Path $scriptRoot 'validate-test-artifacts.ps1'
$work = Join-Path ([IO.Path]::GetTempPath()) ("flow-artifact-guard-" + [guid]::NewGuid().ToString('N'))

function New-Fixture([string]$Name, [bool]$Invalid) {
    $change = Join-Path $work "changes\$Name"
    $fixtures = Join-Path $change 'fixtures'
    New-Item -ItemType Directory -Force -Path $fixtures | Out-Null
    Set-Content -LiteralPath (Join-Path $change 'test-design.md') -Encoding utf8 -NoNewline -Value "# Test design`n`nPlanned polling timeout is 60 seconds with a 500 ms interval; these are design parameters."
    Set-Content -LiteralPath (Join-Path $change 'test-plan.md') -Encoding utf8 -NoNewline -Value ("> system-test path: $work")
    Set-Content -LiteralPath (Join-Path $change 'manifest.yaml') -Encoding utf8 -NoNewline -Value '{"stage":"design","testAuthorization":{"ceiling":"design","grantedBy":"user"},"configurationSource":"user-confirmed","requiredEndpoints":["database"],"connectivityProbe":"SELECT 1","ownership":"environment-owner","failureObservability":[],"apiTestFilter":"ExampleTest"}'
    Set-Content -LiteralPath (Join-Path $fixtures 'ids.yaml') -Encoding utf8 -NoNewline -Value 'fixture_marker: FLOW_TEST_1'
    Set-Content -LiteralPath (Join-Path $fixtures 'seed.sql') -Encoding utf8 -NoNewline -Value "INSERT INTO t (marker) VALUES ('FLOW_TEST_1');"
    $cleanup = "-- fixture marker reserved by IDS`nDELETE FROM t WHERE marker = 'FLOW_TEST_1';"
    if ($Invalid) { $cleanup += "`nExit code: 0`nCREATE TABLE accidental (id INT);" }
    Set-Content -LiteralPath (Join-Path $fixtures 'cleanup.sql') -Encoding utf8 -NoNewline -Value $cleanup
}

try {
    New-Fixture 'valid' $false
    & powershell.exe -NoProfile -File $guard -SystemTestRepo $work -ChangeName valid -Mode design
    if ($LASTEXITCODE -ne 0) { throw 'Expected valid fixture to pass artifact guard.' }

    New-Fixture 'invalid' $true
    & powershell.exe -NoProfile -File $guard -SystemTestRepo $work -ChangeName invalid -Mode design
    if ($LASTEXITCODE -eq 0) { throw 'Expected polluted DDL fixture to fail artifact guard.' }

    New-Fixture 'unsafe-cleanup' $false
    Set-Content -LiteralPath (Join-Path $work 'changes\unsafe-cleanup\fixtures\cleanup.sql') -Encoding utf8 -NoNewline -Value "-- fixture marker reserved by IDS`nDELETE FROM t;"
    & powershell.exe -NoProfile -File $guard -SystemTestRepo $work -ChangeName unsafe-cleanup -Mode design
    if ($LASTEXITCODE -eq 0) { throw 'Expected cleanup without WHERE to fail artifact guard.' }

    New-Fixture 'missing-authorization' $false
    Set-Content -LiteralPath (Join-Path $work 'changes\missing-authorization\manifest.yaml') -Encoding utf8 -NoNewline -Value '{"stage":"design","apiTestFilter":"ExampleTest"}'
    & powershell.exe -NoProfile -File $guard -SystemTestRepo $work -ChangeName missing-authorization -Mode design
    if ($LASTEXITCODE -eq 0) { throw 'Expected manifest without testAuthorization to fail artifact guard.' }
    Write-Output 'validate-test-artifacts positive and pollution/DDL negative cases passed.'
} finally {
    if (Test-Path -LiteralPath $work) { Remove-Item -LiteralPath $work -Recurse -Force }
}
