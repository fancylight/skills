[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)][string]$RepositoryPath,
    [Parameter(Mandatory=$true)][string]$BaseRevision,
    [Parameter(Mandatory=$true)][AllowEmptyCollection()][string[]]$Files,
    [Parameter(Mandatory=$true)][string]$ReportDirectory,
    [string]$CheckstyleJar,
    [string]$JavaExecutable,
    [string]$ConfigPath = (Join-Path $PSScriptRoot '../templates/java-need-braces.xml')
)

$ErrorActionPreference = 'Stop'
$utf8 = [Text.UTF8Encoding]::new($false)
$toolVersion = '14.1.0'
$result = [ordered]@{ result='UNVERIFIED'; rule='NeedBraces'; toolVersion=$toolVersion; baseRevision=$BaseRevision; files=@(); findings=@(); historicalFindings=@(); reason=''; rawReports=@() }
$reportRoot = [IO.Path]::GetFullPath($ReportDirectory)
$canWriteReport = $false
$pathComparer = if ([IO.Path]::DirectorySeparatorChar -eq '\') { [StringComparer]::OrdinalIgnoreCase } else { [StringComparer]::Ordinal }

function Quote-Argument([string]$Value) {
    # CommandLineToArgvW escaping for Windows PowerShell; PS7 uses ArgumentList directly.
    return '"' + [regex]::Replace([regex]::Replace($Value, '(\\*)"', '$1$1\"'), '(\\+)$', '$1$1') + '"'
}

function Invoke-Tool([string]$Executable, [string[]]$Arguments, [int]$TimeoutSeconds=120) {
    $info = [Diagnostics.ProcessStartInfo]::new()
    $info.FileName = $Executable
    $info.UseShellExecute = $false
    $info.CreateNoWindow = $true
    $info.RedirectStandardOutput = $true
    $info.RedirectStandardError = $true
    $info.StandardOutputEncoding = $utf8
    $info.StandardErrorEncoding = $utf8
    if ($null -ne $info.PSObject.Properties['ArgumentList']) {
        foreach ($argument in $Arguments) { [void]$info.ArgumentList.Add($argument) }
    } else {
        $info.Arguments = ($Arguments | ForEach-Object { Quote-Argument $_ }) -join ' '
    }
    $process = [Diagnostics.Process]::new()
    $process.StartInfo = $info
    try {
        [void]$process.Start()
        $stdout = $process.StandardOutput.ReadToEndAsync()
        $stderr = $process.StandardError.ReadToEndAsync()
        if (-not $process.WaitForExit($TimeoutSeconds * 1000)) {
            if ($PSVersionTable.PSVersion.Major -ge 7) { $process.Kill($true) }
            else { & taskkill.exe /PID $process.Id /T /F 2>$null | Out-Null }
            throw 'Tool execution timed out'
        }
        return @{ exitCode=$process.ExitCode; stdout=$stdout.Result; stderr=$stderr.Result }
    } finally { $process.Dispose() }
}

function Invoke-Git([string[]]$Arguments) {
    $r = Invoke-Tool 'git' (@('-C',$script:repo,'-c','core.quotepath=false') + $Arguments)
    if ($r.exitCode -ne 0) { throw ('Git input could not be resolved: ' + ($Arguments -join ' ')) }
    return $r.stdout
}

function Read-Findings([string]$Path, $PathMap) {
    if (-not [IO.File]::Exists($Path)) { throw 'Checkstyle did not produce XML' }
    $settings = [Xml.XmlReaderSettings]::new()
    $settings.DtdProcessing = [Xml.DtdProcessing]::Prohibit
    $settings.XmlResolver = $null
    $reader = [Xml.XmlReader]::Create($Path,$settings)
    $document = [Xml.XmlDocument]::new()
    $document.XmlResolver = $null
    try { $document.Load($reader) } finally { $reader.Dispose() }
    if ($document.DocumentElement.Name -ne 'checkstyle') { throw 'Unexpected Checkstyle XML' }
    $found = @()
    foreach ($file in $document.SelectNodes('/checkstyle/file')) {
        $absolute = [IO.Path]::GetFullPath($file.GetAttribute('name'))
        if (-not $PathMap.ContainsKey($absolute)) { throw 'Checkstyle returned an unselected file' }
        foreach ($error in $file.SelectNodes('error')) {
            if ($error.GetAttribute('source') -ne 'com.puppycrawl.tools.checkstyle.checks.blocks.NeedBracesCheck') {
                throw ('Java could not be checked: ' + $PathMap[$absolute] + ': ' + $error.GetAttribute('message'))
            }
            $found += [pscustomobject]@{ file=$PathMap[$absolute]; line=[int]$error.GetAttribute('line'); column=[int]$error.GetAttribute('column'); rule='NeedBraces'; message=$error.GetAttribute('message') }
        }
    }
    if ($document.SelectNodes('/checkstyle/file').Count -ne $PathMap.Count) { throw 'Checkstyle report is incomplete' }
    return $found
}

function Map-OldLine([int]$Line, [object[]]$Hunks) {
    $delta = 0
    foreach ($hunk in $Hunks) {
        if ($hunk.oldCount -eq 0) {
            if ($Line -le $hunk.oldStart) { break }
        } else {
            if ($Line -lt $hunk.oldStart) { break }
            if ($Line -lt ($hunk.oldStart + $hunk.oldCount)) { return $null }
        }
        $delta += $hunk.newCount - $hunk.oldCount
    }
    return $Line + $delta
}

try {
    if ([IO.Directory]::Exists($reportRoot) -and [IO.Directory]::GetFileSystemEntries($reportRoot).Length -gt 0) {
        throw 'ReportDirectory must be empty; keep prior evidence in its original directory'
    }
    [void][IO.Directory]::CreateDirectory($reportRoot)
    $canWriteReport = $true
    $selected = @($Files | Where-Object { $_ -match '(?i)\.java$' } | Sort-Object -Unique -CaseSensitive)
    if ($selected.Count -eq 0) {
        $result.result = 'NOT_APPLICABLE'
        $result.reason = 'No Java files selected; no Java tool was started'
    } else {
        $script:repo = [IO.Path]::GetFullPath($RepositoryPath).TrimEnd([IO.Path]::DirectorySeparatorChar)
        if ($BaseRevision.StartsWith('-')) { throw 'BaseRevision must be a Git revision, not an option' }
        $commit = (Invoke-Git @('rev-parse','--verify',($BaseRevision+'^{commit}'))).Trim()
        $result.baseRevision = $commit
        if (-not $CheckstyleJar) { $CheckstyleJar = Join-Path ([Environment]::GetFolderPath('UserProfile')) '.cache/flow-tools/checkstyle/14.1.0/checkstyle-14.1.0-all.jar' }
        if (-not [IO.File]::Exists($CheckstyleJar)) { throw 'Pinned Checkstyle JAR is unavailable; provision the official 14.1.0 release in the tool cache or pass CheckstyleJar' }
        if (-not $JavaExecutable) {
            $JavaExecutable = if ($env:JAVA_HOME) { Join-Path $env:JAVA_HOME 'bin/java' } else { 'java' }
        }
        $javaVersion = Invoke-Tool $JavaExecutable @('-version') 15
        if ($javaVersion.exitCode -ne 0 -or ($javaVersion.stderr+$javaVersion.stdout) -notmatch 'version "(?<major>\d+)') { throw 'Could not determine the tool JDK version' }
        if ([int]$Matches.major -lt 21) { throw 'Checkstyle requires a separate JDK 21 or newer; do not upgrade the business project JDK' }
        $version = Invoke-Tool $JavaExecutable @('-jar',$CheckstyleJar,'--version') 15
        if ($version.exitCode -ne 0 -or $version.stdout.Trim() -ne "Checkstyle version: $toolVersion") { throw 'Checkstyle version does not match pinned 14.1.0' }
        if (-not [IO.File]::Exists($ConfigPath)) { throw 'NeedBraces configuration is missing' }
        $result['toolSha256'] = (Get-FileHash -LiteralPath $CheckstyleJar -Algorithm SHA256).Hash.ToLowerInvariant()
        $renameMap = [Collections.Generic.Dictionary[string,string]]::new($pathComparer)
        foreach ($line in (Invoke-Git @('diff','--name-status','--find-renames',$commit,'--')) -split '\r?\n') {
            $parts = $line -split "`t"
            if ($parts.Count -eq 3 -and $parts[0] -match '^R\d+$') { $renameMap[$parts[2]] = $parts[1] }
        }
        $oldMap = [Collections.Generic.Dictionary[string,string]]::new($pathComparer)
        $newMap = [Collections.Generic.Dictionary[string,string]]::new($pathComparer)
        $hunksByFile = [Collections.Generic.Dictionary[string,object]]::new($pathComparer)
        foreach ($relative in $selected) {
            if ([IO.Path]::IsPathRooted($relative) -or $relative -match '[\r\n\t]' -or ($relative -split '[/\\]') -contains '..') { throw 'Files must be repository-relative paths without traversal or control characters' }
            $relative = $relative.Replace('\','/')
            $current = [IO.Path]::GetFullPath((Join-Path $repo $relative))
            if (-not $current.StartsWith($repo+[IO.Path]::DirectorySeparatorChar,[StringComparison]::OrdinalIgnoreCase)) { throw 'Selected file is outside the repository' }
            $oldRelative = if ($renameMap.ContainsKey($relative)) { $renameMap[$relative] } else { $relative }
            $exists = Invoke-Tool 'git' @('-C',$repo,'cat-file','-e',($commit+':'+$oldRelative))
            if (-not [IO.File]::Exists($current)) {
                if ($exists.exitCode -eq 0) { continue } # A verified deletion has no current code to check.
                throw 'Selected Java file exists neither in the baseline nor the working tree'
            }
            $newMap[$current] = $relative
            if ($exists.exitCode -eq 0) {
                $oldPath = [IO.Path]::GetFullPath((Join-Path (Join-Path $reportRoot 'baseline') $relative))
                [void][IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($oldPath))
                [IO.File]::WriteAllText($oldPath,(Invoke-Git @('show',($commit+':'+$oldRelative))),$utf8)
                $oldMap[$oldPath] = $relative
                $diff = Invoke-Tool 'git' @('diff','--no-index','--no-ext-diff','--unified=0','--',$oldPath,$current)
                if ($diff.exitCode -notin @(0,1)) { throw 'Could not compare baseline and current file' }
                $hunks = @()
                foreach ($match in [regex]::Matches($diff.stdout,'(?m)^@@ -(?<old>\d+)(?:,(?<oc>\d+))? \+(?<new>\d+)(?:,(?<nc>\d+))? @@')) {
                    $hunks += [pscustomobject]@{ oldStart=[int]$match.Groups['old'].Value; oldCount=$(if($match.Groups['oc'].Success){[int]$match.Groups['oc'].Value}else{1}); newCount=$(if($match.Groups['nc'].Success){[int]$match.Groups['nc'].Value}else{1}) }
                }
                $hunksByFile[$relative] = $hunks
            }
        }
        $result.files = @($newMap.Values | Sort-Object)
        if ($newMap.Count -eq 0) {
            $result.result = 'NOT_APPLICABLE'; $result.reason = 'Selected Java files were deleted'
        } else {
            $findings = @{}
            foreach ($mode in @('baseline','current')) {
                $map = if ($mode -eq 'baseline') { $oldMap } else { $newMap }
                if ($map.Count -eq 0) { $findings[$mode] = @(); continue }
                $xmlPath = Join-Path $reportRoot ($mode+'.xml')
                $run = Invoke-Tool $JavaExecutable (@('-jar',$CheckstyleJar,'-c',[IO.Path]::GetFullPath($ConfigPath),'-f','xml','-o',$xmlPath) + @($map.Keys | Sort-Object))
                [IO.File]::WriteAllText((Join-Path $reportRoot ($mode+'.log')),($run.stdout+$run.stderr),$utf8)
                $parsed = @(Read-Findings $xmlPath $map)
                if ($run.exitCode -ne 0 -and $parsed.Count -eq 0) { throw 'Checkstyle failed without usable rule findings' }
                $findings[$mode] = $parsed
                $result.rawReports += $xmlPath
            }
            $known = [Collections.Generic.Dictionary[string,bool]]::new($pathComparer)
            foreach ($old in $findings.baseline) {
                $line = Map-OldLine $old.line @($hunksByFile[$old.file])
                if ($null -ne $line) { $known[($old.file+'|'+$line+'|'+$old.column+'|'+$old.message)] = $true }
            }
            foreach ($finding in $findings.current) {
                $key = $finding.file+'|'+$finding.line+'|'+$finding.column+'|'+$finding.message
                if ($known.ContainsKey($key)) { $result.historicalFindings += $finding }
                else { $result.findings += $finding }
            }
            $result.result = if ($result.findings.Count -gt 0) { 'FAIL' } else { 'PASS' }
            $result.reason = 'Only newly introduced or changed violation locations affect this result; historical findings are reported separately'
        }
    }
} catch {
    $result.result = 'UNVERIFIED'
    $result.reason = $_.Exception.Message
}
$json = $result | ConvertTo-Json -Depth 10
# Do not overwrite a previous invocation's evidence, including on validation failure.
if ($canWriteReport -and -not [IO.File]::Exists((Join-Path $reportRoot 'result.json'))) {
    [void][IO.Directory]::CreateDirectory($reportRoot)
    [IO.File]::WriteAllText((Join-Path $reportRoot 'result.json'),$json,$utf8)
}
Write-Output $json
if ($result.result -in @('PASS','NOT_APPLICABLE')) { exit 0 }
if ($result.result -eq 'FAIL') { exit 1 }
exit 2
