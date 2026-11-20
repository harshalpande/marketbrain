# Local-only probe; no password, network access or token decryption.
function Get-TimeAccountProbeSource([string]$RunId,[string]$OutputPath,[string]$ContractSource) {
 if($RunId -cnotmatch '^[a-f0-9]{32}$' -or $OutputPath.Contains("'")){throw 'TIME_ACCOUNT_ARGUMENT'}
 $body=@'
$ErrorActionPreference='Stop'
$r=@{runId='__RUN__';passed=$false;failure=$null;ordersEnabled=$false;credentialsUsed=$false}
try{
 $id=[Security.Principal.WindowsIdentity]::GetCurrent()
 try{$r.sid=$id.User.Value;$r.admin=([Security.Principal.WindowsPrincipal]::new($id)).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)}finally{$id.Dispose()}
 $r.sessionId=[Diagnostics.Process]::GetCurrentProcess().SessionId
 if($r.sid -cne 'S-1-5-21-3041730714-102984520-3202743044-1011' -or $r.admin -or $r.sessionId -ne 0){throw 'TIME_ACCOUNT_IDENTITY'}
 $r.samples=@()
 for($i=0;$i -lt 3;$i++){$v=Read-TimeObservation;$r.samples+=@{sequence=$v.sequence;ageSeconds=$v.ageSeconds};if($i -lt 2){Start-Sleep -Milliseconds 1500}}
 if($r.samples[2].sequence -le $r.samples[0].sequence){throw 'TIME_ACCOUNT_NOT_ADVANCING'}
 $r.writeDenied=@()
 foreach($name in @('worker.ps1','snapshot.json')){
  $denied=$false;$handle=$null
  try{$handle=[IO.File]::Open(('C:\ProgramData\MarketBrainPaytmHealth\time-observer-v1\'+$name),'Open','Write',([IO.FileShare]::ReadWrite -bor [IO.FileShare]::Delete))}
  catch{if($_.Exception.GetBaseException() -is [UnauthorizedAccessException]){$denied=$true}else{throw}}
  finally{if($handle){$handle.Dispose()}}
  if(-not $denied){throw 'TIME_ACCOUNT_WRITE_ALLOWED'};$r.writeDenied+=$name
 }
 $r.passed=$true
}catch{$r.failure=if($_.Exception.Message -cmatch '^(TIME_ACCOUNT|TIME_OBSERVER)_[A-Z_]+$'){$_.Exception.Message}else{'TIME_ACCOUNT_'+$_.Exception.GetBaseException().GetType().Name};$r.failureLine=$_.InvocationInfo.ScriptLineNumber}
[IO.File]::WriteAllText('__OUTPUT__',($r|ConvertTo-Json -Depth 5),[Text.UTF8Encoding]::new($false))
if(-not $r.passed){exit 1}
'@
 return $ContractSource+"`n"+$body.Replace('__RUN__',$RunId).Replace('__OUTPUT__',$OutputPath)
}
function Assert-TimeAccountProbeResult($Value,[string]$RunId) {
 if($Value.runId -cne $RunId -or $Value.passed -ne $true -or $Value.failure -or $Value.sid -cne 'S-1-5-21-3041730714-102984520-3202743044-1011' -or $Value.admin -ne $false -or $Value.sessionId -ne 0 -or @($Value.samples).Count -ne 3 -or (@($Value.writeDenied) -join ',') -cne 'worker.ps1,snapshot.json'){throw 'TIME_ACCOUNT_RESULT_INVALID'}
 $previous=0L
 foreach($sample in $Value.samples){if($null -eq $sample.sequence -or $null -eq $sample.ageSeconds -or [double]::IsNaN([double]$sample.ageSeconds) -or $sample.sequence -le $previous -or $sample.ageSeconds -lt 0 -or $sample.ageSeconds -gt 8){throw 'TIME_ACCOUNT_SAMPLE_INVALID'};$previous=$sample.sequence}
}
function Invoke-TimeAccountProbe([string]$ContractSource) {
 $run=[guid]::NewGuid().ToString('N');$task='MarketBrain-Time-Read-Probe-'+$run
 $parent='C:\ProgramData\MarketBrainPaytmHealth\time-observer-v1'
 $dir=Join-Path $parent ('probe-'+$run);$outputDir=Join-Path $dir 'result';$output=Join-Path $outputDir 'report.json'
 $r=@{passed=$false;runId=$run;taskName=$task;taskCreated=$false;taskRemoved=$false;cleanupFailure=$null;failure=$null;authenticationTested=$false;healthPublicationTested=$false}
 try{
  $r.stage='PARENT_ACL';Assert-TimeObservationAcl $parent
  $r.stage='SNAPSHOT_READ';$null=Read-TimeObservation
  if((Test-Path -LiteralPath $dir) -or @(Get-ScheduledTask|Where-Object {$_.TaskName -ceq $task -and $_.TaskPath -ceq '\'}).Count){throw 'TIME_ACCOUNT_COLLISION'}
  $r.stage='CREATE_PROBE';$null=New-Item -ItemType Directory -Path $dir
  $r.stage='PROBE_ACL';Assert-TimeObservationAcl $dir
  $null=New-Item -ItemType Directory -Path $outputDir
  $r.stage='RESULT_ACL';$acl=Get-Acl -LiteralPath $outputDir
  $acl.AddAccessRule([Security.AccessControl.FileSystemAccessRule]::new([Security.Principal.SecurityIdentifier]::new('S-1-5-21-3041730714-102984520-3202743044-1011'),'Modify','ContainerInherit,ObjectInherit','None','Allow'))
  Set-Acl -LiteralPath $outputDir -AclObject $acl
  $r.stage='WORKER';$worker=Join-Path $dir 'probe.ps1';$source=Get-TimeAccountProbeSource $run $output $ContractSource
  [IO.File]::WriteAllText($worker,$source,[Text.UTF8Encoding]::new($false));Assert-TimeObservationAcl $worker
  $hash=(Get-FileHash -LiteralPath $worker).Hash
  $command="if((Get-FileHash -LiteralPath '$worker').Hash -cne '$hash'){exit 9};&([scriptblock]::Create([IO.File]::ReadAllText('$worker')))"
  $arguments='-NoLogo -NoProfile -NonInteractive -EncodedCommand '+[Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($command))
  $exe=Join-Path $env:WINDIR 'System32\WindowsPowerShell\v1.0\powershell.exe'
  $action=New-ScheduledTaskAction -Execute $exe -Argument $arguments
  $principal=New-ScheduledTaskPrincipal -UserId 'S-1-5-21-3041730714-102984520-3202743044-1011' -LogonType S4U -RunLevel Limited
  $settings=New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -ExecutionTimeLimit ([TimeSpan]::FromMinutes(1)) -MultipleInstances IgnoreNew
  $r.stage='REGISTER';$null=Register-ScheduledTask -TaskName $task -TaskPath '\' -Action $action -Principal $principal -Settings $settings
  $r.taskCreated=$true
  $t=Get-ScheduledTask -TaskName $task -TaskPath '\'
  if($t.Principal.UserId -notin @('marketbrain-health','S-1-5-21-3041730714-102984520-3202743044-1011') -or [string]$t.Principal.LogonType -cne 'S4U' -or [string]$t.Principal.RunLevel -cne 'Limited' -or @($t.Actions).Count -ne 1 -or $t.Actions[0].Arguments -cne $arguments -or $t.Actions[0].Execute -ine $exe -or @($t.Triggers).Count -ne 0){throw 'TIME_ACCOUNT_TASK_DRIFT'}
  $r.stage='START';Start-ScheduledTask -TaskName $task -TaskPath '\'
  $timer=[Diagnostics.Stopwatch]::StartNew()
  do{Start-Sleep -Seconds 1;$t=Get-ScheduledTask -TaskName $task -TaskPath '\'}while($timer.Elapsed.TotalSeconds -lt 40 -and (-not (Test-Path -LiteralPath $output) -or [string]$t.State -eq 'Running'))
  if([string]$t.State -eq 'Running'){throw 'TIME_ACCOUNT_TIMEOUT'}
  if(-not (Test-Path -LiteralPath $output)){throw 'TIME_ACCOUNT_NO_REPORT'}
  if((Get-Item -LiteralPath $output).Length -gt 8192){throw 'TIME_ACCOUNT_REPORT_SIZE'}
  $r.worker=Get-Content -LiteralPath $output -Raw|ConvertFrom-Json
  Assert-TimeAccountProbeResult $r.worker $run
  if((Get-ScheduledTaskInfo -TaskName $task -TaskPath '\').LastTaskResult -ne 0){throw 'TIME_ACCOUNT_EXIT'}
  $r.passed=$true
 }catch{$r.failure=if($_.Exception.Message -cmatch '^(TIME_ACCOUNT|TIME_OBSERVER)_[A-Z_]+$'){$_.Exception.Message}else{'TIME_ACCOUNT_'+$_.Exception.GetBaseException().GetType().Name};$r.failureLine=$_.InvocationInfo.ScriptLineNumber;$r.nativeHResult=$_.Exception.HResult;$message=$_.Exception.Message;$r.failureDetail=$message.Substring(0,[Math]::Min(512,$message.Length));$target=[string]$_.TargetObject;if($target.StartsWith($parent,[StringComparison]::OrdinalIgnoreCase)){$r.failureTarget=$target.Substring($parent.Length)}}
 finally{
  if($r.taskCreated){try{
   $null=Disable-ScheduledTask -TaskName $task -TaskPath '\';Stop-ScheduledTask -TaskName $task -TaskPath '\'
   $t=Get-ScheduledTask -TaskName $task -TaskPath '\';if([string]$t.State -eq 'Running'){throw 'TIME_ACCOUNT_STILL_RUNNING'}
   Unregister-ScheduledTask -TaskName $task -TaskPath '\' -Confirm:$false
   if(@(Get-ScheduledTask|Where-Object {$_.TaskName -ceq $task -and $_.TaskPath -ceq '\'}).Count){throw 'TIME_ACCOUNT_TASK_REMAINS'}
   $r.taskRemoved=$true
  }catch{$r.cleanupFailure='TIME_ACCOUNT_CLEANUP';$r.passed=$false}}
 }
 return $r
}
