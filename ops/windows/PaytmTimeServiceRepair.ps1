# PS5-compatible definitions. No actions on import.
function Initialize-PaytmTimeRepairRuntime {
 # A fresh Windows PowerShell 5.1 worker does not preload System.ServiceProcess.
 if(-not ('System.ServiceProcess.ServiceController' -as [type])){
  Add-Type -AssemblyName System.ServiceProcess -ErrorAction Stop
 }
 if(-not ('System.ServiceProcess.ServiceController' -as [type]) -or -not ('System.ServiceProcess.ServiceControllerStatus' -as [type])){throw 'TIME_REPAIR_SERVICE_ASSEMBLY_UNAVAILABLE'}
}
function Invoke-PaytmTimeRepairNative([string]$Tool,[string]$Arguments,[int]$Seconds=15) {
 if($Tool -cnotin @('sc.exe','w32tm.exe')){throw 'TIME_REPAIR_TOOL'}
 if($Arguments -cnotin @('sdshow W32Time','config W32Time start= auto','start W32Time','/resync /rediscover','/query /status /verbose','/query /source')){throw 'TIME_REPAIR_ARGUMENTS'}
 $p=[Diagnostics.Process]::new();$p.StartInfo.FileName=Join-Path $env:WINDIR ('System32\'+$Tool)
 $p.StartInfo.Arguments=$Arguments;$p.StartInfo.UseShellExecute=$false;$p.StartInfo.CreateNoWindow=$true
 $p.StartInfo.RedirectStandardOutput=$true;$p.StartInfo.RedirectStandardError=$true;$started=$false
 $watch=[Diagnostics.Stopwatch]::StartNew()
 try{
  $started=$p.Start();$o=$p.StandardOutput.ReadToEndAsync();$e=$p.StandardError.ReadToEndAsync()
  if(-not $p.WaitForExit($Seconds*1000)){throw 'TIME_REPAIR_NATIVE_TIMEOUT'}
  if(-not $o.Wait(3000) -or -not $e.Wait(3000)){throw 'TIME_REPAIR_DRAIN_TIMEOUT'}
  $text=$o.Result+$e.Result;if($text.Length -gt 12000){throw 'TIME_REPAIR_OUTPUT_TOO_LARGE'}
  @{tool=$Tool;arguments=$Arguments;exitCode=$p.ExitCode;output=$text;elapsedSeconds=$watch.Elapsed.TotalSeconds}
 }finally{if($started -and -not $p.HasExited){$p.Kill();[void]$p.WaitForExit(3000)};$p.Dispose()}
}
function Get-PaytmTimeRepairSnapshot {
 Initialize-PaytmTimeRepairRuntime
 $key=[Microsoft.Win32.Registry]::LocalMachine.OpenSubKey('SYSTEM\CurrentControlSet\Services\W32Time')
 $parameters=$null;$client=$null;$policy=$null;$svc=$null
 try{
  if(-not $key){throw 'TIME_REPAIR_SERVICE_MISSING'}
  $parameters=$key.OpenSubKey('Parameters');$client=$key.OpenSubKey('TimeProviders\NtpClient')
  if(-not $parameters -or -not $client){throw 'TIME_REPAIR_SOURCE_CONFIGURATION_MISSING'}
  $policy=[Microsoft.Win32.Registry]::LocalMachine.OpenSubKey('SOFTWARE\Policies\Microsoft\W32Time')
  $svc=[System.ServiceProcess.ServiceController]::new('W32Time')
  $sd=Invoke-PaytmTimeRepairNative 'sc.exe' 'sdshow W32Time'
  if($sd.exitCode -ne 0 -or $sd.output.Trim() -notmatch '^D:'){throw 'TIME_REPAIR_SECURITY_QUERY'}
  [pscustomobject]@{state=$svc.Status.ToString();startType=[int]$key.GetValue('Start');imagePath=[string]$key.GetValue('ImagePath');account=[string]$key.GetValue('ObjectName');sddl=$sd.output.Trim();policyPresent=($null -ne $policy);type=[string]$parameters.GetValue('Type');ntpServer=[string]$parameters.GetValue('NtpServer');ntpClientEnabled=[int]$client.GetValue('Enabled')}
 }finally{foreach($v in @($svc,$policy,$client,$parameters,$key)){if($v){$v.Dispose()}}}
}
function Assert-PaytmTimeRepairBaseline($v) {
 $expected='D:(A;;CCDCLCSWRPWPDTLOCRSDRCWDWO;;;SY)(A;;CCLCSWLOCRRC;;;BA)(A;;CCLCSWLOCRRC;;;IU)S:(AU;FA;CCDCLCSWRPWPDTLOCRSDRCWDWO;;;WD)'
 if($v.sddl -cne $expected -or $v.state -cne 'Stopped' -or $v.startType -ne 3){throw 'TIME_REPAIR_BASELINE_CHANGED'}
 if([Environment]::ExpandEnvironmentVariables($v.imagePath) -ine ($env:WINDIR+'\system32\svchost.exe -k LocalService') -or $v.account -ine 'NT AUTHORITY\LocalService'){throw 'TIME_REPAIR_SERVICE_IDENTITY'}
 if($v.policyPresent -or $v.type -cne 'NTP' -or $v.ntpClientEnabled -ne 1 -or [string]::IsNullOrWhiteSpace($v.ntpServer)){throw 'TIME_REPAIR_EXISTING_SOURCE_POLICY_REVIEW'}
}
function Assert-PaytmTimeRepairPreserved($Before,$After) {
 foreach($n in @('sddl','imagePath','account','policyPresent','type','ntpServer','ntpClientEnabled')){if($Before.$n -cne $After.$n){throw 'TIME_REPAIR_UNEXPECTED_CONFIGURATION_CHANGE'}}
}
function Invoke-PaytmTimeRepairSequence($Report,[scriptblock]$Save) {
 $Report.before=Get-PaytmTimeRepairSnapshot
 Assert-PaytmTimeRepairBaseline $Report.before
 & $Save
 $Report.mutationAttempted=$true;& $Save
 foreach($spec in @(@('sc.exe','config W32Time start= auto',15),@('sc.exe','start W32Time',15))){
  $r=Invoke-PaytmTimeRepairNative $spec[0] $spec[1] $spec[2]
  $Report.commands+=,$r;& $Save
  if($r.exitCode -ne 0){throw 'TIME_REPAIR_SERVICE_COMMAND_FAILED'}
 }
 Wait-PaytmTimeRepairRunning
 $r=Invoke-PaytmTimeRepairNative 'w32tm.exe' '/resync /rediscover' 40
 $Report.commands+=,$r;$Report.resyncRequested=$true;& $Save
 # Capture status/source even when the existing NTP source cannot be reached.
 foreach($arg in @('/query /status /verbose','/query /source')){$Report.commands+=,(Invoke-PaytmTimeRepairNative 'w32tm.exe' $arg 15);& $Save}
 if($r.exitCode -ne 0){throw 'TIME_REPAIR_RESYNC_NOT_ACCEPTED'}
 if(@($Report.commands | Where-Object {$_.exitCode -ne 0}).Count){throw 'TIME_REPAIR_STATUS_QUERY_FAILED'}
 $Report.after=Get-PaytmTimeRepairSnapshot
 Assert-PaytmTimeRepairPreserved $Report.before $Report.after
 if($Report.after.startType -ne 2 -or $Report.after.state -cne 'Running'){throw 'TIME_REPAIR_FINAL_STATE'}
 $Report.status='TIME_SERVICE_RUNNING_AUTOMATIC_RESYNC_ACCEPTED_ALIGNMENT_PENDING'
}

function Wait-PaytmTimeRepairRunning {
 Initialize-PaytmTimeRepairRuntime
 $svc=[System.ServiceProcess.ServiceController]::new('W32Time')
 try{$svc.WaitForStatus([System.ServiceProcess.ServiceControllerStatus]::Running,[TimeSpan]::FromSeconds(20))}finally{$svc.Dispose()}
}
