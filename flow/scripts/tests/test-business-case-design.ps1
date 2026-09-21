$ErrorActionPreference = 'Stop'
$validator = Join-Path $PSScriptRoot '../validate-test-cases.ps1'
$root = Join-Path ([IO.Path]::GetTempPath()) ('flow-business-design-' + [guid]::NewGuid().ToString('N'))
$utf8 = [Text.UTF8Encoding]::new($false)
New-Item -ItemType Directory -Path $root | Out-Null
function Check([bool]$Condition, [string]$Message) { if (-not $Condition) { throw $Message } }
try {
    $source = Join-Path $root 'test-cases.yaml'
    $plan = Join-Path $root 'test-plan.md'
    $manifest = Join-Path $root 'manifest.yaml'
    $derived = Join-Path $root 'test-cases.generated.json'
    $complete = Get-Content (Join-Path $PSScriptRoot 'fixtures/business-cases.yaml') -Raw -Encoding utf8
    # No technical details required to draft and review the business cases.
    $businessOnly = [regex]::Replace($complete, '(?ms)^    suite:.*?(?=^  - id:|\z)', '')
    [IO.File]::WriteAllText($source, $businessOnly, $utf8)
    [IO.File]::WriteAllText($plan, "MANUAL`n<!-- FLOW_TEST_CASES_GENERATED:START -->`n<!-- FLOW_TEST_CASES_GENERATED:END -->`nEND", $utf8)
    & $validator -TestCasesPath $source -Mode business -Generate -TestPlanPath $plan | Out-Null
    Check ($LASTEXITCODE -eq 0) 'business-only preview must work without runner, methods, fixtures or sidecar'
    $preview = Get-Content $plan -Raw -Encoding utf8
    Check ($preview.Contains('首次A日3小时/B日0小时') -and $preview.Contains('非严格模式同样更正仍保留3小时')) 'preview lost concrete independent expected result or counterexample'
    Check (-not $preview.Contains('com.example') -and -not (Test-Path $derived)) 'business preview must not fabricate technical bindings'
    $tables='      tables: [{"name":"请求结果","columns":["操作","次数"],"rows":[["首次","1"],["重复","1"]]}]'
    $withTables=$businessOnly.Replace('    business:',("    business:`n"+$tables))
    [IO.File]::WriteAllText($source,$withTables,$utf8)
    & $validator -TestCasesPath $source -Mode business -Generate -TestPlanPath $plan | Out-Null
    Check ($LASTEXITCODE -eq 0) 'named tables rejected'
    $tablePlan=Get-Content $plan -Raw -Encoding utf8
    Check ($tablePlan.Contains('| 用例 |') -and $tablePlan.Contains('| 重复 | 1 |')) 'readable overview/table missing'
    [IO.File]::WriteAllText($source,$withTables.Replace('["首次","1"]','["首次"]'),$utf8)
    & $validator -TestCasesPath $source -Mode business | Out-Null
    Check ($LASTEXITCODE -ne 0) 'invalid table width accepted'
    foreach ($field in @('purpose','preconditions','inputs','steps','expected','oracle','counterexamples','evidenceBoundary')) {
        $bad = [regex]::Replace($businessOnly, "(?m)^      ${field}:.*\r?\n", '')
        [IO.File]::WriteAllText($source, $bad, $utf8)
        & $validator -TestCasesPath $source -Mode business | Out-Null
        Check ($LASTEXITCODE -ne 0) "missing business.$field accepted"
    }
    [IO.File]::WriteAllText($source, $complete, $utf8)
    [IO.File]::WriteAllText($manifest, '{"testCasesContract":{"path":"test-cases.generated.json"}}', $utf8)
    $argsMap = @{TestCasesPath=$source;TestPlanPath=$plan;ManifestPath=$manifest;DerivedContractPath=$derived;CanonicalRevision=('1'*40);Generate=$true;RequireBusiness=$true}
    & $validator @argsMap | Out-Null
    Check ($LASTEXITCODE -eq 0) 'full design generation failed'
    $first = [IO.File]::ReadAllBytes($plan)
    $full = Get-Content $plan -Raw -Encoding utf8
    Check ($full.IndexOf('首次A日3小时') -lt $full.IndexOf('com.example.NightIT')) 'technical bindings precede business cases'
    Check ($full.Contains('N仅引用算法单测') -and $full.Contains('状态：待执行')) 'coverage boundary or design-only status missing'
    # Run the exact same source in Windows PowerShell 5.1 and the current host.
    if (Get-Command powershell.exe -ErrorAction SilentlyContinue) {
        & powershell.exe -NoProfile -File $validator -TestCasesPath $source -TestPlanPath $plan -ManifestPath $manifest -DerivedContractPath $derived -CanonicalRevision ('1'*40) -Generate -RequireBusiness | Out-Null
        Check ($LASTEXITCODE -eq 0) 'Windows PowerShell 5.1 generation failed'
        Check ([Convert]::ToBase64String($first) -eq [Convert]::ToBase64String([IO.File]::ReadAllBytes($plan))) 'Chinese plan bytes differ across PowerShell hosts'
    }
    $legacy = [regex]::Replace($complete, '(?ms)^    business:.*?(?=^    suite:)', '')
    [IO.File]::WriteAllText($source, $legacy, $utf8)
    & $validator -TestCasesPath $source | Out-Null
    Check ($LASTEXITCODE -eq 0) 'legacy source parsing compatibility broken'
    & $validator -TestCasesPath $source -RequireBusiness | Out-Null
    Check ($LASTEXITCODE -ne 0) 'technical-only source passed business design gate'
    $previous = Join-Path $root 'previous-cases.yaml'
    [IO.File]::WriteAllText($previous, $legacy.Replace('required:', 'required :'), $utf8)
    [IO.File]::WriteAllText($source, $complete, $utf8)
    & $validator -TestCasesPath $source -PreviousTestCasesPath $previous -PreserveRequiredCoverage | Out-Null
    Check ($LASTEXITCODE -eq 0) 'preservation must reuse canonical parsing and permit legacy business enrichment'
    [IO.File]::WriteAllText($source, $complete.Replace('required: true', 'required: false'), $utf8)
    & $validator -TestCasesPath $source -PreviousTestCasesPath $previous -PreserveRequiredCoverage | Out-Null
    Check ($LASTEXITCODE -ne 0) 'required weakening escaped preservation with valid YAML whitespace'
    Write-Output '[BUSINESS_CASE_DESIGN_TEST] PASS'
} finally { Remove-Item -LiteralPath $root -Recurse -Force }
