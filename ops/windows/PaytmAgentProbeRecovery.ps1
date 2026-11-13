#Requires -Version 7.0
function Assert-PaytmNativeReceipt([string]$Path){
 $null=Assert-PaytmAccountPath $Path
 if((Get-FileHash -LiteralPath $Path).Hash -cne '0297626FF9C6FB8A385F7C03E98D0DF993FF0390C937959D649E2EA724283897'){throw 'HOST_PROBE_RECEIPT_MISMATCH'}
 Read-PaytmHostJson $Path 65536
}
function Assert-PaytmAgentProbeIdle([string]$Id){
 $c=Get-PaytmHostContract;$task=Get-PaytmOwnedHostTask $Id
 if([string]$task.State -cne 'Ready' -or (Get-ScheduledTaskInfo -TaskName $c.name -TaskPath '\').LastTaskResult -ne 1){throw 'HOST_PROBE_TASK_NOT_IDLE'}
 if(@(Get-Process -ErrorAction Stop|Where-Object Id -EQ 14544).Count){throw 'HOST_PROBE_OLD_PROCESS_PRESENT'}
 $control=Read-PaytmHostJson (Join-Path $c.root 'control.json');Assert-PaytmHostControl $control $Id
 if($control.mode -cne 'LOCKED' -or (Read-PaytmTransportControl $c.root $Id) -cne 'ENABLED'){throw 'HOST_PROBE_CONTROL_DRIFT'}
 foreach($name in @('startup-failure.json','status.json','blocked.json')){
  $p=Assert-PaytmAccountPath (Join-Path $c.work $name)
  if($name -eq 'blocked.json' -and -not(Test-Path -LiteralPath $p)){continue}
  $v=Read-PaytmHostJson $p
  if($v.instanceId -cne 'e2398de523db4fbd8e7e8f8c0eb246de' -or $v.failure -cne 'HOST_AGENT_UNAVAILABLE'){throw 'HOST_PROBE_FAILURE_CHANGED'}
  if($name -ne 'blocked.json' -and ($v.installationId -cne $Id -or $v.processId -ne 14544)){throw 'HOST_PROBE_FAILURE_IDENTITY'}
  if($name -eq 'status.json' -and $v.phase -cne 'BLOCKED'){throw 'HOST_PROBE_STATUS_NOT_BLOCKED'}
 }
 $checkpoint=Read-PaytmHostJson (Assert-PaytmAccountPath (Join-Path $c.root 'session-checkpoint.json'))
 Assert-PaytmSessionCheckpoint $checkpoint
 if($checkpoint.runId -cne '3bec334f1adf423c986286eedd6697f2' -or $checkpoint.nextPhase -cne 'AfterLogoff' -or $checkpoint.before.worker.instanceId -cne 'e2398de523db4fbd8e7e8f8c0eb246de'){throw 'HOST_PROBE_CHECKPOINT_DRIFT'}
 Assert-PaytmTransportListener (Get-PaytmTransportListeners)
}
function Invoke-PaytmNativeRecovery($Receipt,[string]$ReviewPath,[string]$SourceDirectory){
 $null=Assert-PaytmNativeReceipt $ReviewPath;$c=Get-PaytmHostContract
 $m=Assert-PaytmTransportInstallationSources $Receipt;$id=$m.installationId
 Add-Type -Path (Join-Path $c.root 'transport.dll')
 Assert-PaytmAgentProbeIdle $id
 $sources=@{'PaytmSupervisorNative.cs'='new-native.cs';'PaytmSupervisorHost.ps1'='new-host.ps1';'RunPaytmGatewaySupervisor.ps1'='new-runner.ps1';'PaytmSupervisorTransport.ps1'='new-transport.ps1'}
 foreach($name in $sources.Keys){if(-not(Test-PaytmAgentProbeSourceHash $name (Get-FileHash -LiteralPath (Join-Path $SourceDirectory $name)).Hash)){throw 'HOST_PROBE_SOURCE_NOT_REVIEWED'}}
 $held=$null
 try{
  $held=[IO.File]::Open((Assert-PaytmAccountPath (Join-Path $c.work 'instance.lock')),'OpenOrCreate','ReadWrite','None')
  Assert-PaytmAgentProbeIdle $id
  $backup=Assert-PaytmAccountPath (Join-Path $c.root ('agent-probe-recovery-'+$report.runId))
  if(Test-Path -LiteralPath $backup){throw 'HOST_PROBE_ARCHIVE_EXISTS'}
  $null=New-Item -ItemType Directory -Path $backup;Set-PaytmAccountDirectoryAcl $backup (Get-PaytmKeyContract).accountSid
  $report.nativeRecovery=[ordered]@{backupPath=$backup;backupHashes=@{};backupVerified=$false;updatedFiles=@();manifestUpdated=$false;markersArchived=$false;checkpointArchived=$false;startAttempts=0;healthy=$false;keyImported=$false}
  $names=@('native.dll','host.ps1','runner.ps1','transport.ps1','manifest.json','control.json','transport-control.json','session-checkpoint.json','startup-failure.json','status.json')
  if(Test-Path -LiteralPath (Join-Path $c.work 'blocked.json')){$names+='blocked.json'}
  foreach($name in $names){
   $dir=if($name -in @('startup-failure.json','status.json','blocked.json')){$c.work}else{$c.root}
   $from=Assert-PaytmAccountPath (Join-Path $dir $name);$hash=(Get-FileHash -LiteralPath $from).Hash
   Copy-Item -LiteralPath $from -Destination (Join-Path $backup $name) -ErrorAction Stop
   if((Get-FileHash -LiteralPath (Join-Path $backup $name)).Hash -cne $hash){throw 'HOST_PROBE_BACKUP_MISMATCH'}
   $report.nativeRecovery.backupHashes[$name]=$hash
  }
  $report.nativeRecovery.backupVerified=$true;Save-NativeRecoveryReport
  foreach($name in $sources.Keys){
   $dest=Join-Path $backup $sources[$name];Copy-Item -LiteralPath (Join-Path $SourceDirectory $name) -Destination $dest
   if(-not(Test-PaytmAgentProbeSourceHash $name (Get-FileHash -LiteralPath $dest).Hash)){throw 'HOST_PROBE_STAGING_DRIFT'}
  }
  Invoke-PaytmNativeBuild (Join-Path $backup 'new-native.cs') (Join-Path $backup 'new-native.dll')
  Assert-PaytmAgentProbeIdle $id;$null=Assert-PaytmTransportInstallationSources $Receipt
  foreach($name in $names){
   $dir=if($name -in @('startup-failure.json','status.json','blocked.json')){$c.work}else{$c.root}
   if((Get-FileHash -LiteralPath (Join-Path $dir $name)).Hash -cne $report.nativeRecovery.backupHashes[$name]){throw 'HOST_PROBE_STATE_CHANGED'}
  }
  $report.nativeRecoveryAttempted=$true;Save-NativeRecoveryReport
  Set-PaytmHostControl $id STOP
  foreach($name in @('native.dll','host.ps1','runner.ps1','transport.ps1')){
   $from=Join-Path $backup ('new-'+$name);$hash=(Get-FileHash -LiteralPath $from).Hash
   $tmp=Assert-PaytmAccountPath (Join-Path $c.root ($name+'.'+$report.runId+'.tmp'))
   if(Test-Path -LiteralPath $tmp){throw 'HOST_PROBE_TEMP_EXISTS'}
   Copy-Item -LiteralPath $from -Destination $tmp
   if((Get-FileHash -LiteralPath $tmp).Hash -cne $hash){throw 'HOST_PROBE_COPY_DRIFT'}
   [IO.File]::Replace($tmp,(Join-Path $c.root $name),[Management.Automation.Language.NullString]::Value)
   $m.hashes.$name=$hash;$report.nativeRecovery.updatedFiles+= $name
  }
  Write-PaytmHostJson (Join-Path $c.root 'manifest.json') $m
  $null=Assert-PaytmTransportInstallationSources $Receipt;$report.nativeRecovery.manifestUpdated=$true
  foreach($name in @('startup-failure.json','status.json','blocked.json','session-checkpoint.json')){
   if($name -notin $names){continue}
   $dir=if($name -eq 'session-checkpoint.json'){$c.root}else{$c.work}
   $path=Assert-PaytmAccountPath (Join-Path $dir $name)
   if((Get-FileHash -LiteralPath $path).Hash -cne $report.nativeRecovery.backupHashes[$name]){throw 'HOST_PROBE_MARKER_DRIFT'}
   Remove-Item -LiteralPath $path -ErrorAction Stop
  }
  $report.nativeRecovery.markersArchived=$true;$report.nativeRecovery.checkpointArchived=$true
  Set-PaytmHostControl $id LOCKED;$null=Assert-PaytmInstalledTransport $Receipt
 }finally{if($held){$held.Dispose()}}
 $report.nativeRecovery.startAttempts=1;Save-NativeRecoveryReport
 Start-ScheduledTask -TaskName $c.name -TaskPath '\' -ErrorAction Stop
 $report.nativeRecovery.first=Wait-PaytmManagedHost $id TRANSPORT_READY 'e2398de523db4fbd8e7e8f8c0eb246de' -AwaitScheduledStart
 $report.nativeRecovery.healthy=$true;Save-NativeRecoveryReport
}
