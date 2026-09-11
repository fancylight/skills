param([string]$BaselineDir)
$ErrorActionPreference = 'Stop'
$repo = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../..'))
$stage = Join-Path ([IO.Path]::GetTempPath()) ('flow-quality-distribution-' + [Guid]::NewGuid().ToString('N'))
& (Join-Path $repo 'codex/install.ps1') -TargetDir $stage | Out-Null
function Read-Normalized([string]$Path) { return [IO.File]::ReadAllText($Path).Replace("`r`n", "`n").TrimStart([char]0xfeff) }
$templates = Join-Path $stage 'flow-codex-core/assets/templates'
foreach ($name in @('engineering-quality.md','java-need-braces.xml')) {
    if ((Read-Normalized (Join-Path $repo "flow/templates/$name")) -ne (Read-Normalized (Join-Path $templates $name))) { throw "Installed quality resource drift: $name" }
}
$checker = Join-Path $stage 'flow-codex-core/assets/scripts/check-java-style.ps1'
if ((Read-Normalized (Join-Path $repo 'flow/scripts/check-java-style.ps1')) -ne (Read-Normalized $checker)) { throw 'Installed Java checker drift' }
$entries = @('design','verify','apply','review','test-design','test-verify','test-apply','system-test','report','test-report','change','feedback')
foreach ($name in $entries) {
    $text = Read-Normalized (Join-Path $stage "flow-codex-$name/SKILL.md")
    if ($text -notmatch 'engineering-quality.md') { throw "Missing quality route: $name" }
}
if ($BaselineDir) {
    foreach ($name in @('apply','feedback')) {
        $before = Join-Path $BaselineDir "flow-codex-$name"
        $after = Join-Path $stage "flow-codex-$name"
        $oldFiles = @(Get-ChildItem -LiteralPath $before -Recurse -File)
        $newFiles = @(Get-ChildItem -LiteralPath $after -Recurse -File)
        if ($oldFiles.Count -ne $newFiles.Count) { throw "Frozen skill inventory changed: $name" }
        foreach ($file in $oldFiles) {
            $relative = $file.FullName.Substring($before.TrimEnd('\','/').Length + 1)
            $destination = Join-Path $after $relative
            if (-not (Test-Path -LiteralPath $destination) -or (Read-Normalized $file.FullName) -ne (Read-Normalized $destination)) { throw "Frozen installed content changed: $name/$relative" }
        }
    }
    foreach ($path in @('flow-codex-core/assets/scripts/check-java-style.ps1','flow-codex-core/assets/templates/engineering-quality.md','flow-codex-core/assets/templates/java-need-braces.xml')) {
        if ((Read-Normalized (Join-Path $BaselineDir $path)) -ne (Read-Normalized (Join-Path $stage $path))) { throw "Existing quality resource changed: $path" }
    }
}
[pscustomobject]@{result='PASS';entrypoints=$entries.Count;baselineCompared=[bool]$BaselineDir;artifacts=$stage;globalInstallationChanged=$false} | ConvertTo-Json
