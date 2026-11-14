# No service changes. Exercises semantic status checks and the actual zero-exit failure text.
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'PaytmTimeServiceRepair.ps1')
$good="Leap Indicator: 0(no warning)`nStratum: 3`nLast Sync Error: 0 (The command completed successfully.)"
$bad="Leap Indicator: 3(not synchronized)`nStratum: 0 (unspecified)`nLast Sync Error: 1 (The computer did not resync because no time data was available.)"
$count=0
foreach($case in @(@($good,'time.windows.com,0x9',0,$true),@($bad,'time.windows.com,0x9',0,$false),@($good,'Local CMOS Clock',0,$false),@('unknown localized status','time.windows.com',0,$false),@($good,'time.windows.com',1,$false),@($good.Replace('Stratum: 3','Stratum: 16'),'time.windows.com',0,$false),@($good.Replace('Last Sync Error: 0','Last Sync Error: 1'),'time.windows.com',0,$false))){
 $a=Get-PaytmTimeSyncAssessment @{output=$case[0];exitCode=$case[2]} @{output=$case[1];exitCode=0}
 if($a.synchronizedReported -ne $case[3] -or $a.alignmentVerified -or $a.absoluteAccuracyProven){throw 'Semantic assessment failure'};$count++
}
function Get-PaytmTimeRepairSnapshot {@{}}
function Assert-PaytmTimeRepairBaseline($v){}
function Wait-PaytmTimeRepairRunning {}
function Invoke-PaytmTimeRepairNative($Tool,$Arguments,$Seconds){@{arguments=$Arguments;exitCode=0;output=$(switch($Arguments){'/resync /rediscover'{"Sending resync command to local computer`nThe computer did not resync because no time data was available."};'/query /status /verbose'{$bad};'/query /source'{'time.windows.com,0x9'};default{'SUCCESS'}})}}
$r=@{commands=@();status='REVIEW_REQUIRED'};$errorText=$null
try{Invoke-PaytmTimeRepairSequence $r {}}catch{$errorText=$_.Exception.Message}
if($errorText -ne 'TIME_REPAIR_RESYNC_NOT_ACCEPTED' -or $r.status -ne 'REVIEW_REQUIRED' -or $r.commands.Count -ne 5){throw 'Zero-exit semantic failure regression'};$count++
Write-Host "PASS: $count time-status regressions."
