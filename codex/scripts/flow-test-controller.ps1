# Shim - source of truth: flow/scripts/flow-test-controller.ps1
# Temporary Phase 0 wrapper. Prefer flow/scripts/ directly.
param(
    [Parameter(Mandatory = $true, Position = 0)]
    [ValidateSet('status', 'next', 'initialize', 'issue-lease', 'validate-lease', 'accept-result', 'record-verifier', 'start-run', 'record-run', 'block')]
    [string]$Command,
    [Parameter(Mandatory = $true)] [string]$StatePath,
    [string]$ChangeName,
    [string]$SystemTestRepo,
    [string]$SutRepo,
    [string]$TestBaselineRevision,
    [string]$TestRevision,
    [string]$ProposedTestRevision,
    [string]$SutRevision,
    [string]$HarnessRevision,
    [string]$HarnessRoot,
    [string]$HarnessCertificationPath,
    [string]$ConfigurationFingerprint,
    [ValidateSet('design', 'implementation', 'execution', 'result')] [string]$Authorization = 'design',
    [ValidateSet('test-implementer', 'verifier', 'runner')] [string]$Role,
    [string]$AgentId,
    [string]$LeaseId,
    [string]$TargetPath,
    [string]$ReportPath,
    [string]$ScopeGuardReportPath,
    [string]$VerifierId,
    [string[]]$Capabilities,
    [ValidateSet('design', 'implementation', 'environment', 'result')] [string]$VerifyMode,
    [ValidateSet('pass', 'fail')] [string]$RunResult,
    [string]$EvidencePath,
    [string]$ScenarioId,
    [string]$FailureCategory,
    [string]$FirstEvidence,
    [string]$Reason,
    [int]$LeaseMinutes = 30,
    [switch]$SimulateWriteFailure
)
$ErrorActionPreference = 'Stop'
$target = Join-Path (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)) 'flow\scripts\flow-test-controller.ps1'
if (-not (Test-Path -LiteralPath $target)) { throw "Shared script not found: $target" }
$splat = @{}
foreach ($key in $PSBoundParameters.Keys) { $splat[$key] = $PSBoundParameters[$key] }
& $target @splat
exit $LASTEXITCODE
