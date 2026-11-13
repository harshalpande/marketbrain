#Requires -Version 7.0
[CmdletBinding()]param(
 [string]$RecoveryReportPath='C:\MarketBrainData\Review\paytm-native-recovery-47dc9332f38f4ee293ba6b414b12cc5d.json',
 [string]$OutputDirectory='C:\MarketBrainData\Review')
$ErrorActionPreference='Stop'
foreach($name in @('PaytmGatewayAccount.ps1','PaytmGatewayKeyCustody.ps1','PaytmGatewayScheduledProbe.ps1','PaytmSupervisorHost.ps1','PaytmSupervisorInstallation.ps1','PaytmGatewaySession.ps1','PaytmGatewayFailureEvidence.ps1','PaperRuntimeReview.ps1')){. (Join-Path $PSScriptRoot $name)}
$watch=[Diagnostics.Stopwatch]::StartNew()
$report=[ordered]@{version=1;runId=[guid]::NewGuid().ToString('N');status='REVIEW_REQUIRED';failure=$null;gatewayChanged=$false;taskStarted=$false;credentialsUsed=$false;ordersEnabled=$false;historicalCauseEstablished=$false;sourceHashes=@{};tcpSamples=@()}
$null=Assert-PaytmAccountPath $OutputDirectory
$null=New-Item -ItemType Directory -Path $OutputDirectory -Force
$destination=Join-Path $OutputDirectory ('paytm-recovery-connectivity-'+$report.runId+'.json')
function Connectivity-Step([int]$Percent,[string]$Text){
 Write-Host "[$Percent%] $Text"
 Write-Progress -Activity 'Gateway connectivity evidence' -Status $Text -PercentComplete $Percent
 Write-PaytmSessionReport $destination $report
}
try{
 Assert-PaytmCustodyController
 Import-Module ScheduledTasks
 $null=Assert-PaytmAccountPath $RecoveryReportPath
 $hash=(Get-FileHash -LiteralPath $RecoveryReportPath).Hash
 if($hash -cne 'E3B6BF988350538C98C76046F4B9DEBA8F1C45AA826DA2CED9D523CA6F9F16CE'){throw 'CONNECTIVITY_REVIEWED_REPORT_MISMATCH'}
 $report.reviewedReportSha256=$hash
 foreach($name in @('GetPaytmRecoveryConnectivity.ps1','ReadPaytmConnectivityEvents.ps1','PaytmGatewayFailureEvidence.ps1')){$report.sourceHashes[$name]=(Get-FileHash -LiteralPath (Join-Path $PSScriptRoot $name)).Hash}
 Connectivity-Step 10 'Read saved worker state; no restart or state changes.'
 $report.workerDiagnostics=Get-PaytmWorkerFailureEvidence
 $c=Get-PaytmHostContract
 $manifest=Read-PaytmHostJson (Assert-PaytmAccountPath (Join-Path $c.root 'manifest.json'))
 $report.installedFiles=@()
 foreach($name in @('native.dll','runner.ps1','transport.ps1','transport.dll')){
  $actual=(Get-FileHash -LiteralPath (Assert-PaytmAccountPath (Join-Path $c.root $name))).Hash
  $expected=Get-PaytmEvidenceProperty $manifest.hashes $name
  $report.installedFiles+=@{name=$name;actualSha256=$actual;manifestSha256=$expected;matchesManifest=($actual -ceq $expected)}
 }
 Connectivity-Step 35 'Read bounded historical network and sleep events (up to 45 seconds).'
 $body=[IO.File]::ReadAllText((Join-Path $PSScriptRoot 'ReadPaytmConnectivityEvents.ps1'))
 $encoded=[Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($body))
 $result=Invoke-PaperRuntimeProcess 'C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe' @('-NoLogo','-NoProfile','-NonInteractive','-EncodedCommand',$encoded) (Resolve-Path (Join-Path $PSScriptRoot '../..')).Path 45
 $report.eventQuery=@{exitCode=$result.exitCode;elapsedSeconds=$result.elapsedSeconds;stderrCharacters=$result.stderr.Length}
 if($result.exitCode -eq 0 -and $result.stdout.Length -le 60000){$report.events=$result.stdout|ConvertFrom-Json -ErrorAction Stop}
 else{$report.eventQuery.failure='CONNECTIVITY_EVENT_QUERY_FAILED_OR_OVERSIZE'}
 for($index=1;$index -le 3;$index++){
  Connectivity-Step (55+$index*10) "TCP connection sample $index/3 to VPS port 22; no SSH authentication."
  $sample=[ordered]@{observedUtc=[DateTime]::UtcNow.ToString('o');identityScope='CONTROLLER_NOT_GATEWAY_ACCOUNT';connected=$false;timedOut=$false;socketError=$null;elapsedMilliseconds=0}
  $client=[Net.Sockets.TcpClient]::new();$timer=[Diagnostics.Stopwatch]::StartNew()
  try{
   $pending=$client.ConnectAsync('130.250.191.137',22)
   if(-not $pending.Wait(5000)){$sample.timedOut=$true}else{$sample.connected=$client.Connected}
  }catch{
   $base=$_.Exception.GetBaseException()
   $sample.socketError=if($base -is [Net.Sockets.SocketException]){[string]$base.SocketErrorCode}else{$base.GetType().Name}
  }finally{$client.Dispose();$sample.elapsedMilliseconds=$timer.ElapsedMilliseconds}
  $report.tcpSamples+=[pscustomobject]$sample
  if($index -lt 3){Start-Sleep -Seconds 2}
 }
 $report.status='CONNECTIVITY_EVIDENCE_CAPTURED_REVIEW_REQUIRED'
}catch{
 $report.failure=if($_.Exception.Message -cmatch '^(CONNECTIVITY|HOST|KEY|ACCOUNT)_[A-Z_]+$'){$_.Exception.Message}else{'CONNECTIVITY_COLLECTION_FAILED'}
 $report.failureType=$_.Exception.GetBaseException().GetType().Name
}finally{
 $report.elapsedSeconds=[math]::Round($watch.Elapsed.TotalSeconds,3)
 Write-PaytmSessionReport $destination $report
 Write-Progress -Activity 'Gateway connectivity evidence' -Completed
 Write-Host "[100%] $($report.status); elapsed=$($report.elapsedSeconds)s"
 Write-Host "Share this ONE file: $destination"
}
if($report.failure){throw 'Connectivity collection incomplete. Share the JSON; do not restart the gateway.'}
