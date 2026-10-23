#Requires -Version 7.0
[CmdletBinding()]param([Parameter(Mandatory=$true)][string]$PlanEvidencePath,[ValidateSet('Apply','Collect')][string]$Mode='Apply',[string]$RunId,[string]$OutputDirectory='C:\MarketBrainData\Review')
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'PaytmScannerInstall.ps1')
$run=if($Mode -ceq 'Apply'){[guid]::NewGuid().ToString('N')}else{$RunId}
$timer=[Diagnostics.Stopwatch]::StartNew()
$report=[ordered]@{schemaVersion=1;runId=$run;mode=$Mode;status='REVIEW_REQUIRED';acceptedPlan=$null;ownerInstallConfirmed=$false;commandCopied=$false;packageChangeState='NOT_STARTED';observations=$null;failure=$null;elapsedSeconds=0;rebootPerformed=$false;gatewayActivationAuthorized=$false;brokerCredentialsUsed=$false;ordersEnabled=$false}
$null=New-Item -ItemType Directory -Path $OutputDirectory -Force
$path=Join-Path $OutputDirectory ('paytm-scanner-install-'+(Get-Date -Format 'yyyyMMdd-HHmmss')+'-'+[guid]::NewGuid().ToString('N')+'.json')
try{
    if($run -cnotmatch '^[a-f0-9]{32}$'){throw 'SCANNER_INSTALL_COLLECT_RUN_ID_REQUIRED'}
    $report.acceptedPlan=Assert-PaytmScannerPlanAccepted $PlanEvidencePath
    Write-Progress -Activity 'Paytm scanner install and read-only scan' -Status 'Verify scope and owner confirmation' -PercentComplete 10
    Write-Host "[10%] Mode=$Mode; VPS job ID=$run. No repeat of completed 70-package updates."
    if($Mode -ceq 'Apply'){
        Write-Host 'REAL CHANGE: six pinned packages (needrestart plus five Perl dependencies), fresh private same-VPS configuration/package backup, APT index refresh, and new needrestart list-only configuration. No requested service restart, reboot or gateway activation.'
        Write-Host 'Keep the independently tested VNC console available and all other package/configuration jobs idle. Backup is not off-host, a tested restore or full rollback. Package maintainer scripts run as part of installation; this is not a read-only test.'
        if((Read-Host 'Type INSTALL-SCANNER to accept this scope and recovery limitation') -cne 'INSTALL-SCANNER'){throw 'SCANNER_INSTALL_OWNER_CONFIRMATION_REQUIRED'}
        $report.ownerInstallConfirmed=$true
    }else{Write-Host 'COLLECT ONLY: no install, service start or retry.'}
    $null=Read-Host 'In verified marketbrain-admin PuTTY run sudo -v. Return HERE and press Enter when ready'
    $source='';foreach($file in @('InspectPaytmOperations.sh','BackupPaytmMaintenance.sh','PaytmReviewedPackages.sh','UpdatePaytmMaintenance.sh','InspectPaytmMaintenance.sh','InspectPaytmRestart.sh','InspectPaytmScannerPlan.sh','InstallPaytmScanner.sh')){$source+=[IO.File]::ReadAllText((Join-Path $PSScriptRoot "..\linux\$file"))+"`n"}
    Set-Clipboard -Value (New-PaytmScannerInstallPayload $run $source $Mode)
    $report.commandCopied=$true;$report.packageChangeState='UNKNOWN_UNTIL_RECEIPT'
    Write-Progress -Activity 'Paytm scanner install and read-only scan' -Status 'Waiting for VPS receipt' -PercentComplete 30
    Write-Host '[30%] Paste into PuTTY once. No START/STOP input. Detached job; phase shown every 5 seconds. Observation lasts up to 20 minutes without killing dpkg.'
    Write-Host "If disconnected or no final receipt, do NOT repeat Apply. Use Collect with RunId=$run."
    Write-Host "Copy ONLY BEGIN_PAYTM_SCANNER_INSTALL_$run through END_PAYTM_SCANNER_INSTALL_$run including both lines."
    $wait=[Diagnostics.Stopwatch]::StartNew();$null=Read-Host 'After copying that entire block, return HERE and press Enter within 40 minutes'
    if($wait.Elapsed.TotalMinutes -gt 40){throw 'SCANNER_INSTALL_RECEIPT_EXPIRED_USE_COLLECT'}
    $report.observations=Read-PaytmScannerInstallReceipt (Get-Clipboard -Raw) $run
    $report.packageChangeState=$report.observations.packageChangeState
    if(-not $report.observations.installationAndCaptureCompleted){throw 'SCANNER_INSTALL_STAGE_FAILED_REVIEW_NO_RETRY'}
    $report.status=if($report.observations.restartReview.noKnownRestartFindings){'SCANNER_INSTALLED_SCREEN_CLEAR_UNATTENDED_PENDING'}else{'SCANNER_INSTALLED_RESTART_FINDINGS_REVIEW_REQUIRED'}
}catch{
    $report.failure=if($_.Exception.Message -cmatch '^(SCANNER|RESTART|MAINT)_[A-Z_]+$'){$_.Exception.Message}else{'SCANNER_INSTALL_CAPTURE_FAILED_USE_COLLECT_IF_COPIED'}
}finally{
    $timer.Stop();$report.elapsedSeconds=[math]::Round($timer.Elapsed.TotalSeconds,3)
    $stream=[IO.File]::Open($path,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::None)
    try{$bytes=[Text.Encoding]::UTF8.GetBytes(($report|ConvertTo-Json -Depth 15));$stream.Write($bytes,0,$bytes.Length)}finally{$stream.Dispose()}
    Write-Progress -Activity 'Paytm scanner install and read-only scan' -Completed
    Write-Host "[100%] $($report.status); elapsed=$($report.elapsedSeconds)s"
    Write-Host "Share this ONE file: $path"
    Write-Host "VPS job ID: $run. Retain private backup/logs on VPS. No automatic repair, retry, rollback, reboot or gateway activation."
}
if($report.failure){throw $report.failure}
