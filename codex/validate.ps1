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

@('flow-codex-worker', 'flow-codex-test-ready') | ForEach-Object {
    if (Test-Path -LiteralPath (Join-Path $skillsDir $_)) {
        $errors += "Deprecated public skill remains: $_"
    }
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

# Distributable skills and templates must remain requirement-agnostic. Historical evidence belongs
# only under docs/case-studies/, which is never installed or linked as a skill resource.
$caseStudiesDir = Join-Path $projectRoot "docs\case-studies"
if (-not (Test-Path -LiteralPath $caseStudiesDir -PathType Container)) {
    $errors += "Missing non-distributable case-studies directory: $caseStudiesDir"
}
$caseLeakPattern = '(?i)overseas-roster-template-optimization|guanghuo-wage-register-audit|worker-service|glm-system-test|31cc73b|b4bdb667'
$distributableFiles = @(
    @(Get-ChildItem -LiteralPath $skillsDir -Recurse -File -ErrorAction SilentlyContinue),
    @(Get-ChildItem -LiteralPath $sharedTemplatesDir -Recurse -File -ErrorAction SilentlyContinue),
    @(Get-ChildItem -LiteralPath $projectRoot -Filter 'PLAN-*.md' -File -ErrorAction SilentlyContinue)
) | ForEach-Object { $_ }
$distributableFiles | Where-Object { $_.Extension -in @('.md', '.tmpl', '.yaml', '.yml', '.ps1') } | ForEach-Object {
    $resourceContent = Get-Content -LiteralPath $_.FullName -Raw -Encoding utf8
    if ($resourceContent -match $caseLeakPattern) {
        $errors += "Requirement-specific identifier in distributable surface: $($_.FullName)"
    }
}
Get-ChildItem -LiteralPath $skillsDir -Recurse -File -Filter '*.md' -ErrorAction SilentlyContinue | ForEach-Object {
    if ((Get-Content -LiteralPath $_.FullName -Raw -Encoding utf8) -match 'docs/case-studies') {
        $errors += "Skill must not link case-study evidence: $($_.FullName)"
    }
}

@(
    "test-design.md.tmpl",
    "test-plan.md.tmpl",
    "test-verify-checklist.md",
    "test-cases.yaml.tmpl",
    "integration-test-result.md.tmpl",
    "domain-model.md.tmpl"
) | ForEach-Object {
    if (-not (Test-Path -LiteralPath (Join-Path $sharedTemplatesDir $_))) {
        $errors += "Missing integration-test template: $_"
    }
}

@('validate-test-artifacts.ps1', 'test-scope-guard.ps1') | ForEach-Object {
    $scriptPath = Join-Path $scriptDir "scripts\$_"
    if (-not (Test-Path -LiteralPath $scriptPath)) {
        $errors += "Missing integration-test guard script: $scriptPath"
    }
    else {
        $parseErrors = $null
        [void][System.Management.Automation.Language.Parser]::ParseFile($scriptPath, [ref]$null, [ref]$parseErrors)
        if ($parseErrors.Count -gt 0) {
            $errors += "PowerShell parse error in guard script: $scriptPath"
        }
    }
}
$testCasesValidator = Join-Path $scriptDir 'scripts\validate-test-cases.ps1'
if (-not (Test-Path -LiteralPath $testCasesValidator)) {
    $errors += "Missing canonical test-cases validator: $testCasesValidator"
}
else {
    $parseErrors = $null
    [void][System.Management.Automation.Language.Parser]::ParseFile($testCasesValidator, [ref]$null, [ref]$parseErrors)
    if ($parseErrors.Count -gt 0) { $errors += "PowerShell parse error in test-cases validator: $testCasesValidator" }
}
$domainArtifactValidator = Join-Path $scriptDir 'scripts\validate-domain-artifact.ps1'
if (-not (Test-Path -LiteralPath $domainArtifactValidator)) {
    $errors += "Missing domain artifact validator: $domainArtifactValidator"
}
else {
    $parseErrors = $null
    [void][System.Management.Automation.Language.Parser]::ParseFile($domainArtifactValidator, [ref]$null, [ref]$parseErrors)
    if ($parseErrors.Count -gt 0) {
        $errors += "PowerShell parse error in domain artifact validator: $domainArtifactValidator"
    }
}
$flowTestController = Join-Path $scriptDir 'scripts\flow-test-controller.ps1'
if (-not (Test-Path -LiteralPath $flowTestController)) {
    $errors += "Missing flow test controller: $flowTestController"
}
else {
    $parseErrors = $null
    [void][System.Management.Automation.Language.Parser]::ParseFile($flowTestController, [ref]$null, [ref]$parseErrors)
    if ($parseErrors.Count -gt 0) {
        $errors += "PowerShell parse error in flow test controller: $flowTestController"
    }
}
$domainReplayCases = Join-Path $scriptDir 'scripts\tests\fixtures\domain-replay\cases.json'
if (-not (Test-Path -LiteralPath $domainReplayCases)) {
    $errors += "Missing domain verifier replay case index: $domainReplayCases"
}
$failureCollector = Join-Path $sharedTemplatesDir 'system-test\scripts\collect-failure-evidence.ps1'
if (-not (Test-Path -LiteralPath $failureCollector)) {
    $errors += "Missing system-test failure evidence collector: $failureCollector"
}
else {
    $parseErrors = $null
    [void][System.Management.Automation.Language.Parser]::ParseFile($failureCollector, [ref]$null, [ref]$parseErrors)
    if ($parseErrors.Count -gt 0) {
        $errors += "PowerShell parse error in failure evidence collector: $failureCollector"
    }
}
$systemTestRunner = Join-Path $sharedTemplatesDir 'system-test\scripts\system-test.ps1'
if (-not (Test-Path -LiteralPath $systemTestRunner)) {
    $errors += "Missing system-test runner: $systemTestRunner"
}
else {
    $parseErrors = $null
    [void][System.Management.Automation.Language.Parser]::ParseFile($systemTestRunner, [ref]$null, [ref]$parseErrors)
    if ($parseErrors.Count -gt 0) {
        $errors += "PowerShell parse error in system-test runner: $systemTestRunner"
    }
}

@('test-validate-test-artifacts.ps1', 'test-test-scope-guard.ps1', 'test-distributable-surface.ps1', 'test-collect-failure-evidence.ps1', 'test-validate-domain-artifact.ps1', 'test-design-domain-gate.ps1', 'test-domain-fact-propagation.ps1', 'test-domain-verifier-replay.ps1', 'test-flow-test-controller.ps1', 'test-validate-test-cases.ps1') | ForEach-Object {
    if (-not (Test-Path -LiteralPath (Join-Path $scriptDir "scripts\tests\$_"))) {
        $label = if ($_ -match '(?i)domain') { 'domain artifact' } elseif ($_ -match '(?i)flow-test-controller') { 'flow controller' } else { 'integration-test guard' }
        $errors += "Missing $label test script: $_"
    }
}

$workflowMarkers = @(
    @{ File = "flow-codex-test-design\SKILL.md"; Marker = "TDD.1" },
    @{ File = "flow-codex-test-design\SKILL.md"; Marker = "authorization_ceiling" },
    @{ File = "flow-codex-test-design\SKILL.md"; Marker = "failureObservability" },
    @{ File = "flow-codex-test-design\SKILL.md"; Marker = "test-cases.yaml" },
    @{ File = "flow-codex-test-verify\SKILL.md"; Marker = "validate-test-cases.ps1" },
    @{ File = "flow-codex-test-verify\SKILL.md"; Marker = "validate-test-artifacts.ps1" },
    @{ File = "flow-codex-test-assign\SKILL.md"; Marker = "verify_mode: design" },
    @{ File = "flow-codex-test-assign\SKILL.md"; Marker = "ceiling" },
    @{ File = "flow-codex-test-apply\SKILL.md"; Marker = "BLOCKED_SCOPE_VIOLATION" },
    @{ File = "flow-codex-test\SKILL.md"; Marker = "verify_mode: implementation" },
    @{ File = "flow-codex-test\SKILL.md"; Marker = "configurationSource" },
    @{ File = "flow-codex-test\SKILL.md"; Marker = "STOP_AWAIT_USER_AUTHORIZATION" },
    @{ File = "flow-codex-test\SKILL.md"; Marker = "flow-codex-test-verify result" },
    @{ File = "flow-codex-system-test\SKILL.md"; Marker = "execution_mode" },
    @{ File = "flow-codex-system-test\SKILL.md"; Marker = "configurationSource" },
    @{ File = "flow-codex-system-test\SKILL.md"; Marker = "failure-report.md" },
    @{ File = "flow-codex-system-test\SKILL.md"; Marker = "ceiling<execution" },
    @{ File = "flow-codex-core\references\checkpoints.md"; Marker = "MAX_REJECT_ROUNDS" },
    @{ File = "flow-codex-test-verify\SKILL.md"; Marker = "TEST_EVIDENCE_INCOMPLETE" },
    @{ File = "flow-codex-archive\SKILL.md"; Marker = "verify_mode: result" },
    @{ File = "flow-codex-design\SKILL.md"; Marker = "[FLOW_DOMAIN_RESULT] DOMAIN_DRAFT" },
    @{ File = "flow-codex-verify\SKILL.md"; Marker = "verify_mode=domain" },
    @{ File = "flow-codex-review\SKILL.md"; Marker = "DOMAIN_VERIFY_RESULT PASS" }
)
$workflowMarkers | ForEach-Object {
    $path = Join-Path $skillsDir $_.File
    if (-not (Test-Path -LiteralPath $path) -or (Get-Content -LiteralPath $path -Raw -Encoding utf8) -notmatch [regex]::Escape($_.Marker)) {
        $label = if ($_.File -match '(?i)flow-codex-(design|verify|review)') { 'domain' } else { 'integration-test' }
        $errors += "Missing $label lifecycle marker '$($_.Marker)' in $($_.File)"
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
