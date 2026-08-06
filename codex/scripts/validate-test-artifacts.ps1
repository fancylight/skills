# Shim - source of truth: flow/scripts/validate-test-artifacts.ps1
# Temporary Phase 0 wrapper. Prefer flow/scripts/ directly.
param(
    [Parameter(Mandatory = $true)]
    [string]$SystemTestRepo,
    [Parameter(Mandatory = $true)]
    [string]$ChangeName,
    [Parameter(Mandatory = $true)]
    [ValidateSet('design', 'implementation', 'result')]
    [string]$Mode,
    [Parameter(Mandatory = $true)]
    [string]$CanonicalRevision
)
$ErrorActionPreference = 'Stop'
$target = Join-Path (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)) 'flow\scripts\validate-test-artifacts.ps1'
if (-not (Test-Path -LiteralPath $target)) { throw "Shared script not found: $target" }
$splat = @{}
foreach ($key in $PSBoundParameters.Keys) { $splat[$key] = $PSBoundParameters[$key] }
& $target @splat
exit $LASTEXITCODE
