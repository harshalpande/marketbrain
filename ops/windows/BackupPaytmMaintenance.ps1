#Requires -Version 7.0
[CmdletBinding()]param([Parameter(Mandatory=$true)][string]$MaintenanceEvidencePath,[string]$OutputDirectory='C:\MarketBrainData\Review')
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'PaytmMaintenanceBackup.ps1')
$run=[guid]::NewGuid().ToString('N');$timer=[Diagnostics.Stopwatch]::StartNew()
$report=[ordered]@{schemaVersion=1;runId=$run;status='REVIEW_REQUIRED';acceptedMaintenance=$null;consoleLoginOwnerConfirmed=$false;backupOwnerConfirmed=$false;commandCopied=$false;backupState='NOT_STARTED';observations=$null;failure=$null;elapsedSeconds=0;packagesChanged=$false;rebootPerformed=$false;gatewayStarted=$false;brokerCredentialsUsed=$false;ordersEnabled=$false;upgradeAuthorized=$false}
$null=New-Item -ItemType Directory -Path $OutputDirectory -Force
$path=Join-Path $OutputDirectory ('paytm-maintenance-backup-'+(Get-Date -Format 'yyyyMMdd-HHmmss')+'-'+$run+'.json')
try {
    Write-Host '[10%] Private VPS configuration/package backup only. No updates, restart, extraction or reboot.'
    Write-Progress -Activity 'Paytm maintenance backup' -Status 'Validate reviewed evidence' -PercentComplete 10
    $report.acceptedMaintenance=Assert-PaytmAcceptedMaintenance $MaintenanceEvidencePath
    if((Read-Host 'First log in through HosterDaddy browser/VNC independently of PuTTY. Type CONSOLE-LOGIN-OK only after success') -cne 'CONSOLE-LOGIN-OK'){throw 'BACKUP_CONSOLE_CONFIRMATION_REQUIRED'}
    $report.consoleLoginOwnerConfirmed=$true
    Write-Host 'Archive contains sensitive /etc configuration, package records and admin .ssh files. It remains root-only ON THE VPS, not in this report. Do not share/archive-upload it. This is not a full-system or off-host backup.'
    if((Read-Host 'Keep configuration/package jobs idle; in verified admin PuTTY run sudo -v. Type CREATE-PRIVATE-BACKUP here to authorize only this backup') -cne 'CREATE-PRIVATE-BACKUP'){throw 'BACKUP_OWNER_CONFIRMATION_REQUIRED'}
    $report.backupOwnerConfirmed=$true
    $helpers=[IO.File]::ReadAllText((Join-Path $PSScriptRoot '..\linux\InspectPaytmOperations.sh'))
    $source=[IO.File]::ReadAllText((Join-Path $PSScriptRoot '..\linux\BackupPaytmMaintenance.sh'))
    Set-Clipboard -Value (New-PaytmBackupPayload $run $helpers $source)
    $report.commandCopied=$true;$report.backupState='UNKNOWN_UNTIL_RECEIPT'
    Write-Host '[30%] Paste the copied command in PuTTY. No interactive VPS prompts. Maximum600 seconds plus10 seconds termination grace. Do not close PuTTY.'
    Write-Progress -Activity 'Paytm maintenance backup' -Status 'Waiting for VPS archive verification' -PercentComplete 30
    Write-Host "Copy ONLY BEGIN_PAYTM_BACKUP_$run through END_PAYTM_BACKUP_$run, including both lines."
    $wait=[Diagnostics.Stopwatch]::StartNew()
    $null=Read-Host 'After copying the complete block, return HERE and press Enter within20minutes'
    if($wait.Elapsed.TotalMinutes -gt 20){throw 'BACKUP_RECEIPT_EXPIRED'}
    Write-Progress -Activity 'Paytm maintenance backup' -Status 'Validate safe report' -PercentComplete 80
    Write-Host '[80%] Validate archive comparison, digest and unchanged package status; no archive contents are read here.'
    $report.observations=Read-PaytmBackupReceipt (Get-Clipboard -Raw) $run
    $report.backupState=if($report.observations.archiveComparisonPassed){'LOCAL_ARCHIVE_COMPARED'}elseif($report.observations.fields.DIRECTORY_CREATED -ceq 'yes'){'PARTIAL_PRIVATE_FILES_RETAINED'}else{'NOT_CREATED'}
    if(-not $report.observations.archiveComparisonPassed){throw 'BACKUP_VPS_STAGE_FAILED_REVIEW_PHASE'}
    $report.status='PRIVATE_BACKUP_COMPARED_UPDATE_AND_RECOVERY_REVIEW_PENDING'
}catch{
    $report.failure=if($_.Exception.Message -cmatch '^BACKUP_[A-Z_]+$'){$_.Exception.Message}else{'BACKUP_COLLECTION_FAILED_CHECK_LOCAL_PREREQUISITES'}
}finally{
    $timer.Stop();$report.elapsedSeconds=[math]::Round($timer.Elapsed.TotalSeconds,3)
    $stream=[IO.File]::Open($path,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::None)
    try{$bytes=[Text.Encoding]::UTF8.GetBytes(($report|ConvertTo-Json -Depth 10));$stream.Write($bytes,0,$bytes.Length)}finally{$stream.Dispose()}
    Write-Progress -Activity 'Paytm maintenance backup' -Completed
    Write-Host "[100%] $($report.status); elapsed=$($report.elapsedSeconds)s"
    Write-Host "Share this ONE JSON file: $path"
    Write-Host 'Never share configuration.tar, package files or private.log. Partial VPS files are retained; no automatic cleanup or update.'
}
if($report.failure){throw $report.failure}
