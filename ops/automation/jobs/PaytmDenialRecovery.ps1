#Requires -Version 7.2
# Fixed read-only job: return only the compact supervised login report, never credentials.
param([Parameter(Mandatory)][string]$ResultPath,[ValidateSet('Observe','Apply','FailureFixture')][string]$Mode='Observe')
$ErrorActionPreference='Stop'
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

# Read-only, fixed-task diagnostics. Never return task arguments, event messages or credentials.
function Get-SupervisedGatewayTaskObservation {
 $r=@{readOnly=$true;ordersEnabled=$false;taskChanged=$false}
 try {
  $name='MarketBrain-Gateway-Supervisor-v1'
  $t=Get-ScheduledTask -TaskName $name -TaskPath '\' -ErrorAction Stop
  $i=Get-ScheduledTaskInfo -TaskName $name -TaskPath '\' -ErrorAction Stop
  $r.task=@{state=[string]$t.State;lastTaskResult=[long]$i.LastTaskResult;lastRunTime=$i.LastRunTime.ToString('o');missedRuns=[int]$i.NumberOfMissedRuns;settings=@{}}
  foreach($n in @('Enabled','AllowDemandStart','DisallowStartIfOnBatteries','StopIfGoingOnBatteries','RunOnlyIfIdle','RunOnlyIfNetworkAvailable','StartWhenAvailable')){$r.task.settings[$n]=[bool]$t.Settings.$n}
  $r.task.multipleInstances=[string]$t.Settings.MultipleInstances
  $r.task.executionTimeLimit=[string]$t.Settings.ExecutionTimeLimit
  $r.task.idle=@{stopOnIdleEnd=[bool]$t.Settings.IdleSettings.StopOnIdleEnd;restartOnIdle=[bool]$t.Settings.IdleSettings.RestartOnIdle}
 }catch{$r.taskError=$_.Exception.GetBaseException().GetType().Name}
 try {
  $r.batteries=@(Get-CimInstance Win32_Battery -ErrorAction Stop|Select-Object -First 4|ForEach-Object {@{batteryStatus=[int]$_.BatteryStatus;estimatedChargeRemaining=[int]$_.EstimatedChargeRemaining}})
 }catch{$r.batteryError=$_.Exception.GetBaseException().GetType().Name}
 try {
  $log=Get-WinEvent -ListLog 'Microsoft-Windows-TaskScheduler/Operational' -ErrorAction Stop
  $r.eventLogEnabled=[bool]$log.IsEnabled
  if($log.IsEnabled){
   # Filter by the fixed task on the event service; do not return arbitrary message text.
   $filter="*[System[TimeCreated[timediff(@SystemTime) <= 86400000]]] and *[EventData[Data[@Name='TaskName']='\MarketBrain-Gateway-Supervisor-v1']]"
   $r.events=@(Get-WinEvent -LogName $log.LogName -FilterXPath $filter -MaxEvents 24 -ErrorAction Stop|ForEach-Object {
    $e=@{id=$_.Id;recordId=$_.RecordId;timeCreated=$_.TimeCreated.ToString('o');codes=@{}}
    $xml=[xml]$_.ToXml()
    foreach($d in $xml.Event.EventData.Data){if($d.Name -in @('ResultCode','ErrorCode') -and [string]$d.'#text' -match '^(0x[0-9a-fA-F]+|[0-9]+)$'){$e.codes[$d.Name]=[string]$d.'#text'}}
    $e
   })
  }
 }catch{$r.eventError=$_.Exception.GetBaseException().GetType().Name}
 return $r
}

# Fixed saved-universe read. Only the existing local paper read token is read into
# process memory. No broker login, gateway changes, database writes or orders.
function Invoke-UniverseDocker([string[]]$Arguments) {
 $exe=(Get-Command docker.exe -CommandType Application -ErrorAction Stop|Select-Object -First 1).Source
 $info=[Diagnostics.ProcessStartInfo]::new();$info.FileName=$exe;$info.UseShellExecute=$false;$info.CreateNoWindow=$true
 $info.RedirectStandardOutput=$true;$info.RedirectStandardError=$true
 foreach($arg in (@('--host','npipe:////./pipe/docker_engine')+$Arguments)){$info.ArgumentList.Add($arg)}
 $p=[Diagnostics.Process]::new();$p.StartInfo=$info
 try{
  $null=$p.Start();$stdout=$p.StandardOutput.ReadToEndAsync();$stderr=$p.StandardError.ReadToEndAsync()
  if(-not $p.WaitForExit(10000)){try{$p.Kill($true)}catch{};throw 'UNIVERSE_DOCKER_TIMEOUT'}
  if($p.ExitCode -ne 0){throw 'UNIVERSE_DOCKER_FAILED'}
  $value=$stdout.GetAwaiter().GetResult()
  if($value.Length -gt 4096){throw 'UNIVERSE_DOCKER_OUTPUT_REJECTED'}
  return $value.Trim()
 }finally{$p.Dispose()}
}
function Invoke-SupervisedUniverseProbe {
 $r=[ordered]@{version=1;test='SUPERVISED_SAVED_UNIVERSE_PROBE';passed=$false;ordersEnabled=$false;brokerCredentialsUsed=$false;failure=$null}
 $token=$null;$headers=$null
 try{
  $id=Invoke-UniverseDocker -Arguments @('ps','-q','--filter','label=com.docker.compose.service=marketbrain-service','--filter','status=running')
  if($id -cnotmatch '^[a-f0-9]{12,64}$'){throw 'UNIVERSE_APPLICATION_NOT_UNIQUE'}
  $token=Invoke-UniverseDocker -Arguments @('exec',$id,'printenv','MARKETBRAIN_PAPER_READ_TOKEN')
  if($token -cnotmatch '^[A-Za-z0-9_-]{32,128}$'){throw 'UNIVERSE_LOCAL_TOKEN_INVALID'}
  $headers=@{'X-MarketBrain-Paper-Read-Token'=$token;'X-MarketBrain-Paytm-Supervised'='supervised-paper'}
  $v=Invoke-RestMethod -Uri 'http://127.0.0.1:8080/api/v1/paytm/supervised/universe-match' -Method Post -NoProxy -TimeoutSec 10 -MaximumRedirection 0 -Headers $headers -ContentType 'application/json' -Body '{"symbol":"RELIANCE"}'
  if($v.status -cnotmatch '^[A-Z_]{1,100}$' -or $v.ordersEnabled -ne $false -or $v.snapshotMatched -isnot [bool]){throw 'UNIVERSE_RESPONSE_INVALID'}
  $safe=[ordered]@{status=[string]$v.status;snapshotMatched=$v.snapshotMatched;ordersEnabled=$false}
  $patterns=@{symbol='^RELIANCE$';snapshotId='^[a-f0-9-]{36}$';observedOn='^[0-9]{4}-[0-9]{2}-[0-9]{2}$';isin='^[A-Z]{2}[A-Z0-9]{9}[0-9]$';instrumentId='^[1-9][0-9]{0,18}$'}
  foreach($name in $patterns.Keys){if($v.PSObject.Properties[$name]){if([string]$v.$name -cnotmatch $patterns[$name]){throw 'UNIVERSE_RESPONSE_INVALID'};$safe[$name]=$v.$name}}
  foreach($name in @('currentMembershipVerified','providerIsinVerified')){if($v.PSObject.Properties[$name]){if($v.$name -isnot [bool] -or $v.$name){throw 'UNIVERSE_RESPONSE_INVALID'};$safe[$name]=$false}}
  $r.universeMatch=$safe
  $r.passed=($v.status -ceq 'LOCAL_SNAPSHOT_SYMBOL_ISIN_MATCHED' -and $v.snapshotMatched -eq $true -and $v.symbol -ceq 'RELIANCE')
 }catch{$r.failure=if($_.Exception.Message -cmatch '^UNIVERSE_[A-Z_]+$'){$_.Exception.Message}else{'UNIVERSE_PROBE_FAILED'}}
 finally{$token=$null;$headers=$null}
 return $r
}

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

function Get-PaytmQuoteBatchAssessment {
 param([object[]]$Samples,[int]$SecurityId,[switch]$RequireFresh)
 if($Samples.Count -ne 3){throw 'SUPERVISED_QUOTE_BATCH_COUNT'}
 $fresh=0;$stale=0;$missing=0;$lastObserved=0
 foreach($q in $Samples){
  if($q.ordersEnabled -ne $false -or $q.fresh -isnot [bool]){throw 'SUPERVISED_QUOTE_BATCH_SCOPE'}
  if($q.status -eq 'NO_QUOTE'){if($q.fresh){throw 'SUPERVISED_QUOTE_BATCH_INVALID'};$missing++;continue}
  if($q.status -notin @('FRESH_QUOTE_OBSERVED','STALE_QUOTE') -or $q.securityId -ne $SecurityId -or $q.exchange -cne 'NSE' -or $q.scripType -cne 'EQUITY' -or $q.timestampEpoch -cne 'PAYTM_1980_SECONDS'){throw 'SUPERVISED_QUOTE_BATCH_IDENTITY'}
  foreach($n in @('observedEpochMilliseconds','tradeEpochMilliseconds','ageMilliseconds','lastPrice')){
   if($null -eq $q.$n -or $q.$n -is [string] -or $q.$n -is [bool]){throw 'SUPERVISED_QUOTE_BATCH_INVALID'}
  }
  if($q.lastPrice -le 0 -or $q.observedEpochMilliseconds -le $lastObserved -or $q.ageMilliseconds -lt 0 -or ($q.observedEpochMilliseconds-$q.tradeEpochMilliseconds) -ne $q.ageMilliseconds){throw 'SUPERVISED_QUOTE_BATCH_INVALID'}
  $lastObserved=$q.observedEpochMilliseconds
  if($q.status -eq 'FRESH_QUOTE_OBSERVED'){
   if(-not $q.fresh -or $q.ageMilliseconds -gt 15000){throw 'SUPERVISED_QUOTE_BATCH_FALSE_FRESH'};$fresh++
  }else{if($q.fresh -or $q.ageMilliseconds -le 15000){throw 'SUPERVISED_QUOTE_BATCH_FALSE_STALE'};$stale++}
 }
 return @{status=$(if($fresh -eq 3){'THREE_FRESH_MAPPED_QUOTES'}else{'FRESHNESS_PENDING'});passed=($fresh -eq 3);freshCount=$fresh;staleCount=$stale;missingCount=$missing;sampleCount=3;securityId=$SecurityId;strictFreshRequired=[bool]$RequireFresh;ordersEnabled=$false}
}


function Resolve-PaytmQuoteMappingFromCsv {
 param([Parameter(Mandatory)][string]$Csv,[Parameter(Mandatory)][string]$Symbol,[Parameter(Mandatory)][string]$Sha256)
 if($Symbol -cnotmatch '^[A-Z0-9][A-Z0-9&-]{0,29}$' -or $Sha256 -cnotmatch '^[A-F0-9]{64}$'){throw 'SUPERVISED_MAPPING_INPUT_INVALID'}
 if([Text.Encoding]::UTF8.GetByteCount($Csv) -gt 4194304){throw 'SUPERVISED_MAPPING_TOO_LARGE'}
 $rows=@(ConvertFrom-Csv -InputObject $Csv -ErrorAction Stop)
 if($rows.Count -eq 0 -or $rows.Count -gt 30000){throw 'SUPERVISED_MAPPING_ROWS_INVALID'}
 foreach($name in @('security_id','symbol','exchange','series','segment','instrument_type')){
  if(-not $rows[0].PSObject.Properties[$name]){throw 'SUPERVISED_MAPPING_SCHEMA_INVALID'}
 }
 $matchingRows=@($rows|Where-Object {$_.symbol -ceq $Symbol -and $_.exchange -ceq 'NSE' -and $_.series -ceq 'EQ' -and $_.segment -ceq 'E' -and $_.instrument_type -ceq 'ES'})
 if($matchingRows.Count -ne 1 -or $matchingRows[0].security_id -cnotmatch '^[1-9][0-9]{0,7}$'){throw 'SUPERVISED_MAPPING_NOT_UNIQUE'}
 $id=$matchingRows[0].security_id
 if(@($rows|Where-Object {$_.exchange -ceq 'NSE' -and $_.security_id -ceq $id}).Count -ne 1){throw 'SUPERVISED_MAPPING_ID_CONFLICT'}
 return [ordered]@{symbol=$Symbol;securityId=[int]$id;exchange='NSE';series='EQ';segment='E';instrumentType='ES';source='PAYTM_PUBLIC_EQUITY_MASTER';sha256=$Sha256;localUniverseVerified=$false}
}
function Get-PaytmQuoteMapping {
 param([Parameter(Mandatory)][string]$Symbol)
 # Public reference data only. No broker credentials; no fallback URL or redirects.
 $handler=[Net.Http.HttpClientHandler]::new();$handler.AllowAutoRedirect=$false
 $client=[Net.Http.HttpClient]::new($handler);$client.Timeout=[TimeSpan]::FromSeconds(25);$client.MaxResponseContentBufferSize=4194304
 $response=$null
 try {
  $response=$client.GetAsync('https://developer.paytmmoney.com/data/v1/scrips/equity_security_master.csv').GetAwaiter().GetResult()
  if([int]$response.StatusCode -ne 200){throw 'SUPERVISED_MAPPING_DOWNLOAD_FAILED'}
  $bytes=$response.Content.ReadAsByteArrayAsync().GetAwaiter().GetResult()
  $hash=[Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($bytes))
  $csv=[Text.UTF8Encoding]::new($false,$true).GetString($bytes).TrimStart([char]0xFEFF)
  Resolve-PaytmQuoteMappingFromCsv -Csv $csv -Symbol $Symbol -Sha256 $hash
 } catch {
  if($_.Exception.Message -cmatch '^SUPERVISED_MAPPING_[A-Z_]+$'){throw}
  throw 'SUPERVISED_MAPPING_DOWNLOAD_OR_PARSE_FAILED'
 } finally {if($response){$response.Dispose()};$client.Dispose();$handler.Dispose()}
}

# Public master plus existing saved-universe endpoint. No broker login or writes.
function Invoke-SupervisedIdentityProbe {
 $r=[ordered]@{test='PROVIDER_AND_SAVED_UNIVERSE_IDENTITY';passed=$false;ordersEnabled=$false;currentMembershipVerified=$false;providerIsinVerified=$false;failure=$null}
 try{
  $m=Get-PaytmQuoteMapping -Symbol RELIANCE
  $u=Invoke-SupervisedUniverseProbe
  if(-not $u.passed -or $u.universeMatch.symbol -cne $m.symbol -or $m.exchange -cne 'NSE' -or $m.series -cne 'EQ' -or $m.instrumentType -cne 'ES'){throw 'IDENTITY_CORROBORATION_FAILED'}
  # Explicit fields only: no raw CSV, local token, or unknown provider values.
  if($m.symbol -cne 'RELIANCE' -or [string]$m.securityId -cnotmatch '^[1-9][0-9]{0,7}$' -or $m.sha256 -cnotmatch '^[A-F0-9]{64}$'){throw 'IDENTITY_MAPPING_REJECTED'}
  $r.mapping=@{symbol=$m.symbol;securityId=[int]$m.securityId;exchange='NSE';series='EQ';sha256=$m.sha256;source='PAYTM_PUBLIC_EQUITY_MASTER'}
  $r.savedUniverse=$u.universeMatch
  $r.passed=$true;$r.status='SYMBOL_CORROBORATED_FULL_IDENTITY_PENDING'
 }catch{$r.status='REVIEW_REQUIRED';$r.failure='IDENTITY_PROBE_FAILED'}
 return $r
}

function Invoke-SupervisedQuoteFixtures {
try {
$ErrorActionPreference='Stop'
function Samples {
 @(1..3|ForEach-Object {@{status='FRESH_QUOTE_OBSERVED';fresh=$true;ordersEnabled=$false;securityId=2885;exchange='NSE';scripType='EQUITY';timestampEpoch='PAYTM_1980_SECONDS';observedEpochMilliseconds=(20000+$_*5000);tradeEpochMilliseconds=(20000+$_*5000-100);ageMilliseconds=100;lastPrice=1377.5}})
}
$s=Samples;$r=Get-PaytmQuoteBatchAssessment $s 2885 -RequireFresh
if(-not $r.passed -or $r.freshCount -ne 3){throw 'FRESH_FIXTURE_FAILED'}
$s=Samples;foreach($q in $s){$q.status='STALE_QUOTE';$q.fresh=$false;$q.tradeEpochMilliseconds=1;$q.ageMilliseconds=$q.observedEpochMilliseconds-1}
if((Get-PaytmQuoteBatchAssessment $s 2885 -RequireFresh).passed){throw 'STALE_ACCEPTED'}
$s=@(1..3|ForEach-Object {@{status='NO_QUOTE';fresh=$false;ordersEnabled=$false}})
if((Get-PaytmQuoteBatchAssessment $s 2885 -RequireFresh).missingCount -ne 3){throw 'MISSING_FIXTURE_FAILED'}
foreach($case in @('identity','age','price','duplicate','falseFresh')){
 $s=Samples
 switch($case){identity{$s[0].securityId=1};age{$s[0].ageMilliseconds=1};price{$s[0].lastPrice=0};duplicate{$s[1]=$s[0]};falseFresh{$s[0].ageMilliseconds=20000;$s[0].tradeEpochMilliseconds=$s[0].observedEpochMilliseconds-20000}}
 $failed=$false;try{$null=Get-PaytmQuoteBatchAssessment $s 2885 -RequireFresh}catch{$failed=$true}
 if(-not $failed){throw "NEGATIVE_NOT_CAUGHT_$case"}
}

 return @{test='POWERSHELL_QUOTE_VALIDATOR_SYNTHETIC_FIXTURES';passed=$true;fixtureCount=8;brokerCalls=0;ordersEnabled=$false}
}catch{return @{test='POWERSHELL_QUOTE_VALIDATOR_SYNTHETIC_FIXTURES';passed=$false;fixtureCount=8;failure='QUOTE_FIXTURE_FAILED';brokerCalls=0;ordersEnabled=$false}}
}
if($Mode -eq 'FailureFixture'){
 $boundary=Invoke-SupervisedBoundaryProbe
 $quality=Invoke-SupervisedQuoteFixtures
 $identity=Invoke-SupervisedIdentityProbe
 $batch=@{test='BOUNDARY_QUOTE_VALIDATION_AND_IDENTITY';passed=($boundary.passed -and $quality.passed -and $identity.passed);boundary=$boundary;quoteFixtures=$quality;identity=$identity;ordersEnabled=$false}
 [IO.File]::WriteAllText($ResultPath,($batch|ConvertTo-Json -Depth 8))
 if(-not $batch.passed){exit 1}
 exit 0
}
if($Mode -eq 'Apply'){
 $universe=Invoke-SupervisedUniverseProbe
 [IO.File]::WriteAllText($ResultPath,($universe|ConvertTo-Json -Depth 6))
 if(-not $universe.passed){exit 1}
 $lifecycle=Invoke-SupervisedLifecycleProbe
 $batch=@{test='SUPERVISED_UNIVERSE_AND_LIFECYCLE';passed=$lifecycle.passed;ordersEnabled=$false;universe=$universe;lifecycle=$lifecycle}
 [IO.File]::WriteAllText($ResultPath,($batch|ConvertTo-Json -Depth 8))
 if(-not $lifecycle.passed){exit 1}
 exit 0
}

$result=[ordered]@{version=1;test='SUPERVISED_LOGIN_REPORT_COLLECTION';passed=$false;ordersEnabled=$false;failure=$null}
try{
 if($Mode -ne 'Observe'){throw 'REPORT_OBSERVE_ONLY'}
 $files=@(Get-ChildItem -LiteralPath 'C:\MarketBrainData\Review' -Filter 'paytm-supervised-*.json' -File|Where-Object {$_.Name -match '^paytm-supervised-(login|deployment)-[a-f0-9]{32}\.json$'}|Sort-Object LastWriteTimeUtc -Descending|Select-Object -First 1)
 if($files.Count -ne 1){throw 'SUPERVISED_REPORT_NOT_CREATED_YET'}
 $file=$files[0]
 if($file.Length -gt 16384 -or $file.Attributes -band [IO.FileAttributes]::ReparsePoint){throw 'REPORT_FILE_REJECTED'}
 $stream=$null;$reader=$null
 try{
  $stream=[IO.File]::Open($file.FullName,'Open','Read',([IO.FileShare]::ReadWrite -bor [IO.FileShare]::Delete))
  if($stream.Length -gt 16384){throw 'REPORT_FILE_REJECTED'}
  $reader=[IO.StreamReader]::new($stream)
  $v=$reader.ReadToEnd()|ConvertFrom-Json
 }finally{if($reader){$reader.Dispose()};if($stream){$stream.Dispose()}}
 if($v.version -ne 1 -or $v.runId -cnotmatch '^[a-f0-9]{32}$' -or $v.ordersEnabled -ne $false){throw 'REPORT_SCOPE_REJECTED'}
 $safe=[ordered]@{runId=$v.runId;ordersEnabled=$false}
 foreach($name in @('status','stage','failure','providerFailure','clockSource','applicationState')){
  $text=[string]$v.$name
  if($text -and $text -cnotmatch '^[A-Z0-9_]{1,100}$'){throw 'REPORT_FIELD_REJECTED'}
  $safe[$name]=$text
 }
 foreach($name in @('readAccessVerified','quotesTested','windowsClockGate','vpsAccuracyAssumed')){
  if($v.$name -isnot [bool]){throw 'REPORT_FIELD_REJECTED'};$safe[$name]=$v.$name
 }
 $safe.cleanup=@($v.cleanup|ForEach-Object {if($_ -cnotmatch '^[A-Z_]{1,80}$'){throw 'REPORT_FIELD_REJECTED'};$_})
 $safe.elapsedSeconds=[double]$v.elapsedSeconds
 if($v.PSObject.Properties['identityBinding']){
  $b=$v.identityBinding
  if($b.status -cnotmatch '^[A-Z0-9_]{1,100}$' -or $b.reviewEligible -isnot [bool] -or $b.ordersEnabled -ne $false){throw 'REPORT_IDENTITY_REJECTED'}
  $safe.identityBinding=@{status=$b.status;reviewEligible=$b.reviewEligible;ordersEnabled=$false}
  if($b.PSObject.Properties['identity']){
   $x=$b.identity;$safe.identityBinding.identity=@{}
   $patterns=@{symbol='^[A-Z0-9][A-Z0-9&-]{0,29}$';securityId='^[1-9][0-9]{0,7}$';instrumentId='^[1-9][0-9]{0,18}$';isin='^[A-Z]{2}[A-Z0-9]{9}[0-9]$';snapshotId='^[a-f0-9-]{36}$';snapshotDate='^[0-9]{4}-[0-9]{2}-[0-9]{2}$';providerSha256='^[A-F0-9]{64}$';constituentSha256='^[A-F0-9]{64}$';basis='^UNIQUE_NSE_EQ_SYMBOL_BRIDGE$';membershipScope='^LATEST_PUBLISHED_FILE$'}
   foreach($n in $patterns.Keys){if([string]$x.$n -cnotmatch $patterns[$n]){throw 'REPORT_IDENTITY_REJECTED'};$safe.identityBinding.identity[$n]=$x.$n}
   if($x.providerIsinVerified -ne $false){throw 'REPORT_IDENTITY_REJECTED'};$safe.identityBinding.identity.providerIsinVerified=$false
  }
 }
 if($v.PSObject.Properties['quoteBatch']){
  $x=$v.quoteBatch
  if($x.status -notin @('THREE_FRESH_MAPPED_QUOTES','FRESHNESS_PENDING') -or $x.passed -isnot [bool] -or $x.strictFreshRequired -isnot [bool] -or $x.ordersEnabled -ne $false -or $x.sampleCount -ne 3){throw 'REPORT_BATCH_REJECTED'}
  foreach($n in @('freshCount','staleCount','missingCount')){if([string]$x.$n -cnotmatch '^[0-3]$'){throw 'REPORT_BATCH_REJECTED'}}
  if(($x.freshCount+$x.staleCount+$x.missingCount) -ne 3 -or [string]$x.securityId -cnotmatch '^[1-9][0-9]{0,7}$'){throw 'REPORT_BATCH_REJECTED'}
  $safe.quoteBatch=@{status=$x.status;passed=$x.passed;strictFreshRequired=$x.strictFreshRequired;sampleCount=3;freshCount=[int]$x.freshCount;staleCount=[int]$x.staleCount;missingCount=[int]$x.missingCount;securityId=[int]$x.securityId;ordersEnabled=$false}
 }
 if($v.PSObject.Properties['transportFailure']){
  $x=$v.transportFailure
  if($x.status -cnotmatch '^[A-Z_]{1,100}$' -or ($x.failure -and $x.failure -cnotmatch '^SUPERVISED_[A-Z_]{1,100}$') -or $x.ordersEnabled -ne $false){throw 'REPORT_TRANSPORT_REJECTED'}
  $safe.transportFailure=[ordered]@{status=[string]$x.status;failure=[string]$x.failure;elapsedSeconds=[double]$x.elapsedSeconds;ordersEnabled=$false}
  foreach($n in @('passed','gatewayStopped','transportRejected','sessionLocked','subsequentQuoteRejected')){if($x.$n -isnot [bool]){throw 'REPORT_TRANSPORT_REJECTED'};$safe.transportFailure[$n]=$x.$n}
 }
 if($v.PSObject.Properties['callbackReplay']){
  $x=$v.callbackReplay
  if($x.requested -isnot [bool] -or $x.verified -isnot [bool] -or $x.exchangeAttempts -ne 1){throw 'REPORT_REPLAY_REJECTED'}
  $safe.callbackReplay=@{requested=$x.requested;verified=$x.verified;exchangeAttempts=1}
 }
 if($v.PSObject.Properties['sessionRestart']){
  $x=$v.sessionRestart
  if($x.status -cnotmatch '^[A-Z_]{1,100}$' -or ($x.failure -and $x.failure -cnotmatch '^SUPERVISED_[A-Z_]{1,100}$') -or $x.ordersEnabled -ne $false){throw 'REPORT_RESTART_REJECTED'}
  $safe.sessionRestart=[ordered]@{status=[string]$x.status;failure=[string]$x.failure;elapsedSeconds=[double]$x.elapsedSeconds;ordersEnabled=$false}
  foreach($n in @('passed','authenticatedBeforeRestart','restartAttempted','sameContainer','startChanged','lockedAfterRestart','quoteRejected')){if($x.$n -isnot [bool]){throw 'REPORT_RESTART_REJECTED'};$safe.sessionRestart[$n]=$x.$n}
 }
 if($v.PSObject.Properties['sessionExpiry']){
  $x=$v.sessionExpiry
  if($x.status -cnotmatch '^[A-Z_]{1,100}$' -or ($x.failure -and $x.failure -cnotmatch '^SUPERVISED_[A-Z_]{1,100}$') -or $x.ordersEnabled -ne $false){throw 'REPORT_EXPIRY_REJECTED'}
  $safe.sessionExpiry=[ordered]@{status=[string]$x.status;failure=[string]$x.failure;elapsedSeconds=[double]$x.elapsedSeconds;ordersEnabled=$false}
  foreach($n in @('passed','quoteLimitRejected','authenticatedBeforeWait','expiryObserved','postExpiryQuoteRejected')){if($x.$n -isnot [bool]){throw 'REPORT_EXPIRY_REJECTED'};$safe.sessionExpiry[$n]=$x.$n}
  if($safe.sessionExpiry.elapsedSeconds -lt 0 -or $safe.sessionExpiry.elapsedSeconds -gt 1800){throw 'REPORT_EXPIRY_REJECTED'}
 }
 if($v.PSObject.Properties['universeMatch']){
  $u=$v.universeMatch
  if($u.status -cnotmatch '^[A-Z_]{1,100}$' -or $u.ordersEnabled -ne $false -or $u.snapshotMatched -isnot [bool]){throw 'REPORT_UNIVERSE_REJECTED'}
  $safe.universeMatch=[ordered]@{status=[string]$u.status;snapshotMatched=$u.snapshotMatched;ordersEnabled=$false}
  $patterns=@{symbol='^[A-Z0-9][A-Z0-9&-]{0,29}$';snapshotId='^[a-f0-9-]{36}$';observedOn='^[0-9]{4}-[0-9]{2}-[0-9]{2}$';isin='^[A-Z]{2}[A-Z0-9]{9}[0-9]$';instrumentId='^[1-9][0-9]{0,18}$'}
  foreach($n in $patterns.Keys){if($u.PSObject.Properties[$n]){if([string]$u.$n -cnotmatch $patterns[$n]){throw 'REPORT_UNIVERSE_REJECTED'};$safe.universeMatch[$n]=$u.$n}}
  foreach($n in @('currentMembershipVerified','providerIsinVerified')){if($u.PSObject.Properties[$n]){if($u.$n -isnot [bool] -or $u.$n){throw 'REPORT_UNIVERSE_REJECTED'};$safe.universeMatch[$n]=$false}}
 }
 if($v.PSObject.Properties['quoteMapping']){
  $m=$v.quoteMapping
  if($m.symbol -cnotmatch '^[A-Z0-9][A-Z0-9&-]{0,29}$' -or [string]$m.securityId -cnotmatch '^[1-9][0-9]{0,7}$' -or $m.sha256 -cnotmatch '^[A-F0-9]{64}$' -or $m.exchange -cne 'NSE' -or $m.series -cne 'EQ' -or $m.segment -cne 'E' -or $m.instrumentType -cne 'ES' -or $m.source -cne 'PAYTM_PUBLIC_EQUITY_MASTER' -or $m.localUniverseVerified -ne $false){throw 'REPORT_MAPPING_REJECTED'}
  $safe.quoteMapping=@{symbol=[string]$m.symbol;securityId=[int]$m.securityId;exchange='NSE';series='EQ';segment='E';instrumentType='ES';source='PAYTM_PUBLIC_EQUITY_MASTER';sha256=[string]$m.sha256;localUniverseVerified=$false}
 }
 if($v.PSObject.Properties['quoteSamples']){
  if(@($v.quoteSamples).Count -gt 3){throw 'REPORT_FIELD_REJECTED'}
  $safe.quoteSamples=@($v.quoteSamples|ForEach-Object {
   $q=$_;$s=[ordered]@{}
   foreach($n in @('status','exchange','scripType','timestampEpoch')){
    if($q.PSObject.Properties[$n]){if([string]$q.$n -cnotmatch '^[A-Z0-9_]{1,100}$'){throw 'REPORT_FIELD_REJECTED'};$s[$n]=[string]$q.$n}
   }
   foreach($n in @('securityId','observedEpochMilliseconds','rawTradeTime','tradeEpochMilliseconds','ageMilliseconds','lastPrice')){
    if($q.PSObject.Properties[$n]){if($q.$n -is [string] -or $q.$n -is [bool] -or $null -eq $q.$n){throw 'REPORT_FIELD_REJECTED'};$s[$n]=[decimal]$q.$n}
   }
   foreach($n in @('fresh','mappingVerified','ordersEnabled')){if($q.$n -isnot [bool]){throw 'REPORT_FIELD_REJECTED'};$s[$n]=$q.$n}
   if($q.ordersEnabled -ne $false -or $q.mappingVerified -ne $false){throw 'REPORT_SCOPE_REJECTED'}
   $s
  })
 }
 if($v.PSObject.Properties['failureLine']){$safe.failureLine=[int]$v.failureLine}
 if($v.PSObject.Properties['deploymentAttempted']){$safe.deploymentAttempted=($v.deploymentAttempted -eq $true)}
 if($v.PSObject.Properties['commands']){
  $safe.commands=@($v.commands|ForEach-Object {
   if($_.stage -cnotmatch '^[A-Z_]{1,60}$'){throw 'REPORT_FIELD_REJECTED'}
   @{stage=$_.stage;exitCode=[int]$_.exitCode;elapsedSeconds=[double]$_.elapsedSeconds}
  })
 }
 $result.report=$safe;$result.sourceFile=$file.Name;$result.passed=$true
 if($safe.stage -eq 'GATEWAY'){
  if(-not (Get-Command Get-SupervisedGatewayTaskObservation -ErrorAction SilentlyContinue)){. "$PSScriptRoot/SupervisedGatewayObservation.ps1"}
  $result.gatewayTaskObservation=Get-SupervisedGatewayTaskObservation
 }
 $result.status='REPORT_COLLECTED_NOT_AUTOMATICALLY_ACCEPTED'
}catch{$result.failure=if($_.Exception.Message -cmatch '^[A-Z_]+$'){$_.Exception.Message}else{'REPORT_COLLECTION_FAILED'}}
[IO.File]::WriteAllText($ResultPath,($result|ConvertTo-Json -Depth 6))
if(-not $result.passed){exit 1}
