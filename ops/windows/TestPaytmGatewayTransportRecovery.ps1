#Requires -Version 7.0
$ErrorActionPreference='Stop'
foreach($n in @('PaytmSupervisorHost.ps1','PaytmGatewayRestart.ps1','PaytmGatewayFailureEvidence.ps1','PaytmGatewayLatchRecovery.ps1','PaytmGatewayTransportRecovery.ps1')){. (Join-Path $PSScriptRoot $n)}
Set-StrictMode -Version Latest
$realWrite=(Get-Command Write-PaytmHostJson).ScriptBlock
$temp=Join-Path ([IO.Path]::GetTempPath()) ('mb-transport-recovery-'+[guid]::NewGuid().ToString('N'));$null=New-Item -ItemType Directory -Path $temp
$f=@{};$report=@{};$checks=0
function Check($Ok,$Name){if(-not $Ok){throw "RECOVERY_TEST_$Name"};$script:checks++}
function Assert-PaytmAccountPath($Path){$Path}
function Assert-PaytmAccountAcl {}
function Set-PaytmAccountDirectoryAcl {}
function Get-Acl {}
function Add-Type {}
function Get-PaytmKeyContract {@{accountSid='fixture'}}
function Get-PaytmHostContract {@{root=$f.root;work=$f.work;name='fixture-task'}}
function Get-PaytmOwnedHostTask {if($f.case -eq 'task_drift'){throw 'HOST_TASK_OWNERSHIP'};@{State=$(if($f.case -eq 'running'){'Running'}else{'Ready'})}}
function Get-ScheduledTaskInfo {@{LastTaskResult=$(if($f.case -eq 'task_result'){0}else{1})}}
function Get-Process {if($f.case -eq 'pid_present'){@{Id=11056}}}
function Get-PaytmTransportListeners {if($f.case -eq 'listener'){'occupied'}}
function Assert-PaytmTransportListener($Rows){if($null -ne $Rows -and @($Rows).Count){throw 'TRANSPORT_LISTENER_PRESENT'}}
function Read-PaytmTransportControl($Root,$Id){(Read-PaytmHostJson (Join-Path $Root 'transport-control.json')).mode}
function Set-PaytmHostControl($Id,$Mode){Write-PaytmHostJson (Join-Path $f.root 'control.json') @{version=1;installationId=$Id;mode=$Mode}}
function Get-FileHash($LiteralPath){
 if($LiteralPath -eq $f.review){@{Hash=$(if($f.case -eq 'bad_receipt'){'BAD'}else{'E2C70C7DDCDB5B3E0EA3E742DE094FC568D1728D2CF6D51A5C8876B7D19A128E'})}}
 else{Microsoft.PowerShell.Utility\Get-FileHash -LiteralPath $LiteralPath}
}
function Save-Report {
 Write-PaytmHostJson (Join-Path $f.root 'report.json') $report
 if($f.case -eq 'checkpoint_failure' -and $report.transportRecoveryAttempted){throw 'HOST_CHECKPOINT_FAILED'}
 if($f.case -eq 'marker_drift' -and $report.transportRecoveryAttempted){Write-PaytmHostJson (Join-Path $f.work 'blocked.json') @{failure='HOST_NEW_FAILURE'}}
}
function Write-PaytmHostJson($Path,$Value){
 if($f.Count -and $f.case -eq 'manifest_failure' -and $report.transportRecoveryAttempted -and $Path -eq (Join-Path $f.root 'manifest.json')){throw 'HOST_MANIFEST_WRITE_FAILED'}
 & $realWrite $Path $Value
}
function Start-ScheduledTask {$f.starts++;if($f.case -eq 'start_failure'){throw 'HOST_START_FAILED'}}
function Wait-PaytmManagedHost {
 if($f.case -eq 'worker_failure'){Write-PaytmHostJson (Join-Path $f.work 'blocked.json') @{failure='TRANSPORT_KEY_DENIED'};throw 'HOST_WORKER_BLOCKED'}
 @{instanceId=('b'*32);phase='TRANSPORT_READY'}
}
try{
 $cases=@('pass','bad_receipt','task_drift','running','task_result','pid_present','listener','changed_marker','source_drift','control_stop','lease_held','checkpoint_failure','manifest_failure','marker_drift','start_failure','worker_failure','already_changed')
 foreach($case in $cases){
  $base=Join-Path $temp $case;$root=Join-Path $base root;$work=Join-Path $base work
  $null=New-Item -ItemType Directory -Path $root,$work
  $f=@{case=$case;root=$root;work=$work;review=(Join-Path $base review.json);starts=0}
  $report=@{runId=[guid]::NewGuid().ToString('N');transportRecoveryAttempted=$false}
  $id='ea8b91471cf048aa97a0f6b939b355c7';$hashes=@{}
  foreach($n in @('runner.ps1','host.ps1','native.dll','gateway.ps1','transport.ps1','transport.dll')){
   [IO.File]::WriteAllText((Join-Path $root $n),'fixture-'+$n)
   if($n -eq 'runner.ps1'){Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'RunPaytmGatewaySupervisor.ps1') -Destination (Join-Path $root $n) -Force}
   $hashes[$n]=(Get-FileHash -LiteralPath (Join-Path $root $n)).Hash
  }
  $receipt=@{sourceHashes=@{'RunPaytmGatewaySupervisor.ps1'=$hashes['runner.ps1'];'PaytmGatewaySupervisor.ps1'=$hashes['gateway.ps1'];'PaytmSupervisorTransport.ps1'=$hashes['transport.ps1']}}
  $oldTransport=$hashes['transport.ps1']
  if($case -eq 'already_changed'){Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'PaytmSupervisorTransport.ps1') -Destination (Join-Path $root 'transport.ps1') -Force;$hashes['transport.ps1']=(Get-FileHash -LiteralPath (Join-Path $root 'transport.ps1')).Hash}
  Write-PaytmHostJson (Join-Path $root 'manifest.json') @{version=1;transportVersion=1;installationId=$id;hashes=$hashes}
  Set-PaytmHostControl $id $(if($case -eq 'control_stop'){'STOP'}else{'LOCKED'})
  Write-PaytmHostJson (Join-Path $root 'transport-control.json') @{version=1;installationId=$id;mode='ENABLED'}
  $files=@{}
  foreach($n in @('startup-failure.json','blocked.json','status.json')){
   Write-PaytmHostJson (Join-Path $work $n) @{failure='TRANSPORT_UNKNOWN';instanceId='f9d773e4554a4d9fbd26d0dc62c52e2a';processId=11056;phase='BLOCKED';brokerReady=$false;ordersEnabled=$false}
   $files[$n]=Get-PaytmWorkerEvidenceFile (Join-Path $work $n)
  }
  Write-PaytmHostJson $f.review @{runId='b49f51c3f0db4ad996892fcdcd6b14b7';failure='STARTUP_WORKER_FAILURE_PRESENT';cleanupFailure=$null;networkInterruptionAttempted=$false;cleanupTasksRegistered=0;sourceHashes=@{'PaytmSupervisorTransport.ps1'=$oldTransport};workerDiagnostics=@{files=$files;task=@{lastResult=1;definitionVerified=$true};process=@{exists=$false}}}
  if($case -eq 'changed_marker'){Write-PaytmHostJson (Join-Path $work 'blocked.json') @{failure='HOST_NEW_FAILURE'}}
  if($case -eq 'source_drift'){[IO.File]::WriteAllText((Join-Path $root 'gateway.ps1'),'changed')}
  $held=$null;$failed=$false
  try{
   if($case -eq 'lease_held'){$held=[IO.File]::Open((Join-Path $work 'instance.lock'),'OpenOrCreate','ReadWrite','None')}
   Invoke-PaytmReviewedTransportRecovery $receipt $f.review $PSScriptRoot
  }catch{$failed=$true;if($case -eq 'pass'){throw}}finally{if($held){$held.Dispose()}}
  if($case -eq 'pass'){
   Check (-not $failed -and $f.starts -eq 1 -and $report.transportRecovery.healthy) 'ONE_START_SUCCESS'
   Check ($report.transportRecovery.backupVerified -and $report.transportRecovery.transportUpdated -and $report.transportRecovery.manifestUpdated -and $report.transportRecovery.markersArchived) 'ALL_RECOVERY_PROOFS'
   foreach($n in @('startup-failure.json','blocked.json','status.json')){Check ((Test-Path -LiteralPath (Join-Path $report.transportRecovery.backupPath $n)) -and -not (Test-Path -LiteralPath (Join-Path $work $n))) 'ARCHIVED_BEFORE_REMOVAL'}
   Check ((Read-PaytmHostJson (Join-Path $root 'manifest.json')).hashes.'transport.ps1' -ceq (Get-FileHash -LiteralPath (Join-Path $PSScriptRoot 'PaytmSupervisorTransport.ps1')).Hash) 'EXACT_TRANSPORT_PATCH'
   Check ((Get-FileHash -LiteralPath (Join-Path $root 'runner.ps1')).Hash -ceq $hashes['runner.ps1']) 'RUNNER_UNCHANGED'
   $again=$false;try{Invoke-PaytmReviewedTransportRecovery $receipt $f.review $PSScriptRoot}catch{$again=$true}
   Check ($again -and $f.starts -eq 1) 'NO_REPEAT_RESET'
  }elseif($case -in @('start_failure','worker_failure')){
   Check ($failed -and $f.starts -eq 1 -and -not $report.transportRecovery.healthy) 'FAILED_START_NO_RETRY'
   Check (Test-Path -LiteralPath (Join-Path $report.transportRecovery.backupPath 'blocked.json')) 'OLD_EVIDENCE_RETAINED'
   if($case -eq 'worker_failure'){Check ((Read-PaytmHostJson (Join-Path $work 'blocked.json')).failure -eq 'TRANSPORT_KEY_DENIED') 'NEW_CAUSE_RETAINED'}
  }else{
   Check ($failed -and $f.starts -eq 0) ($case+'_NO_START')
   Check (Test-Path -LiteralPath (Join-Path $work 'blocked.json')) ($case+'_MARKER_RETAINED')
  }
 }
 [pscustomobject]@{status='TRANSPORT_RECOVERY_WORKFLOWS_PASSED';assertions=$checks;workflows=$cases.Count;realArchivesAndReplacement=$true;runtimeApisMocked=$true}|ConvertTo-Json
}finally{
 $full=[IO.Path]::GetFullPath($temp);$base=[IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\')+'\'
 if(-not $full.StartsWith($base,[StringComparison]::OrdinalIgnoreCase) -or [IO.Path]::GetFileName($full) -notmatch '^mb-transport-recovery-[a-f0-9]{32}$'){throw 'UNSAFE_FIXTURE_CLEANUP'}
 Remove-Item -LiteralPath $full -Recurse -Force
}
