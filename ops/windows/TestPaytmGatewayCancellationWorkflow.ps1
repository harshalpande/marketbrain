#Requires -Version 7.0
[CmdletBinding()]param([switch]$PreviousCollector)
$ErrorActionPreference='Stop'
foreach($n in @('PaytmSupervisorHost.ps1','PaytmManagedTransport.ps1','PaytmApplicationRoute.ps1','PaytmGatewayCancellation.ps1','PaytmGatewayFailureEvidence.ps1','PaytmGatewayNetworkRecovery.ps1')){. (Join-Path $PSScriptRoot $n)}
Set-StrictMode -Version Latest
$realFailureEvidence=(Get-Command Get-PaytmWorkerFailureEvidence -CommandType Function).ScriptBlock
$temp=Join-Path ([IO.Path]::GetTempPath()) ('mb-cancel-test-'+[guid]::NewGuid().ToString('N'));$null=New-Item -ItemType Directory -Path $temp
$fixture=@{};$checkState=@{count=0}
function Check($Ok,$Name){if(-not $Ok){throw "CANCEL_WORKFLOW_$Name"};$checkState.count++}
function Assert-PaytmCustodyController {}
function Assert-PaytmAccountPath($Path){$Path}
function Assert-PaytmAccountAcl {}
function Get-Acl {}
function Import-Module {}
function Get-PaytmKeyContract {@{accountSid='fixture'}}
function Get-PaytmAccountContract {@{root=$fixture.root}}
function Get-PaytmHostContract {@{root=$fixture.root;work=$fixture.root;name='fixture-task'}}
function Assert-PaytmRestartAcceptance {}
function Assert-PaytmTransportAcceptance {}
function Assert-PaytmCancellationReceipt {if($fixture.case -eq 'network_preflight'){throw 'NETWORK_CANCELLATION_RECEIPT_INVALID'}}
function Invoke-PaytmReviewedTransportRecovery($Receipt,[string]$Path,[string]$SourceDirectory) {
 $report.transportRecoveryAttempted=$true;$fixture.latchCalls++;Save-Report
 if($fixture.case -eq 'transport_failure'){throw 'TRANSPORT_WORKER_BLOCKED'}
 $report.transportRecovery=@{healthy=$true;startAttempts=1}
}
function Invoke-PaytmNetworkBatch {
 $report.networkInterruptionAttempted=$true
 if($fixture.case -eq 'network_failure'){throw 'NETWORK_BACKOFF_NOT_OBSERVED'}
 $report.networkCleanupRehearsalPassed=$true;$report.networkLossObserved=$true;$report.networkRecoveryPassed=$true;$report.noAutomaticRearmPassed=$true
 foreach($label in @('before','outage','rearm')){$report.applicationRouteChecks.Add(@{label=$label;passed=$true})}
}
function Invoke-PaytmReviewedNetworkResume($Receipt,[string]$Path,[string]$SourceDirectory) {
 $report.networkResumeAttempted=$true;$fixture.latchCalls++;Save-Report
 if($fixture.case -eq 'networkresume_failure'){throw 'HOST_NETWORK_RESUME_NEW_FAILURE'}
 $report.networkResume=@{healthy=$true;startAttempts=1}
}
function Invoke-PaytmReviewedNetworkFailureRecovery($Receipt,[string]$Path,[string]$SourceDirectory) {
 if($fixture.case -like 'checkpoint_*'){
  # Real pinned receipt validator + real collector Save-Report, including nested Path.
  $validated=Assert-PaytmReviewedNetworkDiagnostic $Path
  Check ($validated.runId -ceq '2ebb314193ad49af954ea8b1eeadbcec') 'REAL_RECEIPT_VALIDATED_AFTER_CHECKPOINT'
  Invoke-CheckpointShadowProbe $Path
 }
 $report.networkFailureRecoveryAttempted=$true;$fixture.latchCalls++;Save-Report
 if($fixture.case -eq 'networkrecover_failure'){throw 'HOST_NETWORK_RECOVERY_MARKER_DRIFT'}
 $report.networkFailureRecovery=@{healthy=$true;startAttempts=1}
}
function Invoke-CheckpointShadowProbe([string]$Path){
 $clock=[pscustomobject]@{Elapsed=[TimeSpan]::FromDays(365)}
 $report=@{runId='CALLER_SHADOW';ordersEnabled=$true}
 Save-Report
 $files=@(Get-ChildItem -LiteralPath $fixture.out -Filter '*.json')
 Check ($files.Count -eq 1) 'CHECKPOINT_STAYS_IN_OUTPUT_DIRECTORY'
 $saved=Read-PaytmHostJson $files[0].FullName 65536
 Check ($saved.runId -cne 'CALLER_SHADOW' -and -not $saved.ordersEnabled) 'CALLER_REPORT_CANNOT_REPLACE_COLLECTOR_REPORT'
 Check ($saved.elapsedSeconds -lt 60) 'CALLER_TIMER_CANNOT_REPLACE_COLLECTOR_TIMER'
}
function Assert-PaytmInstalledTransport {if($fixture.case -eq 'worker_failure'){throw 'STARTUP_WORKER_FAILURE_PRESENT'};@{installationId='fixture'}}
function Assert-PaytmTransportInstallationSources {@{installationId='fixture'}}
function Invoke-PaytmReviewedRecoveryResume($Receipt,[string]$Path) {
 $report.resumeRecoveryAttempted=$true;Save-Report;$fixture.latchCalls++
 if($fixture.case -eq 'resume_failure'){throw 'HOST_WORKER_BLOCKED'}
 $report.recoveryResume=@{healthy=$true;startAttempts=1}
}
function Invoke-PaytmReviewedLatchRecovery($Receipt,[string]$DiagnosticPath,[string]$SourceDirectory) {
 $report.latchRecoveryAttempted=$true;Save-Report;$fixture.latchCalls++
 if($fixture.case -eq 'recover_failure'){throw 'HOST_WORKER_BLOCKED'}
 $report.latchRecovery=@{healthy=$true;startAttempts=1}
}
function Get-PaytmWorkerFailureEvidence {
 if($fixture.case -eq 'capture_failure'){throw 'Fixture failure'}
 if($fixture.case -in @('inspect','worker_failure')){& $realFailureEvidence;return}
 @{readOnly=$true;files=@{'blocked.json'=@{present=$true;value=@{failure='TRANSPORT_UNKNOWN'}}}}
}
function Get-PaytmProbeTask {$fixture.taskReads++;[pscustomobject]@{State='Ready';Settings=[pscustomobject]@{Enabled=$true}}}
function Assert-PaytmHostTask {}
function Get-FileHash($LiteralPath){
 if($LiteralPath -eq $fixture.restart){@{Hash=if($fixture.case -eq 'bad_receipt'){'wrong'}else{'E0B23005357143333BC537F8515F5D3A70D14B19E8D92F6F5869ECCEEA50DA06'}}}
 elseif($LiteralPath -eq $fixture.transport){@{Hash='078A34DB0A46951EB98C5A08063F9FC76DB6EC75C175A3572CEE3D65DA4FAB4B'}}
 else{Microsoft.PowerShell.Utility\Get-FileHash -LiteralPath $LiteralPath}
}
function Initialize-PaytmManagedApplication {
 if($fixture.case -in @('unlocked','resume_unlocked','recover_unlocked','transport_unlocked','networkresume_unlocked','networkrecover_unlocked')){throw 'APP_ROUTE_EXPECTED_LOCKED'}
 $application.BeforeAccount='{"cash":100000}';$application.Id='container';$application.Before=@{Id='container';Image='image';State=@{StartedAt='unchanged'}}
 $application.Ready=$true;$application.BootId='boot';$application.Token='PRIVATE_TOKEN_NEVER_REPORT'
}
function Wait-PaytmManagedHost($Id,$Phase,$PreviousInstance=''){
 if($PreviousInstance -and $fixture.case -eq 'recovery_failure'){throw 'TRANSPORT_HEARTBEAT_TIMEOUT'}
 @{instanceId=if($PreviousInstance){'b'*32}else{'a'*32};childProcessId=if($PreviousInstance){202}else{201};childStartTicks=123}
}
function Open-PaytmCancellationProcesses {
 $p=[pscustomobject]@{};$p|Add-Member -MemberType ScriptMethod Dispose {$fixture.disposed++};@{Owner=$p;Child=$p}
}
function Get-PaytmOwnedHostTask {
 if($fixture.case -eq 'task_drift'){throw 'HOST_TASK_OWNERSHIP'}
 @{State=if($fixture.cancelled){'Ready'}else{'Running'}}
}
function Stop-ScheduledTask {
 $fixture.cancelCalls++
 if($fixture.case -eq 'cancel_failure'){throw 'CANCEL_STOP_FAILED'}
 $fixture.cancelled=$true
}
function Start-ScheduledTask {$fixture.cancelled=$false;$fixture.starts++}
function Get-ScheduledTaskInfo {@{LastTaskResult=267014;LastRunTime=[DateTime]::UtcNow}}
function Wait-PaytmCancellationExit {
 if($fixture.case -eq 'orphan'){throw 'CANCEL_PROCESS_OR_LISTENER_SURVIVED'}
 @{taskIdle=$true;ownerExited=$true;childExited=$true;listenerCount=0}
}
function Get-PaytmCancellationExit {
 if($fixture.case -eq 'unexpected_restart'){@{taskIdle=$false;ownerExited=$true;childExited=$true;listenerCount=0}}
 else{@{taskIdle=$true;ownerExited=$true;childExited=$true;listenerCount=0}}
}
function Invoke-PaytmApplicationHttp($Command){
 if($Command -eq 'arm'){$fixture.app='ARMED'}
 if($Command -eq 'lock'){$fixture.app='LOCKED';if($fixture.case -eq 'final_lock_failure'){throw 'APP_ROUTE_FINAL_LOCK_FAILED'}}
 if($Command -eq 'head' -and $fixture.starts -and $fixture.case -eq 'authority_replay'){$fixture.app='ARMED'}
 $status=$fixture.app;$tls=$false;$http=0;$failure='NONE'
 if($Command -eq 'head' -and $fixture.app -eq 'ARMED'){
  if($fixture.cancelled -and $fixture.case -ne 'direct_fallback'){$status='TRANSPORT_FAILED';$fixture.app='LOCKED';$failure='ConnectException'}
  else{$status='TLS_RESPONSE';$tls=$true;$http=503}
 }
 @{state=$fixture.app;status=$status;tlsVerified=$tls;httpStatus=$http;failureType=$failure;bootId='boot'}
}
function Assert-PaytmWriterLocked {}
function Get-PaytmApplicationContainer {$application.Before}
function Read-PaytmPaperAccount {if($fixture.case -eq 'account_drift'){'changed'}else{$application.BeforeAccount}}
function Stop-PaytmFailedManagedHost {$fixture.failureStopped=$true}
try{
 foreach($caseName in @('checkpoint_pass','checkpoint_wrong','networkrecover_pass','networkrecover_failure','networkrecover_unlocked','networkresume_pass','networkresume_failure','networkresume_unlocked','transport_pass','transport_failure','transport_unlocked','network_pass','network_failure','network_preflight','pass','resume_pass','resume_failure','resume_unlocked','recover_pass','recover_failure','recover_unlocked','inspect','worker_failure','capture_failure','bad_receipt','unlocked','task_drift','cancel_failure','orphan','unexpected_restart','direct_fallback','authority_replay','recovery_failure','account_drift','final_lock_failure')){
  $base=Join-Path $temp $caseName;$source=Join-Path $base 'ops/windows';$root=Join-Path $base 'host';$out=Join-Path $base 'out';$null=New-Item -ItemType Directory -Path $source,$root -Force
  $fixture=@{case=$caseName;root=$root;out=$out;review=(Join-Path $base 'review.json');restart=(Join-Path $base 'restart.json');transport=(Join-Path $base 'transport.json');app='LOCKED';cancelled=$false;cancelCalls=0;starts=0;disposed=0;failureStopped=$false;taskReads=0;latchCalls=0}
  [IO.File]::WriteAllText($fixture.restart,'{}');[IO.File]::WriteAllText($fixture.transport,'{}')
  if($caseName -in @('inspect','worker_failure')){Write-PaytmHostJson (Join-Path $root 'blocked.json') @{failure='TRANSPORT_UNKNOWN';instanceId=('a'*32)}}
  foreach($n in @('PaytmGatewayAccount.ps1','PaytmGatewayKeyCustody.ps1','PaytmGatewayScheduledProbe.ps1','PaytmSupervisorHost.ps1','PaytmSupervisorInstallation.ps1','PaytmSupervisorTransport.ps1','PaytmApplicationRoute.ps1','PaytmManagedTransport.ps1','PaytmGatewayRestart.ps1','PaytmGatewayCancellation.ps1','PaytmGatewayFailureEvidence.ps1')){[IO.File]::WriteAllText((Join-Path $source $n),'# fixture')}
  $scriptPath=Join-Path $source 'TestPaytmGatewayCancellation.ps1';Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'TestPaytmGatewayCancellation.ps1') -Destination $scriptPath
  foreach($n in @('PaytmSupervisorRecovery.ps1','PaytmGatewayLatchRecovery.ps1','RunPaytmGatewaySupervisor.ps1','PaytmGatewayNetwork.ps1','RunPaytmNetworkCleanup.ps1','PaytmGatewayTransportRecovery.ps1','PaytmGatewayNetworkResume.ps1','PaytmGatewayNetworkRecovery.ps1')){[IO.File]::WriteAllText((Join-Path $source $n),'# fixture')}
  if($PreviousCollector){$old=@(git show ea69e3e:ops/windows/TestPaytmGatewayCancellation.ps1);if($LASTEXITCODE -ne 0){throw 'PREVIOUS_COLLECTOR_MISSING'};[IO.File]::WriteAllText($scriptPath,($old -join "`n"))}
  [IO.File]::WriteAllText($fixture.review,'{}')
  if($caseName -eq 'checkpoint_pass'){Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'reviewed/paytm-network-e226.json') -Destination $fixture.review -Force}
  $inputHash=(Get-FileHash -LiteralPath $fixture.review).Hash
  $failed=$false;try{& $scriptPath -RecoverReviewedNetworkFailure:($caseName -like 'networkrecover_*' -or $caseName -like 'checkpoint_*') -ResumeReviewedNetwork:($caseName -like 'networkresume_*') -RecoverReviewedTransport:($caseName -like 'transport_*') -NetworkInterruption:($caseName -like 'checkpoint_*' -or $caseName -like 'network_*' -or $caseName -like 'networkrecover_*' -or $caseName -like 'networkresume_*' -or $caseName -like 'transport_*') -ResumeReviewedRecovery:($caseName -like 'resume_*') -RecoverReviewedLatch:($caseName -like 'recover_*') -InspectOnly:($caseName -in @('inspect','capture_failure')) -NetworkDiagnosticReportPath $fixture.review -NetworkFailureReportPath $fixture.review -TransportFailureReportPath $fixture.review -RecoveryReportPath $fixture.review -DiagnosticReportPath $fixture.review -RestartReportPath $fixture.restart -TransportReportPath $fixture.transport -OutputDirectory $out 6>$null}catch{$failed=$true}
  Check ((Get-FileHash -LiteralPath $fixture.review).Hash -ceq $inputHash) 'INPUT_RECEIPT_BYTES_UNCHANGED'
  $files=@(Get-ChildItem -LiteralPath $out -Filter '*.json');Check ($files.Count -eq 1) 'ONE_REPORT'
  $raw=[IO.File]::ReadAllText($files[0].FullName);$v=$raw|ConvertFrom-Json
  Check (-not $raw.Contains('PRIVATE_TOKEN_NEVER_REPORT') -and -not $v.ordersEnabled -and -not $v.keyImported -and -not $v.vpsChanged) 'SCOPE_AND_REDACTION'
  if($caseName -in @('inspect','worker_failure')){Check ($fixture.taskReads -eq 1 -and -not $v.workerDiagnostics.files.'status.json'.present -and $v.workerDiagnostics.files.'blocked.json'.readSucceeded) 'REAL_STRICT_READER_END_TO_END'}
  if($caseName -eq 'inspect'){
   Check (-not $failed -and $v.status -eq 'WORKER_FAILURE_DIAGNOSTICS_CAPTURED' -and $v.workerDiagnostics.readOnly) 'INSPECTION_CAPTURED'
   Check (-not $fixture.cancelCalls -and -not $fixture.starts -and -not $fixture.failureStopped -and -not $v.accountPreserved -and $v.applicationRouteChecks.Count -eq 0) 'INSPECTION_NO_RUNTIME_MUTATION_OR_ACCEPTANCE'
  }elseif($caseName -in @('checkpoint_pass','network_pass','transport_pass','networkresume_pass','networkrecover_pass')){
   Check (-not $failed -and $v.status -eq 'GATEWAY_NETWORK_INTERRUPTION_AND_RECOVERY_PASSED' -and $files[0].Name.StartsWith('paytm-gateway-network-')) ('NETWORK_SUCCESS_'+$caseName+'_'+$v.failure+'_'+($v.failureDetails|ConvertTo-Json -Compress))
   Check ($v.finalApplicationLockVerified -and $v.accountPreserved -and $v.applicationRouteChecks.Count -eq 3 -and -not $fixture.cancelCalls -and -not $fixture.starts) 'NETWORK_NO_TASK_CANCELLATION'
   if($caseName -eq 'transport_pass'){Check ($v.transportRecoveryAttempted -and $v.transportRecovery.healthy -and $fixture.latchCalls -eq 1) 'RECOVERY_THEN_NETWORK'}
  }elseif($caseName -in @('pass','resume_pass','recover_pass')){
   Check (-not $failed -and $v.status -eq 'GATEWAY_CANCELLATION_AND_APPLICATION_RECOVERY_PASSED') 'SUCCESS'
   Check ($v.applicationRouteChecks.Count -eq 3 -and $v.noAutomaticRearmPassed -and $v.finalApplicationLockVerified -and $v.accountPreserved) 'ROUTE_AND_ACCOUNT'
   Check ($fixture.starts -eq 1 -and $fixture.cancelCalls -eq 1 -and $fixture.disposed -eq 2 -and -not $fixture.failureStopped) 'OWNED_PROCESSES_ONLY'
   if($caseName -eq 'recover_pass'){Check ($fixture.latchCalls -eq 1 -and $v.latchRecovery.healthy -and $v.latchRecoveryAttempted) 'RECOVER_THEN_CANCEL'}
   if($caseName -eq 'resume_pass'){Check ($fixture.latchCalls -eq 1 -and $v.recoveryResume.healthy -and $v.resumeRecoveryAttempted -and -not $v.latchRecoveryAttempted) 'RESUME_THEN_CANCEL_NO_REINSTALL'}
  }else{
   Check ($failed -and $v.status -eq 'REVIEW_REQUIRED') 'FAILURE_RETAINED'
   if($caseName -in @('checkpoint_wrong','networkrecover_unlocked','networkresume_unlocked','transport_unlocked','network_preflight','bad_receipt','unlocked','resume_unlocked','recover_unlocked','task_drift','worker_failure','capture_failure')){Check (-not $fixture.cancelCalls -and -not $fixture.starts -and -not $fixture.failureStopped -and -not $fixture.latchCalls) 'PREFLIGHT_NO_MUTATION'}
   else{Check ($fixture.failureStopped -and $v.failureStopVerified) 'FAILURE_DURABLE_STOP'}
   if($caseName -eq 'worker_failure'){Check ($v.workerDiagnostics.files.'blocked.json'.value.failure -eq 'TRANSPORT_UNKNOWN' -and $v.failure -eq 'STARTUP_WORKER_FAILURE_PRESENT') 'ORIGINAL_FAILURE_AND_MARKER_PRESERVED'}
   if($caseName -eq 'recover_failure'){Check ($fixture.latchCalls -eq 1 -and -not $fixture.cancelCalls -and -not $fixture.starts -and $v.finalApplicationLockVerified) 'FAILED_RECOVERY_NO_CANCELLATION_OR_RETRY'}
   if($caseName -eq 'resume_failure'){Check ($fixture.latchCalls -eq 1 -and -not $fixture.cancelCalls -and -not $fixture.starts -and $v.finalApplicationLockVerified) 'FAILED_RESUME_NO_CANCELLATION_OR_RETRY'}
   if($caseName -eq 'networkrecover_failure'){Check ($v.networkFailureRecoveryAttempted -and $fixture.failureStopped -and -not $v.networkInterruptionAttempted) 'FAILED_NETWORK_RECOVERY_STOPPED'}
   if($caseName -eq 'networkresume_failure'){Check ($v.networkResumeAttempted -and $fixture.failureStopped -and -not $v.networkInterruptionAttempted) 'FAILED_NETWORK_RESUME_STOPPED'}
   if($caseName -eq 'transport_failure'){Check ($fixture.latchCalls -eq 1 -and -not $v.networkInterruptionAttempted -and $v.finalApplicationLockVerified) 'FAILED_TRANSPORT_RECOVERY_NO_NETWORK_FAULT'}
  }
 }
 [pscustomobject]@{status='GATEWAY_CANCELLATION_WORKFLOWS_PASSED';assertions=$checkState.count;workflows=35;runtimeApisMocked=$true;realAtomicReports=$true}|ConvertTo-Json
}finally{
 $resolved=[IO.Path]::GetFullPath($temp);$base=[IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\')+'\'
 if(-not $resolved.StartsWith($base,[StringComparison]::OrdinalIgnoreCase) -or [IO.Path]::GetFileName($resolved) -notmatch '^mb-cancel-test-[a-f0-9]{32}$'){throw 'UNSAFE_FIXTURE_CLEANUP'}
 Remove-Item -LiteralPath $resolved -Recurse -Force
}
