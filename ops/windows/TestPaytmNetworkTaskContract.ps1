#Requires -Version 5.1
# Read-only native CIM construction. Does not register or start a task.
$ErrorActionPreference='Stop'
Import-Module ScheduledTasks
. ([scriptblock]::Create([IO.File]::ReadAllText((Join-Path $PSScriptRoot 'PaytmGatewayNetwork.ps1'))))
function Get-PaytmHostContract { @{executable='C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe'} }
$g=@{runId=('a'*32);name=('MarketBrain-Network-Test-'+('a'*32));arguments='-NoProfile';root='C:\ProgramData\MarketBrainPaytmGateway\supervisor-v1'}
$a=New-ScheduledTaskAction -Execute (Get-PaytmHostContract).executable -Argument $g.arguments -WorkingDirectory $g.root
$p=New-ScheduledTaskPrincipal -UserId 'S-1-5-18' -LogonType ServiceAccount -RunLevel Highest
$s=New-ScheduledTaskSettingsSet -MultipleInstances IgnoreNew -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries
$s.ExecutionTimeLimit='PT5M'
$t=New-ScheduledTask -Action $a -Principal $p -Settings $s -Trigger (New-ScheduledTaskTrigger -AtStartup) -Description $g.runId
function Get-PaytmProbeTask { $t }
$null=Assert-PaytmNetworkGuardTask $g
[pscustomobject]@{status='NATIVE_TASK_CONTRACT_PASSED';assertions=1;nativeCimConstruction=$true;taskRegistered=$false}|ConvertTo-Json
