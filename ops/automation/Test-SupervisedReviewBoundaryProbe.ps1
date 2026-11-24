#Requires -Version 7.2
$ErrorActionPreference='Stop'
. "$PSScriptRoot/SupervisedBoundaryProbe.ps1"
$script:locked=$true;$script:requests=0;$script:bad=$false
function Invoke-UniverseDocker {param($Arguments) if($Arguments[0] -eq 'ps'){'a'*12}else{'b'*40}}
function Invoke-RestMethod {param($Uri,$Method,[switch]$NoProxy,$TimeoutSec,$MaximumRedirection,$Headers)
 if($Uri -ne 'http://127.0.0.1:8080/api/v1/paytm/supervised/status' -or -not $NoProxy -or $TimeoutSec -ne 8){throw 'UNEXPECTED_REQUEST'}
 @{status=$(if($script:locked){'LOCKED'}else{'READ_ACCESS_VERIFIED'});ordersEnabled=$false}
}
function Invoke-WebRequest {param($Uri,$Method,[switch]$NoProxy,$TimeoutSec,$MaximumRedirection,[switch]$SkipHttpErrorCheck,$Headers,$ContentType,$Body)
 $script:requests++
 if($Uri -ne 'http://127.0.0.1:8080/api/v1/paytm/supervised/review-quote' -or -not $NoProxy -or $TimeoutSec -ne 8 -or $MaximumRedirection -ne 0){throw 'UNEXPECTED_REQUEST'}
 $denied=($Headers.Count -gt 2)
 @{StatusCode=$(if($denied){401}else{200});Headers=@{'Cache-Control'=@('no-store')};Content=(@{status=$(if($denied){'UNAUTHORIZED'}else{'SUPERVISED_SESSION_LOCKED'});reviewEligible=$script:bad;ordersEnabled=$false}|ConvertTo-Json -Compress)}
}
$r=Invoke-SupervisedReviewBoundaryProbe
if(-not $r.passed -or $r.checks.Count -ne 6 -or $script:requests -ne 6 -or ($r|ConvertTo-Json -Depth 8).Contains(('b'*40))){throw 'REVIEW_POSITIVE_OR_SECRET_FIXTURE_FAILED'}
$script:bad=$true;$r=Invoke-SupervisedReviewBoundaryProbe
if($r.passed){throw 'FORGED_ELIGIBILITY_NOT_CAUGHT'}
$script:locked=$false;$script:requests=0;$r=Invoke-SupervisedReviewBoundaryProbe
if($r.passed -or $script:requests -ne 0 -or $r.failure -ne 'REVIEW_SESSION_MUST_BE_LOCKED'){throw 'ACTIVE_SESSION_GUARD_FAILED'}
Write-Host 'REVIEW_BOUNDARY_SIX_CASES_AND_TWO_NEGATIVE_FIXTURES_PASSED'
