# Definitions only. Explicit diagnostic lease, never broker/order authority.
function Invoke-PaytmLifecycleRoute([ValidateSet('status','arm','head','lock')][string]$Command) {
 try{
  $r=Invoke-WebRequest ('http://127.0.0.1:8080/api/v1/paytm/route/'+$Command) -Method Post -Headers @{'X-MarketBrain-Paper-Read-Token'=$application.Token;'X-MarketBrain-Paytm-Route'='credential-free'} -NoProxy -TimeoutSec 5 -MaximumRedirection 0 -SkipHttpErrorCheck
  if($r.StatusCode -ne 200 -or ($r.Headers['Cache-Control'] -join ',') -notmatch 'no-store'){throw 'contract'}
  $v=$r.Content|ConvertFrom-Json
  Assert-PaytmApplicationReceipt $v
  return $v
 }catch{throw 'HEALTH_LIFECYCLE_HTTP_FAILED'}
}
function Wait-PaytmLifecycleExpiry {
 $watch=[Diagnostics.Stopwatch]::StartNew()
 while($watch.Elapsed.TotalSeconds -lt 32){
  Write-Progress -Activity 'Diagnostic health lifecycle' -PercentComplete ([math]::Min(95,70+$watch.Elapsed.TotalSeconds/2)) -Status ('No publications: {0:N0}/32 seconds' -f $watch.Elapsed.TotalSeconds)
  Write-Host ('Waiting for health expiry: {0:N0}/32 seconds' -f $watch.Elapsed.TotalSeconds)
  Start-Sleep -Seconds 4
 }
 Write-Progress -Activity 'Diagnostic health lifecycle' -Completed
}
function Invoke-PaytmHealthLifecycle([scriptblock]$Publish,[scriptblock]$Revoke,[scriptblock]$Checkpoint={param($Value)}) {
 $r=[ordered]@{passed=$false;freshArmVerified=$false;staleBlocked=$false;staleRearmBlocked=$false;recoveryRequiresExplicitArm=$false;explicitRevocationVerified=$false;observations=@();ordersEnabled=$false}
 $boot=$null
 function Check-Route([string]$Command,[string]$State,[string]$Status,[string]$Reason='') {
  $v=Invoke-PaytmLifecycleRoute $Command
  if($v.bootId -cne $boot -or $v.state -cne $State -or $v.status -cne $Status -or $v.tlsVerified -or $v.httpStatus -ne 0 -or $v.ordersEnabled -or $v.credentialsUsed -or ($State -eq 'LOCKED' -and $v.remainingRequests -ne 0) -or ($State -eq 'ARMED' -and $v.remainingRequests -ne 4) -or ($Reason -and $v.failureType -cne $Reason)){throw 'HEALTH_LIFECYCLE_ROUTE_MISMATCH'}
  $r.observations+=,$v
  $null=& $Checkpoint $r
 }
 function Publish-Fresh {
  $p=& $Publish
  if($p.status -cne 'HEALTH_PUBLISHED_EXPLICIT_ARM_REQUIRED' -or -not $p.healthAccepted -or $p.failure -or $p.routeArmed -or $p.ordersEnabled){throw 'HEALTH_LIFECYCLE_FRESH_PUBLICATION_FAILED'}
 }
 try{
  $initial=Invoke-PaytmLifecycleRoute 'lock';$boot=$initial.bootId
  Publish-Fresh
  Check-Route 'status' 'LOCKED' 'STATUS'
  Check-Route 'arm' 'ARMED' 'ARMED'
  $r.freshArmVerified=$true
  # No HEAD is sent while armed: expiry must remove authority before any attempted HEAD.
  Wait-PaytmLifecycleExpiry
  Check-Route 'head' 'LOCKED' 'LOCKED' 'HEALTH_STALE_OR_CLOCK_RESET';$r.staleBlocked=$true
  Check-Route 'arm' 'LOCKED' 'TIMING_BLOCKED' 'HEALTH_STALE_OR_CLOCK_RESET';$r.staleRearmBlocked=$true
  Publish-Fresh
  Check-Route 'status' 'LOCKED' 'STATUS'
  Check-Route 'head' 'LOCKED' 'LOCKED' 'LOCKED_OR_BUDGET_EXHAUSTED'
  Check-Route 'arm' 'ARMED' 'ARMED';$r.recoveryRequiresExplicitArm=$true
  $null=& $Revoke
  Check-Route 'head' 'LOCKED' 'LOCKED' 'HEALTH_UNCONFIRMED'
  Check-Route 'arm' 'LOCKED' 'TIMING_BLOCKED' 'HEALTH_UNCONFIRMED';$r.explicitRevocationVerified=$true
  $r.passed=$true
  return [pscustomobject]$r
 }finally{
  $null=& $Checkpoint $r
  $null=Invoke-PaytmLifecycleRoute 'lock'
 }
}
