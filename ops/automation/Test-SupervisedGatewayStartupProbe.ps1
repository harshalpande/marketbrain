#Requires -Version 7.2
$ErrorActionPreference='Stop'
. "$PSScriptRoot/SupervisedGatewayStartupProbe.ps1"
$script:state='Running';$script:mutations=0
function Get-ScheduledTask {param($TaskName,$TaskPath,$ErrorAction) [pscustomobject]@{State=$script:state;Description='MarketBrain locked supervisor ea8b91471cf048aa97a0f6b939b355c7';Actions=@()}}
function Enable-ScheduledTask {$script:mutations++;throw 'UNEXPECTED_MUTATION'}
function Start-ScheduledTask {$script:mutations++;throw 'UNEXPECTED_MUTATION'}
function Stop-ScheduledTask {$script:mutations++;throw 'UNEXPECTED_MUTATION'}
function Disable-ScheduledTask {$script:mutations++;throw 'UNEXPECTED_MUTATION'}
$r=Invoke-SupervisedGatewayStartupProbe
if($r.failure -ne 'STARTUP_TASK_NOT_DISABLED_OR_OWNED' -or $r.started -or $script:mutations){throw 'ACTIVE_TASK_GUARD_FAILED'}
$script:state='Disabled';$r=Invoke-SupervisedGatewayStartupProbe
if($r.failure -ne 'STARTUP_TASK_ACTION_DRIFT' -or $r.started -or $script:mutations){throw 'TASK_ACTION_GUARD_FAILED'}
Write-Host 'GATEWAY_STARTUP_NO_MUTATION_GUARDS_PASSED'
