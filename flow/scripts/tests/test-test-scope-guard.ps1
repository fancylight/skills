$ErrorActionPreference = 'Stop'
$scriptRoot = Split-Path -Parent $PSScriptRoot
$guard = Join-Path $scriptRoot 'test-scope-guard.ps1'
$repo = [IO.Path]::GetFullPath((Join-Path ([IO.Path]::GetTempPath()) 'flow-system-test'))
$allowedTarget = Join-Path $repo 'changes\example\test-plan.md'
$businessTarget = Join-Path ([IO.Path]::GetTempPath()) 'business-service\src\main\java\BusinessService.java'

& powershell.exe -NoProfile -File $guard -AuthorizedRepo $repo -TargetPath $allowedTarget -Stage design
if ($LASTEXITCODE -ne 0) { throw 'Expected system-test design path to pass scope guard.' }

foreach ($canonicalName in @('test-cases.yaml','test-cases.generated.json')) {
    $canonicalTarget = Join-Path $repo "changes\example\$canonicalName"
    & powershell.exe -NoProfile -File $guard -AuthorizedRepo $repo -TargetPath $canonicalTarget -Stage design
    if ($LASTEXITCODE -ne 0) { throw "Expected design-stage canonical artifact to pass scope guard: $canonicalName" }
}

$junitTarget = Join-Path $repo 'backend-tests\src\test\java\ExampleTest.java'
& powershell.exe -NoProfile -File $guard -AuthorizedRepo $repo -TargetPath $junitTarget -Stage design -Action write
if ($LASTEXITCODE -eq 0) { throw 'Expected design-stage JUnit write to be blocked.' }

& powershell.exe -NoProfile -File $guard -AuthorizedRepo $repo -TargetPath $repo -Stage design -Action test -CommandKind docker
if ($LASTEXITCODE -eq 0) { throw 'Expected design-stage Docker execution to be blocked.' }

& powershell.exe -NoProfile -File $guard -AuthorizedRepo $repo -TargetPath $repo -Stage apply -Action test -CommandKind static
if ($LASTEXITCODE -ne 0) { throw 'Expected apply-stage static validation to pass.' }

& powershell.exe -NoProfile -File $guard -AuthorizedRepo $repo -TargetPath $repo -Stage apply -Action test -CommandKind api
if ($LASTEXITCODE -eq 0) { throw 'Expected apply-stage API execution to be blocked.' }

& powershell.exe -NoProfile -File $guard -AuthorizedRepo $repo -TargetPath $allowedTarget -Stage review -Action read
if ($LASTEXITCODE -ne 0) { throw 'Expected review-stage read to pass.' }

& powershell.exe -NoProfile -File $guard -AuthorizedRepo $repo -TargetPath $allowedTarget -Stage review -Action write
if ($LASTEXITCODE -eq 0) { throw 'Expected review-stage write to be blocked.' }

& powershell.exe -NoProfile -File $guard -AuthorizedRepo $repo -TargetPath $businessTarget -Stage apply -Action write
if ($LASTEXITCODE -eq 0) { throw 'Expected business-repository target to be blocked.' }

$evidenceTarget = Join-Path $repo 'changes\example\evidence\current\summary.md'
& powershell.exe -NoProfile -File $guard -AuthorizedRepo $repo -TargetPath $evidenceTarget -Stage execution -Action write
if ($LASTEXITCODE -ne 0) { throw 'Expected execution-stage evidence write to pass.' }

& powershell.exe -NoProfile -File $guard -AuthorizedRepo $repo -TargetPath $repo -Stage execution -Action test -CommandKind runner
if ($LASTEXITCODE -ne 0) { throw 'Expected execution-stage runner command to pass.' }

Write-Output 'test-scope-guard allowed system-test design path and blocked business-repository write.'
