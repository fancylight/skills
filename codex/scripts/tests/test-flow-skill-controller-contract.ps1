$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSScriptRoot))
$skillsRoot = Join-Path $repoRoot 'codex\skills'
$contracts = [ordered]@{
  'flow-codex-test-design' = @('test-controller.md','initialize')
  'flow-codex-test-verify' = @('test-controller.md','record-verifier','VERIFY_DESIGN','VERIFY_IMPLEMENTATION','VERIFY_RESULT')
  'flow-codex-test-assign' = @('test-controller.md','ISSUE_IMPLEMENTATION_LEASE','issue-lease')
  'flow-codex-test-receive' = @('test-controller.md','AWAIT_IMPLEMENTATION_RESULT','validate-lease')
  'flow-codex-test-apply' = @('test-controller.md','AWAIT_IMPLEMENTATION_RESULT','validate-lease')
  'flow-codex-test-report' = @('test-controller.md','AWAIT_IMPLEMENTATION_RESULT','accept-result')
  'flow-codex-system-test' = @('test-controller.md','RUN_ONCE','AWAIT_RUN_RESULT','start-run','record-run')
  'flow-codex-test' = @('test-controller.md','VERIFY_ENVIRONMENT','RUN_ONCE','BLOCKED','COMPLETE')
}
foreach ($entry in $contracts.GetEnumerator()) {
  $skillPath = Join-Path $skillsRoot "$($entry.Key)\SKILL.md"
  $content = Get-Content -LiteralPath $skillPath -Raw -Encoding UTF8
  foreach ($marker in $entry.Value) {
    if (-not $content.Contains($marker)) { throw "$($entry.Key) does not consume controller contract marker: $marker" }
  }
}
$controller = Get-Content -LiteralPath (Join-Path $repoRoot 'codex\scripts\flow-test-controller.ps1') -Raw -Encoding UTF8
foreach ($marker in @('phase: $($state.phase)','skill: $skill','lease_required:','ERROR_TRANSITION','ERROR_AUTHORIZATION')) {
  if (-not $controller.Contains($marker)) { throw "controller next/guard marker missing: $marker" }
}
$goal = Get-Content -LiteralPath (Join-Path $skillsRoot 'flow-codex-core\references\test-controller.md') -Raw -Encoding UTF8
foreach ($marker in @('next=BLOCKED','next=COMPLETE','controller next','Goal')) {
  if (-not $goal.Contains($marker)) { throw "Goal protocol marker missing: $marker" }
}
Write-Output 'flow test skills consume the controller/lease/Goal contract'
