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
# Actual controller workflow with task/ACL calls replaced; never creates a real task.
function Assert-TimeObservationAcl {}
function Read-TimeObservation {return @{sequence=1;ageSeconds=1}}
function Get-Acl {return [Security.AccessControl.DirectorySecurity]::new()}
function Set-Acl {}
function New-ScheduledTaskAction {param($Execute,$Argument) @{Execute=$Execute;Arguments=$Argument}}
function New-ScheduledTaskPrincipal {param($UserId,$LogonType,$RunLevel) @{UserId=$UserId;LogonType=$LogonType;RunLevel=$RunLevel}}
function New-ScheduledTaskSettingsSet {}
function Register-ScheduledTask {param($TaskName,$TaskPath,$Action,$Principal,$Settings) $script:task=@{TaskName=$TaskName;TaskPath=$TaskPath;Actions=@($Action);Principal=$Principal;Triggers=@();State='Ready'};if($script:case -eq 'drift'){$script:task.Principal.RunLevel='Highest'}}
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
foreach($script:case in @('valid','drift','badWorker','cleanup')){
 $root=Join-Path ([IO.Path]::GetTempPath()) ('mb-time-account-fixture-'+[guid]::NewGuid().ToString('N'))
 $null=New-Item -ItemType Directory -Path $root
 $script:task=$null;$script:started=0
 $result=& ([scriptblock]::Create($original.Replace('C:\ProgramData\MarketBrainPaytmHealth\time-observer-v1',$root))) 'fixture'
 if($result.passed -ne ($case -eq 'valid')){throw "Workflow result incorrect: $case $($result.failure)"}
 if($case -eq 'drift' -and $started){throw 'Drifted task started'}
 if($case -ne 'cleanup' -and -not $result.taskRemoved){throw 'Temporary task not removed'}
 if($case -eq 'cleanup' -and -not $result.cleanupFailure){throw 'Cleanup failure not retained'}
}
Write-Host 'TIME_ACCOUNT_PROBE_FIXTURES_PASSED: 10 result cases, generated PS5 worker and 4 isolated workflows.'
