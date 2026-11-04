#Requires -Version 7.0
$ErrorActionPreference='Stop'
foreach($n in @('PaytmSupervisorHost.ps1','PaytmGatewayRestart.ps1','PaytmGatewayFailureEvidence.ps1','PaytmSupervisorRecovery.ps1','PaytmGatewayLatchRecovery.ps1')){. (Join-Path $PSScriptRoot $n)}
Set-StrictMode -Version Latest
$realWrite=(Get-Command Write-PaytmHostJson).ScriptBlock
$temp=Join-Path ([IO.Path]::GetTempPath()) ('mb-latch-test-'+[guid]::NewGuid().ToString('N'));$null=New-Item -ItemType Directory -Path $temp
$checks=0;$fixture=@{};$report=@{}
function Check($Value,$Name){if(-not $Value){throw "LATCH_TEST_$Name"};$script:checks++}
function Assert-PaytmAccountPath($Path){$Path}
function Assert-PaytmAccountAcl {}
function Set-PaytmAccountDirectoryAcl {}
function Get-Acl {}
function Add-Type {}
function Get-PaytmKeyContract {@{accountSid='fixture'}}
function Get-PaytmHostContract {@{root=$fixture.root;work=$fixture.work;name='fixture-task'}}
function Get-PaytmOwnedHostTask {
 if($fixture.case -eq 'task_drift'){throw 'HOST_TASK_OWNERSHIP'}
 @{State=if($fixture.case -eq 'running'){'Running'}else{'Ready'}}
}
function Get-ScheduledTaskInfo {@{LastTaskResult=if($fixture.case -eq 'task_result'){0}else{1}}}
function Get-Process {if($fixture.case -eq 'pid_present'){[pscustomobject]@{Id=6692}}}
function Get-PaytmTransportListeners {if($fixture.case -eq 'listener'){'occupied'}}
function Assert-PaytmTransportListener($Rows){if($null -ne $Rows -and @($Rows).Count){throw 'TRANSPORT_LISTENER_PRESENT'}}
function Read-PaytmTransportControl($Root,$Id){(Read-PaytmHostJson (Join-Path $Root 'transport-control.json')).mode}
function Set-PaytmHostControl($Id,$Mode){Write-PaytmHostJson (Join-Path $fixture.root 'control.json') @{version=1;installationId=$Id;mode=$Mode}}
function Start-ScheduledTask {$fixture.starts++;if($fixture.case -eq 'start_failure'){throw 'HOST_START_FAILED'}}
function Wait-PaytmManagedHost {
 if($fixture.case -eq 'worker_failure'){
  Write-PaytmHostJson (Join-Path $fixture.work 'startup-failure.json') @{failure='HOST_SIGNING_FAILED'}
  throw 'HOST_WORKER_BLOCKED'
 }
 @{instanceId=('b'*32);phase='TRANSPORT_READY'}
}
function Save-Report {
 Write-PaytmHostJson (Join-Path $fixture.root 'test-report.json') $report
 if($fixture.case -eq 'checkpoint_failure' -and $report.latchRecoveryAttempted){throw 'HOST_CHECKPOINT_FAILED'}
 if($fixture.case -eq 'late_marker_drift' -and $report.latchRecoveryAttempted){Write-PaytmHostJson (Join-Path $fixture.work 'blocked.json') @{failure='HOST_NEW_FAILURE'}}
}
function Write-PaytmHostJson($Path,$Value){
 if($fixture.Count -and $fixture.case -eq 'manifest_failure' -and $report.latchRecoveryAttempted -and $Path -eq (Join-Path $fixture.root 'manifest.json')){throw 'HOST_MANIFEST_WRITE_FAILED'}
 & $realWrite $Path $Value
}
function Get-FileHash($LiteralPath){
 if($LiteralPath -eq $fixture.diagnostic){@{Hash=if($fixture.case -eq 'bad_receipt'){'BAD'}else{'84CD04B5A73CF08C01F88668265DCD06D6DDF8CC60F1A755BD38AB6733F6D66C'}}}
 else{Microsoft.PowerShell.Utility\Get-FileHash -LiteralPath $LiteralPath}
}
try{
 $cases=@('pass','bad_receipt','task_drift','running','task_result','pid_present','listener','changed_marker','source_drift','control_stop','lease_held','checkpoint_failure','manifest_failure','late_marker_drift','start_failure','worker_failure','already_changed')
 foreach($case in $cases){
  $base=Join-Path $temp $case;$root=Join-Path $base 'root';$work=Join-Path $base 'work'
  $null=New-Item -ItemType Directory -Path $root,$work
  $fixture=@{case=$case;root=$root;work=$work;diagnostic=(Join-Path $base 'diagnostic.json');starts=0}
  $report=@{runId=[guid]::NewGuid().ToString('N');latchRecoveryAttempted=$false}
  $id='ea8b91471cf048aa97a0f6b939b355c7';$hashes=@{}
  foreach($n in @('runner.ps1','host.ps1','native.dll','gateway.ps1','transport.ps1','transport.dll')){
   [IO.File]::WriteAllText((Join-Path $root $n),'fixture-'+$n);$hashes[$n]=(Get-FileHash -LiteralPath (Join-Path $root $n)).Hash
  }
  $receipt=@{sourceHashes=@{'RunPaytmGatewaySupervisor.ps1'=$hashes['runner.ps1'];'PaytmGatewaySupervisor.ps1'=$hashes['gateway.ps1'];'PaytmSupervisorTransport.ps1'=$hashes['transport.ps1']}}
  if($case -eq 'already_changed'){
   Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'RunPaytmGatewaySupervisor.ps1') -Destination (Join-Path $root 'runner.ps1')
   $hashes['runner.ps1']=(Get-FileHash -LiteralPath (Join-Path $root 'runner.ps1')).Hash
  }
  Write-PaytmHostJson (Join-Path $root 'manifest.json') @{version=1;transportVersion=1;installationId=$id;hashes=$hashes}
  Set-PaytmHostControl $id $(if($case -eq 'control_stop'){'STOP'}else{'LOCKED'})
  Write-PaytmHostJson (Join-Path $root 'transport-control.json') @{version=1;installationId=$id;mode='ENABLED'}
  $files=@{}
  foreach($n in @('startup-failure.json','blocked.json','status.json')){
   Write-PaytmHostJson (Join-Path $work $n) @{failure='TRANSPORT_PREVIOUS_FAILURE_REVIEW_REQUIRED';instanceId=('a'*32);processId=6692;phase='BLOCKED'}
   $files[$n]=Get-PaytmWorkerEvidenceFile (Join-Path $work $n)
  }
  Write-PaytmHostJson $fixture.diagnostic @{runId='8c0d2d14cb304f9493a08f87ba281250';status='WORKER_FAILURE_DIAGNOSTICS_CAPTURED';inspectionOnly=$true;failure=$null;cleanupFailure=$null;workerDiagnostics=@{files=$files}}
  if($case -eq 'changed_marker'){Write-PaytmHostJson (Join-Path $work 'blocked.json') @{failure='HOST_NEW_FAILURE'}}
  if($case -eq 'source_drift'){[IO.File]::WriteAllText((Join-Path $root 'gateway.ps1'),'changed')}
  $held=$null;$failed=$false
  try{
   if($case -eq 'lease_held'){$held=[IO.File]::Open((Join-Path $work 'instance.lock'),'OpenOrCreate','ReadWrite','None')}
   Invoke-PaytmReviewedLatchRecovery $receipt $fixture.diagnostic $PSScriptRoot
  }catch{$failed=$true;if($case -eq 'pass'){throw}}finally{if($held){$held.Dispose()}}
  if($case -eq 'pass'){
   Check (-not $failed -and $fixture.starts -eq 1 -and $report.latchRecovery.healthy) 'SINGLE_START_SUCCESS'
   Check ($report.latchRecovery.backupVerified -and $report.latchRecovery.markersArchived -and $report.latchRecovery.runnerUpdated -and $report.latchRecovery.manifestUpdated) 'RECOVERY_PROOFS'
   foreach($n in @('startup-failure.json','blocked.json','status.json')){
    Check ((Test-Path -LiteralPath (Join-Path $report.latchRecovery.backupPath $n)) -and -not (Test-Path -LiteralPath (Join-Path $work $n))) 'ARCHIVE_PRESERVED'
   }
   Check ((Read-PaytmHostJson (Join-Path $root 'manifest.json')).hashes.'runner.ps1' -ceq (Get-FileHash -LiteralPath (Join-Path $PSScriptRoot 'RunPaytmGatewaySupervisor.ps1')).Hash) 'EXACT_REPLACEMENT'
   $againFailed=$false;try{Invoke-PaytmReviewedLatchRecovery $receipt $fixture.diagnostic $PSScriptRoot}catch{$againFailed=$true}
   Check ($againFailed -and $fixture.starts -eq 1) 'RERUN_CANNOT_RESET_AGAIN'
  }elseif($case -in @('start_failure','worker_failure')){
   Check ($failed -and $fixture.starts -eq 1 -and -not $report.latchRecovery.healthy) 'NO_RETRY_ON_NEW_FAILURE'
   Check (Test-Path -LiteralPath (Join-Path $report.latchRecovery.backupPath 'startup-failure.json')) 'FAILURE_ARCHIVE_RETAINED'
   if($case -eq 'worker_failure'){Check ((Read-PaytmHostJson (Join-Path $work 'startup-failure.json')).failure -ceq 'HOST_SIGNING_FAILED') 'NEW_CAUSE_PRESERVED'}
  }else{
   Check ($failed -and $fixture.starts -eq 0) ($case+'_NO_START')
   Check (Test-Path -LiteralPath (Join-Path $work 'blocked.json')) ($case+'_LATCH_RETAINED')
   if($case -in @('manifest_failure','late_marker_drift')){
    Check ((Read-PaytmHostJson (Join-Path $root 'control.json')).mode -ceq 'STOP' -and (Test-Path -LiteralPath (Join-Path $report.latchRecovery.backupPath 'startup-failure.json'))) 'PARTIAL_UPDATE_STOP_AND_BACKUP'
   }
  }
 }
 Check (-not (Test-PaytmFirstFailureRunnerHash ('F'*64))) 'UNKNOWN_RUNNER_REJECTED'
 [pscustomobject]@{status='LATCH_RECOVERY_ENGINEERING_PASSED';assertions=$checks;workflows=$cases.Count;realFileBackupsAndReplacement=$true;runtimeApisMocked=$true}|ConvertTo-Json
}finally{
 $resolved=[IO.Path]::GetFullPath($temp);$base=[IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\')+'\'
 if(-not $resolved.StartsWith($base,[StringComparison]::OrdinalIgnoreCase) -or [IO.Path]::GetFileName($resolved) -notmatch '^mb-latch-test-[a-f0-9]{32}$'){throw 'UNSAFE_FIXTURE_CLEANUP'}
 Remove-Item -LiteralPath $resolved -Recurse -Force
}
