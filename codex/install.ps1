param(
    [string]$TargetDir = (Join-Path $env:USERPROFILE ".agents\skills"),
    [switch]$WhatIf
)

$ErrorActionPreference = "Stop"
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$skillsDir = Join-Path $scriptDir "skills"

if (-not (Test-Path -LiteralPath $skillsDir)) {
    throw "Codex skills directory not found: $skillsDir"
}

New-Item -ItemType Directory -Force -Path $TargetDir -WhatIf:$WhatIf | Out-Null
$targetRoot = [IO.Path]::GetFullPath($TargetDir)
$sourceSkills = @(Get-ChildItem -LiteralPath $skillsDir -Directory | Select-Object -ExpandProperty Name)

Get-ChildItem -LiteralPath $TargetDir -Directory -Filter "flow-codex-*" | ForEach-Object {
    if ($sourceSkills -contains $_.Name) {
        return
    }
    $staleFullPath = [IO.Path]::GetFullPath($_.FullName)
    if (-not $staleFullPath.StartsWith(
        $targetRoot + [IO.Path]::DirectorySeparatorChar,
        [StringComparison]::OrdinalIgnoreCase
    )) {
        throw "Refusing to remove stale skill outside target directory: $staleFullPath"
    }
    Remove-Item -LiteralPath $staleFullPath -Recurse -Force -WhatIf:$WhatIf
    Write-Output "Removed stale adapter skill $($_.Name)"
}

Get-ChildItem -LiteralPath $skillsDir -Directory | ForEach-Object {
    $destination = Join-Path $TargetDir $_.Name
    $destinationFullPath = [IO.Path]::GetFullPath($destination)
    if (-not $destinationFullPath.StartsWith(
        $targetRoot + [IO.Path]::DirectorySeparatorChar,
        [StringComparison]::OrdinalIgnoreCase
    )) {
        throw "Refusing to install outside target directory: $destinationFullPath"
    }
    if (Test-Path -LiteralPath $destination) {
        Remove-Item -LiteralPath $destination -Recurse -Force -WhatIf:$WhatIf
    }
    New-Item -ItemType Directory -Force -Path $destination -WhatIf:$WhatIf | Out-Null
    Get-ChildItem -LiteralPath $_.FullName -Force | ForEach-Object {
        Copy-Item -LiteralPath $_.FullName -Destination $destination -Recurse -Force -WhatIf:$WhatIf
    }
    Write-Output "Installed $($_.Name) -> $destination"
}
