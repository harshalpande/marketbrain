#Requires -Version 5.1
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'PaytmTimeAccountProbe.ps1')
function New-ValidProbe {
 @{runId='a'*32;passed=$true;failure=$null;sid='S-1-5-21-3041730714-102984520-3202743044-1011';admin=$false;sessionId=0;samples=@(@{sequence=1;ageSeconds=1},@{sequence=2;ageSeconds=2},@{sequence=3;ageSeconds=1});writeDenied=@('worker.ps1','snapshot.json')}
}
foreach($case in @('valid','admin','sid','session','replay','stale','negativeAge','notAdvancing','writeAllowed','failed')){
 $v=New-ValidProbe
 switch($case){'admin'{$v.admin=$true} 'sid'{$v.sid='S-1-5-18'} 'session'{$v.sessionId=2} 'replay'{$v.runId='b'*32} 'stale'{$v.samples[1].ageSeconds=9} 'negativeAge'{$v.samples[0].ageSeconds=-1} 'notAdvancing'{$v.samples[1].sequence=1} 'writeAllowed'{$v.writeDenied=@('worker.ps1')} 'failed'{$v.passed=$false}}
 $failed=$false;try{Assert-TimeAccountProbeResult $v ('a'*32)}catch{$failed=$true}
 if($failed -ne ($case -ne 'valid')){throw "Probe contract case failed: $case"}
}
$source=Get-TimeAccountProbeSource ('a'*32) 'C:\fixture\report.json' ([IO.File]::ReadAllText((Join-Path $PSScriptRoot 'PaytmTimeObservation.ps1')))
$tokens=$null;$errors=$null;$null=[Management.Automation.Language.Parser]::ParseInput($source,[ref]$tokens,[ref]$errors)
if($errors.Count -or $source.Contains('__RUN__') -or $source.Contains('__OUTPUT__')){throw 'Generated account worker invalid'}
# Keep real SID parsing, substitute name resolution only for fixture accounts.
$script:realSidResolver=(Get-Command Resolve-TimeAccountTaskSid).ScriptBlock
function Resolve-TimeAccountTaskSid([string]$Identity) {
 if($Identity -in @('marketbrain-health','SPARE\marketbrain-health')){return 'S-1-5-21-3041730714-102984520-3202743044-1011'}
 if($Identity -eq 'OTHER\marketbrain-health'){return 'S-1-5-21-1-2-3-1011'}
 if($Identity -eq 'unresolved'){throw 'fixture unresolved'}
 & $script:realSidResolver $Identity
}
$taskCases=@('sid','shortName','qualifiedName','nullTriggers','nullElement','foreignName','unresolved','adminSid','high','s4u','extraAction','noAction','arguments','executable','trigger')
foreach($taskCase in $taskCases){
 $t=@{Principal=@{UserId='S-1-5-21-3041730714-102984520-3202743044-1011';LogonType='Password';RunLevel='Limited'};Actions=@(@{Execute='powershell.exe';Arguments='fixture'});Triggers=@()}
 switch($taskCase){
  'shortName'{$t.Principal.UserId='marketbrain-health'} 'qualifiedName'{$t.Principal.UserId='SPARE\marketbrain-health'}
  'nullTriggers'{$t.Triggers=$null} 'nullElement'{$t.Triggers=@($null)}
  'foreignName'{$t.Principal.UserId='OTHER\marketbrain-health'} 'unresolved'{$t.Principal.UserId='unresolved'} 'adminSid'{$t.Principal.UserId='S-1-5-32-544'}
  'high'{$t.Principal.RunLevel='Highest'} 's4u'{$t.Principal.LogonType='S4U'}
  'extraAction'{$t.Actions+=@{Execute='other'}} 'noAction'{$t.Actions=$null}
  'arguments'{$t.Actions[0].Arguments='changed'} 'executable'{$t.Actions[0].Execute='other.exe'} 'trigger'{$t.Triggers=@(@{Enabled=$true})}
 }
 $v=Test-TimeAccountTask $t 'powershell.exe' 'fixture'
 if($v.valid -ne ($taskCase -in @('sid','shortName','qualifiedName','nullTriggers','nullElement'))){throw "Task validation failed: $taskCase"}
 if(-not $v.valid -and $v.reasons.Count -eq 0){throw 'Missing mismatch evidence'}
}
# Actual controller workflow with task/ACL calls replaced; never creates a real task.
function Assert-TimeObservationAcl {}
function Read-TimeObservation {return @{sequence=1;ageSeconds=1}}
function Get-Acl {return [Security.AccessControl.DirectorySecurity]::new()}
function Set-Acl {}
function New-ScheduledTaskAction {param($Execute,$Argument) @{Execute=$Execute;Arguments=$Argument}}
function New-ScheduledTaskPrincipal {param($UserId,$LogonType,$RunLevel) @{UserId=$UserId;LogonType=$LogonType;RunLevel=$RunLevel}}
function New-ScheduledTaskSettingsSet {}
function New-ScheduledTask {param($Action,$Principal,$Settings) @{Action=$Action;Principal=$Principal}}
function Register-ScheduledTask {param($TaskName,$TaskPath,$InputObject,$User,$Password) if($script:case -eq 'registerFailure'){throw [Runtime.InteropServices.COMException]::new('fixture secret must not escape',[Convert]::ToInt32('8007052e',16))};if($Password -cne 'fixture-only-not-a-real-password' -or $User -cne ($env:COMPUTERNAME+'\marketbrain-health')){throw 'Credential argument changed in transit'};$Action=$InputObject.Action;$Principal=$InputObject.Principal; $Principal.UserId='SPARE\marketbrain-health';$script:task=@{TaskName=$TaskName;TaskPath=$TaskPath;Actions=@($Action);Principal=$Principal;Triggers=$null;State='Ready'};if($script:case -eq 'drift'){$script:task.Principal.RunLevel='Highest'}}
function Get-ScheduledTask {if($script:task){return [pscustomobject]$script:task}}
function Start-ScheduledTask {
 $script:started++
 $v=New-ValidProbe;$v.runId=$run
 if($script:case -eq 'badWorker'){$v.admin=$true}
 [IO.File]::WriteAllText($output,($v|ConvertTo-Json -Depth 5))
}
function Get-ScheduledTaskInfo {return @{LastTaskResult=0}}
function Start-Sleep {}
function Disable-ScheduledTask {}
function Stop-ScheduledTask {}
function Unregister-ScheduledTask {param($TaskName,$TaskPath,[switch]$Confirm) if($script:case -eq 'cleanup'){throw 'fixture cleanup failure'};$script:task=$null}
$original=(Get-Command Invoke-TimeAccountProbe).ScriptBlock.ToString()
foreach($script:case in @('valid','drift','badWorker','cleanup','registerFailure')){
 $root=Join-Path ([IO.Path]::GetTempPath()) ('mb-time-account-fixture-'+[guid]::NewGuid().ToString('N'))
 $null=New-Item -ItemType Directory -Path $root
 $script:task=$null;$script:started=0
 $result=& ([scriptblock]::Create($original.Replace('C:\ProgramData\MarketBrainPaytmHealth\time-observer-v1',$root))) 'fixture' (ConvertTo-SecureString 'fixture-only-not-a-real-password' -AsPlainText -Force)
 if($result.passed -ne ($case -eq 'valid')){throw "Workflow result incorrect: $case $($result.failure)"}
 if($case -eq 'drift' -and $started){throw 'Drifted task started'}
 if($case -eq 'drift' -and ($result.stage -ne 'VERIFY_REGISTERED_TASK' -or 'RUN_LEVEL' -notin $result.taskValidation.reasons -or $result.failureDetail -like 'Scheduler registration failed*')){throw 'Incorrect task drift evidence'}
 if($case -notin @('cleanup','registerFailure') -and -not $result.taskRemoved){throw 'Temporary task not removed'}
 if($case -eq 'registerFailure' -and ($result.taskCreated -or $started -or 1326 -notin $result.nativeFailure.win32Codes -or ($result|ConvertTo-Json -Depth 10) -match 'fixture secret')){throw 'Registration diagnostics leaked or missing'}
 if($case -eq 'cleanup' -and -not $result.cleanupFailure){throw 'Cleanup failure not retained'}
}
Write-Host 'TIME_ACCOUNT_PROBE_FIXTURES_PASSED: 10 result cases, 15 task cases, generated PS5 worker and 5 isolated workflows.'

$blocked=$false;try{Invoke-TimeAccountProbe 'fixture'}catch{$blocked=$_.Exception.Message -eq 'TIME_ACCOUNT_LOCAL_PASSWORD_REQUIRED'};if(-not $blocked){throw 'Missing credential not blocked'}

foreach($code in @(5,1326,1330,1331,1385,1909,87)){
 $hresult=[int](-2147024896+$code)
 $e=[Runtime.InteropServices.COMException]::new('SECRET_FIXTURE',$hresult)
 $d=Get-TimeAccountNativeFailure ([pscustomobject]@{Exception=$e})
 if($code -notin $d.win32Codes -or ($d|ConvertTo-Json -Depth 8) -match 'SECRET_FIXTURE'){throw 'Unsafe or missing HRESULT capture'}
}
$fake=[pscustomobject]@{HResult=-2146233088;NativeErrorCode=2;Message='SECRET_FIXTURE HRESULT 0x8007052E';InnerException=$null;ErrorData=[pscustomobject]@{CimInstanceProperties=@{Error_Code=[pscustomobject]@{Value=2147942405L}}}}
$d=Get-TimeAccountNativeFailure ([pscustomobject]@{Exception=$fake})
if(1326 -notin $d.win32Codes -or 5 -notin $d.win32Codes -or 2 -in $d.win32Codes -or ($d|ConvertTo-Json -Depth 8) -match 'SECRET_FIXTURE'){throw 'CIM status namespace or redaction failed'}
$d=Get-TimeAccountNativeFailure ([pscustomobject]@{Exception=[Exception]::new('opaque')})
if($d.win32Codes.Count -or $d.passwordCorrectness -ne 'NOT_ESTABLISHED'){throw 'Unknown failure inferred credentials'}
Write-Host 'TIME_ACCOUNT_NATIVE_ERRORS_PASSED: 9 HRESULT/CIM/unknown cases; secrets excluded.'

$xml='<Event><EventData><Data Name="TargetUserName">marketbrain-health</Data><Data Name="TargetDomainName">SPARE</Data><Data Name="Status">0xc000006d</Data><Data Name="SubStatus">0xc000006a</Data><Data Name="LogonType">4</Data><Data Name="UnrelatedSecret">DO_NOT_EXPORT</Data></EventData></Event>'
$v=ConvertFrom-TimeAccountLogonEvent $xml
if($v.subStatus -cne '0xc000006a' -or ($v|ConvertTo-Json) -match 'DO_NOT_EXPORT'){throw 'Unsafe logon event extraction'}
if($null -ne (ConvertFrom-TimeAccountLogonEvent $xml.Replace('marketbrain-health','other-user'))){throw 'Unrelated event exported'}
Write-Host 'TIME_ACCOUNT_EVENT_FILTER_PASSED: expected account fields only; unrelated users excluded.'
