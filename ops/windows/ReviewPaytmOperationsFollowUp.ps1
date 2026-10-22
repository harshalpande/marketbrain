#Requires -Version 7.0
[CmdletBinding()]param(
    [Parameter(Mandatory=$true)][string]$OperationsEvidencePath,
    [string]$OutputDirectory='C:\MarketBrainData\Review'
)
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'PaytmOperationsReview.ps1')
. (Join-Path $PSScriptRoot 'PaytmOperationsFollowUp.ps1')
$run=[guid]::NewGuid().ToString('N');$timer=[Diagnostics.Stopwatch]::StartNew()
$report=[ordered]@{schemaVersion=2;runId=$run;startedUtc=[DateTimeOffset]::UtcNow.ToString('o');status='REVIEW_REQUIRED';scope='WINDOWS_RESYNC_AND_VPS_INDEX_REFRESH_ONLY';priorEvidence=$null;windowsTime=$null;observations=$null;failure=$null;elapsedSeconds=0;ownerConfirmedIdle=$false;vpsRefreshCommandPrepared=$false;vpsTimeChanged=$false;packageInstallationRequested=$false;applicationChanged=$false;proxyStarted=$false;brokerCredentialsUsed=$false;ordersEnabled=$false;unattendedOperationApproved=$false}
$null=New-Item -ItemType Directory -Path $OutputDirectory -Force
$path=Join-Path $OutputDirectory ("paytm-operations-followup-{0}-{1}.json" -f (Get-Date -Format 'yyyyMMdd-HHmmss'),$run)
try{
    Write-Progress -Activity 'Paytm operational corrections' -Status 'Prerequisites' -PercentComplete 5
    Write-Host '[5%] Windows resync + VPS package INDEX refresh. No upgrades, reboot, VPS clock changes or broker login.'
    $report.priorEvidence=Assert-PaytmReviewedOperationsReport $OperationsEvidencePath
    if(-not (Test-PaytmOperationsAdministrator)){throw 'OPS_ADMIN_POWERSHELL_REQUIRED'}
    $answer=Read-Host 'Confirm clock-sensitive jobs, approvals and tests are idle. Type SYNC_AND_REFRESH to resync Windows and refresh VPS package indexes'
    if($answer -cne 'SYNC_AND_REFRESH'){throw 'OPS_OWNER_CONFIRMATION_REQUIRED'}
    $report.ownerConfirmedIdle=$true
    Write-Progress -Activity 'Paytm operational corrections' -Status 'Windows clock resynchronization' -PercentComplete 20
    Write-Host '[20%] Querying Windows time, requesting resync using its existing source, then collecting status.'
    $report.windowsTime=Invoke-PaytmWindowsTimeReview
    Write-Host "Windows time: $($report.windowsTime.status). Failures are retained; VPS evidence collection can still continue."
    $report.windowsSshInventory=Get-PaytmWindowsSshInventory
    $source=[IO.File]::ReadAllText((Join-Path $PSScriptRoot '..\linux\InspectPaytmOperations.sh'))
    $payload=New-PaytmOperationsPayload $run $source -RefreshReviewed
    $digest=[Security.Cryptography.SHA256]::Create()
    try{$report.payloadSha256=[BitConverter]::ToString($digest.ComputeHash([Text.Encoding]::UTF8.GetBytes($payload))).Replace('-','')}finally{$digest.Dispose()}
    $null=Read-Host 'In verified marketbrain-admin PuTTY, run sudo -v and enter your sudo password. Return HERE and press Enter'
    # New window AFTER resync; do not compare against a pre-correction Windows timestamp.
    $start=[DateTimeOffset]::UtcNow;$collection=[Diagnostics.Stopwatch]::StartNew()
    Set-Clipboard -Value $payload;$report.vpsRefreshCommandPrepared=$true
    Write-Progress -Activity 'Paytm operational corrections' -Status 'VPS index refresh and snapshot' -PercentComplete 50
    Write-Host '[50%] Paste copied command into PuTTY. No START-TEST or STOP. Refresh has 180-second limit and heartbeat; complete script limit is 420 seconds.'
    Write-Host "Copy ONLY BEGIN_PAYTM_OPERATIONS_$run through END_PAYTM_OPERATIONS_$run when complete."
    $null=Read-Host 'Return HERE and press Enter once that complete block is on the clipboard (within 20 minutes)'
    $received=[DateTimeOffset]::UtcNow;$collection.Stop()
    Write-Progress -Activity 'Paytm operational corrections' -Status 'Validate findings' -PercentComplete 85
    Write-Host '[85%] Checking corrected package identity, refresh result, upgrade candidates and post-resync clock comparison.'
    $report.observations=Read-PaytmOperationsReceipt -Text (Get-Clipboard -Raw) -RunId $run -Started $start -Received $received -ExpectedVersion 2
    $report.collectionMonotonicSeconds=[math]::Round($collection.Elapsed.TotalSeconds,3)
    if([math]::Abs(($received-$start).TotalSeconds-$collection.Elapsed.TotalSeconds) -gt 2){$report.observations.findings+= 'WINDOWS_CLOCK_MOVED_DURING_COLLECTION'}
    if($report.windowsTime.failure){$report.observations.findings+='WINDOWS_TIME_REVIEW_REQUIRED'}
    $report.status=if($report.observations.findings.Count){'FOLLOWUP_CAPTURED_WITH_FINDINGS'}else{'FOLLOWUP_CAPTURED_UNATTENDED_PROVISIONING_PENDING'}
}catch{
    $report.failure=if($_.Exception.Message -cmatch '^OPS_[A-Z_]+$'){$_.Exception.Message}else{'OPS_FOLLOWUP_CAPTURE_FAILED'}
}finally{
    $timer.Stop();$report.elapsedSeconds=[math]::Round($timer.Elapsed.TotalSeconds,3)
    $stream=[IO.File]::Open($path,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::None)
    try{$bytes=[Text.Encoding]::UTF8.GetBytes(($report|ConvertTo-Json -Depth 15));$stream.Write($bytes,0,$bytes.Length)}finally{$stream.Dispose()}
    Write-Progress -Activity 'Paytm operational corrections' -Completed
    Write-Host "[100%] $($report.status); elapsed=$($report.elapsedSeconds)s"
    Write-Host "Share this ONE file: $path"
    Write-Host 'Windows clock/service state may have changed; VPS indexes may have refreshed. No packages installed, broker credentials used or gateway activated by this script.'
}
if($report.failure){throw $report.failure}
