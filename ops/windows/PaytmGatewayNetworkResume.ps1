#Requires -Version 7.0
# E225 completed recovery; resume its deliberately stopped worker with one adapter update.
function Assert-PaytmReviewedNetworkFailure([string]$Path){
 $null=Assert-PaytmAccountPath $Path
 if((Get-FileHash -LiteralPath $Path).Hash -cne 'C548C0A71025967778C14BC7573D358FD9FD0A290DB6D1FED3FBA1C9B9053B3B'){throw 'HOST_NETWORK_RESUME_RECEIPT_NOT_REVIEWED'}
 $v=Read-PaytmHostJson $Path 65536
 if($v.runId -cne '1c972328b34c4a7e80fb637e05ec8a8c' -or $v.failure -cne 'NETWORK_BACKOFF_NOT_OBSERVED' -or $v.cleanupFailure -or $v.networkLossObserved -or $v.networkRecoveryPassed){throw 'HOST_NETWORK_RESUME_RECEIPT_INVALID'}
 foreach($n in @('failureStopVerified','accountPreserved','finalApplicationLockVerified','networkCleanupRehearsalPassed','transportRecoveryAttempted')){if($v.$n -ne $true){throw 'HOST_NETWORK_RESUME_RECEIPT_PROOF'}}
 foreach($n in @('backupVerified','transportUpdated','manifestUpdated','markersArchived','healthy')){if($v.transportRecovery.$n -ne $true){throw 'HOST_NETWORK_RESUME_RECOVERY_PROOF'}}
 if($v.transportRecovery.startAttempts -ne 1 -or @($v.networkGuards).Count -ne 2 -or @($v.networkGuards|Where-Object { -not $_.removed -or -not $_.taskRemoved }).Count){throw 'HOST_NETWORK_RESUME_CLEANUP_PROOF'}
 $v
}
function Assert-PaytmNetworkResumeIdle([string]$Id,[int]$PreviousPid){
 $c=Get-PaytmHostContract;$t=Get-PaytmOwnedHostTask $Id $false
 if([string]$t.State -cin @('Running','Queued')){throw 'HOST_NETWORK_RESUME_TASK_NOT_IDLE'}
 $control=Read-PaytmHostJson (Join-Path $c.root 'control.json');Assert-PaytmHostControl $control $Id
 if($control.mode -cne 'STOP' -or (Read-PaytmTransportControl $c.root $Id) -cne 'ENABLED'){throw 'HOST_NETWORK_RESUME_CONTROL_CHANGED'}
 foreach($n in @('startup-failure.json','blocked.json')){if(Test-Path -LiteralPath (Assert-PaytmAccountPath (Join-Path $c.work $n))){throw 'HOST_NETWORK_RESUME_NEW_FAILURE'}}
 if(@(Get-Process -ErrorAction Stop|Where-Object Id -EQ $PreviousPid).Count){throw 'HOST_NETWORK_RESUME_PROCESS_PRESENT'}
 Assert-PaytmTransportListener (Get-PaytmTransportListeners)
}
function Invoke-PaytmReviewedNetworkResume($Receipt,[string]$Path,[string]$SourceDirectory){
 $c=Get-PaytmHostContract;$workerLease=$null
 $review=Assert-PaytmReviewedNetworkFailure $Path
 $m=Assert-PaytmTransportInstallationSources $Receipt;$id=$m.installationId
 if($m.hashes.'transport.ps1' -cne $review.transportRecovery.newTransportHash -or -not (Test-PaytmFirstFailureRunnerHash $m.hashes.'runner.ps1')){throw 'HOST_NETWORK_RESUME_ALREADY_CHANGED'}
 $source=Assert-PaytmAccountPath (Join-Path $SourceDirectory 'PaytmSupervisorTransport.ps1');$newHash=(Get-FileHash -LiteralPath $source).Hash
 if(-not (Test-PaytmOutboundTransportHash $newHash)){throw 'HOST_NETWORK_RESUME_SOURCE_NOT_REVIEWED'}
 Add-Type -Path (Join-Path $c.root 'transport.dll')
 $old=$review.transportRecovery.worker
 Assert-PaytmNetworkResumeIdle $id $old.processId
 try{
  $workerLease=[IO.File]::Open((Assert-PaytmAccountPath (Join-Path $c.work 'instance.lock')),'OpenOrCreate','ReadWrite','None')
  $last=Read-PaytmHostJson (Assert-PaytmAccountPath (Join-Path $c.work 'status.json'))
  if($last.installationId -cne $id -or $last.instanceId -cne $old.instanceId -or $last.processId -ne $old.processId -or $last.failure -or $last.brokerReady -or $last.ordersEnabled){throw 'HOST_NETWORK_RESUME_WORKER_CHANGED'}
  $archive=Assert-PaytmAccountPath (Join-Path $c.root ('transport-recovery-'+$review.runId))
  foreach($n in @('transport.ps1','manifest.json','control.json','transport-control.json','startup-failure.json','blocked.json','status.json')){
   if((Get-FileHash -LiteralPath (Assert-PaytmAccountPath (Join-Path $archive $n))).Hash -cne $review.transportRecovery.backupHashes.$n){throw 'HOST_NETWORK_RESUME_ARCHIVE_DRIFT'}
  }
  $original=Read-PaytmHostJson (Join-Path $archive 'manifest.json')
  foreach($n in @('runner.ps1','host.ps1','native.dll','gateway.ps1','transport.dll')){if($m.hashes.$n -cne $original.hashes.$n){throw 'HOST_NETWORK_RESUME_INSTALLATION_DRIFT'}}
  $backup=Assert-PaytmAccountPath (Join-Path $c.root ('network-resume-'+$report.runId))
  if(Test-Path -LiteralPath $backup){throw 'HOST_NETWORK_RESUME_BACKUP_EXISTS'}
  $null=New-Item -ItemType Directory -Path $backup;Set-PaytmAccountDirectoryAcl $backup (Get-PaytmKeyContract).accountSid
  $report.networkResume=[ordered]@{reviewedRunId=$review.runId;priorArchiveVerified=$true;backupPath=$backup;backupHashes=@{};backupVerified=$false;transportUpdated=$false;manifestUpdated=$false;startAttempts=0;healthy=$false;oldTransportHash=$m.hashes.'transport.ps1';newTransportHash=$newHash}
  foreach($n in @('transport.ps1','manifest.json','control.json','transport-control.json','status.json')){
   $from=Assert-PaytmAccountPath (Join-Path $(if($n -ceq 'status.json'){$c.work}else{$c.root}) $n);$h=(Get-FileHash -LiteralPath $from).Hash
   Copy-Item -LiteralPath $from -Destination (Join-Path $backup $n)
   if((Get-FileHash -LiteralPath (Join-Path $backup $n)).Hash -cne $h){throw 'HOST_NETWORK_RESUME_BACKUP_MISMATCH'}
   $report.networkResume.backupHashes[$n]=$h
  }
  $report.networkResume.backupVerified=$true;$report.networkResumeAttempted=$true;Save-Report
  Assert-PaytmNetworkResumeIdle $id $old.processId
  $null=Assert-PaytmTransportInstallationSources $Receipt
  $replacement=Assert-PaytmAccountPath (Join-Path $c.root ('transport-'+$report.runId+'.tmp'))
  if(Test-Path -LiteralPath $replacement){throw 'HOST_NETWORK_RESUME_TEMP_EXISTS'}
  Copy-Item -LiteralPath $source -Destination $replacement
  if((Get-FileHash -LiteralPath $replacement).Hash -cne $newHash){throw 'HOST_NETWORK_RESUME_REPLACEMENT_DRIFT'}
  [IO.File]::Replace($replacement,(Join-Path $c.root 'transport.ps1'),[Management.Automation.Language.NullString]::Value)
  $report.networkResume.transportUpdated=$true
  $m.hashes.'transport.ps1'=$newHash;Write-PaytmHostJson (Join-Path $c.root 'manifest.json') $m
  $null=Assert-PaytmTransportInstallationSources $Receipt;$report.networkResume.manifestUpdated=$true;Save-Report
  Assert-PaytmNetworkResumeIdle $id $old.processId
  $null=Enable-ScheduledTask -TaskName $c.name -TaskPath '\' -ErrorAction Stop
  $null=Get-PaytmOwnedHostTask $id
  Set-PaytmHostControl $id LOCKED
 }finally{if($workerLease){$workerLease.Dispose()}}
 $report.networkResume.startAttempts=1;Save-Report
 Start-ScheduledTask -TaskName $c.name -TaskPath '\' -ErrorAction Stop
 $report.networkResume.worker=Wait-PaytmManagedHost $id TRANSPORT_READY $old.instanceId -AwaitScheduledStart
 $report.networkResume.healthy=$true;Save-Report
}
