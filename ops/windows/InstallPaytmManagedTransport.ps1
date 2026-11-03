#Requires -Version 7.0
[CmdletBinding()]param(
 [string]$VpsEvidencePath='C:\MarketBrainData\Review\paytm-managed-report-recovery-20261102-234122-5efb864e0b4f48d2b0c6a4dc487cc519.json',
 [string]$CustodyReportPath='C:\MarketBrainData\Review\paytm-key-custody-20261102-112446-29cb6394513a47f687351825698006d5.json',
 [string]$OutputDirectory='C:\MarketBrainData\Review')
$ErrorActionPreference='Stop'
foreach($name in @('PaytmGatewayAccount.ps1','PaytmGatewayAccountRepair.ps1','PaytmGatewayKeyCustody.ps1','PaytmGatewayScheduledProbe.ps1','PaytmTunnelVerification.ps1','PaytmSupervisorHost.ps1','PaytmSupervisorInstallation.ps1','PaytmSupervisorTransport.ps1','PaytmManagedProxy.ps1','PaytmApplicationRoute.ps1','PaytmManagedTransport.ps1')){. (Join-Path $PSScriptRoot $name)}
$clock=[Diagnostics.Stopwatch]::StartNew();$c=Get-PaytmHostContract;$installation='ea8b91471cf048aa97a0f6b939b355c7';$lease=$null;$workerLease=$null;$mutated=$false
$report=[ordered]@{version=1;runId=[guid]::NewGuid().ToString('N');status='REVIEW_REQUIRED';stage='PREFLIGHT';failure=$null;failureDetails=$null;cleanupFailure=$null;elapsedSeconds=0;sourceHashes=@{};backup=$null;upgradeApplied=$false;
 duplicateStartPassed=$false;disabledRoutePassed=$false;childRecoveryPassed=$false;persistentStopPassed=$false;restartPassed=$false;finalApplicationLockVerified=$false;accountPreserved=$false;
 applicationCommands=[Collections.Generic.List[object]]::new();applicationObservations=[Collections.Generic.List[object]]::new();applicationRouteChecks=[Collections.Generic.List[object]]::new();
 ordersEnabled=$false;brokerCredentialsUsed=$false;vpsChanged=$false;taskReRegistered=$false;keyImported=$false;rebootTested=$false}
$route=@{Root=(Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path};$application=@{Ready=$false;Token=$null}
$null=Assert-PaytmAccountPath $OutputDirectory;$null=New-Item -ItemType Directory -Path $OutputDirectory -Force
$path=Join-Path $OutputDirectory ('paytm-managed-transport-'+(Get-Date -Format 'yyyyMMdd-HHmmss')+'-'+$report.runId+'.json')
function Save-Report {$report.elapsedSeconds=[math]::Round($clock.Elapsed.TotalSeconds,3);[IO.File]::WriteAllText($path,($report|ConvertTo-Json -Depth 14),[Text.UTF8Encoding]::new($false))}
function Transport-Step($Stage,$Percent){$report.stage=$Stage;Save-Report;Write-Host "[$Percent%] $Stage";Write-Progress -Activity 'Managed Windows transport' -Status $Stage -PercentComplete $Percent}
try{
 $f=[IO.File]::Open($path,'CreateNew','Write','Read');$f.Dispose();Save-Report
 Assert-PaytmCustodyController;Import-Module ScheduledTasks;Import-Module Microsoft.PowerShell.LocalAccounts
 foreach($name in @('InstallPaytmManagedTransport.ps1','PaytmManagedTransport.ps1','PaytmSupervisorTransport.ps1','PaytmTransportNative.cs','RunPaytmGatewaySupervisor.ps1','PaytmGatewaySupervisor.ps1','PaytmApplicationRoute.ps1')){$report.sourceHashes[$name]=(Get-FileHash -LiteralPath (Join-Path $PSScriptRoot $name)).Hash}
 $report.acceptedProgress=@(Get-PaytmReadinessProgress)
 $null=Assert-PaytmAccountPath $VpsEvidencePath
 if((Get-FileHash -LiteralPath $VpsEvidencePath).Hash -cne '4E0EBE1E69C11EA11455DC5EA40B30C07C9644E314A9667ECC572C0A32B8A4D5'){throw 'TRANSPORT_VPS_RECEIPT_NOT_ACCEPTED'}
 $vps=Read-PaytmRepairJson $VpsEvidencePath 32768;Assert-PaytmManagedProxyPassed $vps.server
 $report.custody=Assert-PaytmScheduledPrerequisites $CustodyReportPath
 $lease=[IO.File]::Open((Assert-PaytmAccountPath (Join-Path (Get-PaytmAccountContract).root 'supervisor-install.lock')),'OpenOrCreate','ReadWrite','None')
 $manifest=Assert-PaytmTransportUpgrade
 $report.before=Wait-PaytmHost $installation LOCKED
 Transport-Step 'CHECK_EXISTING_APPLICATION' 10
 Initialize-PaytmManagedApplication
 Transport-Step 'BUILD_PROTECTED_EXTENSION' 25
 $stage=Join-Path $c.root ('transport-update-'+$report.runId)
 $null=Assert-PaytmAccountPath $stage;if(Test-Path -LiteralPath $stage){throw 'TRANSPORT_BACKUP_EXISTS'}
 $null=New-Item -ItemType Directory -Path $stage;Set-PaytmAccountDirectoryAcl $stage (Get-PaytmKeyContract).accountSid
 foreach($pair in @(@('runner.ps1','RunPaytmGatewaySupervisor.ps1'),@('transport.ps1','PaytmSupervisorTransport.ps1'),@('gateway.ps1','PaytmGatewaySupervisor.ps1'),@('transport.cs','PaytmTransportNative.cs'))){Copy-Item -LiteralPath (Join-Path $PSScriptRoot $pair[1]) -Destination (Join-Path $stage $pair[0])}
 $compile="`$ErrorActionPreference='Stop';Add-Type -Path '$stage\transport.cs' -OutputAssembly '$stage\transport.dll'"
 $encoded=[Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($compile))
 $result=Complete-TunnelProcess (Start-TunnelProcess $c.executable @('-NoLogo','-NoProfile','-NonInteractive','-EncodedCommand',$encoded)) 30
 if($result.StoppedByRunner -or $result.ExitCode -ne 0){$report.compilation=@{exitCode=$result.ExitCode;output=$result.Stdout;error=$result.Stderr};throw 'TRANSPORT_NATIVE_COMPILE_FAILED'}
 Add-Type -Path (Join-Path $stage 'transport.dll')
 Assert-PaytmTransportListener (Get-PaytmTransportListeners)
 # Preflight and compile have succeeded. Existing task/password and native containment DLL are preserved.
 Transport-Step 'STOP_AND_UPDATE_OWNED_HOST' 40
 $mutated=$true;Set-PaytmHostControl $installation STOP
 $report.beforeUpgradeStopped=Wait-PaytmHost $installation STOPPED
 $workerLease=[IO.File]::Open((Join-Path $c.work 'instance.lock'),'Open','ReadWrite','None')
 $backup=Join-Path $stage 'before';$null=New-Item -ItemType Directory -Path $backup
 foreach($name in @('runner.ps1','manifest.json','control.json')){Copy-Item -LiteralPath (Join-Path $c.root $name) -Destination (Join-Path $backup $name);if((Get-FileHash -LiteralPath (Join-Path $backup $name)).Hash -cne (Get-FileHash -LiteralPath (Join-Path $c.root $name)).Hash){throw 'TRANSPORT_BACKUP_MISMATCH'}}
 $report.backup=$backup;Save-Report
 foreach($name in @('transport.ps1','gateway.ps1','transport.dll')){Copy-Item -LiteralPath (Join-Path $stage $name) -Destination (Join-Path $c.root $name);$manifest.hashes|Add-Member -NotePropertyName $name -NotePropertyValue (Get-FileHash -LiteralPath (Join-Path $c.root $name)).Hash}
 [IO.File]::Replace((Join-Path $stage 'runner.ps1'),(Join-Path $c.root 'runner.ps1'),[Management.Automation.Language.NullString]::Value)
 $manifest.hashes.'runner.ps1'=(Get-FileHash -LiteralPath (Join-Path $c.root 'runner.ps1')).Hash
 $manifest|Add-Member -NotePropertyName transportVersion -NotePropertyValue 1
 Write-PaytmHostJson (Join-Path $c.root 'manifest.json') $manifest
 Set-PaytmTransportControl $installation DISABLED;Set-PaytmHostControl $installation LOCKED
 $workerLease.Dispose();$workerLease=$null;$report.upgradeApplied=$true;Save-Report
 Transport-Step 'VERIFY_CONNECTION_ROUTE_RECOVERY_AND_STOP' 60
 Invoke-PaytmManagedLifecycle $installation {Save-Report}
 Transport-Step 'FINAL_ACCOUNT_AND_LOCK_CHECK' 95
}catch{
 $report.failure=if($_.Exception.Message -cmatch '^(HOST|TRANSPORT|APP_ROUTE|SCHEDULE|KEY|ACCOUNT)_[A-Z_]+$'){$_.Exception.Message}else{'TRANSPORT_INSTALL_REVIEW_REQUIRED'}
 $base=$_.Exception.GetBaseException();$report.failureDetails=@{type=$base.GetType().Name;hresult=$base.HResult;line=$_.InvocationInfo.ScriptLineNumber;script=[IO.Path]::GetFileName($_.InvocationInfo.ScriptName)}
}finally{
 if($workerLease){$workerLease.Dispose()}
 try{
  if($application.Ready){
   if((Invoke-PaytmApplicationHttp 'lock').state -cne 'LOCKED'){throw 'APP_ROUTE_FINAL_LOCK_FAILED'}
   $report.finalApplicationLockVerified=$true;Assert-PaytmWriterLocked
   $current=Get-PaytmApplicationContainer
   if($current.Id -cne $application.Id -or $current.Image -cne $application.Before.Image -or $current.State.StartedAt -cne $application.Before.State.StartedAt -or (Read-PaytmPaperAccount) -cne $application.BeforeAccount){throw 'APP_ROUTE_APPLICATION_OR_ACCOUNT_CHANGED'}
   $report.accountPreserved=$true
  }
 }catch{$report.cleanupFailure='APP_ROUTE_FINAL_REVIEW_REQUIRED'}
 $application.Token=$null
 if($report.failure -or $report.cleanupFailure){
  $report.status='REVIEW_REQUIRED'
  if($mutated){try{
   Stop-PaytmFailedManagedHost $installation
   $report.failureStopVerified=$true
   $report.failedWorker=Read-PaytmHostJson (Join-Path $c.work 'status.json')
   if(Test-Path -LiteralPath (Join-Path $c.work 'startup-failure.json')){$report.startupFailure=Read-PaytmHostJson (Join-Path $c.work 'startup-failure.json')}
  }catch{$report.cleanupFailure='TRANSPORT_STOP_REVIEW_REQUIRED'}}
 }
 if($lease){$lease.Dispose()}
 if(-not $report.failure -and -not $report.cleanupFailure -and $report.restartPassed -and $report.finalApplicationLockVerified -and $report.accountPreserved){
  $report.status='MANAGED_WINDOWS_TRANSPORT_AND_APPLICATION_ROUTE_PASSED_BOOT_PENDING'
 }
 if($report.status -ne 'REVIEW_REQUIRED'){$report.stage='COMPLETE'}
 Save-Report;Write-Progress -Activity 'Managed Windows transport' -Completed;Write-Progress -Activity 'Gateway supervisor installation' -Completed
 Write-Host "[100%] $($report.status); elapsed=$($report.elapsedSeconds)s"
 Write-Host "Share this ONE file: $path"
}
if($report.status -ceq 'REVIEW_REQUIRED'){throw 'Managed transport needs review. Share the JSON; do not reinstall or remove the account/key.'}
