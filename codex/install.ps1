param(
    [string]$TargetDir = (Join-Path $env:USERPROFILE ".agents\skills"),
    [switch]$WhatIf,
    [switch]$InstallGitHook,
    [string]$PythonPath,
    [string]$CodexHome = $(if ($env:CODEX_HOME) { $env:CODEX_HOME } else { Join-Path $env:USERPROFILE '.codex' })
)

$ErrorActionPreference = "Stop"
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
. (Join-Path $scriptDir 'scripts/skill-entry.ps1')
$projectRoot = Split-Path -Parent $scriptDir
$skillsDir = Join-Path $scriptDir "skills"
$sharedTemplatesDir = Join-Path $projectRoot "flow\templates"
$codexOverridesDir = Join-Path $sharedTemplatesDir "codex"

if ($InstallGitHook) {
    if (-not $PythonPath -or -not (Test-Path -LiteralPath $PythonPath -PathType Leaf)) {
        throw '-InstallGitHook requires -PythonPath pointing to a verified Python 3.11+ executable.'
    }
    if (-not $WhatIf) {
        & $PythonPath -c 'import sys; sys.exit(0 if sys.version_info >= (3, 11) else 1)'
        if ($LASTEXITCODE -ne 0) { throw 'Flow Git requires Python 3.11+.' }
    }
}

if (-not (Test-Path -LiteralPath $skillsDir)) {
    throw "Codex skills directory not found: $skillsDir"
}

# Validate every entry before removing or replacing any installed skill.
Get-ChildItem -LiteralPath $skillsDir -Directory | ForEach-Object {
    $null = Read-FlowSkillEntry -Path (Join-Path $_.FullName 'SKILL.md') -Name $_.Name
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
    $skillSourceRoot = $_.FullName
    Get-ChildItem -LiteralPath $skillSourceRoot -File -Recurse -Force | Where-Object {
        $_.FullName -notmatch '[\\/]__pycache__[\\/]' -and $_.Extension -ne '.pyc'
    } | ForEach-Object {
        $relativeFile = $_.FullName.Substring($skillSourceRoot.Length + 1)
        $targetFile = Join-Path $destination $relativeFile
        New-Item -ItemType Directory -Force -Path (Split-Path -Parent $targetFile) -WhatIf:$WhatIf | Out-Null
        Copy-Item -LiteralPath $_.FullName -Destination $targetFile -Force -WhatIf:$WhatIf
    }
    if (-not $WhatIf) {
        $null = Read-FlowSkillEntry -Path (Join-Path $destination 'SKILL.md') -Name $_.Name
    }
    Write-Output "Installed $($_.Name) -> $destination"
}

# ---- Shared templates (from flow/templates/, replaces old codex duplicates) ----

# The shared controller protocol is authoritative; refresh the runtime reference from it.
$controllerProtocol = Join-Path $projectRoot 'flow\docs\test-controller.md'
$coreReferencesDir = Join-Path $TargetDir 'flow-codex-core\references'
Copy-Item -LiteralPath $controllerProtocol -Destination (Join-Path $coreReferencesDir 'test-controller.md') -Force -WhatIf:$WhatIf
if (-not $WhatIf) {
    Add-Content -LiteralPath (Join-Path $coreReferencesDir 'test-controller.md') -Encoding UTF8 -Value "`nCodex 单对话执行方式见 first-delivery.md；保持本协议所有状态、授权、租约与版本约束。"
}

$coreTemplatesDir = Join-Path $TargetDir "flow-codex-core\assets\templates"
$coreScriptsDir = Join-Path $TargetDir "flow-codex-core\assets\scripts"

if (Test-Path -LiteralPath $sharedTemplatesDir) {
    Write-Output ""
    Write-Output "Installing shared templates from $sharedTemplatesDir..."

    foreach ($requiredTemplate in @('domain-model.md.tmpl')) {
        $requiredTemplatePath = Join-Path $sharedTemplatesDir $requiredTemplate
        if (-not (Test-Path -LiteralPath $requiredTemplatePath)) {
            throw "Required shared template not found: $requiredTemplatePath"
        }
        Write-Output "  [required] $requiredTemplate"
    }

    New-Item -ItemType Directory -Force -Path $coreTemplatesDir -WhatIf:$WhatIf | Out-Null

    # Copy all top-level template files from shared source
    Get-ChildItem -LiteralPath $sharedTemplatesDir -File | ForEach-Object {
        $dest = Join-Path $coreTemplatesDir $_.Name
        Copy-Item -LiteralPath $_.FullName -Destination $dest -Force -WhatIf:$WhatIf
    }

    # Copy system-test framework skeleton (directory tree used by flow-codex-test-design)
    $systemTestSrc = Join-Path $sharedTemplatesDir "system-test"
    $systemTestDest = Join-Path $coreTemplatesDir "system-test"
    if (Test-Path -LiteralPath $systemTestSrc) {
        if (-not $WhatIf -and (Test-Path -LiteralPath $systemTestDest)) {
            Remove-Item -LiteralPath $systemTestDest -Recurse -Force
        }
        Copy-Item -LiteralPath $systemTestSrc -Destination $systemTestDest -Recurse -Force -WhatIf:$WhatIf
        Write-Output "  [dir] system-test/ -> $systemTestDest"
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

    # Host-agnostic validators/controller live under flow/scripts/ (Phase 0).
    # codex/scripts/*.ps1 are temporary shims only — always install from the shared source.
    $guardScriptsDir = Join-Path $projectRoot 'flow\scripts'
    New-Item -ItemType Directory -Force -Path $coreScriptsDir -WhatIf:$WhatIf | Out-Null
    @('validate-test-artifacts.ps1', 'test-scope-guard.ps1', 'validate-domain-artifact.ps1', 'validate-test-cases.ps1', 'flow-test-controller.ps1', 'flow-test.ps1', 'controller-execution.ps1', 'controller-scope-review.ps1', 'resolve-test-environment.ps1', 'validate-test-environment.ps1', 'migrate-test-environment-manifest.ps1', 'check-java-style.ps1') | ForEach-Object {
        $source = Join-Path $guardScriptsDir $_
        if (-not (Test-Path -LiteralPath $source)) { throw "Required shared guard script not found: $source" }
        $raw = Get-Content -LiteralPath $source -Raw -Encoding UTF8
        if ($raw -match '(?m)^# Shim') { throw "Refusing to install shim as runtime script: $source" }
        Copy-Item -LiteralPath $source -Destination (Join-Path $coreScriptsDir $_) -Force -WhatIf:$WhatIf
        Write-Output "  [script] $_ -> $coreScriptsDir"
    }
}
else {
    Write-Warning "Shared templates directory not found: $sharedTemplatesDir"
}

# Codex-only Git conventions. Do not add to the legacy Claude installer.
Copy-Item -LiteralPath (Join-Path $projectRoot 'flow/scripts/flow-git.py') -Destination (Join-Path $coreScriptsDir 'flow-git.py') -Force -WhatIf:$WhatIf
if ($InstallGitHook) {
    if (-not $WhatIf) {
        & $PythonPath (Join-Path $scriptDir 'scripts/install-git-hook.py') --codex-home $CodexHome --runtime-script (Join-Path $coreScriptsDir 'flow-git.py') --python $PythonPath
        if ($LASTEXITCODE -ne 0) { throw 'Flow Git hook installation failed.' }
    }
}
