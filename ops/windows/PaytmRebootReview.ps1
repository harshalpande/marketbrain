. (Join-Path $PSScriptRoot 'PaytmRestartReview.ps1')
function Assert-PaytmScannerInstallAccepted([string]$Path) {
    $file=Get-Item -LiteralPath $Path
    if($file.PSIsContainer -or $file.Length -gt 30000 -or (Get-FileHash -LiteralPath $file.FullName -Algorithm SHA256).Hash -cne '507BD7B7C94C24EA4ACE9A1258BE41106BE79468FC1FC7F5645D92DCF905ECA2'){throw 'REBOOT_SCANNER_EVIDENCE_MISMATCH'}
    [pscustomobject]@{runId='7e54c5029aca42e3a96c8e0195311723';sha256='507BD7B7C94C24EA4ACE9A1258BE41106BE79468FC1FC7F5645D92DCF905ECA2'}
}
function New-PaytmRebootPayload([string]$RunId,[string]$Source,[ValidateSet('BEFORE','AFTER','REBOOT')][string]$Phase,[string]$BootId,[string]$Epoch) {
    if($RunId -cnotmatch '^[a-f0-9]{32}$' -or $Source.Length -gt 100000 -or $Source.Contains('MB_REBOOT_REVIEW') -or $Source.Contains([char]0)){throw 'REBOOT_PAYLOAD_INVALID'}
    $entry="rb_observe '$RunId' '$Phase'"
    if($Phase -ceq 'REBOOT'){
        if($BootId -cnotmatch '^[a-f0-9]{8}(-[a-f0-9]{4}){3}-[a-f0-9]{12}$' -or $Epoch -cnotmatch '^[0-9]{10}$'){throw 'REBOOT_BINDING_INVALID'}
        $entry="rb_reboot '$BootId' '$Epoch'"
    }
    "sudo -n timeout --kill-after=5s 420s bash <<'MB_REBOOT_REVIEW'`n"+$Source.Replace("`r",'')+"`n$entry`nMB_REBOOT_REVIEW`n"
}
function Read-PaytmRebootReceipt([string]$Text,[string]$RunId,[ValidateSet('BEFORE','AFTER')][string]$Phase) {
    if($RunId -cnotmatch '^[a-f0-9]{32}$' -or $Text.Length -gt 65000){throw 'REBOOT_RECEIPT_INVALID'}
    $lines=@($Text.Replace("`r",'').Trim().Split("`n"));$fields=[ordered]@{}
    $keys=@('VERSION','RUN_ID','PHASE','BOOT_ID','UTC_EPOCH','VM','CONTAINER','SCANNER_PACKAGES','BACKUP_READABLE','JOBS_IDLE','GATEWAY_DISABLED','CORE_SERVICES_ACTIVE','REVIEW_B64','CAPTURE_COMPLETE')
    if($lines.Count -lt 3 -or $lines[0] -cne "BEGIN_PAYTM_REBOOT_$RunId" -or $lines[-1] -cne "END_PAYTM_REBOOT_$RunId"){throw 'REBOOT_CURRENT_BLOCK_REQUIRED'}
    foreach($line in $lines[1..($lines.Count-2)]){
        if($line -cnotmatch '^([A-Z][A-Z0-9_]+)=([A-Za-z0-9+/=_-]{1,54000})$'){throw 'REBOOT_FIELD_INVALID'}
        $key=$Matches[1];$value=$Matches[2]
        if($key -cnotin $keys -or $fields.Contains($key) -or ($key -cne 'REVIEW_B64' -and $value.Length -gt 120)){throw 'REBOOT_DUPLICATE_OR_UNKNOWN'}
        $fields[$key]=$value
    }
    if($fields.Count -ne $keys.Count -or $fields.VERSION -cne '1' -or $fields.RUN_ID -cne $RunId -or $fields.PHASE -cne $Phase -or $fields.CAPTURE_COMPLETE -cne 'yes'){throw 'REBOOT_INCOMPLETE'}
    if($fields.BOOT_ID -cnotmatch '^[a-f0-9]{8}(-[a-f0-9]{4}){3}-[a-f0-9]{12}$' -or $fields.UTC_EPOCH -cnotmatch '^[0-9]{10}$'){throw 'REBOOT_IDENTITY_INVALID'}
    $review=Read-PaytmRestartReceipt (ConvertFrom-PaytmRestartBase64 $fields.REVIEW_B64) $RunId
    $findings=[Collections.Generic.List[string]]::new()
    if($review.scanner.KCUR -cne $review.scanner.KEXP){$findings.Add('KERNEL_VERSION_MISMATCH')}
    foreach($name in @('SCANNER_PACKAGES','BACKUP_READABLE','JOBS_IDLE','GATEWAY_DISABLED','CORE_SERVICES_ACTIVE')){if($fields[$name] -cne 'YES'){$findings.Add($name+'_REVIEW')}}
    # needrestart 3.11 skips microcode inside a VM; keep this as an explicit provider limit.
    # Never infer VM status from hostname or missing UCSTA alone. Unknown containers stay blocked.
    $vmConfirmed=$fields.VM -cin @('kvm','qemu','vmware','microsoft','oracle','xen','amazon','google','parallels','bhyve','bochs','uml','acrn','powervm','zvm','apple') -and $fields.CONTAINER -ceq 'none'
    $providerLimit=$vmConfirmed -and -not $review.scanner.Contains('UCSTA') -and $review.scanner.VER -ceq '3.11'
    if(-not $vmConfirmed){$findings.Add('VM_ENVIRONMENT_REVIEW')}
    foreach($finding in $review.findings){
        if($providerLimit -and $finding -cin @('RESTART_SCANNER_UCSTA_MISSING','MICROCODE_REVIEW_REQUIRED')){continue}
        if($Phase -ceq 'BEFORE' -and $finding -cin @('SERVICE_RESTARTS_REVIEW','STALE_SESSIONS_REVIEW')){continue}
        $findings.Add($finding)
    }
    # Before a whole-VPS reboot, only the reviewed six service names are in scope.
    if($Phase -ceq 'BEFORE'){
        foreach($service in $review.servicesRequiringReview){if($service -cnotin @('cron.service','dbus.service','ssh.service','systemd-logind.service','systemd-timesyncd.service','systemd-udevd.service')){$findings.Add('UNREVIEWED_SERVICE_RESTART')}}
    }
    [pscustomobject]@{fields=$fields;restartReview=$review;findings=@($findings.ToArray()|Select-Object -Unique);checksPassed=($findings.Count -eq 0);microcodeAssessment=if($providerLimit){'NOT_ASSESSED_IN_VM_PROVIDER_MANAGED'}else{'SEE_SCANNER'};gatewayActivationAuthorized=$false;ordersEnabled=$false}
}
function Read-PaytmRebootCheckpoint([string]$Path) {
    $file=Get-Item -LiteralPath $Path
    if($file.PSIsContainer -or $file.Length -gt 180000){throw 'REBOOT_CHECKPOINT_INVALID'}
    $report=Get-Content -LiteralPath $file.FullName -Raw|ConvertFrom-Json
    if($report.schemaVersion -ne 1 -or $report.mode -cne 'Before' -or $report.runId -cnotmatch '^[a-f0-9]{32}$' -or $report.status -cne 'REBOOT_COMMAND_PREPARED_POSTCHECK_PENDING' -or $report.ownerRebootConfirmed -ne $true -or $report.rebootCommandPrepared -ne $true -or $report.failure -or $report.acceptedScanner.sha256 -cne '507BD7B7C94C24EA4ACE9A1258BE41106BE79468FC1FC7F5645D92DCF905ECA2'){throw 'REBOOT_CHECKPOINT_INVALID'}
    $before=Read-PaytmRebootReceipt $report.beforeReceipt $report.runId BEFORE
    if(-not $before.checksPassed){throw 'REBOOT_CHECKPOINT_FINDINGS'}
    [pscustomobject]@{runId=$report.runId;before=$before;beforeReceipt=$report.beforeReceipt;acceptedScanner=$report.acceptedScanner}
}
