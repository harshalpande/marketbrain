# Definitions only. No scheduled task, credential provisioning or application changes on import.
function Invoke-PaytmHealthHttp([ValidateSet('challenge','submit','clock')][string]$Command,[string]$Token,$Body) {
 if($Token -cnotmatch '^[A-Za-z0-9_-]{32,128}$'){throw 'HEALTH_PUBLISHER_TOKEN_INVALID'}
 $arguments=@{Uri=('http://127.0.0.1:8080/api/v1/paytm/route-health/'+$Command);Method='POST';Headers=@{'X-MarketBrain-Paytm-Health-Token'=$Token;'X-MarketBrain-Paytm-Health'='diagnostic-health'};NoProxy=$true;TimeoutSec=2;MaximumRedirection=0;SkipHttpErrorCheck=$true}
 if($Command -eq 'submit'){$arguments.TimeoutSec=3}
 if($null -ne $Body){$arguments.ContentType='application/json';$arguments.Body=[Text.Encoding]::UTF8.GetBytes(($Body|ConvertTo-Json -Compress))}
 try{
  $r=Invoke-WebRequest @arguments
  if($r.StatusCode -ne 200 -or ($r.Headers['Cache-Control'] -join ',') -notmatch '(?i)\bno-store\b' -or $r.Content.Length -gt 2048){throw 'contract'}
  return ($r.Content|ConvertFrom-Json)
 }catch{throw 'HEALTH_PUBLISHER_HTTP_FAILED'} # Never retain HTTP errors, headers or token.
}
function Invoke-PaytmHealthPublishOnce([string]$Token,[scriptblock]$Collect,[scriptblock]$MonotonicSeconds={ [Diagnostics.Stopwatch]::GetTimestamp()/[double][Diagnostics.Stopwatch]::Frequency }) {
 # Collect is a trusted in-process adapter, never a saved-report import or user-provided payload.
 $result=[ordered]@{status='PUBLISHER_FAILED';healthAccepted=$false;healthySubmitted=$false;submissionAttempted=$false;failure=$null;collectionFailure=$null;collectionPhase=$null;windowExceeded=$false;elapsedSeconds=0;ordersEnabled=$false;routeArmed=$false}
 $start=& $MonotonicSeconds
 try{
  $c=Invoke-PaytmHealthHttp 'challenge' $Token $null
  $uuid='^[a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12}$'
  if($c.healthContractVersion -cne 'SERVER_TRANSPORT_V2' -or $c.status -cne 'CHALLENGE' -or $c.challenge -cnotmatch $uuid -or $c.bootId -cnotmatch $uuid -or $c.validForSeconds -ne 10 -or $c.accepted -isnot [bool] -or $c.accepted -or $c.ordersEnabled -isnot [bool] -or $c.ordersEnabled){throw 'HEALTH_PUBLISHER_CHALLENGE_INVALID'}
  $healthy=$false;$lower=0.0;$upper=0.0
  try{
   $round=& $Collect
   $assessment=Get-PaytmLiveHealthAssessment $round
   if($round.PSObject.Properties['collectionFailure'] -and $round.collectionFailure){$result.collectionFailure=$round.collectionFailure;$result.collectionPhase=$round.failedPhase;$result.failure='HEALTH_PUBLISHER_COLLECTION_FAILED'}
   # V2 Java independently probes its own fixed proxy before it accepts this claim.
   $healthy=$assessment.collectionPassed
   $lower=[double]$assessment.applicationMinusVpsLowerSeconds;$upper=[double]$assessment.applicationMinusVpsUpperSeconds
  }catch{$result.failure='HEALTH_PUBLISHER_COLLECTION_FAILED';$result.collectionFailure='LIVE_HEALTH_COLLECTOR_EXCEPTION'}
  $elapsed=(& $MonotonicSeconds)-$start
  if(-not [double]::IsFinite($elapsed) -or $elapsed -lt 0 -or $elapsed -ge 8){$healthy=$false;$result.windowExceeded=$true;if(-not $result.failure){$result.failure='HEALTH_PUBLISHER_WINDOW_EXCEEDED'}}
  # Even failed collection attempts submit a one-use unhealthy result to revoke prior authority.
  # If delivery fails, revocation is unconfirmed; the server's existing health TTL remains the bound.
  if(-not $healthy){$lower=0.0;$upper=0.0}
  $body=@{challenge=$c.challenge;bootId=$c.bootId;synchronizedClock=[bool]$healthy;transportHealthy=[bool]$healthy;lowerOffsetSeconds=$lower;upperOffsetSeconds=$upper}
  $result.submissionAttempted=$true;$result.healthySubmitted=[bool]$healthy
  $receipt=Invoke-PaytmHealthHttp 'submit' $Token $body
  if($receipt.healthContractVersion -cne 'SERVER_TRANSPORT_V2' -or $receipt.bootId -cne $c.bootId -or $receipt.ordersEnabled -isnot [bool] -or $receipt.ordersEnabled -or $receipt.accepted -isnot [bool]){throw 'HEALTH_PUBLISHER_RECEIPT_INVALID'}
  if($receipt.accepted){
   if(-not $healthy -or $receipt.status -cne 'HEALTH_RECORDED_EXPLICIT_ARM_REQUIRED'){throw 'HEALTH_PUBLISHER_RECEIPT_INVALID'}
   $result.healthAccepted=$true;$result.status='HEALTH_PUBLISHED_EXPLICIT_ARM_REQUIRED'
  }else{
   if($receipt.status -cnotin @('UNHEALTHY_AND_LOCKED','REJECTED_AND_LOCKED')){throw 'HEALTH_PUBLISHER_RECEIPT_INVALID'}
   $result.status='HEALTH_REJECTED_LOCK_CONFIRMED'
  }
 }catch{
  $result.failure=if($_.Exception.Message -cmatch '^HEALTH_PUBLISHER_[A-Z_]+$'){$_.Exception.Message}else{'HEALTH_PUBLISHER_FAILED'}
  $result.status='PUBLISHER_FAILED_LOCK_UNCONFIRMED'
 }finally{$result.elapsedSeconds=(& $MonotonicSeconds)-$start}
 return [pscustomobject]$result
}
