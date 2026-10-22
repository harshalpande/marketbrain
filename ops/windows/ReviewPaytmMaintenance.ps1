#Requires -Version 7.0
[CmdletBinding()]param([string]$OutputDirectory='C:\MarketBrainData\Review')
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'PaytmMaintenanceReview.ps1')
$run=[guid]::NewGuid().ToString('N');$timer=[Diagnostics.Stopwatch]::StartNew()
$report=[ordered]@{schemaVersion=1;runId=$run;status='REVIEW_REQUIRED';observations=$null;failure=$null;elapsedSeconds=0;packagesChanged=$false;indexesRefreshed=$false;backupCreated=$false;rebootPerformed=$false;gatewayStarted=$false;brokerCredentialsUsed=$false;ordersEnabled=$false;unattendedOperationApproved=$false}
$null=New-Item -ItemType Directory -Path $OutputDirectory -Force
$path=Join-Path $OutputDirectory ('paytm-maintenance-plan-'+(Get-Date -Format 'yyyyMMdd-HHmmss')+'-'+$run+'.json')
try {
    Write-Host '[10%] Read-only maintenance plan. No update, installation, backup, reboot or gateway start.'
    Write-Progress -Activity 'Paytm maintenance plan' -Status 'Preparing bounded command' -PercentComplete 10
    $helpers=[IO.File]::ReadAllText((Join-Path $PSScriptRoot '..\linux\InspectPaytmOperations.sh'))
    $source=[IO.File]::ReadAllText((Join-Path $PSScriptRoot '..\linux\InspectPaytmMaintenance.sh'))
    $payload=New-PaytmMaintenancePayload $run $helpers $source
    if((Read-Host 'Keep package changes/tests idle. In verified admin PuTTY run sudo -v. Type PLAN here when ready') -cne 'PLAN'){throw 'MAINT_OWNER_CONFIRMATION_REQUIRED'}
    Set-Clipboard -Value $payload
    Write-Progress -Activity 'Paytm maintenance plan' -Status 'Waiting for VPS report' -PercentComplete 30
    Write-Host '[30%] Paste the copied command into PuTTY. No START-TEST, STOP or SERVER_READY input. Maximum 240 seconds plus 5 seconds termination grace.'
    Write-Host "Copy ONLY BEGIN_PAYTM_MAINTENANCE_$run through END_PAYTM_MAINTENANCE_$run (including both lines)."
    $wait=[Diagnostics.Stopwatch]::StartNew()
    $null=Read-Host 'After copying that complete block, return to THIS PowerShell and press Enter within 20 minutes'
    if($wait.Elapsed.TotalMinutes -gt 20){throw 'MAINT_RECEIPT_EXPIRED'}
    Write-Host '[80%] Checking current-run receipt, package health, space and exact candidate versions.'
    Write-Progress -Activity 'Paytm maintenance plan' -Status 'Validating receipt' -PercentComplete 80
    $report.observations=Read-PaytmMaintenanceReceipt (Get-Clipboard -Raw) $run
    $report.status=if($report.observations.technicalPreflightPassed){'MAINTENANCE_PLAN_CAPTURED_BACKUP_AND_APPLY_PENDING'}else{'MAINTENANCE_PLAN_CAPTURED_WITH_FINDINGS'}
}catch{
    $report.failure=if($_.Exception.Message -cmatch '^MAINT_[A-Z_]+$'){$_.Exception.Message}else{'MAINT_CAPTURE_FAILED_CHECK_LOCAL_PREREQUISITES'}
}finally{
    $timer.Stop();$report.elapsedSeconds=[math]::Round($timer.Elapsed.TotalSeconds,3)
    $stream=[IO.File]::Open($path,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::None)
    try{$bytes=[Text.Encoding]::UTF8.GetBytes(($report|ConvertTo-Json -Depth 10));$stream.Write($bytes,0,$bytes.Length)}finally{$stream.Dispose()}
    Write-Progress -Activity 'Paytm maintenance plan' -Completed
    Write-Host "[100%] $($report.status); elapsed=$($report.elapsedSeconds)s"
    Write-Host "Share this ONE file: $path"
    Write-Host 'No changes applied. Cached simulation is not an upgrade authorization, verified backup or security audit.'
}
if($report.failure){throw $report.failure}
