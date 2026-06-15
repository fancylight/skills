param(
    [string]$TargetDir = (Join-Path $env:USERPROFILE ".agents\skills"),
    [switch]$WhatIf
)

$ErrorActionPreference = "Stop"
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$projectRoot = Split-Path -Parent $scriptDir
$skillsDir = Join-Path $scriptDir "skills"
$sharedTemplatesDir = Join-Path $projectRoot "flow\templates"
$codexOverridesDir = Join-Path $sharedTemplatesDir "codex"

if (-not (Test-Path -LiteralPath $skillsDir)) {
    throw "Codex skills directory not found: $skillsDir"
}

New-Item -ItemType Directory -Force -Path $TargetDir -WhatIf:$WhatIf | Out-Null
$targetRoot = [IO.Path]::GetFullPath($TargetDir)

# ---- Stale cleanup ----

$sourceSkills = @(Get-ChildItem -LiteralPath $skillsDir -Directory | Select-Object -ExpandProperty Name)

Get-ChildItem -LiteralPath $TargetDir -Directory -Filter "flow-codex-*" | ForEach-Object {
    if ($sourceSkills -contains $_.Name) { return }
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

# ---- Skill installation ----

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

# ---- Shared templates (from flow/templates/, replaces old codex duplicates) ----

$coreTemplatesDir = Join-Path $TargetDir "flow-codex-core\assets\templates"

if (Test-Path -LiteralPath $sharedTemplatesDir) {
    Write-Output ""
    Write-Output "Installing shared templates from $sharedTemplatesDir..."

    # Copy all templates from shared source
    Get-ChildItem -LiteralPath $sharedTemplatesDir -File | ForEach-Object {
        $dest = Join-Path $coreTemplatesDir $_.Name
        Copy-Item -LiteralPath $_.FullName -Destination $dest -Force -WhatIf:$WhatIf
    }

    # Apply command-name substitution for Codex platform
    $replacements = @(
        @{From='/flow:'; To='$flow-codex-'},
        @{From='/flow:templates:'; To='$flow-codex-'},
        @{From='子 agent'; To='执行 agent'}
    )

    Get-ChildItem -LiteralPath $coreTemplatesDir -File | ForEach-Object {
        $content = Get-Content -LiteralPath $_.FullName -Raw -Encoding UTF8
        $changed = $false
        foreach ($r in $replacements) {
            if ($content.Contains($r.From)) {
                $content = $content.Replace($r.From, $r.To)
                $changed = $true
            }
        }
        if ($changed -and -not $WhatIf) {
            Set-Content -LiteralPath $_.FullName -Value $content -Encoding UTF8 -NoNewline
        }
    }

    # Overlay Codex-specific template overrides
    if (Test-Path -LiteralPath $codexOverridesDir) {
        Write-Output "Overlaying Codex-specific templates from $codexOverridesDir..."
        Get-ChildItem -LiteralPath $codexOverridesDir -File | ForEach-Object {
            $dest = Join-Path $coreTemplatesDir $_.Name
            Copy-Item -LiteralPath $_.FullName -Destination $dest -Force -WhatIf:$WhatIf
            Write-Output "  [override] $($_.Name)"
        }
    }

    Write-Output "Templates installed to $coreTemplatesDir"
}
else {
    Write-Warning "Shared templates directory not found: $sharedTemplatesDir"
}
