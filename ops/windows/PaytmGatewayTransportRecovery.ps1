#Requires -Version 7.0
# One recovery of E224's exact stopped worker. Never a generic latch reset.
function Assert-PaytmReviewedTransportFailure([string]$Path){
 $null=Assert-PaytmAccountPath $Path
 if((Get-FileHash -LiteralPath $Path).Hash -cne 'E2C70C7DDCDB5B3E0EA3E742DE094FC568D1728D2CF6D51A5C8876B7D19A128E'){throw 'HOST_TRANSPORT_RECOVERY_RECEIPT_NOT_REVIEWED'}
 $r=Read-PaytmHostJson $Path 65536
 if($r.runId -cne 'b49f51c3f0db4ad996892fcdcd6b14b7' -or $r.failure -cne 'STARTUP_WORKER_FAILURE_PRESENT' -or $r.cleanupFailure -or $r.networkInterruptionAttempted -or $r.cleanupTasksRegistered -ne 0 -or $r.workerDiagnostics.task.lastResult -ne 1 -or -not $r.workerDiagnostics.task.definitionVerified -or $r.workerDiagnostics.process.exists -ne $false){throw 'HOST_TRANSPORT_RECOVERY_RECEIPT_INVALID'}
 $v=$r.workerDiagnostics.files.'status.json'.value
 if($v.instanceId -cne 'f9d773e4554a4d9fbd26d0dc62c52e2a' -or $v.processId -ne 11056 -or $v.failure -cne 'TRANSPORT_UNKNOWN' -or $v.phase -cne 'BLOCKED' -or $v.brokerReady -or $v.ordersEnabled){throw 'HOST_TRANSPORT_RECOVERY_WORKER_NOT_REVIEWED'}
 $r
}
function Invoke-PaytmReviewedTransportRecovery($Receipt,[string]$Path,[string]$SourceDirectory){
 $c=Get-PaytmHostContract;$workerLease=$null
 $review=Assert-PaytmReviewedTransportFailure $Path
 $m=Assert-PaytmTransportInstallationSources $Receipt;$id=$m.installationId
 if($m.hashes.'transport.ps1' -cne $review.sourceHashes.'PaytmSupervisorTransport.ps1' -or -not (Test-PaytmFirstFailureRunnerHash $m.hashes.'runner.ps1')){throw 'HOST_TRANSPORT_RECOVERY_ALREADY_CHANGED'}
 $source=Assert-PaytmAccountPath (Join-Path $SourceDirectory 'PaytmSupervisorTransport.ps1')
 $newHash=(Get-FileHash -LiteralPath $source).Hash
 if(-not (Test-PaytmObservedTransportHash $newHash)){throw 'HOST_TRANSPORT_RECOVERY_SOURCE_NOT_REVIEWED'}
 Add-Type -Path (Join-Path $c.root 'transport.dll')
 $old=$review.workerDiagnostics.files.'status.json'.value
 Assert-PaytmLatchIdle $id $old.processId
 $control=Read-PaytmHostJson (Join-Path $c.root 'control.json');Assert-PaytmHostControl $control $id
 if($control.mode -cne 'LOCKED' -or (Read-PaytmTransportControl $c.root $id) -cne 'ENABLED'){throw 'HOST_TRANSPORT_RECOVERY_CONTROL_CHANGED'}
 try{
  $workerLease=[IO.File]::Open((Assert-PaytmAccountPath (Join-Path $c.work 'instance.lock')),'OpenOrCreate','ReadWrite','None')
  $hashes=@{}
  foreach($n in @('startup-failure.json','blocked.json','status.json')){
   $p=Assert-PaytmAccountPath (Join-Path $c.work $n)
   $v=Get-PaytmWorkerEvidenceFile $p;$expected=$review.workerDiagnostics.files.$n
   if(-not $v.present -or -not $v.readSucceeded -or $v.length -ne $expected.length -or ($v.value|ConvertTo-Json -Depth 8 -Compress) -cne ($expected.value|ConvertTo-Json -Depth 8 -Compress)){throw 'HOST_TRANSPORT_RECOVERY_EVIDENCE_CHANGED'}
   $hashes[$n]=(Get-FileHash -LiteralPath $p).Hash
  }
  Assert-PaytmLatchIdle $id $old.processId
  $backup=Assert-PaytmAccountPath (Join-Path $c.root ('transport-recovery-'+$report.runId))
  if(Test-Path -LiteralPath $backup){throw 'HOST_TRANSPORT_RECOVERY_BACKUP_EXISTS'}
  $null=New-Item -ItemType Directory -Path $backup
  Set-PaytmAccountDirectoryAcl $backup (Get-PaytmKeyContract).accountSid
  $report.transportRecovery=[ordered]@{reviewedRunId=$review.runId;backupPath=$backup;backupHashes=@{};backupVerified=$false;transportUpdated=$false;manifestUpdated=$false;markersArchived=$false;startAttempts=0;healthy=$false;oldTransportHash=$m.hashes.'transport.ps1';newTransportHash=$newHash}
  foreach($n in @('transport.ps1','manifest.json','control.json','transport-control.json','startup-failure.json','blocked.json','status.json')){
   $from=Assert-PaytmAccountPath (Join-Path $(if($hashes.ContainsKey($n)){$c.work}else{$c.root}) $n)
   $h=(Get-FileHash -LiteralPath $from).Hash
   Copy-Item -LiteralPath $from -Destination (Join-Path $backup $n)
   if((Get-FileHash -LiteralPath (Join-Path $backup $n)).Hash -cne $h){throw 'HOST_TRANSPORT_RECOVERY_BACKUP_MISMATCH'}
   $report.transportRecovery.backupHashes[$n]=$h
  }
  $report.transportRecovery.backupVerified=$true
  $report.transportRecoveryAttempted=$true;Save-Report
  Set-PaytmHostControl $id STOP
  $null=Assert-PaytmTransportInstallationSources $Receipt
  $replacement=Assert-PaytmAccountPath (Join-Path $c.root ('transport-'+$report.runId+'.tmp'))
  if(Test-Path -LiteralPath $replacement){throw 'HOST_TRANSPORT_RECOVERY_TEMP_EXISTS'}
  Copy-Item -LiteralPath $source -Destination $replacement
  if((Get-FileHash -LiteralPath $replacement).Hash -cne $newHash){throw 'HOST_TRANSPORT_RECOVERY_REPLACEMENT_DRIFT'}
  [IO.File]::Replace($replacement,(Join-Path $c.root 'transport.ps1'),[Management.Automation.Language.NullString]::Value)
  $report.transportRecovery.transportUpdated=$true
  $m.hashes.'transport.ps1'=$newHash;Write-PaytmHostJson (Join-Path $c.root 'manifest.json') $m
  $null=Assert-PaytmTransportInstallationSources $Receipt
  $report.transportRecovery.manifestUpdated=$true;Save-Report
  Assert-PaytmLatchIdle $id $old.processId
  foreach($n in @('startup-failure.json','blocked.json','status.json')){
   if((Get-FileHash -LiteralPath (Join-Path $c.work $n)).Hash -cne $hashes[$n]){throw 'HOST_TRANSPORT_RECOVERY_MARKER_DRIFT'}
  }
  foreach($n in @('startup-failure.json','blocked.json','status.json')){Remove-Item -LiteralPath (Join-Path $c.work $n) -ErrorAction Stop}
  $report.transportRecovery.markersArchived=$true
  Set-PaytmHostControl $id LOCKED
  $null=Assert-PaytmInstalledTransport $Receipt
 }finally{if($workerLease){$workerLease.Dispose()}}
 $report.transportRecovery.startAttempts=1;Save-Report
 Start-ScheduledTask -TaskName $c.name -TaskPath '\' -ErrorAction Stop
 $report.transportRecovery.worker=Wait-PaytmManagedHost $id TRANSPORT_READY $old.instanceId -AwaitScheduledStart
 $report.transportRecovery.healthy=$true;Save-Report
}
