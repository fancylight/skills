$ErrorActionPreference = 'Stop'
$skillPath = Join-Path (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)) 'skills\flow-codex-design\SKILL.md'
$skill = Get-Content -LiteralPath $skillPath -Raw -Encoding utf8

foreach ($required in @(
    '[FLOW_DOMAIN_RESULT] DOMAIN_DRAFT',
    '[DOMAIN_VERIFY_RESULT] PASS',
    'phase: DOMAIN_VERIFIED',
    'domain_model_sha256',
    'OpenSpec'
)) {
    if ($skill -notmatch [regex]::Escape($required)) {
        throw "Missing domain gate contract: $required"
    }
}

Write-Output 'flow-codex-design domain gate contract passed'
