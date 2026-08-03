[CmdletBinding()]
param(
  [Parameter(Mandatory=$true)] [string]$ControllerPath,
  [Parameter(Mandatory=$true)] [string]$InputPath,
  [Parameter(Mandatory=$true)] [string]$OutputPath
)

$ErrorActionPreference='Stop'
function Get-Hash([string]$Path){return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()}
function Get-TextHash([string]$Text){$sha=[Security.Cryptography.SHA256]::Create();try{return(-join($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($Text))|ForEach-Object{$_.ToString('x2')}))}finally{$sha.Dispose()}}
function Get-GitHead([string]$Path){$output=@(& git -C $Path rev-parse HEAD 2>&1);$exitCode=$LASTEXITCODE;if($exitCode -ne 0 -or $output.Count -eq 0){return 'unavailable'};return ([string]$output[0]).Trim()}

$parsedInputs=Get-Content -LiteralPath $InputPath -Raw -Encoding UTF8|ConvertFrom-Json
$inputs=@(); foreach($parsedInput in $parsedInputs){$inputs += $parsedInput}
if($inputs.Count -ne 3){throw 'exactly three real shadow observations are required'}
$observations=@()
for($i=0;$i-lt$inputs.Count;$i++){
  $item=$inputs[$i]
  foreach($property in @('taskPath','statePath','sutRepo','actualPreparedAction')){if([string]::IsNullOrWhiteSpace([string]$item.$property)){throw"shadow input missing $property"}}
  if(-not(Test-Path -LiteralPath $item.taskPath -PathType Leaf)){throw 'shadow task source missing'}
  $task=Get-Item -LiteralPath $item.taskPath; $stateExists=Test-Path -LiteralPath $item.statePath -PathType Leaf
  $oldPreference=$ErrorActionPreference;$ErrorActionPreference='Continue'
  try{$raw=@(& powershell.exe -NoProfile -ExecutionPolicy Bypass -File $ControllerPath next -StatePath $item.statePath 2>&1|ForEach-Object{[string]$_});$exitCode=$LASTEXITCODE}finally{$ErrorActionPreference=$oldPreference}
  $rawText=$raw-join"`n"; $errorCode=if($rawText-match '\[FLOW_CONTROLLER\] (ERROR_[A-Z_]+)'){$Matches[1]}else{'NONE'}; $next=if($rawText-match '(?m)^next: ([A-Z_]+)'){$Matches[1]}else{'BLOCKED'}
  $normalized=@($raw|ForEach-Object{$_-replace'(?i)(state file not found:).*','$1 <redacted>'})
  $observations += [ordered]@{
    observationId=('shadow-'+($i+1)); observedAt=[DateTime]::UtcNow.ToString('o'); inputRevision=(Get-Hash $item.taskPath)
    sutRevision=(Get-GitHead $item.sutRepo); sourceLocatorHash=(Get-TextHash ([IO.Path]::GetFullPath($item.taskPath))); sourceModifiedAt=$task.LastWriteTimeUtc.ToString('o')
    initialControllerState=[ordered]@{ exists=$stateExists; stateHash=$(if($stateExists){Get-Hash $item.statePath}else{'missing'}) }
    controller=[ordered]@{ exitCode=$exitCode; next=$next; errorCode=$errorCode; rawOutputHash=(Get-TextHash $rawText); normalizedOutput=$normalized }
    actualPreparedAction=[string]$item.actualPreparedAction; consistent=($next-eq[string]$item.actualPreparedAction); evidenceLocation=('shadow-'+($i+1)+'.json')
  }
}
$directory=Split-Path -Parent $OutputPath;if(-not(Test-Path $directory)){[void](New-Item -ItemType Directory -Path $directory -Force)}
foreach($observation in $observations){[IO.File]::WriteAllText((Join-Path $directory $observation.evidenceLocation),($observation|ConvertTo-Json -Depth 8),[Text.UTF8Encoding]::new($false))}
$report=[ordered]@{schemaVersion=1;result='PASS';observationCount=$observations.Count;generatedAt=[DateTime]::UtcNow.ToString('o');observations=$observations}
[IO.File]::WriteAllText($OutputPath,($report|ConvertTo-Json -Depth 10),[Text.UTF8Encoding]::new($false))
Write-Output '[SHADOW_OBSERVATION] PASS'
