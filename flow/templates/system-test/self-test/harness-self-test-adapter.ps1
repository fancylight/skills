[CmdletBinding()]
param(
  [Parameter(Mandatory=$true)]
  [ValidateSet('doctor','up','wiremock-reload','seed','suite','cleanup')]
  [string]$Operation,
  [Parameter(Mandatory=$true)] [string]$Scenario,
  [Parameter(Mandatory=$true)] [string]$TestRoot,
  [Parameter(Mandatory=$true)] [string]$Change,
  [Parameter(Mandatory=$true)] [string]$RuntimeDir,
  [string]$PayloadBase64 = 'e30='
)

$ErrorActionPreference = 'Stop'

function Write-Utf8([string]$Path, [string]$Value) {
  $directory = Split-Path -Parent $Path
  if (-not (Test-Path -LiteralPath $directory)) { [void](New-Item -ItemType Directory -Path $directory -Force) }
  [IO.File]::WriteAllText($Path, $Value, [Text.UTF8Encoding]::new($false))
}

function Stop-Adapter([string]$Message) {
  Write-Output $Message
  exit 1
}

function Write-State {
  Write-Utf8 (Join-Path $RuntimeDir 'state.json') '{"processes":[],"composeProfiles":[]}'
}

function Write-RawEvidence {
  if ($Scenario -eq 'evidence-missing') { return }
  $payload = [ordered]@{ scenario=$Scenario; operation=$Operation; generatedAt=[DateTime]::UtcNow.ToString('o') }
  Write-Utf8 (Join-Path $RuntimeDir 'raw\runner.json') ($payload | ConvertTo-Json -Compress)
}

switch ($Operation) {
  'doctor' {
    if ($Scenario -eq 'mysql-unavailable') { Stop-Adapter '[TEST_CONFIGURATION] BLOCKED; STOP_AWAIT_HUMAN_CONFIGURATION; MySQL unavailable' }
    if ($Scenario -eq 'postgres-unavailable') { Stop-Adapter '[TEST_CONFIGURATION] BLOCKED; STOP_AWAIT_HUMAN_CONFIGURATION; PostgreSQL unavailable' }
    if ($Scenario -eq 'redis-unavailable') { Stop-Adapter '[TEST_CONFIGURATION] BLOCKED; STOP_AWAIT_HUMAN_CONFIGURATION; Redis unavailable' }
  }
  'up' {
    Write-State
    if ($Scenario -eq 'sut-startup-failure') {
      Write-Utf8 (Join-Path $RuntimeDir 'logs\sut.err.log') '[TEST_HARNESS] controlled SUT startup failure'
      Stop-Adapter '[TEST_HARNESS] SUT startup failed'
    }
  }
  'wiremock-reload' { }
  'seed' {
    if ($Scenario -eq 'seed-failure') {
      Write-Utf8 (Join-Path $RuntimeDir 'logs\seed.log') '[FIXTURE_ASSERTION] controlled seed failure'
      Stop-Adapter '[FIXTURE_ASSERTION] seed failed'
    }
  }
  'suite' {
    if ($Scenario -eq 'wiremock-unmatched') {
      Write-Utf8 (Join-Path $RuntimeDir 'wiremock\unmatched.json') '{"request":"unmatched"}'
      Stop-Adapter '[TEST_HARNESS] WireMock unmatched request'
    }
    if ($Scenario -eq 'maven-execution-failure') { Stop-Adapter '[TEST_HARNESS] Maven execution failed' }
    if ($Scenario -eq 'interrupted-run') {
      Write-Utf8 (Join-Path $RuntimeDir 'logs\interruption.log') '[TEST_HARNESS] controlled runner interruption'
      Stop-Adapter '[TEST_HARNESS] runner interrupted'
    }

    $payloadJson = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($PayloadBase64))
    $payload = $payloadJson | ConvertFrom-Json
    if ($Scenario -eq 'maven-arguments') {
      $arguments = @($payload.arguments | ForEach-Object { [string]$_ })
      if (@($arguments | Where-Object { $_ -eq '-Dtest=*Test' }).Count -ne 1) { Stop-Adapter '[TEST_HARNESS] Maven filter argument was not preserved' }
      if (@($arguments | Where-Object { $_ -match '\s' }).Count -eq 0) { Stop-Adapter '[TEST_HARNESS] Maven path containing spaces was not preserved' }
      Write-Utf8 (Join-Path $RuntimeDir 'raw\maven-arguments.json') ($arguments | ConvertTo-Json)
    }
    if ($Scenario -eq 'utf8-log') {
      $utf8Text = -join @([char]0x4E2D,[char]0x6587,[char]0x65E5,[char]0x5FD7)
      Write-Utf8 (Join-Path $RuntimeDir 'logs\utf8.log') $utf8Text
    }
    Write-RawEvidence
    if ($Scenario -ne 'surefire-missing') {
      $xml = '<testsuite name="HarnessSelfTest" tests="1" failures="0" errors="0" skipped="0"><testcase classname="HarnessSelfTest" name="runnerContract" /></testsuite>'
      Write-Utf8 (Join-Path $TestRoot 'backend-tests\target\surefire-reports\TEST-HarnessSelfTest.xml') $xml
    }
  }
  'cleanup' {
    if ($Scenario -eq 'cleanup-failure') {
      Write-Utf8 (Join-Path $RuntimeDir 'logs\cleanup.log') '[TEST_HARNESS] controlled cleanup failure'
      Stop-Adapter '[TEST_HARNESS] cleanup failed'
    }
  }
}

exit 0
