#Requires -Version 7.0
[CmdletBinding()]param([string]$EvidencePath='C:\MarketBrainData\Review\paytm-live-health-20261115-022556-78ae275dd4234715b40498b204109820.json',[string]$OutputDirectory='C:\MarketBrainData\Review')
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'PaytmLiveHealthCollector.ps1')
. (Join-Path $PSScriptRoot 'PaytmHealthPublisher.ps1')
$watch=[Diagnostics.Stopwatch]::StartNew();$run=[guid]::NewGuid().ToString('N');$null=New-Item -ItemType Directory $OutputDirectory -Force
$file=Join-Path $OutputDirectory ('paytm-publisher-'+$run+'.json')
$report=[ordered]@{version=1;runId=$run;status='REVIEW_REQUIRED';failure=$null;checks=0;sourceHashes=@{};networkCalls=0;realCredentialsUsed=$false;applicationChanged=$false;ordersEnabled=$false;elapsedSeconds=0}
try{
 if((Get-FileHash -LiteralPath $EvidencePath).Hash -cne '2F4A4F7CACCB50EA5DC6A0305421EA1B74D0BF1DFD97CD72DF720E2BD1D405BC'){throw 'PUBLISHER_EVIDENCE_MISMATCH'}
 foreach($n in @('TestPaytmHealthPublisher.ps1','PaytmHealthPublisher.ps1','PaytmLiveHealthCollector.ps1')){$report.sourceHashes[$n]=(Get-FileHash -LiteralPath (Join-Path $PSScriptRoot $n)).Hash}
 Write-Host '[10%] Publisher contract fixtures only. No HTTP request, real token or deployment.'
 function New-FixtureRound {
  [pscustomobject]@{elapsedSeconds=2.0;wallSeconds=2.0;applicationTransportVerified=$true;service=@{state='Running';startType=2};sync=@{synchronizedReported=$true};windowsStatus=@{output="Time since Last Good Sync Time: 20s`nPoll Interval: 10 (1024s)"};vps=@{ntp='yes';bounds=@{usable=$true;lowerOffsetSeconds=-0.1;upperOffsetSeconds=0.1}};application=@{bounds=@{usable=$true;lowerOffsetSeconds=-0.1;upperOffsetSeconds=0.1}};transport=@{tlsVerified=$true}}
 }
 $token='fixture_only_not_a_real_token_12345';$script:badHttp=$false
 function Invoke-WebRequest {
  param($Uri,$Method,$Headers,[switch]$NoProxy,$TimeoutSec,$MaximumRedirection,[switch]$SkipHttpErrorCheck,$ContentType,$Body)
  if($Uri -cne 'http://127.0.0.1:8080/api/v1/paytm/route-health/challenge' -or $Method -cne 'POST' -or -not $NoProxy -or $MaximumRedirection -ne 0 -or $TimeoutSec -ne 2 -or $Headers['X-MarketBrain-Paytm-Health-Token'] -cne $token){throw 'unsafe HTTP contract'}
  if($script:badHttp){throw 'SECRET_ERROR_SHOULD_NOT_ESCAPE'}
  @{StatusCode=200;Headers=@{'Cache-Control'='no-store'};Content='{"fixture":true}'}
 }
 if(-not (Invoke-PaytmHealthHttp 'challenge' $token $null).fixture){throw 'HTTP adapter'};$report.checks++
 $script:badHttp=$true;$errorText=$null
 try{Invoke-PaytmHealthHttp 'challenge' $token $null}catch{$errorText=$_.Exception.Message}
 if($errorText -cne 'HEALTH_PUBLISHER_HTTP_FAILED'){throw 'Error redaction'};$report.checks++
 # Remaining fixtures replace the HTTP adapter; the orchestrator is the actual publisher function.
 function Invoke-PaytmHealthHttp($Command,$Token,$Body){
  $script:events+=,$Command
  if($Command -eq 'challenge'){
   if($script:scenario -eq 'challengefail'){throw 'HEALTH_PUBLISHER_HTTP_FAILED'}
   return @{healthContractVersion=$(if($script:scenario -eq 'oldserver'){'OLD'}else{'SERVER_TRANSPORT_V2'});status='CHALLENGE';challenge='11111111-1111-1111-1111-111111111111';bootId='22222222-2222-2222-2222-222222222222';validForSeconds=10;accepted=$false;ordersEnabled=($script:scenario -eq 'badchallenge')}
  }
  if($Command -cne 'submit'){throw 'Unexpected route action'}
  $script:sent=$Body
  if($script:scenario -eq 'submitfail'){throw 'HEALTH_PUBLISHER_HTTP_FAILED'}
  $accepted=$Body.transportHealthy -and $script:scenario -ne 'rejected'
  @{healthContractVersion='SERVER_TRANSPORT_V2';bootId=$(if($script:scenario -eq 'wrongboot'){'different'}else{$Body.bootId});ordersEnabled=$false;accepted=$accepted;status=$(if($accepted){'HEALTH_RECORDED_EXPLICIT_ARM_REQUIRED'}else{'UNHEALTHY_AND_LOCKED'})}
 }
 $cases=@('healthy','window','collectorfailed','windowsOnly','unsynchronized','tlsfailed','staleSync','nanBounds','challengefail','badchallenge','oldserver','submitfail','wrongboot','rejected')
 foreach($script:scenario in $cases){
  $script:events=@();$script:sent=$null;$script:t=0.0
  $collector={
   $script:events+=,'collect'
   if($script:scenario -eq 'collectorfailed'){throw 'SECRET_INTERNAL_ERROR'}
   if($script:scenario -eq 'window'){$script:t=8.0}
   $r=New-FixtureRound
   switch($script:scenario){
    'windowsOnly'{$r.applicationTransportVerified=$false}
    'unsynchronized'{$r.sync.synchronizedReported=$false}
    'tlsfailed'{$r.transport.tlsVerified=$false}
    'staleSync'{$r.windowsStatus.output="Time since Last Good Sync Time: 4000s`nPoll Interval: 10 (1024s)"}
    'nanBounds'{$r.application.bounds.lowerOffsetSeconds=[double]::NaN}
   };return $r
  }
  $result=Invoke-PaytmHealthPublishOnce $token $collector {$script:t}
  $expected=switch($script:scenario){{$_ -in @('healthy','windowsOnly')}{'HEALTH_PUBLISHED_EXPLICIT_ARM_REQUIRED'} {$_ -in @('challengefail','badchallenge','oldserver','submitfail','wrongboot')}{'PUBLISHER_FAILED_LOCK_UNCONFIRMED'} default{'HEALTH_REJECTED_LOCK_CONFIRMED'}}
  if($result.status -cne $expected){throw "Fixture failed: $script:scenario"}
  if($script:scenario -in @('challengefail','badchallenge','oldserver')){if(($script:events -join ',') -cne 'challenge'){throw 'Collection before valid challenge'}}
  else{if(($script:events -join ',') -cne 'challenge,collect,submit'){throw 'Ordering or retry regression'}}
  if($result.routeArmed -or $result.ordersEnabled -or ($result|ConvertTo-Json).Contains('SECRET')){throw 'Authority or redaction regression'}
  if($script:sent -and -not $script:sent.transportHealthy -and ($script:sent.lowerOffsetSeconds -ne 0 -or $script:sent.upperOffsetSeconds -ne 0)){throw 'Unhealthy bounds not sanitized'}
  $report.checks++
  Write-Progress -Activity 'Publisher fixtures' -PercentComplete (10+80*($cases.IndexOf($script:scenario)+1)/$cases.Count) -Status $script:scenario
 }
 if($report.checks -ne 16){throw 'Incomplete fixture batch'}
 $report.status='PUBLISHER_CONTRACT_PASSED_RUNTIME_PENDING'
}catch{$report.failure=$_.Exception.Message}
finally{
 $report.elapsedSeconds=$watch.Elapsed.TotalSeconds
 [IO.File]::WriteAllText($file,($report|ConvertTo-Json -Depth 8),[Text.UTF8Encoding]::new($false))
 Write-Progress -Activity 'Publisher fixtures' -Completed
 Write-Host "[100%] $($report.status); checks=$($report.checks)"
 Write-Host "Share this ONE file: $file"
}
if($report.failure){throw $report.failure}
