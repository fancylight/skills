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
    "flow-codex-test-design",
    "flow-codex-test-verify",
    "flow-codex-test-assign",
    "flow-codex-test-receive",
    "flow-codex-test-apply",
    "flow-codex-test-report",
    "flow-codex-system-test",
    "flow-codex-change",
    "flow-codex-archive",
    "flow-codex-kb",
    "flow-codex-hotfix",
    "flow-codex-feedback"
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
$projectRoot = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
$sharedTemplatesDir = Join-Path $projectRoot "flow\templates"
$codexOverridesDir = Join-Path $sharedTemplatesDir "codex"

@(
    "references\platform.md",
    "references\checkpoints.md"
) | ForEach-Object {
    if (-not (Test-Path -LiteralPath (Join-Path $coreDir $_))) {
        $errors += "Missing core resource: $_"
    }
}

# Shared templates now live in flow/templates/ (single source of truth)
if (-not (Test-Path -LiteralPath $codexOverridesDir)) {
    $errors += "Missing Codex template overrides directory: $codexOverridesDir"
}
else {
    $overrideFiles = @(Get-ChildItem -LiteralPath $codexOverridesDir -File)
    if ($overrideFiles.Count -lt 4) {
        $errors += "Codex template overrides directory has fewer than 4 files ($($overrideFiles.Count) found)"
    }
}

if (-not (Test-Path -LiteralPath $sharedTemplatesDir)) {
    $errors += "Missing shared templates directory: $sharedTemplatesDir"
}

@(
    "test-design.md.tmpl",
    "test-plan.md.tmpl",
    "test-verify-checklist.md",
    "integration-test-result.md.tmpl"
) | ForEach-Object {
    if (-not (Test-Path -LiteralPath (Join-Path $sharedTemplatesDir $_))) {
        $errors += "Missing integration-test template: $_"
    }
}

$workflowMarkers = @(
    @{ File = "flow-codex-test-design\SKILL.md"; Marker = "TDD.1" },
    @{ File = "flow-codex-test-assign\SKILL.md"; Marker = "verify_mode: design" },
    @{ File = "flow-codex-test\SKILL.md"; Marker = "verify_mode: implementation" },
    @{ File = "flow-codex-test\SKILL.md"; Marker = "flow-codex-test-verify result" },
    @{ File = "flow-codex-system-test\SKILL.md"; Marker = "execution_mode" },
    @{ File = "flow-codex-archive\SKILL.md"; Marker = "verify_mode: result" }
)
$workflowMarkers | ForEach-Object {
    $path = Join-Path $skillsDir $_.File
    if (-not (Test-Path -LiteralPath $path) -or (Get-Content -LiteralPath $path -Raw -Encoding utf8) -notmatch [regex]::Escape($_.Marker)) {
        $errors += "Missing integration-test lifecycle marker '$($_.Marker)' in $($_.File)"
    }
}

# Feedback / CDP templates and skill references (Discover + data-fix)
$feedbackSkillDir = Join-Path $skillsDir "flow-codex-feedback"
@(
    (Join-Path $sharedTemplatesDir "feedback-report.md.tmpl"),
    (Join-Path $sharedTemplatesDir "feedback-record.md.tmpl"),
    (Join-Path $sharedTemplatesDir "feedback-index.md.tmpl"),
    (Join-Path $sharedTemplatesDir "cdp-playbook.md.tmpl"),
    (Join-Path $sharedTemplatesDir "feedback-kb-rules.md"),
    (Join-Path $feedbackSkillDir "references\cdp.md"),
    (Join-Path $feedbackSkillDir "references\discover-kb.md"),
    (Join-Path $feedbackSkillDir "references\workflow.md"),
    (Join-Path $skillsDir "flow-codex-kb\references\feedback-kb-rules.md")
) | ForEach-Object {
    if (-not (Test-Path -LiteralPath $_)) {
        $errors += "Missing feedback/CDP resource: $_"
    }
}

$journeyTemplateFound = $false
Get-ChildItem -LiteralPath $sharedTemplatesDir -Filter "*.tmpl" -File -ErrorAction SilentlyContinue | ForEach-Object {
    $head = (Get-Content -LiteralPath $_.FullName -TotalCount 12 -Encoding utf8 -ErrorAction SilentlyContinue) -join "`n"
    if ($head -match 'J\{n\}') {
        $journeyTemplateFound = $true
    }
}
if (-not $journeyTemplateFound) {
    $errors += "Missing journey template (operation journey .tmpl with J{n} sections) in $sharedTemplatesDir"
}

if ($errors.Count -gt 0) {
    $errors | ForEach-Object { Write-Error $_ }
    exit 1
}

Write-Output "Codex Flow skills validated."
