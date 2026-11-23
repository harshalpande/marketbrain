# Two quote attempts precede this bounded check; the third must reach the transport.
function Test-PaytmTransportFailure {
 param([scriptblock]$Request,[scriptblock]$StopGateway,[int]$SecurityId,
  [scriptblock]$Checkpoint,[scriptblock]$Pause={param($seconds) Start-Sleep -Seconds $seconds})
 $watch=[Diagnostics.Stopwatch]::StartNew()
 $r=[ordered]@{status='RUNNING';passed=$false;gatewayStopped=$false;transportRejected=$false;sessionLocked=$false;subsequentQuoteRejected=$false;ordersEnabled=$false;failure=$null;elapsedSeconds=0}
 try{
  $s=& $Request 'status' $null
  if($s.status -ne 'READ_ACCESS_VERIFIED' -or $s.readAccessVerified -ne $true -or $s.ordersEnabled -ne $false){throw 'SUPERVISED_TRANSPORT_AUTH_REQUIRED'}
  if((& $StopGateway) -ne $true){throw 'SUPERVISED_TRANSPORT_STOP_FAILED'}
  $r.gatewayStopped=$true;& $Checkpoint $r
  & $Pause 5
  $q=& $Request 'quote' @{securityId=$SecurityId}
  if($q.status -ne 'PAYTM_TRANSPORT_OR_JSON_FAILED' -or $q.fresh -ne $false -or $q.ordersEnabled -ne $false){throw 'SUPERVISED_TRANSPORT_FAILURE_NOT_OBSERVED'}
  $r.transportRejected=$true
  $s=& $Request 'status' $null
  if($s.status -ne 'LOCKED' -or $s.readAccessVerified -ne $false -or $s.ordersEnabled -ne $false -or $s.failure -ne 'PAYTM_TRANSPORT_OR_JSON_FAILED'){throw 'SUPERVISED_TRANSPORT_SESSION_NOT_LOCKED'}
  $r.sessionLocked=$true;& $Checkpoint $r
  $q=& $Request 'quote' @{securityId=$SecurityId}
  if($q.status -ne 'SUPERVISED_SESSION_LOCKED' -or $q.fresh -ne $false -or $q.ordersEnabled -ne $false){throw 'SUPERVISED_TRANSPORT_SUBSEQUENT_READ_NOT_BLOCKED'}
  $r.subsequentQuoteRejected=$true;$r.passed=$true;$r.status='TRANSPORT_FAILURE_PASSED_RELOGIN_PENDING'
 }catch{
  $r.status='REVIEW_REQUIRED';$r.failure=if($_.Exception.Message -cmatch '^SUPERVISED_[A-Z_]+$'){$_.Exception.Message}else{'SUPERVISED_TRANSPORT_CHECK_FAILED'}
 }finally{$r.elapsedSeconds=$watch.Elapsed.TotalSeconds;& $Checkpoint $r}
 return $r
}
