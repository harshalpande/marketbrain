#Requires -Version 7.0
$ErrorActionPreference='Stop'
foreach($n in @('PaytmSupervisorHost.ps1','PaytmGatewayRestart.ps1','PaytmGatewayNetworkResume.ps1')){. (Join-Path $PSScriptRoot $n)}
Set-StrictMode -Version Latest
$realWrite=(Get-Command Write-PaytmHostJson).ScriptBlock
$temp=Join-Path ([IO.Path]::GetTempPath()) ('mb-network-resume-'+[guid]::NewGuid().ToString('N'));$null=New-Item -ItemType Directory -Path $temp
$f=@{};$report=@{};$checks=0
function Check($Ok,$Name){if(-not $Ok){throw "NETWORK_RESUME_TEST_$Name"};$script:checks++}
function Assert-PaytmAccountPath($Path){$Path}
function Assert-PaytmAccountAcl {}
function Set-PaytmAccountDirectoryAcl {}
function Get-Acl {}
function Add-Type {}
function Get-PaytmKeyContract {@{accountSid='fixture'}}
function Get-PaytmHostContract {@{root=$f.root;work=$f.work;name='fixture-task'}}
function Get-PaytmOwnedHostTask($Id,$Enabled=$true){
 if($f.case -eq 'task_drift' -or $f.enabled -ne $Enabled){throw 'HOST_TASK_OWNERSHIP'}
 @{State=$(if($f.case -eq 'running'){'Running'}else{'Ready'})}
}
function Get-Process {if($f.case -eq 'pid_present'){@{Id=18292}}}
function Get-PaytmTransportListeners {if($f.case -eq 'listener'){'occupied'}}
function Assert-PaytmTransportListener($Rows){if($null -ne $Rows -and @($Rows).Count){throw 'TRANSPORT_LISTENER_PRESENT'}}
function Read-PaytmTransportControl($Root,$Id){(Read-PaytmHostJson (Join-Path $Root 'transport-control.json')).mode}
function Set-PaytmHostControl($Id,$Mode){Write-PaytmHostJson (Join-Path $f.root 'control.json') @{version=1;installationId=$Id;mode=$Mode}}
function Get-FileHash($LiteralPath){
 if($LiteralPath -eq $f.review){@{Hash=$(if($f.case -eq 'bad_receipt'){'BAD'}else{'C548C0A71025967778C14BC7573D358FD9FD0A290DB6D1FED3FBA1C9B9053B3B'})}}
 else{Microsoft.PowerShell.Utility\Get-FileHash -LiteralPath $LiteralPath}
}
function Save-Report {
 Write-PaytmHostJson (Join-Path $f.root 'report.json') $report
 if($f.case -eq 'checkpoint_failure' -and $report.networkResumeAttempted){throw 'HOST_CHECKPOINT_FAILED'}
 if($f.case -eq 'new_failure_during_update' -and $report.networkResumeAttempted){Write-PaytmHostJson (Join-Path $f.work 'blocked.json') @{failure='HOST_NEW_FAILURE'}}
}
function Write-PaytmHostJson($Path,$Value){
 if($f.Count -and $f.case -eq 'manifest_failure' -and $report.networkResumeAttempted -and $Path -eq (Join-Path $f.root 'manifest.json')){throw 'HOST_MANIFEST_WRITE_FAILED'}
 & $realWrite $Path $Value
}
function Enable-ScheduledTask {$f.enables++;$f.enabled=$true}
function Start-ScheduledTask {$f.starts++;if($f.case -eq 'start_failure'){throw 'HOST_START_FAILED'}}
function Wait-PaytmManagedHost {
 if($f.case -eq 'worker_failure'){Write-PaytmHostJson (Join-Path $f.work 'blocked.json') @{failure='TRANSPORT_KEY_DENIED'};throw 'HOST_WORKER_BLOCKED'}
 @{instanceId=('b'*32);phase='TRANSPORT_READY'}
}
try{
 $cases=@('pass','bad_receipt','bad_proof','task_drift','enabled','running','pid_present','listener','archive_drift','source_drift','control_changed','lease_held','checkpoint_failure','manifest_failure','new_failure','new_failure_during_update','start_failure','worker_failure','already_changed','worker_changed')
 foreach($case in $cases){
  $base=Join-Path $temp $case;$root=Join-Path $base root;$work=Join-Path $base work;$null=New-Item -ItemType Directory -Path $root,$work
  $f=@{case=$case;root=$root;work=$work;review=(Join-Path $base review.json);starts=0;enables=0;enabled=($case -eq 'enabled')}
  $report=@{runId=[guid]::NewGuid().ToString('N');networkResumeAttempted=$false}
  $id='ea8b91471cf048aa97a0f6b939b355c7';$hashes=@{}
  foreach($n in @('runner.ps1','host.ps1','native.dll','gateway.ps1','transport.ps1','transport.dll')){
   [IO.File]::WriteAllText((Join-Path $root $n),'fixture-'+$n)
   if($n -eq 'runner.ps1'){Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'RunPaytmGatewaySupervisor.ps1') -Destination (Join-Path $root $n) -Force}
   $hashes[$n]=(Get-FileHash -LiteralPath (Join-Path $root $n)).Hash
  }
  $receipt=@{sourceHashes=@{'RunPaytmGatewaySupervisor.ps1'=$hashes['runner.ps1'];'PaytmGatewaySupervisor.ps1'=$hashes['gateway.ps1'];'PaytmSupervisorTransport.ps1'=$hashes['transport.ps1']}}
  $oldHash=$hashes['transport.ps1']
  Write-PaytmHostJson (Join-Path $root 'manifest.json') @{version=1;transportVersion=1;installationId=$id;hashes=$hashes}
  Set-PaytmHostControl $id STOP
  Write-PaytmHostJson (Join-Path $root 'transport-control.json') @{version=1;installationId=$id;mode='ENABLED'}
  $worker=@{installationId=$id;instanceId='659d1c487b7942b0be855dc8df212c45';processId=18292;failure=$null;brokerReady=$false;ordersEnabled=$false}
  Write-PaytmHostJson (Join-Path $work 'status.json') $worker
  $archive=Join-Path $root 'transport-recovery-1c972328b34c4a7e80fb637e05ec8a8c';$null=New-Item -ItemType Directory -Path $archive;$archiveHashes=@{}
  foreach($n in @('transport.ps1','manifest.json','control.json','transport-control.json','startup-failure.json','blocked.json','status.json')){
   if($n -in @('startup-failure.json','blocked.json')){Write-PaytmHostJson (Join-Path $archive $n) @{failure='TRANSPORT_UNKNOWN'}}
   else{Copy-Item -LiteralPath (Join-Path $(if($n -eq 'status.json'){$work}else{$root}) $n) -Destination (Join-Path $archive $n)}
   $archiveHashes[$n]=(Get-FileHash -LiteralPath (Join-Path $archive $n)).Hash
  }
  $review=@{runId='1c972328b34c4a7e80fb637e05ec8a8c';failure='NETWORK_BACKOFF_NOT_OBSERVED';cleanupFailure=$null;networkLossObserved=$false;networkRecoveryPassed=$false;failureStopVerified=$true;accountPreserved=$true;finalApplicationLockVerified=$true;networkCleanupRehearsalPassed=$true;transportRecoveryAttempted=$true;networkGuards=@(@{removed=$true;taskRemoved=$true},@{removed=$true;taskRemoved=$true});transportRecovery=@{newTransportHash=$oldHash;backupVerified=$true;transportUpdated=$true;manifestUpdated=$true;markersArchived=$true;healthy=($case -ne 'bad_proof');startAttempts=1;backupHashes=$archiveHashes;worker=$worker}}
  Write-PaytmHostJson $f.review $review
  if($case -eq 'archive_drift'){[IO.File]::WriteAllText((Join-Path $archive 'blocked.json'),'changed')}
  if($case -eq 'source_drift'){[IO.File]::WriteAllText((Join-Path $root 'gateway.ps1'),'changed')}
  if($case -eq 'control_changed'){Set-PaytmHostControl $id LOCKED}
  if($case -eq 'new_failure'){Write-PaytmHostJson (Join-Path $work 'blocked.json') @{failure='TRANSPORT_KEY_DENIED'}}
  if($case -eq 'worker_changed'){$worker.instanceId='c'*32;Write-PaytmHostJson (Join-Path $work 'status.json') $worker}
  if($case -eq 'already_changed'){Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'PaytmSupervisorTransport.ps1') -Destination (Join-Path $root 'transport.ps1') -Force;$hashes['transport.ps1']=(Get-FileHash -LiteralPath (Join-Path $root 'transport.ps1')).Hash;Write-PaytmHostJson (Join-Path $root 'manifest.json') @{version=1;transportVersion=1;installationId=$id;hashes=$hashes}}
  $held=$null;$failed=$false
  try{
   if($case -eq 'lease_held'){$held=[IO.File]::Open((Join-Path $work 'instance.lock'),'OpenOrCreate','ReadWrite','None')}
   Invoke-PaytmReviewedNetworkResume $receipt $f.review $PSScriptRoot
  }catch{$failed=$true;if($case -eq 'pass'){throw}}finally{if($held){$held.Dispose()}}
  if($case -eq 'pass'){
   Check (-not $failed -and $f.starts -eq 1 -and $f.enables -eq 1 -and $report.networkResume.healthy) 'ONE_START_SUCCESS'
   Check ($report.networkResume.backupVerified -and $report.networkResume.transportUpdated -and $report.networkResume.manifestUpdated -and $report.networkResume.priorArchiveVerified) 'UPDATE_PROOFS'
   Check ((Read-PaytmHostJson (Join-Path $root 'manifest.json')).hashes.'transport.ps1' -ceq (Get-FileHash -LiteralPath (Join-Path $PSScriptRoot 'PaytmSupervisorTransport.ps1')).Hash) 'EXACT_PATCH'
   $again=$false;try{Invoke-PaytmReviewedNetworkResume $receipt $f.review $PSScriptRoot}catch{$again=$true};Check ($again -and $f.starts -eq 1) 'NO_REPEAT_RESET'
  }elseif($case -in @('start_failure','worker_failure')){Check ($failed -and $f.starts -eq 1 -and -not $report.networkResume.healthy) 'FAILED_START_NO_RETRY'}
  else{Check ($failed -and $f.starts -eq 0 -and $f.enables -eq 0) ($case+'_NO_START')}
  foreach($n in @('startup-failure.json','blocked.json','status.json')){if($case -eq 'archive_drift' -and $n -eq 'blocked.json'){continue};Check ((Get-FileHash -LiteralPath (Join-Path $archive $n)).Hash -ceq $archiveHashes[$n]) 'PRIOR_ARCHIVE_UNCHANGED'}
  Check (Test-Path -LiteralPath (Join-Path $work 'status.json')) 'CURRENT_STATUS_RETAINED'
 }
 [pscustomobject]@{status='NETWORK_RESUME_WORKFLOWS_PASSED';assertions=$checks;workflows=$cases.Count;realArchivesAndReplacement=$true;runtimeApisMocked=$true}|ConvertTo-Json
}finally{
 $full=[IO.Path]::GetFullPath($temp);$base=[IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\')+'\'
 if(-not $full.StartsWith($base,[StringComparison]::OrdinalIgnoreCase) -or [IO.Path]::GetFileName($full) -notmatch '^mb-network-resume-[a-f0-9]{32}$'){throw 'UNSAFE_FIXTURE_CLEANUP'}
 Remove-Item -LiteralPath $full -Recurse -Force
}
