$ErrorActionPreference='Stop'
$repo=Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$tempRoot=[IO.Path]::GetFullPath((Join-Path ([IO.Path]::GetTempPath()) ('flow-sites-install-'+[guid]::NewGuid().ToString('N'))))
$oldProfile=$env:USERPROFILE
try {
    $env:USERPROFILE=$tempRoot
    $personal=Join-Path $tempRoot '.flow/worksites'
    [void](New-Item -ItemType Directory -Path $personal -Force)
    $marker=Join-Path $personal 'README.md'
    [IO.File]::WriteAllText($marker,'private site registry; preserve across upgrade',[Text.UTF8Encoding]::new($false))
    $expected=(Get-FileHash $marker).Hash
    $target=Join-Path $tempRoot '.agents/skills'
    & (Join-Path $repo 'codex/install.ps1') -TargetDir $target | Out-Null
    $installed=Join-Path $target 'flow-codex-sites'
    $hashes=@{}
    Get-ChildItem $installed -Recurse -File | ForEach-Object {$hashes[$_.FullName]=(Get-FileHash $_.FullName).Hash}
    if($hashes.Count -lt 5){throw 'Incomplete site skill installation'}
    $operation=Join-Path $personal 'new-operation.md'
    [IO.File]::WriteAllText($operation,'local operation added after install',[Text.UTF8Encoding]::new($false))
    & (Join-Path $repo 'codex/install.ps1') -TargetDir $target | Out-Null
    foreach($path in $hashes.Keys){if((Get-FileHash $path).Hash -ne $hashes[$path]){throw 'Repeat install changed skill resource'}}
    if((Get-FileHash $marker).Hash -ne $expected -or -not(Test-Path $operation)){throw 'Installer changed personal site data'}
    if(-not ([IO.Path]::GetFullPath($installed)).StartsWith($tempRoot+[IO.Path]::DirectorySeparatorChar)){throw 'Unsafe test cleanup'}
    Remove-Item -LiteralPath $installed -Recurse -Force
    if((Get-FileHash $marker).Hash -ne $expected -or -not(Test-Path $operation)){throw 'Rollback changed personal site data'}
    Write-Output 'PASS: installation, resource identity, personal data preservation, extension without reinstall, rollback boundary'
} finally {
    $env:USERPROFILE=$oldProfile
    if($tempRoot.StartsWith([IO.Path]::GetFullPath([IO.Path]::GetTempPath())) -and (Split-Path $tempRoot -Leaf) -like 'flow-sites-install-*') {Remove-Item -LiteralPath $tempRoot -Recurse -Force -ErrorAction SilentlyContinue}
}
