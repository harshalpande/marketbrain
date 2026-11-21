#Requires -Version 7.2
$ErrorActionPreference='Stop'
. "$PSScriptRoot/PaytmAuthenticatedExpiry.ps1"
foreach($case in @('good','wrongLock','limitFailure','timeout','requestFailure')){
 $script:seconds=0;$script:quoteCalls=0;$script:saved=0
 $request={param($command,$body)
  if($case -eq 'requestFailure'){throw 'secret request details'}
  if($command -eq 'status'){
   if($script:seconds -ge 20 -and $case -ne 'timeout'){
    return @{status='LOCKED';failure=$(if($case -eq 'wrongLock'){'NONE'}else{'SUPERVISED_SESSION_EXPIRED'});readAccessVerified=$false;ordersEnabled=$false}
   };return @{status='READ_ACCESS_VERIFIED';readAccessVerified=$true;ordersEnabled=$false}
  }
  if($command -ne 'quote' -or $body.securityId -ne 2885){throw 'unexpected request'}
  $script:quoteCalls++
  return @{status=$(if($case -eq 'limitFailure'){'FRESH_QUOTE_OBSERVED'}elseif($script:quoteCalls -eq 1){'PAYTM_QUOTE_LIMIT'}else{'SUPERVISED_SESSION_LOCKED'});fresh=$false;ordersEnabled=$false}
 }
 $result=Test-PaytmAuthenticatedExpiry -SecurityId 2885 -Request $request -Checkpoint {param($r) $script:saved++} -Pause {param($s) $script:seconds+= $(if($case -eq 'timeout'){630}else{$s})} -ElapsedSeconds {$script:seconds}
 if($case -eq 'good'){
  if(-not $result.passed -or -not $result.expiryObserved -or -not $result.postExpiryQuoteRejected -or $script:quoteCalls -ne 2){throw 'EXPIRY_SUCCESS_FAILED'}
 }elseif($result.passed -or -not $result.failure){throw 'EXPIRY_NEGATIVE_FAILED'}
 if(($result|ConvertTo-Json) -match 'secret request details' -or $script:saved -lt 1){throw 'EXPIRY_EVIDENCE_FAILED'}
}
Write-Host 'AUTHENTICATED_EXPIRY_5_FIXTURES_PASSED'
