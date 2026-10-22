# Pure bounded receipt reader and payload construction. No execution on import.
function New-PaytmMaintenancePayload([string]$RunId,[string]$Helpers,[string]$Source) {
    if($RunId -cnotmatch '^[a-f0-9]{32}$' -or ($Helpers.Length+$Source.Length) -gt 24000 -or ($Helpers+$Source).Contains('MB_MAINTENANCE_PLAN') -or ($Helpers+$Source).Contains([char]0)){throw 'MAINT_PAYLOAD_INVALID'}
    "sudo -n timeout --kill-after=5s 240s bash <<'MB_MAINTENANCE_PLAN'`n"+$Helpers.Replace("`r",'')+"`n"+$Source.Replace("`r",'')+"`npm_main '$RunId'`nMB_MAINTENANCE_PLAN`n"
}
function Read-PaytmMaintenanceReceipt([string]$Text,[string]$RunId) {
    if($RunId -cnotmatch '^[a-f0-9]{32}$' -or $Text.Length -gt 40000){throw 'MAINT_RECEIPT_INVALID'}
    $lines=@($Text.Replace("`r",'').Trim().Split("`n"))
    if($lines.Count -lt 3 -or $lines[0] -cne "BEGIN_PAYTM_MAINTENANCE_$RunId" -or $lines[-1] -cne "END_PAYTM_MAINTENANCE_$RunId"){throw 'MAINT_CURRENT_BLOCK_REQUIRED'}
    $expected=@('VERSION','RUN_ID','HOST_IDENTITY','PROXY_CONFIG','ALLOWLIST','SERVICE_CONFIG','SERVICE_STATE','DROPINS','RELOAD_NEEDED','LISTENER_COUNT','SSH_CONFIG_VALID','DPKG_AUDIT','HOLD_COUNT','APT_FREE_KIB','APT_FREE_INODES','NTP_SYNCHRONIZED','SIMULATION_EXIT','UPGRADE_COUNT','REMOVAL_COUNT','CANDIDATES_B64','CAPTURE_COMPLETE')
    $fields=[ordered]@{}
    foreach($line in $lines[1..($lines.Count-2)]){
        if($line -cnotmatch '^([A-Z][A-Z0-9_]+)=([A-Za-z0-9+/=_-]{1,32768})$'){throw 'MAINT_FIELD_INVALID'}
        $key=$Matches[1];$value=$Matches[2]
        if($key -cnotin $expected -or $fields.Contains($key) -or ($key -cne 'CANDIDATES_B64' -and $value.Length -gt 120)){throw 'MAINT_FIELD_DUPLICATE_OR_UNKNOWN'}
        $fields[$key]=$value
    }
    if($fields.Count -ne $expected.Count -or $fields.VERSION -cne '1' -or $fields.RUN_ID -cne $RunId -or $fields.CAPTURE_COMPLETE -cne 'yes'){throw 'MAINT_INCOMPLETE'}
    $findings=[Collections.Generic.List[string]]::new()
    foreach($pair in @(@('HOST_IDENTITY','MATCH'),@('PROXY_CONFIG','MATCH'),@('ALLOWLIST','MATCH'),@('SERVICE_CONFIG','MATCH'),@('SERVICE_STATE','inactive'),@('DROPINS','NONE'),@('RELOAD_NEEDED','no'),@('LISTENER_COUNT','0'),@('SSH_CONFIG_VALID','yes'),@('DPKG_AUDIT','CLEAN'),@('HOLD_COUNT','0'),@('NTP_SYNCHRONIZED','yes'),@('SIMULATION_EXIT','0'),@('REMOVAL_COUNT','0'))){
        if($fields[$pair[0]] -cne $pair[1]){$findings.Add($pair[0]+'_REVIEW')}
    }
    # Conservative screening only, not a computed package/backup space requirement.
    foreach($pair in @(@('APT_FREE_KIB',1048576),@('APT_FREE_INODES',10000))){
        if($fields[$pair[0]] -cnotmatch '^\d{1,15}$' -or [long]$fields[$pair[0]] -lt $pair[1]){$findings.Add($pair[0]+'_REVIEW')}
    }
    $packages=@();$seen=[Collections.Generic.HashSet[string]]::new()
    if($fields.CANDIDATES_B64 -ceq 'TOO_LARGE'){$findings.Add('PACKAGE_LIST_TOO_LARGE')}
    elseif($fields.CANDIDATES_B64 -cne 'NONE'){
        try{$decoded=[Text.UTF8Encoding]::new($false,$true).GetString([Convert]::FromBase64String($fields.CANDIDATES_B64))}catch{throw 'MAINT_PACKAGE_ENCODING_INVALID'}
        foreach($row in $decoded.TrimEnd("`n").Split("`n")){
            if($row -cnotmatch '^([a-z0-9][a-z0-9.+:-]{0,119})\|([A-Za-z0-9.+:~_-]{1,120})\|([A-Za-z0-9.+:~_-]{1,120})$'){throw 'MAINT_PACKAGE_INVALID'}
            $name=$Matches[1];$installed=$Matches[2];$candidate=$Matches[3]
            if(-not $seen.Add($name)){throw 'MAINT_DUPLICATE_PACKAGE'}
            if($installed -ceq 'NOT_INSTALLED'){$findings.Add('NEW_PACKAGE_REVIEW')}
            $packages+=[pscustomobject]@{package=$name;installed=$installed;candidate=$candidate}
        }
        if($packages.Count -gt 200){throw 'MAINT_PACKAGE_LIMIT'}
    }
    if($fields.SIMULATION_EXIT -ceq '0' -and $fields.CANDIDATES_B64 -cne 'TOO_LARGE' -and ($fields.UPGRADE_COUNT -cnotmatch '^\d{1,3}$' -or [int]$fields.UPGRADE_COUNT -ne $packages.Count)){throw 'MAINT_PACKAGE_COUNT_MISMATCH'}
    [pscustomobject]@{fields=$fields;packages=$packages;findings=@($findings.ToArray());technicalPreflightPassed=($findings.Count -eq 0);upgradeAuthorized=$false;backupVerified=$false;recoveryVerified=$false;indexesRefreshed=$false;diskRequirementCalculated=$false}
}
