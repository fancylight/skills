[CmdletBinding()]
param(
    [Parameter(Mandatory = $true, Position = 0)]
    [ValidateSet('status', 'next', 'initialize', 'issue-lease', 'validate-lease', 'accept-result', 'record-verifier', 'start-run', 'record-run', 'block')]
    [string]$Command,
    [Parameter(Mandatory = $true)] [string]$StatePath,
    [string]$ChangeName,
    [string]$SystemTestRepo,
    [string]$SutRepo,
    [string]$TestBaselineRevision,
    [string]$TestRevision,
    [string]$ProposedTestRevision,
    [string]$SutRevision,
    [string]$HarnessRevision,
    [string]$HarnessRoot,
    [string]$HarnessCertificationPath,
    [string]$ConfigurationFingerprint,
    [ValidateSet('design', 'implementation', 'execution', 'result')] [string]$Authorization = 'design',
    [ValidateSet('test-implementer', 'verifier', 'runner')] [string]$Role,
    [string]$AgentId,
    [string]$LeaseId,
    [string]$TargetPath,
    [string]$ReportPath,
    [string]$ScopeGuardReportPath,
    [string]$VerifierId,
    [string[]]$Capabilities,
    [ValidateSet('design', 'implementation', 'environment', 'result')] [string]$VerifyMode,
    [ValidateSet('pass', 'fail')] [string]$RunResult,
    [string]$EvidencePath,
    [string]$ScenarioId,
    [string]$FailureCategory,
    [string]$FirstEvidence,
    [string]$Reason,
    [int]$LeaseMinutes = 30,
    [switch]$SimulateWriteFailure
)

$ErrorActionPreference = 'Stop'
$phases = @('TEST_DESIGN_DRAFT','TEST_DESIGN_VERIFIED','TEST_IMPLEMENTING','TEST_IMPLEMENTED','TEST_IMPLEMENTATION_VERIFIED','TEST_ENVIRONMENT_VERIFIED','TEST_EXECUTING','TEST_EXECUTED_PASS','TEST_EXECUTED_FAIL','TEST_RESULT_VERIFIED','BLOCKED')
$ceilingRank = @{ design = 1; implementation = 2; execution = 3; result = 4 }

function Stop-Controller([string]$Code, [string]$Message) {
    Write-Output "[FLOW_CONTROLLER] $Code"
    Write-Output "message: $Message"
    exit 1
}
function Require-Ceiling($State, [string]$Required) {
    if (-not $ceilingRank.ContainsKey($Required) -or -not $ceilingRank.ContainsKey([string]$State.authorization.maxPhase) -or $ceilingRank[[string]$State.authorization.maxPhase] -lt $ceilingRank[$Required]) {
        Stop-Controller 'ERROR_AUTHORIZATION' "required authorization ceiling: $Required"
    }
}
function Get-CanonicalPath([string]$Path) { return [IO.Path]::GetFullPath($Path).TrimEnd('\', '/') }
function Test-SensitiveContent([string]$Value) {
    return -not [string]::IsNullOrWhiteSpace($Value) -and $Value -match '(?i)(password|passwd|token|secret|api[_ -]?key|bearer\s+|connection\s*string|connectionstring)'
}
function Get-GitOutput([string]$Repository, [string[]]$Arguments) {
    $output = @(& git -C $Repository @Arguments 2>$null)
    if ($LASTEXITCODE -ne 0) { Stop-Controller 'ERROR_GIT' "git command failed in canonical repository: $Repository" }
    return $output
}
function Get-CanonicalGitRepo([string]$Path) {
    $candidate = Get-CanonicalPath $Path
    if (-not (Test-Path -LiteralPath $candidate -PathType Container)) { Stop-Controller 'ERROR_REPOSITORY' "repository does not exist: $candidate" }
    $root = (Get-GitOutput $candidate @('rev-parse', '--show-toplevel') | Select-Object -First 1).Trim()
    if ([string]::IsNullOrWhiteSpace($root)) { Stop-Controller 'ERROR_REPOSITORY' "not a Git repository: $candidate" }
    return Get-CanonicalPath $root
}
function Get-GitHead([string]$Repository) {
    $head = (Get-GitOutput $Repository @('rev-parse', '--verify', 'HEAD') | Select-Object -First 1).Trim()
    if ([string]::IsNullOrWhiteSpace($head)) { Stop-Controller 'ERROR_REVISION' "repository has no HEAD: $Repository" }
    return $head
}
function Resolve-GitRevision([string]$Repository, [string]$Revision) {
    if ([string]::IsNullOrWhiteSpace($Revision)) { Stop-Controller 'ERROR_INPUT' 'Git revision is required' }
    return (Get-GitOutput $Repository @('rev-parse', '--verify', "$Revision^{commit}") | Select-Object -First 1).Trim()
}
function Assert-GitAncestor([string]$Repository, [string]$Baseline, [string]$Current) {
    $baselineCommit = Resolve-GitRevision $Repository $Baseline
    $currentCommit = Resolve-GitRevision $Repository $Current
    & git -C $Repository merge-base --is-ancestor $baselineCommit $currentCommit 2>$null
    if ($LASTEXITCODE -ne 0) { Stop-Controller 'ERROR_REVISION_ANCESTRY' "revision is not a descendant of implementation base: $currentCommit" }
}
function Get-GitDiffInfo([string]$Repository, [string]$Baseline, [string]$Current) {
    $baselineCommit = Resolve-GitRevision $Repository $Baseline
    $currentCommit = Resolve-GitRevision $Repository $Current
    Assert-GitAncestor $Repository $baselineCommit $currentCommit
    $changed = @(Get-GitOutput $Repository @('diff', '--name-only', '--diff-filter=ACDMRTUXB', $baselineCommit, $currentCommit) | ForEach-Object { $_.Trim().Replace('\','/') } | Where-Object { $_ })
    $diffLines = @(Get-GitOutput $Repository @('diff', '--no-ext-diff', '--binary', '--full-index', $baselineCommit, $currentCommit))
    $diffText = $diffLines -join "`n"
    [pscustomobject]@{ baseline = $baselineCommit; current = $currentCommit; changedFiles = @($changed | Sort-Object -Unique); diffHash = Get-StringHash $diffText }
}
function Assert-GitWorktreeClean([string]$Repository) {
    $status = @(Get-GitOutput $Repository @('status', '--porcelain=v1', '--untracked-files=all') | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
    if ($status.Count -gt 0) { Stop-Controller 'ERROR_SCOPE_WORKTREE_DIRTY' 'canonical system-test worktree, index, and untracked files must be clean' }
}
function Test-PathWithin([string]$Child, [string]$Parent) {
    $childPath = Get-CanonicalPath $Child; $parentPath = Get-CanonicalPath $Parent
    return $childPath.Equals($parentPath, [StringComparison]::OrdinalIgnoreCase) -or $childPath.StartsWith($parentPath + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)
}
function Get-StateIntegrityHash($State) {
    $previous = $State.integrityHash; $State.integrityHash = ''
    try {
        $bytes = [Text.Encoding]::UTF8.GetBytes(($State | ConvertTo-Json -Depth 16 -Compress))
        $sha = [Security.Cryptography.SHA256]::Create(); try { return (-join ($sha.ComputeHash($bytes) | ForEach-Object { $_.ToString('x2') })) } finally { $sha.Dispose() }
    } finally { $State.integrityHash = $previous }
}
function Read-State {
    function Read-ValidStateFile([string]$Path) {
        if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { throw "state file not found: $Path" }
        $candidate = Get-Content -LiteralPath $Path -Raw -Encoding utf8 | ConvertFrom-Json
        if ([string]::IsNullOrWhiteSpace($candidate.integrityHash) -or $candidate.integrityHash -ne (Get-StateIntegrityHash $candidate)) { throw "state integrity hash does not match: $Path" }
        return $candidate
    }
    try { return Read-ValidStateFile $StatePath }
    catch {
        $primaryError = $_.Exception.Message
        $backupPath = "$StatePath.bak"
        try {
            $backup = Read-ValidStateFile $backupPath
            $restoreTemp = "$StatePath.recover.$([guid]::NewGuid().ToString('N')).tmp"
            try {
                [IO.File]::Copy($backupPath, $restoreTemp, $true)
                Move-Item -LiteralPath $restoreTemp -Destination $StatePath -Force
            }
            finally { if (Test-Path -LiteralPath $restoreTemp) { Remove-Item -LiteralPath $restoreTemp -Force } }
            return $backup
        }
        catch { Stop-Controller 'ERROR_STATE_CORRUPT' "state cannot be read or recovered: $primaryError" }
    }
}
function Write-State($State) {
    $directory = Split-Path -Parent $StatePath
    if (-not (Test-Path -LiteralPath $directory -PathType Container)) { [void](New-Item -ItemType Directory -Path $directory -Force) }
    $temporary = Join-Path $directory ('.automation-state-' + [guid]::NewGuid().ToString('N') + '.tmp')
    $backupPath = "$StatePath.bak"
    $hadPreviousState = Test-Path -LiteralPath $StatePath -PathType Leaf
    try {
        $State.updatedAt = [DateTime]::UtcNow.ToString('o')
        $State.integrityHash = Get-StateIntegrityHash $State
        if ($SimulateWriteFailure) { Stop-Controller 'ERROR_ATOMIC_WRITE' 'injected state write failure' }
        [IO.File]::WriteAllText($temporary, ($State | ConvertTo-Json -Depth 16), [Text.UTF8Encoding]::new($false))
        if ($hadPreviousState) { [IO.File]::Copy($StatePath, $backupPath, $true) }
        Move-Item -LiteralPath $temporary -Destination $StatePath -Force
        [IO.File]::Copy($StatePath, $backupPath, $true)
    } finally { if (Test-Path -LiteralPath $temporary) { Remove-Item -LiteralPath $temporary -Force } }
}
function Read-StructuredJson([string]$Path, [string]$Label) {
    if ([string]::IsNullOrWhiteSpace($Path) -or -not (Test-Path -LiteralPath $Path -PathType Leaf)) { Stop-Controller 'ERROR_INPUT' "$Label is required" }
    if (Test-SensitiveContent $Path) { Stop-Controller 'ERROR_SECRET_INPUT' "$Label path contains sensitive material" }
    try {
        $raw = Get-Content -LiteralPath $Path -Raw -Encoding utf8
        if (Test-SensitiveContent $raw) { Stop-Controller 'ERROR_SECRET_INPUT' "$Label contains sensitive material" }
        return $raw | ConvertFrom-Json
    }
    catch { Stop-Controller 'ERROR_STRUCTURED_OUTPUT' "$Label is not valid JSON" }
}
function Get-StringHash([string]$Value) {
    $bytes = [Text.Encoding]::UTF8.GetBytes($Value)
    $sha = [Security.Cryptography.SHA256]::Create(); try { return (-join ($sha.ComputeHash($bytes) | ForEach-Object { $_.ToString('x2') })) } finally { $sha.Dispose() }
}
function Assert-HarnessCertification([string]$Root, [string]$Path, [string]$ExpectedRevision) {
    if ([string]::IsNullOrWhiteSpace($Root) -or [string]::IsNullOrWhiteSpace($Path)) { Stop-Controller 'ERROR_HARNESS_UNCERTIFIED' 'harness root and certification are required' }
    $canonicalRoot = Get-CanonicalPath $Root
    $canonicalPath = Get-CanonicalPath $Path
    if (-not (Test-PathWithin $canonicalPath $canonicalRoot) -or -not (Test-Path -LiteralPath $canonicalPath -PathType Leaf)) { Stop-Controller 'ERROR_HARNESS_UNCERTIFIED' 'harness certification must be inside the canonical harness root' }
    $certification = Read-StructuredJson $canonicalPath 'harness certification'
    if ($certification.schemaVersion -ne 1 -or $certification.result -ne 'PASS' -or $certification.harnessRevision -ne $ExpectedRevision -or @($certification.files).Count -eq 0) { Stop-Controller 'ERROR_HARNESS_UNCERTIFIED' 'harness certification is incomplete or bound to another revision' }
    $seen = @{}
    foreach ($file in @($certification.files)) {
        $relative = ([string]$file.path).Replace('/', [IO.Path]::DirectorySeparatorChar)
        if ([string]::IsNullOrWhiteSpace($relative) -or $seen.ContainsKey($relative)) { Stop-Controller 'ERROR_HARNESS_UNCERTIFIED' 'harness certification file list is invalid' }
        $seen[$relative] = $true
        $actualPath = Get-CanonicalPath (Join-Path $canonicalRoot $relative)
        if (-not (Test-PathWithin $actualPath $canonicalRoot) -or -not (Test-Path -LiteralPath $actualPath -PathType Leaf)) { Stop-Controller 'ERROR_HARNESS_UNCERTIFIED' "certified harness file is missing: $relative" }
        $actualHash = (Get-FileHash -LiteralPath $actualPath -Algorithm SHA256).Hash.ToLowerInvariant()
        if ($actualHash -ne ([string]$file.sha256).ToLowerInvariant()) { Stop-Controller 'ERROR_HARNESS_UNCERTIFIED' "certified harness file changed: $relative" }
    }
    return [pscustomobject]@{ root=$canonicalRoot; path=$canonicalPath; certificationHash=(Get-FileHash -LiteralPath $canonicalPath -Algorithm SHA256).Hash.ToLowerInvariant() }
}
function Add-History($State, [string]$From, [string]$To, [string]$ReasonText) {
    $State.history += [pscustomobject]@{ at = [DateTime]::UtcNow.ToString('o'); from = $From; to = $To; reason = $ReasonText }
}
function Set-Phase($State, [string]$To, [string]$ReasonText) {
    if ($To -notin $phases) { Stop-Controller 'ERROR_INVALID_PHASE' $To }
    $from = $State.phase; $State.phase = $To; Add-History $State $from $To $ReasonText
}
function Require-RevisionLock($State) {
    if ([string]::IsNullOrWhiteSpace($TestRevision) -or [string]::IsNullOrWhiteSpace($SutRevision) -or [string]::IsNullOrWhiteSpace($HarnessRevision) -or [string]::IsNullOrWhiteSpace($ConfigurationFingerprint)) {
        Stop-Controller 'ERROR_INPUT' 'state-changing commands require test, SUT, harness revisions and configuration fingerprint'
    }
    foreach ($item in @(@('test',$TestRevision), @('sut',$SutRevision), @('harness',$HarnessRevision))) {
        if ($State.revisions.($item[0]) -ne $item[1]) { Stop-Controller 'ERROR_REVISION_DRIFT' "$($item[0]) revision differs from state" }
    }
    if ($State.configurationFingerprint -ne $ConfigurationFingerprint) { Stop-Controller 'ERROR_CONFIGURATION_DRIFT' 'configuration fingerprint differs from state' }
    $actualTestHead = Get-GitHead $State.repositories.systemTest
    $actualSutHead = Get-GitHead $State.repositories.sut
    if ($actualTestHead -ne $State.revisions.test) { Stop-Controller 'ERROR_REVISION_DRIFT' 'canonical system-test HEAD differs from locked test revision' }
    if ($actualSutHead -ne $State.revisions.sut) { Stop-Controller 'ERROR_REVISION_DRIFT' 'canonical SUT HEAD differs from locked SUT revision' }
}
function Require-ImmutableRevisionLock($State) {
    if ([string]::IsNullOrWhiteSpace($SutRevision) -or [string]::IsNullOrWhiteSpace($HarnessRevision) -or [string]::IsNullOrWhiteSpace($ConfigurationFingerprint)) {
        Stop-Controller 'ERROR_INPUT' 'state-changing commands require SUT, harness revisions and configuration fingerprint'
    }
    if ($State.revisions.sut -ne $SutRevision) { Stop-Controller 'ERROR_REVISION_DRIFT' 'sut revision differs from state' }
    if ($State.revisions.harness -ne $HarnessRevision) { Stop-Controller 'ERROR_REVISION_DRIFT' 'harness revision differs from state' }
    if ($State.configurationFingerprint -ne $ConfigurationFingerprint) { Stop-Controller 'ERROR_CONFIGURATION_DRIFT' 'configuration fingerprint differs from state' }
    if ((Get-GitHead $State.repositories.sut) -ne $State.revisions.sut) { Stop-Controller 'ERROR_REVISION_DRIFT' 'canonical SUT HEAD differs from locked SUT revision' }
}
function Get-Fingerprint($State) {
    $input = @($State.phase, $State.revisions.sut, $State.revisions.test, $ScenarioId, $FailureCategory, $FirstEvidence) -join "`n"
    $bytes = [Text.Encoding]::UTF8.GetBytes($input)
    $sha = [Security.Cryptography.SHA256]::Create(); try { return (-join ($sha.ComputeHash($bytes) | ForEach-Object { $_.ToString('x2') })) } finally { $sha.Dispose() }
}

if ($Command -eq 'initialize') {
    if ([string]::IsNullOrWhiteSpace($ChangeName) -or [string]::IsNullOrWhiteSpace($SystemTestRepo) -or [string]::IsNullOrWhiteSpace($SutRepo) -or [string]::IsNullOrWhiteSpace($TestBaselineRevision) -or [string]::IsNullOrWhiteSpace($TestRevision) -or [string]::IsNullOrWhiteSpace($SutRevision) -or [string]::IsNullOrWhiteSpace($HarnessRevision) -or [string]::IsNullOrWhiteSpace($ConfigurationFingerprint)) { Stop-Controller 'ERROR_INPUT' 'initialize requires change, repositories, baseline/current revisions, harness certification, and configuration fingerprint' }
    if ((Test-SensitiveContent $ChangeName) -or (Test-SensitiveContent $ConfigurationFingerprint)) { Stop-Controller 'ERROR_SECRET_INPUT' 'initialize input contains sensitive material' }
    if (Test-Path -LiteralPath $StatePath) { Stop-Controller 'ERROR_STATE_EXISTS' 'refusing to overwrite existing state' }
    $systemRepo = Get-CanonicalGitRepo $SystemTestRepo; $sut = Get-CanonicalGitRepo $SutRepo
    $systemHead = Get-GitHead $systemRepo; $sutHead = Get-GitHead $sut
    if ($systemHead -ne $TestRevision) { Stop-Controller 'ERROR_REVISION_DRIFT' 'test revision must equal canonical system-test HEAD' }
    if ($sutHead -ne $SutRevision) { Stop-Controller 'ERROR_REVISION_DRIFT' 'SUT revision must equal canonical SUT HEAD' }
    $harnessCertification = Assert-HarnessCertification $HarnessRoot $HarnessCertificationPath $HarnessRevision
    $baselineCommit = Resolve-GitRevision $systemRepo $TestBaselineRevision
    $state = [pscustomobject]@{
        schemaVersion = 1; changeName = $ChangeName; phase = 'TEST_DESIGN_DRAFT'; authorization = [pscustomobject]@{ maxPhase = $Authorization }
        repositories = [pscustomobject]@{ systemTest = $systemRepo; sut = $sut }; revisions = [pscustomobject]@{ designRevision = $TestRevision; testBaseRevision = $TestRevision; testBaseline = $baselineCommit; test = $TestRevision; sut = $SutRevision; harness = $HarnessRevision }
        configurationFingerprint = $ConfigurationFingerprint; harnessCertification = $harnessCertification; leases = @(); runs = @(); failureFingerprints = @(); activeRun = $null; scopeVerification = $null; verifier = $null
        history = @(); createdAt = [DateTime]::UtcNow.ToString('o'); updatedAt = [DateTime]::UtcNow.ToString('o'); integrityHash = ''
    }
    Require-Ceiling $state 'design'; Add-History $state '' 'TEST_DESIGN_DRAFT' 'initialize'; Write-State $state; Write-Output '[FLOW_CONTROLLER] PASS'; Write-Output 'phase: TEST_DESIGN_DRAFT'; exit 0
}

$state = Read-State
if ($state.schemaVersion -ne 1 -or $state.phase -notin $phases) { Stop-Controller 'ERROR_STATE_CORRUPT' 'unsupported schema or phase' }
if ($Command -in @('issue-lease','record-verifier','start-run','record-run','block')) { Require-RevisionLock $state }
if ($Command -eq 'accept-result') { Require-ImmutableRevisionLock $state }

switch ($Command) {
    'status' { $state | ConvertTo-Json -Depth 16; exit 0 }
    'next' {
        $next = @{ TEST_DESIGN_DRAFT='VERIFY_DESIGN'; TEST_DESIGN_VERIFIED='ISSUE_IMPLEMENTATION_LEASE'; TEST_IMPLEMENTING='AWAIT_IMPLEMENTATION_RESULT'; TEST_IMPLEMENTED='VERIFY_IMPLEMENTATION'; TEST_IMPLEMENTATION_VERIFIED='VERIFY_ENVIRONMENT'; TEST_ENVIRONMENT_VERIFIED='RUN_ONCE'; TEST_EXECUTING='AWAIT_RUN_RESULT'; TEST_EXECUTED_PASS='VERIFY_RESULT'; TEST_EXECUTED_FAIL='BLOCKED'; TEST_RESULT_VERIFIED='COMPLETE'; BLOCKED='BLOCKED' }[$state.phase]
        Write-Output '[FLOW_CONTROLLER] PASS'; Write-Output "next: $next"; exit 0
    }
    'issue-lease' {
        if ($state.phase -ne 'TEST_DESIGN_VERIFIED' -or $Role -ne 'test-implementer') { Stop-Controller 'ERROR_TRANSITION' 'implementation lease requires TEST_DESIGN_VERIFIED' }
        Require-Ceiling $state 'implementation'
        if ([string]::IsNullOrWhiteSpace($AgentId)) { Stop-Controller 'ERROR_INPUT' 'agent id is required' }
        if (Test-SensitiveContent $AgentId) { Stop-Controller 'ERROR_SECRET_INPUT' 'agent id contains sensitive material' }
        if (@($state.leases | Where-Object { $_.active -and $_.role -eq $Role }).Count -gt 0) { Stop-Controller 'ERROR_LEASE_ACTIVE' 'an implementation lease is already active' }
        $implementationBaseRevision = Get-GitHead $state.repositories.systemTest
        $lease = [pscustomobject]@{ leaseId = [guid]::NewGuid().ToString(); role = $Role; agentId = $AgentId; phase = 'TEST_IMPLEMENTING'; repository = $state.repositories.systemTest; implementationBaseRevision = $implementationBaseRevision; authorizedPaths = @("changes/$($state.changeName)/**", "backend-tests/src/test/$($state.changeName)/**", "backend-tests/src/test/**/$($state.changeName)/**"); allowedCapabilities = @('read','write-test-artifact','test-compile'); forbiddenCapabilities = @('start-service','run-integration','modify-business'); expiresAt = [DateTime]::UtcNow.AddMinutes($LeaseMinutes).ToString('o'); active = $true }
        $state.leases += $lease; Set-Phase $state 'TEST_IMPLEMENTING' 'issue implementation lease'; Write-State $state; Write-Output '[FLOW_CONTROLLER] PASS'; $lease | ConvertTo-Json -Depth 6; exit 0
    }
    'validate-lease' {
        $lease = @($state.leases | Where-Object { $_.leaseId -eq $LeaseId -and $_.active } | Select-Object -First 1)
        if ($lease.Count -ne 1 -or $lease[0].agentId -ne $AgentId -or [DateTimeOffset]::Parse($lease[0].expiresAt).UtcDateTime -le [DateTime]::UtcNow) { Stop-Controller 'ERROR_LEASE_INVALID' 'lease is missing, stale, expired, or owned by another agent' }
        if ($Role -and $lease[0].role -ne $Role) { Stop-Controller 'ERROR_LEASE_INVALID' 'lease role does not match requested role' }
        foreach ($capability in @($Capabilities)) {
            if ($capability -in @($lease[0].forbiddenCapabilities)) { Stop-Controller 'ERROR_CAPABILITY_FORBIDDEN' "capability is forbidden: $capability" }
            if ($capability -notin @($lease[0].allowedCapabilities)) { Stop-Controller 'ERROR_CAPABILITY_NOT_GRANTED' "capability is not granted: $capability" }
        }
        if (-not (Test-PathWithin $TargetPath $lease[0].repository)) { Stop-Controller 'ERROR_CANONICAL_PATH' 'target path is outside the canonical repository' }
        $relative = (Get-CanonicalPath $TargetPath).Substring((Get-CanonicalPath $lease[0].repository).Length + 1).Replace('\','/')
        if (-not (@($lease[0].authorizedPaths | Where-Object { $relative -like $_ }).Count -gt 0)) { Stop-Controller 'ERROR_SCOPE' 'target path is outside the lease allowlist' }
        Write-Output '[FLOW_CONTROLLER] PASS'; Write-Output "lease_id: $LeaseId"; exit 0
    }
    'accept-result' {
        Require-Ceiling $state 'implementation'
        if ($state.phase -ne 'TEST_IMPLEMENTING') { Stop-Controller 'ERROR_TRANSITION' 'implementation result requires TEST_IMPLEMENTING' }
        if ([string]::IsNullOrWhiteSpace($ProposedTestRevision)) { Stop-Controller 'ERROR_INPUT' 'proposed test revision is required' }
        $report = Read-StructuredJson $ReportPath 'implementation report'
        $scope = Read-StructuredJson $ScopeGuardReportPath 'scope guard report'
        $activeLease = @($state.leases | Where-Object { $_.active -and $_.role -eq 'test-implementer' } | Select-Object -First 1)
        if ($activeLease.Count -ne 1) { Stop-Controller 'ERROR_LEASE_INVALID' 'implementation result requires an active implementation lease' }
        $baseRevision = [string]$activeLease[0].implementationBaseRevision
        $proposed = Resolve-GitRevision $state.repositories.systemTest $ProposedTestRevision
        $actualHead = Get-GitHead $state.repositories.systemTest
        if ($proposed -eq $baseRevision) { Stop-Controller 'ERROR_NO_IMPLEMENTATION_REVISION' 'implementation must create a new revision after lease issuance' }
        if ($proposed -ne $actualHead) { Stop-Controller 'ERROR_REVISION_DRIFT' 'proposed test revision must equal canonical system-test HEAD' }
        Assert-GitAncestor $state.repositories.systemTest $baseRevision $proposed
        Assert-GitWorktreeClean $state.repositories.systemTest
        if ($report.result -ne 'PASS' -or $report.testRevision -ne $proposed -or $report.implementationBaseRevision -ne $baseRevision) { Stop-Controller 'ERROR_RESULT' 'implementation report must be PASS and bound to the implementation base and proposed test revision' }
        if ($scope.result -ne 'PASS' -or $scope.repository -ne $state.repositories.systemTest -or $scope.baselineRevision -ne $baseRevision -or $scope.currentRevision -ne $proposed) { Stop-Controller 'ERROR_SCOPE' 'scope guard result is missing or stale' }
        $actualDiff = Get-GitDiffInfo $state.repositories.systemTest $baseRevision $proposed
        $reportedFiles = @($scope.changedFiles | ForEach-Object { ([string]$_).Trim().Replace('\','/') } | Where-Object { $_ })
        $actualFiles = @($actualDiff.changedFiles)
        if ($reportedFiles.Count -ne $actualFiles.Count -or (@($reportedFiles | Sort-Object) -join "`n") -ne (@($actualFiles | Sort-Object) -join "`n")) { Stop-Controller 'ERROR_SCOPE_CHANGED_FILES' 'scope guard did not report the exact canonical Git changed-file set' }
        foreach ($path in $actualFiles) {
            if ($path -match '(^|/)\.\.(/|$)' -or -not (@($activeLease[0].authorizedPaths | Where-Object { $path -like $_ }).Count -gt 0)) { Stop-Controller 'ERROR_SCOPE' "actual changed file is outside the lease allowlist: $path" }
        }
        if ([string]$scope.diffHash -ne $actualDiff.diffHash) { Stop-Controller 'ERROR_SCOPE_DIFF_HASH' 'scope diffHash does not match controller-computed canonical Git diff' }
        $state.revisions.test = $proposed
        $state.scopeVerification = [pscustomobject]@{ result='PASS'; baselineRevision=$actualDiff.baseline; currentRevision=$actualDiff.current; repository=$state.repositories.systemTest; diffHash=$actualDiff.diffHash; changedFiles=@($actualFiles); at=[DateTime]::UtcNow.ToString('o') }
        $state.leases | Where-Object { $_.active } | ForEach-Object { $_.active = $false }; Set-Phase $state 'TEST_IMPLEMENTED' 'accepted trusted scope guard result'; Write-State $state; Write-Output '[FLOW_CONTROLLER] PASS'; exit 0
    }
    'record-verifier' {
        if ([string]::IsNullOrWhiteSpace($VerifyMode)) { Stop-Controller 'ERROR_INPUT' 'verify mode is required' }
        if ([string]::IsNullOrWhiteSpace($VerifierId)) { Stop-Controller 'ERROR_INPUT' 'verifier identity is required' }
        if (Test-SensitiveContent $VerifierId) { Stop-Controller 'ERROR_SECRET_INPUT' 'verifier identity contains sensitive material' }
        $requiredCeiling = @{ design='design'; implementation='implementation'; environment='execution'; result='result' }[$VerifyMode]
        Require-Ceiling $state $requiredCeiling
        $expected = @{ design='TEST_DESIGN_DRAFT'; implementation='TEST_IMPLEMENTED'; environment='TEST_IMPLEMENTATION_VERIFIED'; result='TEST_EXECUTED_PASS' }[$VerifyMode]
        $target = @{ design='TEST_DESIGN_VERIFIED'; implementation='TEST_IMPLEMENTATION_VERIFIED'; environment='TEST_ENVIRONMENT_VERIFIED'; result='TEST_RESULT_VERIFIED' }[$VerifyMode]
        if ($state.phase -ne $expected -or $TestRevision -ne $state.revisions.test) { Stop-Controller 'ERROR_VERIFIER_REVISION' 'verifier phase or revision does not match state' }
        $report = Read-StructuredJson $ReportPath 'verifier report'
        if ($report.result -ne 'PASS' -or $report.mode -ne $VerifyMode -or $report.verifierId -ne $VerifierId -or $report.testRevision -ne $state.revisions.test -or $report.sutRevision -ne $state.revisions.sut -or $report.harnessRevision -ne $state.revisions.harness -or $report.configurationFingerprint -ne $state.configurationFingerprint -or [string]::IsNullOrWhiteSpace([string]$report.summary)) { Stop-Controller 'ERROR_VERIFIER_REPORT' 'verifier report is not a bound structured PASS' }
        $state.verifier = [pscustomobject]@{ identity=$VerifierId; mode=$VerifyMode; testRevision=$report.testRevision; sutRevision=$report.sutRevision; harnessRevision=$report.harnessRevision; configurationFingerprint=$report.configurationFingerprint; summaryHash=(Get-StringHash ([string]$report.summary)); at=[DateTime]::UtcNow.ToString('o') }
        Set-Phase $state $target "record $VerifyMode verifier"; Write-State $state; Write-Output '[FLOW_CONTROLLER] PASS'; exit 0
    }
    'start-run' {
        Require-Ceiling $state 'execution'
        [void](Assert-HarnessCertification $state.harnessCertification.root $state.harnessCertification.path $state.revisions.harness)
        if ([string]::IsNullOrWhiteSpace($TestRevision) -or [string]::IsNullOrWhiteSpace($SutRevision) -or [string]::IsNullOrWhiteSpace($HarnessRevision) -or [string]::IsNullOrWhiteSpace($ConfigurationFingerprint) -or $TestRevision -ne $state.revisions.test -or $SutRevision -ne $state.revisions.sut -or $HarnessRevision -ne $state.revisions.harness -or $ConfigurationFingerprint -ne $state.configurationFingerprint) { Stop-Controller 'ERROR_REVISION_DRIFT' 'runner start must bind current test, SUT, harness, and configuration revisions' }
        if ($null -ne $state.activeRun -or @($state.runs | Where-Object { $_.testRevision -eq $state.revisions.test }).Count -gt 0) { Stop-Controller 'ERROR_RUN_DUPLICATE' 'runner already started for this test revision' }
        if ($state.phase -ne 'TEST_ENVIRONMENT_VERIFIED') { Stop-Controller 'ERROR_TRANSITION' "runner start phase is $($state.phase)" }
        $state.activeRun = [pscustomobject]@{ runId=[guid]::NewGuid().ToString(); testRevision=$state.revisions.test; sutRevision=$state.revisions.sut; harnessRevision=$state.revisions.harness; configurationFingerprint=$state.configurationFingerprint; startedAt=[DateTime]::UtcNow.ToString('o') }
        Set-Phase $state 'TEST_EXECUTING' 'persist runner start authorization'; Write-State $state; Write-Output '[FLOW_CONTROLLER] PASS'; Write-Output "run_id: $($state.activeRun.runId)"; exit 0
    }
    'record-run' {
        Require-Ceiling $state 'execution'
        if ($state.phase -ne 'TEST_EXECUTING' -or $null -eq $state.activeRun) { Stop-Controller 'ERROR_TRANSITION' 'runner result requires a persisted TEST_EXECUTING state' }
        if ([string]::IsNullOrWhiteSpace($TestRevision) -or [string]::IsNullOrWhiteSpace($SutRevision) -or [string]::IsNullOrWhiteSpace($HarnessRevision) -or [string]::IsNullOrWhiteSpace($ConfigurationFingerprint) -or $state.activeRun.testRevision -ne $TestRevision -or $state.activeRun.sutRevision -ne $SutRevision -or $state.activeRun.harnessRevision -ne $HarnessRevision -or $state.activeRun.configurationFingerprint -ne $ConfigurationFingerprint) { Stop-Controller 'ERROR_REVISION_DRIFT' 'runner result revisions or configuration differ from persisted run' }
        if (Test-SensitiveContent $EvidencePath) { Stop-Controller 'ERROR_SECRET_INPUT' 'evidence path contains sensitive material' }
        if ([string]::IsNullOrWhiteSpace($RunResult) -or -not (Test-Path -LiteralPath $EvidencePath)) { Stop-Controller 'ERROR_INPUT' 'run result and evidence path are required' }
        if ($RunResult -eq 'pass') { Set-Phase $state 'TEST_EXECUTED_PASS' 'runner evidence pass' }
        else {
            $fingerprint = Get-Fingerprint $state
            if ($state.failureFingerprints -contains $fingerprint) { Stop-Controller 'ERROR_FAILURE_DUPLICATE' 'failure fingerprint already exists' }
            $state.failureFingerprints += $fingerprint; Set-Phase $state 'TEST_EXECUTED_FAIL' 'runner evidence fail'
        }
        $state.runs += [pscustomobject]@{ runId=$state.activeRun.runId; testRevision=$state.revisions.test; result=$RunResult; evidence=$EvidencePath; at=[DateTime]::UtcNow.ToString('o') }; $state.activeRun = $null; Write-State $state; Write-Output '[FLOW_CONTROLLER] PASS'; exit 0
    }
    'block' {
        if (Test-SensitiveContent $Reason) { Stop-Controller 'ERROR_SECRET_INPUT' 'block reason contains sensitive material' }
        Set-Phase $state 'BLOCKED' $(if ($Reason) { $Reason } else { 'blocked by controller' }); Write-State $state; Write-Output '[FLOW_CONTROLLER] PASS'; exit 0
    }
}
