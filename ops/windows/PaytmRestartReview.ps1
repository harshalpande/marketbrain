. (Join-Path $PSScriptRoot 'PaytmMaintenanceReview.ps1')
function Assert-PaytmUpdateAccepted([string]$Path) {
    $file=Get-Item -LiteralPath $Path
    if($file.PSIsContainer -or $file.Length -gt 20000 -or (Get-FileHash -LiteralPath $file.FullName -Algorithm SHA256).Hash -cne '146AF6DC88625F881981900DB571A1BCEDA3BCFAB67FB4470A13F4850A120EF5'){throw 'RESTART_UPDATE_EVIDENCE_MISMATCH'}
    [pscustomobject]@{runId='61e8afb23b9e4e73b883914330c99514';sha256='146AF6DC88625F881981900DB571A1BCEDA3BCFAB67FB4470A13F4850A120EF5'}
}
function New-PaytmRestartPayload([string]$RunId,[string]$Source) {
    if($RunId -cnotmatch '^[a-f0-9]{32}$' -or $Source.Length -gt 35000 -or $Source.Contains('MB_RESTART_REVIEW') -or $Source.Contains([char]0)){throw 'RESTART_PAYLOAD_INVALID'}
    "sudo -n timeout --kill-after=5s 300s bash <<'MB_RESTART_REVIEW'`n"+$Source.Replace("`r",'')+"`npr_main '$RunId'`nMB_RESTART_REVIEW`n"
}
function ConvertFrom-PaytmRestartBase64([string]$Value) {
    if($Value -ceq 'NONE'){return ''}
    if($Value.Length -gt 54000){throw 'RESTART_ENCODED_LIMIT'}
    try{[Text.UTF8Encoding]::new($false,$true).GetString([Convert]::FromBase64String($Value))}catch{throw 'RESTART_ENCODING_INVALID'}
}
function Read-PaytmRestartReceipt([string]$Text,[string]$RunId) {
    if($RunId -cnotmatch '^[a-f0-9]{32}$' -or $Text.Length -gt 120000){throw 'RESTART_RECEIPT_INVALID'}
    $lines=@($Text.Replace("`r",'').Trim().Split("`n")); $fields=[ordered]@{}
    $keys=@('VERSION','RUN_ID','BASELINE_B64','TARGETS_VERIFIED','REBOOT_MARKER','FAILED_UNITS_EXIT','FAILED_UNITS_B64','NEEDRESTART_STATE','NEEDRESTART_EXIT','NEEDRESTART_B64','CAPTURE_COMPLETE')
    if($lines.Count -lt 3 -or $lines[0] -cne "BEGIN_PAYTM_RESTART_$RunId" -or $lines[-1] -cne "END_PAYTM_RESTART_$RunId"){throw 'RESTART_CURRENT_BLOCK_REQUIRED'}
    foreach($line in $lines[1..($lines.Count-2)]){
        if($line -cnotmatch '^([A-Z][A-Z0-9_]+)=([A-Za-z0-9+/=_-]{1,54000})$'){throw 'RESTART_FIELD_INVALID'}
        $key=$Matches[1];$value=$Matches[2]
        if($key -cnotin $keys -or $fields.Contains($key)){throw 'RESTART_DUPLICATE_OR_UNKNOWN'}
        $fields[$key]=$value
    }
    if($fields.Count -ne $keys.Count -or $fields.VERSION -cne '1' -or $fields.RUN_ID -cne $RunId -or $fields.CAPTURE_COMPLETE -cne 'yes'){throw 'RESTART_INCOMPLETE'}
    if($fields.TARGETS_VERIFIED -cnotin @('YES','NO') -or $fields.REBOOT_MARKER -cnotin @('ABSENT','PRESENT') -or $fields.NEEDRESTART_STATE -cnotin @('PRESENT','UNAVAILABLE') -or $fields.FAILED_UNITS_EXIT -cnotmatch '^(UNKNOWN|[0-9]{1,3})$' -or $fields.NEEDRESTART_EXIT -cnotmatch '^(NOT_RUN|[0-9]{1,3})$'){throw 'RESTART_STATE_INVALID'}
    $baseline=Read-PaytmMaintenanceReceipt (ConvertFrom-PaytmRestartBase64 $fields.BASELINE_B64) $RunId
    $findings=[Collections.Generic.List[string]]::new()
    foreach($f in $baseline.findings){$findings.Add('BASELINE_'+$f)}
    if($baseline.packages.Count -gt 0){$findings.Add('CACHED_UPDATES_REMAIN_REVIEW')}
    if($fields.TARGETS_VERIFIED -cne 'YES'){$findings.Add('INSTALLED_TARGETS_REVIEW')}
    if($fields.REBOOT_MARKER -ceq 'PRESENT'){$findings.Add('REBOOT_MARKER_PRESENT')}
    $failedUnits=@();$historicalFailedUnitObserved=$false
    if($fields.FAILED_UNITS_EXIT -cne '0' -or $fields.FAILED_UNITS_B64 -ceq 'TOO_LARGE'){$findings.Add('FAILED_UNIT_SCAN_INCOMPLETE')}
    else{
        foreach($unit in (ConvertFrom-PaytmRestartBase64 $fields.FAILED_UNITS_B64).Trim().Split("`n")){
            if(-not $unit){continue}
            if($unit -cnotmatch '^[A-Za-z0-9_.@:-]+\.service$'){$findings.Add('FAILED_UNIT_OUTPUT_UNRECOGNIZED');continue}
            if($unit -ceq 'marketbrain-maintenance-7fb461f8bff74ee0bb15a5afed8c49bc.service'){$historicalFailedUnitObserved=$true}else{$failedUnits+=$unit}
        }
        if($failedUnits.Count -gt 0){$findings.Add('FAILED_SERVICES_REVIEW')}
    }
    $nr=[ordered]@{};$services=@();$sessions=0;$containers=0
    if($fields.NEEDRESTART_STATE -cne 'PRESENT' -or $fields.NEEDRESTART_EXIT -cne '0' -or $fields.NEEDRESTART_B64 -cin @('NONE','TOO_LARGE')){$findings.Add('RESTART_SCANNER_UNAVAILABLE_OR_FAILED')}
    else{
        foreach($line in (ConvertFrom-PaytmRestartBase64 $fields.NEEDRESTART_B64).Trim().Split("`n")){
            if($line -cnotmatch '^NEEDRESTART-(VER|KCUR|KEXP|KSTA|UCSTA|UCCUR|UCEXP|SVC|SESS|CONT): ([A-Za-z0-9_.+@:~=-]{1,160})$'){$findings.Add('RESTART_SCANNER_OUTPUT_UNRECOGNIZED');continue}
            $key=$Matches[1];$value=$Matches[2]
            switch -CaseSensitive ($key){
                'SVC' {if($value -cnotmatch '^[A-Za-z0-9_.@:-]+\.service$'){$findings.Add('RESTART_SERVICE_UNRECOGNIZED')}else{$services+=$value}}
                'SESS' {if($value -cne 'REDACTED'){throw 'RESTART_PRIVATE_DESCRIPTION_REJECTED'};$sessions++}
                'CONT' {if($value -cne 'REDACTED'){throw 'RESTART_PRIVATE_DESCRIPTION_REJECTED'};$containers++}
                default {if($nr.Contains($key)){throw 'RESTART_SCANNER_DUPLICATE'};$nr[$key]=$value}
            }
        }
        foreach($key in @('VER','KCUR','KEXP','KSTA','UCSTA')){if(-not $nr.Contains($key)){$findings.Add('RESTART_SCANNER_'+$key+'_MISSING')}}
        if($nr.KSTA -cne '1'){$findings.Add('KERNEL_REVIEW_REQUIRED')}
        if($nr.UCSTA -cne '1'){$findings.Add('MICROCODE_REVIEW_REQUIRED')}
        if($services.Count -gt 0){$findings.Add('SERVICE_RESTARTS_REVIEW')}
        if($sessions -gt 0){$findings.Add('STALE_SESSIONS_REVIEW')}
        if($containers -gt 0){$findings.Add('STALE_CONTAINERS_REVIEW')}
    }
    [pscustomobject]@{baseline=$baseline;targetsVerified=($fields.TARGETS_VERIFIED -ceq 'YES');rebootMarker=$fields.REBOOT_MARKER;scannerState=$fields.NEEDRESTART_STATE;scannerExit=$fields.NEEDRESTART_EXIT;scanner=$nr;servicesRequiringReview=$services;staleSessionCount=$sessions;staleContainerCount=$containers;failedServices=$failedUnits;historicalFailedUnitObserved=$historicalFailedUnitObserved;findings=@($findings.ToArray()|Select-Object -Unique);noKnownRestartFindings=($findings.Count -eq 0);restartAuthorized=$false;unattendedGatewayApproved=$false}
}
