. (Join-Path $PSScriptRoot 'PaytmRestartReview.ps1')
function Assert-PaytmScannerPlanAccepted([string]$Path) {
    $file=Get-Item -LiteralPath $Path
    if($file.PSIsContainer -or $file.Length -gt 30000 -or (Get-FileHash -LiteralPath $file.FullName -Algorithm SHA256).Hash -cne '545290116C8C0D6B3F852A3EE50A405B66B711A6A282BD646B59753FB8A657B2'){throw 'SCANNER_INSTALL_PLAN_MISMATCH'}
    [pscustomobject]@{runId='6b823ad4ebfe4de8b310e4897d7df4d9';sha256='545290116C8C0D6B3F852A3EE50A405B66B711A6A282BD646B59753FB8A657B2';packageCount=6}
}
function New-PaytmScannerInstallPayload([string]$RunId,[string]$Source,[ValidateSet('Apply','Collect')][string]$Mode) {
    if($RunId -cnotmatch '^[a-f0-9]{32}$' -or $Source.Length -gt 90000 -or $Source.Contains('MB_SCANNER_INSTALL') -or $Source.Contains([char]0)){throw 'SCANNER_INSTALL_PAYLOAD_INVALID'}
    $entry=if($Mode -ceq 'Apply'){'si_launch'}else{'si_poll'}
    "sudo -n bash <<'MB_SCANNER_INSTALL'`n"+$Source.Replace("`r",'')+"`n$entry '$RunId'`nMB_SCANNER_INSTALL`n"
}
function Read-PaytmScannerInstallReceipt([string]$Text,[string]$RunId) {
    if($RunId -cnotmatch '^[a-f0-9]{32}$' -or $Text.Length -gt 60000){throw 'SCANNER_INSTALL_RECEIPT_INVALID'}
    $lines=@($Text.Replace("`r",'').Trim().Split("`n"));$fields=[ordered]@{}
    $keys=@('VERSION','RUN_ID','PHASE','EXIT_CODE','INSTALL_ATTEMPTED','POSTCHECKS_PASSED','ORIGINS_VERIFIED','LIST_ONLY_CONFIGURED','REVIEW_B64','FAILURE_CODE','CAPTURE_COMPLETE')
    if($lines.Count -lt 3 -or $lines[0] -cne "BEGIN_PAYTM_SCANNER_INSTALL_$RunId" -or $lines[-1] -cne "END_PAYTM_SCANNER_INSTALL_$RunId"){throw 'SCANNER_INSTALL_CURRENT_BLOCK_REQUIRED'}
    foreach($line in $lines[1..($lines.Count-2)]){
        if($line -cnotmatch '^([A-Z][A-Z0-9_]+)=([A-Za-z0-9+/=_-]{1,54000})$'){throw 'SCANNER_INSTALL_FIELD_INVALID'}
        $key=$Matches[1];$value=$Matches[2]
        if($key -cnotin $keys -or $fields.Contains($key) -or ($key -cne 'REVIEW_B64' -and $value.Length -gt 100)){throw 'SCANNER_INSTALL_DUPLICATE_OR_UNKNOWN'}
        $fields[$key]=$value
    }
    if($fields.Count -ne $keys.Count -or $fields.VERSION -cne '1' -or $fields.RUN_ID -cne $RunId -or $fields.CAPTURE_COMPLETE -cne 'yes'){throw 'SCANNER_INSTALL_INCOMPLETE'}
    if($fields.PHASE -cnotin @('PRECHECK','BACKUP','REFRESH','SIMULATE','DOWNLOAD','INSTALL','POSTCHECK','SCAN','COMPLETE') -or $fields.EXIT_CODE -cnotmatch '^\d{1,3}$'){throw 'SCANNER_INSTALL_STATE_INVALID'}
    foreach($key in @('INSTALL_ATTEMPTED','POSTCHECKS_PASSED','ORIGINS_VERIFIED','LIST_ONLY_CONFIGURED')){if($fields[$key] -cnotin @('yes','no')){throw 'SCANNER_INSTALL_STATE_INVALID'}}
    if($fields.FAILURE_CODE -cnotin @('NONE','STATE_WRITE','GUARD','ARCHITECTURE','TIME_HEALTH','APT_TRUST_CONFIGURATION','BACKUP','INDEX_REFRESH','SIMULATION_FAILED','CANDIDATE_PLAN_CHANGED','EXACT_PLAN_CHANGED','URI_QUERY','ORIGIN_OR_SIZE_REVIEW','DOWNLOAD','PREINSTALL_DRIFT','INSTALL_FAILED_NO_AUTO_REPAIR','POSTCHECK','LIST_ONLY_CONFIG','SCANNER_NOT_AVAILABLE','SCAN_FAILED','SCAN_RECEIPT')){throw 'SCANNER_INSTALL_FAILURE_INVALID'}
    $installed=$fields.POSTCHECKS_PASSED -ceq 'yes' -and $fields.INSTALL_ATTEMPTED -ceq 'yes' -and $fields.ORIGINS_VERIFIED -ceq 'yes' -and $fields.LIST_ONLY_CONFIGURED -ceq 'yes' -and $fields.PHASE -cin @('SCAN','COMPLETE')
    $review=$null
    if($fields.REVIEW_B64 -cne 'NONE'){$review=Read-PaytmRestartReceipt (ConvertFrom-PaytmRestartBase64 $fields.REVIEW_B64) $RunId}
    $completed=$installed -and $fields.PHASE -ceq 'COMPLETE' -and $fields.EXIT_CODE -ceq '0' -and $fields.FAILURE_CODE -ceq 'NONE' -and $null -ne $review
    [pscustomobject]@{fields=$fields;installationVerified=$installed;installationAndCaptureCompleted=$completed;restartReview=$review;packageChangeState=if($installed){'SIX_SCANNER_PACKAGES_VERIFIED'}elseif($fields.INSTALL_ATTEMPTED -ceq 'yes'){'POSSIBLE_PARTIAL_CHANGES_REVIEW_REQUIRED'}else{'INSTALL_NOT_ATTEMPTED'};restartAuthorized=$false;unattendedGatewayApproved=$false}
}
