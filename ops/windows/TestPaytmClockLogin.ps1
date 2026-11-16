#Requires -Version 7.0
[CmdletBinding()]param(
 [string]$EvidencePath='C:\MarketBrainData\Review\paytm-clock-key-authorization-8b3fc82ef05a4e9194efea01f7bfb76c.json',
 [string]$PreparationPath='C:\MarketBrainData\Review\paytm-clock-key-preparation-c192c546fbc2470f961341ea21f52266.json',
 [string]$OutputDirectory='C:\MarketBrainData\Review')
$ErrorActionPreference='Stop'
. "$PSScriptRoot/PaytmClockLogin.ps1"
. "$PSScriptRoot/PaytmGatewayKeyCustody.ps1"
$run=[guid]::NewGuid().ToString('N');$watch=[Diagnostics.Stopwatch]::StartNew()
$null=New-Item -ItemType Directory -Path $OutputDirectory -Force
$path=Join-Path $OutputDirectory "paytm-clock-login-$run.json"
$temp=Join-Path ([IO.Path]::GetTempPath()) "marketbrain-clock-login-$run"
$report=[ordered]@{version=1;runId=$run;status='REVIEW_REQUIRED';failure=$null;checks=@();hostPinned=$false;elapsedSeconds=0;ordersEnabled=$false;agentModified=$false;unattendedCustodyTested=$false;sourceHashes=@{}}
function Save-ClockLogin {$report.elapsedSeconds=$watch.Elapsed.TotalSeconds;[IO.File]::WriteAllText($path,($report|ConvertTo-Json -Depth 8))}
try{
 Save-ClockLogin
 if((Get-FileHash -LiteralPath $EvidencePath).Hash -cne 'A4D85CC3D9BF6F88978F5BCE881E5088810E9205B04E4061EB759F9B47543329' -or (Get-FileHash -LiteralPath $PreparationPath).Hash -cne '6DDEB3B0B3DAFC9F67E4D6FFF8DAD671D57860B3ECD944778E489FBE4400D2DE'){throw 'CLOCK_LOGIN_EVIDENCE_MISMATCH'}
 foreach($f in @('PaytmClockLogin.ps1','TestPaytmClockLogin.ps1','PaytmGatewayKeyCustody.ps1')){$report.sourceHashes[$f]=(Get-FileHash -LiteralPath "$PSScriptRoot/$f").Hash}
 $prep=Get-Content -LiteralPath $PreparationPath -Raw|ConvertFrom-Json
 $key=[string]$prep.privateKeyPath
 $verified=Test-PaytmEncryptedKeyFile $key 'AAAAC3NzaC1lZDI1NTE5AAAAIB/0obZcN+dR0yxN6IWDvIsk37mxi6VbQfmlacUR/jk4'
 if(-not $verified.encrypted){throw 'CLOCK_LOGIN_ENCRYPTION_REQUIRED'}
 $bin=Join-Path $env:WINDIR 'System32/OpenSSH'
 Write-Host '[10%] Verify the previously supplied VPS public key against its accepted fingerprint (no keyscan).'
 $hostFile=Join-Path $PSScriptRoot 'paytm-vps-host-rsa.pub'
 $report.sourceHashes['paytm-vps-host-rsa.pub']=(Get-FileHash -LiteralPath $hostFile).Hash
 $pins=ConvertFrom-PaytmHostPublicKey ([IO.File]::ReadAllText($hostFile).Trim())
 $report.checks+=@{stage='hostPin';source='previously supplied public key';fingerprint=$pins.fingerprint};Save-ClockLogin
 $report.hostPinned=$true
 if(Test-Path -LiteralPath $temp){throw 'CLOCK_LOGIN_TEMP_EXISTS'}
 $null=New-Item -ItemType Directory -Path $temp
 $known=Join-Path $temp 'known_hosts';[IO.File]::WriteAllText($known,$pins.knownHost)
 $common=Get-ClockLoginSshArguments $known $key
 for($i=0;$i -lt 3;$i++){
  $allowed=$i -ne 1;$nonce=[guid]::NewGuid().ToString('N')
  $command=if($allowed){"marketbrain-clock $nonce"}else{'marketbrain-clock INVALID'}
  $percent=20+$i*25
  Write-Progress -Activity 'Clock SSH acceptance' -PercentComplete $percent -Status "Request $($i+1)/3"
  Write-Host "[$percent%] Request $($i+1)/3. Enter the CLOCK KEY passphrase if OpenSSH prompts. Input is hidden; allow up to 180 seconds."
  $result=Invoke-ClockLoginNative "$bin/ssh.exe" ($common+@($command)) 180
  $report.checks+=@{stage="request-$i";allowed=$allowed;nonce=$nonce;result=$result};Save-ClockLogin
  $value=Assert-ClockLoginReply $result $nonce $allowed
  if($allowed -and -not $value.ntpSynchronized){throw 'CLOCK_LOGIN_VPS_NTP_UNSYNCHRONIZED'}
 }
 $report.status='CLOCK_SSH_LOGIN_AND_COMMAND_DENIAL_PASSED_CUSTODY_PENDING'
}catch{$report.failure=$_.Exception.Message}finally{
 # Retain the small public known_hosts file for diagnosis; no private material copied.
 Save-ClockLogin;Write-Progress -Activity 'Clock SSH acceptance' -Completed
 Write-Host "[100%] $($report.status)";Write-Host "Share this ONE file: $path"
}
if($report.failure){throw "Clock login failed; share the report: $($report.failure)"}
