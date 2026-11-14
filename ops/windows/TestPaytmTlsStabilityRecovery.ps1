#Requires -Version 7.0
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'PaytmSupervisorHost.ps1')
. (Join-Path $PSScriptRoot 'PaytmTlsStabilityRecovery.ps1')
$idleBody=${function:Assert-PaytmIncidentIdle}
$tmp=Join-Path ([IO.Path]::GetTempPath()) ('mb-incident-recovery-'+[guid]::NewGuid().ToString('N'))
$checks=0
function Check($ok,$name){if(-not $ok){throw $name};$script:checks++}
function Assert-PaytmAccountPath($p){$p}
function Get-PaytmHostContract {@{root=$root;work=$work;name='fixture'}}
function Get-PaytmKeyContract {@{accountSid='fixture'}}
function Assert-PaytmNativeReceipt {}
function Assert-PaytmTransportInstallationSources {Read-PaytmHostJson (Join-Path $root 'manifest.json')}
function Test-PaytmTlsPhaseHash {$case -ne 'wrongCode'}
function Test-PaytmAgentProbeSourceHash {$case -ne 'wrongCode'}
function Add-Type {param($Path)}
function Set-PaytmAccountDirectoryAcl {}
function Assert-PaytmIncidentIdle {if($case -eq 'drift'){throw 'HOST_INCIDENT_STATUS_CHANGED'}}
function Save-NativeRecoveryReport {
 if($case -eq 'archiveDrift' -and $report.nativeRecovery.backupVerified -and -not $report.nativeRecoveryAttempted){[IO.File]::WriteAllText((Join-Path $work 'status.json'),'changed')}
}
function Set-PaytmHostControl($id,$mode){$script:mode=$mode}
function Enable-ScheduledTask {param($TaskName,$TaskPath,$ErrorAction) $script:enables++}
function Assert-PaytmInstalledTransport {}
function Start-ScheduledTask {param($TaskName,$TaskPath,$ErrorAction) $script:starts++;if($case -eq 'startFail'){throw 'START_FAILED'}}
function Wait-PaytmManagedHost {param($Id,$Phase,$PreviousInstance,[switch]$AwaitScheduledStart)
 Check ($PreviousInstance -ceq 'c338666a731548d79efb93642071222d' -and $AwaitScheduledStart) 'NEW_WORKER_REQUIRED'
 if($case -eq 'healthFail'){throw 'TRANSPORT_HEARTBEAT_TIMEOUT'}
 @{instanceId='new'}
}
try{
 foreach($case in @('pass','drift','wrongCode','archiveDrift','startFail','healthFail')){
  $root=Join-Path $tmp $case;$work=Join-Path $root work
  $null=New-Item -ItemType Directory -Path $work -Force
  $code=@('native.dll','host.ps1','runner.ps1','transport.ps1','transport.dll','gateway.ps1')
  foreach($n in ($code+@('control.json','transport-control.json'))){[IO.File]::WriteAllText((Join-Path $root $n),'old-'+$n)}
  [IO.File]::WriteAllText((Join-Path $work 'status.json'),'old-status')
  $hashes=@{};foreach($n in $code){$hashes[$n]=(Get-FileHash (Join-Path $root $n)).Hash}
  Write-PaytmHostJson (Join-Path $root 'manifest.json') @{installationId='fixture';hashes=$hashes}
  $manifestHash=(Get-FileHash (Join-Path $root 'manifest.json')).Hash
  $report=[ordered]@{runId=[guid]::NewGuid().ToString('N');nativeRecoveryAttempted=$false};$starts=0;$enables=0;$mode=$null
  $failed=$false;try{Invoke-PaytmNativeRecovery @{} 'fixture' $PSScriptRoot}catch{$failed=$true}
  Check ($failed -eq ($case -ne 'pass')) ($case+'_OUTCOME')
  foreach($n in $code){Check ((Get-FileHash (Join-Path $root $n)).Hash -ceq $hashes[$n]) 'INSTALLED_CODE_UNCHANGED'}
  Check ((Get-FileHash (Join-Path $root 'manifest.json')).Hash -ceq $manifestHash) 'MANIFEST_UNCHANGED'
  if($case -in @('drift','wrongCode','archiveDrift')){
   Check ($starts -eq 0 -and $enables -eq 0 -and -not $report.nativeRecoveryAttempted -and (Test-Path (Join-Path $work 'status.json'))) 'PREFLIGHT_NO_START'
  }else{
   Check ($starts -eq 1 -and $enables -eq 1 -and $mode -eq 'LOCKED') 'SINGLE_START'
   foreach($n in $report.nativeRecovery.backupHashes.Keys){Check ((Get-FileHash (Join-Path $report.nativeRecovery.backupPath $n)).Hash -ceq $report.nativeRecovery.backupHashes[$n]) 'VERIFIED_ARCHIVE'}
   Check (-not(Test-Path (Join-Path $work 'status.json'))) 'ARCHIVED_OLD_STATUS'
  }
 }
 # Real idle gate: accept only this stopped installation; reject changed evidence.
 function Get-PaytmOwnedHostTask {@{State=$taskState}}
 function Get-ScheduledTaskInfo {param($TaskName,$TaskPath) @{LastTaskResult=$taskResult}}
 function Get-Process {param($ErrorAction) @()}
 function Assert-PaytmHostControl {}
 function Read-PaytmTransportControl {'ENABLED'}
 function Assert-PaytmTransportListener {}
 function Get-PaytmTransportListeners {@()}
 $v=@{installationId='fixture';instanceId='c338666a731548d79efb93642071222d';processId=2924;phase='BACKOFF';failure=$null;brokerReady=$false;ordersEnabled=$false}
 foreach($gate in @('pass','gracefulStop','running','result','control','newInstance','blocked','checkpoint')){
  $taskState='Disabled';$taskResult=267014;$v.instanceId='c338666a731548d79efb93642071222d'
  Write-PaytmHostJson (Join-Path $root 'control.json') @{mode=$(if($gate -eq 'control'){'LOCKED'}else{'STOP'})}
  if($gate -eq 'gracefulStop'){$taskResult=0}
  if($gate -eq 'running'){$taskState='Running'}
  if($gate -eq 'result'){$taskResult=1}
  if($gate -eq 'newInstance'){$v.instanceId='different'}
  if($gate -eq 'blocked'){Write-PaytmHostJson (Join-Path $work 'blocked.json') @{}}
  if($gate -eq 'checkpoint'){Write-PaytmHostJson (Join-Path $root 'session-checkpoint.json') @{}}
  Write-PaytmHostJson (Join-Path $work 'status.json') $v
  $failed=$false;try{& $idleBody fixture}catch{$failed=$true}
  Check ($failed -eq ($gate -notin @('pass','gracefulStop'))) ($gate+'_IDLE_GATE')
  foreach($p in @((Join-Path $work 'blocked.json'),(Join-Path $root 'session-checkpoint.json'))){if(Test-Path -LiteralPath $p){Remove-Item -LiteralPath $p}}
 }
 Write-Host "PASS: $checks TLS stability recovery assertions; real archives and hashes; task and runtime APIs mocked."
}finally{
 $full=[IO.Path]::GetFullPath($tmp);$parent=[IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\')+'\'
 if(-not $full.StartsWith($parent,[StringComparison]::OrdinalIgnoreCase) -or [IO.Path]::GetFileName($full) -notmatch '^mb-incident-recovery-[a-f0-9]{32}$'){throw 'UNSAFE_FIXTURE_CLEANUP'}
 if(Test-Path -LiteralPath $full){Remove-Item -LiteralPath $full -Recurse -Force}
}
