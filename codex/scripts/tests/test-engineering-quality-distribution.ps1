param([string]$BashExecutable = 'bash')
$ErrorActionPreference = 'Stop'
$repo = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../..'))
$stage = Join-Path ([IO.Path]::GetTempPath()) ('flow-quality-distribution-'+[Guid]::NewGuid().ToString('N'))
$codex = Join-Path $stage 'codex'
$claude = Join-Path $stage 'claude-preview'
[void][IO.Directory]::CreateDirectory($claude)
& (Join-Path $repo 'codex/install.ps1') -TargetDir $codex | Out-Null
Push-Location $claude
try {
    # --project confines even the real installation to this newly created temporary directory.
    & $BashExecutable (Join-Path $repo 'install.sh').Replace('\','/') --project --dry-run | Out-Null
    if ($LASTEXITCODE -ne 0) { throw 'Claude installation preview failed' }
    & $BashExecutable (Join-Path $repo 'install.sh').Replace('\','/') --project | Out-Null
    if ($LASTEXITCODE -ne 0) { throw 'Isolated Claude installation failed' }
} finally { Pop-Location }
$codexTemplates = Join-Path $codex 'flow-codex-core/assets/templates'
$claudeTemplates = Join-Path $claude '.claude/commands/flow/templates'
foreach ($name in @('engineering-quality.md','java-need-braces.xml')) {
    $source = [IO.File]::ReadAllText((Join-Path $repo ('flow/templates/'+$name)))
    foreach ($destination in @($codexTemplates,$claudeTemplates)) {
        if ([IO.File]::ReadAllText((Join-Path $destination $name)) -ne $source) { throw "Shared resource drift: $name" }
        if (-not (Test-Path -LiteralPath (Join-Path $destination '../scripts/check-java-style.ps1'))) { throw 'Installed checker reference is broken' }
    }
}
$names = @('design','verify','apply','review','test-design','test-verify','test-apply','system-test','report','test-report','change','feedback')
foreach ($name in $names) {
    $c = [IO.File]::ReadAllText((Join-Path $codex ('flow-codex-'+$name+'/SKILL.md')))
    $h = [IO.File]::ReadAllText((Join-Path $claude ('.claude/commands/flow/'+$name+'.md')))
    if ($c -notmatch 'engineering-quality.md' -or $h -notmatch 'engineering-quality.md') { throw "Missing installed quality routing: $name" }
    $codexRoute = [regex]::Match($c,'(?m)^.*engineering-quality\.md.*$').Value
    $claudeRoute = [regex]::Match($h,'(?m)^.*engineering-quality\.md.*$').Value
    if ($codexRoute -match '~/.claude|/flow:' -or $claudeRoute -match 'flow-codex-') { throw "Cross-platform quality routing leaked: $name" }
}
foreach ($path in @((Join-Path $codex 'flow-codex-core/assets/scripts/check-java-style.ps1'),(Join-Path $claude '.claude/commands/flow/scripts/check-java-style.ps1'))) {
    $errors = $null
    [void][System.Management.Automation.Language.Parser]::ParseFile($path,[ref]$null,[ref]$errors)
    if ($errors.Count -gt 0) { throw 'Installed checker has syntax errors' }
}
$result = @{result='PASS';entrypoints=24;sharedResources=2;artifacts=$stage;claudeLiveInstallationChanged=$false}
$result | ConvertTo-Json
([IO.File]::WriteAllText((Join-Path $stage 'result.json'),($result | ConvertTo-Json),[Text.UTF8Encoding]::new($false)))
