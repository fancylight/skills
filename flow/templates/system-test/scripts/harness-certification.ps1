[CmdletBinding()]
param(
  [Parameter(Position=0, Mandatory=$true)]
  [ValidateSet('revision','verify','certify')]
  [string]$Command,
  [string]$HarnessRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path,
  [string]$CertificationPath = '',
  [string]$SelfTestReport = '',
  [string]$HarnessVersion = '1'
)

$ErrorActionPreference = 'Stop'
$HarnessRoot = (Resolve-Path -LiteralPath $HarnessRoot).Path
if ([string]::IsNullOrWhiteSpace($CertificationPath)) {
  $CertificationPath = Join-Path $HarnessRoot 'self-test\harness-certification.json'
}

function Get-Hash([string]$Path) {
  return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
}

function Get-HarnessFiles {
  $relativePaths = @(
    'scripts/system-test.ps1',
    'scripts/collect-failure-evidence.ps1',
    'scripts/harness-certification.ps1',
    'self-test/invoke-harness-self-test.ps1'
  )
  $items = @()
  foreach ($relativePath in $relativePaths) {
    $path = Join-Path $HarnessRoot ($relativePath.Replace('/', [IO.Path]::DirectorySeparatorChar))
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "Harness file missing: $relativePath" }
    $items += [pscustomobject]@{ path=$relativePath; sha256=(Get-Hash $path) }
  }
  return $items
}

function Get-HarnessRevision($Files) {
  $canonical = @($Files | Sort-Object path | ForEach-Object { "$($_.path)`n$($_.sha256)" }) -join "`n"
  $bytes = [Text.Encoding]::UTF8.GetBytes($canonical)
  $sha = [Security.Cryptography.SHA256]::Create()
  try { return (-join ($sha.ComputeHash($bytes) | ForEach-Object { $_.ToString('x2') })) }
  finally { $sha.Dispose() }
}

function Read-Certification {
  if (-not (Test-Path -LiteralPath $CertificationPath -PathType Leaf)) { throw "Harness certification missing: $CertificationPath" }
  try { return Get-Content -LiteralPath $CertificationPath -Raw -Encoding UTF8 | ConvertFrom-Json }
  catch { throw "Harness certification is not valid JSON: $CertificationPath" }
}

function Assert-Certification {
  $certification = Read-Certification
  $files = @(Get-HarnessFiles)
  $revision = Get-HarnessRevision $files
  if ($certification.schemaVersion -ne 1 -or $certification.result -ne 'PASS') { throw 'Harness certification is not a structured PASS.' }
  if ($certification.harnessRevision -ne $revision) { throw 'Harness certification is stale for the current harness revision.' }
  if ([string]::IsNullOrWhiteSpace([string]$certification.harnessVersion)) { throw 'Harness certification version is missing.' }
  $reported = @($certification.files)
  if ($reported.Count -ne $files.Count) { throw 'Harness certification file set differs from the controlled harness file set.' }
  foreach ($file in $files) {
    $match = @($reported | Where-Object { $_.path -eq $file.path })
    if ($match.Count -ne 1 -or $match[0].sha256 -ne $file.sha256) { throw "Harness certification file hash mismatch: $($file.path)" }
  }
  Write-Output '[HARNESS_CERTIFICATION] PASS'
  Write-Output "harness_revision: $revision"
}

$files = @(Get-HarnessFiles)
$revision = Get-HarnessRevision $files
switch ($Command) {
  'revision' {
    Write-Output $revision
  }
  'verify' {
    Assert-Certification
  }
  'certify' {
    if ([string]::IsNullOrWhiteSpace($SelfTestReport) -or -not (Test-Path -LiteralPath $SelfTestReport -PathType Leaf)) { throw 'A harness self-test report is required for certification.' }
    try { $report = Get-Content -LiteralPath $SelfTestReport -Raw -Encoding UTF8 | ConvertFrom-Json }
    catch { throw 'Harness self-test report is not valid JSON.' }
    if ($report.result -ne 'PASS' -or $report.harnessRevision -ne $revision -or @($report.scenarios).Count -lt 12 -or @($report.scenarios | Where-Object { $_.result -ne 'PASS' }).Count -gt 0) {
      throw 'Harness self-test report is incomplete, failed, or bound to another revision.'
    }
    $directory = Split-Path -Parent $CertificationPath
    if (-not (Test-Path -LiteralPath $directory)) { [void](New-Item -ItemType Directory -Path $directory -Force) }
    $certification = [ordered]@{
      schemaVersion = 1
      result = 'PASS'
      harnessVersion = $HarnessVersion
      harnessRevision = $revision
      selfTestReportHash = Get-Hash $SelfTestReport
      files = $files
      certifiedAt = [DateTime]::UtcNow.ToString('o')
    }
    [IO.File]::WriteAllText($CertificationPath, ($certification | ConvertTo-Json -Depth 8), [Text.UTF8Encoding]::new($false))
    Assert-Certification
  }
}
