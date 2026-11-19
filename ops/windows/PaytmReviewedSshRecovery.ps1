#Requires -Version 7.0
# Reviewed November 19 UNKNOWN exit only. One operator-initiated recovery; original cause remains unknown.
function Assert-PaytmNativeReceipt([string]$Path){
 $null=Assert-PaytmAccountPath $Path
 $v=Read-PaytmHostJson $Path 65536
 if($v.runId -cne 'ba3fa8bf42434bd1bbb1115f63f4c457' -or $v.status -cne 'SCHEDULED_SIGNING_PASSED_SUPERVISOR_INSTALLATION_PENDING' -or $v.stage -cne 'COMPLETE' -or $v.failure -or $v.cleanupFailure){throw 'HOST_CURRENT_SIGNING_NOT_ACCEPTED'}
 foreach($n in @('productionStateUnchanged','taskRemoved','taskStarted')){if($v.$n -isnot [bool] -or -not $v.$n){throw 'HOST_CURRENT_SIGNING_PROOF'}}
 foreach($n in @('ordersEnabled','networkContacted','keyImported','agentChanged')){if($v.$n -isnot [bool] -or $v.$n){throw 'HOST_CURRENT_SIGNING_SCOPE'}}
 if($v.lastTaskResult -ne 0){throw 'HOST_CURRENT_SIGNING_EXIT'}
 Assert-PaytmScheduledWorker $v.worker $v.runId
 $expected=@{
  'TestPaytmGatewayScheduledSigning.ps1'='DBA1CD184F1EFFDA3AB145C052242E0DF0938FC5A0AA394137A5286A30BD0CBE'
  'Invoke-LocalGatewaySigning.ps1'='B7BB5904E24C2122ED425E4304EF09E8FC5A89A630464FBDF9975918C3C9A5E2'
  'PaytmGatewayScheduledProbe.ps1'='5D473A9F234E2AB5D4C8EE80DC57D370DBFB439A1F20379E880EB367778E47E3'
  'PaytmGatewayAccountRepair.ps1'='2AA61943D64AC10C5EF384C3F4BDEC16EBC75B5C676480CA7F8851EE0688142B'
  'PaytmGatewayKeyCustody.ps1'='2D0CEDE38E0B3314915FBDB1FEC69E328560F8EFC48DAE86F8BA4F40050FC463'
  'PaytmGatewayAccount.ps1'='9E64140801D7CC044117206E8411277F9CEA120614EACD5A8E90EE68016D405A'
 }
 if(@($v.sourceHashes.PSObject.Properties).Count -ne $expected.Count){throw 'HOST_CURRENT_SIGNING_SOURCE_COUNT'}
 foreach($n in $expected.Keys){if($v.sourceHashes.$n -cne $expected[$n]){throw 'HOST_CURRENT_SIGNING_SOURCE_DRIFT'}}
 $v
}
function Get-PaytmCurrentRecoverySnapshot {
 $c=Get-PaytmHostContract;$id='ea8b91471cf048aa97a0f6b939b355c7';$instance='75ecfd57f6874744a83611a856a8b161'
 $task=Get-PaytmOwnedHostTask $id
 $info=Get-ScheduledTaskInfo -TaskName $c.name -TaskPath '\' -ErrorAction Stop
 if([string]$task.State -cne 'Ready' -or $info.LastTaskResult -ne 1){throw 'HOST_CURRENT_TASK_CHANGED'}
 $control=Read-PaytmHostJson (Join-Path $c.root 'control.json');Assert-PaytmHostControl $control $id
 if($control.mode -cne 'LOCKED' -or (Read-PaytmTransportControl $c.root $id) -cne 'ENABLED'){throw 'HOST_CURRENT_CONTROL_CHANGED'}
 foreach($name in @('startup-failure.json','blocked.json','status.json')){
  $v=Read-PaytmHostJson (Join-Path $c.work $name)
  if($v.instanceId -cne $instance -or $v.failure -cne 'TRANSPORT_UNKNOWN'){throw 'HOST_CURRENT_INCIDENT_CHANGED'}
  if($name -ne 'blocked.json' -and ($v.installationId -cne $id -or $v.processId -ne 8716 -or $v.ordersEnabled -ne $false)){throw 'HOST_CURRENT_IDENTITY_CHANGED'}
  if($name -eq 'status.json' -and ($v.phase -cne 'BLOCKED' -or $v.sequence -ne 9319 -or $v.sessionId -ne 0)){throw 'HOST_CURRENT_HEARTBEAT_CHANGED'}
  if($name -eq 'status.json'){
   $ssh=$v.lastSshObservation
   if($v.lastSshAttempt -ne 13 -or $ssh.reason -cne 'UNKNOWN' -or $ssh.exited -ne $true -or $ssh.authenticated -ne $false -or $ssh.stderrDrained -ne $true -or $ssh.stderrCharacters -ne 557 -or @($ssh.tags).Count -ne 0 -or $ssh.stderrSha256 -cne '4A39CFA7D3593D41AB4AADC1A24976E7F67E6E404FE2CCD8AF68FF9A35F56E8D'){throw 'HOST_REVIEWED_SSH_EVIDENCE_CHANGED'}
  }
 }
 # instance.lock excludes an active worker; do not mistake a reused PID for that worker.
 $hashes=[ordered]@{}
 foreach($name in @('manifest.json','control.json','transport-control.json','startup-failure.json','blocked.json','status.json','session-checkpoint.json')){
  $dir=if($name -in @('startup-failure.json','blocked.json','status.json')){$c.work}else{$c.root}
  $path=Assert-PaytmAccountPath (Join-Path $dir $name)
  if($name -eq 'session-checkpoint.json' -and -not (Test-Path -LiteralPath $path)){$hashes[$name]='ABSENT'}else{$hashes[$name]=(Get-FileHash -LiteralPath $path -ErrorAction Stop).Hash}
 }
 [pscustomobject]@{hashes=$hashes;taskLastRunUtc=$info.LastRunTime.ToUniversalTime().ToString('o')}
}
function Assert-PaytmCurrentRecoverySnapshot($Before){
 $now=Get-PaytmCurrentRecoverySnapshot
 if(($now.hashes|ConvertTo-Json -Compress) -cne ($Before.hashes|ConvertTo-Json -Compress) -or $now.taskLastRunUtc -cne $Before.taskLastRunUtc){throw 'HOST_CURRENT_SNAPSHOT_DRIFT'}
 $now
}
function Invoke-PaytmNativeRecovery($Receipt,[string]$ReviewPath,[string]$SourceDirectory){
 $review=Assert-PaytmNativeReceipt $ReviewPath;$c=Get-PaytmHostContract
 $m=Assert-PaytmTransportInstallationSources $Receipt;$id=$m.installationId
 $before=Get-PaytmCurrentRecoverySnapshot
 Add-Type -Path (Join-Path $c.root 'transport.dll')
 Assert-PaytmTransportListener (Get-PaytmTransportListeners)
 $held=$null
 try{
  $held=[IO.File]::Open((Assert-PaytmAccountPath (Join-Path $c.work 'instance.lock')),'OpenOrCreate','ReadWrite','None')
  $snapshot=Assert-PaytmCurrentRecoverySnapshot $before
  $backup=Assert-PaytmAccountPath (Join-Path $c.root ('current-agent-recovery-'+$report.runId))
  if(Test-Path -LiteralPath $backup){throw 'HOST_AGENT_ARCHIVE_EXISTS'}
  $null=New-Item -ItemType Directory -Path $backup;Set-PaytmAccountDirectoryAcl $backup (Get-PaytmKeyContract).accountSid
  $report.nativeRecovery=[ordered]@{backupPath=$backup;backupHashes=@{};backupVerified=$false;markersArchived=$false;checkpointPreserved=$true;startAttempts=0;healthy=$false;installedCodeChanged=$false;keyImported=$false}
  foreach($name in $snapshot.hashes.Keys){
   if($snapshot.hashes[$name] -ceq 'ABSENT'){continue}
   $dir=if($name -in @('startup-failure.json','blocked.json','status.json')){$c.work}else{$c.root}
   $from=Assert-PaytmAccountPath (Join-Path $dir $name)
   Copy-Item -LiteralPath $from -Destination (Join-Path $backup $name) -ErrorAction Stop
   if((Get-FileHash -LiteralPath (Join-Path $backup $name)).Hash -cne $snapshot.hashes[$name]){throw 'HOST_AGENT_BACKUP_MISMATCH'}
   $report.nativeRecovery.backupHashes[$name]=$snapshot.hashes[$name]
  }
  $report.nativeRecovery.backupVerified=$true;Save-NativeRecoveryReport
  $null=Assert-PaytmCurrentRecoverySnapshot $before
  Assert-PaytmTransportListener (Get-PaytmTransportListeners)
  $report.nativeRecoveryAttempted=$true;Save-NativeRecoveryReport
  Set-PaytmHostControl $id STOP
  # Remove only this incident's three markers after complete verified copies exist. Keep any session checkpoint.
  foreach($name in @('startup-failure.json','blocked.json','status.json')){
   $dir=if($name -eq 'session-checkpoint.json'){$c.root}else{$c.work}
   $path=Assert-PaytmAccountPath (Join-Path $dir $name)
   if((Get-FileHash -LiteralPath $path).Hash -cne $snapshot.hashes[$name]){throw 'HOST_AGENT_FILE_CHANGED_BEFORE_ARCHIVE'}
   Remove-Item -LiteralPath $path -ErrorAction Stop
  }
  $report.nativeRecovery.markersArchived=$true;$report.nativeRecovery.checkpointPreserved=$true
  Set-PaytmHostControl $id LOCKED
  $null=Assert-PaytmInstalledTransport $Receipt
 }finally{if($held){$held.Dispose()}}
 $report.nativeRecovery.startAttempts=1;Save-NativeRecoveryReport
 Start-ScheduledTask -TaskName $c.name -TaskPath '\' -ErrorAction Stop
 $report.nativeRecovery.first=Wait-PaytmManagedHost $id TRANSPORT_READY '75ecfd57f6874744a83611a856a8b161' -AwaitScheduledStart
 $report.nativeRecovery.healthy=$true;Save-NativeRecoveryReport
}
