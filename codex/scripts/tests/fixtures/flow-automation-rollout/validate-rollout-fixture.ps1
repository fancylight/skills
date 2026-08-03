$ErrorActionPreference = 'Stop'
$path = Join-Path $PSScriptRoot 'cases.json'
$cases = Get-Content -LiteralPath $path -Raw -Encoding UTF8 | ConvertFrom-Json
if ($cases.schemaVersion -ne 1) { throw 'unsupported rollout fixture schema' }
if (@($cases.batchB).Count -ne 11) { throw 'incident replay matrix must contain 11 cases' }
if (@($cases.batchC).Count -ne 5) { throw 'forward matrix must contain 5 cases' }
if (@($cases.batchD).Count -ne 3) { throw 'shadow matrix must contain 3 cases' }
if (@($cases.batchE).Count -ne 7) { throw 'goal fault matrix must contain 7 cases' }
foreach ($batch in @($cases.batchB, $cases.batchC, $cases.batchD, $cases.batchE)) {
  $ids = @($batch | ForEach-Object { $_.id })
  if (@($ids | Sort-Object -Unique).Count -ne $ids.Count) { throw 'fixture IDs must be unique within each batch' }
}
foreach ($property in $cases.batchA.PSObject.Properties) {
  $testPath = Join-Path (Split-Path -Parent (Split-Path -Parent (Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSScriptRoot))))) $property.Value
  if (-not (Test-Path -LiteralPath $testPath -PathType Leaf)) { throw "missing deterministic test: $($property.Value)" }
}
if ([string]::IsNullOrWhiteSpace([string]$cases.rollback)) { throw 'rollback description is required' }
$raw = Get-Content -LiteralPath $path -Raw -Encoding UTF8
if ($raw -match 'guanghuo|overseas-roster|glm-system-test|worker-service|31cc73b|b4bdb667') { throw 'rollout fixture leaked a historical case identifier' }
Write-Output 'flow automation rollout fixture validated'
