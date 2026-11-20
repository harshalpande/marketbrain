# PS5 compatible. Local readiness is not authority to publish healthy state.
function Test-CollectorApplicationReady {
 Add-Type -AssemblyName System.Net.Http
 $h=[Net.Http.HttpClientHandler]::new();$h.UseProxy=$false;$h.AllowAutoRedirect=$false
 $c=[Net.Http.HttpClient]::new($h);$c.Timeout=[TimeSpan]::FromSeconds(3);$c.MaxResponseContentBufferSize=4096;$response=$null
 try{$response=$c.GetAsync('http://127.0.0.1:8080/actuator/health').GetAwaiter().GetResult();if([int]$response.StatusCode -ne 200){return $false};$v=$response.Content.ReadAsStringAsync().GetAwaiter().GetResult()|ConvertFrom-Json;return ($v.status -ceq 'UP')}catch{return $false}finally{if($response){$response.Dispose()};$c.Dispose()}
}
function Get-CollectorRecoveryElapsed($Watch){return $Watch.Elapsed.TotalSeconds}
function Wait-CollectorApplication([scriptblock]$Enabled) {
 $watch=[Diagnostics.Stopwatch]::StartNew()
 while((& $Enabled)){
  if(Test-CollectorApplicationReady){return}
  if((Get-CollectorRecoveryElapsed $watch) -ge 300){throw 'COLLECTOR_APPLICATION_WAIT_EXHAUSTED'}
  Start-Sleep -Seconds 5
 }
 throw 'COLLECTOR_START_CANCELLED'
}
function Get-CollectorRecoveryBoot([string]$Token) {
 $v=Invoke-CollectorHttp $Token 'clock' $null
 if($v.clockContractVersion -cne 'HEALTH_CLOCK_V1' -or $v.bootId -cnotmatch '^[a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12}$' -or $v.accepted -isnot [bool] -or $v.accepted -or $v.ordersEnabled -isnot [bool] -or $v.ordersEnabled){throw 'COLLECTOR_RECOVERY_CLOCK_CONTRACT'}
 return [string]$v.bootId
}
function Invoke-CollectorRecoveryLoop([string]$Token,[string[]]$SshArguments,[string]$Boot,[scriptblock]$Enabled,[scriptblock]$Save) {
 $r=@{version=2;instanceId=[guid]::NewGuid().ToString('N');processId=$PID;sequence=0;acceptedCount=0;consecutiveFailures=0;phase='STARTING';failure=$null;finalHealthRevoked=$false;ordersEnabled=$false;applicationBootId=$Boot;recoveryCount=0;lastFailure=$null}
 $outage=$null;$recover=$false
 try{
  while((& $Enabled)){
   $r.sequence++;$r.observedUtc=[DateTimeOffset]::UtcNow.ToString('o')
   if(-not (Test-CollectorApplicationReady)){
    if(-not $outage){$outage=[Diagnostics.Stopwatch]::StartNew();try{$null=Invoke-CollectorCycle $Token $SshArguments $Boot -Revoke}catch{}}
    $recover=$true;$r.phase='WAITING_FOR_APPLICATION';$r.failure='COLLECTOR_APPLICATION_NOT_READY';$r.lastFailure=@{code=$r.failure;sequence=$r.sequence}
    & $Save $r
    if((Get-CollectorRecoveryElapsed $outage) -ge 300){throw 'COLLECTOR_APPLICATION_WAIT_EXHAUSTED'}
    Start-Sleep -Seconds 5;continue
   }
   $v=$null
   try{
    $currentBoot=Get-CollectorRecoveryBoot $Token
    if($recover -or $currentBoot -cne $Boot){
     $newBoot=Test-HealthTokenAuthority $Token
     if($newBoot -cne $currentBoot){throw 'COLLECTOR_RECOVERY_BOOT_CHANGED'}
     $Boot=$newBoot;$r.applicationBootId=$Boot;$recover=$false;$r.recoveryCount++
    }
    $v=Invoke-CollectorCycle $Token $SshArguments $Boot
    if(-not $v.accepted -or -not $v.healthySubmitted){throw 'COLLECTOR_SAMPLE_REJECTED'}
    $r.acceptedCount++;$r.consecutiveFailures=0;$r.phase='HEALTH_RECORDED';$r.failure=$null;$outage=$null
   }catch{
    $r.consecutiveFailures++;$r.phase='BACKOFF';$r.failure='COLLECTOR_SAMPLE_FAILED'
    $code=if($_.Exception.Message -cmatch '^(COLLECTOR|HEALTH_TOKEN)_[A-Z_]+$'){$_.Exception.Message}else{'COLLECTOR_SAMPLE_EXCEPTION'}
    $r.lastFailure=@{code=$code;sequence=$r.sequence;phase=$null;findings=@();windowExceeded=$false}
    if($v){$r.lastFailure.phase=if([string]$v.failedPhase -cmatch '^[A-Z_]{1,64}$'){$v.failedPhase}else{$null};$r.lastFailure.findings=@($v.findings|Where-Object {$_ -cmatch '^[A-Z_]{1,100}$'}|Select-Object -First 10);$r.lastFailure.windowExceeded=($v.windowExceeded -eq $true)}
    try{$null=Invoke-CollectorCycle $Token $SshArguments $Boot -Revoke}catch{}
   }
   & $Save $r
   if($r.consecutiveFailures -ge 3){throw 'COLLECTOR_FAILURE_LIMIT'}
   if($outage -and (Get-CollectorRecoveryElapsed $outage) -ge 300){throw 'COLLECTOR_APPLICATION_WAIT_EXHAUSTED'}
   Start-Sleep -Seconds ([int][math]::Min(8,2*[math]::Pow(2,$r.consecutiveFailures)))
  }
  $r.phase='STOPPED';$r.failure=$null
 }catch{$r.phase='FAILED';$r.failure=if($_.Exception.Message -cmatch '^COLLECTOR_[A-Z_]+$'){$_.Exception.Message}else{'COLLECTOR_RUNTIME_FAILED'}}
 finally{
  try{$v=Invoke-CollectorCycle $Token $SshArguments $Boot -Revoke;$r.finalHealthRevoked=($v.revoked -eq $true)}catch{$r.finalHealthRevoked=$false}
  if(-not $r.finalHealthRevoked){$r.phase='FAILED';$r.failure='COLLECTOR_REVOCATION_UNCONFIRMED'}
  $r.observedUtc=[DateTimeOffset]::UtcNow.ToString('o');& $Save $r
 }
 return $r
}
