#requires -Version 7.5
param([Parameter(Mandatory)][string]$ResultPath,[ValidateSet('Observe','Apply','FailureFixture')][string]$Mode='Observe')
# PS5-compatible read-only time observation contract. No actions on import.
function Get-TimeObservationBootId {
    # Stable across users/processes; changes after a Windows restart.
    (Get-CimInstance Win32_OperatingSystem -ErrorAction Stop).LastBootUpTime.ToUniversalTime().ToString('o')
}
function Assert-TimeObservationAcl([string]$Path) {
    if((Get-Item -LiteralPath $Path -Force).Attributes -band [IO.FileAttributes]::ReparsePoint){throw 'TIME_OBSERVER_REPARSE'}
    $acl=Get-Acl -LiteralPath $Path
    $trusted=@('S-1-5-18','S-1-5-32-544')
    if($acl.GetOwner([Security.Principal.SecurityIdentifier]).Value -notin $trusted){throw 'TIME_OBSERVER_OWNER'}
    $write=[Security.AccessControl.FileSystemRights]::Write -bor [Security.AccessControl.FileSystemRights]::Delete -bor [Security.AccessControl.FileSystemRights]::DeleteSubdirectoriesAndFiles -bor [Security.AccessControl.FileSystemRights]::ChangePermissions -bor [Security.AccessControl.FileSystemRights]::TakeOwnership
    foreach($ace in $acl.GetAccessRules($true,$true,[Security.Principal.SecurityIdentifier])){
        if($ace.AccessControlType -eq 'Allow' -and ($ace.FileSystemRights -band $write) -and $ace.IdentityReference.Value -notin $trusted){throw 'TIME_OBSERVER_WRITABLE'}
    }
}
function ConvertFrom-TimeObservation($Value,[string]$BootId,[long]$NowTicks,[long]$Frequency) {
    if($Value.version -ne 1 -or $Value.bootId -cne $BootId -or $Value.frequency -ne $Frequency -or $Value.sequence -lt 1){throw 'TIME_OBSERVER_IDENTITY'}
    if($Value.startTicks -isnot [long] -or $Value.endTicks -isnot [long] -or $Value.startTicks -gt $Value.endTicks -or $Value.endTicks -gt $NowTicks){throw 'TIME_OBSERVER_TIMING'}
    $age=($NowTicks-$Value.startTicks)/[double]$Frequency
    if($age -lt 0 -or $age -gt 8){throw 'TIME_OBSERVER_STALE'}
    if($Value.status.exitCode -ne 0 -or $Value.source.exitCode -ne 0 -or $Value.service.state -cne 'Running' -or $Value.service.startType -ne 2){throw 'TIME_OBSERVER_UNHEALTHY'}
    if($Value.status.output -isnot [string] -or $Value.source.output -isnot [string] -or $Value.status.output.Length -gt 12000 -or $Value.source.output.Length -gt 1024){throw 'TIME_OBSERVER_FORMAT'}
    # Add snapshot age to the reported sync age; never make old evidence younger.
    $pattern='(?im)^(Time since Last Good Sync Time:\s*)([0-9]+(?:\.[0-9]+)?)(s\s*)$'
    $m=[regex]::Match($Value.status.output,$pattern)
    if(-not $m.Success){throw 'TIME_OBSERVER_SYNC_AGE'}
    $seconds=[double]::Parse($m.Groups[2].Value,[Globalization.CultureInfo]::InvariantCulture)+$age
    $output=$Value.status.output.Remove($m.Groups[2].Index,$m.Groups[2].Length).Insert($m.Groups[2].Index,$seconds.ToString('F6',[Globalization.CultureInfo]::InvariantCulture))
    [pscustomobject]@{status=@{exitCode=0;output=$output};source=$Value.source;service=$Value.service;ageSeconds=$age;sequence=$Value.sequence}
}
function ConvertFrom-TimeObservationJson([string]$Json) {
    # PS7 otherwise coerces ISO boot IDs into DateTime, unlike the PS5 producer.
    if($PSVersionTable.PSVersion -ge [version]'7.5'){ConvertFrom-Json -InputObject $Json -DateKind String}else{ConvertFrom-Json -InputObject $Json}
}
function Read-TimeObservation {
    $root='C:\ProgramData\MarketBrainPaytmHealth\time-observer-v1';$path=Join-Path $root 'snapshot.json'
    foreach($p in @('C:\ProgramData\MarketBrainPaytmHealth',$root,$path)){Assert-TimeObservationAcl $p}
    $stream=[IO.File]::Open($path,'Open','Read',([IO.FileShare]::ReadWrite -bor [IO.FileShare]::Delete))
    try{if($stream.Length -gt 16384){throw 'TIME_OBSERVER_SIZE'};$reader=[IO.StreamReader]::new($stream);try{$buffer=[char[]]::new(16385);$n=$reader.ReadBlock($buffer,0,16385);if($n -gt 16384){throw 'TIME_OBSERVER_SIZE'};$json=[string]::new($buffer,0,$n);$v=ConvertFrom-TimeObservationJson $json}finally{$reader.Dispose()}}finally{$stream.Dispose()}
    ConvertFrom-TimeObservation $v (Get-TimeObservationBootId) ([Diagnostics.Stopwatch]::GetTimestamp()) ([Diagnostics.Stopwatch]::Frequency)
}

$timeObserverWorker = 'I1JlcXVpcmVzIC1WZXJzaW9uIDUuMQokRXJyb3JBY3Rpb25QcmVmZXJlbmNlPSdTdG9wJwokcm9vdD0nQzpcUHJvZ3JhbURhdGFcTWFya2V0QnJhaW5QYXl0bUhlYWx0aFx0aW1lLW9ic2VydmVyLXYxJwppZihbU2VjdXJpdHkuUHJpbmNpcGFsLldpbmRvd3NJZGVudGl0eV06OkdldEN1cnJlbnQoKS5Vc2VyLlZhbHVlIC1jbmUgJ1MtMS01LTE4Jyl7dGhyb3cgJ1RJTUVfT0JTRVJWRVJfU1lTVEVNX1JFUVVJUkVEJ30KJHBhdGg9Sm9pbi1QYXRoICRyb290ICdzbmFwc2hvdC5qc29uJzskc2VxdWVuY2U9MEwKZnVuY3Rpb24gUmVhZC1GaXhlZFRpbWVRdWVyeShbVmFsaWRhdGVTZXQoJy9xdWVyeSAvc3RhdHVzIC92ZXJib3NlJywnL3F1ZXJ5IC9zb3VyY2UnKV1bc3RyaW5nXSRBcmd1bWVudHMpewogICAgJHA9W0RpYWdub3N0aWNzLlByb2Nlc3NdOjpuZXcoKTskcC5TdGFydEluZm8uRmlsZU5hbWU9Sm9pbi1QYXRoICRlbnY6V0lORElSICdTeXN0ZW0zMlx3MzJ0bS5leGUnOyRwLlN0YXJ0SW5mby5Bcmd1bWVudHM9JEFyZ3VtZW50cwogICAgJHAuU3RhcnRJbmZvLlVzZVNoZWxsRXhlY3V0ZT0kZmFsc2U7JHAuU3RhcnRJbmZvLkNyZWF0ZU5vV2luZG93PSR0cnVlOyRwLlN0YXJ0SW5mby5SZWRpcmVjdFN0YW5kYXJkT3V0cHV0PSR0cnVlOyRwLlN0YXJ0SW5mby5SZWRpcmVjdFN0YW5kYXJkRXJyb3I9JHRydWUKICAgIHRyeXtpZigtbm90ICRwLlN0YXJ0KCkpe3Rocm93ICdUSU1FX09CU0VSVkVSX1NUQVJUJ307JG89JHAuU3RhbmRhcmRPdXRwdXQuUmVhZFRvRW5kQXN5bmMoKTskZT0kcC5TdGFuZGFyZEVycm9yLlJlYWRUb0VuZEFzeW5jKCk7aWYoLW5vdCAkcC5XYWl0Rm9yRXhpdCgyMDAwKSl7dGhyb3cgJ1RJTUVfT0JTRVJWRVJfVElNRU9VVCd9O2lmKC1ub3QgJG8uV2FpdCg1MDApIC1vciAtbm90ICRlLldhaXQoNTAwKSl7dGhyb3cgJ1RJTUVfT0JTRVJWRVJfRFJBSU4nfTtpZigkby5SZXN1bHQuTGVuZ3RoIC1ndCAxMjAwMCl7dGhyb3cgJ1RJTUVfT0JTRVJWRVJfU0laRSd9O0B7ZXhpdENvZGU9JHAuRXhpdENvZGU7b3V0cHV0PSRvLlJlc3VsdH19ZmluYWxseXt0cnl7aWYoLW5vdCAkcC5IYXNFeGl0ZWQpeyRwLktpbGwoKTskbnVsbD0kcC5XYWl0Rm9yRXhpdCgxMDAwKX19Y2F0Y2h7fTskcC5EaXNwb3NlKCl9Cn0KJGJvb3Q9KEdldC1DaW1JbnN0YW5jZSBXaW4zMl9PcGVyYXRpbmdTeXN0ZW0pLkxhc3RCb290VXBUaW1lLlRvVW5pdmVyc2FsVGltZSgpLlRvU3RyaW5nKCdvJykKd2hpbGUoJHRydWUpewogICAgJHN0YXJ0PVtEaWFnbm9zdGljcy5TdG9wd2F0Y2hdOjpHZXRUaW1lc3RhbXAoKQogICAgdHJ5ewogICAgICAgICRzdGF0dXM9UmVhZC1GaXhlZFRpbWVRdWVyeSAnL3F1ZXJ5IC9zdGF0dXMgL3ZlcmJvc2UnOyRzb3VyY2U9UmVhZC1GaXhlZFRpbWVRdWVyeSAnL3F1ZXJ5IC9zb3VyY2UnCiAgICAgICAgJHNlcnZpY2U9R2V0LVNlcnZpY2UgVzMyVGltZTskc3RhcnRUeXBlPShHZXQtSXRlbVByb3BlcnR5ICdIS0xNOlxTWVNURU1cQ3VycmVudENvbnRyb2xTZXRcU2VydmljZXNcVzMyVGltZScgLU5hbWUgU3RhcnQpLlN0YXJ0CiAgICAgICAgJHNlcXVlbmNlKysKICAgICAgICAkdj1Ae3ZlcnNpb249MTtib290SWQ9JGJvb3Q7c2VxdWVuY2U9JHNlcXVlbmNlO3N0YXJ0VGlja3M9JHN0YXJ0O2VuZFRpY2tzPVtEaWFnbm9zdGljcy5TdG9wd2F0Y2hdOjpHZXRUaW1lc3RhbXAoKTtmcmVxdWVuY3k9W0RpYWdub3N0aWNzLlN0b3B3YXRjaF06OkZyZXF1ZW5jeTtzdGF0dXM9JHN0YXR1cztzb3VyY2U9JHNvdXJjZTtzZXJ2aWNlPUB7c3RhdGU9W3N0cmluZ10kc2VydmljZS5TdGF0dXM7c3RhcnRUeXBlPSRzdGFydFR5cGV9fQogICAgICAgICRqc29uPSR2fENvbnZlcnRUby1Kc29uIC1EZXB0aCA1IC1Db21wcmVzcztpZihbVGV4dC5FbmNvZGluZ106OlVURjguR2V0Qnl0ZUNvdW50KCRqc29uKSAtZ3QgMTYzODQpe3Rocm93ICdUSU1FX09CU0VSVkVSX1NJWkUnfQogICAgICAgICR0ZW1wPSRwYXRoKycubmV3JztbSU8uRmlsZV06OldyaXRlQWxsVGV4dCgkdGVtcCwkanNvbixbVGV4dC5VVEY4RW5jb2RpbmddOjpuZXcoJGZhbHNlKSkKICAgICAgICBpZihbSU8uRmlsZV06OkV4aXN0cygkcGF0aCkpe1tJTy5GaWxlXTo6UmVwbGFjZSgkdGVtcCwkcGF0aCxbTWFuYWdlbWVudC5BdXRvbWF0aW9uLkxhbmd1YWdlLk51bGxTdHJpbmddOjpWYWx1ZSl9ZWxzZXtbSU8uRmlsZV06Ok1vdmUoJHRlbXAsJHBhdGgpfQogICAgfWNhdGNoe2lmKFtJTy5GaWxlXTo6RXhpc3RzKCRwYXRoKSl7W0lPLkZpbGVdOjpEZWxldGUoJHBhdGgpfTt0aHJvd30KICAgIFN0YXJ0LVNsZWVwIC1TZWNvbmRzIDEKfQo='
# Embedded by Build-TimeObserverJob.ps1. Fixed installation; no supplied commands.
$ErrorActionPreference='Stop'
$r=@{version=1;passed=$false;mode=$Mode;failure=$null;ordersEnabled=$false;credentialsUsed=$false;taskCreated=$false;healthAccountAcceptance=$false}
$root='C:\ProgramData\MarketBrainPaytmHealth\time-observer-v1';$task='MarketBrain-Time-Observer-v1';$watch=[Diagnostics.Stopwatch]::StartNew()
try{
 if($Mode -ceq 'FailureFixture'){throw 'TIME_OBSERVER_DELIBERATE_FIXTURE'}
 $id=[Security.Principal.WindowsIdentity]::GetCurrent()
 try{if(-not ([Security.Principal.WindowsPrincipal]::new($id)).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)){throw 'TIME_OBSERVER_ADMIN_REQUIRED'}}finally{$id.Dispose()}
 Assert-TimeObservationAcl 'C:\ProgramData\MarketBrainPaytmHealth'
 $account=Get-LocalUser -Name 'marketbrain-health'
 if($account.SID.Value -cne 'S-1-5-21-3041730714-102984520-3202743044-1011' -or -not $account.Enabled){throw 'TIME_OBSERVER_ACCOUNT_DRIFT'}
 $existing=@(Get-ScheduledTask|Where-Object {$_.TaskPath -ceq '\' -and $_.TaskName -ceq $task})
 if($Mode -ceq 'Observe'){
  $r.directoryPresent=Test-Path -LiteralPath $root;$r.taskPresent=($existing.Count -gt 0)
  if($r.directoryPresent){$snapshot=Join-Path $root 'snapshot.json';if(Test-Path -LiteralPath $snapshot){Assert-TimeObservationAcl $snapshot;$raw=[IO.File]::ReadAllText($snapshot);if($raw.Length -gt 16384){throw 'TIME_OBSERVER_SIZE'};$v=ConvertFrom-Json -InputObject $raw -DateKind String;$r.snapshotIdentity=@{bootId=$v.bootId;expectedBootId=(Get-TimeObservationBootId);frequency=$v.frequency;expectedFrequency=[Diagnostics.Stopwatch]::Frequency;sequence=$v.sequence;version=$v.version}};$r.workerSha256=(Get-FileHash -LiteralPath (Join-Path $root 'worker.ps1')).Hash};if($existing.Count -eq 1){$r.taskState=[string]$existing[0].State}
  $r.status='TIME_OBSERVER_INVENTORY_ONLY';$r.passed=$true;return
 }
 if((Test-Path -LiteralPath $root) -or $existing.Count){throw 'TIME_OBSERVER_EXISTING_INSTALL_REVIEW_REQUIRED'}
 $null=New-Item -ItemType Directory -Path $root
 $acl=[Security.AccessControl.DirectorySecurity]::new();$acl.SetAccessRuleProtection($true,$false)
 $acl.SetOwner([Security.Principal.SecurityIdentifier]::new('S-1-5-32-544'))
 foreach($sid in @('S-1-5-18','S-1-5-32-544',$account.SID.Value)){
  $rights=if($sid -ceq $account.SID.Value){[Security.AccessControl.FileSystemRights]::ReadAndExecute}else{[Security.AccessControl.FileSystemRights]::FullControl}
  $acl.AddAccessRule([Security.AccessControl.FileSystemAccessRule]::new([Security.Principal.SecurityIdentifier]::new($sid),$rights,'ContainerInherit,ObjectInherit','None','Allow'))
 }
 Set-Acl -LiteralPath $root -AclObject $acl;Assert-TimeObservationAcl $root
 $path=Join-Path $root 'worker.ps1';$bytes=[Convert]::FromBase64String($timeObserverWorker)
 [IO.File]::WriteAllBytes($path,$bytes);Assert-TimeObservationAcl $path
 $hash=(Get-FileHash -LiteralPath $path).Hash
 $command="if((Get-FileHash -LiteralPath '$path').Hash -cne '$hash'){exit 9};&([scriptblock]::Create([IO.File]::ReadAllText('$path')))"
 $arguments='-NoLogo -NoProfile -NonInteractive -EncodedCommand '+[Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($command))
 $exe=Join-Path $env:WINDIR 'System32\WindowsPowerShell\v1.0\powershell.exe'
 $action=New-ScheduledTaskAction -Execute $exe -Argument $arguments
 $trigger=New-ScheduledTaskTrigger -AtStartup
 $principal=New-ScheduledTaskPrincipal -UserId 'S-1-5-18' -LogonType ServiceAccount -RunLevel Highest
 $settings=New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable -MultipleInstances IgnoreNew -ExecutionTimeLimit ([TimeSpan]::Zero)
 $null=Register-ScheduledTask -TaskName $task -TaskPath '\' -Description 'MarketBrain fixed read-only Windows time observer v1' -Action $action -Trigger $trigger -Principal $principal -Settings $settings
 $r.taskCreated=$true
 $t=Get-ScheduledTask -TaskName $task -TaskPath '\'
 if($t.Actions.Count -ne 1 -or $t.Actions[0].Arguments -cne $arguments -or $t.Actions[0].Execute -ine $exe -or $t.Principal.UserId -notin @('SYSTEM','S-1-5-18') -or [string]$t.Principal.LogonType -ne 'ServiceAccount' -or $t.Triggers.Count -ne 1 -or $t.Triggers[0].CimClass.CimClassName -cne 'MSFT_TaskBootTrigger'){throw 'TIME_OBSERVER_TASK_VERIFY'}
 $r.workerSha256=$hash
 Start-ScheduledTask -TaskName $task -TaskPath '\'
 $first=$null;$last=$null
 for($i=0;$i -lt 15;$i++){
  Start-Sleep -Seconds 1
  if(Test-Path -LiteralPath (Join-Path $root 'snapshot.json')){
   $last=Read-TimeObservation
   if($first -and $last.sequence -gt $first.sequence){break}
   $first=$last
  }
 }
 if(-not $last -or -not $first -or $last.sequence -le $first.sequence){throw 'TIME_OBSERVER_NO_FRESH_SEQUENCE'}
 $r.firstSequence=$first.sequence;$r.lastSequence=$last.sequence;$r.ageSeconds=$last.ageSeconds
 $r.status='TIME_OBSERVER_SYSTEM_PASSED_HEALTH_ACCOUNT_PENDING';$r.passed=$true
}catch{
 $r.failure=if($_.Exception.Message -cmatch '^TIME_OBSERVER_[A-Z_]+$'){$_.Exception.Message}else{'TIME_OBSERVER_'+$_.Exception.GetBaseException().GetType().Name}
 $r.failureLine=$_.InvocationInfo.ScriptLineNumber
 if($r.taskCreated){try{$null=Disable-ScheduledTask -TaskName $task -TaskPath '\';Stop-ScheduledTask -TaskName $task -TaskPath '\';$r.failureStopRequested=$true}catch{$r.cleanupFailure='TIME_OBSERVER_STOP_REVIEW_REQUIRED'}}
}finally{
 $r.elapsedSeconds=$watch.Elapsed.TotalSeconds
 [IO.File]::WriteAllText($ResultPath,($r|ConvertTo-Json -Depth 6),[Text.UTF8Encoding]::new($false))
}
if(-not $r.passed){exit 1}
