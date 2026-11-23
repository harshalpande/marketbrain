# Fixed supervised gateway reproduction. No task registration, password, key or policy changes.
function Invoke-SupervisedGatewayStartupProbe {
 $r=@{test='SUPERVISED_GATEWAY_STARTUP';passed=$false;ordersEnabled=$false;brokerCredentialsUsed=$false;started=$false;cleanupPassed=$false;samples=@();failure=$null}
 $root='C:\ProgramData\MarketBrainPaytmGateway\supervisor-v1'
 $work='C:\ProgramData\MarketBrainPaytmGateway\supervisor-work-v1'
 $name='MarketBrain-Gateway-Supervisor-v1';$installation='ea8b91471cf048aa97a0f6b939b355c7'
 function Read-StartupState([string]$Path){
  $s=$null;$reader=$null
  try{$s=[IO.File]::Open($Path,'Open','Read',([IO.FileShare]::ReadWrite -bor [IO.FileShare]::Delete));if($s.Length -gt 65536){throw 'STARTUP_STATE_TOO_LARGE'};$reader=[IO.StreamReader]::new($s);$reader.ReadToEnd()|ConvertFrom-Json}
  finally{if($reader){$reader.Dispose()};if($s){$s.Dispose()}}
 }
 function Get-StartupListeners {@([Net.NetworkInformation.IPGlobalProperties]::GetIPGlobalProperties().GetActiveTcpListeners()|Where-Object Port -EQ 18889)}
 try{
  $t=Get-ScheduledTask -TaskName $name -TaskPath '\' -ErrorAction Stop
  if($t.Description -cne "MarketBrain locked supervisor $installation" -or $t.State -ne 'Disabled'){throw 'STARTUP_TASK_NOT_DISABLED_OR_OWNED'}
  $text="&([scriptblock]::Create([IO.File]::ReadAllText('$root\runner.ps1')))"
  $expected='-NoLogo -NoProfile -NonInteractive -EncodedCommand '+[Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($text))
  $a=@($t.Actions)
  if($a.Count -ne 1 -or $a[0].Execute -cne 'C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe' -or $a[0].Arguments -cne $expected -or $a[0].WorkingDirectory -cne $root){throw 'STARTUP_TASK_ACTION_DRIFT'}
  $sid=$t.Principal.UserId
  if($sid -notmatch '^S-1-'){$sid=([Security.Principal.NTAccount]::new($sid)).Translate([Security.Principal.SecurityIdentifier]).Value}
  if($sid -cne 'S-1-5-21-3041730714-102984520-3202743044-1010' -or [string]$t.Principal.RunLevel -cne 'Limited' -or [string]$t.Principal.LogonType -cne 'Password'){throw 'STARTUP_PRINCIPAL_DRIFT'}
  $collector=Get-ScheduledTask -TaskName 'MarketBrain-Health-Collector-v1' -ErrorAction SilentlyContinue
  if($collector -and $collector.State -ne 'Disabled'){throw 'STARTUP_COLLECTOR_ACTIVE'}
  $m=Read-StartupState "$root/manifest.json"
  if($m.installationId -cne $installation -or $m.version -ne 1 -or $m.transportVersion -ne 1){throw 'STARTUP_MANIFEST_DRIFT'}
  foreach($file in @('host.ps1','runner.ps1','native.dll','transport.ps1','gateway.ps1','transport.dll')){if((Get-FileHash -LiteralPath "$root/$file").Hash -cne $m.hashes.$file){throw 'STARTUP_SOURCE_DRIFT'}}
  if((Read-StartupState "$root/control.json").mode -cne 'LOCKED' -or (Read-StartupState "$root/transport-control.json").mode -cne 'ENABLED'){throw 'STARTUP_CONTROL_DRIFT'}
  if((Test-Path "$work/blocked.json") -or (Test-Path "$work/startup-failure.json")){throw 'STARTUP_EXISTING_FAILURE'}
  if(@(Get-StartupListeners).Count){throw 'STARTUP_EXISTING_LISTENER'}
  $previous=(Read-StartupState "$work/status.json").instanceId
  $r.before=Get-SupervisedGatewayTaskObservation
  $r.started=$true
  $null=Enable-ScheduledTask -TaskName $name -TaskPath '\'
  Start-ScheduledTask -TaskName $name -TaskPath '\'
  $watch=[Diagnostics.Stopwatch]::StartNew();$lastSequence=$null
  do{
   Start-Sleep -Seconds 2
   $v=Read-StartupState "$work/status.json"
   $t=Get-ScheduledTask -TaskName $name -TaskPath '\';$i=Get-ScheduledTaskInfo -TaskName $name -TaskPath '\'
   $phase=if([string]$v.phase -cmatch '^[A-Z_]{1,60}$'){[string]$v.phase}else{'INVALID'}
   $fresh=($v.instanceId -cne $previous -and $v.instanceId -cmatch '^[a-f0-9]{32}$')
   $r.samples+=@{seconds=[math]::Round($watch.Elapsed.TotalSeconds,2);newInstance=$fresh;phase=$phase;sequence=[long]$v.sequence;taskState=[string]$t.State;taskResult=[long]$i.LastTaskResult}
   if($fresh -and $phase -eq 'BLOCKED'){throw 'STARTUP_WORKER_BLOCKED'}
   if($fresh -and $phase -eq 'TRANSPORT_READY' -and $v.ordersEnabled -eq $false -and $v.brokerReady -eq $false -and $t.State -eq 'Running' -and @(Get-StartupListeners).Count -gt 0){
    if($null -ne $lastSequence -and $v.sequence -gt $lastSequence){$r.passed=$true;break};$lastSequence=$v.sequence
   }
  }while($watch.Elapsed.TotalSeconds -lt 60)
  if(-not $r.passed){throw 'STARTUP_NO_FRESH_READY_HEARTBEAT'}
 }catch{$r.failure=if($_.Exception.Message -cmatch '^STARTUP_[A-Z_]+$'){$_.Exception.Message}else{'STARTUP_PROBE_FAILED'};$r.errorType=$_.Exception.GetBaseException().GetType().Name}
 finally{
  if($r.started){
   try{
    $r.beforeCleanup=Get-SupervisedGatewayTaskObservation
    Stop-ScheduledTask -TaskName $name -TaskPath '\'
    $null=Disable-ScheduledTask -TaskName $name -TaskPath '\'
    $stop=[Diagnostics.Stopwatch]::StartNew()
    do{if((Get-ScheduledTask -TaskName $name -TaskPath '\').State -eq 'Disabled' -and @(Get-StartupListeners).Count -eq 0){$r.cleanupPassed=$true;break};Start-Sleep -Seconds 1}while($stop.Elapsed.TotalSeconds -lt 30)
   }catch{$r.cleanupError=$_.Exception.GetBaseException().GetType().Name}
   if(-not $r.cleanupPassed){$r.passed=$false;$r.failure='STARTUP_CLEANUP_NOT_VERIFIED'}
  }
 }
 return $r
}
