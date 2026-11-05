#Requires -Version 7.0
[CmdletBinding()]param(
 [ValidateSet('Before','AfterLogoff','AfterBoot')][string]$Phase='Before',
 [switch]$ConfirmSignedOut,
 [switch]$ConfirmFullShutdown,
 [switch]$ConfirmNoManualGatewayStart,
 [string]$NetworkReportPath='C:\MarketBrainData\Review\paytm-gateway-network-9d10806aee964df4951c3eb79be931f9.json',
 [string]$TransportReportPath='C:\MarketBrainData\Review\paytm-managed-transport-20261103-171133-8ac7cdda3ca7475eb001df485797cb70.json',
 [string]$OutputDirectory='C:\MarketBrainData\Review')
$ErrorActionPreference='Stop'
$collectorStartedUtc=[DateTime]::UtcNow.ToString('o')
foreach($name in @('PaytmGatewayAccount.ps1','PaytmGatewayKeyCustody.ps1','PaytmGatewayScheduledProbe.ps1','PaytmSupervisorHost.ps1','PaytmSupervisorInstallation.ps1','PaytmSupervisorTransport.ps1','PaytmApplicationRoute.ps1','PaytmManagedTransport.ps1','PaytmGatewayRestart.ps1','PaytmGatewaySession.ps1')){. (Join-Path $PSScriptRoot $name)}
$c=Get-PaytmHostContract;$lease=$null;$state=$null;$snapshot=$null;$completedReceipt=$false
$checkpointPath=Join-Path $c.root 'session-checkpoint.json'
$route=@{Root=(Resolve-Path (Join-Path $PSScriptRoot '../..')).Path};$application=@{Ready=$false;Token=$null}
$script:sessionWatch=[Diagnostics.Stopwatch]::StartNew()
$report=[ordered]@{version=1;runId=[guid]::NewGuid().ToString('N');phase=$Phase;stage='PREFLIGHT';status='REVIEW_REQUIRED';failure=$null;failureDetails=$null;cleanupFailure=$null;elapsedSeconds=0;
 sourceHashes=@{};applicationCommands=[Collections.Generic.List[object]]::new();applicationObservations=[Collections.Generic.List[object]]::new();applicationRouteChecks=[Collections.Generic.List[object]]::new();
 accountPreserved=$false;finalApplicationLockVerified=$false;ownerConfirmsSignedOut=[bool]$ConfirmSignedOut;ownerConfirmsFullShutdown=[bool]$ConfirmFullShutdown;ownerConfirmsNoManualGatewayStart=[bool]$ConfirmNoManualGatewayStart;
 taskStartedByCollector=$false;configurationChanged=$false;powerActionByCollector=$false;credentialsUsed=$false;ordersEnabled=$false;abruptPowerLossTested=$false}
$null=Assert-PaytmAccountPath $OutputDirectory;$null=New-Item -ItemType Directory -Path $OutputDirectory -Force
$script:sessionReportPath=Join-Path $OutputDirectory ('paytm-gateway-session-'+$report.runId+'.json')
function Save-SessionReport {
 $script:report.elapsedSeconds=[math]::Round($script:sessionWatch.Elapsed.TotalSeconds,3)
 Write-PaytmHostJson $script:sessionReportPath $script:report
}
function Session-Step($Stage,$Percent){$report.stage=$Stage;Save-SessionReport;Write-Host "[$Percent%] $Stage";Write-Progress -Activity 'Gateway logoff and full shutdown verification' -Status $Stage -PercentComplete $Percent}
try{
 Assert-PaytmCustodyController;Import-Module ScheduledTasks
 $null=Assert-PaytmAccountPath $c.root;Assert-PaytmAccountAcl (Get-Acl -LiteralPath $c.root) (Get-PaytmKeyContract).accountSid
 $lease=[IO.File]::Open((Assert-PaytmAccountPath (Join-Path (Get-PaytmAccountContract).root 'supervisor-install.lock')),'OpenOrCreate','ReadWrite','None')
 $null=Assert-PaytmAccountPath $checkpointPath
 if(Test-Path -LiteralPath $checkpointPath){
  $state=Read-PaytmHostJson $checkpointPath;Assert-PaytmSessionCheckpoint $state
  if($state.nextPhase -ceq 'Complete'){
   $completedReceipt=$true;$report.status='ALREADY_COMPLETED';$script:sessionReportPath=Join-Path $OutputDirectory $state.reportName
   return
  }
  $report.runId=$state.runId;$script:sessionReportPath=Join-Path $OutputDirectory $state.reportName
  $report.baseline=$state.before;$report.savedNextPhase=$state.nextPhase
  if($state.nextPhase -cne 'AfterLogoff'){$report.afterLogoff=$state.afterLogoff}
  if($Phase -ceq 'Before' -or $Phase -cne $state.nextPhase){throw 'SESSION_USE_SAVED_NEXT_PHASE'}
 }elseif($Phase -cne 'Before'){throw 'SESSION_BASELINE_REQUIRED'}
 if($Phase -cne 'Before' -and -not $ConfirmNoManualGatewayStart){throw 'SESSION_NO_MANUAL_START_CONFIRMATION_REQUIRED'}
 if($Phase -ceq 'AfterLogoff' -and -not $ConfirmSignedOut){throw 'SESSION_SIGNOUT_CONFIRMATION_REQUIRED'}
 if($Phase -ceq 'AfterBoot' -and -not $ConfirmFullShutdown){throw 'SESSION_FULL_SHUTDOWN_CONFIRMATION_REQUIRED'}
 foreach($name in @('TestPaytmGatewaySession.ps1','ReadPaytmInteractiveSession.ps1','PaytmGatewaySession.ps1','PaytmGatewayRestart.ps1','PaytmManagedTransport.ps1','PaytmApplicationRoute.ps1','PaytmSupervisorInstallation.ps1')){$report.sourceHashes[$name]=(Get-FileHash -LiteralPath (Join-Path $PSScriptRoot $name)).Hash}
 if($state){foreach($name in $report.sourceHashes.Keys){if($report.sourceHashes[$name] -cne $state.sourceHashes.$name){throw 'SESSION_COLLECTOR_CHANGED_BETWEEN_PHASES'}}}
 foreach($pair in @(@($NetworkReportPath,'860F63E79D86A6460EA87C2C492B84FEA342FD919E85019E6C26D2B8CA5C3773'),@($TransportReportPath,'078A34DB0A46951EB98C5A08063F9FC76DB6EC75C175A3572CEE3D65DA4FAB4B'))){
  $null=Assert-PaytmAccountPath $pair[0];if((Get-FileHash -LiteralPath $pair[0]).Hash -cne $pair[1]){throw 'SESSION_ACCEPTED_RECEIPT_HASH'}
 }
 $receipt=Read-PaytmHostJson $TransportReportPath 65536;Assert-PaytmTransportAcceptance $receipt
 Session-Step 'VERIFY_EXISTING_INSTALLATION' 15
 $manifest=Assert-PaytmInstalledTransport $receipt
 if($state){foreach($name in @('runner.ps1','host.ps1','native.dll','gateway.ps1','transport.ps1','transport.dll')){if($manifest.hashes.$name -cne $state.manifestHashes.$name){throw 'SESSION_INSTALLATION_CHANGED'}}}
 Session-Step 'OBSERVE_BACKGROUND_WORKER_AND_WINDOWS_SESSION' 35
 $snapshot=Get-PaytmRestartObservation $manifest.installationId
 $snapshot|Add-Member -NotePropertyName interactive -NotePropertyValue (Get-PaytmInteractiveSession)
 $report.observation=$snapshot
 if($Phase -ceq 'AfterLogoff'){Assert-PaytmSessionBoundary $state.before $snapshot;$report.logoffSurvivalObserved=$true}
 if($Phase -ceq 'AfterBoot'){
  Assert-PaytmSessionBootBoundary $state.afterLogoff $snapshot
  if($snapshot.interactive.userSidHash -cne $state.before.interactive.userSidHash){throw 'SESSION_DIFFERENT_USER'}
  $report.newWindowsBootObserved=$true
 }
 Session-Step 'VERIFY_LOCKED_APPLICATION_AND_UNCHANGED_ACCOUNT' 65
 Initialize-PaytmManagedApplication
 if($state){
  if($application.BeforeAccount -cne $state.account -or $application.Id -cne $state.containerId -or $application.Before.Image -cne $state.imageId){throw 'SESSION_APPLICATION_OR_ACCOUNT_CHANGED'}
  if($Phase -ceq 'AfterBoot' -and $application.BootId -ceq $state.afterLogoffApplicationBootId){throw 'SESSION_APPLICATION_RESTART_NOT_OBSERVED'}
 }
 Invoke-PaytmApplicationHead ('Explicit diagnostic route '+$Phase) $true
 Session-Step 'FINAL_LOCK_AND_SAVE_NEXT_PHASE' 90
}catch{
 $report.failure=if($_.Exception.Message -cmatch '^(SESSION|STARTUP|HOST|TRANSPORT|APP_ROUTE|DEPLOY|ACCOUNT|KEY)_[A-Z_]+$'){$_.Exception.Message}else{'SESSION_VERIFICATION_FAILED'}
 $report.failureDetails=@{type=$_.Exception.GetBaseException().GetType().Name;line=$_.InvocationInfo.ScriptLineNumber;script=[IO.Path]::GetFileName($_.InvocationInfo.ScriptName)}
}finally{
 try{
  if($application.Ready){
   $v=Invoke-PaytmApplicationHttp 'lock';if($v.state -cne 'LOCKED' -or $v.bootId -cne $application.BootId){throw 'APP_ROUTE_FINAL_LOCK_FAILED'}
   Assert-PaytmWriterLocked;$report.finalApplicationLockVerified=$true
   $current=Get-PaytmApplicationContainer
   if($current.Id -cne $application.Id -or $current.Image -cne $application.Before.Image -or $current.State.StartedAt -cne $application.Before.State.StartedAt -or (Read-PaytmPaperAccount) -cne $application.BeforeAccount){throw 'APP_ROUTE_APPLICATION_OR_ACCOUNT_CHANGED'}
   $report.accountPreserved=$true
  }
  if(-not $report.failure -and $report.accountPreserved -and $report.finalApplicationLockVerified){
   $phaseProof=@{accountPreserved=$true;finalApplicationLockVerified=$true;routeChecks=@($report.applicationRouteChecks.ToArray());applicationBootId=$application.BootId;elapsedSeconds=[math]::Round($script:sessionWatch.Elapsed.TotalSeconds,3);ownerConfirmsSignedOut=[bool]$ConfirmSignedOut;ownerConfirmsFullShutdown=[bool]$ConfirmFullShutdown;ownerConfirmsNoManualGatewayStart=[bool]$ConfirmNoManualGatewayStart}
   if($Phase -ceq 'Before'){
    $state=[pscustomobject]@{version=1;runId=$report.runId;nextPhase='AfterLogoff';reportName=[IO.Path]::GetFileName($script:sessionReportPath);sourceHashes=$report.sourceHashes;
     before=$snapshot;manifestHashes=$manifest.hashes;account=$application.BeforeAccount;containerId=$application.Id;imageId=$application.Before.Image;phaseProofs=@{Before=$phaseProof}}
    $report.status='BASELINE_SAVED_AWAITING_SIGNOUT'
   }elseif($Phase -ceq 'AfterLogoff'){
    $state|Add-Member afterLogoff $snapshot -Force;$state|Add-Member afterLogoffApplicationBootId $application.BootId -Force
    $state.phaseProofs|Add-Member AfterLogoff $phaseProof -Force
    $state.nextPhase='AfterBoot';$report.status='LOGOFF_PASSED_AWAITING_FULL_SHUTDOWN'
   }else{
    $state|Add-Member afterBoot $snapshot -Force;$state.phaseProofs|Add-Member AfterBoot $phaseProof -Force
    $state.nextPhase='Complete';$report.status='GATEWAY_LOGOFF_AND_FULL_BOOT_PASSED'
   }
   Write-PaytmHostJson $checkpointPath $state
   $report.phaseProofs=$state.phaseProofs;$report.nextPhase=$state.nextPhase;$report.stage='COMPLETE'
  }
 }catch{$report.cleanupFailure='SESSION_FINAL_CHECK_OR_CHECKPOINT_FAILED';$report.status='REVIEW_REQUIRED'}
 $application.Token=$null
 if($lease){$lease.Dispose()}
 if(-not $completedReceipt){Save-SessionReport}
 Write-Progress -Activity 'Gateway logoff and full shutdown verification' -Completed;Write-Progress -Activity 'Managed Windows transport' -Completed
 Write-Host "[100%] $($report.status); phase elapsed=$($report.elapsedSeconds)s"
 Write-Host "Share this ONE file after AfterBoot (or on failure): $script:sessionReportPath"
}
if($report.status -ceq 'REVIEW_REQUIRED'){throw 'Session verification needs review. Share the JSON; preserve the checkpoint and retry only its saved next phase. Do not reinstall or manually start the gateway.'}
