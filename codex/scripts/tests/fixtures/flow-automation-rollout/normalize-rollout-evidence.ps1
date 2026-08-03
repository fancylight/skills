[CmdletBinding()]
param(
  [string]$EvidenceRoot = ''
)

$ErrorActionPreference = 'Stop'
if ([string]::IsNullOrWhiteSpace($EvidenceRoot)) {
  $repoRoot = $PSScriptRoot
  1..5 | ForEach-Object { $repoRoot = Split-Path -Parent $repoRoot }
  $EvidenceRoot = Join-Path $repoRoot 'docs\case-studies\evidence\flow-automation-wp7'
}
function Get-Hash([string]$Path) { return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant() }
function Normalize-Text([string]$Value) {
  $Value = $Value -replace '(?i)[A-Z]:\\\\Users\\\\[^\\\\]+\\\\AppData\\\\Local\\\\Temp', '<TEMP_ROOT>'
  return $Value -replace '(?i)[A-Z]:\\Users\\[^\\]+\\AppData\\Local\\Temp', '<TEMP_ROOT>'
}
function Write-Utf8([string]$Path, [string]$Value) { [IO.File]::WriteAllText($Path, $Value, [Text.UTF8Encoding]::new($false)) }

if (-not (Test-Path -LiteralPath $EvidenceRoot -PathType Container)) { throw "evidence root not found: $EvidenceRoot" }
foreach ($file in @(Get-ChildItem -LiteralPath $EvidenceRoot -File -Recurse | Where-Object { $_.Extension -in @('.json','.log','.md','.xml') })) {
  $raw = Get-Content -LiteralPath $file.FullName -Raw -Encoding UTF8
  $normalized = Normalize-Text $raw
  if ($normalized -ne $raw) { Write-Utf8 $file.FullName $normalized }
}

$deterministicRoot = Join-Path $EvidenceRoot 'deterministic'
$deterministicReportPath = Join-Path $deterministicRoot 'report.json'
$deterministic = Get-Content -LiteralPath $deterministicReportPath -Raw -Encoding UTF8 | ConvertFrom-Json
foreach ($test in @($deterministic.tests)) { $test.logHash = Get-Hash (Join-Path $deterministicRoot ([string]$test.log)) }
Write-Utf8 $deterministicReportPath ($deterministic | ConvertTo-Json -Depth 12)

$harnessRoot = Join-Path $EvidenceRoot 'harness'
$certificationPath = Join-Path $harnessRoot 'self-test\certification.json'
$certification = Get-Content -LiteralPath $certificationPath -Raw -Encoding UTF8 | ConvertFrom-Json
$certification.selfTestReportHash = Get-Hash (Join-Path $harnessRoot ([string]$certification.selfTestReportPath))
foreach ($item in @($certification.scenarioEvidence)) { $item.sha256 = Get-Hash (Join-Path $harnessRoot ([string]$item.path)) }
$certification | Add-Member -NotePropertyName evidenceNormalized -NotePropertyValue $true -Force
Write-Utf8 $certificationPath ($certification | ConvertTo-Json -Depth 12)

$gatesPath = Join-Path $EvidenceRoot 'environment-gates.json'
$gates = Get-Content -LiteralPath $gatesPath -Raw -Encoding UTF8 | ConvertFrom-Json
$gates.controlledHarnessForward | Add-Member -NotePropertyName sourceRevisionStatus -NotePropertyValue 'STALE_REQUIRES_REVALIDATION' -Force
$gates.controlledHarnessForward | Add-Member -NotePropertyName revalidationRequired -NotePropertyValue $true -Force
Write-Utf8 $gatesPath ($gates | ConvertTo-Json -Depth 12)
Write-Output 'rollout evidence normalized before deterministic and certification hashes were recomputed'
