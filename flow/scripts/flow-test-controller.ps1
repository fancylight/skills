[CmdletBinding()]
param(
    [Parameter(Mandatory = $true, Position = 0)]
    [ValidateSet('status', 'next', 'initialize', 'grant-authorization', 'reopen-design', 'accept-design-revision', 'record-scope-review', 'issue-lease', 'validate-lease', 'accept-result', 'repair-derived-artifacts', 'record-verifier', 'start-run', 'record-run', 'retry-harness-failure', 'retry-test-infra-failure', 'execution', 'block')]
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
    [switch]$SimulateWriteFailure,
    [ValidateSet('prepare','resume','review','environment','start','finish','result','status','import','revise','review-design','rebind')] [string]$Action,
    [string[]]$ScenarioIds
)

$ErrorActionPreference = 'Stop'
$phases = @('TEST_DESIGN_DRAFT','TEST_DESIGN_VERIFIED','TEST_IMPLEMENTING','TEST_IMPLEMENTED','TEST_IMPLEMENTATION_VERIFIED','TEST_ENVIRONMENT_VERIFIED','TEST_ENVIRONMENT_FAILED','TEST_EXECUTING','TEST_EXECUTED_PASS','TEST_EXECUTED_FAIL','TEST_RESULT_VERIFIED','BLOCKED')
$ceilingRank = @{ design = 1; implementation = 2; execution = 3; result = 4 }

function Stop-Controller([string]$Code, [string]$Message) {
    Write-Output "[FLOW_CONTROLLER] $Code"
    Write-Output "message: $Message"
    $next=if($Code -match 'BUDGET'){'CLEANUP_AND_REPORT'}elseif($Code -match 'AUTHORIZATION'){'USE_EXISTING_GRANT_OR_REQUEST_MISSING_AUTHORIZATION'}elseif($Code -match 'STATE_CORRUPT|REPOSITORY'){'INVESTIGATE_IDENTITY_OR_STATE'}else{'DIAGNOSE_AND_REPAIR_WITHIN_AUTHORIZATION'}
    [ordered]@{status='ACTION_REJECTED';reason=$Code;affectedAction=$Command;nextAction=$next;evidencePath=$StatePath;taskStopped=$false} | ConvertTo-Json -Compress
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
    $output = @(& git -c core.longpaths=true -C $Repository @Arguments 2>$null)
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
function Assert-HarnessRepairWorktreeClean([string]$Repository, [string]$CurrentChangeName) {
    $status = @(Get-GitOutput $Repository @('status', '--porcelain=v1', '--untracked-files=all') | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
    foreach ($line in $status) {
        $path = ([string]$line).Substring(3).Trim().Replace('\','/')
        if ($path -notlike "changes/$CurrentChangeName/evidence/*") {
            Stop-Controller 'ERROR_SCOPE_WORKTREE_DIRTY' "canonical system-test worktree contains non-evidence drift: $path"
        }
    }
}
function Test-PathWithin([string]$Child, [string]$Parent) {
    $childPath = Get-CanonicalPath $Child; $parentPath = Get-CanonicalPath $Parent
    return $childPath.Equals($parentPath, [StringComparison]::OrdinalIgnoreCase) -or $childPath.StartsWith($parentPath + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)
}
function Get-ImplementationAuthorizedPaths([string]$CurrentChangeName) {
    return @(
        "changes/$CurrentChangeName/**",
        'backend-tests/pom.xml',
        "backend-tests/src/test/$CurrentChangeName/**",
        "backend-tests/src/test/**/$CurrentChangeName/**",
        "test-support/src/main/**/$CurrentChangeName/**",
        "config/**/$CurrentChangeName/**",
        "infra/**/$CurrentChangeName/**"
    )
}
function Get-EffectiveLeaseAuthorizedPaths($State, $Lease) {
    return @(@($Lease.authorizedPaths) + @(Get-ImplementationAuthorizedPaths ([string]$State.changeName)) | Sort-Object -Unique)
}
function Get-StateIntegrityHash($State) {
    $previous = $State.integrityHash; $State.integrityHash = ''
    try {
        $bytes = [Text.Encoding]::UTF8.GetBytes(($State | ConvertTo-Json -Depth 16 -Compress))
        $sha = [Security.Cryptography.SHA256]::Create(); try { return (-join ($sha.ComputeHash($bytes) | ForEach-Object { $_.ToString('x2') })) } finally { $sha.Dispose() }
    } finally { $State.integrityHash = $previous }
}
function ConvertFrom-StateJson([string]$Raw) {
    $convert = Get-Command ConvertFrom-Json
    if ($convert.Parameters.ContainsKey('DateKind')) { return $Raw | ConvertFrom-Json -DateKind String }
    return $Raw | ConvertFrom-Json
}
function Read-State {
    function Read-ValidStateFile([string]$Path) {
        if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { throw "state file not found: $Path" }
        $raw=Get-Content -LiteralPath $Path -Raw -Encoding utf8
        $candidate = ConvertFrom-StateJson $raw
        if ($candidate.integrityHash -ne (Get-StateIntegrityHash $candidate)) {
            . (Join-Path $PSScriptRoot '../templates/system-test/scripts/test-runtime-contract.ps1')
            if ([string]::IsNullOrWhiteSpace($candidate.integrityHash) -or $candidate.integrityHash -ne (Get-TestStateIntegrityHashFromRaw $raw)) { throw "state integrity hash does not match: $Path" }
        }
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
        return ConvertFrom-StateJson $raw
    }
    catch { Stop-Controller 'ERROR_STRUCTURED_OUTPUT' "$Label is not valid JSON" }
}
function Get-StringHash([string]$Value) {
    $bytes = [Text.Encoding]::UTF8.GetBytes($Value)
    $sha = [Security.Cryptography.SHA256]::Create(); try { return (-join ($sha.ComputeHash($bytes) | ForEach-Object { $_.ToString('x2') })) } finally { $sha.Dispose() }
}
function Get-FileHashValue([string]$Path) {
    $stream = [IO.File]::OpenRead($Path); $sha = [Security.Cryptography.SHA256]::Create()
    try { return -join ($sha.ComputeHash($stream) | ForEach-Object { $_.ToString('x2') }) }
    finally { $sha.Dispose(); $stream.Dispose() }
}
function Assert-HarnessCertification([string]$Root, [string]$Path, [string]$ExpectedRevision) {
    if ([string]::IsNullOrWhiteSpace($Root) -or [string]::IsNullOrWhiteSpace($Path)) { Stop-Controller 'ERROR_HARNESS_UNCERTIFIED' 'harness root and certification are required' }
    $canonicalRoot = Get-CanonicalPath $Root
    $canonicalPath = Get-CanonicalPath $Path
    if (-not (Test-PathWithin $canonicalPath $canonicalRoot) -or -not (Test-Path -LiteralPath $canonicalPath -PathType Leaf)) { Stop-Controller 'ERROR_HARNESS_UNCERTIFIED' 'harness certification must be inside the canonical harness root' }
    $canonicalVerifier = Get-CanonicalPath (Join-Path $canonicalRoot 'scripts\harness-certification.ps1')
    if (-not (Test-PathWithin $canonicalVerifier $canonicalRoot) -or -not (Test-Path -LiteralPath $canonicalVerifier -PathType Leaf)) { Stop-Controller 'ERROR_HARNESS_UNCERTIFIED' 'formal harness certification verifier must be inside the canonical harness root' }
    $verificationFailed = $false
    try { $output = @(& $canonicalVerifier verify -HarnessRoot $canonicalRoot -CertificationPath $canonicalPath 2>&1) }
    catch { $output = @($_); $verificationFailed = $true }
    if ($verificationFailed -or $LASTEXITCODE -ne 0) { Stop-Controller 'ERROR_HARNESS_UNCERTIFIED' 'formal harness certification verification failed' }
    $revisionLines = @($output | ForEach-Object { [string]$_ } | Where-Object { $_ -match '^harness_revision:\s*\S+\s*$' })
    if ($revisionLines.Count -ne 1) { Stop-Controller 'ERROR_HARNESS_UNCERTIFIED' 'formal harness certification verifier did not emit exactly one harness revision' }
    $verifiedRevision = ($revisionLines[0] -replace '^harness_revision:\s*', '').Trim()
    if ($verifiedRevision -ne $ExpectedRevision) { Stop-Controller 'ERROR_HARNESS_UNCERTIFIED' 'formal harness certification revision differs from the expected harness revision' }
    return [pscustomobject]@{ root=$canonicalRoot; path=$canonicalPath; certificationHash=(Get-FileHashValue $canonicalPath) }
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

function Read-AuthorizationGrant($State, [string]$Previous) {
    $grant = Read-StructuredJson $ReportPath 'user authorization grant'
    if ($grant.schemaVersion -ne 1 -or $grant.grantedBy -ne 'user' -or $grant.previousCeiling -ne $Previous -or
        $grant.ceiling -ne $Authorization -or $grant.changeName -ne $State.changeName -or
        $grant.testRevision -ne $State.revisions.test -or $grant.sutRevision -ne $State.revisions.sut -or
        $grant.harnessRevision -ne $State.revisions.harness -or $grant.configurationFingerprint -ne $State.configurationFingerprint -or
        [string]::IsNullOrWhiteSpace([string]$grant.requestRef) -or [string]::IsNullOrWhiteSpace([string]$grant.requestText)) {
        Stop-Controller 'ERROR_AUTHORIZATION' 'grant must contain an explicit user request and match change, previous/new ceiling and locked revisions/configuration'
    }
    # Audit record, not a signature or a substitute for actual user authorization.
    return [pscustomobject]@{ at=[DateTime]::UtcNow.ToString('o'); previousCeiling=$Previous; ceiling=$Authorization; grantedBy='user'; requestRef=[string]$grant.requestRef; requestText=[string]$grant.requestText; reportSha256=(Get-FileHashValue $ReportPath); testRevision=$State.revisions.test; sutRevision=$State.revisions.sut; harnessRevision=$State.revisions.harness; configurationFingerprint=$State.configurationFingerprint }
}
function Assert-DesignRevisionWindow($State) {
    Require-Ceiling $State 'design'
    if ($State.phase -notin @('TEST_DESIGN_DRAFT','TEST_DESIGN_VERIFIED') -or @($State.leases).Count -gt 0 -or @($State.runs).Count -gt 0 -or $null -ne $State.activeRun) {
        Stop-Controller 'ERROR_TRANSITION' 'design revision is only supported before implementation leasing and execution'
    }
}

# Serialize every canonical state transition, including compatibility commands.
$stateDirectory=Split-Path -Parent ([IO.Path]::GetFullPath($StatePath))
[void](New-Item -ItemType Directory -Force -Path $stateDirectory)
$stateLock=$null
try {
    try { $stateLock=[IO.File]::Open(([IO.Path]::GetFullPath($StatePath)+'.controller.lock'),'OpenOrCreate','ReadWrite','None') }
    catch { Stop-Controller 'ERROR_STATE_BUSY' 'Another controller transition is active; inspect status after it completes' }
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
    $initialManifest = Join-Path $systemRepo "changes/$ChangeName/manifest.yaml"
    if (Test-Path -LiteralPath $initialManifest -PathType Leaf) {
        $manifestJson = @(Get-GitOutput $systemRepo @('show', "${TestRevision}:changes/$ChangeName/manifest.yaml")) -join "`n"
        $manifestGrant = ($manifestJson | ConvertFrom-Json).testAuthorization
        if ($manifestGrant.ceiling -ne $Authorization -or $manifestGrant.grantedBy -ne 'user') { Stop-Controller 'ERROR_AUTHORIZATION' 'initialize ceiling must match the committed manifest initial user grant' }
    }
    if ($Authorization -ne 'design' -or $ReportPath) {
        $grant = Read-AuthorizationGrant $state 'none'
        $state.authorization | Add-Member -NotePropertyName grants -NotePropertyValue @($grant)
    }
    Require-Ceiling $state 'design'; Add-History $state '' 'TEST_DESIGN_DRAFT' 'initialize'; Write-State $state; Write-Output '[FLOW_CONTROLLER] PASS'; Write-Output 'phase: TEST_DESIGN_DRAFT'; exit 0
}

$state = Read-State
if ($state.schemaVersion -ne 1 -or $state.phase -notin $phases) { Stop-Controller 'ERROR_STATE_CORRUPT' 'unsupported schema or phase' }
if ($Command -eq 'execution') {
    . (Join-Path $PSScriptRoot 'controller-execution.ps1')
    Invoke-Execution $state
    exit 0
}
if ($state.PSObject.Properties['execution'] -and $Command -eq 'next') {
    . (Join-Path $PSScriptRoot 'controller-execution.ps1')
    $summary=Get-ExecutionSummary $state
    Write-Output '[FLOW_CONTROLLER] PASS'
    Write-Output "next: $($summary.next)"
    Write-Output 'entry: flow-test.ps1'
    exit 0
}
if ($state.PSObject.Properties['execution'] -and $Command -notin @('status','next','grant-authorization','validate-lease')) {
    Stop-Controller 'ERROR_EXECUTION_ENTRY' 'This change uses flow-test.ps1; use prepare/advance/resume/status. Legacy writes cannot reset its budget or current results.'
}
if ($Command -in @('grant-authorization','reopen-design','issue-lease','record-verifier','start-run','record-run','block')) { Require-RevisionLock $state }
if ($Command -in @('accept-design-revision','accept-result','repair-derived-artifacts','record-scope-review')) { Require-ImmutableRevisionLock $state }

switch ($Command) {
    'record-scope-review' {
        . (Join-Path $PSScriptRoot 'controller-scope-review.ps1')
        Record-ImplementationScopeReview $state
        exit 0
    }
    'status' { $state | ConvertTo-Json -Depth 16; exit 0 }
    'next' {
        $next = @{ TEST_DESIGN_DRAFT='VERIFY_DESIGN'; TEST_DESIGN_VERIFIED='ISSUE_IMPLEMENTATION_LEASE'; TEST_IMPLEMENTING='AWAIT_IMPLEMENTATION_RESULT'; TEST_IMPLEMENTED='VERIFY_IMPLEMENTATION'; TEST_IMPLEMENTATION_VERIFIED='VERIFY_ENVIRONMENT'; TEST_ENVIRONMENT_VERIFIED='RUN_ONCE'; TEST_EXECUTING='AWAIT_RUN_RESULT'; TEST_EXECUTED_PASS='VERIFY_RESULT'; TEST_EXECUTED_FAIL='BLOCKED'; TEST_RESULT_VERIFIED='COMPLETE'; BLOCKED='BLOCKED' }[$state.phase]
        $skill = @{ VERIFY_DESIGN='flow-codex-test-verify'; ISSUE_IMPLEMENTATION_LEASE='flow-codex-test-assign'; AWAIT_IMPLEMENTATION_RESULT='flow-codex-test-receive/apply/report'; VERIFY_IMPLEMENTATION='flow-codex-test-verify'; VERIFY_ENVIRONMENT='flow-codex-test'; RUN_ONCE='flow-codex-system-test'; AWAIT_RUN_RESULT='flow-codex-system-test'; VERIFY_RESULT='flow-codex-test-verify'; COMPLETE='flow-codex-test'; BLOCKED='none' }[$next]
        $required = @{ ISSUE_IMPLEMENTATION_LEASE='implementation'; AWAIT_IMPLEMENTATION_RESULT='implementation'; VERIFY_IMPLEMENTATION='implementation'; VERIFY_ENVIRONMENT='execution'; RUN_ONCE='execution'; AWAIT_RUN_RESULT='execution'; VERIFY_RESULT='result' }[$next]
        if ($required -and $ceilingRank[[string]$state.authorization.maxPhase] -lt $ceilingRank[$required]) { $next='STOP_AWAIT_USER_AUTHORIZATION'; $skill='none' }
        Write-Output '[FLOW_CONTROLLER] PASS'; Write-Output "phase: $($state.phase)"; Write-Output "next: $next"; Write-Output "skill: $skill"; Write-Output "lease_required: $($next -in @('ISSUE_IMPLEMENTATION_LEASE','AWAIT_IMPLEMENTATION_RESULT'))"; exit 0
    }
    'grant-authorization' {
        if ($ceilingRank[$Authorization] -le $ceilingRank[[string]$state.authorization.maxPhase]) { Stop-Controller 'ERROR_AUTHORIZATION' 'grant must strictly increase the ceiling; downgrade, reset and replay are forbidden' }
        $grant = Read-AuthorizationGrant $state ([string]$state.authorization.maxPhase)
        $certification = Assert-HarnessCertification $state.harnessCertification.root $state.harnessCertification.path $state.revisions.harness
        if ($certification.certificationHash -ne $state.harnessCertification.certificationHash) { Stop-Controller 'ERROR_HARNESS_UNCERTIFIED' 'locked harness certification changed' }
        if ($null -eq $state.authorization.PSObject.Properties['grants']) { $state.authorization | Add-Member -NotePropertyName grants -NotePropertyValue @() }
        $state.authorization.grants += $grant
        $state.authorization.maxPhase = $Authorization
        Add-History $state $state.phase $state.phase 'explicit user authorization grant'
        Write-State $state; Write-Output '[FLOW_CONTROLLER] PASS'; Write-Output "authorization_ceiling: $Authorization"; exit 0
    }
    'reopen-design' {
        Assert-DesignRevisionWindow $state
        if ([string]::IsNullOrWhiteSpace($Reason) -or (Test-SensitiveContent $Reason)) { Stop-Controller 'ERROR_INPUT' 'a non-sensitive design revision reason is required' }
        if ($null -eq $state.PSObject.Properties['designRevisions']) { $state | Add-Member -NotePropertyName designRevisions -NotePropertyValue @() }
        $state.designRevisions += [pscustomobject]@{ at=[DateTime]::UtcNow.ToString('o'); revision=$state.revisions.test; verifier=$state.verifier; reason=$Reason }
        $state.verifier = $null
        Set-Phase $state 'TEST_DESIGN_DRAFT' $Reason
        Write-State $state; Write-Output '[FLOW_CONTROLLER] PASS'; exit 0
    }
    'accept-design-revision' {
        Assert-DesignRevisionWindow $state
        if ($state.phase -ne 'TEST_DESIGN_DRAFT' -or $TestRevision -ne $state.revisions.test) { Stop-Controller 'ERROR_REVISION_DRIFT' 'reopen design before accepting a new design revision; supply the locked old TestRevision' }
        $proposed = Resolve-GitRevision $state.repositories.systemTest $ProposedTestRevision
        if ($proposed -eq $TestRevision -or $proposed -ne (Get-GitHead $state.repositories.systemTest)) { Stop-Controller 'ERROR_REVISION_DRIFT' 'proposed design must be a new canonical HEAD' }
        Assert-GitWorktreeClean $state.repositories.systemTest
        $diff = Get-GitDiffInfo $state.repositories.systemTest $TestRevision $proposed
        $prefix = "changes/$($state.changeName)/"
        $allowed = @('test-design.md','test-plan.md','test-cases.yaml','test-cases.generated.json')
        foreach ($file in $diff.changedFiles) {
            if (-not $file.StartsWith($prefix) -or $file.Substring($prefix.Length) -notin $allowed) { Stop-Controller 'ERROR_SCOPE' 'design revalidation only changes canonical cases and design/plan/sidecar; configuration, fixtures and implementation remain locked' }
        }
        # Static guard precedes revision acceptance; semantic review follows in VERIFY_DESIGN.
        $guard = Join-Path $PSScriptRoot 'validate-test-artifacts.ps1'
        $guardOutput = @(& $guard -SystemTestRepo $state.repositories.systemTest -ChangeName $state.changeName -Mode design -CanonicalRevision $state.revisions.testBaseline 2>&1)
        if ($LASTEXITCODE -ne 0) { Stop-Controller 'ERROR_DESIGN_ARTIFACTS' ($guardOutput -join ' | ') }
        # Required scenarios cannot disappear or be weakened in this compatibility migration.
        $sourcePath = $prefix + 'test-cases.yaml'
        $oldSource = @(Get-GitOutput $state.repositories.systemTest @('show', "${TestRevision}:$sourcePath")) -join "`n"
        $previousPath = Join-Path ([IO.Path]::GetTempPath()) ('flow-previous-cases-' + [guid]::NewGuid().ToString('N') + '.yaml')
        try {
            [IO.File]::WriteAllText($previousPath, $oldSource, [Text.UTF8Encoding]::new($false))
            $caseValidator = Join-Path $PSScriptRoot 'validate-test-cases.ps1'
            $coverageOutput = @(& $caseValidator -TestCasesPath (Join-Path $state.repositories.systemTest $sourcePath) -PreviousTestCasesPath $previousPath -PreserveRequiredCoverage 2>&1)
            if ($LASTEXITCODE -ne 0) { Stop-Controller 'ERROR_SCOPE' ($coverageOutput -join ' | ') }
        } finally { if (Test-Path -LiteralPath $previousPath) { Remove-Item -LiteralPath $previousPath -Force } }
        $state.revisions.test = $proposed; $state.revisions.designRevision = $proposed; $state.revisions.testBaseRevision = $proposed
        $state.verifier = $null
        Add-History $state $state.phase $state.phase ("accepted design revision " + $proposed)
        Write-State $state; Write-Output '[FLOW_CONTROLLER] PASS'; Write-Output 'next: VERIFY_DESIGN'; exit 0
    }
    'issue-lease' {
        if ($state.phase -ne 'TEST_DESIGN_VERIFIED' -or $Role -ne 'test-implementer') { Stop-Controller 'ERROR_TRANSITION' 'implementation lease requires TEST_DESIGN_VERIFIED' }
        Require-Ceiling $state 'implementation'
        if ([string]::IsNullOrWhiteSpace($AgentId)) { Stop-Controller 'ERROR_INPUT' 'agent id is required' }
        if (Test-SensitiveContent $AgentId) { Stop-Controller 'ERROR_SECRET_INPUT' 'agent id contains sensitive material' }
        if (@($state.leases | Where-Object { $_.active -and $_.role -eq $Role }).Count -gt 0) { Stop-Controller 'ERROR_LEASE_ACTIVE' 'an implementation lease is already active' }
        $implementationBaseRevision = Get-GitHead $state.repositories.systemTest
        $lease = [pscustomobject]@{ leaseId = [guid]::NewGuid().ToString(); role = $Role; agentId = $AgentId; phase = 'TEST_IMPLEMENTING'; repository = $state.repositories.systemTest; implementationBaseRevision = $implementationBaseRevision; authorizedPaths = @(Get-ImplementationAuthorizedPaths ([string]$state.changeName)); allowedCapabilities = @('read','write-test-artifact','test-compile'); forbiddenCapabilities = @('start-service','run-integration','modify-business'); expiresAt = [DateTime]::UtcNow.AddMinutes($LeaseMinutes).ToString('o'); active = $true }
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
        $effectiveAuthorizedPaths = @(Get-EffectiveLeaseAuthorizedPaths $state $lease[0])
        if (-not (@($effectiveAuthorizedPaths | Where-Object { $relative -like $_ }).Count -gt 0)) { Stop-Controller 'ERROR_SCOPE' 'target path is outside the lease allowlist' }
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
        $effectiveAuthorizedPaths = @(Get-EffectiveLeaseAuthorizedPaths $state $activeLease[0])
        foreach ($path in $actualFiles) {
            if ($path -match '(^|/)\.\.(/|$)' -or -not (@($effectiveAuthorizedPaths | Where-Object { $path -like $_ }).Count -gt 0)) { Stop-Controller 'ERROR_SCOPE' "actual changed file is outside the lease allowlist: $path" }
        }
        if ([string]$scope.diffHash -ne $actualDiff.diffHash) { Stop-Controller 'ERROR_SCOPE_DIFF_HASH' 'scope diffHash does not match controller-computed canonical Git diff' }
        $state.revisions.test = $proposed
        $state.scopeVerification = [pscustomobject]@{ result='PASS'; baselineRevision=$actualDiff.baseline; currentRevision=$actualDiff.current; repository=$state.repositories.systemTest; diffHash=$actualDiff.diffHash; changedFiles=@($actualFiles); at=[DateTime]::UtcNow.ToString('o') }
        $state.leases | Where-Object { $_.active } | ForEach-Object { $_.active = $false }; Set-Phase $state 'TEST_IMPLEMENTED' 'accepted trusted scope guard result'; Write-State $state; Write-Output '[FLOW_CONTROLLER] PASS'; exit 0
    }
    'repair-derived-artifacts' {
        Require-Ceiling $state 'implementation'
        if ($state.phase -ne 'TEST_IMPLEMENTED') { Stop-Controller 'ERROR_TRANSITION' 'derived artifact repair requires TEST_IMPLEMENTED' }
        if ([string]::IsNullOrWhiteSpace($ProposedTestRevision)) { Stop-Controller 'ERROR_INPUT' 'proposed test revision is required' }
        $report = Read-StructuredJson $ReportPath 'derived artifact repair report'
        $oldTestRevision = [string]$state.revisions.test
        $proposed = Resolve-GitRevision $state.repositories.systemTest $ProposedTestRevision
        if ($proposed -eq $oldTestRevision -or $proposed -ne (Get-GitHead $state.repositories.systemTest)) { Stop-Controller 'ERROR_REVISION_DRIFT' 'derived artifact repair must create the canonical system-test HEAD' }
        Assert-GitAncestor $state.repositories.systemTest $oldTestRevision $proposed
        Assert-HarnessRepairWorktreeClean $state.repositories.systemTest ([string]$state.changeName)
        $repairDiff = Get-GitDiffInfo $state.repositories.systemTest $oldTestRevision $proposed
        $allowedPaths = @(
            "changes/$($state.changeName)/test-cases.generated.json",
            "changes/$($state.changeName)/test-plan.md"
        )
        if ($repairDiff.changedFiles.Count -ne $allowedPaths.Count -or (@($repairDiff.changedFiles | Sort-Object) -join "`n") -ne (@($allowedPaths | Sort-Object) -join "`n")) {
            Stop-Controller 'ERROR_SCOPE' 'derived artifact repair must change exactly the generated contract and test-plan generated region'
        }
        if ($report.result -ne 'PASS' -or $report.mode -ne 'implementation' -or $report.baselineRevision -ne $oldTestRevision -or $report.testRevision -ne $proposed -or $report.canonicalRevision -ne $state.revisions.testBaseline) {
            Stop-Controller 'ERROR_RESULT' 'derived artifact repair report must be a bound implementation PASS'
        }
        $state.revisions.test = $proposed
        $state.scopeVerification = [pscustomobject]@{ result='PASS'; kind='derived-artifact-repair'; baselineRevision=$repairDiff.baseline; currentRevision=$repairDiff.current; repository=$state.repositories.systemTest; diffHash=$repairDiff.diffHash; changedFiles=@($repairDiff.changedFiles); at=[DateTime]::UtcNow.ToString('o') }
        $state.verifier = $null
        Add-History $state $state.phase $state.phase 'accepted canonical derived artifact repair'
        Write-State $state
        Write-Output '[FLOW_CONTROLLER] PASS'
        Write-Output "test_revision: $proposed"
        exit 0
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
        if ($RunResult -eq 'pass') {
            $evidenceIndex = if (Test-Path -LiteralPath $EvidencePath -PathType Container) { Join-Path $EvidencePath 'index.md' } else { $EvidencePath }
            if (Test-Path -LiteralPath $evidenceIndex -PathType Leaf) {
                $evidenceText = Get-Content -LiteralPath $evidenceIndex -Raw -Encoding utf8
                if ($evidenceText -match '(?im)(?:"?fullSuite"?\s*:\s*false|execution_mode\s*:\s*standalone)') { Stop-Controller 'ERROR_PARTIAL_RUN' 'standalone or selected-scenario evidence cannot register a full Flow PASS' }
            }
        }
        if ($RunResult -eq 'pass') { Set-Phase $state 'TEST_EXECUTED_PASS' 'runner evidence pass' }
        else {
            $fingerprint = Get-Fingerprint $state
            if ($state.failureFingerprints -contains $fingerprint) { Stop-Controller 'ERROR_FAILURE_DUPLICATE' 'failure fingerprint already exists' }
            $state.failureFingerprints += $fingerprint; Set-Phase $state 'TEST_EXECUTED_FAIL' 'runner evidence fail'
        }
        $state.runs += [pscustomobject]@{ runId=$state.activeRun.runId; testRevision=$state.revisions.test; result=$RunResult; evidence=$EvidencePath; scenarioId=$ScenarioId; failureCategory=$FailureCategory; firstEvidence=$FirstEvidence; at=[DateTime]::UtcNow.ToString('o') }; $state.activeRun = $null; Write-State $state; Write-Output '[FLOW_CONTROLLER] PASS'; exit 0
    }
    'retry-harness-failure' {
        Require-Ceiling $state 'implementation'
        if ($state.phase -ne 'TEST_EXECUTED_FAIL' -or $null -ne $state.activeRun) { Stop-Controller 'ERROR_TRANSITION' 'harness retry requires a completed failed run' }
        if ($state.revisions.sut -ne $SutRevision -or (Get-GitHead $state.repositories.sut) -ne $state.revisions.sut) { Stop-Controller 'ERROR_REVISION_DRIFT' 'SUT revision changed during harness repair' }
        if ($state.configurationFingerprint -ne $ConfigurationFingerprint) { Stop-Controller 'ERROR_CONFIGURATION_DRIFT' 'configuration fingerprint changed during harness repair' }
        if ([string]::IsNullOrWhiteSpace($ProposedTestRevision) -or [string]::IsNullOrWhiteSpace($HarnessRevision)) { Stop-Controller 'ERROR_INPUT' 'new test and harness revisions are required' }
        $failedRun = @($state.runs | Select-Object -Last 1)
        if ($failedRun.Count -ne 1 -or $failedRun[0].result -ne 'fail') { Stop-Controller 'ERROR_TRANSITION' 'last run is not a recorded failure' }
        $runnerReport = Read-StructuredJson $ReportPath 'failed runner report'
        if ($runnerReport.status -ne 'FAIL' -or $runnerReport.classification -ne 'TEST_HARNESS' -or $null -eq $runnerReport.cleanup -or -not [bool]$runnerReport.cleanup.succeeded) {
            Stop-Controller 'ERROR_RESULT' 'only a cleaned TEST_HARNESS failure may be retried'
        }
        $evidenceRoot = if (Test-Path -LiteralPath $failedRun[0].evidence -PathType Leaf) { Split-Path -Parent $failedRun[0].evidence } else { [string]$failedRun[0].evidence }
        if (-not (Test-PathWithin $ReportPath $evidenceRoot)) { Stop-Controller 'ERROR_RESULT' 'failed runner report is outside the recorded evidence root' }
        $oldTestRevision = [string]$state.revisions.test
        $proposed = Resolve-GitRevision $state.repositories.systemTest $ProposedTestRevision
        if ($proposed -eq $oldTestRevision -or $proposed -ne (Get-GitHead $state.repositories.systemTest)) { Stop-Controller 'ERROR_REVISION_DRIFT' 'harness repair must create the canonical system-test HEAD' }
        Assert-GitAncestor $state.repositories.systemTest $oldTestRevision $proposed
        Assert-HarnessRepairWorktreeClean $state.repositories.systemTest ([string]$state.changeName)
        $repairDiff = Get-GitDiffInfo $state.repositories.systemTest $oldTestRevision $proposed
        foreach ($path in @($repairDiff.changedFiles)) {
            if ($path -notlike 'scripts/*' -and $path -notlike 'self-test/*') { Stop-Controller 'ERROR_SCOPE' "harness repair changed a non-harness file: $path" }
        }
        if ($HarnessRevision -eq $state.revisions.harness) { Stop-Controller 'ERROR_HARNESS_UNCERTIFIED' 'harness repair must produce a new certified revision' }
        $certification = Assert-HarnessCertification $HarnessRoot $HarnessCertificationPath $HarnessRevision
        $state.revisions.test = $proposed
        $state.revisions.harness = $HarnessRevision
        $state.harnessCertification = $certification
        $state.scopeVerification = [pscustomobject]@{ result='PASS'; kind='certified-harness-repair'; baselineRevision=$repairDiff.baseline; currentRevision=$repairDiff.current; repository=$state.repositories.systemTest; diffHash=$repairDiff.diffHash; changedFiles=@($repairDiff.changedFiles); at=[DateTime]::UtcNow.ToString('o') }
        $state.verifier = $null
        Set-Phase $state 'TEST_IMPLEMENTED' 'accepted certified harness repair after TEST_HARNESS failure'
        Write-State $state
        Write-Output '[FLOW_CONTROLLER] PASS'
        Write-Output "test_revision: $proposed"
        Write-Output "harness_revision: $HarnessRevision"
        exit 0
    }
    'retry-test-infra-failure' {
        Require-Ceiling $state 'implementation'
        if ($state.phase -ne 'TEST_EXECUTED_FAIL' -or $null -ne $state.activeRun) { Stop-Controller 'ERROR_TRANSITION' 'test infrastructure retry requires a completed failed run' }
        if ($state.revisions.sut -ne $SutRevision -or (Get-GitHead $state.repositories.sut) -ne $state.revisions.sut) { Stop-Controller 'ERROR_REVISION_DRIFT' 'SUT revision changed during test infrastructure repair' }
        if ($state.revisions.harness -ne $HarnessRevision) { Stop-Controller 'ERROR_REVISION_DRIFT' 'harness revision changed during test infrastructure repair' }
        if ($state.configurationFingerprint -ne $ConfigurationFingerprint) { Stop-Controller 'ERROR_CONFIGURATION_DRIFT' 'configuration fingerprint changed during test infrastructure repair' }
        if ([string]::IsNullOrWhiteSpace($ProposedTestRevision)) { Stop-Controller 'ERROR_INPUT' 'new test revision is required' }
        $failedRun = @($state.runs | Select-Object -Last 1)
        if ($failedRun.Count -ne 1 -or $failedRun[0].result -ne 'fail' -or $failedRun[0].failureCategory -notin @('TEST_HARNESS','CONFIG_INFRA')) { Stop-Controller 'ERROR_TRANSITION' 'last run is not a retryable test infrastructure failure' }
        $runnerReport = Read-StructuredJson $ReportPath 'failed runner report'
        if ($runnerReport.status -ne 'FAIL' -or $runnerReport.classification -notin @('TEST_HARNESS','CONFIG_INFRA') -or $null -eq $runnerReport.cleanup -or -not [bool]$runnerReport.cleanup.succeeded) {
            Stop-Controller 'ERROR_RESULT' 'only a cleaned TEST_HARNESS or CONFIG_INFRA failure may use test infrastructure retry'
        }
        $evidenceRoot = if (Test-Path -LiteralPath $failedRun[0].evidence -PathType Leaf) { Split-Path -Parent $failedRun[0].evidence } else { [string]$failedRun[0].evidence }
        if (-not (Test-PathWithin $ReportPath $evidenceRoot)) { Stop-Controller 'ERROR_RESULT' 'failed runner report is outside the recorded evidence root' }
        $oldTestRevision = [string]$state.revisions.test
        $proposed = Resolve-GitRevision $state.repositories.systemTest $ProposedTestRevision
        if ($proposed -eq $oldTestRevision -or $proposed -ne (Get-GitHead $state.repositories.systemTest)) { Stop-Controller 'ERROR_REVISION_DRIFT' 'test infrastructure repair must create the canonical system-test HEAD' }
        Assert-GitAncestor $state.repositories.systemTest $oldTestRevision $proposed
        Assert-HarnessRepairWorktreeClean $state.repositories.systemTest ([string]$state.changeName)
        $repairDiff = Get-GitDiffInfo $state.repositories.systemTest $oldTestRevision $proposed
        foreach ($path in @($repairDiff.changedFiles)) {
            if ($path -notlike "changes/$($state.changeName)/fixtures/*" -and $path -ne "changes/$($state.changeName)/manifest.yaml" -and $path -notlike "config/*/$($state.changeName)/*" -and $path -notlike "infra/*/$($state.changeName)/*") {
                Stop-Controller 'ERROR_SCOPE' "test infrastructure repair changed a non-infrastructure file: $path"
            }
        }
        $state.revisions.test = $proposed
        $state.scopeVerification = [pscustomobject]@{ result='PASS'; kind='test-infrastructure-repair'; baselineRevision=$repairDiff.baseline; currentRevision=$repairDiff.current; repository=$state.repositories.systemTest; diffHash=$repairDiff.diffHash; changedFiles=@($repairDiff.changedFiles); at=[DateTime]::UtcNow.ToString('o') }
        $state.verifier = $null
        Set-Phase $state 'TEST_IMPLEMENTED' 'accepted test infrastructure repair after cleaned startup failure'
        Write-State $state
        Write-Output '[FLOW_CONTROLLER] PASS'
        Write-Output "test_revision: $proposed"
        exit 0
    }
    'block' {
        if (Test-SensitiveContent $Reason) { Stop-Controller 'ERROR_SECRET_INPUT' 'block reason contains sensitive material' }
        Set-Phase $state 'BLOCKED' $(if ($Reason) { $Reason } else { 'blocked by controller' }); Write-State $state; Write-Output '[FLOW_CONTROLLER] PASS'; exit 0
    }
}

} finally { if ($stateLock) { $stateLock.Dispose() } }
