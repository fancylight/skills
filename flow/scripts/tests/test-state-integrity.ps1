$ErrorActionPreference='Stop'
$contract=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../templates/system-test/scripts/test-runtime-contract.ps1'))
. $contract
function Hash-Text([string]$Text) {
    $sha=[Security.Cryptography.SHA256]::Create()
    try{return -join($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($Text))|ForEach-Object{$_.ToString('x2')})}finally{$sha.Dispose()}
}
$data=[ordered]@{message='OUT->IN and literal \u003e';seconds=43.605;nested=@{integrityHash='keep-nested';value=123};integrityHash=''}
foreach($mode in @('Default','EscapeHtml')) {
    $data.integrityHash=''
    $data.integrityHash=Hash-Text ($data|ConvertTo-Json -Depth 8 -Compress -EscapeHandling $mode)
    $raw=$data|ConvertTo-Json -Depth 8 -EscapeHandling $mode
    if((Get-TestStateIntegrityHashFromRaw $raw) -ne $data.integrityHash){throw "Valid $mode writer rejected"}
    if((Get-TestStateIntegrityHashFromRaw ($raw.Replace('123','124'))) -eq $data.integrityHash){throw 'Changed payload accepted'}
    if((Get-TestStateIntegrityHashFromRaw ($raw.Replace('keep-nested','changed'))) -eq $data.integrityHash){throw 'Nested signature was incorrectly excluded'}
}
$temp=Join-Path ([IO.Path]::GetTempPath()) ('flow-integrity-'+[guid]::NewGuid().ToString('N'))
[void](New-Item -ItemType Directory $temp)
try {
    $data.integrityHash=''
    $data.integrityHash=Hash-Text ($data|ConvertTo-Json -Depth 8 -Compress)
    [IO.File]::WriteAllText((Join-Path $temp 'state.json'),($data|ConvertTo-Json -Depth 8),[Text.UTF8Encoding]::new($false))
    $child=@'
param($Contract,$InputPath)
$ErrorActionPreference='Stop'
. $Contract
$raw=Get-Content -LiteralPath $InputPath -Raw -Encoding utf8
$value=$raw|ConvertFrom-Json
if((Get-TestStateIntegrityHashFromRaw $raw) -ne $value.integrityHash){throw 'Cross-version signature mismatch'}
Write-Output 'PS5_SIGNATURE_PASS'
'@
    [IO.File]::WriteAllText((Join-Path $temp 'check.ps1'),$child,[Text.UTF8Encoding]::new($true))
    $result=@(& powershell.exe -NoProfile -File (Join-Path $temp 'check.ps1') -Contract $contract -InputPath (Join-Path $temp 'state.json'))
    if($LASTEXITCODE -ne 0 -or $result -notcontains 'PS5_SIGNATURE_PASS'){throw 'PowerShell 5 compatibility failed'}
} finally {
    if([IO.Path]::GetFullPath($temp).StartsWith([IO.Path]::GetFullPath([IO.Path]::GetTempPath()),[StringComparison]::OrdinalIgnoreCase)){Remove-Item -LiteralPath $temp -Recurse -Force}
}
Write-Output '[STATE_INTEGRITY_TEST] PASS'
