#Requires -Version 7.2
$ErrorActionPreference='Stop'
. "$PSScriptRoot/SupervisedUniverseProbe.ps1"
$script:scenario='good';$script:httpCalls=0
function Invoke-UniverseDocker([string[]]$Arguments){
 if($Arguments[0] -eq 'ps'){if($script:scenario -eq 'multiple'){return "abcdef123456`n123456abcdef"};return 'abcdef123456'}
 if($Arguments[0] -ne 'exec' -or $Arguments[2] -ne 'printenv' -or $Arguments[3] -ne 'MARKETBRAIN_PAPER_READ_TOKEN'){throw 'BAD_DOCKER_COMMAND'}
 return ('a'*40)
}
function Invoke-RestMethod {
 param($Uri,$Method,[switch]$NoProxy,$TimeoutSec,$MaximumRedirection,$Headers,$ContentType,$Body)
 $script:httpCalls++
 if($Uri -cne 'http://127.0.0.1:8080/api/v1/paytm/supervised/universe-match' -or $Method -ne 'Post' -or -not $NoProxy -or $TimeoutSec -ne 10 -or $MaximumRedirection -ne 0 -or $Body -cne '{"symbol":"RELIANCE"}' -or $Headers['X-MarketBrain-Paper-Read-Token'] -cne ('a'*40)){throw 'BAD_REQUEST'}
 if($script:scenario -eq 'exception'){throw 'SECRET_MUST_NOT_LEAVE'}
 return [pscustomobject]@{status='LOCAL_SNAPSHOT_SYMBOL_ISIN_MATCHED';snapshotMatched=$true;ordersEnabled=$false;symbol='RELIANCE';snapshotId='11111111-1111-1111-1111-111111111111';observedOn='2026-09-18';isin='INE002A01018';instrumentId=123;currentMembershipVerified=($script:scenario -eq 'claim');providerIsinVerified=$false;secret='SECRET_MUST_NOT_LEAVE'}
}
$r=Invoke-SupervisedUniverseProbe
if(-not $r.passed -or $r.universeMatch.isin -ne 'INE002A01018' -or ($r|ConvertTo-Json -Depth 8) -match 'SECRET_MUST_NOT_LEAVE'){throw 'POSITIVE_OR_REDACTION_FAILED'}
foreach($scenario in @('claim','exception','multiple')){
 $script:scenario=$scenario;$script:httpCalls=0;$r=Invoke-SupervisedUniverseProbe
 if($r.passed -or ($r|ConvertTo-Json -Depth 8) -match 'SECRET_MUST_NOT_LEAVE'){throw 'NEGATIVE_OR_REDACTION_FAILED'}
 if($scenario -eq 'multiple' -and $script:httpCalls -ne 0){throw 'AMBIGUOUS_CONTAINER_USED'}
}
Write-Host 'SUPERVISED_UNIVERSE_PROBE_4_FIXTURES_PASSED'
