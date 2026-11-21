#Requires -Version 7.2
$ErrorActionPreference='Stop'
. "$PSScriptRoot/PaytmQuoteBatch.ps1"
function Samples {
 @(1..3|ForEach-Object {@{status='FRESH_QUOTE_OBSERVED';fresh=$true;ordersEnabled=$false;securityId=2885;exchange='NSE';scripType='EQUITY';timestampEpoch='PAYTM_1980_SECONDS';observedEpochMilliseconds=(20000+$_*5000);tradeEpochMilliseconds=(20000+$_*5000-100);ageMilliseconds=100;lastPrice=1377.5}})
}
$s=Samples;$r=Get-PaytmQuoteBatchAssessment $s 2885 -RequireFresh
if(-not $r.passed -or $r.freshCount -ne 3){throw 'FRESH_FIXTURE_FAILED'}
$s=Samples;foreach($q in $s){$q.status='STALE_QUOTE';$q.fresh=$false;$q.tradeEpochMilliseconds=1;$q.ageMilliseconds=$q.observedEpochMilliseconds-1}
if((Get-PaytmQuoteBatchAssessment $s 2885 -RequireFresh).passed){throw 'STALE_ACCEPTED'}
$s=@(1..3|ForEach-Object {@{status='NO_QUOTE';fresh=$false;ordersEnabled=$false}})
if((Get-PaytmQuoteBatchAssessment $s 2885 -RequireFresh).missingCount -ne 3){throw 'MISSING_FIXTURE_FAILED'}
foreach($case in @('identity','age','price','duplicate','falseFresh')){
 $s=Samples
 switch($case){identity{$s[0].securityId=1};age{$s[0].ageMilliseconds=1};price{$s[0].lastPrice=0};duplicate{$s[1]=$s[0]};falseFresh{$s[0].ageMilliseconds=20000;$s[0].tradeEpochMilliseconds=$s[0].observedEpochMilliseconds-20000}}
 $failed=$false;try{$null=Get-PaytmQuoteBatchAssessment $s 2885 -RequireFresh}catch{$failed=$true}
 if(-not $failed){throw "NEGATIVE_NOT_CAUGHT_$case"}
}
Write-Host 'QUOTE_BATCH_8_FIXTURES_PASSED'
