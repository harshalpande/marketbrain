#Requires -Version 7.0
[CmdletBinding()]param([Parameter(Mandatory=$true)][string]$UpdateEvidencePath,[string]$OutputDirectory='C:\MarketBrainData\Review')
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'PaytmRestartReview.ps1')
$run=[guid]::NewGuid().ToString('N');$timer=[Diagnostics.Stopwatch]::StartNew()
$report=[ordered]@{schemaVersion=1;runId=$run;status='REVIEW_REQUIRED';acceptedUpdate=$null;observations=$null;commandCopied=$false;failure=$null;elapsedSeconds=0;packagesChanged=$false;servicesRestarted=$false;rebootPerformed=$false;gatewayStarted=$false;brokerCredentialsUsed=$false;ordersEnabled=$false}
$null=New-Item -ItemType Directory -Path $OutputDirectory -Force
$path=Join-Path $OutputDirectory ('paytm-restart-review-'+(Get-Date -Format 'yyyyMMdd-HHmmss')+'-'+$run+'.json')
try{
    $report.acceptedUpdate=Assert-PaytmUpdateAccepted $UpdateEvidencePath
    Write-Progress -Activity 'Paytm read-only restart review' -Status 'Preparing observation' -PercentComplete 10
    Write-Host '[10%] Read-only review. No installs, restarts, reboot, reset-failed or gateway activation. Missing scanner remains a finding.'
    $source='';foreach($file in @('InspectPaytmOperations.sh','InspectPaytmMaintenance.sh','PaytmReviewedPackages.sh','InspectPaytmRestart.sh')){$source+=[IO.File]::ReadAllText((Join-Path $PSScriptRoot "..\linux\$file"))+"`n"}
    if((Read-Host 'Keep package/configuration jobs idle. In verified admin PuTTY run sudo -v. Type REVIEW here when ready') -cne 'REVIEW'){throw 'RESTART_OWNER_CONFIRMATION_REQUIRED'}
    Set-Clipboard -Value (New-PaytmRestartPayload $run $source);$report.commandCopied=$true
    Write-Progress -Activity 'Paytm read-only restart review' -Status 'Waiting for VPS receipt' -PercentComplete 30
    Write-Host '[30%] Paste into PuTTY once. No START/STOP prompts. At most 300 seconds plus 5 seconds termination grace; scanner up to 90 seconds.'
    Write-Host "Copy ONLY BEGIN_PAYTM_RESTART_$run through END_PAYTM_RESTART_$run including both lines."
    $wait=[Diagnostics.Stopwatch]::StartNew();$null=Read-Host 'After copying that entire block, return HERE and press Enter within 20 minutes'
    if($wait.Elapsed.TotalMinutes -gt 20){throw 'RESTART_RECEIPT_EXPIRED'}
    $report.observations=Read-PaytmRestartReceipt (Get-Clipboard -Raw) $run
    $report.status=if($report.observations.noKnownRestartFindings){'RESTART_SCREEN_NO_KNOWN_FINDINGS_UNATTENDED_PENDING'}else{'RESTART_REVIEW_CAPTURED_WITH_FINDINGS'}
}catch{
    $report.failure=if($_.Exception.Message -cmatch '^(RESTART|MAINT)_[A-Z_]+$'){$_.Exception.Message}else{'RESTART_CAPTURE_FAILED_REVIEW_REQUIRED'}
}finally{
    $timer.Stop();$report.elapsedSeconds=[math]::Round($timer.Elapsed.TotalSeconds,3)
    $stream=[IO.File]::Open($path,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::None)
    try{$bytes=[Text.Encoding]::UTF8.GetBytes(($report|ConvertTo-Json -Depth 12));$stream.Write($bytes,0,$bytes.Length)}finally{$stream.Dispose()}
    Write-Progress -Activity 'Paytm read-only restart review' -Completed
    Write-Host "[100%] $($report.status); elapsed=$($report.elapsedSeconds)s"
    Write-Host "Share this ONE file: $path"
    Write-Host 'No restart is authorized by this report. Do not rerun package installation or upload private VPS logs.'
}
if($report.failure){throw $report.failure}
