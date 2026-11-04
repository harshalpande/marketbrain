#Requires -Version 7.0
[CmdletBinding()]param(
 [switch]$InspectOnly,
 [switch]$RecoverReviewedLatch,
 [switch]$ResumeReviewedRecovery,
 [switch]$NetworkInterruption,
 [switch]$RecoverReviewedTransport,
 [string]$TransportFailureReportPath='C:\MarketBrainData\Review\paytm-gateway-network-b49f51c3f0db4ad996892fcdcd6b14b7.json',
 [string]$CancellationReportPath='C:\MarketBrainData\Review\paytm-gateway-cancellation-1eebaa9b8dec4b9b82d8fa9f66b26859.json',
 [string]$RecoveryReportPath='C:\MarketBrainData\Review\paytm-gateway-cancellation-c331433dafe242bca2d651c4625866aa.json',
 [string]$DiagnosticReportPath='C:\MarketBrainData\Review\paytm-gateway-cancellation-8c0d2d14cb304f9493a08f87ba281250.json',
 [string]$RestartReportPath='C:\MarketBrainData\Review\paytm-gateway-restart-eb86108cc1e247d68d06e135eb580bf6.json',
 [string]$TransportReportPath='C:\MarketBrainData\Review\paytm-managed-transport-20261103-171133-8ac7cdda3ca7475eb001df485797cb70.json',
 [string]$OutputDirectory='C:\MarketBrainData\Review')
$ErrorActionPreference='Stop'
foreach($name in @('PaytmGatewayAccount.ps1','PaytmGatewayKeyCustody.ps1','PaytmGatewayScheduledProbe.ps1','PaytmSupervisorHost.ps1','PaytmSupervisorInstallation.ps1','PaytmSupervisorTransport.ps1','PaytmApplicationRoute.ps1','PaytmManagedTransport.ps1','PaytmGatewayRestart.ps1','PaytmGatewayCancellation.ps1','PaytmGatewayFailureEvidence.ps1')){. (Join-Path $PSScriptRoot $name)}
if($RecoverReviewedLatch -or $ResumeReviewedRecovery){foreach($name in @('PaytmSupervisorRecovery.ps1','PaytmGatewayLatchRecovery.ps1')){. (Join-Path $PSScriptRoot $name)}}
if($NetworkInterruption){. (Join-Path $PSScriptRoot 'PaytmGatewayNetwork.ps1')}
if($RecoverReviewedTransport){foreach($name in @('PaytmGatewayLatchRecovery.ps1','PaytmGatewayTransportRecovery.ps1')){. (Join-Path $PSScriptRoot $name)}}
$clock=[Diagnostics.Stopwatch]::StartNew();$c=Get-PaytmHostContract;$lease=$null;$finished=$false
$route=@{Root=(Resolve-Path (Join-Path $PSScriptRoot '../..')).Path};$application=@{Ready=$false;Token=$null}
$report=[ordered]@{version=1;runId=[guid]::NewGuid().ToString('N');status='REVIEW_REQUIRED';stage='PREFLIGHT';failure=$null;failureDetails=$null;cleanupFailure=$null;elapsedSeconds=0;sourceHashes=@{};
 inspectionOnly=[bool]$InspectOnly;latchRecoveryAttempted=$false;resumeRecoveryAttempted=$false;cancellationAttempted=$false;cancellationPassed=$false;recoveryPassed=$false;noAutomaticRearmPassed=$false;accountPreserved=$false;finalApplicationLockVerified=$false;failureStopVerified=$false;
 networkInterruptionAttempted=$false;networkCleanupRehearsalPassed=$false;networkLossObserved=$false;networkRecoveryPassed=$false;cleanupTasksRegistered=0;transportRecoveryAttempted=$false;
 applicationCommands=[Collections.Generic.List[object]]::new();applicationObservations=[Collections.Generic.List[object]]::new();applicationRouteChecks=[Collections.Generic.List[object]]::new();
 credentialsUsed=$false;ordersEnabled=$false;vpsChanged=$false;keyImported=$false;taskReRegistered=$false;rebootRequested=$false}
$null=Assert-PaytmAccountPath $OutputDirectory;$null=New-Item -ItemType Directory -Path $OutputDirectory -Force
$prefix=if($NetworkInterruption){'paytm-gateway-network-'}else{'paytm-gateway-cancellation-'}
$path=Join-Path $OutputDirectory ($prefix+$report.runId+'.json')
function Save-Report {
 $report.elapsedSeconds=[math]::Round($clock.Elapsed.TotalSeconds,3)
 # Recovery archives and failure projections share this one bounded report.
 $bytes=[Text.Encoding]::UTF8.GetBytes(($report|ConvertTo-Json -Depth 12 -Compress))
 if($bytes.Length -gt 65536){throw 'CANCEL_REPORT_TOO_LARGE'}
 $temporary=$path+'.'+[guid]::NewGuid().ToString('N')+'.tmp'
 try{
  $f=[IO.File]::Open($temporary,'CreateNew','Write','None')
  try{$f.Write($bytes,0,$bytes.Length);$f.Flush($true)}finally{$f.Dispose()}
  if([IO.File]::Exists($path)){[IO.File]::Replace($temporary,$path,[Management.Automation.Language.NullString]::Value)}else{[IO.File]::Move($temporary,$path)}
 }finally{if([IO.File]::Exists($temporary)){[IO.File]::Delete($temporary)}}
}
function Cancellation-Step($Stage,$Percent){$report.stage=$Stage;Save-Report;Write-Host "[$Percent%] $Stage";Write-Progress -Activity 'Gateway cancellation and recovery' -Status $Stage -PercentComplete $Percent}
try{
 Assert-PaytmCustodyController;Import-Module ScheduledTasks
 if(([int][bool]$InspectOnly+[int][bool]$RecoverReviewedLatch+[int][bool]$ResumeReviewedRecovery+[int][bool]$NetworkInterruption) -gt 1){throw 'HOST_LATCH_INCOMPATIBLE_MODES'}
 if($RecoverReviewedTransport -and -not $NetworkInterruption){throw 'HOST_TRANSPORT_RECOVERY_REQUIRES_NETWORK_BATCH'}
 if($RecoverReviewedTransport){foreach($name in @('PaytmGatewayLatchRecovery.ps1','PaytmGatewayTransportRecovery.ps1')){$report.sourceHashes[$name]=(Get-FileHash -LiteralPath (Join-Path $PSScriptRoot $name)).Hash}}
 if($NetworkInterruption){foreach($name in @('PaytmGatewayNetwork.ps1','RunPaytmNetworkCleanup.ps1')){$report.sourceHashes[$name]=(Get-FileHash -LiteralPath (Join-Path $PSScriptRoot $name)).Hash};Assert-PaytmCancellationReceipt $CancellationReportPath}
 if($RecoverReviewedLatch -or $ResumeReviewedRecovery){foreach($name in @('PaytmSupervisorRecovery.ps1','PaytmGatewayLatchRecovery.ps1','RunPaytmGatewaySupervisor.ps1')){$report.sourceHashes[$name]=(Get-FileHash -LiteralPath (Join-Path $PSScriptRoot $name)).Hash}}
 foreach($name in @('TestPaytmGatewayCancellation.ps1','PaytmGatewayCancellation.ps1','PaytmGatewayFailureEvidence.ps1','PaytmGatewayRestart.ps1','PaytmManagedTransport.ps1','PaytmSupervisorInstallation.ps1','PaytmSupervisorTransport.ps1','PaytmApplicationRoute.ps1')){$report.sourceHashes[$name]=(Get-FileHash -LiteralPath (Join-Path $PSScriptRoot $name)).Hash}
 $null=Assert-PaytmAccountPath $c.root;Assert-PaytmAccountAcl (Get-Acl -LiteralPath $c.root) (Get-PaytmKeyContract).accountSid
 $lease=[IO.File]::Open((Assert-PaytmAccountPath (Join-Path (Get-PaytmAccountContract).root 'supervisor-install.lock')),'OpenOrCreate','ReadWrite','None')
 if($InspectOnly){
  Cancellation-Step 'READ_SAVED_WORKER_FAILURE_AND_TASK_STATE' 35
  $report.workerDiagnostics=Get-PaytmWorkerFailureEvidence
  $finished=$true;$report.status='WORKER_FAILURE_DIAGNOSTICS_CAPTURED';$report.stage='COMPLETE'
 }else{
 foreach($pair in @(@($RestartReportPath,'E0B23005357143333BC537F8515F5D3A70D14B19E8D92F6F5869ECCEEA50DA06'),@($TransportReportPath,'078A34DB0A46951EB98C5A08063F9FC76DB6EC75C175A3572CEE3D65DA4FAB4B'))){
  $null=Assert-PaytmAccountPath $pair[0];if((Get-FileHash -LiteralPath $pair[0]).Hash -cne $pair[1]){throw 'CANCEL_ACCEPTED_RECEIPT_HASH'}
 }
 $restart=Read-PaytmHostJson $RestartReportPath;Assert-PaytmRestartAcceptance $restart
 $receipt=Read-PaytmHostJson $TransportReportPath 65536;Assert-PaytmTransportAcceptance $receipt
 Cancellation-Step 'VERIFY_UNCHANGED_INSTALLATION_AND_APPLICATION' 15
 if($RecoverReviewedTransport){
  $manifest=Assert-PaytmTransportInstallationSources $receipt
  Initialize-PaytmManagedApplication
  Cancellation-Step 'ARCHIVE_EXACT_FAILURE_AND_UPDATE_SSH_OBSERVATION' 20
  Invoke-PaytmReviewedTransportRecovery $receipt $TransportFailureReportPath $PSScriptRoot
 }
 if($ResumeReviewedRecovery){
  $manifest=Assert-PaytmTransportInstallationSources $receipt
  Initialize-PaytmManagedApplication
  Cancellation-Step 'RESUME_COMPLETED_UPDATE_AND_WAIT_FOR_FIRST_HEARTBEAT' 20
  Invoke-PaytmReviewedRecoveryResume $receipt $RecoveryReportPath
 }
 if($RecoverReviewedLatch){
  $manifest=Assert-PaytmTransportInstallationSources $receipt
  Initialize-PaytmManagedApplication
  Cancellation-Step 'ARCHIVE_REVIEWED_FAILURE_AND_RECOVER_ONCE' 20
  Invoke-PaytmReviewedLatchRecovery $receipt $DiagnosticReportPath $PSScriptRoot
 }
 $manifest=Assert-PaytmInstalledTransport $receipt
 if(-not $application.Ready){Initialize-PaytmManagedApplication}
 if($NetworkInterruption){Invoke-PaytmNetworkBatch $manifest.installationId $PSScriptRoot}else{Invoke-PaytmCancellationBatch $manifest.installationId}
 $finished=$true;Cancellation-Step 'VERIFY_FINAL_ACCOUNT_AND_LOCK' 95
 }
}catch{
 $report.failure=if($_.Exception.Message -cmatch '^(NETWORK|CANCEL|HOST|TRANSPORT|STARTUP|APP_ROUTE|ACCOUNT|KEY)_[A-Z_]+$'){$_.Exception.Message}else{'CANCEL_VERIFICATION_FAILED'}
 $report.failureDetails=@{type=$_.Exception.GetBaseException().GetType().Name;line=$_.InvocationInfo.ScriptLineNumber;script=[IO.Path]::GetFileName($_.InvocationInfo.ScriptName);errorId=$_.FullyQualifiedErrorId;category=[string]$_.CategoryInfo.Category;hResult=$_.Exception.GetBaseException().HResult}
}finally{
 if(-not $finished -and -not $report.failure){$report.failure='CANCEL_COLLECTION_INTERRUPTED'}
 try{
  if($application.Ready){
   $v=Invoke-PaytmApplicationHttp 'lock';if($v.state -cne 'LOCKED' -or $v.bootId -cne $application.BootId){throw 'APP_ROUTE_FINAL_LOCK_FAILED'}
   $report.finalApplicationLockVerified=$true;Assert-PaytmWriterLocked
   $current=Get-PaytmApplicationContainer
   if($current.Id -cne $application.Id -or $current.Image -cne $application.Before.Image -or $current.State.StartedAt -cne $application.Before.State.StartedAt -or (Read-PaytmPaperAccount) -cne $application.BeforeAccount){throw 'APP_ROUTE_APPLICATION_OR_ACCOUNT_CHANGED'}
   $report.accountPreserved=$true
  }
 }catch{$report.cleanupFailure='CANCEL_FINAL_LOCK_OR_ACCOUNT_FAILED'}
 $application.Token=$null
 if($report.failure){try{$report.workerDiagnostics=Get-PaytmWorkerFailureEvidence}catch{$report.diagnosticCaptureError=$_.Exception.GetBaseException().GetType().Name}}
 if(($report.failure -or $report.cleanupFailure) -and ($report.cancellationAttempted -or $report.latchRecoveryAttempted -or $report.resumeRecoveryAttempted -or $report.networkInterruptionAttempted -or $report.transportRecoveryAttempted)){
  try{Stop-PaytmFailedManagedHost $manifest.installationId;$report.failureStopVerified=$true}catch{$report.cleanupFailure='CANCEL_FAILURE_STOP_REVIEW_REQUIRED'}
 }
 if($lease){$lease.Dispose()}
 if(-not $report.failure -and -not $report.cleanupFailure -and $report.cancellationPassed -and $report.recoveryPassed -and $report.noAutomaticRearmPassed -and $report.accountPreserved -and $report.finalApplicationLockVerified){$report.status='GATEWAY_CANCELLATION_AND_APPLICATION_RECOVERY_PASSED';$report.stage='COMPLETE'}
 if(-not $report.failure -and -not $report.cleanupFailure -and $report.networkCleanupRehearsalPassed -and $report.networkLossObserved -and $report.networkRecoveryPassed -and $report.noAutomaticRearmPassed -and $report.accountPreserved -and $report.finalApplicationLockVerified){$report.status='GATEWAY_NETWORK_INTERRUPTION_AND_RECOVERY_PASSED';$report.stage='COMPLETE'}
 Save-Report;Write-Progress -Activity 'Gateway cancellation and recovery' -Completed;Write-Progress -Activity 'Managed Windows transport' -Completed
 if($NetworkInterruption){Write-Progress -Activity 'Gateway network recovery' -Completed}
 Write-Host "[100%] $($report.status); elapsed=$($report.elapsedSeconds)s"
 Write-Host "Share this ONE file: $path"
}
if($report.status -ceq 'REVIEW_REQUIRED'){throw 'Cancellation needs review. Share the JSON; do not rerun installation, enable a disabled task or clear STOP.'}
