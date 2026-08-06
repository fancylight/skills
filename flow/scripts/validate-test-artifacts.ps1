[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$SystemTestRepo,
    [Parameter(Mandatory = $true)]
    [string]$ChangeName,
    [Parameter(Mandatory = $true)]
    [ValidateSet('design', 'implementation', 'result')]
    [string]$Mode,
    [Parameter(Mandatory = $true)]
    [string]$CanonicalRevision
)

$ErrorActionPreference = 'Stop'
$errors = [System.Collections.Generic.List[string]]::new()
$repo = [IO.Path]::GetFullPath($SystemTestRepo)
$changeDir = Join-Path $repo "changes\$ChangeName"

function Add-Error([string]$Message) { $script:errors.Add($Message) }
function Require-Path([string]$Path, [string]$Name) {
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        Add-Error "Missing ${Name}: $Path"
        return $false
    }
    return $true
}
function Test-ToolOutputPollution([string]$Path) {
    $patterns = @('(?m)^Exit code:', '(?m)^Wall time:', '(?m)^Output:', '(?m)^Script completed')
    $content = Get-Content -LiteralPath $Path -Raw -Encoding utf8
    foreach ($pattern in $patterns) {
        if ($content -match $pattern) {
            Add-Error "Tool-output wrapper in $Path ($pattern)"
            break
        }
    }
}
function Test-MarkdownTableShape([string]$Path) {
    $rows = @(Get-Content -LiteralPath $Path -Encoding utf8)
    $group = [System.Collections.Generic.List[string]]::new()
    function Test-Group {
        if ($group.Count -lt 2) { $group.Clear(); return }
        $counts = @($group | ForEach-Object { ([regex]::Matches($_, '(?<!\\)\|')).Count } | Sort-Object -Unique)
        if ($counts.Count -gt 1) {
            $shape = @($group | ForEach-Object { "$( ([regex]::Matches($_, '(?<!\\)\|')).Count ):$($_.Trim())" }) -join ' || '
            Add-Error "Malformed Markdown table in $Path (inconsistent column count: $shape)"
        }
        $group.Clear()
    }
    foreach ($row in $rows) {
        if ($row.TrimStart().StartsWith('|')) { $group.Add($row) } else { Test-Group }
    }
    Test-Group
}
function Test-SqlSafety([string]$Path, [bool]$IsCleanup) {
    $content = Get-Content -LiteralPath $Path -Raw -Encoding utf8
    Test-ToolOutputPollution $Path
    $withoutComments = [regex]::Replace($content, '(?m)^\s*(--|#).*$', '')
    if ($withoutComments -match '(?im)^\s*(CREATE|ALTER|DROP|TRUNCATE)\b') {
        Add-Error "Executable DDL is forbidden in fixture: $Path"
    }
    $statements = @($withoutComments -split ';' | Where-Object { $_.Trim() -ne '' })
    if ($statements.Count -gt 0 -and -not $withoutComments.TrimEnd().EndsWith(';')) {
        Add-Error "Final SQL statement lacks semicolon: $Path"
    }
    if ($IsCleanup) {
        if ($content -notmatch '(?i)(reserved\s+ids?|\bids?\b|fixture|marker)') {
            Add-Error "Cleanup does not declare its IDS/reserved-marker scope: $Path"
        }
        foreach ($statement in $statements) {
            if ($statement -match '(?is)^\s*DELETE\b' -and $statement -notmatch '(?is)\bWHERE\b') {
                Add-Error "Cleanup DELETE lacks a scoped WHERE predicate: $Path"
            }
        }
    }
}

if (-not (Test-Path -LiteralPath $repo -PathType Container)) {
    throw "SystemTestRepo does not exist: $repo"
}
if (-not (Test-Path -LiteralPath $changeDir -PathType Container)) {
    Add-Error "Change directory does not exist: $changeDir"
} else {
    $design = Join-Path $changeDir 'test-design.md'
    $plan = Join-Path $changeDir 'test-plan.md'
    $manifest = Join-Path $changeDir 'manifest.yaml'
    $testCases = Join-Path $changeDir 'test-cases.yaml'
    $derivedContract = Join-Path $changeDir 'test-cases.generated.json'
    $fixtures = Join-Path $changeDir 'fixtures'
    $idsFiles = @(Get-ChildItem -LiteralPath $fixtures -File -ErrorAction SilentlyContinue | Where-Object { $_.Name -match '(?i)ids?' })
    $seedFiles = @(Get-ChildItem -LiteralPath $fixtures -File -Filter '*.sql' -ErrorAction SilentlyContinue | Where-Object { $_.Name -match '(?i)seed' })
    $cleanupFiles = @(Get-ChildItem -LiteralPath $fixtures -File -Filter '*.sql' -ErrorAction SilentlyContinue | Where-Object { $_.Name -match '(?i)clean' })

    if ($Mode -eq 'design') {
        @(@($design, 'test-design'), @($plan, 'test-plan'), @($manifest, 'manifest'), @($testCases, 'test-cases'), @($derivedContract, 'test-cases generated contract')) | ForEach-Object {
            [void](Require-Path $_[0] $_[1])
        }
        if ($idsFiles.Count -eq 0) { Add-Error "Missing IDS fixture under $fixtures" }
        if ($seedFiles.Count -eq 0) { Add-Error "Missing seed SQL fixture under $fixtures" }
        if ($cleanupFiles.Count -eq 0) { Add-Error "Missing cleanup SQL fixture under $fixtures" }

        $fixtureFiles = @(Get-ChildItem -LiteralPath $fixtures -File -ErrorAction SilentlyContinue)
        @($design, $plan, $manifest) + @($fixtureFiles.FullName) | Where-Object { Test-Path -LiteralPath $_ } | ForEach-Object {
            Test-ToolOutputPollution $_
        }
        @($design, $plan) + @($fixtureFiles | Where-Object Extension -eq '.md' | ForEach-Object FullName) |
            Where-Object { Test-Path -LiteralPath $_ } | ForEach-Object { Test-MarkdownTableShape $_ }
        @($design, $plan) | Where-Object { Test-Path -LiteralPath $_ } | ForEach-Object {
            $content = Get-Content -LiteralPath $_ -Raw -Encoding utf8
            if ($content -match '(?im)\b\d+\s*/\s*\d+\s+(PASS|FAIL)\b|^\s*(tests? run|passed|failed|skipped|build success|build failure|执行结果|实际耗时)\s*[:=]|\[(SYSTEM_TEST_RESULT|INTEGRATION_TEST_RESULT)\]') {
                Add-Error "Design artifact contains execution result or duration: $_"
            }
        }
        @($seedFiles + $cleanupFiles) | ForEach-Object { Test-SqlSafety $_.FullName ($cleanupFiles.FullName -contains $_.FullName) }

        if (Test-Path -LiteralPath $manifest) {
            try {
                $manifestValue = Get-Content -LiteralPath $manifest -Raw -Encoding utf8 | ConvertFrom-Json
                if ($manifestValue.stage -ne 'design') { Add-Error "Manifest stage must be 'design': $manifest" }
                if ($null -eq $manifestValue.testAuthorization) {
                    Add-Error "Manifest must record testAuthorization: $manifest"
                } elseif ($manifestValue.testAuthorization.ceiling -ne 'design') {
                    Add-Error "Design manifest testAuthorization.ceiling must be 'design': $manifest"
                } elseif ($manifestValue.testAuthorization.grantedBy -ne 'user') {
                    Add-Error "Manifest testAuthorization.grantedBy must be 'user': $manifest"
                }
                @('configurationSource', 'requiredEndpoints', 'connectivityProbe', 'ownership') | ForEach-Object {
                    if ($null -eq $manifestValue.$_ -or [string]::IsNullOrWhiteSpace([string]$manifestValue.$_)) {
                        Add-Error "Manifest must declare ${_}: $manifest"
                    }
                }
                if ($null -eq $manifestValue.testCasesContract -or [string]::IsNullOrWhiteSpace([string]$manifestValue.testCasesContract.path)) {
                    Add-Error "Manifest must declare testCasesContract.path: $manifest"
                }
                $text = Get-Content -LiteralPath $manifest -Raw -Encoding utf8
                if ($text -match '(?i)\b(implementation|result)\s*(PASS|READY)\b') { Add-Error "Manifest contains later-stage result: $manifest" }
            } catch { Add-Error "Manifest is not valid JSON: $manifest ($($_.Exception.Message))" }
        }
        if (Test-Path -LiteralPath $plan) {
            $planText = Get-Content -LiteralPath $plan -Raw -Encoding utf8
            if ($planText -notmatch '(?i)system-test\s+path\s*:') {
                Add-Error "test-plan must contain the ASCII marker 'system-test path:': $plan"
            } elseif ($planText -notmatch [regex]::Escape([IO.Path]::GetFileName($repo))) {
                Add-Error "test-plan system-test path does not identify the verified repo '$([IO.Path]::GetFileName($repo))': $plan"
            }
        }
    }

    if ((Test-Path -LiteralPath $testCases -PathType Leaf) -and (Test-Path -LiteralPath $derivedContract -PathType Leaf) -and
        (Test-Path -LiteralPath $manifest -PathType Leaf) -and (Test-Path -LiteralPath $plan -PathType Leaf)) {
        $validator = Join-Path $PSScriptRoot 'validate-test-cases.ps1'
        if (-not (Test-Path -LiteralPath $validator -PathType Leaf)) { Add-Error "Missing canonical test-cases validator: $validator" }
        else {
            $validatorParameters = @{
                TestCasesPath=$testCases; Mode=$Mode; CanonicalRevision=$CanonicalRevision; ManifestPath=$manifest
                DerivedContractPath=$derivedContract; TestPlanPath=$plan
            }
            if ($Mode -in @('implementation','result')) { $validatorParameters.JavaSourceRoot = Join-Path $repo 'backend-tests\src\test' }
            if ($Mode -eq 'result') { $validatorParameters.EvidenceRoot = Join-Path $changeDir 'evidence\current' }
            $validatorOutput = @(& $validator @validatorParameters 2>&1)
            if ($LASTEXITCODE -ne 0) { Add-Error "Canonical test-cases validation failed: $($validatorOutput -join ' | ')" }
        }
    }
}

if ($errors.Count -gt 0) {
    Write-Output '[TEST_ARTIFACT_GUARD] ERROR'
    $errors | ForEach-Object { Write-Output "- $_" }
    exit 1
}
Write-Output '[TEST_ARTIFACT_GUARD] PASS'
Write-Output "mode: $Mode"
Write-Output "change_name: $ChangeName"
