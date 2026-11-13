#Requires -Version 7.0
# Reviewed E244 network incident. One start; no installed source or key replacement.
function Assert-PaytmNativeReceipt([string]$Path){
 $null=Assert-PaytmAccountPath $Path
 if((Get-FileHash -LiteralPath $Path).Hash -cne '841B4F91E312C866E98E50DBA61DA15C055ED00BA375A9B36FCC5432ECA41827'){throw 'HOST_INCIDENT_RECEIPT_MISMATCH'}
 Read-PaytmHostJson $Path 65536
}
function Assert-PaytmIncidentIdle([string]$Id){
 $c=Get-PaytmHostContract
 $task=Get-PaytmOwnedHostTask $Id $false
 if([string]$task.State -cne 'Disabled'){throw 'HOST_INCIDENT_TASK_NOT_DISABLED'}
 $result=(Get-ScheduledTaskInfo -TaskName $c.name -TaskPath '\').LastTaskResult
 if($result -notin @(0,267014)){throw 'HOST_INCIDENT_TASK_RESULT_CHANGED'}
 if(@(Get-Process -ErrorAction Stop|Where-Object Id -EQ 10540).Count){throw 'HOST_INCIDENT_OLD_PROCESS_PRESENT'}
 $control=Read-PaytmHostJson (Join-Path $c.root 'control.json');Assert-PaytmHostControl $control $Id
 if($control.mode -cne 'STOP' -or (Read-PaytmTransportControl $c.root $Id) -cne 'ENABLED'){throw 'HOST_INCIDENT_CONTROL_DRIFT'}
 foreach($name in @('blocked.json','startup-failure.json')){
  if(Test-Path -LiteralPath (Assert-PaytmAccountPath (Join-Path $c.work $name))){throw 'HOST_INCIDENT_NEW_FAILURE_PRESENT'}
 }
 if(Test-Path -LiteralPath (Assert-PaytmAccountPath (Join-Path $c.root 'session-checkpoint.json'))){throw 'HOST_INCIDENT_CHECKPOINT_PRESENT'}
 $v=Read-PaytmHostJson (Assert-PaytmAccountPath (Join-Path $c.work 'status.json'))
 if($v.installationId -cne $Id -or $v.instanceId -cne 'fd109bc407a844e1ac724cf7466562f5' -or $v.processId -ne 10540 -or $v.failure -or $v.phase -cnotin @('BACKOFF','CONNECTING','TRANSPORT_READY','STOPPED')){throw 'HOST_INCIDENT_STATUS_CHANGED'}
 if($v.brokerReady -ne $false -or $v.ordersEnabled -ne $false){throw 'HOST_INCIDENT_SCOPE_CHANGED'}
 Assert-PaytmTransportListener (Get-PaytmTransportListeners)
}
function Invoke-PaytmNativeRecovery($Receipt,[string]$ReviewPath,[string]$SourceDirectory){
 $null=Assert-PaytmNativeReceipt $ReviewPath;$c=Get-PaytmHostContract
 $m=Assert-PaytmTransportInstallationSources $Receipt;$id=$m.installationId
 # Require the installed agent/phase diagnostics from the incident, not any older accepted version.
 foreach($pair in @(@('host.ps1','PaytmSupervisorHost.ps1'),@('runner.ps1','RunPaytmGatewaySupervisor.ps1'),@('transport.ps1','PaytmSupervisorTransport.ps1'))){
  if(-not(Test-PaytmAgentProbeSourceHash $pair[1] $m.hashes.($pair[0]))){throw 'HOST_INCIDENT_DIAGNOSTICS_NOT_INSTALLED'}
 }
 Add-Type -Path (Join-Path $c.root 'transport.dll')
 Assert-PaytmIncidentIdle $id
 $held=$null
 try{
  $held=[IO.File]::Open((Assert-PaytmAccountPath (Join-Path $c.work 'instance.lock')),'OpenOrCreate','ReadWrite','None')
  Assert-PaytmIncidentIdle $id
  $backup=Assert-PaytmAccountPath (Join-Path $c.root ('incident-recovery-'+$report.runId))
  if(Test-Path -LiteralPath $backup){throw 'HOST_INCIDENT_ARCHIVE_EXISTS'}
  $null=New-Item -ItemType Directory -Path $backup
  Set-PaytmAccountDirectoryAcl $backup (Get-PaytmKeyContract).accountSid
  $report.nativeRecovery=[ordered]@{backupPath=$backup;backupHashes=@{};backupVerified=$false;installedCodeChanged=$false;markersArchived=$false;taskEnabled=$false;startAttempts=0;healthy=$false;keyImported=$false}
  foreach($name in @('native.dll','host.ps1','runner.ps1','transport.ps1','transport.dll','gateway.ps1','manifest.json','control.json','transport-control.json','status.json')){
   $dir=if($name -eq 'status.json'){$c.work}else{$c.root}
   $from=Assert-PaytmAccountPath (Join-Path $dir $name);$hash=(Get-FileHash -LiteralPath $from).Hash
   Copy-Item -LiteralPath $from -Destination (Join-Path $backup $name) -ErrorAction Stop
   if((Get-FileHash -LiteralPath (Join-Path $backup $name)).Hash -cne $hash){throw 'HOST_INCIDENT_BACKUP_MISMATCH'}
   $report.nativeRecovery.backupHashes[$name]=$hash
  }
  $report.nativeRecovery.backupVerified=$true;Save-NativeRecoveryReport
  Assert-PaytmIncidentIdle $id;$null=Assert-PaytmTransportInstallationSources $Receipt
  foreach($name in $report.nativeRecovery.backupHashes.Keys){
   $dir=if($name -eq 'status.json'){$c.work}else{$c.root}
   if((Get-FileHash -LiteralPath (Join-Path $dir $name)).Hash -cne $report.nativeRecovery.backupHashes[$name]){throw 'HOST_INCIDENT_STATE_CHANGED'}
  }
  $report.nativeRecoveryAttempted=$true;Save-NativeRecoveryReport
  Remove-Item -LiteralPath (Assert-PaytmAccountPath (Join-Path $c.work 'status.json')) -ErrorAction Stop
  $report.nativeRecovery.markersArchived=$true
  Set-PaytmHostControl $id LOCKED
  $null=Enable-ScheduledTask -TaskName $c.name -TaskPath '\' -ErrorAction Stop
  $report.nativeRecovery.taskEnabled=$true
  $null=Assert-PaytmInstalledTransport $Receipt
 }finally{if($held){$held.Dispose()}}
 $report.nativeRecovery.startAttempts=1;Save-NativeRecoveryReport
 Start-ScheduledTask -TaskName $c.name -TaskPath '\' -ErrorAction Stop
 $report.nativeRecovery.first=Wait-PaytmManagedHost $id TRANSPORT_READY 'fd109bc407a844e1ac724cf7466562f5' -AwaitScheduledStart
 $report.nativeRecovery.healthy=$true;Save-NativeRecoveryReport
}
