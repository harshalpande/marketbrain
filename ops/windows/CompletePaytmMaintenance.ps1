#Requires -Version 7.0
[CmdletBinding()]param(
    [ValidateSet('Before','After')][string]$Mode='Before',
    [string]$ScannerEvidencePath,
    [string]$BeforeEvidencePath,
    [string]$OutputDirectory='C:\MarketBrainData\Review'
)
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'PaytmRebootReview.ps1')
$timer=[Diagnostics.Stopwatch]::StartNew();$run=[guid]::NewGuid().ToString('N');$rebootPayload=$null
$report=[ordered]@{schemaVersion=1;runId=$run;mode=$Mode;status='REVIEW_REQUIRED';acceptedScanner=$null;beforeReceipt=$null;before=$null;after=$null;ownerRebootConfirmed=$false;rebootCommandPrepared=$false;bootChangeObserved=$false;failure=$null;elapsedSeconds=0;packagesChangedByThisScript=$false;gatewayActivationAuthorized=$false;brokerCredentialsUsed=$false;ordersEnabled=$false}
$null=New-Item -ItemType Directory -Path $OutputDirectory -Force
$path=Join-Path $OutputDirectory ('paytm-maintenance-completion-'+(Get-Date -Format 'yyyyMMdd-HHmmss')+'-'+[guid]::NewGuid().ToString('N')+'.json')
try{
    if($Mode -ceq 'Before'){$report.acceptedScanner=Assert-PaytmScannerInstallAccepted $ScannerEvidencePath}
    else{
        $checkpoint=Read-PaytmRebootCheckpoint $BeforeEvidencePath
        $run=$checkpoint.runId;$report.runId=$run;$report.acceptedScanner=$checkpoint.acceptedScanner
        $report.beforeReceipt=$checkpoint.beforeReceipt;$report.before=$checkpoint.before;$report.ownerRebootConfirmed=$true
    }
    Write-Progress -Activity 'Paytm maintenance completion' -Status "$Mode reboot: prepare evidence" -PercentComplete 10
    Write-Host "[10%] $Mode. Observation is read-only. Only Before can prepare a separately confirmed reboot command."
    if($Mode -ceq 'Before'){
        Write-Host 'A VPS reboot will disconnect ALL PuTTY sessions and interrupt ALL VPS workloads. It does not reboot Windows. Keep the gateway stopped and other package/configuration jobs idle.'
        Write-Host 'Recovery limit: existing private same-VPS configuration backup is not an off-host image, tested restore or full rollback. Keep the independently authenticated HosterDaddy VNC console available.'
        if((Read-Host 'Confirm independent VNC login works NOW, all VPS jobs are idle and you accept these recovery limits. Type CONSOLE-READY') -cne 'CONSOLE-READY'){throw 'REBOOT_CONSOLE_CONFIRMATION_REQUIRED'}
    }
    $source='';foreach($file in @('InspectPaytmOperations.sh','BackupPaytmMaintenance.sh','PaytmReviewedPackages.sh','UpdatePaytmMaintenance.sh','InspectPaytmMaintenance.sh','InspectPaytmRestart.sh','InspectPaytmScannerPlan.sh','InstallPaytmScanner.sh','PaytmRebootReview.sh')){$source+=[IO.File]::ReadAllText((Join-Path $PSScriptRoot "..\linux\$file"))+"`n"}
    $null=Read-Host 'In verified marketbrain-admin PuTTY run sudo -v. Return HERE and press Enter when ready'
    $phase=$Mode.ToUpperInvariant()
    Set-Clipboard -Value (New-PaytmRebootPayload $run $source $phase)
    Write-Progress -Activity 'Paytm maintenance completion' -Status 'Waiting for read-only VPS result' -PercentComplete 30
    Write-Host '[30%] Paste into PuTTY once. This command DOES NOT reboot. Wait up to 420 seconds plus 5 seconds grace.'
    Write-Host "Copy ONLY BEGIN_PAYTM_REBOOT_$run through END_PAYTM_REBOOT_$run, including both lines. Do not press Enter here until you have copied the block."
    $wait=[Diagnostics.Stopwatch]::StartNew();$null=Read-Host 'After copying the entire block, return HERE and press Enter within 20 minutes'
    if($wait.Elapsed.TotalMinutes -gt 20){throw 'REBOOT_RECEIPT_EXPIRED'}
    $text=Get-Clipboard -Raw
    $observed=Read-PaytmRebootReceipt $text $run $phase
    if($Mode -ceq 'Before'){
        # Store only validated, bounded receipt; arbitrary clipboard data is never persisted.
        $report.beforeReceipt=$text.Trim();$report.before=$observed
        if(-not $observed.checksPassed){throw 'REBOOT_PRECHECK_FINDINGS_NO_REBOOT'}
        Write-Progress -Activity 'Paytm maintenance completion' -Status 'Awaiting explicit reboot approval' -PercentComplete 70
        Write-Host '[70%] Fresh guards passed. Next command requests ONE normal VPS reboot; PuTTY disconnection is expected. No package installation, gateway enable or trade.'
        Write-Host "Microcode assessment: $($observed.microcodeAssessment). Host microcode is not certified by this guest test."
        if((Read-Host 'If ready for VPS downtime with VNC recovery open, type REBOOT-VPS. Any other answer cancels') -cne 'REBOOT-VPS'){throw 'REBOOT_OWNER_CANCELLED'}
        $report.ownerRebootConfirmed=$true
        $rebootPayload=New-PaytmRebootPayload $run $source REBOOT $observed.fields.BOOT_ID $observed.fields.UTC_EPOCH
        $report.rebootCommandPrepared=$true;$report.status='REBOOT_COMMAND_PREPARED_POSTCHECK_PENDING'
    }else{
        $report.after=$observed
        $report.bootChangeObserved=$observed.fields.BOOT_ID -cne $report.before.fields.BOOT_ID
        if(-not $report.bootChangeObserved){throw 'REBOOT_NOT_OBSERVED_DO_NOT_REPEAT_BLINDLY'}
        if([long]$observed.fields.UTC_EPOCH -le [long]$report.before.fields.UTC_EPOCH){throw 'REBOOT_TIME_ORDER_REVIEW'}
        if(-not $observed.checksPassed){throw 'REBOOT_POSTCHECK_FINDINGS_REVIEW_REQUIRED'}
        $report.status='VPS_REBOOT_VERIFIED_GUEST_SCREEN_CLEAR_UNATTENDED_PENDING'
    }
}catch{
    $rebootPayload=$null
    $report.failure=if($_.Exception.Message -cmatch '^(REBOOT|RESTART|MAINT)_[A-Z_]+$'){$_.Exception.Message}else{'REBOOT_CAPTURE_FAILED_REVIEW_REQUIRED'}
}finally{
    $timer.Stop();$report.elapsedSeconds=[math]::Round($timer.Elapsed.TotalSeconds,3)
    # Persist the checkpoint before a reboot command ever reaches the clipboard.
    $stream=[IO.File]::Open($path,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::None)
    try{$bytes=[Text.Encoding]::UTF8.GetBytes(($report|ConvertTo-Json -Depth 18));$stream.Write($bytes,0,$bytes.Length)}finally{$stream.Dispose()}
    Write-Progress -Activity 'Paytm maintenance completion' -Completed
    Write-Host "[100%] $($report.status); elapsed=$($report.elapsedSeconds)s"
    Write-Host "Evidence/checkpoint: $path"
}
if($report.failure){throw $report.failure}
if($rebootPayload){
    Set-Clipboard -Value $rebootPayload
    Write-Host 'REBOOT COMMAND NOW COPIED. In PuTTY run sudo -v again, then paste once within 20 minutes of the precheck. Expect disconnection. Never repeat if outcome is uncertain.'
    Write-Host 'Reconnect in a NEW verified marketbrain-admin PuTTY session and run sudo -v. If unavailable after 5 minutes, use VNC to inspect; no blind second reboot.'
    Write-Host 'Next run Mode After with this checkpoint. After is read-only and cannot request a reboot, including after a PowerShell interruption.'
}else{Write-Host 'Share this ONE final JSON; it embeds the before/after evidence. Gateway, authentication, quotes and trades remain unapproved.'}
# Allows the full handoff to retain the exact checkpoint path without scanning directories.
Write-Output $path
