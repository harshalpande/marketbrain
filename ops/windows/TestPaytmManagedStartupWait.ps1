#Requires -Version 7.0
$ErrorActionPreference='Stop'
foreach($n in @('PaytmSupervisorHost.ps1','PaytmManagedTransport.ps1')){. (Join-Path $PSScriptRoot $n)}
Set-StrictMode -Version Latest
$read=(Get-Command Read-PaytmHostJson).ScriptBlock
$temp=Join-Path ([IO.Path]::GetTempPath()) ('mb-startup-wait-'+[guid]::NewGuid().ToString('N'));$null=New-Item -ItemType Directory -Path $temp
$fixture=@{};$checks=0;$id='a'*32
function Check($Ok,$Name){if(-not $Ok){throw "STARTUP_WAIT_TEST_$Name"};$script:checks++}
function Get-PaytmHostContract {@{work=$fixture.path;name='fixture'}}
function Get-PaytmOwnedHostTask {param($Id,$Enabled=$true);@{State=if($fixture.case -eq 'task_exit' -or ($fixture.case -eq 'dispatch' -and $fixture.sleeps -eq 0) -or $fixture.case -eq 'never_dispatched'){'Ready'}else{'Running'}}}
function Get-ScheduledTaskInfo {@{LastTaskResult=1}}
function Get-PaytmTransportListeners {return 'owned'}
function Assert-PaytmTransportListener {param($Rows,$Owner=0);if($fixture.case -eq 'listener'){throw 'TRANSPORT_LISTENER_CONFLICT'}}
function Write-Progress {}
function Read-PaytmHostJson($Path){
 if($fixture.case -eq 'denied'){throw [UnauthorizedAccessException]::new('fixture')}
 if($fixture.case -eq 'disappeared' -and $fixture.reads -eq 0){$fixture.reads++;Remove-Item -LiteralPath $Path}
 & $read $Path
}
function Write-Worker($Instance=('b'*32),$Phase='TRANSPORT_READY'){
 Write-PaytmHostJson (Join-Path $fixture.path 'status.json') @{version=1;transportVersion=1;installationId=$id;phase=$Phase;instanceId=$Instance;sequence=($fixture.sleeps+1);processId=123;sessionId=0;elapsedSeconds=($fixture.sleeps+1);failure=$null;identityVerified=$true;jobContained=$true;agentIdentityVerified=$true;signingVerified=$true;privateCopyAbsent=$true;networkContacted=$true;transportEnabled=$true;brokerReady=$false;ordersEnabled=$false;denialsVerified=$true;childProcessId=124;childStartTicks=1234;httpStatus=503;transportState=@{phase=$Phase}}
}
function Start-Sleep {
 param($Milliseconds)
 $fixture.sleeps++
 if($fixture.case -in @('delayed','dispatch','disappeared','listener')){Write-Worker -Phase $(if($fixture.sleeps -eq 1){'CONNECTING'}else{'TRANSPORT_READY'})}
 elseif($fixture.case -eq 'stale'){Write-Worker ('c'*32)}
 elseif($fixture.case -eq 'frozen'){}
 else{Microsoft.PowerShell.Utility\Start-Sleep -Milliseconds 50}
 if($fixture.case -eq 'frozen' -or $fixture.case -eq 'stale'){Microsoft.PowerShell.Utility\Start-Sleep -Milliseconds 50}
}
try{
 $cases=@('delayed','dispatch','never_dispatched','disappeared','never','denied','malformed','null','task_exit','marker','stale','frozen','listener')
 foreach($case in $cases){
  $p=Join-Path $temp $case;$null=New-Item -ItemType Directory -Path $p
  $fixture=@{case=$case;path=$p;sleeps=0;reads=0}
  if($case -in @('disappeared','frozen')){Write-Worker}
  if($case -eq 'stale'){Write-Worker ('c'*32)}
  if($case -in @('malformed','null')){[IO.File]::WriteAllText((Join-Path $p 'status.json'),$(if($case -eq 'malformed'){'{'}else{'null'}))}
  if($case -eq 'marker'){Write-PaytmHostJson (Join-Path $p 'startup-failure.json') @{failure='HOST_SIGNING_FAILED'}}
  $errorCode=$null;$value=$null
  try{$value=Wait-PaytmManagedHost $id TRANSPORT_READY ('c'*32) -TimeoutSeconds 1 -AwaitScheduledStart:($case -in @('dispatch','never_dispatched'))}catch{$errorCode=$_.Exception.Message}
  if($case -in @('delayed','dispatch','disappeared')){
   Check ($null -eq $errorCode -and $value.phase -eq 'TRANSPORT_READY' -and $fixture.sleeps -ge 3) ($case+'_ADVANCING_HEALTH')
  }else{
   Check ($null -ne $errorCode) ($case+'_REJECTED')
   if($case -in @('never','never_dispatched','stale','frozen')){Check ($errorCode -eq 'TRANSPORT_HEARTBEAT_TIMEOUT') ($case+'_BOUNDED_TIMEOUT')}
   if($case -eq 'marker'){Check ($fixture.sleeps -eq 0 -and $errorCode -eq 'TRANSPORT_WORKER_BLOCKED') 'EARLY_FAILURE_NOT_RETRIED'}
   if($case -eq 'task_exit'){Check ($fixture.sleeps -eq 0 -and $errorCode -eq 'TRANSPORT_TASK_EXIT') 'EXIT_BEFORE_HEARTBEAT'}
  }
 }
 # Failure cleanup accepts both enabled and already-disabled exact tasks.
 function Set-PaytmHostControl {$fixture.stopSet=$true}
 function Get-PaytmProbeTask {@{Settings=@{Enabled=$fixture.enabled}}}
 function Get-PaytmOwnedHostTask {param($Id,$Enabled=$true);if($Enabled -ne $fixture.enabled){throw 'HOST_TASK_SETTINGS'};@{State='Ready'}}
 function Disable-ScheduledTask {$fixture.enabled=$false;$fixture.disables++}
 function Stop-ScheduledTask {$fixture.stops++}
 foreach($enabled in @($true,$false)){
  $fixture=@{case='cleanup';path=$temp;enabled=$enabled;disables=0;stops=0;stopSet=$false}
  Stop-PaytmFailedManagedHost $id
  Check ($fixture.stopSet -and -not $fixture.enabled -and $fixture.stops -eq 1 -and $fixture.disables -eq [int]$enabled) 'EXACT_TASK_CLEANUP'
 }
 [pscustomobject]@{status='MANAGED_STARTUP_WAIT_PASSED';assertions=$checks;waitScenarios=$cases.Count;realFileReads=$true;runtimeApisMocked=$true}|ConvertTo-Json
}finally{
 $full=[IO.Path]::GetFullPath($temp);$base=[IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\')+'\'
 if(-not $full.StartsWith($base,[StringComparison]::OrdinalIgnoreCase) -or [IO.Path]::GetFileName($full) -notmatch '^mb-startup-wait-[a-f0-9]{32}$'){throw 'UNSAFE_FIXTURE_CLEANUP'}
 Remove-Item -LiteralPath $full -Recurse -Force
}
