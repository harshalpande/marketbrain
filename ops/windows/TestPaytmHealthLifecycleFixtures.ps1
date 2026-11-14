#Requires -Version 7.0
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'PaytmApplicationRoute.ps1')
. (Join-Path $PSScriptRoot 'PaytmHealthLifecycle.ps1')
$application=@{Token='fixture-only'}
function Wait-PaytmLifecycleExpiry {$script:health=$false;$script:armed=$false;$script:reason='HEALTH_STALE_OR_CLOCK_RESET'}
function Invoke-WebRequest($Uri,$Method,$Headers,[switch]$NoProxy,$TimeoutSec,$MaximumRedirection,[switch]$SkipHttpErrorCheck){
 if(-not $NoProxy -or $MaximumRedirection -ne 0 -or $Method -ne 'Post' -or $Headers['X-MarketBrain-Paper-Read-Token'] -cne 'fixture-only'){throw 'HTTP boundary'}
 $cmd=($Uri -split '/')[-1];$script:commands+=,$cmd
 if($cmd -eq 'lock'){$script:armed=$false;$status='LOCKED';$why='NONE'}
 elseif($cmd -eq 'arm'){
  if($script:health){$script:armed=$true;$status='ARMED';$why='ARMED'}else{$status='TIMING_BLOCKED';$why=$script:reason}
 }elseif($cmd -eq 'status'){$status='STATUS';$why=$script:reason}
 elseif($cmd -eq 'head'){
  if($script:armed){throw 'Unexpected outbound HEAD would occur'}
  $status='LOCKED';$why=$script:reason
  if($script:case -eq 'stalebypass' -and $why -eq 'HEALTH_STALE_OR_CLOCK_RESET'){$script:armed=$true;$status='TLS_RESPONSE'}
 }else{throw 'Unexpected command'}
 $boot=if($script:case -eq 'bootchange' -and $cmd -eq 'arm'){'22222222-2222-2222-2222-222222222222'}else{'11111111-1111-1111-1111-111111111111'}
 $v=@{version='PAYTM_APPLICATION_ROUTE_V1';bootId=$boot;state=$(if($script:armed){'ARMED'}else{'LOCKED'});status=$status;remainingRequests=$(if($script:armed){4}else{0});httpStatus=0;tlsVerified=$false;failureType=$why;applicationProcessVerified=$true;credentialsUsed=$false;ordersEnabled=$false}
 @{StatusCode=200;Headers=@{'Cache-Control'='no-store'};Content=($v|ConvertTo-Json)}
}
$count=0
foreach($script:case in @('pass','stalebypass','autoarm','revokefail','bootchange','publishfail')){
 $script:health=$false;$script:armed=$false;$script:reason='NO_HEALTH_EVIDENCE';$script:commands=@();$script:publishes=0;$err=$null;$r=$null
 try{
  $r=Invoke-PaytmHealthLifecycle -Publish {
   $script:publishes++;$script:health=$true;$script:reason='LOCKED_OR_BUDGET_EXHAUSTED'
   if($script:case -eq 'autoarm' -and $script:publishes -eq 2){$script:armed=$true}
   @{status='HEALTH_PUBLISHED_EXPLICIT_ARM_REQUIRED';healthAccepted=($script:case -ne 'publishfail');failure=$null;routeArmed=$false;ordersEnabled=$false}
  } -Revoke {
   if($script:case -eq 'revokefail'){throw 'HEALTH_PUBLISHER_HTTP_FAILED'}
   $script:health=$false;$script:armed=$false;$script:reason='HEALTH_UNCONFIRMED'
  }
 }catch{$err=$_.Exception.Message}
 if($script:case -eq 'pass'){
  if($err -or -not $r.passed -or -not $r.staleBlocked -or -not $r.staleRearmBlocked -or -not $r.recoveryRequiresExplicitArm -or -not $r.explicitRevocationVerified){throw "Pass failed: $err"}
 }elseif(-not $err){throw "Unsafe case accepted: $script:case"}
 if($script:armed -or $script:commands[-1] -cne 'lock'){throw 'Final lock not attempted'}
 $count++
}
Write-Host "PASS: $count lifecycle fixtures using real HTTP/receipt helpers and modeled remote guard; no network or clock changes."
