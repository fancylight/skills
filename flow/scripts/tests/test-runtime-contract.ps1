$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot '../../templates/system-test/scripts/test-runtime-contract.ps1')
$root = Join-Path ([IO.Path]::GetTempPath()) ('flow-runtime-contract-' + [guid]::NewGuid().ToString('N'))
[void](New-Item -ItemType Directory -Path $root)
function Assert-Reject([scriptblock]$Action, [string]$Code) {
    try { & $Action | Out-Null } catch { if ($_.Exception.Message -like "*$Code*") { return }; throw }
    throw "Expected rejection: $Code"
}
try {
    & git -C $root init --quiet
    Set-Content -LiteralPath (Join-Path $root '.gitignore') -Value 'application-dev.yml'
    $target = Join-Path $root 'application-dev.yml'
    $sensitive = 'local-test-secret-92371'
    Set-Content -LiteralPath $target -Value "password: $sensitive"
    $hash = Get-TestConfigurationContentHash $target human $root
    Assert-Reject { Get-TestConfigurationContentHash $target harness $root } 'ERROR_SECRET_INPUT'
    Set-Content -LiteralPath $target -Value 'password: changed-local-test-secret'
    if ((Get-TestConfigurationContentHash $target human $root) -eq $hash) { throw 'Local credential mutation did not invalidate the fingerprint' }
    if ((Protect-TestRuntimeText "test emitted $sensitive" @($sensitive)).Contains($sensitive)) { throw 'Literal input leaked' }
    $source = Join-Path $root 'test-cases.yaml'
    Set-Content -LiteralPath $source -Value 'scenarios: [SMOKE-1, FULL-1]'
    $sidecar = [ordered]@{
        kind='flow-test-cases-derived'; source=@{ path='test-cases.yaml'; sha256=(Get-FileHash $source).Hash.ToLowerInvariant() }
        runnerFilters=@(@{ id='SMOKE-1'; filter='example.SmokeTest#complete' }, @{ id='FULL-1'; filter='example.FullTest#complete' })
        failureObservability=@(@{ id='SMOKE-1'; testClass='example.SmokeTest'; testMethod='complete' }, @{ id='FULL-1'; testClass='example.FullTest'; testMethod='complete' })
    }
    $sidecar | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $root 'derived.json')
    Assert-Reject { Get-TestScenarioSelection $root 'derived.json' @() } 'SCENARIO_SELECTION_EMPTY'
    Assert-Reject { Get-TestScenarioSelection $root 'derived.json' @('UNKNOWN') } 'SCENARIO_SELECTION_UNKNOWN'
    Assert-Reject { Get-TestScenarioSelection $root 'derived.json' @('SMOKE-1','SMOKE-1') } 'SCENARIO_SELECTION_DUPLICATE'
    $selection = Get-TestScenarioSelection $root 'derived.json' @('SMOKE-1')
    if ($selection.fullSuite -or $selection.filter -ne 'example.SmokeTest#complete' -or $selection.expectedMethodCount -ne 1) { throw 'Selection escaped canonical scope' }
    Assert-Reject { Get-SelectedTestResults $selection $root } 'SCENARIO_REPORT_MISSING'
    $report = Join-Path $root 'TEST-example.SmokeTest.xml'
    Set-Content -LiteralPath $report -Value '<testsuite />'
    Assert-Reject { Get-SelectedTestResults $selection $root } 'SCENARIO_ZERO_MATCH'
    Set-Content -LiteralPath $report -Value '<testsuite><testcase classname="example.SmokeTest" name="wrong" /></testsuite>'
    Assert-Reject { Get-SelectedTestResults $selection $root } 'SCENARIO_REPORT_OUTSIDE_SELECTION'
    Set-Content -LiteralPath $report -Value '<testsuite><testcase classname="example.SmokeTest" name="complete"><skipped /></testcase></testsuite>'
    Assert-Reject { Get-SelectedTestResults $selection $root } 'SCENARIO_NOT_PASSED'
    $nonPassing = Get-SelectedTestResults $selection $root -AllowNonPassing
    if ($nonPassing.skipped -ne 1 -or $nonPassing.passed -ne 0) { throw 'Non-passing report counts were lost' }
    Set-Content -LiteralPath $report -Value '<testsuite><testcase classname="example.SmokeTest" name="complete" /></testsuite>'
    $result = Get-SelectedTestResults $selection $root
    if ($result.passed -ne 1 -or $result.fullSuite) { throw 'Incorrect partial result' }
    Add-Content -LiteralPath $source -Value '# changed'
    Assert-Reject { Get-TestScenarioSelection $root 'derived.json' @('SMOKE-1') } 'SCENARIO_SELECTION_SOURCE_DRIFT'
    Write-Output '[TEST_RUNTIME_CONTRACT_SELF_TEST] PASS'
} finally {
    $safeRoot = [IO.Path]::GetFullPath($root)
    if (-not $safeRoot.StartsWith([IO.Path]::GetFullPath([IO.Path]::GetTempPath()), [StringComparison]::OrdinalIgnoreCase) -or (Split-Path -Leaf $safeRoot) -notlike 'flow-runtime-contract-*') { throw 'Unsafe cleanup path' }
    Remove-Item -LiteralPath $safeRoot -Recurse -Force
}
