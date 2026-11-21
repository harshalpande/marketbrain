# Fixed local negative lifecycle. Never follow a broker redirect or send a successful callback.
function Invoke-LifecycleHttp($Client,[string]$Path,[string]$Token,[string]$Body,[string]$Cookie) {
 if($Path -cnotmatch '^(/api/v1/paytm/supervised/(status|start|lock)|/paytm/supervised/browser\?code=[A-Za-z0-9_-]{43}|/paytm/callback\?success=false&state=[A-Za-z0-9_-]{43})$'){throw 'LIFECYCLE_PATH_REJECTED'}
 $method=if($Path.StartsWith('/api/')){[Net.Http.HttpMethod]::Post}else{[Net.Http.HttpMethod]::Get}
 $req=[Net.Http.HttpRequestMessage]::new($method,('http://127.0.0.1:8080'+$Path));$reply=$null
 try{
  if($Path.StartsWith('/api/')){$req.Headers.Add('X-MarketBrain-Paper-Read-Token',$Token);$req.Headers.Add('X-MarketBrain-Paytm-Supervised','supervised-paper')}
  if($Cookie){$req.Headers.Add('Cookie',('marketbrain_paytm_supervised='+$Cookie))}
  if($Body){$req.Content=[Net.Http.StringContent]::new($Body,[Text.Encoding]::UTF8,'application/json')}
  $reply=$Client.SendAsync($req).GetAwaiter().GetResult()
  $content=$reply.Content.ReadAsStringAsync().GetAwaiter().GetResult()
  $cookies=if($reply.Headers.Contains('Set-Cookie')){@($reply.Headers.GetValues('Set-Cookie'))}else{@()}
  return @{code=[int]$reply.StatusCode;content=$content;cookies=$cookies;noStore=($reply.Headers.CacheControl.NoStore -eq $true)}
 }finally{if($reply){$reply.Dispose()};$req.Dispose()}
}
function Invoke-SupervisedLifecycleProbe {
 $r=[ordered]@{version=1;test='SUPERVISED_LOCAL_NEGATIVE_LIFECYCLE';passed=$false;checks=@();failure=$null;finalLocked=$false;ordersEnabled=$false;brokerCredentialsUsed=$false;brokerRedirectsFollowed=$false;clockSource='SYNTHETIC_ANCHOR_FOR_LOCAL_NEGATIVES_ONLY'}
 $client=$null;$token=$null;$owned=$false;$cookie=$null;$path=$null
 function Check-Lifecycle($reply,[int]$code,[string]$name){
  $ok=($reply.code -eq $code -and $reply.noStore)
  $r.checks+=@{name=$name;expectedStatus=$code;actualStatus=$reply.code;noStore=$reply.noStore;passed=$ok}
  if(-not $ok){throw 'LIFECYCLE_UNEXPECTED_RESPONSE'}
 }
 function Read-LifecycleState([string]$expected,[string]$name){
  $reply=Invoke-LifecycleHttp $client '/api/v1/paytm/supervised/status' $token $null $null
  Check-Lifecycle $reply 200 $name
  $v=$reply.content|ConvertFrom-Json
  if($v.status -cne $expected -or $v.ordersEnabled -ne $false -or $v.readAccessVerified -ne $false){throw 'LIFECYCLE_STATE_REJECTED'}
 }
 try{
  $id=Invoke-UniverseDocker -Arguments @('ps','-q','--filter','label=com.docker.compose.service=marketbrain-service','--filter','status=running')
  if($id -cnotmatch '^[a-f0-9]{12,64}$'){throw 'LIFECYCLE_APPLICATION_NOT_UNIQUE'}
  $token=Invoke-UniverseDocker -Arguments @('exec',$id,'printenv','MARKETBRAIN_PAPER_READ_TOKEN')
  if($token -cnotmatch '^[A-Za-z0-9_-]{32,128}$'){throw 'LIFECYCLE_TOKEN_INVALID'}
  $handler=[Net.Http.HttpClientHandler]::new();$handler.UseProxy=$false;$handler.AllowAutoRedirect=$false;$handler.UseCookies=$false
  $client=[Net.Http.HttpClient]::new($handler);$client.Timeout=[TimeSpan]::FromSeconds(8);$client.MaxResponseContentBufferSize=8192
  Read-LifecycleState 'LOCKED' 'INITIAL_LOCKED'
  # Test-only anchor; no freshness claim or exchange is possible with success=false callbacks.
  $body='{"apiKey":"local-negative-fixture","apiSecret":"not-a-broker-secret","vpsEpochMilliseconds":1795219200000}'
  $owned=$true
  $reply=Invoke-LifecycleHttp $client '/api/v1/paytm/supervised/start' $token $body $null
  Check-Lifecycle $reply 200 'LOCAL_ATTEMPT_CREATED'
  $v=$reply.content|ConvertFrom-Json
  if($v.ordersEnabled -ne $false -or $v.browserUrl -cnotmatch '^http://127\.0\.0\.1:8080(/paytm/supervised/browser\?code=[A-Za-z0-9_-]{43})$'){throw 'LIFECYCLE_START_REJECTED'}
  $path=$Matches[1];$state=$path.Split('=')[-1]
  $reply=Invoke-LifecycleHttp $client $path $token $null $null
  Check-Lifecycle $reply 303 'BROWSER_LINK_CONSUMED_LOCALLY'
  $bindings=@($reply.cookies|Where-Object {$_ -cmatch '^marketbrain_paytm_supervised=[A-Za-z0-9_-]{43};'})
  if($bindings.Count -ne 1){throw 'LIFECYCLE_COOKIE_REJECTED'}
  $cookie=$bindings[0].Split(';')[0].Split('=')[1]
  Check-Lifecycle (Invoke-LifecycleHttp $client $path $token $null $null) 400 'BROWSER_LINK_REPLAY_REJECTED'
  $callback='/paytm/callback?success=false&state='+$state
  $wrong=if($cookie -ceq ('A'*43)){'B'*43}else{'A'*43}
  Check-Lifecycle (Invoke-LifecycleHttp $client $callback $token $null $wrong) 400 'WRONG_COOKIE_REJECTED'
  Read-LifecycleState 'AWAITING_CALLBACK' 'WRONG_COOKIE_PRESERVES_OWNER'
  Check-Lifecycle (Invoke-LifecycleHttp $client $callback $token $null $cookie) 400 'OWNER_CANCELLATION_REJECTED'
  Read-LifecycleState 'LOCKED' 'CANCELLED_ATTEMPT_LOCKED'
  Check-Lifecycle (Invoke-LifecycleHttp $client $callback $token $null $cookie) 400 'CANCELLED_CALLBACK_REPLAY_REJECTED'
  $reply=Invoke-LifecycleHttp $client '/api/v1/paytm/supervised/start' $token $body $null
  Check-Lifecycle $reply 200 'NEW_ATTEMPT_AFTER_CANCELLATION'
  Check-Lifecycle (Invoke-LifecycleHttp $client $path $token $null $null) 400 'OLD_BROWSER_LINK_REJECTED'
  Read-LifecycleState 'AWAITING_BROWSER' 'NEW_ATTEMPT_PRESERVED'
  $r.passed=$true
 }catch{$r.failure=if($_.Exception.Message -cmatch '^LIFECYCLE_[A-Z_]+$'){$_.Exception.Message}else{'LIFECYCLE_PROBE_FAILED'}}
 finally{
  if($owned){try{
   $reply=Invoke-LifecycleHttp $client '/api/v1/paytm/supervised/lock' $token $null $null
   Check-Lifecycle $reply 200 'FINAL_LOCK'
   Read-LifecycleState 'LOCKED' 'FINAL_LOCK_VERIFIED';$r.finalLocked=$true
  }catch{$r.passed=$false;$r.failure='LIFECYCLE_CLEANUP_NOT_VERIFIED'}}
  if($client){$client.Dispose()};$token=$null;$cookie=$null;$path=$null
 }
 return $r
}
