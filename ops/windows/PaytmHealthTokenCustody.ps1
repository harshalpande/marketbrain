#Requires -Version 5.1
# CurrentUser DPAPI only. Never return a token in an evidence object.
function Get-HealthTokenEntropy { [Text.Encoding]::UTF8.GetBytes('MarketBrain.HealthPublisher.Token.V1') }
function Protect-HealthToken([string]$Token){
 if($Token -cnotmatch '^[A-Za-z0-9_-]{32,128}$'){throw 'HEALTH_TOKEN_FORMAT'}
 Add-Type -AssemblyName System.Security
 $bytes=[Text.Encoding]::UTF8.GetBytes($Token)
 try{,[Security.Cryptography.ProtectedData]::Protect($bytes,(Get-HealthTokenEntropy),[Security.Cryptography.DataProtectionScope]::CurrentUser)}finally{[Array]::Clear($bytes,0,$bytes.Length)}
}
function Unprotect-HealthToken([byte[]]$Cipher){
 if($Cipher.Length -lt 100 -or $Cipher.Length -gt 4096){throw 'HEALTH_TOKEN_CIPHER_SIZE'}
 Add-Type -AssemblyName System.Security
 $bytes=$null
 try{
  $bytes=[Security.Cryptography.ProtectedData]::Unprotect($Cipher,(Get-HealthTokenEntropy),[Security.Cryptography.DataProtectionScope]::CurrentUser)
  $token=[Text.Encoding]::UTF8.GetString($bytes)
  if($token -cnotmatch '^[A-Za-z0-9_-]{32,128}$'){throw 'HEALTH_TOKEN_FORMAT'}
  return $token
 }finally{if($null -ne $bytes){[Array]::Clear($bytes,0,$bytes.Length)}}
}
function Invoke-HealthTokenHttp([string]$Token,[string]$Command,$Body){
 Add-Type -AssemblyName System.Net.Http
 $handler=[Net.Http.HttpClientHandler]::new();$handler.UseProxy=$false;$handler.AllowAutoRedirect=$false
 $client=[Net.Http.HttpClient]::new($handler);$client.Timeout=[TimeSpan]::FromSeconds(3);$client.MaxResponseContentBufferSize=4096;$response=$null;$request=$null
 try{
  if($Command -cnotin @('challenge','submit')){throw 'HEALTH_TOKEN_COMMAND'}
  $request=[Net.Http.HttpRequestMessage]::new([Net.Http.HttpMethod]::Post,('http://127.0.0.1:8080/api/v1/paytm/route-health/'+$Command))
  $null=$request.Headers.TryAddWithoutValidation('X-MarketBrain-Paytm-Health-Token',$Token)
  $null=$request.Headers.TryAddWithoutValidation('X-MarketBrain-Paytm-Health','diagnostic-health')
  if($null -ne $Body){$request.Content=[Net.Http.StringContent]::new(($Body|ConvertTo-Json -Compress),[Text.Encoding]::UTF8,'application/json')}
  $response=$client.SendAsync($request).GetAwaiter().GetResult()
  if([int]$response.StatusCode -ne 200 -or -not $response.Headers.CacheControl.NoStore){throw 'HEALTH_TOKEN_HTTP'}
  $text=$response.Content.ReadAsStringAsync().GetAwaiter().GetResult()
  if($text.Length -gt 2048){throw 'HEALTH_TOKEN_HTTP'}
  $text|ConvertFrom-Json
 }catch{throw 'HEALTH_TOKEN_HTTP_FAILED'}finally{if($response){$response.Dispose()};if($request){$request.Dispose()};$client.Dispose()}
}
function Test-HealthTokenAuthority([string]$Token){
 $c=Invoke-HealthTokenHttp $Token 'challenge' $null
 $uuid='^[a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12}$'
 if($c.healthContractVersion -cne 'SERVER_TRANSPORT_V2' -or $c.status -cne 'CHALLENGE' -or $c.challenge -cnotmatch $uuid -or $c.bootId -cnotmatch $uuid -or $c.validForSeconds -ne 10 -or $c.accepted -isnot [bool] -or $c.accepted -or $c.ordersEnabled -isnot [bool] -or $c.ordersEnabled){throw 'HEALTH_TOKEN_CHALLENGE_INVALID'}
 # Always submit unhealthy: custody verification must not create usable route health.
 $body=@{challenge=$c.challenge;bootId=$c.bootId;synchronizedClock=$false;transportHealthy=$false;lowerOffsetSeconds=0;upperOffsetSeconds=0}
 $r=Invoke-HealthTokenHttp $Token 'submit' $body
 if($r.healthContractVersion -cne 'SERVER_TRANSPORT_V2' -or $r.bootId -cne $c.bootId -or $r.status -cne 'UNHEALTHY_AND_LOCKED' -or $r.accepted -isnot [bool] -or $r.accepted -or $r.ordersEnabled -isnot [bool] -or $r.ordersEnabled){throw 'HEALTH_TOKEN_LOCK_NOT_CONFIRMED'}
 return $c.bootId
}
function New-HealthTokenWorkerSource([string]$Run,[ValidateSet('Stage','Verify')][string]$Mode){
 if($Run -cnotmatch '^[a-f0-9]{32}$'){throw 'HEALTH_TOKEN_RUN'}
 $template=@'
$ErrorActionPreference='Stop'
$root='C:\ProgramData\MarketBrainPaytmHealth\token-custody'
. ([scriptblock]::Create([IO.File]::ReadAllText($root+'\library.ps1')))
$result=[ordered]@{version=1;runId='__RUN__';mode='__MODE__';identityVerified=$false;encrypted=$false;authenticated=$false;locked=$false;bootId=$null;failure=$null}
$token=$null;$cipher=$null
try{
 $id=[Security.Principal.WindowsIdentity]::GetCurrent()
 if($id.User.Value -cne 'S-1-5-21-3041730714-102984520-3202743044-1011' -or ([Security.Principal.WindowsPrincipal]::new($id)).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)){throw 'HEALTH_TOKEN_IDENTITY'}
 $result.identityVerified=$true
 if('__MODE__' -ceq 'Stage'){
  $token=$env:MARKETBRAIN_HEALTH_CUSTODY_TRANSFER
  Remove-Item Env:MARKETBRAIN_HEALTH_CUSTODY_TRANSFER -ErrorAction SilentlyContinue
  $cipher=Protect-HealthToken $token
  if((Unprotect-HealthToken $cipher) -cne $token){throw 'HEALTH_TOKEN_ROUNDTRIP'}
  $f=[IO.File]::Open('C:\ProgramData\MarketBrainPaytmHealth\work\token-__RUN__.dpapi','CreateNew','Write','None')
  try{$f.Write($cipher,0,$cipher.Length);$f.Flush($true)}finally{$f.Dispose()}
 }else{$cipher=[IO.File]::ReadAllBytes($root+'\health-token.dpapi');$token=Unprotect-HealthToken $cipher}
 $result.encrypted=$true
 $result.bootId=Test-HealthTokenAuthority $token
 $result.authenticated=$true;$result.locked=$true
}catch{$result.failure=if($_.Exception.Message -cmatch '^HEALTH_TOKEN_[A-Z_]+$'){$_.Exception.Message}else{'HEALTH_TOKEN_WORKER_FAILED'}}finally{$token=$null;$cipher=$null}
$result|ConvertTo-Json -Compress
'@
 $template.Replace('__RUN__',$Run).Replace('__MODE__',$Mode)
}
