#Requires -Version 7.0
[CmdletBinding()]param([Parameter(Mandatory=$true)][string]$RestartEvidencePath,[string]$OutputDirectory='C:\MarketBrainData\Review')
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'PaytmScannerPlan.ps1')
$run=[guid]::NewGuid().ToString('N');$timer=[Diagnostics.Stopwatch]::StartNew()
$report=[ordered]@{schemaVersion=1;runId=$run;status='REVIEW_REQUIRED';acceptedRestartEvidence=$null;observations=$null;commandCopied=$false;failure=$null;elapsedSeconds=0;packagesChanged=$false;servicesRestarted=$false;rebootPerformed=$false;gatewayStarted=$false;brokerCredentialsUsed=$false;ordersEnabled=$false}
$null=New-Item -ItemType Directory -Path $OutputDirectory -Force
$path=Join-Path $OutputDirectory ('paytm-scanner-plan-'+(Get-Date -Format 'yyyyMMdd-HHmmss')+'-'+$run+'.json')
try{
    $report.acceptedRestartEvidence=Assert-PaytmMissingScannerEvidence $RestartEvidencePath
    Write-Progress -Activity 'Paytm scanner installation preview' -Status 'Preparing read-only preview' -PercentComplete 10
    Write-Host '[10%] Preview only. No install, refresh, download, restart, reboot or gateway activation.'
    $source='';foreach($file in @('InspectPaytmOperations.sh','InspectPaytmMaintenance.sh','PaytmReviewedPackages.sh','InspectPaytmRestart.sh','InspectPaytmScannerPlan.sh')){$source+=[IO.File]::ReadAllText((Join-Path $PSScriptRoot "..\linux\$file"))+"`n"}
    if((Read-Host 'Keep package/configuration jobs idle. In verified admin PuTTY run sudo -v. Type PLAN here when ready') -cne 'PLAN'){throw 'SCANNER_OWNER_CONFIRMATION_REQUIRED'}
    Set-Clipboard -Value (New-PaytmScannerPlanPayload $run $source);$report.commandCopied=$true
    Write-Progress -Activity 'Paytm scanner installation preview' -Status 'Waiting for VPS receipt' -PercentComplete 30
    Write-Host '[30%] Paste into PuTTY once. No START/STOP input. Maximum 420 seconds plus 5 seconds termination grace.'
    Write-Host "Copy ONLY BEGIN_PAYTM_SCANNER_PLAN_$run through END_PAYTM_SCANNER_PLAN_$run including both lines."
    $wait=[Diagnostics.Stopwatch]::StartNew();$null=Read-Host 'After copying that entire block, return HERE and press Enter within 20 minutes'
    if($wait.Elapsed.TotalMinutes -gt 20){throw 'SCANNER_RECEIPT_EXPIRED'}
    $report.observations=Read-PaytmScannerPlan (Get-Clipboard -Raw) $run
    $report.status=if($report.observations.readyForManifestReview){'SCANNER_PLAN_CAPTURED_INSTALL_APPROVAL_PENDING'}else{'SCANNER_PLAN_CAPTURED_WITH_FINDINGS'}
}catch{
    $report.failure=if($_.Exception.Message -cmatch '^(SCANNER|RESTART|MAINT)_[A-Z_]+$'){$_.Exception.Message}else{'SCANNER_CAPTURE_FAILED_REVIEW_REQUIRED'}
}finally{
    $timer.Stop();$report.elapsedSeconds=[math]::Round($timer.Elapsed.TotalSeconds,3)
    $stream=[IO.File]::Open($path,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::None)
    try{$bytes=[Text.Encoding]::UTF8.GetBytes(($report|ConvertTo-Json -Depth 15));$stream.Write($bytes,0,$bytes.Length)}finally{$stream.Dispose()}
    Write-Progress -Activity 'Paytm scanner installation preview' -Completed
    Write-Host "[100%] $($report.status); elapsed=$($report.elapsedSeconds)s"
    Write-Host "Share this ONE file: $path"
    Write-Host 'Installation and restart are NOT authorized. Do not repeat the completed 70-package update.'
}
if($report.failure){throw $report.failure}
