# Local-only probe; registration password stays local. No network or token decryption.
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
function Resolve-TimeAccountTaskSid([string]$Identity) {
 if([string]::IsNullOrWhiteSpace($Identity)){throw 'TIME_ACCOUNT_PRINCIPAL_MISSING'}
 if($Identity.StartsWith('S-1-', [StringComparison]::OrdinalIgnoreCase)){
  return [Security.Principal.SecurityIdentifier]::new($Identity).Value
 }
 return ([Security.Principal.NTAccount]::new($Identity)).Translate([Security.Principal.SecurityIdentifier]).Value
}
function ConvertFrom-TimeAccountLogonEvent([string]$Xml) {
 $document=[xml]$Xml;$data=@{}
 foreach($item in $document.Event.EventData.Data){$data[[string]$item.Name]=[string]$item.'#text'}
 if($data.TargetUserName -ine 'marketbrain-health'){return $null}
 return @{targetUser=$data.TargetUserName;targetDomain=$data.TargetDomainName;status=$data.Status;subStatus=$data.SubStatus;logonType=$data.LogonType}
}
function Get-TimeAccountIdentityEvidence($Account,$LocalReport) {
 $configured=$env:COMPUTERNAME+'\marketbrain-health'
 $r=@{configuredUser=$configured;machineName=[Environment]::MachineName;accountSid=$Account.SID.Value;enabled=[bool]$Account.Enabled;identityMatches=$false;events=@();eventQuery='NOT_REQUESTED'}
 try{$r.resolvedSid=Resolve-TimeAccountTaskSid $configured;$r.identityMatches=$r.resolvedSid -ceq $Account.SID.Value}catch{$r.identityFailure=$_.Exception.GetType().Name}
 if($Account.PasswordLastSet){$r.passwordLastSetUtc=$Account.PasswordLastSet.ToUniversalTime().ToString('o')}
 if($LocalReport -and $LocalReport.observedUtc){
  try{
   $end=[DateTimeOffset]::Parse([string]$LocalReport.observedUtc).UtcDateTime.AddSeconds(10)
   $start=$end.AddMinutes(-3)
   $events=@(Get-WinEvent -FilterHashtable @{LogName='Security';Id=4625;StartTime=$start;EndTime=$end} -MaxEvents 50 -ErrorAction Stop)
   foreach($event in $events){$value=ConvertFrom-TimeAccountLogonEvent $event.ToXml();if($value){$value.observedUtc=$event.TimeCreated.ToUniversalTime().ToString('o');$r.events+=$value}}
   $r.eventQuery='COMPLETED_BOUNDED_50'
  }catch{$r.eventQuery='UNAVAILABLE_OR_NO_EVENTS';$r.eventFailure=$_.Exception.GetType().Name}
 }
 return $r
}
function Test-TimeAccountTask($Task,[string]$Executable,[string]$Arguments) {
 $reasons=@();$sid=$null
 try{$sid=Resolve-TimeAccountTaskSid ([string]$Task.Principal.UserId)}catch{$reasons+='PRINCIPAL_UNRESOLVED'}
 if($sid -cne 'S-1-5-21-3041730714-102984520-3202743044-1011'){$reasons+='PRINCIPAL_SID'}
 if([string]$Task.Principal.LogonType -cne 'Password'){$reasons+='LOGON_TYPE'}
 if([string]$Task.Principal.RunLevel -cne 'Limited'){$reasons+='RUN_LEVEL'}
 # CIM may represent an absent collection as null, not an empty array.
 $actions=@($Task.Actions | Where-Object {$null -ne $_})
 $triggers=@($Task.Triggers | Where-Object {$null -ne $_})
 $argumentsMatch=$false;$executableMatch=$false
 if($actions.Count -ne 1){$reasons+='ACTION_COUNT'}else{
  $argumentsMatch=$actions[0].Arguments -ceq $Arguments
  $executableMatch=$actions[0].Execute -ieq $Executable
  if(-not $argumentsMatch){$reasons+='ACTION_ARGUMENTS'}
  if(-not $executableMatch){$reasons+='ACTION_EXECUTABLE'}
 }
 if($triggers.Count -ne 0){$reasons+='UNEXPECTED_TRIGGER'}
 return @{valid=($reasons.Count -eq 0);reasons=$reasons;principalSid=$sid;logonType=[string]$Task.Principal.LogonType;runLevel=[string]$Task.Principal.RunLevel;actionCount=$actions.Count;triggerCount=$triggers.Count;argumentsMatch=$argumentsMatch;executableMatch=$executableMatch}
}
function Get-TimeAccountNativeFailure($ErrorRecord) {
 # Retain numeric diagnostics only: never serialize the ErrorRecord, command,
 # exception message, bound parameters, or CIM message text containing arguments.
 $items=@();$exception=$ErrorRecord.Exception
 for($depth=0;$null -ne $exception -and $depth -lt 4;$depth++){
  foreach($name in @('HResult','NativeErrorCode')){
   $property=$exception.PSObject.Properties[$name]
   if($property -and $null -ne $property.Value){$number=0L;if([long]::TryParse([string]$property.Value,[ref]$number)){$items+=@{source="exception.$depth.$name";value=$number}}}
  }
  $data=$exception.PSObject.Properties['ErrorData']
  if($data -and $data.Value){
   foreach($name in @('Error_Code','ErrorCode','CIMStatusCode','MessageID')){
    $property=$data.Value.CimInstanceProperties[$name]
    if($property -and $null -ne $property.Value){$number=0L;if([long]::TryParse([string]$property.Value,[ref]$number)){$items+=@{source="cim.$depth.$name";value=$number}}}
   }
  }
  # CIM often embeds HRESULT in its message while HResult is generic CLR.
  foreach($match in @([regex]::Matches([string]$exception.Message,'(?i)\b0x[89a-f][0-9a-f]{7}\b') | Select-Object -First 4)){
   $items+=@{source="messageHResult.$depth";value=[Convert]::ToInt64($match.Value.Substring(2),16)}
  }
  $exception=$exception.InnerException
 }
 $win32=@()
 foreach($item in $items){
  $unsigned=$item.value -band 4294967295L
  if(($unsigned -band 4294901760L) -eq 2147942400L){$win32+=($unsigned -band 65535L)}
 }
 $win32=@($win32|Sort-Object -Unique)
 $findings=@()
 foreach($code in $win32){$findings+=switch($code){5{'ACCESS_DENIED'}1326{'USERNAME_OR_PASSWORD_REJECTED'}1330{'PASSWORD_EXPIRED'}1331{'ACCOUNT_DISABLED'}1385{'LOGON_TYPE_NOT_GRANTED'}1909{'ACCOUNT_LOCKED'}default{'UNCLASSIFIED_WIN32_ERROR'}}}
 return @{numericDiagnostics=$items;win32Codes=$win32;findings=$findings;passwordCorrectness='NOT_ESTABLISHED'}
}
function Test-TimeAccountCredential([Security.SecureString]$Password) {
 if(-not ('MarketBrainTimeCredentialV1' -as [type])){
  Add-Type -TypeDefinition @'
using System;
using System.Security;
using System.Security.Principal;
using System.Runtime.InteropServices;
public static class MarketBrainTimeCredentialV1 {
 [DllImport("advapi32.dll", CharSet=CharSet.Unicode, ExactSpelling=true, SetLastError=true)]
 static extern bool LogonUserW(string user, string domain, IntPtr password, int type, int provider, out IntPtr token);
 [DllImport("kernel32.dll", ExactSpelling=true)] static extern bool CloseHandle(IntPtr handle);
 public static int Check(SecureString secret, out string sid) {
  sid=null; IntPtr password=IntPtr.Zero, token=IntPtr.Zero;
  try {
   password=Marshal.SecureStringToGlobalAllocUnicode(secret);
   if(!LogonUserW("marketbrain-health", Environment.MachineName, password, 4, 0, out token)) return Marshal.GetLastWin32Error();
   using(var identity=new WindowsIdentity(token)) { sid=identity.User.Value; }
   return 0;
  } finally { if(token!=IntPtr.Zero) CloseHandle(token); if(password!=IntPtr.Zero) Marshal.ZeroFreeGlobalAllocUnicode(password); }
 }
}
'@
 }
 $sid=$null;$code=[MarketBrainTimeCredentialV1]::Check($Password,[ref]$sid)
 return @{accepted=($code -eq 0 -and $sid -ceq 'S-1-5-21-3041730714-102984520-3202743044-1011');win32Code=$code;resolvedSid=$sid;attempts=1;logonType='BATCH'}
}
function Invoke-TimeAccountProbe([string]$ContractSource,[Security.SecureString]$Password) {
 if(-not $Password -or $Password.Length -eq 0){throw 'TIME_ACCOUNT_LOCAL_PASSWORD_REQUIRED'}
 $run=[guid]::NewGuid().ToString('N');$task='MarketBrain-Time-Read-Probe-'+$run
 $parent='C:\ProgramData\MarketBrainPaytmHealth\time-observer-v1'
 $dir=Join-Path $parent ('probe-'+$run);$outputDir=Join-Path $dir 'result';$output=Join-Path $outputDir 'report.json'
 $r=@{passed=$false;runId=$run;taskName=$task;taskCreated=$false;taskRemoved=$false;cleanupFailure=$null;failure=$null;authenticationTested=$false;healthPublicationTested=$false}
 try{
  $r.stage='PARENT_ACL';Assert-TimeObservationAcl $parent
  $r.stage='SNAPSHOT_READ';$null=Read-TimeObservation
  $r.stage='WINDOWS_CREDENTIAL_CHECK';$r.credentialCheck=Test-TimeAccountCredential $Password
  if(-not $r.credentialCheck.accepted){throw 'TIME_ACCOUNT_WINDOWS_CREDENTIAL_NOT_ACCEPTED'}
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
  $principal=New-ScheduledTaskPrincipal -UserId 'S-1-5-21-3041730714-102984520-3202743044-1011' -LogonType Password -RunLevel Limited
  $settings=New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -ExecutionTimeLimit ([TimeSpan]::FromMinutes(1)) -MultipleInstances IgnoreNew
  $definition=New-ScheduledTask -Action $action -Principal $principal -Settings $settings
  $r.stage='REGISTER';$plain=$null
  try{$plain=[Net.NetworkCredential]::new('', $Password).Password;$null=Register-ScheduledTask -TaskName $task -TaskPath '\' -InputObject $definition -User ($env:COMPUTERNAME+'\marketbrain-health') -Password $plain}finally{$plain=$null}
  $r.taskCreated=$true
  $r.stage='VERIFY_REGISTERED_TASK'
  $t=Get-ScheduledTask -TaskName $task -TaskPath '\'
  $r.taskValidation=Test-TimeAccountTask $t $exe $arguments
  if(-not $r.taskValidation.valid){throw 'TIME_ACCOUNT_TASK_DRIFT'}
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
 }catch{$r.failure=if($_.Exception.Message -cmatch '^(TIME_ACCOUNT|TIME_OBSERVER)_[A-Z_]+$'){$_.Exception.Message}else{'TIME_ACCOUNT_'+$_.Exception.GetBaseException().GetType().Name};$r.failureLine=$_.InvocationInfo.ScriptLineNumber;$r.nativeHResult=$_.Exception.HResult;$r.nativeFailure=Get-TimeAccountNativeFailure $_;$message=$_.Exception.Message;$r.failureDetail=if($r.stage -eq 'REGISTER'){'Scheduler registration failed; password omitted'}else{$message.Substring(0,[Math]::Min(512,$message.Length))};$target=[string]$_.TargetObject;if($target.StartsWith($parent,[StringComparison]::OrdinalIgnoreCase)){$r.failureTarget=$target.Substring($parent.Length)}}
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
