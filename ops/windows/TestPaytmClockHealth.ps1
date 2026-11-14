# Offline tests only. No service, network, clock or task changes.
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'PaytmTimeServiceRepair.ps1')
. (Join-Path $PSScriptRoot 'PaytmClockHealth.ps1')
function Get-PaytmTimeRepairSnapshot {@{state='Running';startType=2;ntpServer='time.windows.com,0x9'}}
function Invoke-PaytmTimeRepairNative($Tool,$Arguments,$Seconds){
 if($Tool -ne 'w32tm.exe' -or $Arguments -notmatch '^/(query|stripchart) '){throw 'Unexpected mutation'}
 if($script:mode -eq 'timeout' -and $Arguments -like '/stripchart *'){throw 'fixture timeout'}
 $output=switch($Arguments){
 '/query /status /verbose'{if($script:mode -eq 'unsync'){"Leap Indicator: 3`nStratum: 0`nLast Sync Error: 1"}elseif($script:mode -eq 'unknown'){'unrecognized'}else{"Leap Indicator: 0`nStratum: 3`nLast Sync Error: 0"}}
 '/query /source'{'time.windows.com,0x9'}
 '/query /peers /verbose'{'fixture peer'}
 default{if($script:mode -eq 'missing'){'Error: timeout'}elseif($script:mode -eq 'offset'){"01:00:00, +06.000s`n01:00:02, +00.010s`n01:00:04, +00.020s"}else{"01:00:00, +00.006s`n01:00:02, +00.014s`n01:00:04, +00.019s"}}
 };@{arguments=$Arguments;exitCode=0;output=$output}
}
$count=0
foreach($script:mode in @('pass','unsync','unknown','timeout','missing','offset','short')){
 $r=@{rounds=@();status='REVIEW_REQUIRED'};$script:elapsed=0;$script:saves=0;$script:waits=0
 Invoke-PaytmClockHealthBatch $r {$script:saves++} {$script:waits++;$script:elapsed+= $(if($script:mode -eq 'short'){10}else{35})} {$script:elapsed}
 if($r.assessment.boundedObservationPassed -ne ($script:mode -eq 'pass')){throw "Wrong assessment $script:mode"};$count++
 if($r.rounds.Count -ne 3 -or $script:saves -ne 3 -or $script:waits -ne 2){throw 'Collection/checkpoint count'};$count++
 if($r.assessment.releaseApproved -or $r.assessment.durableSynchronizationProven -or $r.assessment.quoteTimingApproved){throw 'Overstated proof'};$count++
}
foreach($n in @('ReviewPaytmClockHealth.ps1','PaytmClockHealth.ps1')){
 $t=$null;$e=$null;$null=[Management.Automation.Language.Parser]::ParseFile((Join-Path $PSScriptRoot $n),[ref]$t,[ref]$e);if($e.Count){throw 'Syntax failure'};$count++
}
Write-Host "PASS: $count assertions across seven mocked clock-health batches."
