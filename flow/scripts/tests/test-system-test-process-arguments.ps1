$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSScriptRoot))
$runner = Join-Path $repoRoot 'flow\templates\system-test\scripts\system-test.ps1'
$source = Get-Content -LiteralPath $runner -Raw -Encoding UTF8

$functionMatch = [regex]::Match($source, '(?ms)^function Quote-Argument\(\[string\]\$Value\) \{.*?^\}')
if (-not $functionMatch.Success) { throw 'Quote-Argument helper is missing from system-test runner' }
Invoke-Expression $functionMatch.Value

$convertMatch = [regex]::Match($source, '(?ms)^function Convert-SpringBootRunArgument\(\[string\]\$Value, \[hashtable\]\$Environment\) \{.*?^\}')
if (-not $convertMatch.Success) { throw 'Convert-SpringBootRunArgument helper is missing from system-test runner' }
Invoke-Expression $convertMatch.Value

$managedJavaMatch = [regex]::Match($source, '(?ms)^function Resolve-ManagedJavaHome \{.*?^\}')
if (-not $managedJavaMatch.Success) { throw 'Resolve-ManagedJavaHome helper is missing from system-test runner' }
Invoke-Expression $managedJavaMatch.Value

$resetMarker = "if (`$suites -contains 'api') { Reset-ApiReports }"
$resetIndex = $source.IndexOf($resetMarker, [StringComparison]::Ordinal)
$startupIndex = $source.IndexOf('Invoke-Up $manifest $suites', [StringComparison]::Ordinal)
if ($resetIndex -lt 0 -or $startupIndex -lt 0 -or $resetIndex -gt $startupIndex) {
    throw 'API reports must be reset before managed service startup'
}

$root = Join-Path ([IO.Path]::GetTempPath()) ('flow process arguments ' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $root -Force | Out-Null
try {
    $jdkRoot = Join-Path $root 'managed jdk'
    [void](New-Item -ItemType Directory -Path (Join-Path $jdkRoot 'bin') -Force)
    [void](New-Item -ItemType File -Path (Join-Path $jdkRoot 'bin\java.exe') -Force)
    [void](New-Item -ItemType File -Path (Join-Path $jdkRoot 'bin\javac.exe') -Force)
    $ManagedJavaHome = $jdkRoot
    if ((Resolve-ManagedJavaHome) -ne [IO.Path]::GetFullPath($jdkRoot)) {
        throw 'managed JDK path was not resolved deterministically'
    }

    $capture = Join-Path $root 'capture arguments.cmd'
    $output = Join-Path $root 'captured arguments.txt'
@'
@echo off
> "%~1" echo %~2
'@ | Set-Content -LiteralPath $capture -Encoding UTF8

    $expectedProperty = '-Dspring-boot.run.arguments=--server.port=18888 --spring.profiles.active=native --management.endpoints.web.exposure.include=health,info,env'
    $managedEnvironment = @{}
    $converted = Convert-SpringBootRunArgument $expectedProperty $managedEnvironment
    if ($null -ne $converted) { throw 'Spring Boot application arguments must not remain on the Maven command line' }
    if ($managedEnvironment.SERVER_PORT -ne '18888' -or
        $managedEnvironment.SPRING_PROFILES_ACTIVE -ne 'native' -or
        $managedEnvironment.MANAGEMENT_ENDPOINTS_WEB_EXPOSURE_INCLUDE -ne 'health,info,env') {
        throw 'Spring Boot application arguments were not converted to relaxed-binding environment variables'
    }
    $arguments = @($output, 'spring-boot:run')
    $argumentLine = (@($arguments | ForEach-Object { Quote-Argument ([string]$_) }) -join ' ')
    $process = Start-Process -FilePath $capture -ArgumentList $argumentLine -PassThru -WindowStyle Hidden
    $process.WaitForExit()
    if ($process.ExitCode -ne 0 -or -not (Test-Path -LiteralPath $output -PathType Leaf)) {
        throw 'controlled process did not capture arguments'
    }
    $captured = @(Get-Content -LiteralPath $output -Encoding UTF8)
    if ($captured.Count -ne 1 -or $captured[0] -ne 'spring-boot:run') {
        throw 'managed process argument list contains an unexpected application argument'
    }
}
finally {
    if (Test-Path -LiteralPath $root) { Remove-Item -LiteralPath $root -Recurse -Force }
}

Write-Output '[SYSTEM_TEST_PROCESS_ARGUMENTS] PASS'
