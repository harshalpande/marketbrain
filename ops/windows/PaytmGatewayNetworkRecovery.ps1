#Requires -Version 7.0
# E226: exact saved worker failure only; do not depend on the mismatched E225 path.
function Assert-PaytmReviewedNetworkDiagnostic([string]$Path){
 $null=Assert-PaytmAccountPath $Path
 $actual=(Get-FileHash -LiteralPath $Path).Hash
 $report.networkRecoveryReceipt=[ordered]@{fileName=[IO.Path]::GetFileName($Path);expectedSha256='3AC00E888E53B308D910EB889ABDCAE674917171D497240952C4C39FFBBD5977';actualSha256=$actual}
 Save-Report
 if($actual -cne $report.networkRecoveryReceipt.expectedSha256){throw 'HOST_NETWORK_RECOVERY_RECEIPT_NOT_REVIEWED'}
 $v=Read-PaytmHostJson $Path 65536
 if($v.runId -cne '2ebb314193ad49af954ea8b1eeadbcec' -or $v.failure -cne 'HOST_NETWORK_RESUME_RECEIPT_NOT_REVIEWED' -or $v.cleanupFailure -or $v.networkResumeAttempted -or $v.networkInterruptionAttempted -or $v.cleanupTasksRegistered -ne 0 -or $v.accountPreserved -ne $true -or $v.finalApplicationLockVerified -ne $true){throw 'HOST_NETWORK_RECOVERY_RECEIPT_INVALID'}
 $d=$v.workerDiagnostics;$s=$d.files.'status.json'.value
 if($d.task.definitionVerified -ne $true -or $d.task.enabled -ne $false -or $d.task.lastResult -ne 1 -or $d.process.exists -ne $false -or $d.controls.'control.json'.value.mode -cne 'STOP' -or $d.controls.'transport-control.json'.value.mode -cne 'ENABLED'){throw 'HOST_NETWORK_RECOVERY_STATE_NOT_REVIEWED'}
 if($s.instanceId -cne 'b7598556f2e4478dba5ea94c73eb1f92' -or $s.processId -ne 8576 -or $s.failure -cne 'TRANSPORT_KEY_DENIED' -or $s.phase -cne 'BLOCKED' -or $s.brokerReady -or $s.ordersEnabled -or $s.lastSshObservation.stderrCharacters -ne 245 -or $s.lastSshObservation.stderrSha256 -cne '43292094F48E6EB533C45228EB0C423B128D31A54D3E56364EB949F4D4B6FA59'){throw 'HOST_NETWORK_RECOVERY_CAUSE_NOT_REVIEWED'}
 $v
}
function Assert-PaytmNetworkRecoveryIdle([string]$Id,[int]$PreviousPid){
 $c=Get-PaytmHostContract;$t=Get-PaytmOwnedHostTask $Id $false
 if([string]$t.State -cin @('Running','Queued') -or (Get-ScheduledTaskInfo -TaskName $c.name -TaskPath '\' -ErrorAction Stop).LastTaskResult -ne 1){throw 'HOST_NETWORK_RECOVERY_TASK_CHANGED'}
 $control=Read-PaytmHostJson (Join-Path $c.root 'control.json');Assert-PaytmHostControl $control $Id
 if($control.mode -cne 'STOP' -or (Read-PaytmTransportControl $c.root $Id) -cne 'ENABLED'){throw 'HOST_NETWORK_RECOVERY_CONTROL_CHANGED'}
 if(@(Get-Process -ErrorAction Stop|Where-Object Id -EQ $PreviousPid).Count){throw 'HOST_NETWORK_RECOVERY_PROCESS_PRESENT'}
 Assert-PaytmTransportListener (Get-PaytmTransportListeners)
}
function Invoke-PaytmReviewedNetworkFailureRecovery($Receipt,[string]$Path,[string]$SourceDirectory){
 $c=Get-PaytmHostContract;$workerLease=$null
 $review=Assert-PaytmReviewedNetworkDiagnostic $Path
 $m=Assert-PaytmTransportInstallationSources $Receipt;$id=$m.installationId
 if($m.hashes.'transport.ps1' -cne $review.sourceHashes.'PaytmSupervisorTransport.ps1' -or $m.hashes.'transport.ps1' -cne '0C9405BE49E04763C3FA757A79119A7E5B9D1EC6EC6657EF1B2E7AD0E6AA3656' -or -not (Test-PaytmFirstFailureRunnerHash $m.hashes.'runner.ps1')){throw 'HOST_NETWORK_RECOVERY_ALREADY_CHANGED'}
 $source=Assert-PaytmAccountPath (Join-Path $SourceDirectory 'PaytmSupervisorTransport.ps1');$newHash=(Get-FileHash -LiteralPath $source).Hash
 if(-not (Test-PaytmVerboseTcpTransportHash $newHash)){throw 'HOST_NETWORK_RECOVERY_SOURCE_NOT_REVIEWED'}
 Add-Type -Path (Join-Path $c.root 'transport.dll')
 $old=$review.workerDiagnostics.files.'status.json'.value
 Assert-PaytmNetworkRecoveryIdle $id $old.processId
 # Unknown prior-run cleanup cannot be inferred from E226. Inspect both stores now.
 Import-Module NetSecurity -ErrorAction Stop
 if(@(Get-ScheduledTask -ErrorAction Stop|Where-Object TaskName -Like 'MarketBrain-Network-Test-*').Count){throw 'NETWORK_PREVIOUS_GUARD_REVIEW_REQUIRED'}
 foreach($store in @('PersistentStore','ActiveStore')){if(@(Get-NetFirewallRule -PolicyStore $store -ErrorAction Stop|Where-Object Name -Like 'MarketBrain-Network-Test-*').Count){throw 'NETWORK_PREVIOUS_GUARD_REVIEW_REQUIRED'}}
 $report.networkRecoveryNoPriorGuards=$true
 try{
  $workerLease=[IO.File]::Open((Assert-PaytmAccountPath (Join-Path $c.work 'instance.lock')),'OpenOrCreate','ReadWrite','None')
  $hashes=@{}
  foreach($n in @('startup-failure.json','blocked.json','status.json')){
   $p=Assert-PaytmAccountPath (Join-Path $c.work $n);$v=Get-PaytmWorkerEvidenceFile $p;$expected=$review.workerDiagnostics.files.$n
   if(-not $v.present -or -not $v.readSucceeded -or $v.length -ne $expected.length -or ($v.value|ConvertTo-Json -Depth 8 -Compress) -cne ($expected.value|ConvertTo-Json -Depth 8 -Compress)){throw 'HOST_NETWORK_RECOVERY_EVIDENCE_CHANGED'}
   $hashes[$n]=(Get-FileHash -LiteralPath $p).Hash
  }
  $backup=Assert-PaytmAccountPath (Join-Path $c.root ('network-failure-recovery-'+$report.runId))
  if(Test-Path -LiteralPath $backup){throw 'HOST_NETWORK_RECOVERY_BACKUP_EXISTS'}
  $null=New-Item -ItemType Directory -Path $backup;Set-PaytmAccountDirectoryAcl $backup (Get-PaytmKeyContract).accountSid
  $report.networkFailureRecovery=[ordered]@{reviewedRunId=$review.runId;backupPath=$backup;backupHashes=@{};backupVerified=$false;transportUpdated=$false;manifestUpdated=$false;markersArchived=$false;startAttempts=0;healthy=$false;oldTransportHash=$m.hashes.'transport.ps1';newTransportHash=$newHash}
  foreach($n in @('transport.ps1','manifest.json','control.json','transport-control.json','startup-failure.json','blocked.json','status.json')){
   $from=Assert-PaytmAccountPath (Join-Path $(if($hashes.ContainsKey($n)){$c.work}else{$c.root}) $n);$h=(Get-FileHash -LiteralPath $from).Hash
   Copy-Item -LiteralPath $from -Destination (Join-Path $backup $n)
   if((Get-FileHash -LiteralPath (Join-Path $backup $n)).Hash -cne $h){throw 'HOST_NETWORK_RECOVERY_BACKUP_MISMATCH'}
   $report.networkFailureRecovery.backupHashes[$n]=$h
  }
  $report.networkFailureRecovery.backupVerified=$true;$report.networkFailureRecoveryAttempted=$true;Save-Report
  Assert-PaytmNetworkRecoveryIdle $id $old.processId;$null=Assert-PaytmTransportInstallationSources $Receipt
  $replacement=Assert-PaytmAccountPath (Join-Path $c.root ('transport-'+$report.runId+'.tmp'))
  if(Test-Path -LiteralPath $replacement){throw 'HOST_NETWORK_RECOVERY_TEMP_EXISTS'}
  Copy-Item -LiteralPath $source -Destination $replacement
  if((Get-FileHash -LiteralPath $replacement).Hash -cne $newHash){throw 'HOST_NETWORK_RECOVERY_REPLACEMENT_DRIFT'}
  [IO.File]::Replace($replacement,(Join-Path $c.root 'transport.ps1'),[Management.Automation.Language.NullString]::Value)
  $report.networkFailureRecovery.transportUpdated=$true
  $m.hashes.'transport.ps1'=$newHash;Write-PaytmHostJson (Join-Path $c.root 'manifest.json') $m
  $null=Assert-PaytmTransportInstallationSources $Receipt;$report.networkFailureRecovery.manifestUpdated=$true;Save-Report
  Assert-PaytmNetworkRecoveryIdle $id $old.processId
  foreach($n in @('startup-failure.json','blocked.json','status.json')){if((Get-FileHash -LiteralPath (Join-Path $c.work $n)).Hash -cne $hashes[$n]){throw 'HOST_NETWORK_RECOVERY_MARKER_DRIFT'}}
  foreach($n in @('startup-failure.json','blocked.json','status.json')){Remove-Item -LiteralPath (Join-Path $c.work $n) -ErrorAction Stop}
  $report.networkFailureRecovery.markersArchived=$true
  $null=Enable-ScheduledTask -TaskName $c.name -TaskPath '\' -ErrorAction Stop
  Set-PaytmHostControl $id LOCKED;$null=Assert-PaytmInstalledTransport $Receipt
 }finally{if($workerLease){$workerLease.Dispose()}}
 $report.networkFailureRecovery.startAttempts=1;Save-Report
 Start-ScheduledTask -TaskName $c.name -TaskPath '\' -ErrorAction Stop
 $report.networkFailureRecovery.worker=Wait-PaytmManagedHost $id TRANSPORT_READY $old.instanceId -AwaitScheduledStart
 $report.networkFailureRecovery.healthy=$true;Save-Report
}
