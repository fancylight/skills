$ErrorActionPreference = "Stop"
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$skillsDir = Join-Path $scriptDir "skills"
$errors = @()
$requiredSkills = @(
    "flow-codex-core",
    "flow-codex-init",
    "flow-codex-design",
    "flow-codex-assign",
    "flow-codex-receive",
    "flow-codex-apply",
    "flow-codex-report",
    "flow-codex-review",
    "flow-codex-status",
    "flow-codex-verify",
    "flow-codex-test",
    "flow-codex-change",
    "flow-codex-archive",
    "flow-codex-kb",
    "flow-codex-hotfix"
)
$forbiddenPattern = "TODO|Skill\(|AskUserQuestion|TaskCreate|/flow:|~/\.claude|~/\.Codex"

$requiredSkills | ForEach-Object {
    if (-not (Test-Path -LiteralPath (Join-Path $skillsDir $_))) {
        $errors += "Missing required skill: $_"
    }
}

if (Test-Path -LiteralPath (Join-Path $skillsDir "flow-codex-worker")) {
    $errors += "Deprecated public skill remains: flow-codex-worker"
}

Get-ChildItem -LiteralPath $skillsDir -Directory | ForEach-Object {
    $skillName = $_.Name
    $skillDir = $_.FullName
    $skillFile = Join-Path $skillDir "SKILL.md"
    $openAiFile = Join-Path $skillDir "agents\openai.yaml"

    if (-not (Test-Path -LiteralPath $skillFile)) {
        $errors += "Missing SKILL.md: $skillName"
        return
    }

    if (-not (Test-Path -LiteralPath $openAiFile)) {
        $errors += "Missing agents/openai.yaml: $skillName"
    }

    $content = Get-Content -LiteralPath $skillFile -Raw -Encoding utf8
    $frontmatterPattern = "(?s)^---\r?\nname: $([regex]::Escape($skillName))\r?\ndescription: .+?\r?\n---"
    if ($content -notmatch $frontmatterPattern) {
        $errors += "Invalid frontmatter or folder mismatch: $skillName"
    }

    [regex]::Matches($content, "\]\((references|assets)/([^)]+)\)") | ForEach-Object {
        $relativePath = Join-Path $_.Groups[1].Value $_.Groups[2].Value
        if (-not (Test-Path -LiteralPath (Join-Path $skillDir $relativePath))) {
            $errors += "Missing linked resource: $skillName/$relativePath"
        }
    }

    Get-ChildItem -LiteralPath $skillDir -Recurse -File | Where-Object {
        $_.Extension -in @(".md", ".tmpl", ".yaml", ".yml")
    } | ForEach-Object {
        $resourceContent = Get-Content -LiteralPath $_.FullName -Raw -Encoding utf8
        if ($resourceContent -match $forbiddenPattern) {
            $errors += "Claude-specific or placeholder token remains: $($_.FullName)"
        }
    }

    Write-Output "Validated $skillName"
}

$coreDir = Join-Path $skillsDir "flow-codex-core"
@(
    "references\platform.md",
    "references\checkpoints.md",
    "assets\templates\child-agent-prompt.md",
    "assets\templates\onboarding.md.tmpl"
) | ForEach-Object {
    if (-not (Test-Path -LiteralPath (Join-Path $coreDir $_))) {
        $errors += "Missing core resource: $_"
    }
}

if ($errors.Count -gt 0) {
    $errors | ForEach-Object { Write-Error $_ }
    exit 1
}

Write-Output "Codex Flow skills validated."
