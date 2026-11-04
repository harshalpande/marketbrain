#Requires -Version 7.0
# Read-only, bounded projection. Never copy arbitrary exception text or key material.
function Get-PaytmEvidenceProperty($Value,[string]$Name){
 if($null -eq $Value){return $null}
 if($Value -is [Collections.IDictionary]){if($Value.Contains($Name)){return $Value[$Name]};return $null}
 if($Value -is [pscustomobject]){
  $property=$Value.PSObject.Properties[$Name]
  if($null -ne $property){return $property.Value}
 }
 return $null
}
function ConvertTo-PaytmWorkerEvidence($Value){
 $out=[ordered]@{}
 foreach($n in @('version','transportVersion','processId','sessionId','sequence','elapsedSeconds','childProcessId','childStartTicks','httpStatus')){
  $v=Get-PaytmEvidenceProperty $Value $n;if($v -is [ValueType] -and $v -isnot [bool] -and $v -isnot [DateTime] -and "$v" -match '^\d+(\.\d+)?$'){$out[$n]=$v}
 }
 foreach($n in @('identityVerified','jobContained','agentIdentityVerified','signingVerified','privateCopyAbsent','networkContacted','transportEnabled','brokerReady','ordersEnabled','denialsVerified')){$v=Get-PaytmEvidenceProperty $Value $n;if($v -is [bool]){$out[$n]=$v}}
 foreach($n in @('installationId','instanceId')){$v=Get-PaytmEvidenceProperty $Value $n;if([string]$v -cmatch '^[a-f0-9]{32}$'){$out[$n]=[string]$v}}
 foreach($n in @('phase','stage','failure','mode')){
  $v=Get-PaytmEvidenceProperty $Value $n
  if($null -eq $v){$out[$n]=$null}elseif($v -is [string] -and $v -cmatch '^[A-Z][A-Z0-9_]{0,95}$'){$out[$n]=$v}else{$out[$n]='UNRECOGNIZED_VALUE_REDACTED'}
 }
 $observed=Get-PaytmEvidenceProperty $Value observedUtc
 if($observed -is [DateTime]){$out.observedUtc=$observed.ToUniversalTime().ToString('o')}
 elseif($observed -is [string] -and $observed -cmatch '^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(\.\d{1,7})?Z$'){$out.observedUtc=$observed}
 $details=Get-PaytmEvidenceProperty $Value details;$transport=Get-PaytmEvidenceProperty $Value transportState
 $d=[ordered]@{}
 foreach($n in @('type','outerType')){$v=Get-PaytmEvidenceProperty $details $n;if([string]$v -cmatch '^[A-Za-z][A-Za-z0-9.]{0,95}$'){$d[$n]=[string]$v}}
 foreach($n in @('hresult','line','nativeErrorCode')){$v=Get-PaytmEvidenceProperty $details $n;if($v -is [int] -or $v -is [long]){$d[$n]=$v}}
 if($d.Count){$out.details=$d}
 $s=[ordered]@{}
 foreach($n in @('attempts','failures','closedOutageSeconds','firstReadySeconds','lastHealthSeconds','lastSeconds','retryAtSeconds')){$v=Get-PaytmEvidenceProperty $transport $n;if($v -is [int] -or $v -is [long]){$s[$n]=$v}}
 foreach($n in @('phase','reason','action')){$v=Get-PaytmEvidenceProperty $transport $n;if([string]$v -cmatch '^[A-Z][A-Z0-9_]{0,95}$'){$s[$n]=[string]$v}}
 if($s.Count){$out.transportState=$s}
 $ssh=Get-PaytmEvidenceProperty $Value lastSshObservation
 if($null -ne $ssh){
  $o=[ordered]@{}
  foreach($n in @('exited','stderrDrained','authenticated')){$v=Get-PaytmEvidenceProperty $ssh $n;if($v -is [bool]){$o[$n]=$v}}
  foreach($n in @('version','stderrCharacters')){$v=Get-PaytmEvidenceProperty $ssh $n;if(($v -is [int] -or $v -is [long]) -and $v -ge 0){$o[$n]=$v}}
  $v=Get-PaytmEvidenceProperty $ssh stderrSha256;if([string]$v -cmatch '^[A-F0-9]{64}$'){$o.stderrSha256=$v}
  $v=Get-PaytmEvidenceProperty $ssh reason;if([string]$v -cin @('UNKNOWN','NETWORK_UNAVAILABLE','HOST_KEY_CHANGED','KEY_DENIED','LISTENER_CONFLICT','DESTINATION_DRIFT')){$o.reason=$v}
  $allowed=@('TCP_CONNECT_DENIED','TCP_CONNECT_UNKNOWN','TCP_CONNECT_TIMEOUT','TCP_CONNECT_REFUSED','NETWORK_UNREACHABLE','CONNECTION_RESET','BROKEN_PIPE','KEX_CLOSED','SSH_TIMEOUT','HOST_KEY_FAILURE','PERMISSION_DENIED','SIGNING_FAILURE','LISTENER_FAILURE','DESTINATION_DENIED')
  $o.tags=@((Get-PaytmEvidenceProperty $ssh tags)|Where-Object {$_ -is [string] -and $_ -cin $allowed}|Select-Object -First 14)
  $out.lastSshObservation=$o
  foreach($n in @('lastSshAttempt','lastSshElapsedSeconds')){$v=Get-PaytmEvidenceProperty $Value $n;if(($v -is [int] -or $v -is [long]) -and $v -ge 0){$out[$n]=$v}}
 }
 [pscustomobject]$out
}
function Get-PaytmWorkerEvidenceFile([string]$Path){
 $entry=[ordered]@{present=$null;readSucceeded=$false;errorType=$null;value=$null}
 try{
  $null=Assert-PaytmAccountPath $Path
  $entry.present=Test-Path -LiteralPath $Path -ErrorAction Stop
  if($entry.present){
   $item=Get-Item -LiteralPath $Path -ErrorAction Stop
   $entry.length=$item.Length;$entry.lastWriteUtc=$item.LastWriteTimeUtc.ToString('o')
   $value=Read-PaytmHostJson $Path 16384
   if($null -eq $value -or ($value -isnot [Collections.IDictionary] -and $value -isnot [pscustomobject])){throw 'HOST_EVIDENCE_OBJECT_REQUIRED'}
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
 $workerPid=Get-PaytmEvidenceProperty $first processId
 if(($workerPid -is [int] -or $workerPid -is [long]) -and $workerPid -gt 0 -and $workerPid -le [int]::MaxValue){
  $p=$null;$out.process.exists=$null
  try{
   $p=Get-Process -Id $workerPid -ErrorAction Stop
   $out.process.pid=$workerPid;$out.process.exists=$true;$out.process.sessionId=$p.SessionId
   $out.process.expectedExecutable=($p.Path -ieq $c.executable);$out.process.startUtc=$p.StartTime.ToUniversalTime().ToString('o')
  }catch{
   if($_.FullyQualifiedErrorId -like 'NoProcessFoundForGivenId,*'){$out.process.exists=$false}
   $out.process.errorType=$_.Exception.GetBaseException().GetType().Name
  }finally{if($p){$p.Dispose()}}
 }
 Start-Sleep -Seconds 2
 $out.statusAfter=Get-PaytmWorkerEvidenceFile (Join-Path $c.work 'status.json')
 $second=$out.statusAfter.value
 $firstId=Get-PaytmEvidenceProperty $first instanceId;$secondId=Get-PaytmEvidenceProperty $second instanceId
 $secondPid=Get-PaytmEvidenceProperty $second processId
 $firstSequence=Get-PaytmEvidenceProperty $first sequence;$secondSequence=Get-PaytmEvidenceProperty $second sequence
 if($out.files['status.json'].readSucceeded -and $out.statusAfter.readSucceeded -and $firstId -and $firstId -ceq $secondId -and
    $null -ne $workerPid -and $workerPid -eq $secondPid -and $null -ne $firstSequence -and $null -ne $secondSequence -and $secondSequence -gt $firstSequence){$out.heartbeatAdvanced=$true}
 # Advancing status alone does not prove listener ownership, task health or TLS.
 [pscustomobject]$out
}
