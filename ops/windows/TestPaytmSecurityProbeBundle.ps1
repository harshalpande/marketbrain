#Requires -Version 7.0
[CmdletBinding()]param(
 [string]$OutputDirectory='C:\MarketBrainData\Review',
 [string]$TransportReportPath='C:\MarketBrainData\Review\paytm-managed-transport-20261103-171133-8ac7cdda3ca7475eb001df485797cb70.json')
$ErrorActionPreference='Stop'
foreach($name in @('PaytmGatewayAccount.ps1','PaytmGatewayKeyCustody.ps1','PaytmGatewayScheduledProbe.ps1','PaytmSupervisorHost.ps1','PaytmSupervisorInstallation.ps1','PaytmSupervisorTransport.ps1','PaytmApplicationRoute.ps1','PaytmManagedTransport.ps1','PaytmGatewayRestart.ps1','PaytmGatewaySession.ps1','PaytmSecurityProbes.ps1')){. (Join-Path $PSScriptRoot $name)}
$watch=[Diagnostics.Stopwatch]::StartNew();$lease=$null;$manifest=$null
$report=[ordered]@{version=1;runId=[guid]::NewGuid().ToString('N');status='REVIEW_REQUIRED';failure=$null;cleanupFailure=$null;elapsedSeconds=0;checks=@();sourceHashes=@{};credentialsUsed=$false;ordersEnabled=$false;gatewayChanged=$false;applicationAccessed=$false;checkpointCompleted=$false}
$null=Assert-PaytmAccountPath $OutputDirectory
$null=New-Item -ItemType Directory -Path $OutputDirectory -Force
$reportPath=Join-Path $OutputDirectory ('paytm-security-probes-'+$report.runId+'.json')
function Save-SecurityReport {
 $report.elapsedSeconds=[math]::Round($watch.Elapsed.TotalSeconds,3)
 Write-PaytmSessionReport $reportPath $report
}
try{
 Save-SecurityReport
 Assert-PaytmCustodyController
 Import-Module ScheduledTasks
 foreach($n in @('TestPaytmSecurityProbeBundle.ps1','PaytmSecurityProbes.ps1','PaytmGatewayRestart.ps1','PaytmManagedTransport.ps1','PaytmSupervisorTransport.ps1','PaytmSupervisorInstallation.ps1','PaytmSupervisorHost.ps1','PaytmGatewaySession.ps1','PaperRuntimeReview.ps1')){$report.sourceHashes[$n]=(Get-FileHash -LiteralPath (Join-Path $PSScriptRoot $n)).Hash}
 $lease=[IO.File]::Open((Assert-PaytmAccountPath (Join-Path (Get-PaytmAccountContract).root 'supervisor-install.lock')),'OpenOrCreate','ReadWrite','None')
 $null=Assert-PaytmAccountPath $TransportReportPath
 if((Get-FileHash -LiteralPath $TransportReportPath).Hash -cne '078A34DB0A46951EB98C5A08063F9FC76DB6EC75C175A3572CEE3D65DA4FAB4B'){throw 'SECURITY_ACCEPTED_RECEIPT_HASH'}
 $receipt=Read-PaytmHostJson $TransportReportPath 65536
 Assert-PaytmTransportAcceptance $receipt
 Write-Host '[10%] Verify installed gateway and advancing owned listener'
 $manifest=Assert-PaytmInstalledTransport $receipt
 $report.before=Wait-PaytmManagedHost $manifest.installationId TRANSPORT_READY -TimeoutSeconds 30
 Save-SecurityReport
 Invoke-PaytmSecurityProbeBatch -Run {
  param($Arguments)
  Invoke-PaperRuntimeProcess 'C:\Windows\System32\curl.exe' $Arguments $PSScriptRoot 12
 } -Record {param($Row) $report.checks+=,$Row;Save-SecurityReport}
 $report.status='SECURITY_PROBES_PASSED_SSH_AND_HEALTH_TESTS_PENDING'
}catch{$report.failure=$_.Exception.Message}
finally{
 if($manifest){
  try{
   Write-Host '[90%] Verify gateway installation and advancing worker remain intact'
   $null=Assert-PaytmInstalledTransport $receipt
   $report.after=Wait-PaytmManagedHost $manifest.installationId TRANSPORT_READY -TimeoutSeconds 30
   Assert-PaytmHostAdvance $report.before $report.after
   if($report.before.instanceId -cne $report.after.instanceId){throw 'SECURITY_WORKER_CHANGED'}
  }catch{$report.cleanupFailure=$_.Exception.Message;$report.status='REVIEW_REQUIRED'}
 }
 if($report.failure){$report.status='REVIEW_REQUIRED'}
 if($lease){$lease.Dispose()}
 Save-SecurityReport
 Write-Progress -Activity 'Gateway security rejection checks' -Completed
 Write-Host "[100%] $($report.status); elapsed=$($report.elapsedSeconds)s"
 Write-Host "Share this ONE file: $reportPath"
}
if($report.status -cne 'SECURITY_PROBES_PASSED_SSH_AND_HEALTH_TESTS_PENDING'){throw "Review report: $($report.failure) $($report.cleanupFailure)"}
