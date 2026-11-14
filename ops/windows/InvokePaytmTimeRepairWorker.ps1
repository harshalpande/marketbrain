#Requires -Version 5.1
param([string]$RunId,[string]$HelperHash)
$ErrorActionPreference='Stop'
if($RunId -cnotmatch '^[a-f0-9]{32}$' -or $HelperHash -cnotmatch '^[A-F0-9]{64}$'){throw 'TIME_REPAIR_WORKER_ARGUMENTS'}
if([Security.Principal.WindowsIdentity]::GetCurrent().User.Value -cne 'S-1-5-18'){throw 'TIME_REPAIR_SYSTEM_REQUIRED'}
if($PSScriptRoot -ine ('C:\ProgramData\MarketBrainTimeRepair\'+$RunId)){throw 'TIME_REPAIR_WORKER_LOCATION'}
$helper=Join-Path $PSScriptRoot 'helper.ps1'
if((Get-FileHash -LiteralPath $helper).Hash -cne $HelperHash){throw 'TIME_REPAIR_HELPER_HASH'}
. $helper
$report=@{version=1;runId=$RunId;status='REVIEW_REQUIRED';completed=$false;failure=$null;cleanupFailure=$null;mutationAttempted=$false;resyncRequested=$false;commands=@();securityChanged=$null;timeServersChanged=$null;absoluteAccuracyProven=$false}
function Save-TimeWorker {[IO.File]::WriteAllText((Join-Path $PSScriptRoot 'worker.json'),($report|ConvertTo-Json -Depth 10),[Text.UTF8Encoding]::new($false))}
$exitCode=1
try{Invoke-PaytmTimeRepairSequence $report {Save-TimeWorker};$exitCode=0}catch{$report.failure=$_.Exception.Message}
finally{
 if($report.mutationAttempted){try{$report.after=Get-PaytmTimeRepairSnapshot;$report.securityChanged=($report.before.sddl -cne $report.after.sddl);$report.timeServersChanged=($report.before.ntpServer -cne $report.after.ntpServer);Assert-PaytmTimeRepairPreserved $report.before $report.after}catch{$report.cleanupFailure=$_.Exception.Message;$report.status='REVIEW_REQUIRED';$exitCode=1}}
 $report.completed=$true;Save-TimeWorker
}
exit $exitCode
