[CmdletBinding()]
param(
  [Parameter(Position=0, Mandatory=$true)]
  [ValidateSet('doctor','up','run','down','cleanup')]
  [string]$Command,
  [Parameter(Mandatory=$true)]
  [string]$Change,
  [ValidateSet('ui-mock','api','e2e','cdc','all')]
  [string]$Suite = 'all',
  [string]$EnvFile = '.env.local',
  [string]$OrchRoot = ''
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
    throw "doctor failed with $($errors.Count) blocker(s)"
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
    & mvn.cmd @mvnArgs
    if ($LASTEXITCODE -ne 0) { throw 'api suite failed' }
  } elseif ($Name -eq 'cdc') {
    $cdc = Join-Path $TestRoot 'scripts\cdc-smoke.ps1'
    if (-not (Test-Path $cdc)) { throw 'scripts/cdc-smoke.ps1 missing; cannot run cdc suite' }
    & $cdc -EnvFile $EnvFile
    if ($LASTEXITCODE -ne 0) { throw 'cdc suite failed' }
  }
}

function Write-Summary([string]$Status, [string[]]$Suites, [string]$Message='') {
  $evidenceDir = Join-Path $TestRoot "changes\$Change\evidence"
  New-Item -ItemType Directory -Force $evidenceDir | Out-Null
  $summary = Join-Path $evidenceDir 'summary.md'
  $retained = if ($Status -eq 'PASS') { 'false' } else { 'true' }
  $cleanup = if ($Status -eq 'PASS') { 'none' } else { ".\scripts\system-test.ps1 cleanup -Change $Change" }
  @"
# System Test Result

- status: $Status
- change_name: $Change
- suites: $($Suites -join ',')
- generated_at: $([DateTime]::Now.ToString('s'))
- retained_state: $retained
- cleanup_command: $cleanup
- message: $Message
"@ | Set-Content -Encoding UTF8 $summary
  Write-Host "[SYSTEM_TEST_RESULT] $Status"
  Write-Host "change_name: $Change"
  Write-Host "suites: $($Suites -join ',')"
  Write-Host "passed: $(if ($Status -eq 'PASS') { $Suites.Count } else { 0 })"
  Write-Host "failed: $(if ($Status -eq 'PASS') { 0 } else { 1 })"
  Write-Host 'skipped: 0'
  Write-Host "evidence: $summary"
  Write-Host "retained_state: $retained"
  Write-Host "cleanup_command: $cleanup"
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

Import-DotEnv (Join-Path $TestRoot $EnvFile)
$manifest = Get-Manifest
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
    try {
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
        foreach ($name in $suites) { Invoke-Suite $name $manifest }
        if (Test-Path $SeedMarker) { Invoke-CleanupData $manifest; Remove-Item $SeedMarker -Force }
        Invoke-Down
      }
      Write-Summary 'PASS' $suites
    } catch {
      Write-Summary 'FAIL' $suites $_.Exception.Message
      Write-Warning "failure state retained; cleanup with: .\scripts\system-test.ps1 cleanup -Change $Change"
      throw
    }
  }
}
