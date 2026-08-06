$ErrorActionPreference = 'Stop'
$scriptRoot = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
$validator = Join-Path $scriptRoot 'validate-domain-artifact.ps1'
$fixtureRoot = Join-Path $PSScriptRoot 'fixtures\domain-artifact'
$validPath = Join-Path $fixtureRoot 'valid.md'
$renderedTemplatePath = Join-Path $fixtureRoot 'rendered-template.md'

function New-UtfString([int[]]$CodePoints) { return -join ($CodePoints | ForEach-Object { [char]$_ }) }
function Assert-Result([string]$Name, [string]$Content, [bool]$ExpectedPass, [string]$ExpectedMarker) {
    $path = Join-Path $TestDrive "$Name.md"
    Set-Content -LiteralPath $path -Value $Content -Encoding utf8
    $output = & $validator -DomainModelPath $path 2>&1
    $passed = @($output | Where-Object { $_ -eq '[DOMAIN_ARTIFACT_RESULT] PASS' }).Count -eq 1
    if ($passed -ne $ExpectedPass -or (@($output | Where-Object { $_ -match [regex]::Escape($ExpectedMarker) }).Count -eq 0)) {
        throw "Unexpected result for ${Name}: $($output -join [Environment]::NewLine)"
    }
}

$TestDrive = Join-Path ([IO.Path]::GetTempPath()) ("domain-artifact-" + [guid]::NewGuid())
New-Item -ItemType Directory -Path $TestDrive | Out-Null
try {
    $valid = Get-Content -LiteralPath $validPath -Raw -Encoding utf8
    Assert-Result 'valid' $valid $true 'DOMAIN_ARTIFACT_RESULT] PASS'
    Assert-Result 'rendered-template' (Get-Content -LiteralPath $renderedTemplatePath -Raw -Encoding utf8) $true 'DOMAIN_ARTIFACT_RESULT] PASS'
    Assert-Result 'java-generics' ($valid.Replace('non-empty string', 'List<T>')) $true 'DOMAIN_ARTIFACT_RESULT] PASS'
    $fence = -join (1..3 | ForEach-Object { [char]96 })
    Assert-Result 'code-example-is-not-data' ($valid + "`n${fence}markdown`n| TODO | TBD | unknown |`n${fence}") $true 'DOMAIN_ARTIFACT_RESULT] PASS'
    Assert-Result 'second-row-todo' ($valid.Replace('| Record | belongs to account | no cross-account merge | DP-001 |', "| Record | belongs to account | no cross-account merge | DP-001 |`n| TODO | TBD | unknown | DP-001 |")) $false 'DV.2'
    Assert-Result 'missing-section' ($valid.Replace("## $(New-UtfString @(29366,24577,19982,36716,25442))", '## removed-section')) $false 'DV.1'
    Assert-Result 'placeholder' ($valid.Replace('complete identity', 'TODO')) $false 'DV.2'
    Assert-Result 'fact-to-decision' ($valid.Replace('EV-001 | DP-001', 'EV-001 | DP-999')) $false 'DV.1'
    Assert-Result 'decision-to-fact' ($valid.Replace('| DF-001 | Incorrect aggregation', '| DF-999 | Incorrect aggregation')) $false 'DV.1'
    $twoDecisions = $valid.Replace('| DP-001 | Choose aggregation key | DF-001 | Incorrect aggregation | resolved |', "| DP-001 | Choose aggregation key | DF-001 | Incorrect aggregation | resolved |`n| DP-002 | Secondary decision | DF-001 | Requires the same fact | resolved |")
    Assert-Result 'both-existing-fact-decision-mismatch' ($twoDecisions.Replace('EV-001 | DP-001', 'EV-001 | DP-002')) $false 'DV.1'
    Assert-Result 'both-existing-decision-fact-mismatch' $twoDecisions $false 'DV.1'
    Assert-Result 'direct-evidence' ($valid.Replace('EV-001 | DP-001', 'E2: source | DP-001')) $false 'DV.3'
    Assert-Result 'unknown-evidence' ($valid.Replace('EV-001 | DP-001', 'EV-999 | DP-001')) $false 'DV.3'
    Assert-Result 'e3-only' ($valid.Replace('EV-001 | E2 |', 'EV-001 | E3 |')) $false 'DV.3'
    Assert-Result 'e4-fact' ($valid.Replace('EV-001 | E2 |', 'EV-001 | E4 |')) $false 'DV.3'
    Assert-Result 'e4-not-unresolved' ($valid.Replace('| EV-001 | E2 | schema definition | schema/record#account-code | DF-001 | composite uniqueness constraint |', "| EV-001 | E2 | schema definition | schema/record#account-code | DF-001 | composite uniqueness constraint |`n| EV-002 | E4 | comment | src/comment | none | unresolved only |")) $false 'DV.3'
    Assert-Result 'duplicate-evidence' ($valid.Replace('| EV-001 | E2 | schema definition | schema/record#account-code | DF-001 | composite uniqueness constraint |', "| EV-001 | E2 | schema definition | schema/record#account-code | DF-001 | composite uniqueness constraint |`n| EV-001 | E2 | second source | src/second | DF-001 | duplicate |")) $false 'DV.3'
    Assert-Result 'english-self-evidence' ($valid.Replace('schema/record#account-code', 'overview-design.md')) $false 'DV.3'
    Assert-Result 'english-self-evidence-spaced' ($valid.Replace('schema/record#account-code', 'overview design.md')) $false 'DV.3'
    Assert-Result 'english-implementation-idea' ($valid.Replace('schema/record#account-code', 'implementation idea')) $false 'DV.3'
    Assert-Result 'english-agent-inference' ($valid.Replace('schema/record#account-code', 'agent inference')) $false 'DV.3'
    Assert-Result 'chinese-self-evidence' ($valid.Replace('schema/record#account-code', (New-UtfString @(24403,21069,26041,26696)))) $false 'DV.3'
    Assert-Result 'chinese-agent-inference' ($valid.Replace('schema/record#account-code', ('agent ' + (New-UtfString @(25512,26029))))) $false 'DV.3'
    Assert-Result 'unresolved-conflict' ($valid.Replace('| none | none | none | none | none | resolved |', '| conflict | source-a | DP-001 | authority required | none | open |')) $false 'DV.6'
    foreach ($fixture in @('missing-fact-id.md','missing-condition.md','missing-counterexample.md','missing-evidence.md','self-evidence.md','unresolved-conflict.md')) {
        Assert-Result ([IO.Path]::GetFileNameWithoutExtension($fixture)) (Get-Content -LiteralPath (Join-Path $fixtureRoot $fixture) -Raw -Encoding utf8) $false 'DV.1'
    }
}
finally { Remove-Item -LiteralPath $TestDrive -Recurse -Force -ErrorAction SilentlyContinue }
Write-Output 'validate-domain-artifact tests passed'
