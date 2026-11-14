#Requires -Version 7.0
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'PaytmLiveHealthCollector.ps1')
. (Join-Path $PSScriptRoot 'PaytmHealthPublisher.ps1')
function Get-PaytmTimeRepairSnapshot { @{state='Running';startType=2} }
function Invoke-PaytmTimeRepairNative { @{exitCode=0;output='fixture'} }
function New-PaytmClockSshArguments { @('fixture') }
function Invoke-PaperRuntimeProcess {
 if($script:mode -eq 'throw'){throw 'private exception that must not be reported'}
 @{exitCode=-1;stdout='private output';stderr='private error'}
}
function Invoke-PaytmHealthHttp($Command,$Token,$Body){
 if($Command -eq 'challenge'){return @{status='CHALLENGE';healthContractVersion='SERVER_TRANSPORT_V2';bootId=('1'*8+'-1111-1111-1111-'+('1'*12));challenge=('2'*8+'-2222-2222-2222-'+('2'*12));validForSeconds=10;accepted=$false;ordersEnabled=$false}}
 if($Body.synchronizedClock -or $Body.transportHealthy){throw 'Unhealthy collection submitted as healthy'}
 @{healthContractVersion='SERVER_TRANSPORT_V2';bootId=$Body.bootId;accepted=$false;ordersEnabled=$false;status='UNHEALTHY_AND_LOCKED'}
}
foreach($script:mode in @('throw','exit')){
 $script:t=0
 $r=Invoke-PaytmHealthPublishOnce ('T'*64) { $script:row=Invoke-PaytmLiveHealthRound 'fixture' 'fixture' 'fixture';return $script:row } { $script:t+=9;return $script:t }
 if($row.failedPhase -cne 'VPS_SSH' -or $row.assessment.collectionPassed -or $r.collectionPhase -cne 'VPS_SSH' -or -not $r.windowExceeded -or $r.failure -cne 'HEALTH_PUBLISHER_COLLECTION_FAILED' -or $r.status -cne 'HEALTH_REJECTED_LOCK_CONFIRMED'){throw 'Lost failure or window evidence'}
 if(($row|ConvertTo-Json -Depth 8) -match 'private'){throw 'Private process detail leaked'}
}
Write-Host 'PASS: 2 actual collector/publisher failure paths; no native, SSH or HTTP calls.'
