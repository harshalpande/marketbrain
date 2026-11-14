# Offline fixtures only; no native commands, sleeps, service or clock changes.
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'PaytmTimeServiceRepair.ps1')
function Get-PaytmTimeRepairSnapshot {
 [pscustomobject]@{state='Running';startType=2;imagePath=($env:WINDIR+'\system32\svchost.exe -k LocalService');account='NT AUTHORITY\LocalService';sddl=$(if($script:drift){'changed'}else{'D:(A;;CCDCLCSWRPWPDTLOCRSDRCWDWO;;;SY)(A;;CCLCSWLOCRRC;;;BA)(A;;CCLCSWLOCRRC;;;IU)S:(AU;FA;CCDCLCSWRPWPDTLOCRSDRCWDWO;;;WD)'});policyPresent=$false;type='NTP';ntpServer=$script:peer;ntpClientEnabled=1}
}
function Wait-PaytmPollingSample {}
function Invoke-PaytmTimeRepairNative($Tool,$Arguments,$Seconds){
 $script:calls+=,$Arguments;$code=0;$out='The command completed successfully.'
 switch -Wildcard ($Arguments){
 '*manualpeerlist:time.windows.com,0x8*' {$script:peer='time.windows.com,0x8';if($script:mode -eq 'config'){$code=1};if($script:mode -eq 'drift'){$script:drift=$true}}
 '*manualpeerlist:time.windows.com,0x9*' {if($script:mode -eq 'rollback'){$code=1}else{$script:peer='time.windows.com,0x9'}}
 '/resync /rediscover' {if($script:mode -in @('resync','rollback')){$out='The computer did not resync because no time data was available.'}}
 '/query /status /verbose' {if($script:mode -eq 'status'){$out="Leap Indicator: 3`nStratum: 0`nLast Sync Error: 1"}elseif($script:mode -eq 'timeout'){throw 'fixture timeout'}else{$out="Leap Indicator: 0`nStratum: 4`nLast Sync Error: 0"}}
 '/query /source' {$out=$script:peer}
 }
 @{arguments=$Arguments;output=$out;exitCode=$code}
}
$count=0
foreach($script:mode in @('pass','config','resync','status','timeout','rollback','drift','baseline')){
 $script:peer=if($script:mode -eq 'baseline'){'other.example'}else{'time.windows.com,0x9'};$script:drift=$false;$script:calls=@();$script:saves=0
 $r=@{commands=@();mutationAttempted=$false;status='REVIEW_REQUIRED';cleanupFailure=$null};$err=$null
 try{Invoke-PaytmPollingSequence $r {$script:saves++}}catch{$err=$_.Exception.Message}
 if($script:mode -eq 'pass'){if($err -or $r.status -ne 'TIME_POLLING_CHANGED_SYNC_OBSERVED_RELEASE_PENDING' -or $r.samples.Count -ne 3 -or $script:peer -ne 'time.windows.com,0x8'){throw 'Pass fixture failed'}}else{if(-not $err -or $r.status -ne 'REVIEW_REQUIRED'){throw "Failure fixture: $script:mode"}};$count++
 if($script:mode -in @('config','resync','status','timeout')){if(-not $r.rollbackVerified -or $script:peer -ne 'time.windows.com,0x9'){throw 'Rollback failed'};$count++}
 if($script:mode -in @('rollback','drift')){if(-not $r.cleanupFailure -or $r.rollbackVerified){throw 'Rollback failure hidden'};$count++}
 if($script:mode -eq 'drift' -and @($script:calls|Where-Object {$_ -like '*0x9*'}).Count){throw 'Unexpected overwrite on drift'}
 if($script:mode -eq 'baseline' -and ($script:calls.Count -or $r.mutationAttempted)){throw 'Baseline mutation'}
 if($script:mode -ne 'baseline' -and $script:saves -lt 2){throw 'Missing checkpoint'};$count++
}
Write-Host "PASS: $count polling assertions across eight mocked workflows."
