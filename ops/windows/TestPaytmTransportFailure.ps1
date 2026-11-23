#Requires -Version 7.2
$ErrorActionPreference='Stop'
. "$PSScriptRoot/PaytmTransportFailure.ps1"
foreach($case in @('pass','auth','stop','limit','lock','subsequent','exception')){
 $calls=[Collections.Generic.List[string]]::new()
 $request={param($command,$body)
  $calls.Add($command)
  switch($calls.Count){
   1 {return @{status=$(if($case -eq 'auth'){'LOCKED'}else{'READ_ACCESS_VERIFIED'});readAccessVerified=$true;ordersEnabled=$false}}
   2 {if($case -eq 'exception'){throw 'private sensitive text'};return @{status=$(if($case -eq 'limit'){'PAYTM_QUOTE_LIMIT'}else{'PAYTM_TRANSPORT_OR_JSON_FAILED'});fresh=$false;ordersEnabled=$false}}
   3 {return @{status=$(if($case -eq 'lock'){'READ_ACCESS_VERIFIED'}else{'LOCKED'});readAccessVerified=$false;ordersEnabled=$false;failure='PAYTM_TRANSPORT_OR_JSON_FAILED'}}
   4 {return @{status=$(if($case -eq 'subsequent'){'FRESH_QUOTE_OBSERVED'}else{'SUPERVISED_SESSION_LOCKED'});fresh=$false;ordersEnabled=$false}}
   default {throw 'Unexpected extra request'}
  }
 }.GetNewClosure()
 $stop={return ($case -ne 'stop')}.GetNewClosure()
 $r=Test-PaytmTransportFailure -Request $request -StopGateway $stop -SecurityId 2885 -Pause {} -Checkpoint {}
 if($r.passed -ne ($case -eq 'pass')){throw "Unexpected result: $case"}
 $expected=switch($case){auth{1} stop{1} limit{2} exception{2} lock{3} default{4}}
 if($calls.Count -ne $expected){throw "Extra request: $case"}
 if(($r|ConvertTo-Json).Contains('private sensitive')){throw 'Sensitive error retained'}
}
Write-Host 'TRANSPORT_FAILURE_FIXTURES_PASSED: 7 cases; no provider or task calls.'
