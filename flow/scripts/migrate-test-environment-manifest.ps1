[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)] [string]$SystemTestRepo,
    [Parameter(Mandatory = $true)] [string]$LegacyManifestPath,
    [Parameter(Mandatory = $true)] [string]$MigrationSpecPath,
    [Parameter(Mandatory = $true)] [string]$OutputPath
)

$ErrorActionPreference = 'Stop'

function Stop-Migration([string]$Code, [string]$Message) {
    Write-Output '[TEST_ENVIRONMENT_MIGRATION] ERROR'
    Write-Output "code: $Code"
    Write-Output "message: $Message"
    exit 1
}

function Get-CanonicalPath([string]$Path) {
    return [IO.Path]::GetFullPath($Path).TrimEnd([IO.Path]::DirectorySeparatorChar, [IO.Path]::AltDirectorySeparatorChar)
}

function Test-PathWithin([string]$Child, [string]$Parent, [bool]$AllowEqual = $true) {
    $childPath = Get-CanonicalPath $Child
    $parentPath = Get-CanonicalPath $Parent
    if ($AllowEqual -and $childPath.Equals($parentPath, [StringComparison]::OrdinalIgnoreCase)) { return $true }
    return $childPath.StartsWith($parentPath + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)
}

function Read-Json([string]$Path, [string]$Label) {
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { Stop-Migration 'MISSING_MIGRATION_INPUT' "$Label not found: $Path" }
    try { return Get-Content -LiteralPath $Path -Raw -Encoding utf8 | ConvertFrom-Json }
    catch { Stop-Migration 'INVALID_MIGRATION_INPUT' "$Label is not valid JSON: $Path" }
}

function Assert-NoLiteralSensitiveValue($Value, [string]$Location) {
    if ($null -eq $Value) { return }
    if ($Value -is [string]) {
        if ($Value -match '(?i)\b[a-z][a-z0-9+.-]*://[^\s/:@]+:[^\s/@]+@') { Stop-Migration 'ERROR_SECRET_INPUT' "credential-bearing URI found in $Location" }
        if ($Value -match '(?i)(?:password|passwd|token|cookie|secret|credential|connection.?string)\s*[=:]\s*(?!\$\{[A-Z][A-Z0-9_]*\}$)\S+') {
            Stop-Migration 'ERROR_SECRET_INPUT' "literal sensitive value found in $Location"
        }
        return
    }
    if ($Value -is [ValueType]) { return }
    if ($Value -is [System.Collections.IEnumerable] -and -not ($Value -is [pscustomobject])) {
        foreach ($item in $Value) { Assert-NoLiteralSensitiveValue $item $Location }
        return
    }
    foreach ($property in @($Value.PSObject.Properties)) {
        if ($property.Name -match '(?i)(password|passwd|token|cookie|secret|credential|connection.?string)$') {
            $text = [string]$property.Value
            if (-not [string]::IsNullOrWhiteSpace($text) -and $text -notmatch '^\$\{[A-Z][A-Z0-9_]*\}$') {
                Stop-Migration 'ERROR_SECRET_INPUT' "sensitive value must remain a reference at $Location.$($property.Name)"
            }
        }
        Assert-NoLiteralSensitiveValue $property.Value "$Location.$($property.Name)"
    }
}

$testRoot = Get-CanonicalPath $SystemTestRepo
$legacyPath = Get-CanonicalPath $LegacyManifestPath
$specPath = Get-CanonicalPath $MigrationSpecPath
$output = Get-CanonicalPath $OutputPath
if (-not (Test-Path -LiteralPath $testRoot -PathType Container)) { Stop-Migration 'MISSING_TEST_PLATFORM' "system-test repository not found: $testRoot" }
foreach ($path in @($legacyPath, $specPath, $output)) {
    if (-not (Test-PathWithin $path $testRoot)) { Stop-Migration 'PATH_CONFLICT' 'all migration inputs and output must remain inside system-test' }
}
if ($output.Equals($legacyPath, [StringComparison]::OrdinalIgnoreCase)) { Stop-Migration 'IN_PLACE_MIGRATION_FORBIDDEN' 'migration must write a new file for review' }
if (Test-Path -LiteralPath $output) { Stop-Migration 'OUTPUT_ALREADY_EXISTS' "migration output already exists: $output" }

$legacy = Read-Json $legacyPath 'legacy manifest'
$spec = Read-Json $specPath 'migration spec'
Assert-NoLiteralSensitiveValue $legacy 'legacyManifest'
Assert-NoLiteralSensitiveValue $spec 'migrationSpec'

if ([int]$legacy.schemaVersion -eq 2 -or $legacy.PSObject.Properties.Name -contains 'environment') {
    Stop-Migration 'ALREADY_V2' 'input already contains the v2 environment model'
}
if ($null -eq $legacy.configuration -or [string]::IsNullOrWhiteSpace([string]$legacy.configuration.source) -or
    [string]$legacy.configuration.ownership -notin @('human','harness')) {
    Stop-Migration 'INVALID_LEGACY_MANIFEST' 'legacy configuration.source and ownership=human|harness are required'
}
if ([int]$spec.schemaVersion -ne 1 -or $null -eq $spec.environment -or [string]::IsNullOrWhiteSpace([string]$spec.environment.id) -or
    [string]::IsNullOrWhiteSpace([string]$spec.environment.descriptor)) {
    Stop-Migration 'INVALID_MIGRATION_SPEC' 'migration spec schemaVersion=1 and environment id/descriptor are required'
}
if (@($spec.configuration.targets).Count -eq 0 -or @($spec.suts).Count -eq 0 -or $null -eq $spec.harness -or $null -eq $spec.runner) {
    Stop-Migration 'INVALID_MIGRATION_SPEC' 'migration spec requires configuration.targets, suts, harness, and runner'
}

$migrated = [ordered]@{}
foreach ($property in @($legacy.PSObject.Properties)) {
    if ($property.Name -in @('schemaVersion','configuration','environment','suts','harness','runner','configurationSource','requiredEndpoints','connectivityProbe','ownership')) { continue }
    $migrated[$property.Name] = $property.Value
}
$migrated.schemaVersion = 2
$migrated.environment = $spec.environment
$migrated.configuration = [ordered]@{
    environmentFile = ([string]$legacy.configuration.source).Replace('\','/')
    ownership = [string]$legacy.configuration.ownership
    targets = @($spec.configuration.targets)
}
$migrated.suts = @($spec.suts)
$migrated.harness = $spec.harness
$migrated.runner = $spec.runner
$migrated.migration = [ordered]@{
    sourceSchema = 'legacy-v1'
    sourceManifestSha256 = (Get-FileHash -LiteralPath $legacyPath -Algorithm SHA256).Hash.ToLowerInvariant()
    migrationSpecSha256 = (Get-FileHash -LiteralPath $specPath -Algorithm SHA256).Hash.ToLowerInvariant()
}

$parent = Split-Path -Parent $output
if (-not (Test-Path -LiteralPath $parent -PathType Container)) { [void](New-Item -ItemType Directory -Path $parent -Force) }
[IO.File]::WriteAllText($output, ($migrated | ConvertTo-Json -Depth 20), [Text.UTF8Encoding]::new($false))
Write-Output '[TEST_ENVIRONMENT_MIGRATION] PASS'
Write-Output "output: $output"
