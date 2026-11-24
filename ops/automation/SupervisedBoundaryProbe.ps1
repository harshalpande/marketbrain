# Fixed local application negative checks. No valid credentials, browser cookies,
# session creation, broker requests, task changes or order endpoints.
function Invoke-SupervisedBoundaryProbe {
 $checks=@(
  @{name='STATUS_MISSING_TOKEN';method='Post';path='/api/v1/paytm/supervised/status';code=401},
  @{name='STATUS_WRONG_TOKEN';method='Post';path='/api/v1/paytm/supervised/status';code=401;wrongToken=$true},
  @{name='QUOTE_MISSING_TOKEN';method='Post';path='/api/v1/paytm/supervised/quote';code=401;body='{"securityId":2885}'},
  @{name='QUOTE_WRONG_TOKEN';method='Post';path='/api/v1/paytm/supervised/quote';code=401;wrongToken=$true;body='{"securityId":2885}'},
  @{name='REVIEW_QUOTE_MISSING_TOKEN';method='Post';path='/api/v1/paytm/supervised/review-quote';code=401;body='{"symbol":"RELIANCE"}'},
  @{name='REVIEW_QUOTE_WRONG_TOKEN';method='Post';path='/api/v1/paytm/supervised/review-quote';code=401;wrongToken=$true;body='{"symbol":"RELIANCE"}'},
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

# Read-only checks with the existing local token; require a locked session first.
# Never start/login/unlock and never return the token or arbitrary response bodies.
function Invoke-SupervisedReviewBoundaryProbe {
 $r=@{test='DEPLOYED_REVIEW_QUOTE_BOUNDARY';passed=$false;checks=@();ordersEnabled=$false;sessionCreated=$false;failure=$null}
 $token=$null;$headers=$null
 try{
  $id=Invoke-UniverseDocker -Arguments @('ps','-q','--filter','label=com.docker.compose.service=marketbrain-service','--filter','status=running')
  if($id -cnotmatch '^[a-f0-9]{12,64}$'){throw 'REVIEW_APPLICATION_NOT_UNIQUE'}
  $token=Invoke-UniverseDocker -Arguments @('exec',$id,'printenv','MARKETBRAIN_PAPER_READ_TOKEN')
  if($token -cnotmatch '^[A-Za-z0-9_-]{32,128}$'){throw 'REVIEW_TOKEN_INVALID'}
  $headers=@{'X-MarketBrain-Paper-Read-Token'=$token;'X-MarketBrain-Paytm-Supervised'='supervised-paper'}
  $base='http://127.0.0.1:8080/api/v1/paytm/supervised/'
  $state=Invoke-RestMethod -Uri ($base+'status') -Method Post -NoProxy -TimeoutSec 8 -MaximumRedirection 0 -Headers $headers
  if($state.status -cne 'LOCKED' -or $state.ordersEnabled -ne $false){throw 'REVIEW_SESSION_MUST_BE_LOCKED'}
  foreach($h in @('NONE','Origin','Forwarded','X-Forwarded-For','X-Forwarded-Host','X-Forwarded-Proto')){
   $requestHeaders=$headers.Clone()
   if($h -ne 'NONE'){$requestHeaders[$h]='untrusted-fixture'}
   $reply=Invoke-WebRequest -Uri ($base+'review-quote') -Method Post -NoProxy -TimeoutSec 8 -MaximumRedirection 0 -SkipHttpErrorCheck -Headers $requestHeaders -ContentType 'application/json' -Body '{"symbol":"RELIANCE","securityId":1,"fresh":true,"lastPrice":999,"reviewEligible":true,"ordersEnabled":true}'
   if($reply.Content.Length -gt 4096){throw 'REVIEW_RESPONSE_TOO_LARGE'}
   $v=$reply.Content|ConvertFrom-Json
   $expected=if($h -eq 'NONE'){200}else{401}
   $expectedStatus=if($h -eq 'NONE'){'SUPERVISED_SESSION_LOCKED'}else{'UNAUTHORIZED'}
   $ok=([int]$reply.StatusCode -eq $expected -and $v.status -ceq $expectedStatus -and [string]($reply.Headers['Cache-Control'] -join ',') -match '(^|[, ])no-store($|[, ])')
   if($h -eq 'NONE'){$ok=$ok -and $v.reviewEligible -eq $false -and $v.ordersEnabled -eq $false}
   $r.checks+=@{name=('REVIEW_'+$h.Replace('-','_').ToUpperInvariant());passed=[bool]$ok;expectedStatus=$expected;actualStatus=[int]$reply.StatusCode}
  }
  $state=Invoke-RestMethod -Uri ($base+'status') -Method Post -NoProxy -TimeoutSec 8 -MaximumRedirection 0 -Headers $headers
  $r.finalLocked=($state.status -ceq 'LOCKED' -and $state.ordersEnabled -eq $false)
  $r.passed=($r.finalLocked -and @($r.checks|Where-Object passed -NE $true).Count -eq 0)
 }catch{$r.failure=if($_.Exception.Message -cmatch '^REVIEW_[A-Z_]+$'){$_.Exception.Message}else{'REVIEW_BOUNDARY_FAILED'}}
 finally{$token=$null;$headers=$null;$requestHeaders=$null}
 return $r
}
