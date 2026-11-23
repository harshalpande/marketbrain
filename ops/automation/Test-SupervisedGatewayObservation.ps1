#Requires -Version 7.2
$ErrorActionPreference='Stop'
. "$PSScriptRoot/SupervisedGatewayObservation.ps1"
function Get-ScheduledTask {param($TaskName,$TaskPath,$ErrorAction)
 if($TaskName -cne 'MarketBrain-Gateway-Supervisor-v1' -or $TaskPath -cne '\'){throw 'WRONG_TASK'}
 [pscustomobject]@{State='Disabled';Actions='SECRET_SENTINEL';Settings=[pscustomobject]@{Enabled=$false;AllowDemandStart=$true;DisallowStartIfOnBatteries=$false;StopIfGoingOnBatteries=$false;RunOnlyIfIdle=$false;RunOnlyIfNetworkAvailable=$false;StartWhenAvailable=$false;MultipleInstances='IgnoreNew';ExecutionTimeLimit='PT72H';IdleSettings=@{StopOnIdleEnd=$true;RestartOnIdle=$false}}}
}
function Get-ScheduledTaskInfo {param($TaskName,$TaskPath,$ErrorAction) [pscustomobject]@{LastTaskResult=0;LastRunTime=[datetime]'2026-11-23';NumberOfMissedRuns=0}}
function Get-CimInstance {param($ClassName,$ErrorAction) [pscustomobject]@{BatteryStatus=2;EstimatedChargeRemaining=90;Name='SECRET_SENTINEL'}}
function Get-WinEvent {param($ListLog,$ErrorAction) [pscustomobject]@{IsEnabled=$false}}
$r=Get-SupervisedGatewayTaskObservation
if($r.task.state -ne 'Disabled' -or -not $r.task.settings.AllowDemandStart -or $r.batteries[0].batteryStatus -ne 2 -or $r.eventLogEnabled){throw 'TASK_OBSERVATION_FIXTURE_FAILED'}
if(($r|ConvertTo-Json -Depth 8) -match 'SECRET_SENTINEL'){throw 'SECRET_FILTER_FAILED'}
function Get-ScheduledTask {throw [UnauthorizedAccessException]::new('SECRET_SENTINEL')}
$r=Get-SupervisedGatewayTaskObservation
if($r.taskError -ne 'UnauthorizedAccessException' -or ($r|ConvertTo-Json -Depth 8) -match 'SECRET_SENTINEL'){throw 'ERROR_FILTER_FAILED'}
Write-Host 'GATEWAY_TASK_OBSERVATION_FIXTURES_PASSED'
