# Controller helpers; staging remains disabled and does not start gateway or collector.
function Get-DurableCollectorDefinition([string]$WorkerHash) {
 if($WorkerHash -cnotmatch '^[A-F0-9]{64}$'){throw 'COLLECTOR_WORKER_HASH'}
 $root='C:\ProgramData\MarketBrainPaytmHealth\collector-v1'
 $command="if((Get-FileHash -LiteralPath '$root\worker.ps1').Hash -cne '$WorkerHash'){exit 9};&([scriptblock]::Create([IO.File]::ReadAllText('$root\worker.ps1')))"
 @{name='MarketBrain-Health-Collector-v1';root=$root;work='C:\ProgramData\MarketBrainPaytmHealth\collector-work-v1';exe='C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe';arguments=('-NoLogo -NoProfile -NonInteractive -EncodedCommand '+[Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($command)))}
}
function Assert-DurableCollectorTask($Task,$Definition) {
 $sid=Resolve-TimeAccountTaskSid ([string]$Task.Principal.UserId)
 if($Task.TaskName -cne $Definition.name -or $Task.TaskPath -cne '\' -or $sid -cne 'S-1-5-21-3041730714-102984520-3202743044-1011' -or [string]$Task.Principal.LogonType -cne 'Password' -or [string]$Task.Principal.RunLevel -cne 'Limited'){throw 'COLLECTOR_TASK_IDENTITY'}
 if($Task.Actions.Count -ne 1 -or $Task.Actions[0].Execute -ine $Definition.exe -or $Task.Actions[0].Arguments -cne $Definition.arguments -or $Task.Actions[0].WorkingDirectory -cne $Definition.root){throw 'COLLECTOR_TASK_ACTION'}
 if($Task.Settings.Enabled -or [string]$Task.State -cne 'Disabled' -or $Task.Triggers.Count -ne 1 -or $Task.Triggers[0].CimClass.CimClassName -cne 'MSFT_TaskBootTrigger' -or -not $Task.Triggers[0].Enabled){throw 'COLLECTOR_TASK_STARTUP'}
 if([string]$Task.Settings.MultipleInstances -cne 'IgnoreNew' -or $Task.Settings.RestartCount -ne 0 -or [Xml.XmlConvert]::ToTimeSpan($Task.Settings.ExecutionTimeLimit).TotalSeconds -ne 0 -or $Task.Settings.DisallowStartIfOnBatteries -or $Task.Settings.StopIfGoingOnBatteries -or -not $Task.Settings.StartWhenAvailable){throw 'COLLECTOR_TASK_SETTINGS'}
}
function New-DurableCollectorSource([string]$Installation) {
 if($Installation -cnotmatch '^[a-f0-9]{32}$'){throw 'COLLECTOR_INSTALLATION_ID'}
 $root='C:\ProgramData\MarketBrainPaytmHealth\collector-v1';$work='C:\ProgramData\MarketBrainPaytmHealth\collector-work-v1'
 $preamble=[IO.File]::ReadAllText((Join-Path $PSScriptRoot 'PaytmTimeObservation.ps1'))+"`n"+[IO.File]::ReadAllText((Join-Path $PSScriptRoot 'PaytmDurableCollector.ps1'))+"`n"
 $preamble+="if(-not (Read-DurableCollectorControl '$root\control.json' '$Installation')){exit 0}`n"
 $preamble+="`$collectorLease=[IO.File]::Open('$work\instance.lock','Open','ReadWrite','None')`n"
 $source=[IO.File]::ReadAllText((Join-Path $PSScriptRoot 'PaytmHealthScheduledWorker.ps1'))
 $token=Get-HealthScheduledTokenSource
 foreach($name in @('PaytmTimeServiceRepair.ps1','PaytmLiveHealthCollector.ps1','PaytmHealthCollectorCore.ps1')){$token+="`n"+[IO.File]::ReadAllText((Join-Path $PSScriptRoot $name))}
 $token+=@'

 $token=$null
 try{
  $token=Unprotect-HealthToken ([IO.File]::ReadAllBytes($tokenRoot+'\health-token.dpapi'))
  $r['collector']=Invoke-DurableCollectorLoop $token $a $r.applicationBootId {Read-DurableCollectorControl '__ROOT__\control.json' '__RUN__'} {param($v) Write-DurableCollectorStatus '__WORK__\status.json' $v}
  if($r.collector.failure -or -not $r.collector.finalHealthRevoked){throw 'COLLECTOR_RUNTIME_FAILED'}
 }finally{$token=$null}
'@
 $source=$source.Replace('__TOKEN_CHECK__',$token)
 # One final report is atomically replaced, not an unbounded history of files.
 $start=$source.IndexOf(' $bytes=[Text.Encoding]::UTF8.GetBytes')
 $end=$source.IndexOf("`n}",$start)
 if($start -lt 0 -or $end -lt 0){throw 'COLLECTOR_TEMPLATE_CHANGED'}
 $source=$source.Substring(0,$start)+" Write-DurableCollectorStatus '__WORK__\final.json' `$r`n `$collectorLease.Dispose()"+$source.Substring($end)
 return ($preamble+$source).Replace('__RUN__',$Installation).Replace('__ROOT__',$root).Replace('__WORK__',$work).Replace('__KNOWN__',($root.Replace('\','/')+'/known_hosts'))
}
