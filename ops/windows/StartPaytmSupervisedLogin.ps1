#Requires -Version 7.2
#Requires -RunAsAdministrator
[CmdletBinding()]param(
 [switch]$TestQuotes,
 [ValidatePattern('^[A-Z0-9][A-Z0-9&-]{0,29}$')][string]$QuoteSymbol,
 [ValidateRange(1,99999999)][int]$QuoteSecurityId=3456,
 [string]$ClockKeyPath,
 [string]$OutputDirectory='C:\MarketBrainData\Review')
$ErrorActionPreference='Stop'
. "$PSScriptRoot/PaytmClockLogin.ps1"
. "$PSScriptRoot/PaytmGatewayKeyCustody.ps1"
. "$PSScriptRoot/PaytmQuoteMapping.ps1"
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
function Invoke-LocalSupervised([string]$Command,$Body=$null) {
 $p=@{Uri="http://127.0.0.1:8080/api/v1/paytm/supervised/$Command";Method='Post';Headers=$headers;NoProxy=$true;TimeoutSec=40}
 if($null -ne $Body){$p.ContentType='application/json';$p.Body=($Body|ConvertTo-Json -Compress)}
 Invoke-RestMethod @p
}
try {
 Save-SupervisedReport
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
 do {
  Start-Sleep -Seconds 1
  $v=Get-Content "$gatewayWork/status.json" -Raw|ConvertFrom-Json
  if($v.instanceId -ne $previous -and $v.phase -eq 'BLOCKED'){throw 'SUPERVISED_GATEWAY_BLOCKED'}
  if($v.instanceId -ne $previous -and $v.phase -eq 'TRANSPORT_READY' -and $v.ordersEnabled -eq $false){$ready=$true;break}
  Write-Progress -Activity 'Supervised Paytm login' -PercentComplete 20 -Status "Starting gateway: $([int]$wait.Elapsed.TotalSeconds)/60 seconds"
 }while($wait.Elapsed.TotalSeconds -lt 60)
 if(-not $ready){throw 'SUPERVISED_GATEWAY_TIMEOUT'}
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
 $start=Invoke-LocalSupervised 'start' @{apiKey=$apiKey;apiSecret=$apiSecret;vpsEpochMilliseconds=$clock.epochMilliseconds}
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
 $report.status='SUPERVISED_LOGIN_READ_PASSED_QUOTES_PENDING'
 if($TestQuotes){
  $report.stage='QUOTES';$report.quoteSamples=@();Save-SupervisedReport
  Write-Host '[80%] Reading three NSE EQUITY quote samples, five seconds apart. Diagnostic only; local universe integration remains pending.'
  for($sample=1;$sample -le 3;$sample++){
   if($sample -gt 1){Start-Sleep -Seconds 5}
   $quote=Invoke-LocalSupervised 'quote' @{securityId=$QuoteSecurityId}
   if($quote.ordersEnabled -ne $false -or $quote.status -cnotmatch '^[A-Z0-9_]{1,100}$'){throw 'SUPERVISED_QUOTE_RESPONSE_INVALID'}
   $report.quoteSamples+= $quote;$report.quotesTested=$true;Save-SupervisedReport
   Write-Host "  Quote $sample/3: $($quote.status)"
   Write-Progress -Activity 'Supervised Paytm login' -PercentComplete (80+5*$sample) -Status "Quote $sample/3: $($quote.status)"
   if($quote.status -notin @('FRESH_QUOTE_OBSERVED','STALE_QUOTE','NO_QUOTE')){throw 'SUPERVISED_QUOTE_REVIEW_REQUIRED'}
  }
  $fresh=@($report.quoteSamples|Where-Object fresh -EQ $true).Count
  $report.status=if($fresh -eq 3){'SUPERVISED_QUOTE_READ_PASSED_MAPPING_PENDING'}else{'SUPERVISED_QUOTE_CAPTURED_FRESHNESS_PENDING'}
 }
}catch{
 $report.status='REVIEW_REQUIRED'
 # Do not retain HTTP bodies, exception dumps, API keys or callback URLs in shareable evidence.
 $report.failure=if($_.Exception.Message -cmatch '^(SUPERVISED|CLOCK_LOGIN)_[A-Z_]+$'){$_.Exception.Message}else{'SUPERVISED_STEP_FAILED'}
}finally{
 if($loginStarted){try{$locked=Invoke-LocalSupervised 'lock';if($locked.status -ne 'LOCKED'){throw 'lock'};$report.cleanup+='APPLICATION_LOCKED'}catch{$report.cleanup+='APPLICATION_LOCK_FAILED'}}
 if($gatewayStarted){try{
  Stop-ScheduledTask -TaskName $taskName;$null=Disable-ScheduledTask -TaskName $taskName
  $stop=[Diagnostics.Stopwatch]::StartNew()
  do{
   $listeners=@([Net.NetworkInformation.IPGlobalProperties]::GetIPGlobalProperties().GetActiveTcpListeners()|Where-Object Port -EQ 18889)
   if((Get-ScheduledTask -TaskName $taskName).State -eq 'Disabled' -and -not $listeners.Count){break}
   Start-Sleep -Seconds 1
  }while($stop.Elapsed.TotalSeconds -lt 30)
  if($listeners.Count -or (Get-ScheduledTask -TaskName $taskName).State -ne 'Disabled'){throw 'cleanup'}
  $report.cleanup+='GATEWAY_STOPPED_DISABLED'
 }catch{$report.cleanup+='GATEWAY_STOP_FAILED'}}
 if($known -and (Test-Path -LiteralPath $known)){Remove-Item -LiteralPath $known -Force}
 $apiKey=$null;$apiSecret=$null;$headers=$null;$reply=$null
 if(@($report.cleanup|Where-Object {$_ -like '*FAILED'}).Count){$report.failure='SUPERVISED_CLEANUP_FAILED';$report.status='REVIEW_REQUIRED'}
 Save-SupervisedReport;Write-Progress -Activity 'Supervised Paytm login' -Completed
 Write-Host "[100%] $($report.status). Result: $path"
}
if($report.failure){throw "Supervised check stopped at $($report.stage): $($report.failure). Report: $path"}
