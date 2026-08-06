# Redirect - source of truth: flow/scripts/tests/test-validate-domain-artifact.ps1
$ErrorActionPreference = 'Stop'
$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '../../..')).Path
$target = Join-Path $repoRoot 'flow/scripts/tests/test-validate-domain-artifact.ps1'
if (-not (Test-Path -LiteralPath $target)) { throw "Shared test not found: $target" }
& $target @args
exit $LASTEXITCODE