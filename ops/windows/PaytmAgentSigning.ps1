#Requires -Version 7.0
# Definitions only. Preserve the stopped production worker and its unfinished session checkpoint.
function Assert-PaytmAgentSigningReceipt([string]$Path){
 $null=Assert-PaytmAccountPath $Path
 if((Get-FileHash -LiteralPath $Path).Hash -cne '097FE3F105F7579DF20BDC9DE1F5603B43AABF16CC523C5A97026A5E600032D4'){throw 'SCHEDULE_AGENT_RECEIPT_NOT_REVIEWED'}
 $r=Read-PaytmHostJson $Path 65536
 if($r.runId -cne 'd1938ba2c01d4a1b9759e2b81d972fed' -or $r.status -cne 'AGENT_EVIDENCE_CAPTURED_GATEWAY_RECOVERY_PENDING' -or $r.failure -or -not $r.checkpointUnchanged -or -not $r.serviceQueriesComplete){throw 'SCHEDULE_AGENT_RECEIPT_INVALID'}
 [pscustomobject]@{runId=$r.runId;checkpointHash=$r.checkpointAfter.sha256;historicalCauseEstablished=$false}
}
function Get-PaytmAgentSigningSnapshot {
 $c=Get-PaytmHostContract;$id='ea8b91471cf048aa97a0f6b939b355c7'
 $tasks=@(Get-PaytmProbeTask $c.name)
 if($tasks.Count -ne 1){throw 'SCHEDULE_AGENT_SUPERVISOR_MISSING'}
 Assert-PaytmHostTask $tasks[0] $id $true
 $info=Get-ScheduledTaskInfo -TaskName $c.name -TaskPath '\' -ErrorAction Stop
 if([string]$tasks[0].State -cne 'Ready' -or $info.LastTaskResult -ne 1){throw 'SCHEDULE_AGENT_SUPERVISOR_STATE_CHANGED'}
 if(@(Get-Process -ErrorAction Stop|Where-Object Id -EQ 13636).Count){throw 'SCHEDULE_AGENT_OLD_PROCESS_PRESENT'}
 $r=[ordered]@{taskState=[string]$tasks[0].State;taskLastResult=[long]$info.LastTaskResult;taskLastRunUtc=$info.LastRunTime.ToUniversalTime().ToString('o');oldProcessAbsent=$true;hashes=[ordered]@{}}
 foreach($name in @('manifest.json','control.json','transport-control.json','session-checkpoint.json','startup-failure.json','blocked.json','status.json')){
  $dir=if($name -in @('startup-failure.json','blocked.json','status.json')){$c.work}else{$c.root}
  $path=Assert-PaytmAccountPath (Join-Path $dir $name)
  $r.hashes[$name]=(Get-FileHash -LiteralPath $path -ErrorAction Stop).Hash
 }
 $control=Read-PaytmHostJson (Join-Path $c.root 'control.json')
 if($control.installationId -cne $id -or $control.mode -cne 'LOCKED'){throw 'SCHEDULE_AGENT_AUTHORITY_CHANGED'}
 $blocked=Read-PaytmHostJson (Join-Path $c.work 'blocked.json')
 if($blocked.instanceId -cne 'c066052a24f1456895792ee98dda78ac' -or $blocked.failure -cne 'HOST_AGENT_UNAVAILABLE'){throw 'SCHEDULE_AGENT_FAILURE_CHANGED'}
 [pscustomobject]$r
}
