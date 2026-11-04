#Requires -Version 7.0
# One reviewed recovery of E220. Never a general latch reset or automatic retry.
function Assert-PaytmReviewedLatchReceipt([string]$Path){
 $null=Assert-PaytmAccountPath $Path
 if((Get-FileHash -LiteralPath $Path).Hash -cne '84CD04B5A73CF08C01F88668265DCD06D6DDF8CC60F1A755BD38AB6733F6D66C'){throw 'HOST_LATCH_RECEIPT_NOT_REVIEWED'}
 $v=Read-PaytmHostJson $Path 32768
 if($v.runId -cne '8c0d2d14cb304f9493a08f87ba281250' -or $v.status -cne 'WORKER_FAILURE_DIAGNOSTICS_CAPTURED' -or -not $v.inspectionOnly -or $v.failure -or $v.cleanupFailure){throw 'HOST_LATCH_RECEIPT_INVALID'}
 $v
}
function Assert-PaytmLatchIdle([string]$Id,[int]$PreviousPid){
 $c=Get-PaytmHostContract;$task=Get-PaytmOwnedHostTask $Id
 if([string]$task.State -cin @('Running','Queued')){throw 'HOST_LATCH_TASK_NOT_IDLE'}
 $info=Get-ScheduledTaskInfo -TaskName $c.name -TaskPath '\' -ErrorAction Stop
 if($info.LastTaskResult -ne 1){throw 'HOST_LATCH_TASK_RESULT_CHANGED'}
 # Enumerating IDs avoids treating access-denied as proof of absence.
 if(@(Get-Process -ErrorAction Stop|Where-Object Id -EQ $PreviousPid).Count){throw 'HOST_LATCH_PROCESS_PRESENT'}
 Assert-PaytmTransportListener (Get-PaytmTransportListeners)
}
function Invoke-PaytmReviewedLatchRecovery($Receipt,[string]$DiagnosticPath,[string]$SourceDirectory){
 $c=Get-PaytmHostContract;$workerLease=$null
 $review=Assert-PaytmReviewedLatchReceipt $DiagnosticPath
 $m=Assert-PaytmTransportInstallationSources $Receipt;$id=$m.installationId
 # A completed/partial recovery cannot silently reset a newer failure.
 if($m.hashes.'runner.ps1' -cne $Receipt.sourceHashes.'RunPaytmGatewaySupervisor.ps1'){throw 'HOST_LATCH_ALREADY_CHANGED_REVIEW_REQUIRED'}
 $newHash=(Get-FileHash -LiteralPath (Join-Path $SourceDirectory 'RunPaytmGatewaySupervisor.ps1')).Hash
 if(-not (Test-PaytmFirstFailureRunnerHash $newHash)){throw 'HOST_LATCH_REPLACEMENT_NOT_REVIEWED'}
 $control=Read-PaytmHostJson (Join-Path $c.root 'control.json');Assert-PaytmHostControl $control $id
 if($control.mode -cne 'LOCKED' -or (Read-PaytmTransportControl $c.root $id) -cne 'ENABLED'){throw 'HOST_LATCH_CONTROL_CHANGED'}
 $old=$review.workerDiagnostics.files.'status.json'.value
 Add-Type -Path (Join-Path $c.root 'transport.dll')
 Assert-PaytmLatchIdle $id $old.processId
 try{
  $workerLease=[IO.File]::Open((Assert-PaytmAccountPath (Join-Path $c.work 'instance.lock')),'OpenOrCreate','ReadWrite','None')
  $hashes=@{}
  foreach($name in @('startup-failure.json','blocked.json','status.json')){
   $p=Assert-PaytmAccountPath (Join-Path $c.work $name)
   $v=Get-PaytmWorkerEvidenceFile $p;$expected=$review.workerDiagnostics.files.$name
   if(-not $v.present -or -not $v.readSucceeded -or $v.length -ne $expected.length -or
      ($v.value|ConvertTo-Json -Depth 8 -Compress) -cne ($expected.value|ConvertTo-Json -Depth 8 -Compress)){throw 'HOST_LATCH_EVIDENCE_CHANGED'}
   $hashes[$name]=(Get-FileHash -LiteralPath $p).Hash
  }
  Assert-PaytmLatchIdle $id $old.processId
  $backup=Join-Path $c.root ('latch-recovery-'+$report.runId)
  $null=Assert-PaytmAccountPath $backup
  if(Test-Path -LiteralPath $backup){throw 'HOST_LATCH_BACKUP_EXISTS'}
  $null=New-Item -ItemType Directory -Path $backup
  Set-PaytmAccountDirectoryAcl $backup (Get-PaytmKeyContract).accountSid
  $report.latchRecovery=[ordered]@{backupPath=$backup;backupHashes=@{};backupVerified=$false;runnerUpdated=$false;manifestUpdated=$false;markersArchived=$false;startAttempts=0;healthy=$false}
  foreach($name in @('startup-failure.json','blocked.json','status.json','runner.ps1','manifest.json','control.json','transport-control.json')){
   $source=Join-Path $(if($hashes.ContainsKey($name)){$c.work}else{$c.root}) $name
   $source=Assert-PaytmAccountPath $source
   $h=(Get-FileHash -LiteralPath $source).Hash
   Copy-Item -LiteralPath $source -Destination (Join-Path $backup $name)
   if((Get-FileHash -LiteralPath (Join-Path $backup $name)).Hash -cne $h){throw 'HOST_LATCH_BACKUP_MISMATCH'}
   $report.latchRecovery.backupHashes[$name]=$h
  }
  $report.latchRecovery.backupVerified=$true
  # Checkpoint intent before mutation. Failure cleanup persists STOP and disables task.
  $report.latchRecoveryAttempted=$true;Save-Report
  Set-PaytmHostControl $id STOP
  $null=Assert-PaytmTransportInstallationSources $Receipt
  Update-PaytmReviewedRunner $m $report.runId $SourceDirectory $report.latchRecovery
  foreach($name in @('startup-failure.json','blocked.json','status.json')){
   $p=Assert-PaytmAccountPath (Join-Path $c.work $name)
   if((Get-FileHash -LiteralPath $p).Hash -cne $hashes[$name]){throw 'HOST_LATCH_EVIDENCE_DRIFT'}
  }
  Assert-PaytmLatchIdle $id $old.processId
  # Only these three archived files, under the fixed work root and exclusive worker lease.
  foreach($name in @('startup-failure.json','blocked.json','status.json')){Remove-Item -LiteralPath (Join-Path $c.work $name) -ErrorAction Stop}
  $report.latchRecovery.markersArchived=$true
  Set-PaytmHostControl $id LOCKED
  $null=Assert-PaytmInstalledTransport $Receipt
 }finally{if($workerLease){$workerLease.Dispose()}}
 $report.latchRecovery.startAttempts=1;Save-Report
 Start-ScheduledTask -TaskName $c.name -TaskPath '\' -ErrorAction Stop
 $report.latchRecovery.worker=Wait-PaytmManagedHost $id TRANSPORT_READY $old.instanceId
 $report.latchRecovery.healthy=$true;Save-Report
}
