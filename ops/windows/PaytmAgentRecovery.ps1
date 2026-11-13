#Requires -Version 7.0
# Recovery adapter for the established archive/start/observe/application-lock controller.
# Loaded only with -AgentSigningRecovery. No installed code or keys are replaced.
function Assert-PaytmNativeReceipt([string]$Path){
 $null=Assert-PaytmAccountPath $Path
 if((Get-FileHash -LiteralPath $Path).Hash -cne '9365DC3D892CF86DF48C0874E3A9FCA2224F7BBB7CA08AE812B3891F34AD2654'){throw 'HOST_AGENT_SIGNING_RECEIPT_MISMATCH'}
 $v=Read-PaytmHostJson $Path 65536
 if($v.status -cne 'AGENT_SIGNING_PASSED_PRODUCTION_RECOVERY_PENDING' -or $v.failure -or $v.cleanupFailure -or -not $v.productionStateUnchanged -or -not $v.taskRemoved){throw 'HOST_AGENT_SIGNING_NOT_ACCEPTED'}
 Assert-PaytmScheduledWorker $v.worker $v.runId
 $v
}
function Assert-PaytmAgentRecoverySnapshot($Review){
 $now=Get-PaytmAgentSigningSnapshot
 foreach($entry in $Review.productionAfter.hashes.PSObject.Properties){
  if($now.hashes[$entry.Name] -cne $entry.Value){throw 'HOST_AGENT_RECOVERY_FILE_DRIFT'}
 }
 if($now.taskLastRunUtc -cne ([DateTimeOffset]$Review.productionAfter.taskLastRunUtc).UtcDateTime.ToString('o')){throw 'HOST_AGENT_RECOVERY_TASK_DRIFT'}
 $now
}
function Invoke-PaytmNativeRecovery($Receipt,[string]$ReviewPath,[string]$SourceDirectory){
 $review=Assert-PaytmNativeReceipt $ReviewPath;$c=Get-PaytmHostContract
 $m=Assert-PaytmTransportInstallationSources $Receipt;$id=$m.installationId
 $null=Assert-PaytmAgentRecoverySnapshot $review
 Add-Type -Path (Join-Path $c.root 'transport.dll')
 Assert-PaytmTransportListener (Get-PaytmTransportListeners)
 $held=$null
 try{
  $held=[IO.File]::Open((Assert-PaytmAccountPath (Join-Path $c.work 'instance.lock')),'OpenOrCreate','ReadWrite','None')
  $snapshot=Assert-PaytmAgentRecoverySnapshot $review
  $backup=Assert-PaytmAccountPath (Join-Path $c.root ('agent-recovery-'+$report.runId))
  if(Test-Path -LiteralPath $backup){throw 'HOST_AGENT_ARCHIVE_EXISTS'}
  $null=New-Item -ItemType Directory -Path $backup;Set-PaytmAccountDirectoryAcl $backup (Get-PaytmKeyContract).accountSid
  $report.nativeRecovery=[ordered]@{backupPath=$backup;backupHashes=@{};backupVerified=$false;markersArchived=$false;checkpointArchived=$false;startAttempts=0;healthy=$false;installedCodeChanged=$false;keyImported=$false}
  foreach($name in $snapshot.hashes.Keys){
   $dir=if($name -in @('startup-failure.json','blocked.json','status.json')){$c.work}else{$c.root}
   $from=Assert-PaytmAccountPath (Join-Path $dir $name)
   Copy-Item -LiteralPath $from -Destination (Join-Path $backup $name) -ErrorAction Stop
   if((Get-FileHash -LiteralPath (Join-Path $backup $name)).Hash -cne $snapshot.hashes[$name]){throw 'HOST_AGENT_BACKUP_MISMATCH'}
   $report.nativeRecovery.backupHashes[$name]=$snapshot.hashes[$name]
  }
  $report.nativeRecovery.backupVerified=$true;Save-NativeRecoveryReport
  $null=Assert-PaytmAgentRecoverySnapshot $review
  Assert-PaytmTransportListener (Get-PaytmTransportListeners)
  $report.nativeRecoveryAttempted=$true;Save-NativeRecoveryReport
  Set-PaytmHostControl $id STOP
  # Remove only four exact files after their complete verified copies exist.
  foreach($name in @('startup-failure.json','blocked.json','status.json','session-checkpoint.json')){
   $dir=if($name -eq 'session-checkpoint.json'){$c.root}else{$c.work}
   $path=Assert-PaytmAccountPath (Join-Path $dir $name)
   if((Get-FileHash -LiteralPath $path).Hash -cne $snapshot.hashes[$name]){throw 'HOST_AGENT_FILE_CHANGED_BEFORE_ARCHIVE'}
   Remove-Item -LiteralPath $path -ErrorAction Stop
  }
  $report.nativeRecovery.markersArchived=$true;$report.nativeRecovery.checkpointArchived=$true
  Set-PaytmHostControl $id LOCKED
  $null=Assert-PaytmInstalledTransport $Receipt
 }finally{if($held){$held.Dispose()}}
 $report.nativeRecovery.startAttempts=1;Save-NativeRecoveryReport
 Start-ScheduledTask -TaskName $c.name -TaskPath '\' -ErrorAction Stop
 $report.nativeRecovery.first=Wait-PaytmManagedHost $id TRANSPORT_READY 'c066052a24f1456895792ee98dda78ac' -AwaitScheduledStart
 $report.nativeRecovery.healthy=$true;Save-NativeRecoveryReport
}
