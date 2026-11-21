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

if($Mode -eq 'FailureFixture'){
 $boundary=Invoke-SupervisedBoundaryProbe
 [IO.File]::WriteAllText($ResultPath,($boundary|ConvertTo-Json -Depth 6))
 if(-not $boundary.passed){exit 1}
 exit 0
}
if($Mode -eq 'Apply'){
 $universe=Invoke-SupervisedUniverseProbe
 [IO.File]::WriteAllText($ResultPath,($universe|ConvertTo-Json -Depth 6))
 if(-not $universe.passed){exit 1}
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
 $result.status='REPORT_COLLECTED_NOT_AUTOMATICALLY_ACCEPTED'
}catch{$result.failure=if($_.Exception.Message -cmatch '^[A-Z_]+$'){$_.Exception.Message}else{'REPORT_COLLECTION_FAILED'}}
[IO.File]::WriteAllText($ResultPath,($result|ConvertTo-Json -Depth 6))
if(-not $result.passed){exit 1}
