$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSScriptRoot))
$runner = Join-Path $repoRoot 'flow\templates\system-test\scripts\system-test.ps1'
$source = Get-Content -LiteralPath $runner -Raw -Encoding UTF8

$functionMatch = [regex]::Match($source, '(?ms)^function Quote-Argument\(\[string\]\$Value\) \{.*?^\}')
if (-not $functionMatch.Success) { throw 'Quote-Argument helper is missing from system-test runner' }
Invoke-Expression $functionMatch.Value

$resetMarker = "if (`$suites -contains 'api') { Reset-ApiReports }"
$resetIndex = $source.IndexOf($resetMarker, [StringComparison]::Ordinal)
$startupIndex = $source.IndexOf('Invoke-Up $manifest $suites', [StringComparison]::Ordinal)
if ($resetIndex -lt 0 -or $startupIndex -lt 0 -or $resetIndex -gt $startupIndex) {
    throw 'API reports must be reset before managed service startup'
}

$root = Join-Path ([IO.Path]::GetTempPath()) ('flow process arguments ' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $root -Force | Out-Null
try {
    $capture = Join-Path $root 'capture arguments.cmd'
    $output = Join-Path $root 'captured arguments.txt'
    @'
@echo off
> "%~1" echo %~2
>> "%~1" echo %~3
'@ | Set-Content -LiteralPath $capture -Encoding UTF8

    $expectedProperty = '-Dspring-boot.run.arguments=--server.port=18888 --spring.profiles.active=native'
    $arguments = @($output, 'spring-boot:run', $expectedProperty)
    $argumentLine = (@($arguments | ForEach-Object { Quote-Argument ([string]$_) }) -join ' ')
    $process = Start-Process -FilePath $capture -ArgumentList $argumentLine -PassThru -WindowStyle Hidden
    $process.WaitForExit()
    if ($process.ExitCode -ne 0 -or -not (Test-Path -LiteralPath $output -PathType Leaf)) {
        throw 'controlled process did not capture arguments'
    }
    $captured = @(Get-Content -LiteralPath $output -Encoding UTF8)
    if ($captured.Count -ne 2 -or $captured[0] -ne 'spring-boot:run' -or $captured[1] -ne $expectedProperty) {
        throw 'managed process argument containing spaces was split or changed'
    }
}
finally {
    if (Test-Path -LiteralPath $root) { Remove-Item -LiteralPath $root -Recurse -Force }
}

Write-Output '[SYSTEM_TEST_PROCESS_ARGUMENTS] PASS'
