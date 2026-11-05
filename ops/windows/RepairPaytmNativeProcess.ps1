#Requires -Version 7.0
[CmdletBinding()]param(
 [string]$DiagnosticReportPath='C:\MarketBrainData\Review\paytm-native-failure-1290fc4e5fc448ac98c749ff437f4a8d.json',
 [string]$TransportReportPath='C:\MarketBrainData\Review\paytm-managed-transport-20261103-171133-8ac7cdda3ca7475eb001df485797cb70.json',
 [string]$OutputDirectory='C:\MarketBrainData\Review')
$ErrorActionPreference='Stop'
foreach($n in @('PaytmGatewayAccount.ps1','PaytmGatewayKeyCustody.ps1','PaytmGatewayScheduledProbe.ps1','PaytmSupervisorHost.ps1','PaytmSupervisorInstallation.ps1','PaytmSupervisorTransport.ps1','PaytmApplicationRoute.ps1','PaytmManagedTransport.ps1','PaytmGatewayRestart.ps1','PaytmGatewaySession.ps1','PaytmGatewayFailureEvidence.ps1','PaytmNativeRecovery.ps1')){. (Join-Path $PSScriptRoot $n)}
$c=Get-PaytmHostContract;$lease=$null;$manifest=$null;$finished=$false
$route=@{Root=(Resolve-Path (Join-Path $PSScriptRoot '../..')).Path};$application=@{Ready=$false;Token=$null}
$script:nativeRecoveryWatch=[Diagnostics.Stopwatch]::StartNew()
$report=[ordered]@{version=1;runId=[guid]::NewGuid().ToString('N');status='REVIEW_REQUIRED';stage='PREFLIGHT';failure=$null;cleanupFailure=$null;elapsedSeconds=0;sourceHashes=@{};
 nativeRecoveryAttempted=$false;failureStopVerified=$false;soakPassed=$false;accountPreserved=$false;finalApplicationLockVerified=$false;brokerCredentialsUsed=$false;ordersEnabled=$false;originalRootCauseProven=$false;
 applicationCommands=[Collections.Generic.List[object]]::new();applicationObservations=[Collections.Generic.List[object]]::new();applicationRouteChecks=[Collections.Generic.List[object]]::new()}
$null=Assert-PaytmAccountPath $OutputDirectory;$null=New-Item -ItemType Directory -Path $OutputDirectory -Force
$script:nativeRecoveryReportPath=Join-Path $OutputDirectory ('paytm-native-recovery-'+$report.runId+'.json')
function Save-NativeRecoveryReport {
 $script:report.elapsedSeconds=[math]::Round($script:nativeRecoveryWatch.Elapsed.TotalSeconds,3)
 Write-PaytmSessionReport $script:nativeRecoveryReportPath $script:report
}
# Existing application-route helpers checkpoint through this name.
function Save-Report {Save-NativeRecoveryReport}
function Native-Step($Stage,$Percent){$report.stage=$Stage;Save-NativeRecoveryReport;Write-Host "[$Percent%] $Stage";Write-Progress -Activity 'Gateway native recovery and 30-minute observation' -Status $Stage -PercentComplete $Percent}
try{
 Assert-PaytmCustodyController;Import-Module ScheduledTasks
 $null=Assert-PaytmAccountPath $c.root;Assert-PaytmAccountAcl (Get-Acl -LiteralPath $c.root) (Get-PaytmKeyContract).accountSid
 $lease=[IO.File]::Open((Assert-PaytmAccountPath (Join-Path (Get-PaytmAccountContract).root 'supervisor-install.lock')),'OpenOrCreate','ReadWrite','None')
 foreach($n in @('RepairPaytmNativeProcess.ps1','PaytmNativeRecovery.ps1','PaytmSupervisorNative.cs','RunPaytmGatewaySupervisor.ps1','PaytmGatewayRestart.ps1','PaytmGatewayFailureEvidence.ps1')){$report.sourceHashes[$n]=(Get-FileHash -LiteralPath (Join-Path $PSScriptRoot $n)).Hash}
 $null=Assert-PaytmNativeReceipt $DiagnosticReportPath
 $null=Assert-PaytmAccountPath $TransportReportPath
 if((Get-FileHash -LiteralPath $TransportReportPath).Hash -cne '078A34DB0A46951EB98C5A08063F9FC76DB6EC75C175A3572CEE3D65DA4FAB4B'){throw 'HOST_NATIVE_TRANSPORT_RECEIPT_MISMATCH'}
 $receipt=Read-PaytmHostJson $TransportReportPath 65536;Assert-PaytmTransportAcceptance $receipt
 Native-Step 'VERIFY_INSTALLATION_AND_LOCKED_APPLICATION' 10
 $manifest=Assert-PaytmTransportInstallationSources $receipt
 Initialize-PaytmManagedApplication
 Native-Step 'ARCHIVE_FAILURE_BUILD_PATCH_AND_START_ONCE' 20
 Invoke-PaytmNativeRecovery $receipt $DiagnosticReportPath $PSScriptRoot
 Invoke-PaytmApplicationHead 'Native recovery initial diagnostic route' $true
 Native-Step 'OBSERVE_SAME_WORKER_FOR_30_MINUTES' 30
 $previous=Wait-PaytmManagedHost $manifest.installationId TRANSPORT_READY -TimeoutSeconds 20
 if($previous.instanceId -cne $report.nativeRecovery.first.instanceId){throw 'HOST_NATIVE_WORKER_REPLACED'}
 $soak=[Diagnostics.Stopwatch]::StartNew()
 $report.soak=[ordered]@{requiredSeconds=1800;elapsedSeconds=0;observations=0;first=$previous;last=$null;healthSamples=[Collections.Generic.List[object]]::new()}
 $nextSample=0
 do{
  $current=Wait-PaytmManagedHost $manifest.installationId TRANSPORT_READY -TimeoutSeconds 20
  Assert-PaytmNativeSoakSample $previous $current
  $report.soak.observations++;$report.soak.elapsedSeconds=[math]::Round($soak.Elapsed.TotalSeconds,3);$report.soak.last=$current
  if($soak.Elapsed.TotalSeconds -ge $nextSample){
   $report.soak.healthSamples.Add(@{seconds=$report.soak.elapsedSeconds;sequence=$current.sequence;workerSeconds=$current.elapsedSeconds;healthSeconds=$current.transportState.lastHealthSeconds;httpStatus=$current.httpStatus})
   $nextSample=$soak.Elapsed.TotalSeconds+30
   Native-Step ('OBSERVING {0:n0}/1800 seconds; heartbeat {1}' -f $soak.Elapsed.TotalSeconds,$current.sequence) ([math]::Min(90,30+[int]($soak.Elapsed.TotalSeconds/30)))
  }
  $previous=$current
  if($soak.Elapsed.TotalSeconds -lt 1800){Start-Sleep -Seconds 10}
 }while($soak.Elapsed.TotalSeconds -lt 1800)
 # Last proof must follow the full interval, never a sleep crossing its end.
 $current=Wait-PaytmManagedHost $manifest.installationId TRANSPORT_READY -TimeoutSeconds 20
 Assert-PaytmNativeSoakSample $previous $current
 $report.soak.last=$current;$report.soak.elapsedSeconds=[math]::Round($soak.Elapsed.TotalSeconds,3);$report.soak.observations++
 if($current.elapsedSeconds-$report.soak.first.elapsedSeconds -lt 1800){throw 'HOST_NATIVE_OBSERVATION_TOO_SHORT'}
 $report.soakPassed=$true
 Invoke-PaytmApplicationHead 'Native recovery final diagnostic route' $true
 Native-Step 'VERIFY_FINAL_LOCK_AND_ACCOUNT' 95
 $finished=$true
}catch{
 $report.failure=if($_.Exception.Message -cmatch '^(HOST|TRANSPORT|STARTUP|APP_ROUTE|KEY|ACCOUNT)_[A-Z_]+$'){$_.Exception.Message}else{'HOST_NATIVE_RECOVERY_FAILED'}
 $report.failureDetails=@{type=$_.Exception.GetBaseException().GetType().Name;script=[IO.Path]::GetFileName($_.InvocationInfo.ScriptName);line=$_.InvocationInfo.ScriptLineNumber}
}finally{
 if(-not $finished -and -not $report.failure){$report.failure='HOST_NATIVE_COLLECTION_INTERRUPTED'}
 try{
  if($application.Ready){
   $v=Invoke-PaytmApplicationHttp 'lock';if($v.state -cne 'LOCKED' -or $v.bootId -cne $application.BootId){throw 'APP_ROUTE_FINAL_LOCK_FAILED'}
   Assert-PaytmWriterLocked;$report.finalApplicationLockVerified=$true
   $current=Get-PaytmApplicationContainer
   if($current.Id -cne $application.Id -or $current.Image -cne $application.Before.Image -or $current.State.StartedAt -cne $application.Before.State.StartedAt -or (Read-PaytmPaperAccount) -cne $application.BeforeAccount){throw 'APP_ROUTE_APPLICATION_OR_ACCOUNT_CHANGED'}
   $report.accountPreserved=$true
  }
 }catch{$report.cleanupFailure='HOST_NATIVE_FINAL_LOCK_OR_ACCOUNT_FAILED'}
 $application.Token=$null
 if($report.failure -or $report.cleanupFailure){
  try{$report.workerDiagnostics=Get-PaytmWorkerFailureEvidence}catch{$report.diagnosticError=$_.Exception.GetBaseException().GetType().Name}
  if($report.nativeRecoveryAttempted){try{Stop-PaytmFailedManagedHost $manifest.installationId;$report.failureStopVerified=$true}catch{$report.cleanupFailure='HOST_NATIVE_FAILURE_STOP_REVIEW_REQUIRED'}}
 }
 if($lease){$lease.Dispose()}
 if($finished -and -not $report.failure -and -not $report.cleanupFailure -and $report.soakPassed -and $report.accountPreserved -and $report.finalApplicationLockVerified){$report.status='NATIVE_RECOVERY_AND_30_MINUTE_OBSERVATION_PASSED';$report.stage='COMPLETE'}
 Save-NativeRecoveryReport
 Write-Progress -Activity 'Gateway native recovery and 30-minute observation' -Completed
 Write-Progress -Activity 'Managed Windows transport' -Completed
 Write-Host "[100%] $($report.status); elapsed=$($report.elapsedSeconds)s"
 Write-Host "Share this ONE file: $script:nativeRecoveryReportPath"
}
if($report.status -ceq 'REVIEW_REQUIRED'){throw 'Native recovery needs review. Share the JSON; do not rerun or clear failure markers.'}
