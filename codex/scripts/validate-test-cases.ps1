# Shim - source of truth: flow/scripts/validate-test-cases.ps1
# Temporary Phase 0 wrapper. Prefer flow/scripts/ directly.
param(
    [Parameter(Mandatory = $true)] [string]$TestCasesPath,
    [ValidateSet('design', 'implementation', 'result')] [string]$Mode = 'design',
    [string]$CanonicalRevision,
    [string]$ManifestPath,
    [string]$DerivedContractPath,
    [string]$TestPlanPath,
    [string]$JavaSourceRoot,
    [string]$EvidenceRoot,
    [string]$PreviousTestCasesPath,
    [string]$PreviousTestRevision,
    [string]$DesignVerifierReportPath,
    [string]$ControllerStatePath,
    [string]$TrustedVerifierIdentity,
    [switch]$Generate
)
$ErrorActionPreference = 'Stop'
$target = Join-Path (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)) 'flow\scripts\validate-test-cases.ps1'
if (-not (Test-Path -LiteralPath $target)) { throw "Shared script not found: $target" }
$splat = @{}
foreach ($key in $PSBoundParameters.Keys) { $splat[$key] = $PSBoundParameters[$key] }
& $target @splat
exit $LASTEXITCODE
