#Requires -Version 7.0
# Read-only, bounded projection. Never copy arbitrary exception text or key material.
function ConvertTo-PaytmWorkerEvidence($Value){
 $out=[ordered]@{}
 foreach($n in @('version','transportVersion','processId','sessionId','sequence','elapsedSeconds','childProcessId','childStartTicks','httpStatus')){
  $v=$Value.$n;if($v -is [ValueType] -and $v -isnot [bool] -and $v -isnot [DateTime] -and "$v" -match '^\d+(\.\d+)?$'){$out[$n]=$v}
 }
 foreach($n in @('identityVerified','jobContained','agentIdentityVerified','signingVerified','privateCopyAbsent','networkContacted','transportEnabled','brokerReady','ordersEnabled','denialsVerified')){if($Value.$n -is [bool]){$out[$n]=$Value.$n}}
 foreach($n in @('installationId','instanceId')){if([string]$Value.$n -cmatch '^[a-f0-9]{32}$'){$out[$n]=[string]$Value.$n}}
 foreach($n in @('phase','stage','failure','mode')){
  $v=$Value.$n
  if($null -eq $v){$out[$n]=$null}elseif($v -is [string] -and $v -cmatch '^[A-Z][A-Z0-9_]{0,95}$'){$out[$n]=$v}else{$out[$n]='UNRECOGNIZED_VALUE_REDACTED'}
 }
 if($Value.observedUtc -is [DateTime]){$out.observedUtc=$Value.observedUtc.ToUniversalTime().ToString('o')}
 elseif($Value.observedUtc -is [string] -and $Value.observedUtc -cmatch '^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(\.\d{1,7})?Z$'){$out.observedUtc=$Value.observedUtc}
 $d=[ordered]@{}
 foreach($n in @('type','outerType')){if([string]$Value.details.$n -cmatch '^[A-Za-z][A-Za-z0-9.]{0,95}$'){$d[$n]=[string]$Value.details.$n}}
 foreach($n in @('hresult','line','nativeErrorCode')){if($Value.details.$n -is [int] -or $Value.details.$n -is [long]){$d[$n]=$Value.details.$n}}
 if($d.Count){$out.details=$d}
 $s=[ordered]@{}
 foreach($n in @('attempts','failures','closedOutageSeconds','firstReadySeconds','lastHealthSeconds','lastSeconds','retryAtSeconds')){if($Value.transportState.$n -is [int] -or $Value.transportState.$n -is [long]){$s[$n]=$Value.transportState.$n}}
 foreach($n in @('phase','reason','action')){if([string]$Value.transportState.$n -cmatch '^[A-Z][A-Z0-9_]{0,95}$'){$s[$n]=[string]$Value.transportState.$n}}
 if($s.Count){$out.transportState=$s}
 [pscustomobject]$out
}
function Get-PaytmWorkerEvidenceFile([string]$Path){
 $entry=[ordered]@{present=$null;readSucceeded=$false;errorType=$null}
 try{
  $null=Assert-PaytmAccountPath $Path
  $entry.present=Test-Path -LiteralPath $Path -ErrorAction Stop
  if($entry.present){
   $item=Get-Item -LiteralPath $Path -ErrorAction Stop
   $entry.length=$item.Length;$entry.lastWriteUtc=$item.LastWriteTimeUtc.ToString('o')
   $value=Read-PaytmHostJson $Path 16384
   $entry.value=ConvertTo-PaytmWorkerEvidence $value;$entry.readSucceeded=$true
  }
 }catch{$entry.errorType=$_.Exception.GetBaseException().GetType().Name}
 [pscustomobject]$entry
}
function Get-PaytmWorkerFailureEvidence {
 $c=Get-PaytmHostContract
 $out=[ordered]@{observedUtc=[DateTime]::UtcNow.ToString('o');readOnly=$true;files=@{};controls=@{};task=@{};process=@{};heartbeatAdvanced=$false;currentHealthEstablished=$false}
 foreach($name in @('blocked.json','startup-failure.json','status.json')){$out.files[$name]=Get-PaytmWorkerEvidenceFile (Join-Path $c.work $name)}
 foreach($name in @('control.json','transport-control.json')){$out.controls[$name]=Get-PaytmWorkerEvidenceFile (Join-Path $c.root $name)}
 try{
  $tasks=@(Get-PaytmProbeTask $c.name)
  if($tasks.Count -ne 1){throw 'HOST_TASK_MISSING'}
  $t=$tasks[0];$out.task.state=[string]$t.State;$out.task.enabled=[bool]$t.Settings.Enabled
  Assert-PaytmHostTask $t 'ea8b91471cf048aa97a0f6b939b355c7' ([bool]$t.Settings.Enabled)
  $out.task.definitionVerified=$true
  $info=Get-ScheduledTaskInfo -TaskName $c.name -TaskPath '\' -ErrorAction Stop
  $out.task.lastResult=$info.LastTaskResult;$out.task.lastRunUtc=$info.LastRunTime.ToUniversalTime().ToString('o')
 }catch{$out.task.errorType=$_.Exception.GetBaseException().GetType().Name}
 $first=$out.files['status.json'].value
 if($first.processId -gt 0){
  $p=$null;$out.process.exists=$null
  try{
   $p=Get-Process -Id $first.processId -ErrorAction Stop
   $out.process.pid=$first.processId;$out.process.exists=$true;$out.process.sessionId=$p.SessionId
   $out.process.expectedExecutable=($p.Path -ieq $c.executable);$out.process.startUtc=$p.StartTime.ToUniversalTime().ToString('o')
  }catch{
   if($_.FullyQualifiedErrorId -like 'NoProcessFoundForGivenId,*'){$out.process.exists=$false}
   $out.process.errorType=$_.Exception.GetBaseException().GetType().Name
  }finally{if($p){$p.Dispose()}}
 }
 Start-Sleep -Seconds 2
 $out.statusAfter=Get-PaytmWorkerEvidenceFile (Join-Path $c.work 'status.json')
 $second=$out.statusAfter.value
 if($out.files['status.json'].readSucceeded -and $out.statusAfter.readSucceeded -and $first.instanceId -and $first.instanceId -ceq $second.instanceId -and $first.processId -eq $second.processId -and $second.sequence -gt $first.sequence){$out.heartbeatAdvanced=$true}
 # Advancing status alone does not prove listener ownership, task health or TLS.
 [pscustomobject]$out
}
