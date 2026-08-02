$ErrorActionPreference = 'Stop'
$collector = Join-Path (Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSScriptRoot))) 'flow\templates\system-test\scripts\collect-failure-evidence.ps1'
$root = Join-Path ([IO.Path]::GetTempPath()) ("flow-failure-evidence-" + [guid]::NewGuid().ToString('N'))

try {
    $change = Join-Path $root 'changes\sample'
    $reports = Join-Path $root 'backend-tests\target\surefire-reports'
    New-Item -ItemType Directory -Force -Path $change, $reports, (Join-Path $root '.runtime\sample\logs') | Out-Null
    '{"failureObservability":[{"scenarioId":"AC-1-S1","testClass":"SampleTest","testMethod":"fails","category":"TEST_HARNESS","certainty":"confirmed"}]}' |
        Set-Content -LiteralPath (Join-Path $change 'manifest.yaml') -Encoding UTF8
    '<testsuite tests="1" failures="1" errors="0" skipped="0"><testcase classname="SampleTest" name="fails"><failure message="token=hidden">boom</failure></testcase></testsuite>' |
        Set-Content -LiteralPath (Join-Path $reports 'TEST-SampleTest.xml') -Encoding UTF8
    'request completed' | Set-Content -LiteralPath (Join-Path $root '.runtime\sample\logs\service.log') -Encoding UTF8

    & powershell.exe -NoProfile -File $collector -TestRoot $root -Change sample -Status FAIL -Suites api -Message 'password=secret' -Passed 0 -Failed 1 -Skipped 0
    if ($LASTEXITCODE -ne 0) { throw 'Expected failure evidence collection to pass.' }
    $failureReport = Get-Content -LiteralPath (Join-Path $change 'evidence\current\failure-report.md') -Raw -Encoding UTF8
    if ($failureReport -notmatch 'AC-1-S1' -or $failureReport -notmatch 'TEST_HARNESS' -or $failureReport -notmatch '<redacted>') {
        throw 'Failure report did not retain mapped classification and redaction.'
    }
    if (-not (Test-Path -LiteralPath (Join-Path $change 'evidence\current\index.md'))) { throw 'Missing evidence index.' }
    Write-Output 'collect-failure-evidence generated indexed, redacted failure evidence.'
} finally {
    if (Test-Path -LiteralPath $root) { Remove-Item -LiteralPath $root -Recurse -Force }
}
