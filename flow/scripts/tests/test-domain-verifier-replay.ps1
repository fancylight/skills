$ErrorActionPreference = 'Stop'
$fixtureRoot = Join-Path $PSScriptRoot 'fixtures\domain-replay'
$cases = Get-Content -LiteralPath (Join-Path $fixtureRoot 'cases.json') -Raw -Encoding utf8 | ConvertFrom-Json
$allowed = @('PASS','ERROR')
foreach ($case in $cases) {
    $caseDir = Join-Path $fixtureRoot ([string]$case.name)
    $domainPath = Join-Path $caseDir 'domain-model.md'
    if (-not (Test-Path -LiteralPath $domainPath -PathType Leaf)) { throw "Missing domain-model fixture: $($case.name)" }
    $expectedPath = Join-Path $caseDir 'expected.json'
    if (-not (Test-Path -LiteralPath $expectedPath -PathType Leaf)) { throw "Missing expected conclusion fixture: $($case.name)" }
    $expectedFixture = Get-Content -LiteralPath $expectedPath -Raw -Encoding utf8 | ConvertFrom-Json
    $domain = Get-Content -LiteralPath $domainPath -Raw -Encoding utf8
    if ($domain -notmatch '(?i)Fact\s+DF-' -or $domain -notmatch '(?i)Decision\s+DP-') { throw "Domain replay fixture lacks Fact/Decision identifiers: $($case.name)" }
    foreach ($evidenceName in @($case.requiredEvidence)) {
        $evidencePath = Join-Path $caseDir ([string]$evidenceName)
        if (-not (Test-Path -LiteralPath $evidencePath -PathType Leaf)) { throw "Missing simulated evidence $evidenceName for $($case.name)" }
        if ([string]::IsNullOrWhiteSpace((Get-Content -LiteralPath $evidencePath -Raw -Encoding utf8))) { throw "Empty simulated evidence $evidenceName for $($case.name)" }
    }
    foreach ($id in @('DV.4','DV.5','DV.6')) {
        $expected = [string]$case.expected.$id
        if ($expected -notin $allowed) { throw "Invalid expected $id conclusion for $($case.name): $expected" }
        if ([string]$expectedFixture.$id -ne $expected) { throw "Expected conclusion index mismatch for $($case.name) $id" }
    }
    $allEvidence = ($domain + "`n" + (Get-Content -LiteralPath (Join-Path $caseDir 'schema.md') -Raw -Encoding utf8) + "`n" + (Get-Content -LiteralPath (Join-Path $caseDir 'code.md') -Raw -Encoding utf8) + "`n" + (Get-Content -LiteralPath (Join-Path $caseDir 'kb.md') -Raw -Encoding utf8))
    if ([string]$case.expected.'DV.4' -eq 'ERROR' -and $allEvidence -notmatch '(?i)contradict|conflict|discrepancy|reject') { throw "DV.4 ERROR case lacks a code/schema conflict signal: $($case.name)" }
    if ([string]$case.expected.'DV.6' -eq 'ERROR' -and $allEvidence -notmatch '(?i)conflict|unresolved|authority') { throw "DV.6 ERROR case lacks an unresolved conflict signal: $($case.name)" }
}
Write-Output '[DOMAIN_REPLAY_RESULT] PASS'
Write-Output 'semantic_verification: replay-contract-only (agent semantic review remains separate)'
