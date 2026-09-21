$ErrorActionPreference='Stop'
$root=Join-Path ([IO.Path]::GetTempPath()) ('flow-inputs-'+[guid]::NewGuid().ToString('N'))
[void][IO.Directory]::CreateDirectory($root)
function Stop-Controller($code,$message){throw "$code $message"}
function Get-GitOutput($repo,$args){return $script:changes}
function Get-FileHashValue($path){(Get-FileHash $path).Hash.ToLowerInvariant()}
. (Join-Path $PSScriptRoot '../controller-execution.ps1')
try {
    $file=Join-Path $root 'notes.txt'; Set-Content $file 'unrelated notes'
    $evidence=Join-Path $root 'review.md'; Set-Content $evidence 'Build uses src and pom only; notes are not read.'
    $script:changes=@('?? notes.txt')
    $rejected=$false; try{Assert-ExecutionSutClean $root}catch{$rejected=$true}
    if(-not $rejected){throw 'unknown input was silently ignored'}
    $review=@{repository=$root;path='notes.txt';sha256=(Get-FileHashValue $file);reason='not a build input';evidencePath=$evidence}
    Assert-ExecutionSutClean $root @($review)
    if(-not(Test-Path $file)){throw 'unrelated file was removed'}
    Set-Content $file 'changed content'
    $rejected=$false; try{Assert-ExecutionSutClean $root @($review)}catch{$rejected=$true}
    if(-not $rejected){throw 'stale exclusion was accepted'}
    $script:changes=@(' M src/Business.java')
    $rejected=$false; try{Assert-ExecutionSutClean $root @($review)}catch{$rejected=$true}
    if(-not $rejected){throw 'source change escaped review'}
    '[BUILD_INPUT_REVIEW] PASS'
} finally {
    if(([IO.Path]::GetFullPath($root)).StartsWith([IO.Path]::GetFullPath([IO.Path]::GetTempPath()))){Remove-Item -LiteralPath $root -Recurse -Force}
}
