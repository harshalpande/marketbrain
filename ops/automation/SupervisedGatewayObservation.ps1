# Read-only, fixed-task diagnostics. Never return task arguments, event messages or credentials.
function Get-SupervisedGatewayTaskObservation {
 $r=@{readOnly=$true;ordersEnabled=$false;taskChanged=$false}
 try {
  $name='MarketBrain-Gateway-Supervisor-v1'
  $t=Get-ScheduledTask -TaskName $name -TaskPath '\' -ErrorAction Stop
  $i=Get-ScheduledTaskInfo -TaskName $name -TaskPath '\' -ErrorAction Stop
  $r.task=@{state=[string]$t.State;lastTaskResult=[long]$i.LastTaskResult;lastRunTime=$i.LastRunTime.ToString('o');missedRuns=[int]$i.NumberOfMissedRuns;settings=@{}}
  foreach($n in @('Enabled','AllowDemandStart','DisallowStartIfOnBatteries','StopIfGoingOnBatteries','RunOnlyIfIdle','RunOnlyIfNetworkAvailable','StartWhenAvailable')){$r.task.settings[$n]=[bool]$t.Settings.$n}
  $r.task.multipleInstances=[string]$t.Settings.MultipleInstances
  $r.task.executionTimeLimit=[string]$t.Settings.ExecutionTimeLimit
  $r.task.idle=@{stopOnIdleEnd=[bool]$t.Settings.IdleSettings.StopOnIdleEnd;restartOnIdle=[bool]$t.Settings.IdleSettings.RestartOnIdle}
 }catch{$r.taskError=$_.Exception.GetBaseException().GetType().Name}
 try {
  $r.batteries=@(Get-CimInstance Win32_Battery -ErrorAction Stop|Select-Object -First 4|ForEach-Object {@{batteryStatus=[int]$_.BatteryStatus;estimatedChargeRemaining=[int]$_.EstimatedChargeRemaining}})
 }catch{$r.batteryError=$_.Exception.GetBaseException().GetType().Name}
 try {
  $log=Get-WinEvent -ListLog 'Microsoft-Windows-TaskScheduler/Operational' -ErrorAction Stop
  $r.eventLogEnabled=[bool]$log.IsEnabled
  if($log.IsEnabled){
   # Filter by the fixed task on the event service; do not return arbitrary message text.
   $filter="*[System[TimeCreated[timediff(@SystemTime) <= 86400000]]] and *[EventData[Data[@Name='TaskName']='\MarketBrain-Gateway-Supervisor-v1']]"
   $r.events=@(Get-WinEvent -LogName $log.LogName -FilterXPath $filter -MaxEvents 24 -ErrorAction Stop|ForEach-Object {
    $e=@{id=$_.Id;recordId=$_.RecordId;timeCreated=$_.TimeCreated.ToString('o');codes=@{}}
    $xml=[xml]$_.ToXml()
    foreach($d in $xml.Event.EventData.Data){if($d.Name -in @('ResultCode','ErrorCode') -and [string]$d.'#text' -match '^(0x[0-9a-fA-F]+|[0-9]+)$'){$e.codes[$d.Name]=[string]$d.'#text'}}
    $e
   })
  }
 }catch{$r.eventError=$_.Exception.GetBaseException().GetType().Name}
 return $r
}
