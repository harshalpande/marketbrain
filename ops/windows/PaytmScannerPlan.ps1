. (Join-Path $PSScriptRoot 'PaytmRestartReview.ps1')
function Assert-PaytmMissingScannerEvidence([string]$Path) {
    $file=Get-Item -LiteralPath $Path
    if($file.PSIsContainer -or $file.Length -gt 20000 -or (Get-FileHash -LiteralPath $file.FullName -Algorithm SHA256).Hash -cne 'A5439CA9AEE38BB561F6E61CDFA45899D755FD81162DAFCADE6BCEEB635D50CC'){throw 'SCANNER_EVIDENCE_MISMATCH'}
    [pscustomobject]@{runId='77b0af7628bf4162807175c4c8eac0c3';sha256='A5439CA9AEE38BB561F6E61CDFA45899D755FD81162DAFCADE6BCEEB635D50CC'}
}
function New-PaytmScannerPlanPayload([string]$RunId,[string]$Source) {
    if($RunId -cnotmatch '^[a-f0-9]{32}$' -or $Source.Length -gt 40000 -or $Source.Contains('MB_SCANNER_PLAN') -or $Source.Contains([char]0)){throw 'SCANNER_PAYLOAD_INVALID'}
    "sudo -n timeout --kill-after=5s 420s bash <<'MB_SCANNER_PLAN'`n"+$Source.Replace("`r",'')+"`npsp_main '$RunId'`nMB_SCANNER_PLAN`n"
}
function Read-PaytmScannerPlan([string]$Text,[string]$RunId) {
    if($RunId -cnotmatch '^[a-f0-9]{32}$' -or $Text.Length -gt 90000){throw 'SCANNER_RECEIPT_INVALID'}
    $lines=@($Text.Replace("`r",'').Trim().Split("`n"));$fields=[ordered]@{}
    $keys=@('VERSION','RUN_ID','REVIEW_B64','SIMULATION_EXIT','ACTIONS_STATE','ACTIONS_B64','CAPTURE_COMPLETE')
    if($lines.Count -lt 3 -or $lines[0] -cne "BEGIN_PAYTM_SCANNER_PLAN_$RunId" -or $lines[-1] -cne "END_PAYTM_SCANNER_PLAN_$RunId"){throw 'SCANNER_CURRENT_BLOCK_REQUIRED'}
    foreach($line in $lines[1..($lines.Count-2)]){
        if($line -cnotmatch '^([A-Z][A-Z0-9_]+)=([A-Za-z0-9+/=_-]{1,54000})$'){throw 'SCANNER_FIELD_INVALID'}
        $key=$Matches[1];$value=$Matches[2]
        if($key -cnotin $keys -or $fields.Contains($key)){throw 'SCANNER_DUPLICATE_OR_UNKNOWN'}
        $fields[$key]=$value
    }
    if($fields.Count -ne $keys.Count -or $fields.VERSION -cne '1' -or $fields.RUN_ID -cne $RunId -or $fields.CAPTURE_COMPLETE -cne 'yes'){throw 'SCANNER_INCOMPLETE'}
    if($fields.SIMULATION_EXIT -cnotmatch '^(UNKNOWN|[0-9]{1,3})$' -or $fields.ACTIONS_STATE -cnotin @('CAPTURED','INVALID','TOO_LARGE')){throw 'SCANNER_STATE_INVALID'}
    $review=Read-PaytmRestartReceipt (ConvertFrom-PaytmRestartBase64 $fields.REVIEW_B64) $RunId
    $findings=[Collections.Generic.List[string]]::new()
    foreach($f in $review.findings){
        # Only the already-known absent scanner is expected; all other findings persist.
        if(-not ($f -ceq 'RESTART_SCANNER_UNAVAILABLE_OR_FAILED' -and $review.scannerState -ceq 'UNAVAILABLE' -and $review.scannerExit -ceq 'NOT_RUN')){$findings.Add($f)}
    }
    if($review.scannerState -cne 'UNAVAILABLE'){$findings.Add('SCANNER_NOW_PRESENT_DO_NOT_REINSTALL')}
    if($fields.SIMULATION_EXIT -cne '0'){$findings.Add('SCANNER_INSTALL_SIMULATION_FAILED')}
    if($fields.ACTIONS_STATE -cne 'CAPTURED'){$findings.Add('SCANNER_ACTION_CAPTURE_INCOMPLETE')}
    $actions=@();$installs=[ordered]@{};$configs=[ordered]@{};$seen=[Collections.Generic.HashSet[string]]::new()
    if($fields.ACTIONS_STATE -ceq 'CAPTURED'){
        $decoded=ConvertFrom-PaytmRestartBase64 $fields.ACTIONS_B64
        if($decoded.Length -gt 16000){throw 'SCANNER_ACTION_LIMIT'}
        if($decoded){foreach($row in $decoded.TrimEnd("`n").Split("`n")){
            if($row -cnotmatch '^([ICR])\|([a-z0-9][a-z0-9.+:-]{0,119})\|([A-Za-z0-9.+:~_-]{1,120})\|([A-Za-z0-9.+:~_-]{1,120})$'){throw 'SCANNER_ACTION_INVALID'}
            $action=$Matches[1];$name=$Matches[2];$before=$Matches[3];$after=$Matches[4]
            if(-not $seen.Add($action+'|'+$name)){throw 'SCANNER_DUPLICATE_ACTION'}
            $actions+=[pscustomobject]@{action=$action;package=$name;installed=$before;candidate=$after}
            switch -CaseSensitive ($action){
                'I' {$installs[$name]=$after;if($before -cne 'NOT_INSTALLED'){$findings.Add('EXISTING_PACKAGE_CHANGE_REVIEW')}}
                'C' {if($before -cne 'NOT_APPLICABLE'){throw 'SCANNER_CONFIG_INVALID'};$configs[$name]=$after}
                'R' {if($after -cne 'NOT_APPLICABLE'){throw 'SCANNER_REMOVAL_INVALID'};$findings.Add('PACKAGE_REMOVAL_REVIEW')}
            }
        }}
        if($actions.Count -gt 60 -or $installs.Count -gt 30){throw 'SCANNER_ACTION_LIMIT'}
        if(-not $installs.Contains('needrestart')){$findings.Add('SCANNER_NEW_INSTALL_NOT_IN_PLAN')}
        foreach($name in $installs.Keys){if(-not $configs.Contains($name) -or $configs[$name] -cne $installs[$name]){$findings.Add('INSTALL_CONFIGURE_MISMATCH')}}
        foreach($name in $configs.Keys){if(-not $installs.Contains($name)){$findings.Add('UNEXPECTED_CONFIGURATION_REVIEW')}}
    }
    [pscustomobject]@{restartReview=$review;simulationExit=$fields.SIMULATION_EXIT;actionsState=$fields.ACTIONS_STATE;actions=$actions;proposedInstallCount=$installs.Count;findings=@($findings.ToArray()|Select-Object -Unique);readyForManifestReview=($findings.Count -eq 0);installationAuthorized=$false;restartClearanceGranted=$false;indexesRefreshed=$false;packageOriginsVerified=$false;unattendedGatewayApproved=$false}
}
