$ErrorActionPreference = 'Stop'
$validator = Join-Path $PSScriptRoot '..\validate-test-cases.ps1'
$root = Join-Path ([IO.Path]::GetTempPath()) ('flow-test-cases-' + [guid]::NewGuid().ToString('N'))
$utf8NoBom = New-Object System.Text.UTF8Encoding($false)
$revision = '1111111111111111111111111111111111111111'
$previousRevision = '2222222222222222222222222222222222222222'
$startMarker = '<!-- FLOW_TEST_CASES_GENERATED:START -->'
$endMarker = '<!-- FLOW_TEST_CASES_GENERATED:END -->'

function Assert-True([bool]$Condition, [string]$Message) { if (-not $Condition) { throw "ASSERT FAILED: $Message" } }
function Invoke-Validator([hashtable]$Parameters) {
    try {
        $output = & $validator @Parameters 2>&1
        return [pscustomobject]@{ Code=$LASTEXITCODE; Output=($output -join "`n") }
    } catch { return [pscustomobject]@{ Code=1; Output=$_.Exception.Message } }
}
function Assert-Pass($Result, [string]$Label) { Assert-True ($Result.Code -eq 0 -and $Result.Output -match '\[TEST_CASES_RESULT\] PASS') "$Label should pass: $($Result.Output)" }
function Assert-Fail($Result, [string]$Label) { Assert-True ($Result.Code -ne 0) "$Label should fail: $($Result.Output)" }
function Write-Text([string]$Path, [string]$Value) { [IO.File]::WriteAllText($Path, $Value, $utf8NoBom) }
function Get-Sha256([byte[]]$Bytes) {
    $sha = [Security.Cryptography.SHA256]::Create()
    try { return (-join ($sha.ComputeHash($Bytes) | ForEach-Object { $_.ToString('x2') })) } finally { $sha.Dispose() }
}
function Get-StringSha256([string]$Value) { return Get-Sha256 ([Text.Encoding]::UTF8.GetBytes($Value)) }
function Get-OutsideBytes([string]$Path) {
    $bytes = [IO.File]::ReadAllBytes($Path); $text = [Text.Encoding]::UTF8.GetString($bytes)
    $start = $text.IndexOf($startMarker); $end = $text.IndexOf($endMarker)
    Assert-True ($start -ge 0 -and $end -gt $start) 'plan markers must exist'
    $prefixText = $text.Substring(0, $start + $startMarker.Length); $suffixText = $text.Substring($end)
    return [Text.Encoding]::UTF8.GetBytes($prefixText + $suffixText)
}
function Get-SourceText([bool]$IncludeSecond = $true) {
    $second = if ($IncludeSecond) {
@'
  - id: AC-2-S1
    acceptance: AC-2
    required: true
    suite: cdc
    integration: N
    externalEvidence: [external/contract.json]
    setup:
      fixtures: [worker]
    action:
      method: POST
      path: /contracts
    assertions:
      response: [accepted]
      database: [event-recorded]
      sideEffects: [none-unexpected]
    cleanup: [worker]
    observability:
      correlationField: X-Test-Scenario
      allowedEvidence: [reports/ac2.xml]
'@
    } else { '' }
@"
schemaVersion: 1
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
    externalEvidence: []
    setup:
      fixtures: [project]
    action:
      method: POST
      path: /records
    assertions:
      response: [success]
      database: [row-created]
      sideEffects: [none-unexpected]
    cleanup: [project]
    observability:
      correlationField: X-Test-Scenario
      allowedEvidence: [reports/ac1.xml, logs/service.log]
$second
"@
}
function Write-Manifest([string]$Path, [bool]$Legacy = $false, [string]$Pointer = 'test-cases.generated.json') {
    $manifest = [ordered]@{
        stage='design'; testAuthorization=[ordered]@{ceiling='design';grantedBy='user'}; configurationSource='user-confirmed'
        requiredEndpoints=@('database'); connectivityProbe='SELECT 1'; ownership='environment-owner'
        requiredEnvBySuite=[ordered]@{api=@('API_URL')}; wireMockContracts=@(); fixtureSchema=[ordered]@{engine='mysql'}
        runner=[ordered]@{command=@('mvn','test')}; testCasesContract=[ordered]@{path=$Pointer}
    }
    if ($Legacy) { $manifest.requiredScenarioCount = 2 }
    Write-Text $Path ($manifest | ConvertTo-Json -Depth 12)
}
function New-State($Report, [string]$Identity, [string]$CurrentRevision) {
    $state = [pscustomobject][ordered]@{
        schemaVersion=1; phase='TEST_DESIGN_VERIFIED'; revisions=[pscustomobject][ordered]@{test=$CurrentRevision}
        verifier=[pscustomobject][ordered]@{identity=$Identity;mode='design';testRevision=$CurrentRevision;summaryHash=(Get-StringSha256 ([string]$Report.summary))}
        integrityHash=''
    }
    $state.integrityHash = Get-StateHash $state
    return $state
}
function Get-StateHash($State) {
    $prior = $State.integrityHash; $State.integrityHash = ''
    try { return Get-StringSha256 ($State | ConvertTo-Json -Depth 16 -Compress) } finally { $State.integrityHash = $prior }
}
function New-RemovalReport([string]$PreviousHash, [string]$CurrentHash, [string]$Identity) {
    $facts = [pscustomobject][ordered]@{
        currentSourceSha256=$CurrentHash; currentTestRevision=$revision; previousSourceSha256=$PreviousHash; previousTestRevision=$previousRevision
    }
    $summary = 'required-scenario-removal:' + (Get-StringSha256 ($facts | ConvertTo-Json -Depth 8 -Compress))
    return [pscustomobject][ordered]@{
        schemaVersion=1; result='PASS'; mode='design'; verifierId=$Identity; previousTestRevision=$previousRevision
        currentTestRevision=$revision; previousSourceSha256=$PreviousHash; currentSourceSha256=$CurrentHash; summary=$summary
    }
}

New-Item -ItemType Directory -Path $root -Force | Out-Null
try {
    $source = Join-Path $root 'test-cases.yaml'; Write-Text $source (Get-SourceText)
    $manifest = Join-Path $root 'manifest.yaml'; Write-Manifest $manifest
    $contract = Join-Path $root 'test-cases.generated.json'
    $plan = Join-Path $root 'test-plan.md'
    Write-Text $plan ("MANUAL PREFIX 中文`r`n$startMarker`r`nold generated content`r`n$endMarker`r`nMANUAL SUFFIX`r`n")
    $evidence = Join-Path $root 'evidence'; New-Item -ItemType Directory -Path (Join-Path $evidence 'reports'), (Join-Path $evidence 'logs'), (Join-Path $evidence 'external') -Force | Out-Null
    Write-Text (Join-Path $evidence 'reports\ac1.xml') '<testsuite />'; Write-Text (Join-Path $evidence 'reports\ac2.xml') '<testsuite />'
    Write-Text (Join-Path $evidence 'logs\service.log') 'safe log'; Write-Text (Join-Path $evidence 'external\contract.json') '{}'

    $outsideBefore = Get-OutsideBytes $plan; $manifestBefore = [IO.File]::ReadAllBytes($manifest)
    $base = @{TestCasesPath=$source;CanonicalRevision=$revision;ManifestPath=$manifest;DerivedContractPath=$contract;TestPlanPath=$plan}
    $generate = @{} + $base; $generate.Generate = $true
    Assert-Pass (Invoke-Validator $generate) 'structured source generation'
    Assert-True ([Convert]::ToBase64String((Get-OutsideBytes $plan)) -eq [Convert]::ToBase64String($outsideBefore)) 'generator must preserve plan bytes outside generated region'
    Assert-True ([Convert]::ToBase64String([IO.File]::ReadAllBytes($manifest)) -eq [Convert]::ToBase64String($manifestBefore)) 'generator must preserve the real manifest'
    $contractFirst = [IO.File]::ReadAllBytes($contract); $planFirst = [IO.File]::ReadAllBytes($plan)
    Assert-Pass (Invoke-Validator $generate) 'deterministic regeneration'
    Assert-True ([Convert]::ToBase64String([IO.File]::ReadAllBytes($contract)) -eq [Convert]::ToBase64String($contractFirst)) 'derived contract must be byte deterministic'
    Assert-True ([Convert]::ToBase64String([IO.File]::ReadAllBytes($plan)) -eq [Convert]::ToBase64String($planFirst)) 'generated plan must be byte deterministic'
    $validate = @{} + $base; $validate.EvidenceRoot = $evidence
    Assert-Pass (Invoke-Validator $validate) 'canonical source/manifest/plan/evidence validation'

    $negativeSources = [ordered]@{
        'malformed YAML' = (Get-SourceText).Replace('    action:', '    action')
        'unknown field' = (Get-SourceText).Replace('    acceptance: AC-1', "    acceptance: AC-1`n    mystery: value")
        'wrong nesting' = (Get-SourceText).Replace("    setup:`n      fixtures: [project]", '    setup: fixture-ready')
        'field type' = (Get-SourceText).Replace('    required: true', '    required: "true"')
        'invalid integration' = (Get-SourceText).Replace('    integration: Y', '    integration: MAYBE')
        'missing external evidence' = (Get-SourceText).Replace('    externalEvidence: [external/contract.json]', '    externalEvidence: []')
        'duplicate id' = (Get-SourceText).Replace('AC-2-S1', 'AC-1-S1')
    }
    foreach ($entry in $negativeSources.GetEnumerator()) {
        $path = Join-Path $root (($entry.Key -replace '[^A-Za-z]','') + '.yaml'); Write-Text $path $entry.Value
        Assert-Fail (Invoke-Validator @{TestCasesPath=$path}) $entry.Key
    }
    $emptyEvidence = Join-Path $root 'empty-evidence'; New-Item -ItemType Directory -Path $emptyEvidence | Out-Null
    Assert-Fail (Invoke-Validator (@{} + $base + @{EvidenceRoot=$emptyEvidence})) 'stale ordinary and external evidence'
    $missingExternalEvidence = Join-Path $root 'missing-external-evidence'
    New-Item -ItemType Directory -Path (Join-Path $missingExternalEvidence 'reports'), (Join-Path $missingExternalEvidence 'logs') -Force | Out-Null
    Write-Text (Join-Path $missingExternalEvidence 'reports\ac1.xml') '<testsuite />'; Write-Text (Join-Path $missingExternalEvidence 'reports\ac2.xml') '<testsuite />'
    Write-Text (Join-Path $missingExternalEvidence 'logs\service.log') 'safe log'
    Assert-Fail (Invoke-Validator (@{} + $base + @{EvidenceRoot=$missingExternalEvidence})) 'stale external evidence only'

    function Assert-ContractDrift([scriptblock]$Mutation, [string]$Label) {
        $value = Get-Content -LiteralPath $contract -Raw -Encoding utf8 | ConvertFrom-Json
        & $Mutation $value
        Write-Text $contract ($value | ConvertTo-Json -Depth 20)
        Assert-Fail (Invoke-Validator $base) $Label
        [IO.File]::WriteAllBytes($contract, $contractFirst)
    }
    Assert-ContractDrift { param($v) $v.integrationDecisions[0].integration='N' } 'manifest integration drift'
    Assert-ContractDrift { param($v) $v.requiredScenarioCount=99 } 'manifest count drift'
    Assert-ContractDrift { param($v) $v.runnerFilters[0].filter='wrong' } 'manifest filter drift'
    Assert-ContractDrift { param($v) $v.expectedReportClasses[0]='wrong.Report' } 'manifest report drift'
    Assert-ContractDrift { param($v) $v.evidenceIndex[0].allowedEvidence=@('wrong.xml') } 'manifest evidence drift'
    Assert-ContractDrift { param($v) $v.failureObservability[0].correlationField='Wrong-Field' } 'manifest failureObservability drift'

    $legacyManifest = Join-Path $root 'manifest-legacy.yaml'; Write-Manifest $legacyManifest $true
    Assert-Fail (Invoke-Validator @{TestCasesPath=$source;CanonicalRevision=$revision;ManifestPath=$legacyManifest;DerivedContractPath=$contract;TestPlanPath=$plan}) 'legacy manifest migration'
    $wrongPointer = Join-Path $root 'manifest-wrong-pointer.yaml'; Write-Manifest $wrongPointer $false 'other.json'
    Assert-Fail (Invoke-Validator @{TestCasesPath=$source;CanonicalRevision=$revision;ManifestPath=$wrongPointer;DerivedContractPath=$contract;TestPlanPath=$plan}) 'manifest pointer drift'

    Write-Text $plan ([Text.Encoding]::UTF8.GetString($planFirst).Replace('| AC-1-S1 |', '| CHANGED |'))
    Assert-Fail (Invoke-Validator $base) 'generated plan drift'
    [IO.File]::WriteAllBytes($plan, $planFirst)
    Write-Text $plan ('MODIFIED MANUAL PREFIX' + [Text.Encoding]::UTF8.GetString($planFirst))
    Assert-Fail (Invoke-Validator $base) 'generated-region outside manual note modification'
    [IO.File]::WriteAllBytes($plan, $planFirst)

    $java = Join-Path $root 'java'; New-Item -ItemType Directory -Path $java | Out-Null
    $padding = 'x' * 800
    $javaFile = Join-Path $java 'SampleIT.java'
    Write-Text $javaFile @"
package com.example;
class SampleIT {
  @TestScenarioId("AC-1-S1")
  /* $padding */
  public void createsRecord() {}
}
"@
    $implementation = @{} + $validate; $implementation.Mode='implementation'; $implementation.JavaSourceRoot=$java
    Assert-Pass (Invoke-Validator $implementation) 'Java binding beyond 500 characters'
    Write-Text $javaFile ((Get-Content -LiteralPath $javaFile -Raw).Replace('class SampleIT', 'class OtherIT'))
    Assert-Fail (Invoke-Validator $implementation) 'Java class drift';
    Write-Text $javaFile ((Get-Content -LiteralPath $javaFile -Raw).Replace('class OtherIT', 'class SampleIT').Replace('createsRecord', 'wrongMethod'))
    Assert-Fail (Invoke-Validator $implementation) 'Java method drift'
    Write-Text $javaFile 'package com.example; class SampleIT { public void helper() {} }'
    Assert-Fail (Invoke-Validator $implementation) 'missing Java binding'
    Write-Text $javaFile 'package com.example; class SampleIT { @TestScenarioId("AC-1-S1") public void createsRecord() {} @TestScenarioId("AC-1-S1") public void duplicate() {} }'
    Assert-Fail (Invoke-Validator $implementation) 'duplicate Java binding'
    Write-Text $javaFile 'package com.example; class SampleIT { @TestScenarioId("AC-1-S1") public void createsRecord() {} @TestScenarioId("AC-9-S1") public void unknown() {} }'
    Assert-Fail (Invoke-Validator $implementation) 'unknown Java binding'

    $previous = Join-Path $root 'previous.yaml'; Write-Text $previous (Get-SourceText)
    $removed = Join-Path $root 'removed.yaml'; Write-Text $removed (Get-SourceText $false)
    $previousHash = Get-Sha256 ([IO.File]::ReadAllBytes($previous)); $currentHash = Get-Sha256 ([IO.File]::ReadAllBytes($removed)); $identity='design-verifier-1'
    $report = New-RemovalReport $previousHash $currentHash $identity
    $reportPath = Join-Path $root 'design-verifier.json'; Write-Text $reportPath ($report | ConvertTo-Json -Depth 8)
    $state = New-State $report $identity $revision; $statePath = Join-Path $root 'automation-state.json'; Write-Text $statePath ($state | ConvertTo-Json -Depth 16)
    $removal = @{TestCasesPath=$removed;CanonicalRevision=$revision;PreviousTestCasesPath=$previous;PreviousTestRevision=$previousRevision;DesignVerifierReportPath=$reportPath;ControllerStatePath=$statePath;TrustedVerifierIdentity=$identity}
    Assert-Pass (Invoke-Validator $removal) 'trusted required scenario removal'
    $booleanBypass = @{} + $removal; $booleanBypass.Remove('DesignVerifierReportPath'); $booleanBypass.Remove('ControllerStatePath'); $booleanBypass.DesignVerifyPassed=$true
    Assert-Fail (Invoke-Validator $booleanBypass) 'free boolean bypass'
    $forged = $report.PSObject.Copy(); $forged.verifierId='forged-verifier'; Write-Text $reportPath ($forged | ConvertTo-Json -Depth 8)
    Assert-Fail (Invoke-Validator $removal) 'forged verifier report'
    Write-Text $reportPath ($report | ConvertTo-Json -Depth 8)
    $stale = $report.PSObject.Copy(); $stale.currentTestRevision=$previousRevision; Write-Text $reportPath ($stale | ConvertTo-Json -Depth 8)
    Assert-Fail (Invoke-Validator $removal) 'stale verifier revision'
    Write-Text $reportPath ($report | ConvertTo-Json -Depth 8)
    $wrongHash = $report.PSObject.Copy(); $wrongHash.currentSourceSha256=('f' * 64); Write-Text $reportPath ($wrongHash | ConvertTo-Json -Depth 8)
    Assert-Fail (Invoke-Validator $removal) 'verifier source hash mismatch'
    Write-Text $reportPath ($report | ConvertTo-Json -Depth 8)
    $wrongMode = $report.PSObject.Copy(); $wrongMode.mode='implementation'; Write-Text $reportPath ($wrongMode | ConvertTo-Json -Depth 8)
    Assert-Fail (Invoke-Validator $removal) 'verifier mode mismatch'
    Write-Text $reportPath ($report | ConvertTo-Json -Depth 8)
    $wrongResult = $report.PSObject.Copy(); $wrongResult.result='FAIL'; Write-Text $reportPath ($wrongResult | ConvertTo-Json -Depth 8)
    Assert-Fail (Invoke-Validator $removal) 'verifier result mismatch'

    Write-Output '[TEST_VALIDATE_TEST_CASES] PASS'
} finally {
    if (Test-Path -LiteralPath $root) { Remove-Item -LiteralPath $root -Recurse -Force }
}
