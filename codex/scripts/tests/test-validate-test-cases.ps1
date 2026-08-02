$ErrorActionPreference = 'Stop'
$validator = Join-Path $PSScriptRoot '..\validate-test-cases.ps1'
$root = Join-Path ([IO.Path]::GetTempPath()) ('flow-test-cases-' + [guid]::NewGuid().ToString('N'))

function Assert-True([bool]$Condition, [string]$Message) {
    if (-not $Condition) { throw "ASSERT FAILED: $Message" }
}
function Invoke-Validator([hashtable]$Parameters) {
    $output = & $validator @Parameters 2>&1
    [pscustomobject]@{ Code = $LASTEXITCODE; Output = ($output -join "`n") }
}
function Assert-Pass($Result, [string]$Label) {
    Assert-True ($Result.Code -eq 0 -and $Result.Output -match '\[TEST_CASES_RESULT\] PASS') "$Label should pass: $($Result.Output)"
}
function Assert-Fail($Result, [string]$Label) {
    Assert-True ($Result.Code -ne 0 -and $Result.Output -match '\[TEST_CASES_RESULT\] ERROR') "$Label should fail: $($Result.Output)"
}
function Write-Source([string]$Path, [bool]$WithExternalEvidence = $true, [bool]$SecondScenario = $true) {
    $external = if ($WithExternalEvidence) { 'contract.pdf' } else { '' }
    $second = if ($SecondScenario) {
@"
  - id: AC-2-S1
    acceptance: AC-2
    required: true
    suite: cdc
    integration: N
    testClass: com.example.SampleIT
    testMethod: publishesContract
    reportClass: com.example.SampleReport
    filter: AC-2-S1
    evidence: [junit.xml]
    externalEvidence: [$external]
    setup: fixture-ready
    action: submit-request
    assertions: [record-created]
    cleanup: delete-fixture
    observability: [correlation-id, junit.xml]
"@
    } else { '' }
    @"
schemaVersion: 1
changeName: sample-change
sourceOfTruth: test-cases.yaml
scenarios:
  - id: AC-1-S1
    acceptance: AC-1
    required: true
    suite: api
    integration: Y
    testClass: com.example.SampleIT
    testMethod: createsRecord
    reportClass: com.example.SampleReport
    filter: AC-1-S1
    evidence: [junit.xml]
    externalEvidence: []
    setup: fixture-ready
    action: submit-request
    assertions: [record-created]
    cleanup: delete-fixture
    observability: [correlation-id, junit.xml]
$second
"@ | Set-Content -LiteralPath $Path -Encoding utf8
}

New-Item -ItemType Directory -Path $root -Force | Out-Null
try {
    $source = Join-Path $root 'test-cases.yaml'
    $previous = Join-Path $root 'previous.yaml'
    $evidence = Join-Path $root 'evidence'
    $java = Join-Path $root 'java'
    New-Item -ItemType Directory -Path $evidence, $java -Force | Out-Null
    Set-Content -LiteralPath (Join-Path $evidence 'junit.xml') -Value '<testsuite />' -Encoding utf8
    Set-Content -LiteralPath (Join-Path $evidence 'contract.pdf') -Value 'external evidence' -Encoding utf8
    Write-Source $source
    Copy-Item -LiteralPath $source -Destination $previous

    $positive = Invoke-Validator @{ TestCasesPath = $source; EvidenceRoot = $evidence }
    Assert-Pass $positive 'valid YAML source'

    $manifest1 = Join-Path $root 'manifest-1.json'
    $manifest2 = Join-Path $root 'manifest-2.json'
    Assert-Pass (Invoke-Validator @{ TestCasesPath = $source; GenerateManifestPath = $manifest1 }) 'manifest generation 1'
    Assert-Pass (Invoke-Validator @{ TestCasesPath = $source; GenerateManifestPath = $manifest2 }) 'manifest generation 2'
    Assert-True ((Get-FileHash $manifest1 -Algorithm SHA256).Hash -eq (Get-FileHash $manifest2 -Algorithm SHA256).Hash) 'manifest generation must be deterministic'
    Assert-Pass (Invoke-Validator @{ TestCasesPath = $source; ManifestPath = $manifest1 }) 'manifest consistency'

    $plan = Join-Path $root 'test-plan.md'
    Set-Content -LiteralPath $plan -Value "Human note: scenario rationale and count discussion." -Encoding utf8
    $planHash = (Get-FileHash $plan -Algorithm SHA256).Hash
    Assert-Pass (Invoke-Validator @{ TestCasesPath = $source; GenerateManifestPath = (Join-Path $root 'manifest-3.json') }) 'generation preserves human notes'
    Assert-True ((Get-FileHash $plan -Algorithm SHA256).Hash -eq $planHash) 'human notes must not be rewritten'

    $manifestDrift = Join-Path $root 'manifest-drift.json'
    (Get-Content -LiteralPath $manifest1 -Raw) -replace '"scenarioCount"\s*:\s*\d+', '"scenarioCount": 9' | Set-Content -LiteralPath $manifestDrift -Encoding utf8
    Assert-Fail (Invoke-Validator @{ TestCasesPath = $source; ManifestPath = $manifestDrift }) 'manifest count drift'

    $duplicate = Join-Path $root 'duplicate.yaml'
    (Get-Content -LiteralPath $source -Raw) -replace 'AC-2-S1', 'AC-1-S1' | Set-Content -LiteralPath $duplicate -Encoding utf8
    Assert-Fail (Invoke-Validator @{ TestCasesPath = $duplicate }) 'duplicate IDs'

    $missingId = Join-Path $root 'missing-id.yaml'
    (Get-Content -LiteralPath $source -Raw) -replace '  - id: AC-1-S1', '  - acceptance: AC-1' | Set-Content -LiteralPath $missingId -Encoding utf8
    Assert-Fail (Invoke-Validator @{ TestCasesPath = $missingId }) 'missing scenario ID'

    $missing = Join-Path $root 'missing.yaml'
    (Get-Content -LiteralPath $source -Raw) -replace '    filter: AC-1-S1\r?\n', '' | Set-Content -LiteralPath $missing -Encoding utf8
    Assert-Fail (Invoke-Validator @{ TestCasesPath = $missing }) 'missing required field'

    $noExternal = Join-Path $root 'no-external.yaml'
    (Get-Content -LiteralPath $source -Raw) -replace 'externalEvidence: \[contract.pdf\]', 'externalEvidence: []' | Set-Content -LiteralPath $noExternal -Encoding utf8
    Assert-Fail (Invoke-Validator @{ TestCasesPath = $noExternal }) 'integration-N external evidence'

    $emptyEvidence = Join-Path $root 'empty-evidence'
    New-Item -ItemType Directory -Path $emptyEvidence -Force | Out-Null
    Assert-Fail (Invoke-Validator @{ TestCasesPath = $source; EvidenceRoot = $emptyEvidence }) 'stale evidence'

    $reportDrift = Join-Path $root 'report-drift.yaml'
    (Get-Content -LiteralPath $source -Raw) -replace 'SampleReport', 'OtherReport' | Set-Content -LiteralPath $reportDrift -Encoding utf8
    Assert-Fail (Invoke-Validator @{ TestCasesPath = $reportDrift; ManifestPath = $manifest1 }) 'report class drift'

    $removed = Join-Path $root 'removed.yaml'
    Write-Source $removed -SecondScenario:$false
    Assert-Fail (Invoke-Validator @{ TestCasesPath = $removed; PreviousTestCasesPath = $previous }) 'required scenario removal'
    Assert-Pass (Invoke-Validator @{ TestCasesPath = $removed; PreviousTestCasesPath = $previous; DesignVerifyPassed = $true }) 'approved required removal'

    $javaFile = Join-Path $java 'SampleIT.java'
    @'
package com.example;
class SampleIT {
  @TestScenarioId("AC-1-S1")
  public void createsRecord() {}
  @TestScenarioId("AC-2-S1")
  public void publishesContract() {}
}
'@ | Set-Content -LiteralPath $javaFile -Encoding utf8
    Assert-Pass (Invoke-Validator @{ TestCasesPath = $source; Mode = 'implementation'; JavaSourceRoot = $java }) 'Java stable ID bindings'

    (Get-Content -LiteralPath $javaFile -Raw) -replace 'publishesContract', 'wrongMethod' | Set-Content -LiteralPath $javaFile -Encoding utf8
    Assert-Fail (Invoke-Validator @{ TestCasesPath = $source; Mode = 'implementation'; JavaSourceRoot = $java }) 'Java method drift'

    @'
package com.example;
class SampleIT {
  @TestScenarioId("AC-1-S1") public void createsRecord() {}
  @TestScenarioId("AC-2-S1") public void publishesContract() {}
  @TestScenarioId("AC-2-S1") public void duplicateBinding() {}
}
'@ | Set-Content -LiteralPath $javaFile -Encoding utf8
    Assert-Fail (Invoke-Validator @{ TestCasesPath = $source; Mode = 'implementation'; JavaSourceRoot = $java }) 'duplicate Java binding'

    @'
package com.example;
class SampleIT {
  @TestScenarioId("AC-1-S1") public void createsRecord() {}
}
'@ | Set-Content -LiteralPath $javaFile -Encoding utf8
    Assert-Fail (Invoke-Validator @{ TestCasesPath = $source; Mode = 'implementation'; JavaSourceRoot = $java }) 'unbound Java scenario'

    @'
package com.example;
class SampleIT {
  @TestScenarioId("AC-1-S1") public void createsRecord() {}
  @TestScenarioId("AC-2-S1") public void publishesContract() {}
  @TestScenarioId("AC-9-S1") public void unknownScenario() {}
}
'@ | Set-Content -LiteralPath $javaFile -Encoding utf8
    Assert-Fail (Invoke-Validator @{ TestCasesPath = $source; Mode = 'implementation'; JavaSourceRoot = $java }) 'unknown Java scenario'

    Write-Output '[TEST_VALIDATE_TEST_CASES] PASS'
}
finally {
    if (Test-Path -LiteralPath $root) { Remove-Item -LiteralPath $root -Recurse -Force }
}
