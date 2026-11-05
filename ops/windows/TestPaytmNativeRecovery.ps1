#Requires -Version 7.0
$ErrorActionPreference='Stop'
foreach($n in @('PaytmSupervisorHost.ps1','PaytmGatewayRestart.ps1','PaytmGatewayFailureEvidence.ps1','PaytmNativeRecovery.ps1','PaytmManagedTransport.ps1','PaperRuntimeReview.ps1')){. (Join-Path $PSScriptRoot $n)}
Set-StrictMode -Version Latest
$realWrite=(Get-Command Write-PaytmHostJson).ScriptBlock
$realBuild=(Get-Command Invoke-PaytmNativeBuild).ScriptBlock
$temp=Join-Path ([IO.Path]::GetTempPath()) ('mb-native-recovery-'+[guid]::NewGuid().ToString('N'));$null=New-Item -ItemType Directory -Path $temp
$f=@{};$report=@{};$checks=0
function Check($Ok,$Name){if(-not $Ok){throw "RECOVERY_TEST_$Name"};$script:checks++}
function Assert-PaytmAccountPath($Path){$Path}
function Assert-PaytmAccountAcl {}
function Set-PaytmAccountDirectoryAcl {}
function Get-Acl {}
function Add-Type {}
function Get-PaytmKeyContract {@{accountSid='fixture'}}
function Get-PaytmHostContract {@{root=$script:f.root;work=$script:f.work;name='fixture-task';executable='C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe'}}
function Get-PaytmOwnedHostTask {if($script:f.case -eq 'task_drift'){throw 'HOST_TASK_OWNERSHIP'};@{State=$(if($script:f.case -eq 'running'){'Running'}else{'Ready'})}}
function Get-ScheduledTaskInfo {@{LastTaskResult=$(if($script:f.case -eq 'task_result'){0}else{1})}}
function Get-Process {if($script:f.case -eq 'pid_present'){@{Id=18156}}}
function Get-PaytmTransportListeners {if($script:f.case -eq 'listener'){'occupied'}}
function Assert-PaytmTransportListener($Rows){if($null -ne $Rows -and @($Rows).Count){throw 'TRANSPORT_LISTENER_PRESENT'}}
function Read-PaytmTransportControl($Root,$Id){(Read-PaytmHostJson (Join-Path $Root 'transport-control.json')).mode}
function Set-PaytmHostControl($Id,$Mode){Write-PaytmHostJson (Join-Path $script:f.root 'control.json') @{version=1;installationId=$Id;mode=$Mode}}
function Get-FileHash($LiteralPath){
 if($LiteralPath -eq $script:f.review){@{Hash=$(if($script:f.case -eq 'bad_receipt'){'BAD'}else{'857B0C3E835E252EC13DBA0FCFE927A1DF72CAB1DC043AE39F236013EC050024'})}}
 else{Microsoft.PowerShell.Utility\Get-FileHash -LiteralPath $LiteralPath}
}
function Save-NativeRecoveryReport {
 Write-PaytmHostJson (Join-Path $script:f.root 'report.json') $report
 if($script:f.case -eq 'checkpoint_failure' -and $report.nativeRecoveryAttempted){throw 'HOST_CHECKPOINT_FAILED'}
 if($script:f.case -eq 'marker_drift' -and $report.nativeRecoveryAttempted){Write-PaytmHostJson (Join-Path $script:f.work 'blocked.json') @{failure='HOST_NEW_FAILURE'}}
}
function Write-PaytmHostJson($Path,$Value){
 if($script:f.Count -and $script:f.case -eq 'manifest_failure' -and $report.nativeRecoveryAttempted -and $Path -eq (Join-Path $script:f.root 'manifest.json')){throw 'HOST_MANIFEST_WRITE_FAILED'}
 & $realWrite $Path $Value
}
function Invoke-PaytmNativeBuild($Source,$Destination){if($script:f.case -eq 'build_failure'){throw 'HOST_NATIVE_BUILD_FAILED'};[IO.File]::WriteAllText($Destination,'compiled-fixture')}
function Start-ScheduledTask {$script:f.starts++;if($script:f.case -eq 'start_failure'){throw 'HOST_START_FAILED'}}
function Wait-PaytmManagedHost {
 if($script:f.case -eq 'worker_failure'){Write-PaytmHostJson (Join-Path $script:f.work 'blocked.json') @{failure='TRANSPORT_KEY_DENIED'};throw 'HOST_WORKER_BLOCKED'}
 @{instanceId=('b'*32);phase='TRANSPORT_READY'}
}
try{
 $cases=@('pass','bad_receipt','task_drift','running','task_result','pid_present','listener','changed_marker','source_drift','control_stop','build_failure','lease_held','checkpoint_failure','manifest_failure','marker_drift','start_failure','worker_failure','already_changed')
 foreach($case in $cases){
  $base=Join-Path $temp $case;$root=Join-Path $base root;$work=Join-Path $base work
  $null=New-Item -ItemType Directory -Path $root,$work
  $f=@{case=$case;root=$root;work=$work;review=(Join-Path $base review.json);starts=0}
  $report=@{runId=[guid]::NewGuid().ToString('N');nativeRecoveryAttempted=$false}
  $id='ea8b91471cf048aa97a0f6b939b355c7';$hashes=@{}
  foreach($n in @('runner.ps1','host.ps1','native.dll','gateway.ps1','transport.ps1','transport.dll')){
   [IO.File]::WriteAllText((Join-Path $root $n),'fixture-'+$n)
   if($n -eq 'runner.ps1'){Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'RunPaytmGatewaySupervisor.ps1') -Destination (Join-Path $root $n) -Force}
   $hashes[$n]=(Get-FileHash -LiteralPath (Join-Path $root $n)).Hash
  }
  $receipt=@{sourceHashes=@{'RunPaytmGatewaySupervisor.ps1'=$hashes['runner.ps1'];'PaytmGatewaySupervisor.ps1'=$hashes['gateway.ps1'];'PaytmSupervisorTransport.ps1'=$hashes['transport.ps1']}}
  $oldTransport=$hashes['transport.ps1'];$reviewInstalled=@('native.dll','runner.ps1','transport.ps1'|ForEach-Object {@{name=$_;actualSha256=$hashes[$_]}})
  if($case -eq 'already_changed'){[IO.File]::WriteAllText((Join-Path $root 'native.dll'),'newer');$hashes['native.dll']=(Get-FileHash -LiteralPath (Join-Path $root 'native.dll')).Hash}
  Write-PaytmHostJson (Join-Path $root 'manifest.json') @{version=1;transportVersion=1;installationId=$id;hashes=$hashes}
  Set-PaytmHostControl $id $(if($case -eq 'control_stop'){'STOP'}else{'LOCKED'})
  Write-PaytmHostJson (Join-Path $root 'transport-control.json') @{version=1;installationId=$id;mode='ENABLED'}
  $files=@{}
  foreach($n in @('startup-failure.json','blocked.json','status.json')){
   Write-PaytmHostJson (Join-Path $work $n) @{failure='TRANSPORT_UNKNOWN';instanceId='f9d773e4554a4d9fbd26d0dc62c52e2a';processId=11056;phase='BLOCKED';brokerReady=$false;ordersEnabled=$false}
   $files[$n]=Get-PaytmWorkerEvidenceFile (Join-Path $work $n)
  }
  Write-PaytmHostJson $script:f.review @{runId='1290fc4e5fc448ac98c749ff437f4a8d';status='NATIVE_FAILURE_EVIDENCE_CAPTURED';metadataComplete=$true;installedFiles=$reviewInstalled;workerDiagnostics=@{files=$files}}
  if($case -eq 'changed_marker'){Write-PaytmHostJson (Join-Path $work 'blocked.json') @{failure='HOST_NEW_FAILURE'}}
  if($case -eq 'source_drift'){[IO.File]::WriteAllText((Join-Path $root 'gateway.ps1'),'changed')}
  $inputHash=(Microsoft.PowerShell.Utility\Get-FileHash -LiteralPath $script:f.review).Hash
  $held=$null;$failed=$false
  try{
   if($case -eq 'lease_held'){$held=[IO.File]::Open((Join-Path $work 'instance.lock'),'OpenOrCreate','ReadWrite','None')}
   Invoke-PaytmNativeRecovery $receipt $script:f.review $PSScriptRoot
  }catch{$failed=$true;if($case -eq 'pass'){throw}}finally{if($held){$held.Dispose()}}
  Check ((Microsoft.PowerShell.Utility\Get-FileHash -LiteralPath $script:f.review).Hash -ceq $inputHash) 'REVIEWED_INPUT_BYTES_PRESERVED'
  if($case -eq 'pass'){
   Check (-not $failed -and $script:f.starts -eq 1 -and $report.nativeRecovery.healthy) 'ONE_START_SUCCESS'
   Check ($report.nativeRecovery.backupVerified -and $report.nativeRecovery.nativeUpdated -and $report.nativeRecovery.runnerUpdated -and $report.nativeRecovery.manifestUpdated -and $report.nativeRecovery.markersArchived) 'ALL_RECOVERY_PROOFS'
   foreach($n in @('startup-failure.json','blocked.json','status.json')){Check ((Test-Path -LiteralPath (Join-Path $report.nativeRecovery.backupPath $n)) -and -not (Test-Path -LiteralPath (Join-Path $work $n))) 'ARCHIVED_BEFORE_REMOVAL'}
   Check ((Read-PaytmHostJson (Join-Path $root 'manifest.json')).hashes.'native.dll' -ceq (Get-FileHash -LiteralPath (Join-Path $root 'native.dll')).Hash) 'EXACT_NATIVE_PATCH'
   Check ((Get-FileHash -LiteralPath (Join-Path $root 'runner.ps1')).Hash -ceq $hashes['runner.ps1']) 'REVIEWED_RUNNER_BYTES'
   $again=$false;try{Invoke-PaytmNativeRecovery $receipt $script:f.review $PSScriptRoot}catch{$again=$true}
   Check ($again -and $script:f.starts -eq 1) 'NO_REPEAT_RESET'
  }elseif($case -in @('start_failure','worker_failure')){
   Check ($failed -and $script:f.starts -eq 1 -and -not $report.nativeRecovery.healthy) 'FAILED_START_NO_RETRY'
   Check (Test-Path -LiteralPath (Join-Path $report.nativeRecovery.backupPath 'blocked.json')) 'OLD_EVIDENCE_RETAINED'
   if($case -eq 'worker_failure'){Check ((Read-PaytmHostJson (Join-Path $work 'blocked.json')).failure -eq 'TRANSPORT_KEY_DENIED') 'NEW_CAUSE_RETAINED'}
  }else{
   Check ($failed -and $script:f.starts -eq 0) ($case+'_NO_START')
   Check (Test-Path -LiteralPath (Join-Path $work 'blocked.json')) ($case+'_MARKER_RETAINED')
  }
 }
 # Compile and version-probe through the actual production PS7-to-PS5 builder.
 $report=@{nativeRecovery=@{}}
 & $realBuild (Join-Path $PSScriptRoot 'PaytmSupervisorNative.cs') (Join-Path $temp 'actual-native.dll')
 Check ($report.nativeRecovery.build.exitCode -eq 0) 'ACTUAL_NATIVE_BUILD_AND_CURL_PROBE'
 $first=@{version=1;transportVersion=1;installationId=('a'*32);instanceId=('b'*32);processId=10;sessionId=0;sequence=1;elapsedSeconds=100;phase='TRANSPORT_READY';failure=$null;identityVerified=$true;jobContained=$true;networkContacted=$true;transportEnabled=$true;brokerReady=$false;ordersEnabled=$false;agentIdentityVerified=$true;signingVerified=$true;privateCopyAbsent=$true;denialsVerified=$true;childProcessId=11;childStartTicks=100L;httpStatus=503;transportState=@{phase='TRANSPORT_READY';lastSeconds=100;lastHealthSeconds=100}}
 foreach($mode in @('pass','restart','stale_health','gap','frozen','orders','blocked')){
  $current=$first|ConvertTo-Json -Depth 5|ConvertFrom-Json;$current.sequence=2;$current.elapsedSeconds=110
  switch($mode){gap{$current.elapsedSeconds=146} restart{$current.instanceId='c'*32} stale_health{$current.transportState.lastSeconds=131} frozen{$current.sequence=1} orders{$current.ordersEnabled=$true} blocked{$current.phase='BLOCKED'}}
  $failed=$false;try{Assert-PaytmNativeSoakSample $first $current}catch{$failed=$true}
  Check ($failed -eq ($mode -ne 'pass')) ('SOAK_'+$mode)
 }
 [pscustomobject]@{status='NATIVE_RECOVERY_WORKFLOWS_PASSED';assertions=$checks;workflows=$cases.Count;realArchivesAndReplacement=$true;runtimeApisMocked=$true}|ConvertTo-Json
}finally{
 $full=[IO.Path]::GetFullPath($temp);$base=[IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\')+'\'
 if(-not $full.StartsWith($base,[StringComparison]::OrdinalIgnoreCase) -or [IO.Path]::GetFileName($full) -notmatch '^mb-native-recovery-[a-f0-9]{32}$'){throw 'UNSAFE_FIXTURE_CLEANUP'}
 Remove-Item -LiteralPath $full -Recurse -Force
}

