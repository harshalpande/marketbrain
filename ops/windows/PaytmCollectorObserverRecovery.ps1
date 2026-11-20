function Assert-CollectorObserverTask($Task,[string]$ExpectedArguments){
 if($Task.TaskName -cne 'MarketBrain-Time-Observer-v1' -or $Task.TaskPath -cne '\' -or $Task.Description -cne 'MarketBrain fixed read-only Windows time observer v1'){throw 'UPGRADE_OBSERVER_OWNERSHIP'}
 if($Task.Principal.UserId -notin @('SYSTEM','S-1-5-18') -or [string]$Task.Principal.LogonType -cne 'ServiceAccount' -or [string]$Task.Principal.RunLevel -cne 'Highest'){throw 'UPGRADE_OBSERVER_IDENTITY'}
 if($Task.Actions.Count -ne 1 -or $Task.Actions[0].Execute -ine 'C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe' -or $Task.Actions[0].Arguments -cne $ExpectedArguments -or $Task.Actions[0].WorkingDirectory){throw 'UPGRADE_OBSERVER_ACTION'}
 if(-not $Task.Settings.Enabled -or [string]$Task.State -notin @('Ready','Running') -or $Task.Triggers.Count -ne 1 -or $Task.Triggers[0].CimClass.CimClassName -cne 'MSFT_TaskBootTrigger' -or -not $Task.Triggers[0].Enabled -or [string]$Task.Settings.MultipleInstances -cne 'IgnoreNew' -or [Xml.XmlConvert]::ToTimeSpan($Task.Settings.ExecutionTimeLimit).TotalSeconds -ne 0){throw 'UPGRADE_OBSERVER_SETTINGS'}
}
function Restore-CollectorTimeObserver([switch]$Start){
 $root='C:\ProgramData\MarketBrainPaytmHealth\time-observer-v1';$path=Join-Path $root 'worker.ps1';$name='MarketBrain-Time-Observer-v1'
 Assert-TimeObservationAcl $root;Assert-TimeObservationAcl $path
 $hash='7129B3D3844D8E60F039ACE5F9701B100B2A849BB25AB3E5E653B18486BCFBE0'
 if((Get-FileHash -LiteralPath $path).Hash -cne $hash){throw 'UPGRADE_OBSERVER_WORKER_DRIFT'}
 $command="if((Get-FileHash -LiteralPath '$path').Hash -cne '$hash'){exit 9};&([scriptblock]::Create([IO.File]::ReadAllText('$path')))"
 $arguments='-NoLogo -NoProfile -NonInteractive -EncodedCommand '+[Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($command))
 $task=Get-ScheduledTask -TaskName $name -TaskPath '\' -ErrorAction Stop
 Assert-CollectorObserverTask $task $arguments
 $r=@{beforeState=[string]$task.State;lastResult=(Get-ScheduledTaskInfo -TaskName $name -TaskPath '\').LastTaskResult;started=$false;verified=$false}
 if([string]$task.State -ceq 'Ready'){
  if(-not $Start){return $r}
  Start-ScheduledTask -TaskName $name -TaskPath '\';$r.started=$true
 }
 $first=$null
 for($i=0;$i -lt 15;$i++){
  if(Test-Path -LiteralPath (Join-Path $root 'snapshot.json')){
   $v=Read-TimeObservation
   if($first -and $v.sequence -gt $first){$r.firstSequence=$first;$r.lastSequence=$v.sequence;$r.verified=$true;return $r}
   $first=$v.sequence
  }
  Start-Sleep -Seconds 1
 }
 throw 'UPGRADE_OBSERVER_NO_FRESH_SAMPLES'
}
