# Fixed local application negative checks. No valid credentials, browser cookies,
# session creation, broker requests, task changes or order endpoints.
function Invoke-SupervisedBoundaryProbe {
 $checks=@(
  @{name='STATUS_MISSING_TOKEN';method='Post';path='/api/v1/paytm/supervised/status';code=401},
  @{name='STATUS_WRONG_TOKEN';method='Post';path='/api/v1/paytm/supervised/status';code=401;wrongToken=$true},
  @{name='QUOTE_MISSING_TOKEN';method='Post';path='/api/v1/paytm/supervised/quote';code=401;body='{"securityId":2885}'},
  @{name='QUOTE_WRONG_TOKEN';method='Post';path='/api/v1/paytm/supervised/quote';code=401;wrongToken=$true;body='{"securityId":2885}'},
  @{name='CALLBACK_WITHOUT_COOKIE';method='Get';path='/paytm/callback?state=fixture&requestToken=fixture';code=400},
  @{name='CALLBACK_REPEAT_WITHOUT_COOKIE';method='Get';path='/paytm/callback?state=fixture&requestToken=fixture';code=400},
  @{name='BROWSER_INVALID_CODE';method='Get';path='/paytm/supervised/browser?code=fixture';code=400}
 )
 $results=@();$watch=[Diagnostics.Stopwatch]::StartNew()
 foreach($check in $checks){
  $args=@{Uri=('http://127.0.0.1:8080'+$check.path);Method=$check.method;NoProxy=$true;TimeoutSec=8;MaximumRedirection=0;SkipHttpErrorCheck=$true;Headers=@{'X-MarketBrain-Paytm-Supervised'='supervised-paper'}}
  if($check.wrongToken){$args.Headers['X-MarketBrain-Paper-Read-Token']='invalid-fixture'}
  if($check.body){$args.ContentType='application/json';$args.Body=$check.body}
  try {
   $reply=Invoke-WebRequest @args
   $actual=[int]$reply.StatusCode
   $noStore=([string]($reply.Headers['Cache-Control'] -join ',') -match '(^|[, ])no-store($|[, ])')
   $results+=@{name=$check.name;expectedStatus=$check.code;actualStatus=$actual;noStore=$noStore;passed=($actual -eq $check.code -and $noStore)}
  }catch{$results+=@{name=$check.name;expectedStatus=$check.code;actualStatus=0;noStore=$false;passed=$false}}
 }
 $passed=(@($results|Where-Object passed -NE $true).Count -eq 0)
 return @{version=1;test='SUPERVISED_APPLICATION_BOUNDARY_PROBES';passed=$passed;checks=$results;elapsedSeconds=$watch.Elapsed.TotalSeconds;ordersEnabled=$false;brokerCredentialsUsed=$false;sessionCreated=$false;status=$(if($passed){'BOUNDARY_PROBES_PASSED_CALLBACK_LIFECYCLE_PENDING'}else{'BOUNDARY_PROBES_REVIEW_REQUIRED'})}
}
