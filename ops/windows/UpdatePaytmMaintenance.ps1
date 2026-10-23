#Requires -Version 7.0
[CmdletBinding()]param([Parameter(Mandatory=$true)][string]$BackupEvidencePath,[string]$PlanEvidencePath,[string]$FailureEvidencePath,[ValidateSet('Apply','Collect')][string]$Mode='Apply',[string]$RunId,[string]$OutputDirectory='C:\MarketBrainData\Review')
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'PaytmMaintenanceUpdate.ps1')
$timer=[Diagnostics.Stopwatch]::StartNew()
$run=if($Mode -ceq 'Apply'){[guid]::NewGuid().ToString('N')}else{$RunId}
$report=[ordered]@{schemaVersion=1;runId=$run;mode=$Mode;status='REVIEW_REQUIRED';acceptedBackup=$null;retryEvidence=$null;ownerUpdateConfirmed=$false;commandCopied=$false;packageChangeState='NOT_STARTED';observations=$null;freshAdminLoginOwnerConfirmed=$false;failure=$null;elapsedSeconds=0;rebootPerformed=$false;brokerCredentialsUsed=$false;ordersEnabled=$false;unattendedGatewayApproved=$false}
$null=New-Item -ItemType Directory -Path $OutputDirectory -Force
$path=Join-Path $OutputDirectory ('paytm-maintenance-update-'+(Get-Date -Format 'yyyyMMdd-HHmmss')+'-'+[guid]::NewGuid().ToString('N')+'.json')
try {
    if($run -cnotmatch '^[a-f0-9]{32}$'){throw 'UPDATE_VALID_RUN_ID_REQUIRED_FOR_COLLECT'}
    $report.acceptedBackup=Assert-PaytmAcceptedBackup $BackupEvidencePath
    if($Mode -ceq 'Apply'){$report.retryEvidence=Assert-PaytmRetryEvidence $PlanEvidencePath $FailureEvidencePath}
    Write-Progress -Activity 'Paytm reviewed maintenance' -Status 'Validate owner and backup' -PercentComplete 10
    Write-Host "[10%] Mode=$Mode; VPS job ID=$run. No broker access or automatic reboot."
    if($Mode -ceq 'Apply'){
        Write-Host 'REVIEWED RETRY r2: only tzdata target changes to 2026e-0+deb13u1. Prior failed job must be stopped with installation-not-attempted evidence. Old staging is preserved; new staging cannot be overwritten.'
        Write-Host 'REAL VPS UPDATE: exactly 70 reviewed packages only. Existing configuration files retained where supported; package scripts may restart affected services. Keep browser/VNC console available. The accepted backup is same-VPS configuration only, not full-system/off-host rollback.'
        if((Read-Host 'Keep all other package/configuration jobs idle. Type UPDATE-REVIEWED-PACKAGES to accept that scope and recovery limitation') -cne 'UPDATE-REVIEWED-PACKAGES'){throw 'UPDATE_OWNER_CONFIRMATION_REQUIRED'}
        $report.ownerUpdateConfirmed=$true
    }else{Write-Host 'COLLECT ONLY: no new installation, retry or service start.'}
    $null=Read-Host 'In verified marketbrain-admin PuTTY run sudo -v. Return HERE and press Enter once ready'
    $source=''
    foreach($name in @('InspectPaytmOperations.sh','BackupPaytmMaintenance.sh','PaytmReviewedPackages.sh','UpdatePaytmMaintenance.sh')){
        $source += [IO.File]::ReadAllText((Join-Path $PSScriptRoot ("..\linux\$name")))+"`n"
    }
    Set-Clipboard -Value (New-PaytmUpdatePayload $run $source $Mode)
    $report.commandCopied=$true;$report.packageChangeState='UNKNOWN_UNTIL_RECEIPT'
    Write-Progress -Activity 'Paytm reviewed maintenance' -Status 'Waiting for VPS job receipt' -PercentComplete 30
    Write-Host '[30%] Paste into PuTTY. No START/STOP input. Phases print every 5 seconds. The job is launched independently of SSH; observation stops after 20 minutes without killing installation.'
    Write-Host "If disconnected or no final receipt, do NOT rerun Apply. Use Collect with RunId=$run."
    Write-Host "Copy ONLY BEGIN_PAYTM_UPDATE_$run through END_PAYTM_UPDATE_$run, including both lines."
    $wait=[Diagnostics.Stopwatch]::StartNew()
    $null=Read-Host 'After copying the complete block, return HERE and press Enter within 40 minutes'
    if($wait.Elapsed.TotalMinutes -gt 40){throw 'UPDATE_RECEIPT_EXPIRED_USE_COLLECT'}
    $report.observations=Read-PaytmUpdateReceipt (Get-Clipboard -Raw) $run
    $report.packageChangeState=$report.observations.packageChangeState
    if(-not $report.observations.updatePostchecksPassed){throw 'UPDATE_STAGE_FAILED_REVIEW_PHASE_NO_RETRY'}
    Write-Progress -Activity 'Paytm reviewed maintenance' -Status 'Fresh administrator login check' -PercentComplete 90
    Write-Host '[90%] Open a NEW PuTTY session with the existing admin key and verified host pin. Run whoami and sudo whoami; expect marketbrain-admin then root. Keep the old session open.'
    $report.freshAdminLoginOwnerConfirmed=((Read-Host 'Type FRESH-LOGIN-OK only after both checks succeed; otherwise type NOT-VERIFIED') -ceq 'FRESH-LOGIN-OK')
    $report.status=if($report.freshAdminLoginOwnerConfirmed){'REVIEWED_UPDATES_VERIFIED_RESTART_REVIEW_PENDING'}else{'UPDATES_POSTCHECKED_FRESH_LOGIN_PENDING'}
}catch{
    $report.failure=if($_.Exception.Message -cmatch '^UPDATE_[A-Z_]+$'){$_.Exception.Message}else{'UPDATE_CAPTURE_FAILED_USE_COLLECT_IF_COMMAND_WAS_COPIED'}
}finally{
    $timer.Stop();$report.elapsedSeconds=[math]::Round($timer.Elapsed.TotalSeconds,3)
    $stream=[IO.File]::Open($path,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::None)
    try{$bytes=[Text.Encoding]::UTF8.GetBytes(($report|ConvertTo-Json -Depth 10));$stream.Write($bytes,0,$bytes.Length)}finally{$stream.Dispose()}
    Write-Progress -Activity 'Paytm reviewed maintenance' -Completed
    Write-Host "[100%] $($report.status); elapsed=$($report.elapsedSeconds)s"
    Write-Host "Share this ONE JSON: $path"
    Write-Host "VPS job ID: $run. Do not share private.log/archive. No automatic retry, package repair, reboot or rollback."
}
if($report.failure){throw $report.failure}
