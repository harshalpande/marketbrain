#Requires -Version 7.0
[CmdletBinding()]param(
 [ValidateSet('Before','After')][string]$Phase='Before',
 [switch]$ConfirmNoManualGatewayStart,
 [string]$TransportReportPath='C:\MarketBrainData\Review\paytm-managed-transport-20261103-171133-8ac7cdda3ca7475eb001df485797cb70.json')
$ErrorActionPreference='Stop'
$collectorStartedUtc=[DateTime]::UtcNow.ToString('o')
foreach($name in @('PaytmGatewayAccount.ps1','PaytmGatewayKeyCustody.ps1','PaytmGatewayScheduledProbe.ps1','PaytmSupervisorHost.ps1','PaytmSupervisorInstallation.ps1','PaytmSupervisorTransport.ps1','PaytmApplicationRoute.ps1','PaytmManagedTransport.ps1','PaytmGatewayRestart.ps1')){. (Join-Path $PSScriptRoot $name)}
$c=Get-PaytmHostContract;$checkpointPath=Join-Path $c.root 'restart-checkpoint.json';$lease=$null;$state=$null
$clock=[Diagnostics.Stopwatch]::StartNew();$route=@{Root=(Resolve-Path (Join-Path $PSScriptRoot '../..')).Path};$application=@{Ready=$false;Token=$null}
$output='C:\MarketBrainData\Review';$null=Assert-PaytmAccountPath $output;$null=New-Item -ItemType Directory -Path $output -Force
$report=[ordered]@{version=1;runId=[guid]::NewGuid().ToString('N');phase=$Phase;stage='PREFLIGHT';status='REVIEW_REQUIRED';failure=$null;failureDetails=$null;cleanupFailure=$null;elapsedSeconds=0;
 sourceHashes=@{};applicationCommands=[Collections.Generic.List[object]]::new();applicationObservations=[Collections.Generic.List[object]]::new();applicationRouteChecks=[Collections.Generic.List[object]]::new();
 accountPreserved=$false;finalApplicationLockVerified=$false;ownerConfirmsNoManualGatewayStart=[bool]$ConfirmNoManualGatewayStart;
 taskStartedByCollector=$false;configurationChanged=$false;rebootRequestedByCollector=$false;credentialsUsed=$false;ordersEnabled=$false}
$path=Join-Path $output ('paytm-gateway-restart-'+$report.runId+'.json')
function Save-Report {$report.elapsedSeconds=[math]::Round($clock.Elapsed.TotalSeconds,3);Write-PaytmHostJson $path $report}
function Restart-Step($Stage,$Percent){$report.stage=$Stage;Save-Report;Write-Host "[$Percent%] $Stage";Write-Progress -Activity 'Gateway Windows restart verification' -Status $Stage -PercentComplete $Percent}
try{
 Assert-PaytmCustodyController;Import-Module ScheduledTasks
 $null=Assert-PaytmAccountPath $c.root;Assert-PaytmAccountAcl (Get-Acl -LiteralPath $c.root) (Get-PaytmKeyContract).accountSid
 $lease=[IO.File]::Open((Assert-PaytmAccountPath (Join-Path (Get-PaytmAccountContract).root 'supervisor-install.lock')),'OpenOrCreate','ReadWrite','None')
 $null=Assert-PaytmAccountPath $checkpointPath
 if($Phase -ceq 'After'){
  $state=Read-PaytmHostJson $checkpointPath;Assert-PaytmRestartCheckpoint $state
  $report.runId=$state.runId;$path=Join-Path $output $state.reportName;$report.before=$state.before
  if(-not $ConfirmNoManualGatewayStart){throw 'STARTUP_OWNER_CONFIRMATION_REQUIRED'}
 }elseif(Test-Path -LiteralPath $checkpointPath){throw 'STARTUP_CHECKPOINT_EXISTS_USE_AFTER'}
 foreach($name in @('TestPaytmGatewayRestart.ps1','PaytmGatewayRestart.ps1','PaytmManagedTransport.ps1','PaytmApplicationRoute.ps1','PaytmSupervisorInstallation.ps1')){$report.sourceHashes[$name]=(Get-FileHash -LiteralPath (Join-Path $PSScriptRoot $name)).Hash}
 $null=Assert-PaytmAccountPath $TransportReportPath
 if((Get-FileHash -LiteralPath $TransportReportPath).Hash -cne '078A34DB0A46951EB98C5A08063F9FC76DB6EC75C175A3572CEE3D65DA4FAB4B'){throw 'STARTUP_ACCEPTED_RECEIPT_HASH'}
 $receipt=Read-PaytmHostJson $TransportReportPath 65536;Assert-PaytmTransportAcceptance $receipt
 Restart-Step 'VERIFY_INSTALLED_TRANSPORT' 15
 $manifest=Assert-PaytmInstalledTransport $receipt
 if($Phase -ceq 'After'){foreach($name in @('runner.ps1','host.ps1','native.dll','gateway.ps1','transport.ps1','transport.dll')){if($manifest.hashes.$name -cne $state.manifestHashes.$name){throw 'STARTUP_INSTALLATION_CHANGED'}}}
 Restart-Step 'OBSERVE_EXISTING_BACKGROUND_WORKER' 35
 $snapshot=Get-PaytmRestartObservation $manifest.installationId;$report.observation=$snapshot
 if($Phase -ceq 'After'){Assert-PaytmRestartBoundary $state.before $snapshot;$report.windowsRestartObserved=$true}
 Restart-Step 'VERIFY_APPLICATION_LOCK_AND_ACCOUNT' 65
 Initialize-PaytmManagedApplication
 if($Phase -ceq 'After'){
  if($application.BeforeAccount -cne $state.account -or $application.Id -cne $state.containerId -or $application.Before.Image -cne $state.imageId){throw 'STARTUP_APPLICATION_OR_ACCOUNT_CHANGED'}
  if($application.BootId -ceq $state.applicationBootId){throw 'STARTUP_APPLICATION_RESTART_NOT_OBSERVED'}
  Invoke-PaytmApplicationHead 'Application route after Windows restart' $true
 }
 Restart-Step 'FINAL_LOCK_CHECK' 90
}catch{
 $report.failure=if($_.Exception.Message -cmatch '^(STARTUP|HOST|TRANSPORT|APP_ROUTE|DEPLOY|ACCOUNT|KEY)_[A-Z_]+$'){$_.Exception.Message}else{'STARTUP_VERIFICATION_FAILED'}
 $report.failureDetails=@{type=$_.Exception.GetBaseException().GetType().Name;line=$_.InvocationInfo.ScriptLineNumber;script=[IO.Path]::GetFileName($_.InvocationInfo.ScriptName)}
}finally{
 try{
  if($application.Ready){
   $locked=Invoke-PaytmApplicationHttp 'lock'
   if($locked.state -cne 'LOCKED' -or $locked.bootId -cne $application.BootId){throw 'APP_ROUTE_FINAL_LOCK_FAILED'}
   Assert-PaytmWriterLocked;$report.finalApplicationLockVerified=$true
   $current=Get-PaytmApplicationContainer
   if($current.Id -cne $application.Id -or $current.Image -cne $application.Before.Image -or $current.State.StartedAt -cne $application.Before.State.StartedAt){throw 'APP_ROUTE_UNEXPECTED_RESTART'}
   if((Read-PaytmPaperAccount) -cne $application.BeforeAccount){throw 'APP_ROUTE_ACCOUNT_CHANGED'}
   $report.accountPreserved=$true
  }
  if(-not $report.failure -and $report.accountPreserved -and $report.finalApplicationLockVerified){
   if($Phase -ceq 'Before'){
    $state=@{version=1;runId=$report.runId;completed=$false;receiptHash='078A34DB0A46951EB98C5A08063F9FC76DB6EC75C175A3572CEE3D65DA4FAB4B';reportName=[IO.Path]::GetFileName($path);
     before=$snapshot;manifestHashes=$manifest.hashes;account=$application.BeforeAccount;containerId=$application.Id;imageId=$application.Before.Image;applicationBootId=$application.BootId}
    Write-PaytmHostJson $checkpointPath $state;$report.status='BASELINE_SAVED_AWAITING_WINDOWS_RESTART'
   }else{
    $state|Add-Member -NotePropertyName after -NotePropertyValue $snapshot
    $state|Add-Member -NotePropertyName applicationAfterBootId -NotePropertyValue $application.BootId
    $state.completed=$true;Write-PaytmHostJson $checkpointPath $state;$report.status='WINDOWS_RESTART_TRANSPORT_AND_APPLICATION_ROUTE_PASSED'
   }
   $report.stage='COMPLETE'
  }
 }catch{$report.cleanupFailure='STARTUP_FINAL_CHECK_OR_CHECKPOINT_FAILED';$report.status='REVIEW_REQUIRED'}
 $application.Token=$null
 if($report.failure){
  foreach($name in @('status.json','startup-failure.json')){try{$report[$name]=Read-PaytmHostJson (Join-Path $c.work $name)}catch{}}
 }
 if($lease){$lease.Dispose()}
 Save-Report;Write-Progress -Activity 'Gateway Windows restart verification' -Completed;Write-Progress -Activity 'Managed Windows transport' -Completed
 Write-Host "[100%] $($report.status); elapsed=$($report.elapsedSeconds)s"
 Write-Host "Share this ONE file after the After phase: $path"
}
if($report.status -ceq 'REVIEW_REQUIRED'){throw 'Restart verification needs review. Share the JSON. Do not reinstall or manually start the gateway task.'}
