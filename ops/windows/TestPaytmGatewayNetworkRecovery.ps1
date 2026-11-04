#Requires -Version 7.0
$ErrorActionPreference='Stop'
foreach($n in @('PaytmSupervisorHost.ps1','PaytmGatewayRestart.ps1','PaytmGatewayFailureEvidence.ps1','PaytmGatewayNetworkRecovery.ps1')){. (Join-Path $PSScriptRoot $n)}
Set-StrictMode -Version Latest
$realWrite=(Get-Command Write-PaytmHostJson).ScriptBlock
$temp=Join-Path ([IO.Path]::GetTempPath()) ('mb-network-failure-recovery-'+[guid]::NewGuid().ToString('N'));$null=New-Item -ItemType Directory -Path $temp
$f=@{};$report=@{};$checks=0
function Check($Ok,$Name){if(-not $Ok){throw "RECOVERY_TEST_$Name"};$script:checks++}
function Assert-PaytmAccountPath($Path){$Path}
function Assert-PaytmAccountAcl {}
function Set-PaytmAccountDirectoryAcl {}
function Get-Acl {}
function Add-Type {}
function Get-PaytmKeyContract {@{accountSid='fixture'}}
function Get-PaytmHostContract {@{root=$f.root;work=$f.work;name='fixture-task'}}
function Get-PaytmOwnedHostTask($Id,$Enabled=$true) {if($f.case -eq 'task_drift' -or $Enabled -ne $f.enabled){throw 'HOST_TASK_OWNERSHIP'};@{State=$(if($f.case -eq 'running'){'Running'}else{'Ready'})}}
function Enable-ScheduledTask {$f.enabled=$true}
function Import-Module {}
function Get-ScheduledTask {if($f.case -eq 'leftover_task'){@{TaskName='MarketBrain-Network-Test-fixture'}}}
function Get-NetFirewallRule {param($PolicyStore);if($f.case -eq 'leftover_rule'){@{Name='MarketBrain-Network-Test-fixture'}}}
function Get-ScheduledTaskInfo {@{LastTaskResult=$(if($f.case -eq 'task_result'){0}else{1})}}
function Get-Process {if($f.case -eq 'pid_present'){@{Id=8576}}}
function Get-PaytmTransportListeners {if($f.case -eq 'listener'){'occupied'}}
function Assert-PaytmTransportListener($Rows){if($null -ne $Rows -and @($Rows).Count){throw 'TRANSPORT_LISTENER_PRESENT'}}
function Read-PaytmTransportControl($Root,$Id){(Read-PaytmHostJson (Join-Path $Root 'transport-control.json')).mode}
function Set-PaytmHostControl($Id,$Mode){Write-PaytmHostJson (Join-Path $f.root 'control.json') @{version=1;installationId=$Id;mode=$Mode}}
function Get-FileHash($LiteralPath){
 if($LiteralPath -eq $f.review){@{Hash=$(if($f.case -eq 'bad_receipt'){'BAD'}else{'3AC00E888E53B308D910EB889ABDCAE674917171D497240952C4C39FFBBD5977'})}}
 else{Microsoft.PowerShell.Utility\Get-FileHash -LiteralPath $LiteralPath}
}
function Save-Report {
 Write-PaytmHostJson (Join-Path $f.root 'report.json') $report
 if($f.case -eq 'checkpoint_failure' -and $report.networkFailureRecoveryAttempted){throw 'HOST_CHECKPOINT_FAILED'}
 if($f.case -eq 'marker_drift' -and $report.networkFailureRecoveryAttempted){Write-PaytmHostJson (Join-Path $f.work 'blocked.json') @{failure='HOST_NEW_FAILURE'}}
}
function Write-PaytmHostJson($Path,$Value){
 if($f.Count -and $f.case -eq 'manifest_failure' -and $report.networkFailureRecoveryAttempted -and $Path -eq (Join-Path $f.root 'manifest.json')){throw 'HOST_MANIFEST_WRITE_FAILED'}
 & $realWrite $Path $Value
}
function Start-ScheduledTask {$f.starts++;if($f.case -eq 'start_failure'){throw 'HOST_START_FAILED'}}
function Wait-PaytmManagedHost {
 if($f.case -eq 'worker_failure'){Write-PaytmHostJson (Join-Path $f.work 'blocked.json') @{failure='TRANSPORT_KEY_DENIED'};throw 'HOST_WORKER_BLOCKED'}
 @{instanceId=('b'*32);phase='TRANSPORT_READY'}
}
try{
 $oldAdapter=(@(git show a533f4b:ops/windows/PaytmSupervisorTransport.ps1) -join "`r`n")+"`r`n"
 if($LASTEXITCODE -ne 0){throw 'FIXTURE_SOURCE_UNAVAILABLE'}
 $cases=@('pass','bad_receipt','task_drift','running','task_result','pid_present','listener','changed_marker','source_drift','control_unlocked','lease_held','checkpoint_failure','manifest_failure','marker_drift','start_failure','worker_failure','already_changed','leftover_task','leftover_rule')
 foreach($case in $cases){
  $base=Join-Path $temp $case;$root=Join-Path $base root;$work=Join-Path $base work
  $null=New-Item -ItemType Directory -Path $root,$work
  $f=@{case=$case;root=$root;work=$work;review=(Join-Path $base review.json);starts=0;enabled=$false}
  $report=@{runId=[guid]::NewGuid().ToString('N');networkFailureRecoveryAttempted=$false}
  $id='ea8b91471cf048aa97a0f6b939b355c7';$hashes=@{}
  foreach($n in @('runner.ps1','host.ps1','native.dll','gateway.ps1','transport.ps1','transport.dll')){
   [IO.File]::WriteAllText((Join-Path $root $n),'fixture-'+$n)
   if($n -eq 'runner.ps1'){Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'RunPaytmGatewaySupervisor.ps1') -Destination (Join-Path $root $n) -Force}
   if($n -eq 'transport.ps1'){[IO.File]::WriteAllText((Join-Path $root $n),$oldAdapter,[Text.UTF8Encoding]::new($false))}
   $hashes[$n]=(Get-FileHash -LiteralPath (Join-Path $root $n)).Hash
  }
  $receipt=@{sourceHashes=@{'RunPaytmGatewaySupervisor.ps1'=$hashes['runner.ps1'];'PaytmGatewaySupervisor.ps1'=$hashes['gateway.ps1'];'PaytmSupervisorTransport.ps1'=$hashes['transport.ps1']}}
  $oldTransport=$hashes['transport.ps1']
  if($case -eq 'already_changed'){Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'PaytmSupervisorTransport.ps1') -Destination (Join-Path $root 'transport.ps1') -Force;$hashes['transport.ps1']=(Get-FileHash -LiteralPath (Join-Path $root 'transport.ps1')).Hash}
  Write-PaytmHostJson (Join-Path $root 'manifest.json') @{version=1;transportVersion=1;installationId=$id;hashes=$hashes}
  Set-PaytmHostControl $id $(if($case -eq 'control_unlocked'){'LOCKED'}else{'STOP'})
  Write-PaytmHostJson (Join-Path $root 'transport-control.json') @{version=1;installationId=$id;mode='ENABLED'}
  $files=@{}
  foreach($n in @('startup-failure.json','blocked.json','status.json')){
   Write-PaytmHostJson (Join-Path $work $n) @{failure='TRANSPORT_KEY_DENIED';instanceId='b7598556f2e4478dba5ea94c73eb1f92';processId=8576;phase='BLOCKED';brokerReady=$false;ordersEnabled=$false;lastSshObservation=@{stderrCharacters=245;stderrSha256='43292094F48E6EB533C45228EB0C423B128D31A54D3E56364EB949F4D4B6FA59'}}
   $files[$n]=Get-PaytmWorkerEvidenceFile (Join-Path $work $n)
  }
  Write-PaytmHostJson $f.review @{runId='2ebb314193ad49af954ea8b1eeadbcec';failure='HOST_NETWORK_RESUME_RECEIPT_NOT_REVIEWED';cleanupFailure=$null;networkResumeAttempted=$false;networkInterruptionAttempted=$false;cleanupTasksRegistered=0;accountPreserved=$true;finalApplicationLockVerified=$true;sourceHashes=@{'PaytmSupervisorTransport.ps1'=$oldTransport};workerDiagnostics=@{files=$files;task=@{lastResult=1;definitionVerified=$true;enabled=$false};process=@{exists=$false};controls=@{'control.json'=@{value=@{mode='STOP'}};'transport-control.json'=@{value=@{mode='ENABLED'}}}}}
  if($case -eq 'changed_marker'){Write-PaytmHostJson (Join-Path $work 'blocked.json') @{failure='HOST_NEW_FAILURE'}}
  if($case -eq 'source_drift'){[IO.File]::WriteAllText((Join-Path $root 'gateway.ps1'),'changed')}
  $held=$null;$failed=$false
  try{
   if($case -eq 'lease_held'){$held=[IO.File]::Open((Join-Path $work 'instance.lock'),'OpenOrCreate','ReadWrite','None')}
   Invoke-PaytmReviewedNetworkFailureRecovery $receipt $f.review $PSScriptRoot
  }catch{$failed=$true;if($case -eq 'pass'){throw}}finally{if($held){$held.Dispose()}}
  if($case -eq 'pass'){
   Check (-not $failed -and $f.starts -eq 1 -and $report.networkFailureRecovery.healthy) 'ONE_START_SUCCESS'
   Check ($report.networkFailureRecovery.backupVerified -and $report.networkFailureRecovery.transportUpdated -and $report.networkFailureRecovery.manifestUpdated -and $report.networkFailureRecovery.markersArchived) 'ALL_RECOVERY_PROOFS'
   foreach($n in @('startup-failure.json','blocked.json','status.json')){Check ((Test-Path -LiteralPath (Join-Path $report.networkFailureRecovery.backupPath $n)) -and -not (Test-Path -LiteralPath (Join-Path $work $n))) 'ARCHIVED_BEFORE_REMOVAL'}
   Check ((Read-PaytmHostJson (Join-Path $root 'manifest.json')).hashes.'transport.ps1' -ceq (Get-FileHash -LiteralPath (Join-Path $PSScriptRoot 'PaytmSupervisorTransport.ps1')).Hash) 'EXACT_TRANSPORT_PATCH'
   Check ((Get-FileHash -LiteralPath (Join-Path $root 'runner.ps1')).Hash -ceq $hashes['runner.ps1']) 'RUNNER_UNCHANGED'
   $again=$false;try{Invoke-PaytmReviewedNetworkFailureRecovery $receipt $f.review $PSScriptRoot}catch{$again=$true}
   Check ($again -and $f.starts -eq 1) 'NO_REPEAT_RESET'
  }elseif($case -in @('start_failure','worker_failure')){
   Check ($failed -and $f.starts -eq 1 -and -not $report.networkFailureRecovery.healthy) 'FAILED_START_NO_RETRY'
   Check (Test-Path -LiteralPath (Join-Path $report.networkFailureRecovery.backupPath 'blocked.json')) 'OLD_EVIDENCE_RETAINED'
   if($case -eq 'worker_failure'){Check ((Read-PaytmHostJson (Join-Path $work 'blocked.json')).failure -eq 'TRANSPORT_KEY_DENIED') 'NEW_CAUSE_RETAINED'}
  }else{
   Check ($failed -and $f.starts -eq 0) ($case+'_NO_START')
   Check (Test-Path -LiteralPath (Join-Path $work 'blocked.json')) ($case+'_MARKER_RETAINED')
   if($case -eq 'bad_receipt'){Check ($report.networkRecoveryReceipt.actualSha256 -ceq 'BAD' -and $report.networkRecoveryReceipt.expectedSha256 -ceq '3AC00E888E53B308D910EB889ABDCAE674917171D497240952C4C39FFBBD5977') 'RECEIPT_MISMATCH_DIAGNOSTICS'}
  }
 }
 [pscustomobject]@{status='NETWORK_FAILURE_RECOVERY_WORKFLOWS_PASSED';assertions=$checks;workflows=$cases.Count;realArchivesAndReplacement=$true;runtimeApisMocked=$true}|ConvertTo-Json
}finally{
 $full=[IO.Path]::GetFullPath($temp);$base=[IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\')+'\'
 if(-not $full.StartsWith($base,[StringComparison]::OrdinalIgnoreCase) -or [IO.Path]::GetFileName($full) -notmatch '^mb-network-failure-recovery-[a-f0-9]{32}$'){throw 'UNSAFE_FIXTURE_CLEANUP'}
 Remove-Item -LiteralPath $full -Recurse -Force
}
