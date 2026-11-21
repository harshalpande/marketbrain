#Requires -Version 7.2
$ErrorActionPreference='Stop'
. "$PSScriptRoot/SupervisedBoundaryProbe.ps1"
$script:calls=0;$script:bad=$false
function Invoke-WebRequest {
 param($Uri,$Method,$NoProxy,$TimeoutSec,$MaximumRedirection,$SkipHttpErrorCheck,$Headers,$ContentType,$Body)
 $script:calls++
 if($Uri -notlike 'http://127.0.0.1:8080/*' -or $TimeoutSec -ne 8 -or -not $NoProxy -or $MaximumRedirection -ne 0){throw 'UNBOUNDED_REQUEST'}
 if($Headers['X-MarketBrain-Paper-Read-Token'] -and $Headers['X-MarketBrain-Paper-Read-Token'] -ne 'invalid-fixture'){throw 'REAL_TOKEN_NOT_ALLOWED'}
 $code=if($Uri -like '*/api/v1/*'){401}else{400}
 if($script:bad -and $script:calls -eq 1){$code=200}
 return @{StatusCode=$code;Headers=@{'Cache-Control'=@('no-store')}}
}
$r=Invoke-SupervisedBoundaryProbe
if(-not $r.passed -or $r.checks.Count -ne 7 -or $script:calls -ne 7){throw 'PROBE_POSITIVE_FIXTURE_FAILED'}
$script:bad=$true;$script:calls=0
$r=Invoke-SupervisedBoundaryProbe
if($r.passed -or $r.checks[0].passed){throw 'PROBE_UNEXPECTED_SUCCESS_NOT_CAUGHT'}
Write-Host 'SUPERVISED_BOUNDARY_7_CASES_AND_FAILURE_FIXTURE_PASSED'
