$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$files = @(
    (Join-Path $root 'skills\flow-codex-design\SKILL.md'),
    (Join-Path $root 'skills\flow-codex-verify\SKILL.md'),
    (Join-Path $root 'skills\flow-codex-review\SKILL.md'),
    (Join-Path (Split-Path -Parent $root) 'flow\templates\overview-design.md.tmpl')
)

foreach ($file in $files) {
    if (-not (Test-Path -LiteralPath $file)) { throw "Missing propagation artifact: $file" }
    if ((Get-Content -LiteralPath $file -Raw -Encoding utf8) -notmatch 'Fact ID') {
        throw "Missing Fact ID propagation contract: $file"
    }
}

$design = Get-Content -LiteralPath $files[0] -Raw -Encoding utf8
if ($design -notmatch 'DOMAIN_VERIFY_RESULT' -or $design -notmatch 'domain_model_sha256') {
    throw 'Design does not require a matching DOMAIN_VERIFIED result before solution artifacts'
}

Write-Output 'domain Fact ID propagation contract passed'
