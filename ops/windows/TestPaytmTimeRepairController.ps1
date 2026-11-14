# Offline controller fixtures, all privilege/task/service calls replaced before execution.
#Requires -Version 7.0
param([ValidateSet('ServiceStartup','AdaptivePolling')][string]$TestMode='ServiceStartup')
$ErrorActionPreference='Stop'
$source=Get-Content (Join-Path $PSScriptRoot 'RepairPaytmWindowsTime.ps1') -Raw
$root=Join-Path ([IO.Path]::GetTempPath()) ('mb-time-fixture-'+[guid]::NewGuid().ToString('N'))
$null=New-Item -ItemType Directory $root
$source=$source.Replace(". (Join-Path `$PSScriptRoot 'PaytmGatewayAccount.ps1')",'').Replace(". (Join-Path `$PSScriptRoot 'PaytmGatewayKeyCustody.ps1')",'').Replace(". (Join-Path `$PSScriptRoot 'PaytmTimeServiceRepair.ps1')",'').Replace('Import-Module ScheduledTasks','')
$begin=$source.IndexOf('function Protect-TimeDirectory');$end=$source.IndexOf('function Get-OwnedTimeTask')
$source=$source.Substring(0,$begin)+'function Protect-TimeDirectory([string]$p){$null=New-Item -ItemType Directory -Path $p -Force}'+[Environment]::NewLine+$source.Substring($end)
$source=$source.Replace('C:\ProgramData\MarketBrainTimeRepair',$root)
$source=$source.Replace("'68D4CCA6429665966142830CFEC6AE11819BA400A209927F01BEFA87769E6EC1'",'((Get-FileHash -LiteralPath $EvidencePath).Hash)')
$source=$source.Replace("'2D2EF859C6EAD50E44880FC1EEDA04E31EC6808CF6E997E0D80B4E56820518E3'",'((Get-FileHash -LiteralPath $EvidencePath).Hash)')
$source=$source.Replace('$PSScriptRoot',("'"+$PSScriptRoot.Replace("'","''")+"'"))
function Assert-PaytmAccountPath($p){$p}
function Assert-PaytmCustodyController {}
function Get-PaytmTimeRepairSnapshot {@{state='Running';startType=2}}
function Assert-PaytmTimeRepairBaseline($v){}
function Assert-PaytmPollingBaseline($v){}
function Assert-PaytmPollingPreserved($a,$b,$c){}
function Assert-PaytmTimeRepairPreserved($a,$b){}
function New-ScheduledTaskAction {param($Execute,$Argument,$WorkingDirectory) @{Execute=$Execute;Arguments=$Argument;WorkingDirectory=$WorkingDirectory}}
function New-ScheduledTaskPrincipal {param($UserId,$LogonType,$RunLevel) @{UserId=$UserId;LogonType=$LogonType;RunLevel=$RunLevel}}
function New-ScheduledTaskSettingsSet {param($MultipleInstances,$ExecutionTimeLimit,[switch]$AllowStartIfOnBatteries,[switch]$DontStopIfGoingOnBatteries) @{}}
function Register-ScheduledTask {param($TaskName,$TaskPath,$Action,$Principal,$Settings,$ErrorAction) $script:task=@{Actions=@($Action);Principal=$Principal;Triggers=@();State='Ready'}}
function Get-ScheduledTask {param($TaskName,$TaskPath,$ErrorAction) $script:task}
function Get-ScheduledTaskInfo {param($TaskName,$TaskPath) @{LastTaskResult=0}}
function Start-ScheduledTask {param($TaskName,$TaskPath)
 $a=$script:task.Actions[0];$id=Split-Path $a.WorkingDirectory -Leaf
 $status=if($script:scenario -eq 'workerFailure'){'REVIEW_REQUIRED'}elseif($TestMode -eq 'AdaptivePolling'){'TIME_POLLING_CHANGED_SYNC_OBSERVED_RELEASE_PENDING'}else{'TIME_SERVICE_RUNNING_AUTOMATIC_RESYNC_ACCEPTED_ALIGNMENT_PENDING'}
 if($script:scenario -eq 'identity'){$id='incorrect'}
 @{runId=$id;completed=$true;status=$status;failure=$null;cleanupFailure=$null}|ConvertTo-Json|Set-Content (Join-Path $a.WorkingDirectory 'worker.json')
}
function Unregister-ScheduledTask {param($TaskName,$TaskPath,$Confirm) if($script:scenario -eq 'cleanup'){throw 'fixture cleanup failure'};$script:task=$null}
function Stop-ScheduledTask {param($TaskName,$TaskPath) throw 'Unexpected stop'}
$passed=0
foreach($script:scenario in @('pass','workerFailure','identity','cleanup')){
 $out=Join-Path $root $script:scenario;$e=Join-Path $root 'evidence.json';'{}'|Set-Content $e
 $err=$null;try{& ([scriptblock]::Create($source)) -EvidencePath $e -OutputDirectory $out -Mode $TestMode}catch{$err=$_.Exception.Message}
 $r=Get-Content (Get-ChildItem $out -Filter '*.json').FullName -Raw|ConvertFrom-Json
 $expected=if($TestMode -eq 'AdaptivePolling'){'TIME_POLLING_CHANGED_SYNC_OBSERVED_RELEASE_PENDING'}else{'TIME_SERVICE_REPAIRED_ALIGNMENT_RECHECK_PENDING'}
 if($script:scenario -eq 'pass'){if($err -or $r.status -ne $expected -or -not $r.taskRemoved){throw 'controller success fixture failed'}}else{if(-not $err -or $r.status -ne 'REVIEW_REQUIRED'){throw "controller failure fixture failed: $script:scenario"}}
 if($r.clockAlignmentVerified -or $r.ordersEnabled){throw 'False readiness'}
 $passed++
}
Write-Host "PASS: $passed offline controller workflows. Fixture evidence: $root"
