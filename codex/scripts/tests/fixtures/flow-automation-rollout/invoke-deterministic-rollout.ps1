[CmdletBinding()]
param(
  [string]$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..\..\..\..')).Path,
  [Parameter(Mandatory=$true)] [string]$OutputRoot
)

$ErrorActionPreference = 'Stop'
$tests = @(
  @{ id='domain-validator'; path='codex/scripts/tests/test-validate-domain-artifact.ps1' },
  @{ id='domain-replay'; path='codex/scripts/tests/test-domain-verifier-replay.ps1' },
  @{ id='fact-propagation'; path='codex/scripts/tests/test-domain-fact-propagation.ps1' },
  @{ id='design-domain-gate'; path='codex/scripts/tests/test-design-domain-gate.ps1' },
  @{ id='canonical-test-cases'; path='codex/scripts/tests/test-validate-test-cases.ps1' },
  @{ id='test-artifacts'; path='codex/scripts/tests/test-validate-test-artifacts.ps1' },
  @{ id='controller'; path='codex/scripts/tests/test-flow-test-controller.ps1' },
  @{ id='harness'; path='codex/scripts/tests/test-harness-certification.ps1' },
  @{ id='skill-contract'; path='codex/scripts/tests/test-flow-skill-controller-contract.ps1' },
  @{ id='scope-guard'; path='codex/scripts/tests/test-test-scope-guard.ps1' },
  @{ id='distributable-surface'; path='codex/scripts/tests/test-distributable-surface.ps1' },
  @{ id='failure-evidence'; path='codex/scripts/tests/test-collect-failure-evidence.ps1' }
)

function Get-Hash([string]$Path) { return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant() }

if (Test-Path -LiteralPath $OutputRoot) { Remove-Item -LiteralPath $OutputRoot -Recurse -Force }
[void](New-Item -ItemType Directory -Path $OutputRoot -Force)
$results = @()
foreach ($test in $tests) {
  $scriptPath = Join-Path $RepoRoot $test.path
  if (-not (Test-Path -LiteralPath $scriptPath -PathType Leaf)) { throw "rollout test missing: $($test.path)" }
  $started = [DateTime]::UtcNow
  $oldPreference=$ErrorActionPreference; $ErrorActionPreference='Continue'
  try { $output=@(& powershell.exe -NoProfile -ExecutionPolicy Bypass -File $scriptPath 2>&1 | ForEach-Object { [string]$_ }); $exitCode=$LASTEXITCODE }
  finally { $ErrorActionPreference=$oldPreference }
  $logPath=Join-Path $OutputRoot ($test.id + '.log')
  [IO.File]::WriteAllText($logPath, ($output -join "`r`n"), [Text.UTF8Encoding]::new($false))
  $results += [ordered]@{ id=$test.id; script=$test.path; scriptHash=(Get-Hash $scriptPath); startedAt=$started.ToString('o'); completedAt=[DateTime]::UtcNow.ToString('o'); exitCode=$exitCode; result=$(if($exitCode -eq 0){'PASS'}else{'FAIL'}); log=($test.id+'.log'); logHash=(Get-Hash $logPath) }
}
$report=[ordered]@{ schemaVersion=1; result=$(if(@($results|Where-Object{$_.result-ne'PASS'}).Count-eq 0){'PASS'}else{'FAIL'}); runtime='Windows PowerShell'; generatedAt=[DateTime]::UtcNow.ToString('o'); tests=$results }
[IO.File]::WriteAllText((Join-Path $OutputRoot 'report.json'), ($report|ConvertTo-Json -Depth 8), [Text.UTF8Encoding]::new($false))
Write-Output "[ROLLOUT_DETERMINISTIC] $($report.result)"
if($report.result-ne'PASS'){exit 1}
