#Requires -Version 7.0
[CmdletBinding()]param([string]$OutputDirectory='C:\MarketBrainData\Review')
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'PaytmGatewayKeyCustody.ps1')
. (Join-Path $PSScriptRoot 'PaytmTunnelVerification.ps1')
$run=[guid]::NewGuid().ToString('N');$timer=[Diagnostics.Stopwatch]::StartNew();$stream=$null
$c=Get-PaytmKeyContract
$report=[ordered]@{schemaVersion=1;runId=$run;observedUtc=[DateTime]::UtcNow.ToString('o');
    status='REVIEW_REQUIRED';failure=$null;sourceHashes=[ordered]@{};clientVersion=$null;hostScan=$null;
    expectedHost=$c.hostAddress;expectedFingerprint=$c.hostPin;observedFingerprint=$null;
    hostPinVerified=$false;networkAttempted=$false;elapsedSeconds=0;
    keyRead=$false;keyImported=$false;accountChanged=$false;serviceChanged=$false;
    authenticated=$false;tunnelStarted=$false;brokerCredentialsUsed=$false;ordersEnabled=$false}
function Save-HostScanReport {
    $report.elapsedSeconds=[math]::Round($timer.Elapsed.TotalSeconds,3)
    $data=[Text.Encoding]::UTF8.GetBytes(($report|ConvertTo-Json -Depth 8))
    $stream.Position=0;$stream.SetLength(0);$stream.Write($data,0,$data.Length);$stream.Flush($true)
}
$null=New-Item -ItemType Directory -Path $OutputDirectory -Force
$path=Join-Path $OutputDirectory ('paytm-host-scan-'+(Get-Date -Format 'yyyyMMdd-HHmmss')+'-'+$run+'.json')
try {
    $stream=[IO.File]::Open($path,'CreateNew','Write','Read');Save-HostScanReport
    foreach($name in @('GetPaytmHostScanDiagnostic.ps1','PaytmGatewayKeyCustody.ps1','PaytmTunnelVerification.ps1')){
        $report.sourceHashes[$name]=(Get-FileHash -LiteralPath (Join-Path $PSScriptRoot $name)).Hash
    }
    Write-Host '[10%] Reading Windows OpenSSH version; no passwords or private keys needed.'
    Write-Progress -Activity 'VPS public host-key diagnostic' -Status 'Client version' -PercentComplete 10
    $report.clientVersion=Get-PaytmHostScanEvidence (Invoke-PaytmCustodyNative 'ssh.exe' @('-V') 5)
    Save-HostScanReport
    Write-Host '[40%] One bounded public RSA host-key scan of 130.250.191.137:22 (10-second process limit).'
    Write-Progress -Activity 'VPS public host-key diagnostic' -Status 'Public host-key scan' -PercentComplete 40
    $report.networkAttempted=$true;Save-HostScanReport
    $scan=Invoke-PaytmCustodyNative 'ssh-keyscan.exe' @('-v','-4','-T','5','-t','rsa',$c.hostAddress) 10
    $report.hostScan=Get-PaytmHostScanEvidence $scan;Save-HostScanReport
    if($scan.StoppedByRunner -or $scan.ExitCode -ne 0){throw 'KEY_HOST_SCAN_FAILED'}
    $pins=ConvertTo-PaytmPinnedHost $scan.Stdout
    $report.observedFingerprint=$pins.fingerprint;$report.hostPinVerified=$true
    $report.status='HOST_SCAN_PIN_VERIFIED_KEY_IMPORT_NOT_RUN'
} catch {
    $report.failure=if($_.Exception.Message -cmatch '^KEY_[A-Z_]+$'){$_.Exception.Message}else{'HOST_SCAN_DIAGNOSTIC_FAILED'}
    $base=$_.Exception.GetBaseException()
    $report['failureDetails']=[pscustomobject]@{type=$base.GetType().Name;line=$_.InvocationInfo.ScriptLineNumber;
        nativeError=if($base -is [ComponentModel.Win32Exception]){$base.NativeErrorCode}else{$null}}
} finally {
    $timer.Stop();if($null -ne $stream){try{Save-HostScanReport}finally{$stream.Dispose()}}
    Write-Progress -Activity 'VPS public host-key diagnostic' -Completed
    Write-Host "[100%] $($report.status); elapsed=$($report.elapsedSeconds)s"
    Write-Host "Share this ONE file: $path"
    Write-Host 'No key import or account/service changes. G2 remains 40%; review this report before running custody again.'
}
# A failed scan is the diagnostic result, not an instruction to retry or weaken the pin.
