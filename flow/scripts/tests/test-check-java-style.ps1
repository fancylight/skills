param(
    [string]$CheckstyleJar = (Join-Path ([Environment]::GetFolderPath('UserProfile')) '.cache/flow-tools/checkstyle/14.1.0/checkstyle-14.1.0-all.jar'),
    [string]$JavaExecutable = 'java',
    [string]$Checker = (Join-Path $PSScriptRoot '../check-java-style.ps1')
)
$ErrorActionPreference = 'Stop'
$root = Join-Path ([IO.Path]::GetTempPath()) ('flow-style-tests-' + [Guid]::NewGuid().ToString('N'))
$repo = Join-Path $root 'repo with spaces'
[void][IO.Directory]::CreateDirectory($repo)
$utf8 = [Text.UTF8Encoding]::new($false)
$engine = if ($PSVersionTable.PSEdition -eq 'Desktop') { Join-Path $PSHOME 'powershell.exe' } else { Join-Path $PSHOME 'pwsh' }
$checks = @()

function Invoke-TestGit([string[]]$Arguments) {
    $output = & git -C $repo -c core.autocrlf=false @Arguments 2>&1
    if ($LASTEXITCODE -ne 0) { throw ($output -join "`n") }
    return ($output -join "`n").Trim()
}
function Write-Java([string]$Path,[string]$Text) {
    [IO.File]::WriteAllText((Join-Path $repo $Path),$Text,$utf8)
}
function PS-Quote([string]$Text) { return "'" + $Text.Replace("'","''") + "'" }
function Check([string]$Name,[string[]]$Paths,[string]$Expected,[int]$New=-1,[int]$Old=-1,[string]$Revision=$script:base,[string]$Jar=$CheckstyleJar,[string]$Java=$JavaExecutable) {
    $report = Join-Path $root $Name
    $array = '@(' + (($Paths | ForEach-Object { PS-Quote $_ }) -join ',') + ')'
    $command = '& ' + (PS-Quote ([IO.Path]::GetFullPath($Checker))) + ' -RepositoryPath ' + (PS-Quote $repo) + ' -BaseRevision ' + (PS-Quote $Revision) + ' -Files ' + $array + ' -ReportDirectory ' + (PS-Quote $report) + ' -CheckstyleJar ' + (PS-Quote $Jar) + ' -JavaExecutable ' + (PS-Quote $Java)
    $command += '; exit $LASTEXITCODE'
    $encoded = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($command))
    $raw = & $engine -NoProfile -EncodedCommand $encoded 2>&1
    $exit = $LASTEXITCODE
    $path = Join-Path $report 'result.json'
    if (-not [IO.File]::Exists($path)) { throw "$Name produced no result: $raw" }
    $result = [IO.File]::ReadAllText($path) | ConvertFrom-Json
    if ($result.result -ne $Expected) { throw "$Name expected $Expected, got $($result.result): $($result.reason)" }
    $expectedExit = if ($Expected -in @('PASS','NOT_APPLICABLE')) {0} elseif($Expected -eq 'FAIL'){1}else{2}
    if ($exit -ne $expectedExit) { throw "$Name wrong exit code $exit" }
    if ($New -ge 0 -and @($result.findings).Count -ne $New) { throw "$Name new count mismatch: $($result.findings | ConvertTo-Json -Compress)" }
    if ($Old -ge 0 -and @($result.historicalFindings).Count -ne $Old) { throw "$Name old count mismatch" }
    $script:checks += [pscustomobject]@{case=$Name;result='PASS';checkerResult=$result.result}
}

[void](Invoke-TestGit @('init','-q'))
[void](Invoke-TestGit @('config','user.email','fixture@example.invalid'))
[void](Invoke-TestGit @('config','user.name','Flow fixture'))
$legacy = "class Legacy {`n  int value(boolean flag) {`n    if (flag) return 1;`n    return 0;`n  }`n}`n"
$clean = "class Clean {`n  int value(boolean flag) {`n    if (flag) {`n      return 1;`n    }`n    return 0;`n  }`n}`n"
Write-Java 'Legacy.java' $legacy
Write-Java 'Clean.java' $clean
[void](Invoke-TestGit @('add','.'))
[void](Invoke-TestGit @('commit','-qm','baseline'))
$script:base = Invoke-TestGit @('rev-parse','HEAD')
Check 'non-java-no-tools' @('README.md') 'NOT_APPLICABLE' -Java 'missing-java' -Jar 'missing.jar'
Check 'invalid-base' @('Clean.java') 'UNVERIFIED' -Revision 'missing-revision'
Check 'missing-jar' @('Clean.java') 'UNVERIFIED' -Jar 'missing.jar'
Check 'missing-java' @('Clean.java') 'UNVERIFIED' -Java 'missing-java'
Check 'path-traversal' @('../outside.java') 'UNVERIFIED'
Check 'unknown-selected-file' @('Missing.java') 'UNVERIFIED'
Check 'valid' @('Clean.java') 'PASS' 0 0
Check 'historical' @('Legacy.java') 'PASS' 0 1
Write-Java 'Legacy.java' ("// shifted line`n" + $legacy)
Check 'line-shift' @('Legacy.java') 'PASS' 0 1
Write-Java 'Legacy.java' ("// shifted line`n" + $legacy.Replace('if (flag) return 1;','if (flag) return 2;'))
Check 'changed-legacy-location' @('Legacy.java') 'FAIL' 1 0
Write-Java 'Legacy.java' $legacy
[void](Invoke-TestGit @('mv','Legacy.java','Renamed.java'))
Check 'rename' @('Renamed.java') 'PASS' 0 1
Write-Java 'Clean.java' $clean.Replace("    if (flag) {`n      return 1;`n    }","    if (flag)`n      return 1;")
Check 'removed-braces' @('Clean.java') 'FAIL' 1 0
Write-Java 'New.java' "class New { void f(boolean b) { if (b) return; else return; for (int i=0;i<2;i++) continue; while (b) break; do b=false; while(b); } }"
Check 'new-all-control-kinds' @('New.java') 'FAIL' 5 0
$unicodeFile = [string][char]0x4e2d + [char]0x6587 + ' File.java'
Write-Java $unicodeFile 'class UnicodeFile { void f(boolean b) { if (b) return; } }'
Check 'unicode-and-spaces' @($unicodeFile) 'FAIL' 1 0
Write-Java 'Broken.java' 'class Broken { void f( ??? }'
Check 'parse-error' @('Broken.java') 'UNVERIFIED'
Check 'scope-excludes-other-errors' @('Renamed.java') 'PASS' 0 1
[IO.File]::Delete((Join-Path $repo 'Clean.java'))
Check 'deleted-file' @('Clean.java') 'NOT_APPLICABLE'
Write-Java 'RecordExample.java' 'record RecordExample(int value) { int get() { if (value > 0) { return value; } else { return 0; } } }'
Check 'java-record' @('RecordExample.java') 'PASS' 0 0
$summary = [pscustomobject]@{result='PASS';cases=$checks.Count;checks=$checks;artifacts=$root}
[IO.File]::WriteAllText((Join-Path $root 'summary.json'),($summary | ConvertTo-Json -Depth 6),$utf8)
$summary | ConvertTo-Json -Depth 6
