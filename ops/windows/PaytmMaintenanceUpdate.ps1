function Assert-PaytmAcceptedBackup([string]$Path) {
    $file=Get-Item -LiteralPath $Path
    if($file.PSIsContainer -or $file.Length -gt 20000){throw 'UPDATE_BACKUP_EVIDENCE_INVALID'}
    $hash=(Get-FileHash -LiteralPath $file.FullName -Algorithm SHA256).Hash
    if($hash -cne 'DA176C0DA7B3890C7FE41CF249CFE804EDA2BE7109905472FE03E6CB8E5B5CBE'){throw 'UPDATE_BACKUP_EVIDENCE_HASH_MISMATCH'}
    [pscustomobject]@{runId='897a81468f7d4ac0ba034fc15797b6fa';sha256=$hash}
}
function Assert-PaytmRetryEvidence([string]$PlanPath,[string]$FailurePath) {
    if([string]::IsNullOrWhiteSpace($PlanPath) -or [string]::IsNullOrWhiteSpace($FailurePath)){throw 'UPDATE_RETRY_EVIDENCE_REQUIRED'}
    foreach($item in @(@($PlanPath,'5791623DAC303E150B4BF15AD27442DBAEA03584CDD54B097544D36416C4FB43'),@($FailurePath,'84C8828053A8F9C2256E750313A72E91CE97E7F413C5F177B209ECE7DAC1FB45'))){
        $file=Get-Item -LiteralPath $item[0]
        if($file.PSIsContainer -or $file.Length -gt 50000 -or (Get-FileHash -LiteralPath $file.FullName -Algorithm SHA256).Hash -cne $item[1]){throw 'UPDATE_RETRY_EVIDENCE_MISMATCH'}
    }
    [pscustomobject]@{revision=2;planRunId='146a8aba4cdf47c08e356010016eb462';priorRunId='7fb461f8bff74ee0bb15a5afed8c49bc';targetTzdata='2026e-0+deb13u1'}
}
function New-PaytmUpdatePayload([string]$RunId,[string]$Source,[ValidateSet('Apply','Collect')][string]$Mode) {
    if($RunId -cnotmatch '^[a-f0-9]{32}$' -or $Source.Length -gt 50000 -or $Source.Contains('MB_REVIEWED_UPDATE') -or $Source.Contains([char]0)){throw 'UPDATE_PAYLOAD_INVALID'}
    $entry=if($Mode -ceq 'Apply'){'mu_launch'}else{'mu_poll'}
    "sudo -n bash <<'MB_REVIEWED_UPDATE'`n"+$Source.Replace("`r",'')+"`n$entry '$RunId'`nMB_REVIEWED_UPDATE`n"
}
function Read-PaytmUpdateReceipt([string]$Text,[string]$RunId) {
    if($RunId -cnotmatch '^[a-f0-9]{32}$' -or $Text.Length -gt 2000){throw 'UPDATE_RECEIPT_INVALID'}
    $lines=@($Text.Replace("`r",'').Trim().Split("`n"))
    if($lines.Count -lt 3 -or $lines[0] -cne "BEGIN_PAYTM_UPDATE_$RunId" -or $lines[-1] -cne "END_PAYTM_UPDATE_$RunId"){throw 'UPDATE_CURRENT_BLOCK_REQUIRED'}
    $expected=@('VERSION','RUN_ID','PHASE','EXIT_CODE','INSTALL_ATTEMPTED','POSTCHECKS_PASSED','REBOOT_MARKER','FAILURE_CODE','CAPTURE_COMPLETE');$fields=[ordered]@{}
    foreach($line in $lines[1..($lines.Count-2)]){
        if($line -cnotmatch '^([A-Z_]+)=([A-Za-z0-9_]{1,64})$'){throw 'UPDATE_FIELD_INVALID'}
        $key=$Matches[1];$value=$Matches[2]
        if($key -cnotin $expected -or $fields.Contains($key)){throw 'UPDATE_FIELD_DUPLICATE_OR_UNKNOWN'}
        $fields[$key]=$value
    }
    if($fields.Count -ne $expected.Count -or $fields.VERSION -cne '1' -or $fields.RUN_ID -cne $RunId -or $fields.CAPTURE_COMPLETE -cne 'yes'){throw 'UPDATE_INCOMPLETE'}
    if($fields.PHASE -cnotin @('PRECHECK','REFRESH','SIMULATE','DOWNLOAD','INSTALL','POSTCHECK','COMPLETE') -or $fields.EXIT_CODE -cnotmatch '^\d{1,3}$' -or $fields.REBOOT_MARKER -cnotin @('UNKNOWN','ABSENT','PRESENT')){throw 'UPDATE_STATE_INVALID'}
    foreach($key in @('INSTALL_ATTEMPTED','POSTCHECKS_PASSED')){if($fields[$key] -cnotin @('yes','no')){throw 'UPDATE_STATE_INVALID'}}
    if($fields.FAILURE_CODE -cnotin @('NONE','GUARD','PRIOR_RUN_NOT_SAFE','BACKUP_HASH','BACKUP_SOURCE_DRIFT','INSTALLED_VERSION_DRIFT','INDEX_REFRESH','UPGRADE_SIMULATION_FAILED','EXACT_SIMULATION_FAILED','UPGRADE_PLAN_CHANGED','EXACT_PLAN_CHANGED','DOWNLOAD','PREINSTALL_DRIFT','INSTALL_FAILED_NO_AUTO_REPAIR','POSTCHECK','TIME_HEALTH')){throw 'UPDATE_STATE_INVALID'}
    $passed=$fields.PHASE -ceq 'COMPLETE' -and $fields.EXIT_CODE -ceq '0' -and $fields.INSTALL_ATTEMPTED -ceq 'yes' -and $fields.POSTCHECKS_PASSED -ceq 'yes' -and $fields.REBOOT_MARKER -cne 'UNKNOWN' -and $fields.FAILURE_CODE -ceq 'NONE'
    [pscustomobject]@{fields=$fields;updatePostchecksPassed=$passed;packageChangeState=if($passed){'REVIEWED_TARGET_VERSIONS_VERIFIED'}elseif($fields.INSTALL_ATTEMPTED -ceq 'yes'){'POSSIBLE_PARTIAL_CHANGES_REVIEW_REQUIRED'}else{'INSTALL_NOT_ATTEMPTED'};rebootPerformed=$false;fullPatchCurrencyProven=$false;brokerReady=$false}
}
