[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)] [string]$AuthorizedRepo,
    [Parameter(Mandatory = $true)] [string]$TargetPath,
    [Parameter(Mandatory = $true)] [ValidateSet('design', 'apply', 'review', 'execution', 'result')] [string]$Stage,
    [ValidateSet('read', 'write', 'test', 'commit')] [string]$Action = 'write',
    [ValidateSet('none', 'static', 'docker', 'doctor', 'service', 'api', 'runner')] [string]$CommandKind = 'none'
)

$ErrorActionPreference = 'Stop'
$repo = [IO.Path]::GetFullPath($AuthorizedRepo).TrimEnd('\', '/')
$target = [IO.Path]::GetFullPath($TargetPath)
$relative = ''
$insideRepo = $target.Equals($repo, [StringComparison]::OrdinalIgnoreCase)
if ($target.StartsWith($repo + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)) {
    $insideRepo = $true
    $relative = $target.Substring($repo.Length + 1).Replace('\', '/')
}
$allowed = switch ($Stage) {
    'design' { @('changes/*/test-design.md', 'changes/*/test-plan.md', 'changes/*/manifest.yaml', 'changes/*/fixtures/*') }
    'apply' { @('changes/*/*', 'backend-tests/*', 'test-support/*', 'config/*', 'scripts/*', 'infra/*') }
    'execution' { @('changes/*/evidence/*', 'changes/*/fixtures/*', 'reports/*', '.runtime/*', 'backend-tests/target/*') }
    'result' { @('changes/*/evidence/*', 'changes/*/test-result.md') }
    default { @() }
}
$matches = $insideRepo -and $relative -and (@($allowed | Where-Object { $relative -like $_ }).Count -gt 0)
$commandAllowed = switch ($Stage) {
    'design' { $CommandKind -eq 'none' }
    'apply' { $CommandKind -in @('none', 'static') }
    'review' { $CommandKind -eq 'none' }
    'execution' { $CommandKind -in @('none', 'static', 'docker', 'doctor', 'service', 'api', 'runner') }
    'result' { $CommandKind -in @('none', 'static') }
    default { $false }
}
$operationAllowed = if ($Action -eq 'read') {
    $insideRepo -and $CommandKind -eq 'none'
} elseif ($Action -eq 'test') {
    $insideRepo -and $commandAllowed -and $Stage -notin @('design', 'review', 'result')
} elseif ($Action -eq 'commit') {
    $insideRepo -and $commandAllowed -and $Stage -in @('apply', 'execution', 'result')
} else {
    $matches -and $commandAllowed -and $Stage -ne 'review'
}
if (-not $operationAllowed) {
    Write-Output '[FLOW_GUARD] BLOCKED_SCOPE_VIOLATION'
    Write-Output "repo: $repo"
    Write-Output "path: $target"
    Write-Output "authorized_repo: $repo"
    Write-Output "authorized_paths: $($allowed -join ', ')"
    Write-Output "command_kind: $CommandKind"
    exit 1
}
Write-Output '[FLOW_GUARD] PASS'
Write-Output "stage: $Stage"
Write-Output "action: $Action"
Write-Output "command_kind: $CommandKind"
