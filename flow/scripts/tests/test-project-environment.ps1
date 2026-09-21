$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot '../../templates/system-test/scripts/project-test-environment.ps1')
$temp = Join-Path ([IO.Path]::GetTempPath()) ('flow-project-env-' + [guid]::NewGuid().ToString('N'))
[void](New-Item -ItemType Directory -Path $temp)
try {
    $policyPath = Join-Path $temp 'policy.json'
    @{schemaVersion=1; configurationRepository=$temp; middleware=@(@{kind='redis';container='approved-redis';hostPort=6379;containerPort='6379/tcp'})} | ConvertTo-Json -Depth 8 | Set-Content $policyPath
    $resolved = [pscustomobject]@{configuration=@{provider=@{repository=(Join-Path $temp 'build-copy');configurationRepository=$temp}};resources=@([pscustomobject]@{id='cache';kind='redis';lifecycle='external';preflightProbe='cache'});probes=@([pscustomobject]@{id='cache';kind='tcp';host='127.0.0.1';port=6379})}
    $script:calls = [Collections.Generic.List[string]]::new(); $script:running=$true
    $docker = { param($Arguments)
        $script:calls.Add(($Arguments -join ' '))
        if ($Arguments[0] -eq 'start') {$script:running=$true;return 'approved-redis'}
        return (@(@{Name='/approved-redis';Id='test-id';State=@{Running=$script:running};HostConfig=@{PortBindings=@{'6379/tcp'=@(@{HostPort='6379'})}}}) | ConvertTo-Json -Depth 8 -Compress)
    }
    1..2 | ForEach-Object {
        $r = Invoke-ProjectEnvironmentPrepare $resolved $policyPath -Ensure -Docker $docker
        if ($r.result -ne 'INPUTS_ACCEPTED') {throw ($r | ConvertTo-Json -Depth 10)}
    }
    if (@($script:calls | Where-Object {$_ -notlike 'inspect *'}).Count) {throw 'Healthy repeat must be read-only'}
    $script:running=$false
    $r = Invoke-ProjectEnvironmentPrepare $resolved $policyPath -Docker $docker
    if ($r.result -ne 'PREPARATION_REQUIRED' -or $script:running) {throw 'Status must not start'}
    $r = Invoke-ProjectEnvironmentPrepare $resolved $policyPath -Ensure -Docker $docker
    if ($r.result -ne 'INPUTS_ACCEPTED' -or -not $script:running) {throw 'Ensure must start existing instance'}
    $resolved.probes[0].port=19092
    $before=$script:calls.Count
    $r=Invoke-ProjectEnvironmentPrepare $resolved $policyPath -Ensure -Docker $docker
    if ($r.result -ne 'ACTION_REQUIRED' -or $script:calls.Count -ne $before) {throw 'Wrong endpoint must not start/substitute'}
    $resolved.probes[0].port=6379; $resolved.resources[0].lifecycle='managed'
    $r=Invoke-ProjectEnvironmentPrepare $resolved $policyPath -Ensure -Docker $docker
    if ($r.result -ne 'ACTION_REQUIRED') {throw 'Managed replacement must fail'}
    $resolved.resources=@()
    $r=Invoke-ProjectEnvironmentPrepare $resolved $policyPath -Ensure -Docker $docker
    if ($r.result -ne 'INPUTS_ACCEPTED' -or $script:calls.Count -ne $before) {throw 'Unselected middleware must not be checked'}
    Write-Output 'PASS: reuse, repeat, status, start-existing, wrong endpoint, managed replacement, optional selection'
} finally { Remove-Item -LiteralPath $temp -Recurse -Force }
