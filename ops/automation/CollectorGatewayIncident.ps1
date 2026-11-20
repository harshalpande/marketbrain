# One reviewed retry of the retained sign-out incident, never a general latch bypass.
function Assert-CollectorGatewayIncident($Status,$Blocked,$Startup){
 foreach($v in @($Status,$Blocked,$Startup)){if($v.instanceId -cne 'c592dec90f904b9da35d7f9dbf1b4226' -or $v.failure -cne 'TRANSPORT_CONFIG_UNAVAILABLE'){throw 'COLLECTOR_GATEWAY_INCIDENT_CHANGED'}}
 if($Status.installationId -cne 'ea8b91471cf048aa97a0f6b939b355c7' -or $Status.phase -cne 'BLOCKED' -or $Status.sequence -ne 157 -or $Status.processId -ne 8420 -or $Status.ordersEnabled -ne $false -or $Status.brokerReady -ne $false -or $Startup.stage -cne 'OBSERVATION_LOOP'){throw 'COLLECTOR_GATEWAY_INCIDENT_STATE'}
}
function Get-CollectorReviewedGatewayPreflight($Context,$Original){
 if($Original.failure -cne 'RECOVERY_NEW_INCIDENT'){throw $Original.failure}
 # Original preflight already verified all executable/configuration hashes before finding markers.
 $values=@{};$hashes=@{}
 foreach($name in @('status.json','blocked.json','startup-failure.json')){
  $p=Join-Path $Context.work $name
  if((Get-Item -LiteralPath $p).Attributes -band [IO.FileAttributes]::ReparsePoint){throw 'COLLECTOR_GATEWAY_REPARSE'}
  $values[$name]=Read-BoundedJson $p;$hashes[$name]=(Get-FileHash -LiteralPath $p).Hash
 }
 Assert-CollectorGatewayIncident $values['status.json'] $values['blocked.json'] $values['startup-failure.json']
 $task=Get-ScheduledTask -TaskName $Context.taskName -TaskPath '\';$info=Get-ScheduledTaskInfo -TaskName $Context.taskName -TaskPath '\'
 if([string]$task.State -cne 'Disabled' -or $task.Settings.Enabled -or $info.LastTaskResult -ne 1){throw 'COLLECTOR_GATEWAY_INCIDENT_TASK'}
 [xml]$saved=[IO.File]::ReadAllText((Join-Path $Context.root 'denial-recovery-649710f6-e95b-4ebc-831b-60a99d22ac69\task.xml'))
 [xml]$current=Export-ScheduledTask -TaskName $Context.taskName -TaskPath '\'
 if($saved.Task.Actions.OuterXml -cne $current.Task.Actions.OuterXml -or $saved.Task.Principals.OuterXml -cne $current.Task.Principals.OuterXml){throw 'COLLECTOR_GATEWAY_TASK_DRIFT'}
 if(@([Net.NetworkInformation.IPGlobalProperties]::GetIPGlobalProperties().GetActiveTcpListeners()|Where-Object Port -eq 18889).Count){throw 'COLLECTOR_GATEWAY_LISTENER_PRESENT'}
 $lease=[IO.File]::Open((Join-Path $Context.work 'instance.lock'),'Open','ReadWrite','None');$lease.Dispose()
 $Original.hashes['status.json']=$hashes['status.json'];$Original.incidentHashes=$hashes
 $Original.currentStatus=@{instanceId=$values['status.json'].instanceId;sequence=157;phase='BLOCKED';failure='TRANSPORT_CONFIG_UNAVAILABLE';ordersEnabled=$false;brokerReady=$false}
 $Original.passed=$true;$Original.failure=$null;$Original.reviewedIncident=$true
 return $Original
}
function Preserve-CollectorGatewayIncident($Context,$Before){
 if(-not $Before.reviewedIncident){return}
 if(-not $Context.guardXmlHash){throw 'COLLECTOR_GATEWAY_GUARD_REQUIRED'}
 foreach($name in @('status.json','blocked.json','startup-failure.json')){
  $src=Join-Path $Context.work $name;$dst=Join-Path $Context.archive $name
  if((Get-FileHash -LiteralPath $src).Hash -cne $Before.incidentHashes[$name] -or (Test-Path -LiteralPath $dst)){throw 'COLLECTOR_GATEWAY_INCIDENT_RACE'}
  Copy-Item -LiteralPath $src -Destination $dst -ErrorAction Stop
  if((Get-FileHash -LiteralPath $dst).Hash -cne $Before.incidentHashes[$name]){throw 'COLLECTOR_GATEWAY_BACKUP_HASH'}
 }
 foreach($name in @('blocked.json','startup-failure.json')){
  $p=Join-Path $Context.work $name
  if((Get-FileHash -LiteralPath $p).Hash -cne $Before.incidentHashes[$name]){throw 'COLLECTOR_GATEWAY_INCIDENT_RACE'}
  Remove-Item -LiteralPath $p -ErrorAction Stop
 }
 $Context.reviewedIncidentArchived=$true
}
