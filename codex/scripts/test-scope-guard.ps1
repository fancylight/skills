# Shim - source of truth: flow/scripts/test-scope-guard.ps1
# Temporary Phase 0 wrapper. Prefer flow/scripts/ directly.
param(
    [Parameter(Mandatory = $true)] [string]$AuthorizedRepo,
    [Parameter(Mandatory = $true)] [string]$TargetPath,
    [Parameter(Mandatory = $true)] [ValidateSet('design', 'apply', 'review', 'execution', 'result')] [string]$Stage,
    [ValidateSet('read', 'write', 'test', 'commit')] [string]$Action = 'write',
    [ValidateSet('none', 'static', 'docker', 'doctor', 'service', 'api', 'runner')] [string]$CommandKind = 'none'
)
$ErrorActionPreference = 'Stop'
$target = Join-Path (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)) 'flow\scripts\test-scope-guard.ps1'
if (-not (Test-Path -LiteralPath $target)) { throw "Shared script not found: $target" }
$splat = @{}
foreach ($key in $PSBoundParameters.Keys) { $splat[$key] = $PSBoundParameters[$key] }
& $target @splat
exit $LASTEXITCODE
