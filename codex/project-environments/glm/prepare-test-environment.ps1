param(
    [ValidateSet('status','ensure')] [string]$Command = 'status',
    [Parameter(Mandatory=$true)] [string]$ResolvedManifestPath,
    [string]$OutputPath = ''
)
$ErrorActionPreference='Stop'
$helper=Join-Path $env:USERPROFILE '.agents/skills/flow-codex-core/assets/templates/system-test/scripts/project-test-environment.ps1'
. $helper
$resolved=Get-Content -LiteralPath $ResolvedManifestPath -Raw -Encoding UTF8 | ConvertFrom-Json
$policy=Join-Path (Split-Path -Parent $PSScriptRoot) 'test-environment.json'
$result=Invoke-ProjectEnvironmentPrepare -Resolved $resolved -PolicyPath $policy -Ensure:($Command -eq 'ensure')
$json=$result | ConvertTo-Json -Depth 12
if($OutputPath){[IO.File]::WriteAllText([IO.Path]::GetFullPath($OutputPath),$json,[Text.UTF8Encoding]::new($false))}
Write-Output $json
if($result.result -eq 'ACTION_REQUIRED'){exit 1}
