[CmdletBinding()]
param(
  [Parameter(Position=0, Mandatory=$true)]
  [ValidateSet('doctor','up','run','down','cleanup')]
  [string]$Command,
  [Parameter(Mandatory=$true)]
  [string]$Change,
  [ValidateSet('ui-mock','api','e2e','cdc','all')]
  [string]$Suite = 'all',
  [ValidateSet('orchestrated','standalone')]
  [string]$ExecutionMode = 'standalone',
  [string]$EnvFile = '.env.local',
  [string]$OrchRoot = '',
  [string]$HarnessCertificationPath = '',
  [string]$HarnessAdapterPath = '',
  [string]$HarnessSelfTestScenario = '',
  [string]$HarnessSelfTestToken = '',
  [string]$StructuredResultPath = '',
  [switch]$HarnessSelfTest
)

$ErrorActionPreference = 'Stop'
$TestRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
if ([string]::IsNullOrWhiteSpace($OrchRoot)) {
  $OrchRoot = [Environment]::GetEnvironmentVariable('FLOW_ORCH_ROOT')
}
if ([string]::IsNullOrWhiteSpace($OrchRoot)) {
  $OrchRoot = (Resolve-Path (Join-Path $TestRoot '..')).Path
} else {
  $OrchRoot = (Resolve-Path $OrchRoot).Path
}
$RuntimeDir = Join-Path $TestRoot ".runtime\$Change"
$LogDir = Join-Path $RuntimeDir 'logs'
$StateFile = Join-Path $RuntimeDir 'state.json'
$SeedMarker = Join-Path $RuntimeDir 'data-seeded'
$FixtureMainClass = 'com.flow.systemtest.FixtureTool'
$ComposeFile = Join-Path $TestRoot 'infra\compose\system-test.yml'
$HarnessCertifier = Join-Path $PSScriptRoot 'harness-certification.ps1'

function Test-PathWithin([string]$Child, [string]$Parent) {
  $childPath = [IO.Path]::GetFullPath($Child)
  $parentPath = [IO.Path]::GetFullPath($Parent).TrimEnd('\','/')
  return $childPath.StartsWith($parentPath + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)
}

function Get-StringHash([string]$Value) {
  $sha = [Security.Cryptography.SHA256]::Create()
  try { return -join ($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($Value)) | ForEach-Object { $_.ToString('x2') }) }
  finally { $sha.Dispose() }
}

if ($HarnessSelfTest) {
  $expectedChange = '__flow_internal_harness_self_test__-' + $HarnessSelfTestScenario
  if ($ExecutionMode -ne 'standalone') { throw '[TEST_HARNESS] orchestrated mode cannot enable harness self-test' }
  if ([string]::IsNullOrWhiteSpace($HarnessSelfTestScenario) -or $Change -ne $expectedChange) { throw '[TEST_HARNESS] self-test requires its reserved internal change name' }
  $canonicalAdapter = [IO.Path]::GetFullPath((Join-Path $TestRoot 'self-test\harness-self-test-adapter.ps1'))
  $actualAdapter = if ([string]::IsNullOrWhiteSpace($HarnessAdapterPath)) { '' } else { [IO.Path]::GetFullPath($HarnessAdapterPath) }
  if ($actualAdapter -ne $canonicalAdapter -or -not (Test-Path -LiteralPath $canonicalAdapter -PathType Leaf)) { throw '[TEST_HARNESS] self-test adapter must be the exact canonical built-in adapter' }
  $tempRoot = [IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\','/')
  $markerPath = Join-Path $TestRoot '.harness-self-test-isolation.json'
  if (-not (Test-PathWithin $TestRoot $tempRoot) -or (Test-Path -LiteralPath (Join-Path $TestRoot '.git')) -or -not (Test-Path -LiteralPath $markerPath -PathType Leaf)) { throw '[TEST_HARNESS] self-test must run only in an isolated temporary harness copy' }
  try { $marker = Get-Content -LiteralPath $markerPath -Raw -Encoding UTF8 | ConvertFrom-Json } catch { throw '[TEST_HARNESS] self-test isolation marker is invalid' }
  if ($marker.schemaVersion -ne 1 -or $marker.harnessRoot -ne [IO.Path]::GetFullPath($TestRoot) -or [string]::IsNullOrWhiteSpace($HarnessSelfTestToken) -or $marker.tokenSha256 -ne (Get-StringHash $HarnessSelfTestToken)) { throw '[TEST_HARNESS] self-test isolation token is missing or invalid' }
  $manifestOutput = @(& $HarnessCertifier manifest -HarnessRoot $TestRoot 2>&1)
  if ($LASTEXITCODE -ne 0) { throw '[TEST_HARNESS] controlled harness manifest is unavailable' }
  try { $manifest = ($manifestOutput -join "`n") | ConvertFrom-Json } catch { throw '[TEST_HARNESS] controlled harness manifest is invalid' }
  $adapterRecord = @($manifest.files | Where-Object { $_.path -eq 'self-test/harness-self-test-adapter.ps1' })
  if ($adapterRecord.Count -ne 1 -or $manifest.harnessRevision -ne $marker.harnessRevision -or (Get-FileHash -LiteralPath $canonicalAdapter -Algorithm SHA256).Hash.ToLowerInvariant() -ne [string]$adapterRecord[0].sha256) { throw '[TEST_HARNESS] self-test adapter is not bound to the current harness revision' }
  if (-not [string]::IsNullOrWhiteSpace($HarnessCertificationPath)) { throw '[TEST_HARNESS] self-test cannot accept a business harness certification' }
} elseif (-not [string]::IsNullOrWhiteSpace($HarnessAdapterPath) -or -not [string]::IsNullOrWhiteSpace($HarnessSelfTestScenario) -or -not [string]::IsNullOrWhiteSpace($HarnessSelfTestToken)) {
  throw '[TEST_HARNESS] adapter injection is allowed only in explicit harness self-test mode'
}

function Invoke-HarnessAdapter([string]$Operation, $Payload = $null) {
  if ([string]::IsNullOrWhiteSpace($HarnessAdapterPath)) { return $null }
  $payloadJson = if ($null -eq $Payload) { '{}' } else { $Payload | ConvertTo-Json -Depth 8 -Compress }
  $payloadBase64 = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($payloadJson))
  $output = @(& powershell.exe -NoProfile -ExecutionPolicy Bypass -File $HarnessAdapterPath -Operation $Operation -Scenario $HarnessSelfTestScenario -TestRoot $TestRoot -Change $Change -RuntimeDir $RuntimeDir -PayloadBase64 $payloadBase64 2>&1)
  $exitCode = $LASTEXITCODE
  if ($exitCode -ne 0) {
    $message = ($output | ForEach-Object { [string]$_ } | Where-Object { $_ } | Select-Object -Last 1)
    if ([string]::IsNullOrWhiteSpace($message)) { $message = "[TEST_HARNESS] adapter operation failed: $Operation" }
    throw $message
  }
  return $output
}

function Assert-HarnessCertification {
  if (-not (Test-Path -LiteralPath $HarnessCertifier -PathType Leaf)) { throw '[TEST_HARNESS] certification verifier is missing' }
  $path = if ([string]::IsNullOrWhiteSpace($HarnessCertificationPath)) { Join-Path $TestRoot 'self-test\harness-certification.json' } else { $HarnessCertificationPath }
  & $HarnessCertifier verify -HarnessRoot $TestRoot -CertificationPath $path | Out-Null
  if ($LASTEXITCODE -ne 0) { throw '[TEST_HARNESS] harness revision is not certified' }
}

function Import-DotEnv([string]$Path) {
  if (-not (Test-Path $Path)) { return }
  foreach ($line in Get-Content $Path) {
    if ($line -match '^\s*#' -or $line -notmatch '=') { continue }
    $pair = $line -split '=', 2
    [Environment]::SetEnvironmentVariable($pair[0].Trim(), $pair[1].Trim(), 'Process')
  }
}

function Expand-Value([string]$Value) {
  if ($null -eq $Value) { return $null }
  $Value.Replace('${TEST_ROOT}', $TestRoot).Replace('${ORCH_ROOT}', $OrchRoot).Replace('${GLM_ROOT}', $OrchRoot)
}

function Get-Manifest {
  $path = Join-Path $TestRoot "changes\$Change\manifest.yaml"
  if (-not (Test-Path $path)) { throw "Manifest not found: $path" }
  return Get-Content $path -Raw | ConvertFrom-Json
}

function Test-Tcp([string]$HostName, [int]$Port, [int]$TimeoutMs=1200) {
  $client = New-Object System.Net.Sockets.TcpClient
  try {
    $result = $client.BeginConnect($HostName, $Port, $null, $null)
    return $result.AsyncWaitHandle.WaitOne($TimeoutMs) -and $client.Connected
  } catch { return $false } finally { $client.Dispose() }
}

function Test-Http([string]$Url) {
  try { Invoke-WebRequest -UseBasicParsing -Uri $Url -TimeoutSec 3 | Out-Null; return $true } catch { return $false }
}

function Invoke-Doctor($Manifest, [string[]]$Suites) {
  $errors = New-Object System.Collections.Generic.List[string]
  if (-not $Manifest.configuration -or [string]::IsNullOrWhiteSpace([string]$Manifest.configuration.source) -or [string]::IsNullOrWhiteSpace([string]$Manifest.configuration.ownership)) {
    $errors.Add('manifest configuration source and ownership are required')
  } else {
    if ([string]$Manifest.configuration.ownership -notin @('human','harness')) { $errors.Add('configuration ownership must be human or harness') }
    if ([IO.Path]::GetFullPath((Join-Path $TestRoot $EnvFile)) -ne [IO.Path]::GetFullPath((Join-Path $TestRoot ([string]$Manifest.configuration.source)))) {
      $errors.Add('requested EnvFile differs from the manifest configuration source')
    }
    if (@($Manifest.configuration.requiredEndpoints).Count -eq 0 -or $null -eq $Manifest.configuration.probes) { $errors.Add('configuration requiredEndpoints and probes are required') }
  }
  if (-not [string]::IsNullOrWhiteSpace($HarnessAdapterPath)) {
    Invoke-HarnessAdapter 'doctor' @{ suites=$Suites; ownership=[string]$Manifest.configuration.ownership } | Out-Null
    Write-Host "doctor passed through controlled harness adapter (orchRoot=$OrchRoot)"
    return
  }
  foreach ($tool in @('java.exe','mvn.cmd')) {
    if (-not (Get-Command $tool -ErrorAction SilentlyContinue)) { $errors.Add("tool not found: $tool") }
  }
  if ($Manifest.composeProfiles -and @($Manifest.composeProfiles).Count -gt 0) {
    if (-not (Get-Command docker.exe -ErrorAction SilentlyContinue)) { $errors.Add('tool not found: docker.exe (required by composeProfiles)') }
  }
  $requiredEnv = New-Object System.Collections.Generic.HashSet[string]
  foreach ($suiteName in $Suites) {
    $property = $Manifest.requiredEnvBySuite.PSObject.Properties[$suiteName]
    if ($property) { foreach ($name in $property.Value) { [void]$requiredEnv.Add([string]$name) } }
  }
  foreach ($name in $requiredEnv) {
    $value = [Environment]::GetEnvironmentVariable($name)
    if ([string]::IsNullOrWhiteSpace($value)) { $errors.Add("missing env: $name") }
    elseif (($name.EndsWith('_EXE') -or $name.EndsWith('_CLI')) -and -not (Test-Path $value)) { $errors.Add("file not found for $name`: $value") }
  }
  if (-not [string]::IsNullOrWhiteSpace($env:NODE14_EXE) -and (Test-Path $env:NODE14_EXE)) {
    $version = & $env:NODE14_EXE --version
    if ($version -notmatch '^v14\.') { $errors.Add("NODE14_EXE must be v14.x, actual: $version") }
  }
  if (-not [string]::IsNullOrWhiteSpace($env:NODE24_EXE) -and (Test-Path $env:NODE24_EXE)) {
    $version = & $env:NODE24_EXE --version
    if ($version -notmatch '^v24\.') { $errors.Add("NODE24_EXE must be v24.x, actual: $version") }
  }
  if ($Manifest.dependencies) {
    foreach ($dep in $Manifest.dependencies) {
      if (@($dep.suites | Where-Object { $Suites -contains $_ }).Count -eq 0) { continue }
      $ok = $false
      if ($dep.kind -eq 'tcp') {
        $ok = Test-Tcp ([Environment]::GetEnvironmentVariable($dep.hostEnv)) ([int][Environment]::GetEnvironmentVariable($dep.portEnv))
      } elseif ($dep.kind -eq 'tcpAddress') {
        $parts = ([Environment]::GetEnvironmentVariable($dep.addressEnv) -split ',')[0] -split ':'
        $ok = $parts.Length -eq 2 -and (Test-Tcp $parts[0] ([int]$parts[1]))
      } elseif ($dep.kind -eq 'http') {
        $ok = Test-Http ([Environment]::GetEnvironmentVariable($dep.urlEnv))
      }
      if (-not $ok) { $errors.Add("dependency unavailable: $($dep.name)") }
    }
  }
  if ($errors.Count -gt 0) {
    $errors | ForEach-Object { Write-Host "BLOCKER: $_" -ForegroundColor Red }
    $ownership = if ($Manifest.configuration -and $Manifest.configuration.ownership) { [string]$Manifest.configuration.ownership } else { 'human' }
    if ($ownership -eq 'human') { throw "[TEST_CONFIGURATION] BLOCKED; STOP_AWAIT_HUMAN_CONFIGURATION; doctor failed with $($errors.Count) blocker(s)" }
    throw "[TEST_HARNESS] platform-owned configuration failed with $($errors.Count) blocker(s)"
  }
  Write-Host "doctor passed: environment ready (orchRoot=$OrchRoot)"
}

function Start-Compose([string[]]$Profiles) {
  if (-not $Profiles -or $Profiles.Count -eq 0) { return }
  if (-not (Test-Path $ComposeFile)) {
    throw "composeProfiles declared but missing: $ComposeFile (add infra or clear composeProfiles)"
  }
  foreach ($profile in $Profiles) {
    $oldPreference = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    & docker compose -f $ComposeFile --profile $profile up -d 2>&1 | Out-Null
    $ErrorActionPreference = $oldPreference
    if ($LASTEXITCODE -ne 0) { throw "docker compose profile failed: $profile" }
  }
}

function Start-ManagedServices($Manifest, [string[]]$Suites) {
  New-Item -ItemType Directory -Force $LogDir | Out-Null
  $state = @{ processes = @(); composeProfiles = @($Manifest.composeProfiles) }
  $state | ConvertTo-Json -Depth 5 | Set-Content -Encoding UTF8 $StateFile
  if (-not $Manifest.services) { return }
  foreach ($service in $Manifest.services) {
    if (@($service.suites | Where-Object { $Suites -contains $_ }).Count -eq 0) { continue }
    if (Test-Tcp '127.0.0.1' ([int]$service.port)) {
      if (-not $service.allowTcpHealth -and -not (Test-Http $service.healthUrl)) { throw "$($service.name) port $($service.port) is occupied but health check failed" }
      Write-Host "$($service.name) already listening on $($service.port); treating as external"
      continue
    }
    $exe = if ($service.executableEnv) { [Environment]::GetEnvironmentVariable($service.executableEnv) } else { $service.executable }
    if ([string]::IsNullOrWhiteSpace($exe)) { throw "executable missing for $($service.name)" }
    $argumentList = New-Object System.Collections.Generic.List[string]
    if ($service.argumentsEnvPrefix) { $argumentList.Add([Environment]::GetEnvironmentVariable($service.argumentsEnvPrefix)) }
    foreach ($arg in $service.arguments) { $argumentList.Add((Expand-Value $arg)) }
    if ($service.environment) {
      foreach ($property in $service.environment.PSObject.Properties) {
        [Environment]::SetEnvironmentVariable($property.Name, (Expand-Value ([string]$property.Value)), 'Process')
      }
    }
    $stdout = Join-Path $LogDir "$($service.name).out.log"
    $stderr = Join-Path $LogDir "$($service.name).err.log"
    $process = Start-Process -FilePath $exe -ArgumentList $argumentList -WorkingDirectory (Expand-Value $service.workingDirectory) -RedirectStandardOutput $stdout -RedirectStandardError $stderr -PassThru -WindowStyle Hidden
    $state.processes += @{ name=$service.name; pid=$process.Id; port=$service.port }
    $state | ConvertTo-Json -Depth 5 | Set-Content -Encoding UTF8 $StateFile
    $ready = $false
    for ($i=0; $i -lt 240; $i++) {
      if ($process.HasExited) { throw "$($service.name) exited during startup; see $stderr" }
      if ((Test-Http $service.healthUrl) -or (Test-Tcp '127.0.0.1' ([int]$service.port))) { $ready = $true; break }
      Start-Sleep -Seconds 1
    }
    if (-not $ready) { throw "$($service.name) health check timed out; see $stdout" }
  }
}

function Invoke-Up($Manifest, [string[]]$Suites) {
  if (-not [string]::IsNullOrWhiteSpace($HarnessAdapterPath)) {
    Invoke-HarnessAdapter 'up' @{ suites=$Suites } | Out-Null
    return
  }
  Start-Compose @($Manifest.composeProfiles)
  Start-ManagedServices $Manifest $Suites
}

function Invoke-Data([string]$RelativeOrAbsoluteSql, [string]$Database = '') {
  $sqlPath = if ([System.IO.Path]::IsPathRooted($RelativeOrAbsoluteSql)) {
    $RelativeOrAbsoluteSql
  } else {
    Join-Path $TestRoot (Expand-Value $RelativeOrAbsoluteSql)
  }
  if (-not (Test-Path $sqlPath)) { throw "SQL fixture not found: $sqlPath" }
  $db = if ([string]::IsNullOrWhiteSpace($Database)) { $env:MYSQL_DATABASE } else { $Database }
  if ([string]::IsNullOrWhiteSpace($db)) { throw 'MYSQL_DATABASE is required for SQL fixtures (or pass database in manifest seed item)' }
  Write-Host "seed/cleanup: $sqlPath (database=$db)"
  $pom = Join-Path $TestRoot 'pom.xml'
  & mvn.cmd -q -f $pom -pl test-support `
    "-Dexec.mainClass=$FixtureMainClass" `
    "-Dexec.args=$sqlPath $db" `
    exec:java
  if ($LASTEXITCODE -ne 0) { throw "SQL fixture failed: $sqlPath" }
}

function Invoke-Seeds($Manifest) {
  if (-not $Manifest.data) { return }
  if (-not [string]::IsNullOrWhiteSpace($HarnessAdapterPath)) {
    Invoke-HarnessAdapter 'seed' $Manifest.data | Out-Null
    return
  }
  if ($Manifest.data.PSObject.Properties.Name -contains 'seeds' -and $Manifest.data.seeds) {
    foreach ($item in @($Manifest.data.seeds)) {
      if ($item -is [string]) {
        Invoke-Data (Expand-Value $item)
      } else {
        $file = Expand-Value ([string]$item.file)
        $database = if ($item.PSObject.Properties.Name -contains 'database') { [string]$item.database } else { '' }
        Invoke-Data $file $database
      }
    }
    return
  }
  if ($Manifest.data.seed) {
    Invoke-Data (Expand-Value ([string]$Manifest.data.seed))
  }
}

function Invoke-WireMockReload() {
  if (-not [string]::IsNullOrWhiteSpace($HarnessAdapterPath)) {
    Invoke-HarnessAdapter 'wiremock-reload' @{} | Out-Null
    return
  }
  $base = $env:WIREMOCK_ADMIN_BASE
  if ([string]::IsNullOrWhiteSpace($base)) {
    $wm = $env:WIREMOCK_BASE_URL
    if ([string]::IsNullOrWhiteSpace($wm)) { return }
    $base = ($wm -replace '/__admin/.*$', '') + '/__admin'
  }
  $mapDir = Join-Path $TestRoot 'infra\wiremock\mappings'
  if (-not (Test-Path $mapDir)) { return }
  try {
    Invoke-RestMethod -Method POST "$base/mappings/reset" -TimeoutSec 3 | Out-Null
  } catch {
    Write-Host "wiremock reload skipped (admin unreachable): $($_.Exception.Message)"
    return
  }
  Get-ChildItem $mapDir -Filter *.json | ForEach-Object {
    $body = Get-Content $_.FullName -Raw -Encoding UTF8
    Invoke-RestMethod -Method POST "$base/mappings" -ContentType 'application/json; charset=utf-8' -Body $body -TimeoutSec 5 | Out-Null
  }
  Write-Host "wiremock mappings reloaded from $mapDir"
}

function Invoke-CleanupData($Manifest) {
  if (-not $Manifest.data) { return }
  if (-not [string]::IsNullOrWhiteSpace($HarnessAdapterPath)) {
    Invoke-HarnessAdapter 'cleanup' $Manifest.data | Out-Null
    return
  }
  if ($Manifest.data.PSObject.Properties.Name -contains 'cleanups' -and $Manifest.data.cleanups) {
    foreach ($item in @($Manifest.data.cleanups)) {
      if ($item -is [string]) {
        Invoke-Data (Expand-Value $item)
      } else {
        $file = Expand-Value ([string]$item.file)
        $database = if ($item.PSObject.Properties.Name -contains 'database') { [string]$item.database } else { '' }
        Invoke-Data $file $database
      }
    }
    return
  }
  if ($Manifest.data.cleanup) {
    Invoke-Data (Expand-Value ([string]$Manifest.data.cleanup))
  }
}

function Invoke-Suite([string]$Name, $Manifest) {
  if ($Name -eq 'ui-mock' -or $Name -eq 'e2e') {
    $uiDir = Join-Path $TestRoot 'ui-tests'
    if (-not (Test-Path $uiDir)) { throw "ui-tests/ missing; cannot run suite $Name" }
    if ([string]::IsNullOrWhiteSpace($env:NODE24_EXE)) { throw 'NODE24_EXE required for ui-mock/e2e' }
    Push-Location $uiDir
    try {
      $playwright = Join-Path $uiDir 'node_modules\@playwright\test\cli.js'
      if (-not (Test-Path $playwright)) { throw 'Playwright dependencies are not installed; run npm install in ui-tests' }
      & $env:NODE24_EXE $playwright test --project=$Name
      if ($LASTEXITCODE -ne 0) { throw "$Name suite failed" }
    } finally { Pop-Location }
  } elseif ($Name -eq 'api') {
    $mvnArgs = @('-f', (Join-Path $TestRoot 'pom.xml'), '-pl', 'backend-tests', '-am', 'test')
    $filter = $null
    if ($Manifest.PSObject.Properties.Name -contains 'apiTestFilter' -and -not [string]::IsNullOrWhiteSpace([string]$Manifest.apiTestFilter)) {
      $filter = [string]$Manifest.apiTestFilter
    }
    if (-not [string]::IsNullOrWhiteSpace($filter)) {
      $mvnArgs += "-Dtest=$filter", '-Dsurefire.failIfNoSpecifiedTests=false'
      Write-Host "api suite filtered by apiTestFilter: $filter"
    } else {
      Write-Host 'api suite: no apiTestFilter; running all backend-tests'
    }
    if (-not [string]::IsNullOrWhiteSpace($HarnessAdapterPath)) {
      Invoke-HarnessAdapter 'suite' @{ name=$Name; arguments=$mvnArgs } | Out-Null
    } else {
      & mvn.cmd @mvnArgs
      if ($LASTEXITCODE -ne 0) { throw '[TEST_HARNESS] Maven API suite failed' }
    }
  } elseif ($Name -eq 'cdc') {
    $cdc = Join-Path $TestRoot 'scripts\cdc-smoke.ps1'
    if (-not (Test-Path $cdc)) { throw 'scripts/cdc-smoke.ps1 missing; cannot run cdc suite' }
    & $cdc -EnvFile $EnvFile
    if ($LASTEXITCODE -ne 0) { throw 'cdc suite failed' }
  }
}

function Get-GitRevision([string]$Path) {
  try {
    $revision = (& git -C $Path rev-parse HEAD 2>$null).Trim()
    if (-not [string]::IsNullOrWhiteSpace($revision)) { return $revision }
  } catch { }
  return 'unavailable'
}

function Get-ApiCounts {
  $reportDir = Join-Path $TestRoot 'backend-tests\target\surefire-reports'
  $reports = @(Get-ChildItem -LiteralPath $reportDir -Filter 'TEST-*.xml' -File -ErrorAction SilentlyContinue)
  if ($reports.Count -eq 0) { throw "Surefire raw reports missing: $reportDir" }
  $tests = 0; $failed = 0; $skipped = 0
  foreach ($report in $reports) {
    [xml]$xml = Get-Content -LiteralPath $report.FullName -Raw -Encoding UTF8
    $tests += [int]$xml.testsuite.tests
    $failed += [int]$xml.testsuite.failures + [int]$xml.testsuite.errors
    $skipped += [int]$xml.testsuite.skipped
  }
  return @{ passed = $tests - $failed - $skipped; failed = $failed; skipped = $skipped; raw = $reportDir }
}

function Reset-ApiReports {
  $reportDir = Join-Path $TestRoot 'backend-tests\target\surefire-reports'
  if (Test-Path $reportDir) {
    Get-ChildItem -LiteralPath $reportDir -Filter 'TEST-*.xml' -File -ErrorAction SilentlyContinue |
      Remove-Item -Force
  }
}

function Assert-RequiredEvidence($Manifest) {
  foreach ($relativePath in @($Manifest.requiredEvidence)) {
    $path = Join-Path $TestRoot (Expand-Value ([string]$relativePath))
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "[TEST_HARNESS] required raw evidence missing: $relativePath" }
  }
}

function Get-FailureClassification([string]$Message, [string]$Status) {
  if ($Status -eq 'PASS') { return 'NONE' }
  if ($Message -match '^\[TEST_CONFIGURATION\]') { return 'CONFIG_INFRA' }
  if ($Message -match '^\[FIXTURE_ASSERTION\]') { return 'FIXTURE_ASSERTION' }
  if ($Message -match '^\[SUT_BUSINESS\]') { return 'SUT_BUSINESS' }
  if ($Message -match '^\[DATA_SCHEMA_CONTRACT\]') { return 'DATA_SCHEMA_CONTRACT' }
  return 'TEST_HARNESS'
}

function Write-Summary([string]$Status, [string[]]$Suites, [hashtable]$Counts, [string]$Message='', [bool]$CleanupFailed=$false) {
  $evidenceDir = Join-Path $TestRoot "changes\$Change\evidence"
  New-Item -ItemType Directory -Force $evidenceDir | Out-Null
  $summary = Join-Path $evidenceDir 'summary.md'
  $retained = if ($CleanupFailed) { 'true' } else { 'false' }
  $cleanup = if ($CleanupFailed) { ".\scripts\system-test.ps1 cleanup -Change $Change" } else { 'none' }
  $manifestPath = Join-Path $TestRoot "changes\$Change\manifest.yaml"
  $manifestHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $manifestPath).Hash
  $testRevision = Get-GitRevision $TestRoot
  $businessRevisions = if ($Manifest.PSObject.Properties.Name -contains 'businessRevisions') { $Manifest.businessRevisions | ConvertTo-Json -Compress } else { 'not-declared' }
  $summaryMessage = if ($Status -eq 'FAIL') { 'see evidence/current/failure-report.md' } else { 'none' }
  $classification = Get-FailureClassification $Message $Status
  @"
# System Test Result

- status: $Status
- change_name: $Change
- execution_mode: $ExecutionMode
- flow_completed: false
- suites: $($Suites -join ',')
- generated_at: $([DateTime]::Now.ToString('s'))
- manifest_hash: $manifestHash
- test_revision: $testRevision
- business_revisions: $businessRevisions
- raw_reports: $($Counts.raw)
- passed: $($Counts.passed)
- failed: $($Counts.failed)
- skipped: $($Counts.skipped)
- classification: $classification
- retained_state: $retained
- cleanup_command: $cleanup
- message: $summaryMessage
"@ | Set-Content -Encoding UTF8 $summary
  $collector = Join-Path $PSScriptRoot 'collect-failure-evidence.ps1'
  if (-not (Test-Path -LiteralPath $collector)) { throw "Failure evidence collector missing: $collector" }
  $collectorArguments = @('-NoProfile','-ExecutionPolicy','Bypass','-File',$collector,'-TestRoot',$TestRoot,'-Change',$Change,'-Status',$Status,'-Suites') + @($Suites)
  if (-not [string]::IsNullOrEmpty($Message)) { $collectorArguments += '-Message', $Message }
  $collectorArguments += '-Passed', $Counts.passed, '-Failed', $Counts.failed, '-Skipped', $Counts.skipped
  & powershell.exe @collectorArguments
  if ($LASTEXITCODE -ne 0) { throw 'Failure evidence collection failed.' }
  Write-Host "[SYSTEM_TEST_RESULT] $Status"
  Write-Host "change_name: $Change"
  Write-Host "execution_mode: $ExecutionMode"
  Write-Host 'flow_completed: false'
  Write-Host "suites: $($Suites -join ',')"
  Write-Host "passed: $($Counts.passed)"
  Write-Host "failed: $($Counts.failed)"
  Write-Host "skipped: $($Counts.skipped)"
  Write-Host "evidence: $summary"
  Write-Host "retained_state: $retained"
  Write-Host "cleanup_command: $cleanup"
  Write-Host "classification: $classification"
  $indexPath = Join-Path $evidenceDir 'current\index.md'
  if (-not [string]::IsNullOrWhiteSpace($StructuredResultPath)) {
    $resultDirectory = Split-Path -Parent $StructuredResultPath
    if (-not (Test-Path -LiteralPath $resultDirectory)) { [void](New-Item -ItemType Directory -Path $resultDirectory -Force) }
    $phase = if ($Status -eq 'PASS') { 'RUNNER_COMPLETED' } elseif ($Status -eq 'BLOCKED') { 'RUNNER_BLOCKED' } else { 'RUNNER_FAILED' }
    $structured = [ordered]@{
      schemaVersion=1; scenario=$HarnessSelfTestScenario; status=$Status; exitCode=$(if ($Status -eq 'PASS') { 0 } else { 1 })
      phase=$phase; classification=$classification; rawEvidencePath=$indexPath
      cleanup=[ordered]@{ attempted=$true; succeeded=(-not $CleanupFailed); retainedState=$CleanupFailed; command=$cleanup }
      counts=[ordered]@{ passed=$Counts.passed; failed=$Counts.failed; skipped=$Counts.skipped; raw=$Counts.raw }
    }
    [IO.File]::WriteAllText($StructuredResultPath, ($structured | ConvertTo-Json -Depth 8), [Text.UTF8Encoding]::new($false))
  }
}

function Invoke-ReliableCleanup($Manifest) {
  $errors = @()
  try {
    if (Test-Path $SeedMarker) { Invoke-CleanupData $Manifest; Remove-Item $SeedMarker -Force }
  } catch { $errors += $_.Exception.Message }
  try { Invoke-Down } catch { $errors += $_.Exception.Message }
  if ($errors.Count -gt 0) { throw "[TEST_HARNESS] cleanup failed: $($errors -join '; ')" }
}

function Invoke-Down {
  if (Test-Path $StateFile) {
    $state = Get-Content $StateFile -Raw | ConvertFrom-Json
    foreach ($item in $state.processes) {
      $process = Get-Process -Id $item.pid -ErrorAction SilentlyContinue
      if ($process) { Stop-Process -Id $item.pid -Force }
    }
    if ($state.composeProfiles -and (Test-Path $ComposeFile)) {
      foreach ($profile in $state.composeProfiles) {
        & docker compose -f $ComposeFile --profile $profile down
      }
    }
    Remove-Item $StateFile -Force
  }
}

$manifest = Get-Manifest
if (-not $manifest.configuration -or [string]::IsNullOrWhiteSpace([string]$manifest.configuration.source)) {
  throw '[TEST_CONFIGURATION] BLOCKED; STOP_AWAIT_HUMAN_CONFIGURATION; manifest configuration source is missing'
}
$declaredConfigurationSource = [IO.Path]::GetFullPath((Join-Path $TestRoot ([string]$manifest.configuration.source)))
$requestedConfigurationSource = [IO.Path]::GetFullPath((Join-Path $TestRoot $EnvFile))
if ($declaredConfigurationSource -ne $requestedConfigurationSource) {
  throw '[TEST_CONFIGURATION] BLOCKED; STOP_AWAIT_HUMAN_CONFIGURATION; requested configuration source differs from manifest'
}
Import-DotEnv $declaredConfigurationSource
$requestedSuites = if ($Suite -eq 'all') {
  if ($manifest.defaultSuites) { @($manifest.defaultSuites) } else { @('api') }
} else { @($Suite) }

switch ($Command) {
  'doctor' { Invoke-Doctor $manifest $requestedSuites }
  'up' {
    if ($manifest.composeProfiles) { Start-Compose @($manifest.composeProfiles); Start-Sleep -Seconds 2 }
    Invoke-Doctor $manifest $requestedSuites
    Invoke-Up $manifest $requestedSuites
  }
  'down' { Invoke-Down }
  'cleanup' {
    if (Test-Path $SeedMarker) { Invoke-CleanupData $manifest; Remove-Item $SeedMarker -Force }
    Invoke-Down
  }
  'run' {
    $suites = $requestedSuites
    $counts = @{ passed = 0; failed = 0; skipped = 0; raw = 'not-applicable' }
    try {
      if (-not $HarnessSelfTest) { Assert-HarnessCertification }
      if ($suites.Count -eq 1 -and $suites[0] -eq 'cdc') {
        Invoke-Suite 'cdc' $manifest
      } else {
        if ($manifest.composeProfiles) { Start-Compose @($manifest.composeProfiles); Start-Sleep -Seconds 2 }
        Invoke-Doctor $manifest $suites
        Invoke-WireMockReload
        Invoke-Up $manifest $suites
        if (($suites -contains 'api') -or ($suites -contains 'e2e')) {
          Invoke-Seeds $manifest
          New-Item -ItemType File -Force $SeedMarker | Out-Null
        }
        if ($suites -contains 'api') { Reset-ApiReports }
        foreach ($name in $suites) { Invoke-Suite $name $manifest }
        if ($suites -contains 'api') { $counts = Get-ApiCounts }
        else { $counts.passed = $suites.Count }
        Assert-RequiredEvidence $manifest
        Invoke-ReliableCleanup $manifest
      }
      Write-Summary 'PASS' $suites $counts
    } catch {
      $message = $_.Exception.Message
      $cleanupFailed = $false
      if ($suites -contains 'api') {
        try { $counts = Get-ApiCounts } catch { $counts.failed = 1; $counts.raw = 'missing' }
      } else { $counts.failed = 1 }
      try { Invoke-ReliableCleanup $manifest } catch { $cleanupFailed = $true; $message = "$message; $($_.Exception.Message)" }
      $status = if ($message -match '^\[TEST_CONFIGURATION\] BLOCKED') { 'BLOCKED' } else { 'FAIL' }
      Write-Summary $status $suites $counts $message $cleanupFailed
      throw
    }
  }
}
