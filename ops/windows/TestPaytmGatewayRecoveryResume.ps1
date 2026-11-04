#Requires -Version 7.0
$ErrorActionPreference='Stop'
foreach($n in @('PaytmSupervisorHost.ps1','PaytmManagedTransport.ps1','PaytmGatewayRestart.ps1','PaytmGatewayLatchRecovery.ps1')){. (Join-Path $PSScriptRoot $n)}
Set-StrictMode -Version Latest
$temp=Join-Path ([IO.Path]::GetTempPath()) ('mb-resume-test-'+[guid]::NewGuid().ToString('N'));$null=New-Item -ItemType Directory -Path $temp
$fixture=@{};$report=@{};$checks=0;$id='ea8b91471cf048aa97a0f6b939b355c7';$reviewedRun='c331433dafe242bca2d651c4625866aa'
function Check($Ok,$Name){if(-not $Ok){throw "RESUME_TEST_$Name"};$script:checks++}
function Assert-PaytmAccountPath($Path){$Path}
function Assert-PaytmAccountAcl {}
function Get-Acl {}
function Add-Type {}
function Get-PaytmKeyContract {@{accountSid='fixture'}}
function Get-PaytmHostContract {@{root=$fixture.root;work=$fixture.work;name='fixture'}}
function Get-PaytmOwnedHostTask($Id,$Enabled=$true){
 if($Enabled -ne $fixture.enabled){throw 'HOST_TASK_SETTINGS'}
 @{State=if($fixture.running){'Running'}else{'Ready'}}
}
function Get-Process {if($fixture.case -eq 'process_present'){@{Id=13512}}}
function Get-PaytmTransportListeners {if($fixture.case -eq 'listener'){'occupied'}}
function Assert-PaytmTransportListener($Rows,$Owner=0){if($fixture.case -eq 'listener'){throw 'TRANSPORT_LISTENER_CONFLICT'}}
function Read-PaytmTransportControl($Root,$Id){(Read-PaytmHostJson (Join-Path $Root 'transport-control.json')).mode}
function Set-PaytmHostControl($Id,$Mode){Write-PaytmHostJson (Join-Path $fixture.root 'control.json') @{version=1;installationId=$Id;mode=$Mode}}
function Save-Report {Write-PaytmHostJson (Join-Path $fixture.base 'out.json') $report}
function Write-Progress {}
function Enable-ScheduledTask {if($fixture.case -eq 'enable_failure'){throw 'HOST_ENABLE_FAILED'};$fixture.enabled=$true;$fixture.enables++}
function Start-ScheduledTask {
 $fixture.starts++
 if($fixture.case -eq 'start_failure'){throw 'HOST_START_FAILED'}
 $fixture.running=$true
 Remove-Item -LiteralPath (Join-Path $fixture.work 'status.json')
 if($fixture.case -eq 'new_failure'){Write-PaytmHostJson (Join-Path $fixture.work 'startup-failure.json') @{failure='HOST_SIGNING_FAILED'}}
}
function Start-Sleep {
 param($Milliseconds)
 $fixture.sleeps++
 Write-PaytmHostJson (Join-Path $fixture.work 'status.json') @{version=1;transportVersion=1;installationId=$id;instanceId=('b'*32);phase='TRANSPORT_READY';sequence=$fixture.sleeps;elapsedSeconds=$fixture.sleeps;processId=100;sessionId=0;failure=$null;identityVerified=$true;jobContained=$true;agentIdentityVerified=$true;signingVerified=$true;privateCopyAbsent=$true;networkContacted=$true;transportEnabled=$true;brokerReady=$false;ordersEnabled=$false;denialsVerified=$true;childProcessId=101;childStartTicks=123;httpStatus=503;transportState=@{phase='TRANSPORT_READY'}}
}
function Get-FileHash($LiteralPath){
 if($LiteralPath -eq $fixture.receipt){@{Hash=if($fixture.case -eq 'bad_receipt'){'BAD'}else{'6C99A77672CEAC0CC5E1696427F509977BA5AE23AA943E176AC37EE157E52C3B'}}}
 else{Microsoft.PowerShell.Utility\Get-FileHash -LiteralPath $LiteralPath}
}
try{
 $cases=@('pass','bad_receipt','archive_drift','new_marker','runner_drift','enabled','running','wrong_control','wrong_worker','process_present','listener','lease_held','enable_failure','start_failure','new_failure')
 foreach($case in $cases){
  $base=Join-Path $temp $case;$root=Join-Path $base 'root';$work=Join-Path $base 'work';$archive=Join-Path $root ('latch-recovery-'+$reviewedRun)
  $null=New-Item -ItemType Directory -Path $work,$archive -Force
  $fixture=@{case=$case;base=$base;root=$root;work=$work;receipt=(Join-Path $base 'review.json');enabled=($case -eq 'enabled');running=($case -eq 'running');starts=0;enables=0;sleeps=0}
  $report=@{runId=[guid]::NewGuid().ToString('N');resumeRecoveryAttempted=$false}
  $hashes=@{}
  foreach($n in @('runner.ps1','host.ps1','native.dll','gateway.ps1','transport.ps1','transport.dll')){
   [IO.File]::WriteAllText((Join-Path $root $n),'fixture-'+$n)
   if($n -eq 'runner.ps1'){Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'RunPaytmGatewaySupervisor.ps1') -Destination (Join-Path $root $n)}
   $hashes[$n]=(Get-FileHash -LiteralPath (Join-Path $root $n)).Hash
  }
  Write-PaytmHostJson (Join-Path $root 'manifest.json') @{version=1;transportVersion=1;installationId=$id;hashes=$hashes}
  Set-PaytmHostControl $id $(if($case -eq 'wrong_control'){'LOCKED'}else{'STOP'})
  Write-PaytmHostJson (Join-Path $root 'transport-control.json') @{version=1;installationId=$id;mode='ENABLED'}
  $old=@{installationId=$id;instanceId=('a'*32);processId=13512;failure=$null;brokerReady=$false;ordersEnabled=$false}
  Write-PaytmHostJson (Join-Path $work 'status.json') $old
  $archived=@{}
  foreach($n in @('runner.ps1','manifest.json','control.json','transport-control.json','startup-failure.json','blocked.json','status.json')){
   if($n -eq 'manifest.json'){Copy-Item -LiteralPath (Join-Path $root $n) -Destination (Join-Path $archive $n)}else{[IO.File]::WriteAllText((Join-Path $archive $n),'retained-original-'+$n)}
   $archived[$n]=(Get-FileHash -LiteralPath (Join-Path $archive $n)).Hash
  }
  Write-PaytmHostJson $fixture.receipt @{runId=$reviewedRun;failureStopVerified=$true;accountPreserved=$true;finalApplicationLockVerified=$true;cleanupFailure=$null;cancellationAttempted=$false;failureDetails=@{type='FileNotFoundException'};latchRecovery=@{manifestUpdated=$true;markersArchived=$true;startAttempts=1;newRunnerHash=$hashes['runner.ps1'];backupHashes=$archived};workerDiagnostics=@{statusAfter=@{value=$old}}}
  if($case -eq 'archive_drift'){[IO.File]::WriteAllText((Join-Path $archive 'blocked.json'),'changed')}
  if($case -eq 'runner_drift'){[IO.File]::WriteAllText((Join-Path $root 'runner.ps1'),'changed')}
  if($case -eq 'new_marker'){Write-PaytmHostJson (Join-Path $work 'blocked.json') @{failure='HOST_NEW_FAILURE'}}
  if($case -eq 'wrong_worker'){$old.instanceId='c'*32;Write-PaytmHostJson (Join-Path $work 'status.json') $old}
  $receipt=@{sourceHashes=@{'RunPaytmGatewaySupervisor.ps1'=('F'*64);'PaytmGatewaySupervisor.ps1'=$hashes['gateway.ps1'];'PaytmSupervisorTransport.ps1'=$hashes['transport.ps1']}}
  $held=$null;$failed=$false
  try{
   if($case -eq 'lease_held'){$held=[IO.File]::Open((Join-Path $work 'instance.lock'),'OpenOrCreate','ReadWrite','None')}
   Invoke-PaytmReviewedRecoveryResume $receipt $fixture.receipt
  }catch{$failed=$true;if($case -eq 'pass'){throw}}finally{if($held){$held.Dispose()}}
  if($case -eq 'pass'){
   Check (-not $failed -and $report.recoveryResume.healthy -and $fixture.starts -eq 1 -and $fixture.sleeps -eq 2) 'REAL_WAIT_WITH_ABSENT_FIRST_HEARTBEAT'
   Check ($report.recoveryResume.installationUnchanged -and $report.recoveryResume.archivesVerified -and $fixture.enables -eq 1) 'VERIFIED_RESUME'
  }else{
   Check $failed ($case+'_BLOCKED')
   Check ($fixture.starts -eq $(if($case -in @('start_failure','new_failure')){1}else{0})) ($case+'_NO_UNEXPECTED_START')
   if($case -eq 'new_failure'){Check (Test-Path -LiteralPath (Join-Path $work 'startup-failure.json')) 'NEW_CAUSE_NOT_CLEARED'}
  }
  if($case -ne 'runner_drift'){Check ((Get-FileHash -LiteralPath (Join-Path $root 'runner.ps1')).Hash -ceq $hashes['runner.ps1']) 'NO_REINSTALL'}
  if($case -ne 'archive_drift'){foreach($n in $archived.Keys){Check ((Get-FileHash -LiteralPath (Join-Path $archive $n)).Hash -ceq $archived[$n]) 'ARCHIVE_UNCHANGED'}}
 }
 [pscustomobject]@{status='REVIEWED_RECOVERY_RESUME_PASSED';assertions=$checks;workflows=$cases.Count;actualWaitAndFileGuards=$true;runtimeApisMocked=$true}|ConvertTo-Json
}finally{
 $full=[IO.Path]::GetFullPath($temp);$base=[IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\')+'\'
 if(-not $full.StartsWith($base,[StringComparison]::OrdinalIgnoreCase) -or [IO.Path]::GetFileName($full) -notmatch '^mb-resume-test-[a-f0-9]{32}$'){throw 'UNSAFE_FIXTURE_CLEANUP'}
 Remove-Item -LiteralPath $full -Recurse -Force
}
