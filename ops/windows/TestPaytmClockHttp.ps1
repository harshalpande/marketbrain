#Requires -Version 7.0
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'PaytmClockComparison.ps1')
$checks=0
function Check([bool]$Value,[string]$Label){if(-not $Value){throw "FAIL: $Label"};$script:checks++}
function Reject([scriptblock]$Action,[string]$Label){$message='';try{&$Action|Out-Null}catch{$message=$_.Exception.Message};Check ($message -ceq 'CLOCK_APPLICATION_READ_FAILED') $Label}
$global:clockHttpMode='pass'
function Invoke-WebRequest {
    param($Uri,$Method,$Headers,[switch]$NoProxy,$TimeoutSec,$MaximumRedirection,[switch]$SkipHttpErrorCheck)
    Check ($Uri -ceq 'http://127.0.0.1:8080/api/v1/paper/account/overview' -and $Method -ceq 'Get') 'fixed local read endpoint'
    Check ($NoProxy -and $TimeoutSec -eq 15 -and $MaximumRedirection -eq 0 -and $SkipHttpErrorCheck) 'no proxy redirects unbounded request'
    Check ($Headers['X-MarketBrain-Paper-Read-Token'] -ceq 'PRIVATE_TOKEN') 'header not command argument'
    if($global:clockHttpMode -eq 'exception'){throw 'PRIVATE_EXCEPTION_WITH_TOKEN'}
    $v=@{version='PAPER_ACCOUNT_OVERVIEW_V2';status='READ_ONLY_EXECUTION_BLOCKED';currency='INR';observedAtUtc='2026-10-22T15:00:00.123456789Z';account=$null;activeAccountsObserved=0;activeAccountCountIsLowerBound=$false;legacyOrdersPresent=$false;legacyFillsPresent=$false;migrationAssessment='REVIEW_REQUIRED';blockers=@('AUTHENTICATED_APPROVAL_AND_RISK_INTEGRATION_PENDING','FILL_COST_AND_PNL_POLICY_PENDING','LEDGER_RECONCILIATION_REQUIRED');databaseWritesPerformed=$false;actionExecutionEnabled=$false;liveExecutionEnabled=$false;ledger=@{status='REVIEW_REQUIRED';cash=$null;reservedCash=$null;unreservedCash=$null;revision=$null}}
    if($global:clockHttpMode -eq 'unsafe'){$v.actionExecutionEnabled=$true}
    if($global:clockHttpMode -eq 'time'){$v.observedAtUtc='yesterday'}
    if($global:clockHttpMode -eq 'offset'){$v.observedAtUtc='2026-10-22T15:00:00+05:30'}
    @{StatusCode=$(if($global:clockHttpMode -eq 'http'){302}else{200});Headers=@{'Cache-Control'=$(if($global:clockHttpMode -eq 'cache'){'public'}else{'no-store'})};Content=($v|ConvertTo-Json -Depth 5)}
}
$value=Invoke-PaytmClockApplication 'PRIVATE_TOKEN'
Check ($value.ToString('o') -ceq '2026-10-22T15:00:00.1234567+00:00') 'Java nanoseconds parsed without changing UTC'
foreach($mode in @('exception','unsafe','time','offset','http','cache')){
    $global:clockHttpMode=$mode
    Reject {Invoke-PaytmClockApplication 'PRIVATE_TOKEN'} "private sanitized rejection $mode"
}
Write-Host "PASS: $checks HTTP boundary assertions; no actual HTTP or credentials."
