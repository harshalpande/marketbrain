# PS5.1-compatible collector. Fixed destinations only; no broker credentials or route arm.
function Limit-CollectorDiagnostic([string]$Text){if($Text.Length -gt 512){$Text.Substring(0,512)}else{$Text}}
function Invoke-CollectorHttp([string]$Token,[ValidateSet('clock','challenge','submit')][string]$Command,$Body){
 Add-Type -AssemblyName System.Net.Http
 $h=[Net.Http.HttpClientHandler]::new();$h.UseProxy=$false;$h.AllowAutoRedirect=$false
 $c=[Net.Http.HttpClient]::new($h);$c.Timeout=[TimeSpan]::FromSeconds(3);$c.MaxResponseContentBufferSize=4096;$response=$null;$request=$null
 try{
  $request=[Net.Http.HttpRequestMessage]::new([Net.Http.HttpMethod]::Post,('http://127.0.0.1:8080/api/v1/paytm/route-health/'+$Command))
  $null=$request.Headers.TryAddWithoutValidation('X-MarketBrain-Paytm-Health-Token',$Token)
  $null=$request.Headers.TryAddWithoutValidation('X-MarketBrain-Paytm-Health','diagnostic-health')
  if($null -ne $Body){$request.Content=[Net.Http.StringContent]::new(($Body|ConvertTo-Json -Compress),[Text.Encoding]::UTF8,'application/json')}
  $response=$c.SendAsync($request).GetAwaiter().GetResult()
  if([int]$response.StatusCode -ne 200 -or -not $response.Headers.CacheControl.NoStore){throw 'contract'}
  $response.Content.ReadAsStringAsync().GetAwaiter().GetResult()|ConvertFrom-Json
 }catch{throw 'COLLECTOR_HTTP_FAILED'}finally{if($response){$response.Dispose()};if($request){$request.Dispose()};$c.Dispose()}
}
function Get-CollectorBounds([DateTimeOffset]$Start,[DateTimeOffset]$End,[double]$Elapsed,[long]$Millis){
 $wall=($End-$Start).TotalSeconds;$movement=[math]::Abs($wall-$Elapsed);$padding=0.002+$movement
 $remote=[DateTimeOffset]::FromUnixTimeMilliseconds($Millis)
 [pscustomobject]@{lowerOffsetSeconds=($remote-$End).TotalSeconds-$padding;upperOffsetSeconds=($remote-$Start).TotalSeconds+$padding;elapsedSeconds=$Elapsed;wallMovementSeconds=$movement;usable=((Test-PaytmFinite $Elapsed) -and $Elapsed -ge 0 -and $Elapsed -le 2 -and $wall -ge 0 -and $movement -le 0.1)}
}
function Invoke-CollectorTransport {
 $p=[Diagnostics.Process]::new();$p.StartInfo.FileName=Join-Path $env:WINDIR 'System32\curl.exe'
 $p.StartInfo.Arguments='-q --proxy http://127.0.0.1:18889 --noproxy "" --head --proto =https --connect-timeout 2 --max-time 3 --silent --show-error --output NUL --write-out "%{http_code}|%{remote_ip}" https://developer.paytmmoney.com/'
 $p.StartInfo.UseShellExecute=$false;$p.StartInfo.CreateNoWindow=$true;$p.StartInfo.RedirectStandardOutput=$true;$p.StartInfo.RedirectStandardError=$true;$started=$false
 $diag=[ordered]@{exitCode=$null;timedOut=$false;stdout='';stderr='';exceptionType=$null}
 try{
  $started=$p.Start();$o=$p.StandardOutput.ReadToEndAsync();$e=$p.StandardError.ReadToEndAsync()
  if(-not $p.WaitForExit(4000)){$diag.timedOut=$true;throw 'timeout'}
  $diag.exitCode=$p.ExitCode
  if(-not $o.Wait(1000) -or -not $e.Wait(1000)){throw 'drain'}
  $diag.stdout=Limit-CollectorDiagnostic $o.Result;$diag.stderr=Limit-CollectorDiagnostic $e.Result
  if($p.ExitCode -ne 0 -or $o.Result.Trim() -cnotmatch '^([1-5][0-9]{2})\|127\.0\.0\.1$'){throw 'tls'}
  [pscustomobject]@{tlsVerified=$true;httpStatus=[int]$Matches[1];diagnostic=$diag}
 }catch{$diag.exceptionType=$_.Exception.GetBaseException().GetType().Name;[pscustomobject]@{tlsVerified=$false;httpStatus=0;diagnostic=$diag}}finally{if($started -and -not $p.HasExited){$p.Kill();$null=$p.WaitForExit(1000)};$p.Dispose()}
}
function Get-CollectorWindowsService($Status) {
 # A successful local w32tm status query establishes service responsiveness without
 # requiring extra SCM permissions on the non-interactive health account.
 $key=[Microsoft.Win32.Registry]::LocalMachine.OpenSubKey('SYSTEM\CurrentControlSet\Services\W32Time')
 try{@{state=$(if($Status.exitCode -eq 0){'Running'}else{'Unavailable'});startType=[int]$key.GetValue('Start')}}finally{if($key){$key.Dispose()}}
}
function Invoke-CollectorRound([string]$Token,[string[]]$SshArguments,[string]$Boot){
 $timer=[Diagnostics.Stopwatch]::StartNew();$wall=[DateTimeOffset]::UtcNow;$phase='WINDOWS_TIME'
 $diag=[ordered]@{windowsStatus=$null;windowsSource=$null;service=$null;vpsBounds=$null;javaBounds=$null;transport=$null;exceptionType=$null}
 try{
  $status=Invoke-PaytmTimeRepairNative 'w32tm.exe' '/query /status /verbose' 3
  $diag.windowsStatus=@{exitCode=$status.exitCode;output=(Limit-CollectorDiagnostic $status.output)}
  $source=Invoke-PaytmTimeRepairNative 'w32tm.exe' '/query /source' 3
  $diag.windowsSource=@{exitCode=$source.exitCode;output=(Limit-CollectorDiagnostic $source.output)}
  $service=Get-CollectorWindowsService $status
  $diag.service=$service
  $phase='VPS_CLOCK';$nonce=[guid]::NewGuid().ToString('N');$argsCopy=@($SshArguments|ForEach-Object {if($_ -ceq 'ConnectTimeout=15'){'ConnectTimeout=2'}else{$_}});$argsCopy[-1]='marketbrain-clock '+$nonce
  $start=[DateTimeOffset]::UtcNow;$watch=[Diagnostics.Stopwatch]::StartNew()
  $ssh=Invoke-PaytmCustodyNative 'ssh.exe' $argsCopy 3
  $end=[DateTimeOffset]::UtcNow;$watch.Stop()
  if($ssh.StoppedByRunner -or $ssh.ExitCode -ne 0 -or $ssh.Stdout.Trim() -cnotmatch ('^MB_CLOCK_V1\|'+$nonce+'\|([0-9]{13})\|yes$')){throw 'COLLECTOR_VPS_CLOCK'}
  $vps=Get-CollectorBounds $start $end $watch.Elapsed.TotalSeconds ([long]$Matches[1])
  $diag.vpsBounds=$vps
  $phase='JAVA_CLOCK';$start=[DateTimeOffset]::UtcNow;$watch.Restart()
  $java=Invoke-CollectorHttp $Token 'clock' $null
  $end=[DateTimeOffset]::UtcNow;$watch.Stop()
  if($java.clockContractVersion -cne 'HEALTH_CLOCK_V1' -or $java.bootId -cne $Boot -or $java.observedEpochMillis -isnot [long] -or $java.accepted -isnot [bool] -or $java.accepted -or $java.ordersEnabled -isnot [bool] -or $java.ordersEnabled){throw 'COLLECTOR_JAVA_CLOCK'}
  $app=Get-CollectorBounds $start $end $watch.Elapsed.TotalSeconds $java.observedEpochMillis
  $diag.javaBounds=$app
  $phase='PROXY_TLS';$transport=Invoke-CollectorTransport
  $diag.transport=$transport
  $round=[pscustomobject]@{service=$service;windowsStatus=$status;sync=(Get-PaytmTimeSyncAssessment $status $source);vps=@{ntp='yes';bounds=$vps};application=@{bounds=$app};transport=$transport;elapsedSeconds=$timer.Elapsed.TotalSeconds;wallSeconds=([DateTimeOffset]::UtcNow-$wall).TotalSeconds}
  $assessment=Get-PaytmLiveHealthAssessment $round
  $assessment|Add-Member -NotePropertyName diagnostics -NotePropertyValue $diag
  $assessment
 }catch{$diag.exceptionType=$_.Exception.GetBaseException().GetType().Name;[pscustomobject]@{collectionPassed=$false;findings=@('COLLECTOR_SAMPLE_FAILED');failedPhase=$phase;applicationMinusVpsLowerSeconds=0;applicationMinusVpsUpperSeconds=0;diagnostics=$diag}}
}
function Assert-CollectorReceipt($Value,[string]$Boot){
 if($Value.healthContractVersion -cne 'SERVER_TRANSPORT_V2' -or $Value.bootId -cne $Boot -or $Value.ordersEnabled -isnot [bool] -or $Value.ordersEnabled -or $Value.accepted -isnot [bool]){throw 'COLLECTOR_RECEIPT'}
}
function Invoke-CollectorCycle([string]$Token,[string[]]$SshArguments,[string]$Boot,[switch]$Revoke){
 $clock=[Diagnostics.Stopwatch]::StartNew();$c=Invoke-CollectorHttp $Token 'challenge' $null
 Assert-CollectorReceipt $c $Boot
 if($c.status -cne 'CHALLENGE' -or $c.accepted -or $c.validForSeconds -ne 10 -or $c.challenge -cnotmatch '^[a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12}$'){throw 'COLLECTOR_CHALLENGE'}
 $assessment=if($Revoke){[pscustomobject]@{collectionPassed=$false;findings=@('FINAL_REVOCATION')}}else{Invoke-CollectorRound $Token $SshArguments $Boot}
 $windowExceeded=$clock.Elapsed.TotalSeconds -ge 8
 $healthy=-not $Revoke -and $assessment.collectionPassed -and -not $windowExceeded
 $body=@{challenge=$c.challenge;bootId=$Boot;synchronizedClock=[bool]$healthy;transportHealthy=[bool]$healthy;lowerOffsetSeconds=0;upperOffsetSeconds=0}
 if($healthy){$body.lowerOffsetSeconds=$assessment.applicationMinusVpsLowerSeconds;$body.upperOffsetSeconds=$assessment.applicationMinusVpsUpperSeconds}
 $v=Invoke-CollectorHttp $Token 'submit' $body;Assert-CollectorReceipt $v $Boot
 if($v.accepted -and (-not $healthy -or $v.status -cne 'HEALTH_RECORDED_EXPLICIT_ARM_REQUIRED')){throw 'COLLECTOR_UNEXPECTED_ACCEPTANCE'}
 if(-not $v.accepted -and $v.status -cnotin @('UNHEALTHY_AND_LOCKED','REJECTED_AND_LOCKED')){throw 'COLLECTOR_UNEXPECTED_REJECTION'}
 [pscustomobject]@{healthySubmitted=[bool]$healthy;accepted=$v.accepted;status=$v.status;findings=$assessment.findings;failedPhase=$(if($assessment.PSObject.Properties['failedPhase']){$assessment.failedPhase}else{$null});diagnostics=$(if($assessment.PSObject.Properties['diagnostics']){$assessment.diagnostics}else{$null});lowerOffsetSeconds=$body.lowerOffsetSeconds;upperOffsetSeconds=$body.upperOffsetSeconds;windowExceeded=$windowExceeded;elapsedSeconds=$clock.Elapsed.TotalSeconds;revoked=($Revoke -and -not $v.accepted -and $v.status -ceq 'UNHEALTHY_AND_LOCKED')}
}
