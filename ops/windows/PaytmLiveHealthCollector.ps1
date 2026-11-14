# Definitions only. No service, clock, gateway or application mutations.
function Get-PaytmLiveHealthAssessment($Round) {
 if($Round.PSObject.Properties['collectionFailure'] -and $Round.collectionFailure){
  return [pscustomobject]@{collectionPassed=$false;findings=@($Round.collectionFailure);failedPhase=$Round.failedPhase;applicationMinusVpsLowerSeconds=0.0;applicationMinusVpsUpperSeconds=0.0;submitted=$false;absoluteAccuracyProven=$false}
 }
 $reasons=[Collections.Generic.List[string]]::new()
 if(-not [double]::IsFinite($Round.elapsedSeconds) -or $Round.elapsedSeconds -lt 0 -or $Round.elapsedSeconds -ge 8){$reasons.Add('COLLECTION_EXCEEDS_EIGHT_SECOND_BUDGET')}
 if(-not [double]::IsFinite($Round.wallSeconds) -or [math]::Abs($Round.wallSeconds-$Round.elapsedSeconds) -gt 0.1){$reasons.Add('WINDOWS_CLOCK_MOVEMENT')}
 if($Round.service.state -cne 'Running' -or $Round.service.startType -ne 2){$reasons.Add('WINDOWS_TIME_SERVICE')}
 if(-not $Round.sync.synchronizedReported){$reasons.Add('WINDOWS_SYNC_UNCONFIRMED')}
 $age=[regex]::Match($Round.windowsStatus.output,'(?im)^Time since Last Good Sync Time:\s*([0-9]+(?:\.[0-9]+)?)s\s*$')
 $poll=[regex]::Match($Round.windowsStatus.output,'(?im)^Poll Interval:\s*(\d+)\s*\((\d+)s\)')
 $ageSeconds=$null;$limit=$null
 if($age.Success -and $poll.Success){
  $ageSeconds=[double]::Parse($age.Groups[1].Value,[Globalization.CultureInfo]::InvariantCulture)
  $pollSeconds=[double]::Parse($poll.Groups[2].Value,[Globalization.CultureInfo]::InvariantCulture)
  $limit=[math]::Min(3600,2*$pollSeconds+60)
  if(-not [double]::IsFinite($ageSeconds) -or $pollSeconds -lt 1 -or $ageSeconds -gt $limit){$reasons.Add('WINDOWS_LAST_SYNC_TOO_OLD')}
 }else{$reasons.Add('WINDOWS_SYNC_AGE_UNKNOWN')}
 if($Round.vps.ntp -cne 'yes'){$reasons.Add('VPS_NTP_UNCONFIRMED')}
 foreach($b in @($Round.vps.bounds,$Round.application.bounds)){
  if(-not $b.usable -or -not [double]::IsFinite($b.lowerOffsetSeconds) -or -not [double]::IsFinite($b.upperOffsetSeconds) -or $b.lowerOffsetSeconds -gt $b.upperOffsetSeconds -or $b.lowerOffsetSeconds -lt -5 -or $b.upperOffsetSeconds -gt 5){$reasons.Add('CLOCK_BOUNDS_OUTSIDE_SCREEN')}
 }
 $lower=$Round.application.bounds.lowerOffsetSeconds-$Round.vps.bounds.upperOffsetSeconds
 $upper=$Round.application.bounds.upperOffsetSeconds-$Round.vps.bounds.lowerOffsetSeconds
 if($lower -lt -5 -or $upper -gt 5){$reasons.Add('JAVA_VPS_OUTSIDE_SCREEN')}
 if(-not $Round.transport.tlsVerified){$reasons.Add('GATEWAY_TLS_UNCONFIRMED')}
 [pscustomobject]@{collectionPassed=($reasons.Count -eq 0);findings=@($reasons.ToArray());lastGoodSyncAgeSeconds=$ageSeconds;syncAgeLimitSeconds=$limit;applicationMinusVpsLowerSeconds=$lower;applicationMinusVpsUpperSeconds=$upper;submitted=$false;absoluteAccuracyProven=$false}
}
function Get-PaytmLiveHealthCurlArguments {
 # -q must be first: ignore curlrc. Explicit empty noproxy overrides bypass environment.
 @('-q','--proxy','http://127.0.0.1:18889','--noproxy','','--head','--proto','=https','--connect-timeout','3','--max-time','5','--silent','--output','NUL','--write-out','%{http_code}|%{remote_ip}','https://developer.paytmmoney.com/')
}
function Invoke-PaytmLiveHealthTransport([string]$Root) {
 try{
  $r=Invoke-PaperRuntimeProcess (Join-Path $env:WINDIR 'System32\curl.exe') (Get-PaytmLiveHealthCurlArguments) $Root 7
  if($r.exitCode -ne 0 -or $r.stdout.Trim() -cnotmatch '^([1-5][0-9]{2})\|127\.0\.0\.1$'){throw 'transport'}
  [pscustomobject]@{tlsVerified=$true;httpStatus=[int]$Matches[1];failure=$null;scope='WINDOWS_FIXED_PROXY_HEAD'}
 }catch{[pscustomobject]@{tlsVerified=$false;httpStatus=0;failure='PROXY_TLS_FAILED';scope='WINDOWS_FIXED_PROXY_HEAD'}}
}
function Invoke-PaytmLiveHealthRound([string]$Plink,[string]$Root,[string]$Token) {
 $wall=[DateTimeOffset]::UtcNow;$clock=[Diagnostics.Stopwatch]::StartNew()
 $phase='WINDOWS_SERVICE';$ssh=$null
 try{
 $service=Get-PaytmTimeRepairSnapshot
 $phase='WINDOWS_STATUS'
 $status=Invoke-PaytmTimeRepairNative 'w32tm.exe' '/query /status /verbose' 5
 $phase='WINDOWS_SOURCE'
 $source=Invoke-PaytmTimeRepairNative 'w32tm.exe' '/query /source' 5
 $nonce=[guid]::NewGuid().ToString('N')
 $start=[DateTimeOffset]::UtcNow;$watch=[Diagnostics.Stopwatch]::StartNew()
 $phase='VPS_SSH'
 $ssh=Invoke-PaperRuntimeProcess $Plink (New-PaytmClockSshArguments $nonce) $Root 8
 $end=[DateTimeOffset]::UtcNow;$watch.Stop()
 if($ssh.exitCode -ne 0){throw 'LIVE_HEALTH_VPS_READ_FAILED'}
 $phase='VPS_RECEIPT'
 $vps=Read-PaytmClockSshReceipt $ssh.stdout $nonce
 $vpsBounds=Get-PaytmClockBounds $start $end $watch.Elapsed.TotalSeconds $vps.time
 $start=[DateTimeOffset]::UtcNow;$watch.Restart()
 $phase='JAVA_CLOCK'
 $java=Invoke-PaytmClockApplication $Token
 $end=[DateTimeOffset]::UtcNow;$watch.Stop()
 $appBounds=Get-PaytmClockBounds $start $end $watch.Elapsed.TotalSeconds $java
 $phase='PROXY_TLS'
 $transport=Invoke-PaytmLiveHealthTransport $Root
 $clock.Stop()
 $row=[pscustomobject]@{service=$service;windowsStatus=$status;sync=(Get-PaytmTimeSyncAssessment $status $source);vps=@{ntp=$vps.ntp;bounds=$vpsBounds};application=@{bounds=$appBounds};transport=$transport;elapsedSeconds=$clock.Elapsed.TotalSeconds;wallSeconds=([DateTimeOffset]::UtcNow-$wall).TotalSeconds;assessment=$null}
 $phase='ASSESSMENT'
 $row.assessment=Get-PaytmLiveHealthAssessment $row
 return $row
 }catch{
  $clock.Stop()
  $failure=if($_.Exception.Message -cmatch '^(CLOCK|LIVE_HEALTH|TIME_REPAIR)_[A-Z_]+$'){$_.Exception.Message}else{'LIVE_HEALTH_STAGE_FAILED'}
  $row=[pscustomobject]@{collectionFailure=$failure;failedPhase=$phase;elapsedSeconds=$clock.Elapsed.TotalSeconds;wallSeconds=([DateTimeOffset]::UtcNow-$wall).TotalSeconds;nativeExitCode=$(if($null -ne $ssh){$ssh.exitCode}else{$null});assessment=$null}
  $row.assessment=Get-PaytmLiveHealthAssessment $row
  return $row
 }
}
