#Requires -Version 7.0
# Exact E239 stopped installation; archive first, replace transport diagnostics only.
function Assert-PaytmNativeReceipt([string]$Path){
 $null=Assert-PaytmAccountPath $Path
 if((Get-FileHash -LiteralPath $Path).Hash -cne '9230E8F0802094A57D3EA5F03F724664048EEA8694D54AA77A02DFAF527F5FCA'){throw 'HOST_TLS_RECEIPT_MISMATCH'}
 Read-PaytmHostJson $Path 65536
}
function Assert-PaytmTlsIdle($Review,[string]$Id){
 $c=Get-PaytmHostContract
 $task=Get-PaytmOwnedHostTask $Id $false
 if([string]$task.State -cne 'Disabled' -or (Get-ScheduledTaskInfo -TaskName $c.name -TaskPath '\').LastTaskResult -ne 267014){throw 'HOST_TLS_TASK_DRIFT'}
 if(@(Get-Process -ErrorAction Stop|Where-Object Id -EQ 17932).Count){throw 'HOST_TLS_OLD_PID_PRESENT'}
 $control=Read-PaytmHostJson (Join-Path $c.root 'control.json');Assert-PaytmHostControl $control $Id
 if($control.mode -cne 'STOP' -or (Read-PaytmTransportControl $c.root $Id) -cne 'ENABLED'){throw 'HOST_TLS_CONTROL_DRIFT'}
 foreach($n in @('blocked.json','startup-failure.json')){if(Test-Path -LiteralPath (Assert-PaytmAccountPath (Join-Path $c.work $n))){throw 'HOST_TLS_NEW_FAILURE_PRESENT'}}
 if(Test-Path -LiteralPath (Assert-PaytmAccountPath (Join-Path $c.root 'session-checkpoint.json'))){throw 'HOST_TLS_CHECKPOINT_PRESENT'}
 $saved=Get-PaytmWorkerEvidenceFile (Join-Path $c.work 'status.json')
 $expected=$Review.workerDiagnostics.files.'status.json'
 if(-not $saved.readSucceeded -or $saved.length -ne $expected.length -or
    ($saved.value|ConvertTo-Json -Depth 8|ConvertFrom-Json|ConvertTo-Json -Depth 8 -Compress) -cne
    ($expected.value|ConvertTo-Json -Depth 8|ConvertFrom-Json|ConvertTo-Json -Depth 8 -Compress)){throw 'HOST_TLS_STATUS_DRIFT'}
 Assert-PaytmTransportListener (Get-PaytmTransportListeners)
}
function Invoke-PaytmNativeRecovery($Receipt,[string]$ReviewPath,[string]$SourceDirectory){
 $review=Assert-PaytmNativeReceipt $ReviewPath;$c=Get-PaytmHostContract
 $m=Assert-PaytmTransportInstallationSources $Receipt;$id=$m.installationId
 foreach($f in $review.installedFiles){if($m.hashes.($f.name) -cne $f.actualSha256){throw 'HOST_TLS_ALREADY_CHANGED'}}
 $source=Assert-PaytmAccountPath (Join-Path $SourceDirectory 'PaytmSupervisorTransport.ps1')
 $newHash=(Get-FileHash -LiteralPath $source).Hash
 if(-not (Test-PaytmTlsObservedTransportHash $newHash)){throw 'HOST_TLS_PATCH_NOT_REVIEWED'}
 Add-Type -Path (Join-Path $c.root 'transport.dll')
 Assert-PaytmTlsIdle $review $id
 $lease=$null
 try{
  $lease=[IO.File]::Open((Assert-PaytmAccountPath (Join-Path $c.work 'instance.lock')),'OpenOrCreate','ReadWrite','None')
  Assert-PaytmTlsIdle $review $id
  $backup=Assert-PaytmAccountPath (Join-Path $c.root ('tls-recovery-'+$report.runId))
  if(Test-Path -LiteralPath $backup){throw 'HOST_TLS_ARCHIVE_EXISTS'}
  $null=New-Item -ItemType Directory -Path $backup
  Set-PaytmAccountDirectoryAcl $backup (Get-PaytmKeyContract).accountSid
  $report.nativeRecovery=[ordered]@{backupPath=$backup;backupHashes=@{};backupVerified=$false;transportUpdated=$false;manifestUpdated=$false;markersArchived=$false;taskEnabled=$false;startAttempts=0;healthy=$false;keyImported=$false}
  foreach($n in @('transport.ps1','manifest.json','control.json','transport-control.json','status.json')){
   $dir=if($n -eq 'status.json'){$c.work}else{$c.root};$from=Assert-PaytmAccountPath (Join-Path $dir $n)
   $hash=(Get-FileHash -LiteralPath $from).Hash
   Copy-Item -LiteralPath $from -Destination (Join-Path $backup $n) -ErrorAction Stop
   if((Get-FileHash -LiteralPath (Join-Path $backup $n)).Hash -cne $hash){throw 'HOST_TLS_BACKUP_MISMATCH'}
   $report.nativeRecovery.backupHashes[$n]=$hash
  }
  $staged=Join-Path $backup 'new-transport.ps1'
  Copy-Item -LiteralPath $source -Destination $staged -ErrorAction Stop
  if((Get-FileHash -LiteralPath $staged).Hash -cne $newHash){throw 'HOST_TLS_STAGED_PATCH_DRIFT'}
  $report.nativeRecovery.backupVerified=$true;Save-NativeRecoveryReport
  Assert-PaytmTlsIdle $review $id;$null=Assert-PaytmTransportInstallationSources $Receipt
  foreach($n in $report.nativeRecovery.backupHashes.Keys){
   $dir=if($n -eq 'status.json'){$c.work}else{$c.root}
   if((Get-FileHash -LiteralPath (Join-Path $dir $n)).Hash -cne $report.nativeRecovery.backupHashes[$n]){throw 'HOST_TLS_STATE_CHANGED'}
  }
  $report.nativeRecoveryAttempted=$true;Save-NativeRecoveryReport
  # Atomic replacement; the disabled task and exclusive worker lease remain held.
  [IO.File]::Replace($staged,(Join-Path $c.root 'transport.ps1'),[Management.Automation.Language.NullString]::Value)
  $report.nativeRecovery.transportUpdated=$true
  $m.hashes.'transport.ps1'=$newHash
  Write-PaytmHostJson (Join-Path $c.root 'manifest.json') $m
  $null=Assert-PaytmTransportInstallationSources $Receipt
  $report.nativeRecovery.manifestUpdated=$true;Save-NativeRecoveryReport
  Assert-PaytmTlsIdle $review $id
  Remove-Item -LiteralPath (Join-Path $c.work 'status.json') -ErrorAction Stop
  $report.nativeRecovery.markersArchived=$true
  Set-PaytmHostControl $id LOCKED
  $null=Enable-ScheduledTask -TaskName $c.name -TaskPath '\' -ErrorAction Stop
  $report.nativeRecovery.taskEnabled=$true
  $null=Assert-PaytmInstalledTransport $Receipt
 }finally{if($lease){$lease.Dispose()}}
 $report.nativeRecovery.startAttempts=1;Save-NativeRecoveryReport
 Start-ScheduledTask -TaskName $c.name -TaskPath '\' -ErrorAction Stop
 $report.nativeRecovery.first=Wait-PaytmManagedHost $id TRANSPORT_READY '7d07b78014764b6497f70761d7348ff0' -AwaitScheduledStart
 $report.nativeRecovery.healthy=$true;Save-NativeRecoveryReport
}
