# Uses the existing application session and monotonic deadline. No restart or clock adjustment.
function Test-PaytmAuthenticatedExpiry {
 param([Parameter(Mandatory)][scriptblock]$Request,[Parameter(Mandatory)][int]$SecurityId,
  [Parameter(Mandatory)][scriptblock]$Checkpoint,
  [scriptblock]$Pause={param($seconds) Start-Sleep -Seconds $seconds},[scriptblock]$ElapsedSeconds)
 $watch=[Diagnostics.Stopwatch]::StartNew()
 if(-not $ElapsedSeconds){$ElapsedSeconds={$watch.Elapsed.TotalSeconds}.GetNewClosure()}
 $r=[ordered]@{status='RUNNING';passed=$false;quoteLimitRejected=$false;authenticatedBeforeWait=$false;expiryObserved=$false;postExpiryQuoteRejected=$false;elapsedSeconds=0;failure=$null;ordersEnabled=$false}
 try{
  $s=& $Request 'status' $null
  if($s.status -ne 'READ_ACCESS_VERIFIED' -or $s.readAccessVerified -ne $true -or $s.ordersEnabled -ne $false){throw 'SUPERVISED_EXPIRY_AUTH_REQUIRED'}
  $r.authenticatedBeforeWait=$true
  # Three successful quote reads must already have occurred in this session.
  $q=& $Request 'quote' @{securityId=$SecurityId}
  if($q.status -ne 'PAYTM_QUOTE_LIMIT' -or $q.fresh -ne $false -or $q.ordersEnabled -ne $false){throw 'SUPERVISED_QUOTE_LIMIT_NOT_REJECTED'}
  $r.quoteLimitRejected=$true;& $Checkpoint $r
  Write-Host '[95%] Fourth quote rejected. Waiting for natural session expiry (at most 21 minutes); no clock changes or extra provider reads.'
  while((& $ElapsedSeconds) -lt 1260){
   $s=& $Request 'status' $null
   if($s.ordersEnabled -ne $false){throw 'SUPERVISED_EXPIRY_SCOPE_REJECTED'}
   if($s.status -eq 'LOCKED'){
    if($s.failure -ne 'SUPERVISED_SESSION_EXPIRED' -or $s.readAccessVerified -ne $false){throw 'SUPERVISED_UNEXPECTED_SESSION_LOCK'}
    $r.expiryObserved=$true;break
   }
   if($s.status -ne 'READ_ACCESS_VERIFIED' -or $s.readAccessVerified -ne $true){throw 'SUPERVISED_EXPIRY_STATE_REJECTED'}
   $r.elapsedSeconds=[double](& $ElapsedSeconds);& $Checkpoint $r
   Write-Progress -Activity 'Authenticated Paytm expiry' -PercentComplete ([Math]::Min(99,100*$r.elapsedSeconds/1260)) -Status "Waiting: $([int]$r.elapsedSeconds)/1260 seconds"
   Write-Host "  Expiry check: authenticated; elapsed $([int]$r.elapsedSeconds)s"
   & $Pause 10
  }
  if(-not $r.expiryObserved){throw 'SUPERVISED_EXPIRY_TIMEOUT'}
  $q=& $Request 'quote' @{securityId=$SecurityId}
  if($q.status -ne 'SUPERVISED_SESSION_LOCKED' -or $q.fresh -ne $false -or $q.ordersEnabled -ne $false){throw 'SUPERVISED_EXPIRED_QUOTE_NOT_REJECTED'}
  $r.postExpiryQuoteRejected=$true;$r.passed=$true;$r.status='AUTHENTICATED_EXPIRY_PASSED_RELOGIN_RESTART_PENDING'
 }catch{
  $r.status='REVIEW_REQUIRED';$r.failure=if($_.Exception.Message -cmatch '^SUPERVISED_[A-Z_]+$'){$_.Exception.Message}else{'SUPERVISED_EXPIRY_CHECK_FAILED'}
 }finally{$r.elapsedSeconds=[double](& $ElapsedSeconds);& $Checkpoint $r;Write-Progress -Activity 'Authenticated Paytm expiry' -Completed}
 return $r
}
