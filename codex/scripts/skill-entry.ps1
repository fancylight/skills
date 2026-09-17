function Read-FlowSkillEntry {
    param([Parameter(Mandatory)][string]$Path, [Parameter(Mandatory)][string]$Name)

    # Decode raw bytes: Get-Content silently removes the BOM that breaks discovery.
    $bytes = [IO.File]::ReadAllBytes($Path)
    if ($bytes.Length -ge 3 -and $bytes[0] -eq 239 -and $bytes[1] -eq 187 -and $bytes[2] -eq 191) {
        throw "SKILL.md must use UTF-8 without BOM: $Path"
    }
    $utf8 = New-Object System.Text.UTF8Encoding($false, $true)
    $content = $utf8.GetString($bytes)
    $pattern = "(?s)^---\r?\nname: $([regex]::Escape($Name))\r?\ndescription: .+?\r?\n---"
    if ($content -notmatch $pattern) {
        throw "Invalid skill frontmatter or folder mismatch: $Path"
    }
    return $content
}
