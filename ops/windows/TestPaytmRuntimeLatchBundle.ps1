#Requires -Version 7.0
[CmdletBinding()]param(
 [string]$OutputDirectory='C:\MarketBrainData\Review',
 [string]$TransportReportPath='C:\MarketBrainData\Review\paytm-managed-transport-20261103-171133-8ac7cdda3ca7475eb001df485797cb70.json')
$ErrorActionPreference='Stop'
foreach($n in @('PaytmGatewayAccount.ps1','PaytmGatewayKeyCustody.ps1','PaytmGatewayScheduledProbe.ps1','PaytmSupervisorHost.ps1','PaytmSupervisorInstallation.ps1','PaytmSupervisorTransport.ps1','PaytmApplicationRoute.ps1','PaytmManagedTransport.ps1','PaytmGatewayRestart.ps1','PaytmGatewaySession.ps1','PaytmRuntimeLatch.ps1')){. (Join-Path $PSScriptRoot $n)}
$watch=[Diagnostics.Stopwatch]::StartNew();$lease=$null;$manifest=$null
$route=@{Root=(Resolve-Path (Join-Path $PSScriptRoot '../..')).Path};$application=@{Ready=$false;Token=$null}
$report=[ordered]@{version=1;runId=[guid]::NewGuid().ToString('N');status='REVIEW_REQUIRED';failure=$null;cleanupFailure=$null;sourceHashes=@{};elapsedSeconds=0;mutationAttempted=$false;runtimeLatchPassed=$false;latchPersistencePassed=$false;applicationNoFallbackPassed=$false;recoveryStartAttempts=0;accountPreserved=$false;finalApplicationLockVerified=$false;failureStopVerified=$false;credentialsUsed=$false;ordersEnabled=$false;applicationCommands=[Collections.Generic.List[object]]::new();applicationObservations=[Collections.Generic.List[object]]::new();applicationRouteChecks=[Collections.Generic.List[object]]::new()}
$null=Assert-PaytmAccountPath $OutputDirectory;$null=New-Item -ItemType Directory -Path $OutputDirectory -Force
$reportPath=Join-Path $OutputDirectory ('paytm-runtime-latch-'+$report.runId+'.json')
function Save-Report {$report.elapsedSeconds=[math]::Round($watch.Elapsed.TotalSeconds,3);Write-PaytmSessionReport $reportPath $report}
try{
 Save-Report;Assert-PaytmCustodyController;Import-Module ScheduledTasks
 foreach($n in @('TestPaytmRuntimeLatchBundle.ps1','PaytmRuntimeLatch.ps1','PaytmGatewayRestart.ps1','PaytmManagedTransport.ps1','PaytmSupervisorTransport.ps1','PaytmApplicationRoute.ps1','PaytmSupervisorHost.ps1','PaytmSupervisorInstallation.ps1','PaytmGatewaySession.ps1')){$report.sourceHashes[$n]=(Get-FileHash -LiteralPath (Join-Path $PSScriptRoot $n)).Hash}
 $lease=[IO.File]::Open((Assert-PaytmAccountPath (Join-Path (Get-PaytmAccountContract).root 'supervisor-install.lock')),'OpenOrCreate','ReadWrite','None')
 $null=Assert-PaytmAccountPath $TransportReportPath
 if((Get-FileHash -LiteralPath $TransportReportPath).Hash -cne '078A34DB0A46951EB98C5A08063F9FC76DB6EC75C175A3572CEE3D65DA4FAB4B'){throw 'LATCH_RECEIPT_HASH'}
 $receipt=Read-PaytmHostJson $TransportReportPath 65536;Assert-PaytmTransportAcceptance $receipt
 Write-Host '[10%] Verify installed gateway and locked application/account'
 $manifest=Assert-PaytmInstalledTransport $receipt
 Initialize-PaytmManagedApplication
 Save-Report
 Invoke-PaytmRuntimeLatch $receipt $manifest {Save-Report}
}catch{$report.failure=$_.Exception.Message}
finally{
 try{
  if($application.Ready){
   $v=Invoke-PaytmApplicationHttp 'lock'
   if($v.state -cne 'LOCKED' -or $v.bootId -cne $application.BootId){throw 'LATCH_FINAL_APPLICATION_LOCK'}
   Assert-PaytmWriterLocked;$report.finalApplicationLockVerified=$true
   $current=Get-PaytmApplicationContainer
   if($current.Id -cne $application.Id -or $current.Image -cne $application.Before.Image -or $current.State.StartedAt -cne $application.Before.State.StartedAt -or (Read-PaytmPaperAccount) -cne $application.BeforeAccount){throw 'LATCH_APPLICATION_OR_ACCOUNT_CHANGED'}
   $report.accountPreserved=$true
  }
 }catch{$report.cleanupFailure=$_.Exception.Message}
 $application.Token=$null
 if(($report.failure -or $report.cleanupFailure) -and $report.mutationAttempted){
  try{Stop-PaytmFailedManagedHost $manifest.installationId;$report.failureStopVerified=$true}catch{$report.stopFailure=$_.Exception.Message}
 }
 if(-not $report.failure -and -not $report.cleanupFailure -and $report.runtimeLatchPassed -and $report.latchPersistencePassed -and $report.applicationNoFallbackPassed -and $report.accountPreserved -and $report.finalApplicationLockVerified -and $report.recoveryStartAttempts -eq 1){$report.status='RUNTIME_LISTENER_LATCH_AND_RECOVERY_PASSED_CLOCK_PENDING'}
 if($lease){$lease.Dispose()}
 Save-Report
 Write-Progress -Activity 'Managed Windows transport' -Completed
 Write-Host "[100%] $($report.status); elapsed=$($report.elapsedSeconds)s"
 Write-Host "Share this ONE file: $reportPath"
}
if($report.status -eq 'REVIEW_REQUIRED'){throw 'Share the JSON; do not clear markers or rerun recovery.'}
