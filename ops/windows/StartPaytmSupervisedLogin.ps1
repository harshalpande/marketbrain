#Requires -Version 7.2
#Requires -RunAsAdministrator
[CmdletBinding()]param(
 [switch]$TestQuotes,
 [switch]$RequireFreshQuotes,
 [switch]$TestSessionExpiry,
 [switch]$TestSessionRestart,
 [switch]$TestCallbackReplay,
 [switch]$TestTransportFailure,
 [switch]$BindReviewIdentity,
 [ValidatePattern('^[A-Z0-9][A-Z0-9&-]{0,29}$')][string]$QuoteSymbol,
 [ValidateRange(1,99999999)][int]$QuoteSecurityId=3456,
 [string]$ClockKeyPath,
 [string]$OutputDirectory='C:\MarketBrainData\Review')
$ErrorActionPreference='Stop'
. "$PSScriptRoot/PaytmClockLogin.ps1"
. "$PSScriptRoot/PaytmGatewayKeyCustody.ps1"
. "$PSScriptRoot/PaytmQuoteMapping.ps1"
. "$PSScriptRoot/PaytmQuoteBatch.ps1"
. "$PSScriptRoot/PaytmAuthenticatedExpiry.ps1"
. "$PSScriptRoot/PaytmAuthenticatedRestart.ps1"
. "$PSScriptRoot/PaytmTransportFailure.ps1"
$id=[guid]::NewGuid().ToString('N');$timer=[Diagnostics.Stopwatch]::StartNew()
$null=New-Item -ItemType Directory -Force -Path $OutputDirectory
$path=Join-Path $OutputDirectory "paytm-supervised-login-$id.json"
$report=[ordered]@{version=1;runId=$id;status='REVIEW_REQUIRED';stage='PREPARATION';failure=$null;cleanup=@();elapsedSeconds=0;clockSource='VPS_ANCHORED_MONOTONIC';vpsAccuracyAssumed=$true;windowsClockGate=$false;readAccessVerified=$false;quotesTested=$false;ordersEnabled=$false}
$taskName='MarketBrain-Gateway-Supervisor-v1';$gatewayStarted=$false;$headers=$null;$loginStarted=$false
function Save-SupervisedReport {
 $report.elapsedSeconds=$timer.Elapsed.TotalSeconds
 [IO.File]::WriteAllText(($path+'.tmp'),($report|ConvertTo-Json -Depth 6))
 [IO.File]::Move(($path+'.tmp'),$path,$true)
}
function Read-LocalSecret([string]$Prompt) { $s=Read-Host $Prompt -AsSecureString;try{[Net.NetworkCredential]::new('',$s).Password}finally{$s.Dispose()} }
function Stop-SupervisedGateway {
 # Final cleanup may follow an already successful fault-test stop.
 $current=Get-ScheduledTask -TaskName $taskName
 if($current.State -ne 'Disabled'){Stop-ScheduledTask -TaskName $taskName;$null=Disable-ScheduledTask -TaskName $taskName}
 $stop=[Diagnostics.Stopwatch]::StartNew()
 do{
  $listeners=@([Net.NetworkInformation.IPGlobalProperties]::GetIPGlobalProperties().GetActiveTcpListeners()|Where-Object Port -EQ 18889)
  if((Get-ScheduledTask -TaskName $taskName).State -eq 'Disabled' -and -not $listeners.Count){return $true}
  Start-Sleep -Seconds 1
 }while($stop.Elapsed.TotalSeconds -lt 30)
 return $false
}
function Invoke-LocalSupervised([string]$Command,$Body=$null) {
 $p=@{Uri="http://127.0.0.1:8080/api/v1/paytm/supervised/$Command";Method='Post';Headers=$headers;NoProxy=$true;TimeoutSec=40}
 if($Command -eq 'review-quote'){$p.TimeoutSec=60}
 if($null -ne $Body){$p.ContentType='application/json';$p.Body=($Body|ConvertTo-Json -Compress)}
 Invoke-RestMethod @p
}
try {
 Save-SupervisedReport
 if($BindReviewIdentity -and (-not $TestQuotes -or -not $QuoteSymbol -or -not $RequireFreshQuotes -or $TestTransportFailure -or $TestSessionExpiry -or $TestSessionRestart)){throw 'SUPERVISED_IDENTITY_ARGUMENT_CONFLICT'}
 if($TestTransportFailure -and (-not $TestQuotes -or -not $QuoteSymbol -or $RequireFreshQuotes -or $TestSessionExpiry -or $TestSessionRestart)){throw 'SUPERVISED_TRANSPORT_ARGUMENT_CONFLICT'}
 if($RequireFreshQuotes -and (-not $TestQuotes -or -not $QuoteSymbol)){throw 'SUPERVISED_FRESH_REQUIRES_MAPPED_QUOTES'}
 if($TestSessionExpiry -and (-not $TestQuotes -or -not $QuoteSymbol)){throw 'SUPERVISED_EXPIRY_REQUIRES_MAPPED_QUOTES'}
 if($TestSessionRestart -and ($TestSessionExpiry -or -not $TestQuotes -or -not $QuoteSymbol)){throw 'SUPERVISED_RESTART_REQUIRES_MAPPED_QUOTES_NO_EXPIRY'}
 if($QuoteSymbol){
  if(-not $TestQuotes -or $PSBoundParameters.ContainsKey('QuoteSecurityId')){throw 'SUPERVISED_MAPPING_ARGUMENT_CONFLICT'}
  $report.stage='INSTRUMENT_MAPPING';Save-SupervisedReport
  Write-Host '[5%] Resolving the selected NSE EQ symbol from the public Paytm master (25-second limit).'
  $report.quoteMapping=Get-PaytmQuoteMapping -Symbol $QuoteSymbol
  $QuoteSecurityId=$report.quoteMapping.securityId
  Write-Host "Provider mapping: $QuoteSymbol -> NSE:$QuoteSecurityId`:EQUITY. Local Nifty universe match remains pending."
  Save-SupervisedReport
 }
 Write-Host '[10%] Supervised PAPER login. App credentials stay on this laptop; no order operations.'
 $report.stage='APPLICATION';Save-SupervisedReport
 $headers=@{'X-MarketBrain-Paper-Read-Token'=(Read-LocalSecret 'Existing private paper read token');'X-MarketBrain-Paytm-Supervised'='supervised-paper'}
 $initial=Invoke-LocalSupervised 'status'
 if($initial.ordersEnabled -ne $false -or $initial.status -ne 'LOCKED'){throw 'SUPERVISED_EXISTING_SESSION_OR_SCOPE'}
 if($QuoteSymbol){
  $report.stage='LOCAL_UNIVERSE';Save-SupervisedReport
  $report.universeMatch=Invoke-LocalSupervised 'universe-match' @{symbol=$QuoteSymbol}
  Save-SupervisedReport
  if($report.universeMatch.status -ne 'LOCAL_SNAPSHOT_SYMBOL_ISIN_MATCHED' -or $report.universeMatch.snapshotMatched -ne $true -or $report.universeMatch.symbol -cne $QuoteSymbol -or $report.universeMatch.ordersEnabled -ne $false){throw 'SUPERVISED_LOCAL_UNIVERSE_NOT_MATCHED'}
  Write-Host "Local snapshot match: $QuoteSymbol; snapshot dated $($report.universeMatch.observedOn). Current membership and provider ISIN are not asserted."
 }
 $report.stage='GATEWAY';Save-SupervisedReport
 $collector=Get-ScheduledTask -TaskName 'MarketBrain-Health-Collector-v1' -ErrorAction SilentlyContinue
 if($collector -and ($collector.State -ne 'Disabled')){throw 'SUPERVISED_COLLECTOR_MUST_BE_DISABLED'}
 $task=Get-ScheduledTask -TaskName $taskName
 if($task.Description -cne 'MarketBrain locked supervisor ea8b91471cf048aa97a0f6b939b355c7' -or $task.State -ne 'Disabled'){throw 'SUPERVISED_GATEWAY_MUST_BE_STOPPED_DISABLED'}
 $gatewayRoot='C:\ProgramData\MarketBrainPaytmGateway\supervisor-v1'
 if((Get-Content "$gatewayRoot/control.json" -Raw|ConvertFrom-Json).mode -ne 'LOCKED' -or (Get-Content "$gatewayRoot/transport-control.json" -Raw|ConvertFrom-Json).mode -ne 'ENABLED'){throw 'SUPERVISED_GATEWAY_CONTROL'}
 $gatewayWork='C:\ProgramData\MarketBrainPaytmGateway\supervisor-work-v1'
 if(Test-Path "$gatewayWork/blocked.json"){throw 'SUPERVISED_GATEWAY_EXISTING_FAILURE'}
 $previous=(Get-Content "$gatewayWork/status.json" -Raw|ConvertFrom-Json).instanceId
 $gatewayStarted=$true
 $null=Enable-ScheduledTask -TaskName $taskName
 Start-ScheduledTask -TaskName $taskName
 $wait=[Diagnostics.Stopwatch]::StartNew();$ready=$false
 $report.gatewayStartup=@{samples=@();ready=$false}
 do {
  Start-Sleep -Seconds 1
  $v=Get-Content "$gatewayWork/status.json" -Raw|ConvertFrom-Json
  $taskState=[string](Get-ScheduledTask -TaskName $taskName).State
  $taskResult=[long](Get-ScheduledTaskInfo -TaskName $taskName).LastTaskResult
  $phase=if([string]$v.phase -cmatch '^[A-Z_]{1,60}$'){[string]$v.phase}else{'INVALID'}
  $report.gatewayStartup.samples=@($report.gatewayStartup.samples|Select-Object -Last 19)+@(@{seconds=[math]::Round($wait.Elapsed.TotalSeconds,2);newInstance=($v.instanceId -ne $previous);phase=$phase;sequence=[long]$v.sequence;taskState=$taskState;taskResult=$taskResult})
  Save-SupervisedReport
  if($v.instanceId -ne $previous -and $v.phase -eq 'BLOCKED'){throw 'SUPERVISED_GATEWAY_BLOCKED'}
  if($v.instanceId -ne $previous -and $v.phase -eq 'TRANSPORT_READY' -and $v.ordersEnabled -eq $false){$ready=$true;break}
  Write-Progress -Activity 'Supervised Paytm login' -PercentComplete 20 -Status "Starting gateway: $([int]$wait.Elapsed.TotalSeconds)/60 seconds"
 }while($wait.Elapsed.TotalSeconds -lt 60)
 if(-not $ready){throw 'SUPERVISED_GATEWAY_TIMEOUT'}
 $report.gatewayStartup.ready=$true;Save-SupervisedReport
 Write-Host '[35%] Enter app credentials locally, then read VPS time over pinned SSH.'
 $apiKey=Read-LocalSecret 'Paytm developer app API key'
 $apiSecret=Read-LocalSecret 'Paytm developer app API secret'
 if(-not $ClockKeyPath){$ClockKeyPath=(Read-Host 'Full path to encrypted OpenSSH CLOCK key (not gateway key)').Trim().Trim('"').Trim("'")}
 if(-not (Test-Path -LiteralPath $ClockKeyPath -PathType Leaf)){throw 'SUPERVISED_CLOCK_KEY_NOT_FOUND'}
 $pins=ConvertFrom-PaytmHostPublicKey ([IO.File]::ReadAllText((Join-Path $PSScriptRoot 'paytm-vps-host-rsa.pub')).Trim())
 $known=Join-Path $OutputDirectory "supervised-known-host-$id.txt"
 [IO.File]::WriteAllText($known,$pins.knownHost)
 $report.stage='VPS_TIME';Save-SupervisedReport
 $nonce=[guid]::NewGuid().ToString('N')
 $args=Get-ClockLoginSshArguments $known $ClockKeyPath
 Write-Host 'Enter the CLOCK KEY passphrase if SSH requests it. No Windows time comparison is performed.'
 $reply=Invoke-ClockLoginNative "$env:WINDIR/System32/OpenSSH/ssh.exe" ($args+@("marketbrain-clock $nonce")) 180
 $clock=Assert-ClockLoginReply $reply $nonce $true
 $report.vpsNtpReported=$clock.ntpSynchronized
 # User accepts VPS accuracy for this supervised prototype. NTP flag is recorded, not a gate.
 $report.stage='LOGIN';Save-SupervisedReport
 $loginStarted=$true
 $start=Invoke-LocalSupervised 'start' @{apiKey=$apiKey;apiSecret=$apiSecret;vpsEpochMilliseconds=$clock.epochMilliseconds;verifyCallbackReplay=[bool]$TestCallbackReplay}
 $apiKey=$null;$apiSecret=$null
 if($start.browserUrl -cnotmatch '^http://127\.0\.0\.1:8080/paytm/supervised/browser\?code=[A-Za-z0-9_-]{43}$'){throw 'SUPERVISED_BROWSER_URL_REJECTED'}
 Start-Process $start.browserUrl
 Write-Host '[60%] Complete Paytm login/OTP in the browser on THIS laptop. Waiting up to 10 minutes.'
 $wait.Restart()
 do {
  Start-Sleep -Seconds 2
  $state=Invoke-LocalSupervised 'status'
  $report.applicationState=[string]$state.status
  $report.providerFailure=[string]$state.failure
  Save-SupervisedReport
  Write-Progress -Activity 'Supervised Paytm login' -PercentComplete 60 -Status "$($state.status): $([int]$wait.Elapsed.TotalSeconds)/600 seconds"
  if($state.readAccessVerified -eq $true){$report.readAccessVerified=$true;break}
  if($state.status -eq 'LOCKED'){$report.providerFailure=[string]$state.failure;throw 'SUPERVISED_PROVIDER_OR_SESSION_FAILURE'}
 }while($wait.Elapsed.TotalSeconds -lt 600)
 if(-not $report.readAccessVerified){throw 'SUPERVISED_LOGIN_TIMEOUT'}
 if($TestCallbackReplay){
  $v=$state.callbackReplay
  if($v.requested -ne $true -or $v.verified -ne $true -or $v.exchangeAttempts -ne 1){throw 'SUPERVISED_REPLAY_VERIFICATION_FAILED'}
  $report.callbackReplay=@{requested=$true;verified=$true;exchangeAttempts=1};Save-SupervisedReport
  Write-Host '[70%] Same callback rejected on repeated handler consumption; exactly one token exchange attempted.'
 }
 $report.status='SUPERVISED_LOGIN_READ_PASSED_QUOTES_PENDING'
 if($TestQuotes){
  $report.stage='QUOTES';$report.quoteSamples=@();Save-SupervisedReport
  $sampleCount=if($TestTransportFailure){2}else{3}
  Write-Host "[80%] Reading $sampleCount NSE EQUITY quote samples, five seconds apart. Diagnostic only; current membership remains unverified."
  for($sample=1;$sample -le $sampleCount;$sample++){
   if($sample -gt 1){Start-Sleep -Seconds 5}
   if($BindReviewIdentity){
    Write-Host "  Resolving server identity and quote $sample (up to 60 seconds)."
    $bound=Invoke-LocalSupervised 'review-quote' @{symbol=$QuoteSymbol}
    if($sample -gt 1 -and $bound.identity -and $report.identityBinding.identity){
     foreach($field in @('symbol','securityId','instrumentId','isin','snapshotId','snapshotDate','providerSha256','constituentSha256')){
      if([string]$bound.identity.$field -cne [string]$report.identityBinding.identity.$field){throw 'SUPERVISED_IDENTITY_CHANGED_DURING_BATCH'}
     }
    }
    $report.identityBinding=$bound;Save-SupervisedReport
    if($bound.status -ne 'IDENTITY_BOUND_FRESH_QUOTE' -or $bound.reviewEligible -ne $true -or $bound.ordersEnabled -ne $false -or $bound.identity.symbol -cne $QuoteSymbol -or $bound.identity.securityId -ne $QuoteSecurityId){
     if($bound.quote){$report.quoteSamples+=$bound.quote;$report.quotesTested=$true;Save-SupervisedReport}
     throw 'SUPERVISED_IDENTITY_QUOTE_NOT_ELIGIBLE'
    }
    $quote=$bound.quote
   }else{$quote=Invoke-LocalSupervised 'quote' @{securityId=$QuoteSecurityId}}
   if($quote.ordersEnabled -ne $false -or $quote.status -cnotmatch '^[A-Z0-9_]{1,100}$'){throw 'SUPERVISED_QUOTE_RESPONSE_INVALID'}
   $report.quoteSamples+= $quote;$report.quotesTested=$true;Save-SupervisedReport
   Write-Host "  Quote $sample/${sampleCount}: $($quote.status)"
   Write-Progress -Activity 'Supervised Paytm login' -PercentComplete (80+5*$sample) -Status "Quote $sample/${sampleCount}: $($quote.status)"
   if($quote.status -notin @('FRESH_QUOTE_OBSERVED','STALE_QUOTE','NO_QUOTE')){throw 'SUPERVISED_QUOTE_REVIEW_REQUIRED'}
  }
  $fresh=@($report.quoteSamples|Where-Object fresh -EQ $true).Count
  if(-not $TestTransportFailure){$report.quoteBatch=Get-PaytmQuoteBatchAssessment -Samples $report.quoteSamples -SecurityId $QuoteSecurityId -RequireFresh:$RequireFreshQuotes}
  Save-SupervisedReport
  if($RequireFreshQuotes -and -not $report.quoteBatch.passed){throw 'SUPERVISED_FRESH_QUOTES_NOT_OBSERVED'}
  $report.status=if($fresh -eq 3 -and $BindReviewIdentity){'SUPERVISED_IDENTITY_BOUND_FRESH_QUOTES_PASSED'}elseif($fresh -eq 3){'SUPERVISED_QUOTE_READ_PASSED_MAPPING_PENDING'}else{'SUPERVISED_QUOTE_CAPTURED_FRESHNESS_PENDING'}
 }
 if($TestTransportFailure){
  $report.stage='TRANSPORT_FAILURE';Save-SupervisedReport
  Write-Host '[95%] Stopping the gateway deliberately; checking transport failure, session lock and subsequent read denial.'
  $result=Test-PaytmTransportFailure -SecurityId $QuoteSecurityId -Request {param($command,$body) Invoke-LocalSupervised $command $body} -StopGateway {Stop-SupervisedGateway} -Checkpoint {param($progress) $report.transportFailure=$progress;Save-SupervisedReport}
  if(-not $result.passed){throw $result.failure}
  $report.status=$result.status;Save-SupervisedReport
 }
 if($TestSessionExpiry){
  $report.stage='AUTHENTICATED_EXPIRY';Save-SupervisedReport
  $result=Test-PaytmAuthenticatedExpiry -SecurityId $QuoteSecurityId -Request {param($command,$body) Invoke-LocalSupervised $command $body} -Checkpoint {param($progress) $report.sessionExpiry=$progress;Save-SupervisedReport}
  if(-not $result.passed){throw $result.failure}
  # Preserve quote freshness status separately from expiry acceptance.
  $report.sessionExpiry=$result;Save-SupervisedReport
 }
 if($TestSessionRestart){
  $report.stage='AUTHENTICATED_RESTART';Save-SupervisedReport
  $result=Test-PaytmAuthenticatedRestart -SecurityId $QuoteSecurityId -Request {param($command,$body) Invoke-LocalSupervised $command $body} -Checkpoint {param($progress) $report.sessionRestart=$progress;Save-SupervisedReport}
  if(-not $result.passed){throw $result.failure}
  $report.sessionRestart=$result;Save-SupervisedReport
 }
}catch{
 $report.status='REVIEW_REQUIRED'
 # Do not retain HTTP bodies, exception dumps, API keys or callback URLs in shareable evidence.
 $report.failure=if($_.Exception.Message -cmatch '^(SUPERVISED|CLOCK_LOGIN)_[A-Z_]+$'){$_.Exception.Message}else{'SUPERVISED_STEP_FAILED'}
}finally{
 if($loginStarted){try{$locked=Invoke-LocalSupervised 'lock';if($locked.status -ne 'LOCKED'){throw 'lock'};$report.cleanup+='APPLICATION_LOCKED'}catch{$report.cleanup+='APPLICATION_LOCK_FAILED'}}
 if($gatewayStarted){try{
  if(-not (Stop-SupervisedGateway)){throw 'cleanup'}
  $report.cleanup+='GATEWAY_STOPPED_DISABLED'
 }catch{$report.cleanup+='GATEWAY_STOP_FAILED'}}
 if($known -and (Test-Path -LiteralPath $known)){Remove-Item -LiteralPath $known -Force}
 $apiKey=$null;$apiSecret=$null;$headers=$null;$reply=$null
 if(@($report.cleanup|Where-Object {$_ -like '*FAILED'}).Count){$report.failure='SUPERVISED_CLEANUP_FAILED';$report.status='REVIEW_REQUIRED'}
 Save-SupervisedReport;Write-Progress -Activity 'Supervised Paytm login' -Completed
 Write-Host "[100%] $($report.status). Result: $path"
}
if($report.failure){throw "Supervised check stopped at $($report.stage): $($report.failure). Report: $path"}
