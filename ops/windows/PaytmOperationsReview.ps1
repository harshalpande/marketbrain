# Pure receipt validation. No network, settings changes or credential access.
function Read-PaytmOperationsReceipt {
    param([string]$Text,[string]$RunId,[DateTimeOffset]$Started,[DateTimeOffset]$Received,[ValidateSet(1,2)][int]$ExpectedVersion=1)
    $sizeLimit=if($ExpectedVersion -eq 2){40000}else{8000}
    if ($RunId -cnotmatch '^[a-f0-9]{32}$' -or $Text.Length -gt $sizeLimit -or $Received -lt $Started -or ($Received-$Started).TotalMinutes -gt 20) {throw 'OPS_RECEIPT_WINDOW_OR_SIZE_INVALID'}
    $lines=@($Text.Replace("`r",'').Trim().Split("`n"))
    if ($lines.Count -lt 3 -or $lines[0] -cne "BEGIN_PAYTM_OPERATIONS_$RunId" -or $lines[-1] -cne "END_PAYTM_OPERATIONS_$RunId") {throw 'OPS_CURRENT_RUN_BLOCK_REQUIRED'}
    $expected=@('VERSION','RUN_ID','HOST_IDENTITY','UTC_EPOCH','PROXY_CONFIG','ALLOWLIST','SERVICE_CONFIG','SERVICE_STATE','DROPINS','RELOAD_NEEDED','LISTENER_COUNT','WATCHDOG_UNIT_COUNT','VPS_BOUND_PUBLIC_IPV4','NTP_SYNCHRONIZED','KERNEL','SSH_VERSION','PROXY_VERSION','APT_OLDEST_RELEASE_EPOCH','CACHED_UPGRADE_COUNT','REBOOT_MARKER','CAPTURE_COMPLETE')
    $fields=[ordered]@{}
    if($ExpectedVersion -eq 2){$expected+=@('APT_UPDATE_EXIT','APT_UPDATE_SECONDS','APT_SIMULATION_EXIT','UPGRADE_CANDIDATES_B64')}
    foreach($line in $lines[1..($lines.Count-2)]) {
        if ($line -cnotmatch '^([A-Z][A-Z0-9_]+)=([A-Za-z0-9.:+_/~=-]{1,32768})$') {throw 'OPS_RECEIPT_FIELD_INVALID'}
        $key=$Matches[1];$value=$Matches[2]
        if($key -cne 'UPGRADE_CANDIDATES_B64' -and $value.Length -gt 120){throw 'OPS_RECEIPT_FIELD_TOO_LONG'}
        if ($key -cnotin $expected -or $fields.Contains($key)) {throw 'OPS_RECEIPT_DUPLICATE_OR_UNKNOWN_FIELD'}
        $fields[$key]=$value
    }
    if ($fields.Count -ne $expected.Count -or $fields.RUN_ID -cne $RunId -or $fields.VERSION -cne [string]$ExpectedVersion -or $fields.CAPTURE_COMPLETE -cne 'yes') {throw 'OPS_RECEIPT_INCOMPLETE'}
    $findings=[Collections.Generic.List[string]]::new()
    $upgrades=@();$refreshed=$false
    if($ExpectedVersion -eq 2){
        foreach($key in @('APT_UPDATE_EXIT','APT_UPDATE_SECONDS','APT_SIMULATION_EXIT')){if($fields[$key] -cnotmatch '^\d{1,6}$'){throw 'OPS_REFRESH_NUMERIC_FIELD_INVALID'}}
        $refreshed=$fields.APT_UPDATE_EXIT -ceq '0'
        if(-not $refreshed){$findings.Add('APT_REFRESH_FAILED_CANDIDATES_MAY_BE_STALE')}
        if($fields.APT_SIMULATION_EXIT -cne '0'){$findings.Add('APT_SIMULATION_FAILED')}
        if($fields.UPGRADE_CANDIDATES_B64 -ceq 'TOO_LARGE'){$findings.Add('UPGRADE_LIST_TOO_LARGE')}
        elseif($fields.UPGRADE_CANDIDATES_B64 -cne 'NONE'){
            try{$decoded=[Text.UTF8Encoding]::new($false,$true).GetString([Convert]::FromBase64String($fields.UPGRADE_CANDIDATES_B64))}catch{throw 'OPS_UPGRADE_LIST_ENCODING_INVALID'}
            foreach($row in $decoded.TrimEnd("`n").Split("`n")){
                if($row -cnotmatch '^([a-z0-9][a-z0-9.+:-]{0,119})\|([A-Za-z0-9.+:~_-]{1,120})\|([A-Za-z0-9.+:~_-]{1,120})$'){throw 'OPS_UPGRADE_ROW_INVALID'}
                $upgrades+= [pscustomobject]@{package=$Matches[1];installed=$Matches[2];candidate=$Matches[3]}
            }
            if($upgrades.Count -gt 200){throw 'OPS_UPGRADE_LIST_TOO_LONG'}
        }
        if($fields.APT_SIMULATION_EXIT -ceq '0' -and $fields.UPGRADE_CANDIDATES_B64 -cne 'TOO_LARGE' -and ($fields.CACHED_UPGRADE_COUNT -cnotmatch '^\d{1,6}$' -or $upgrades.Count -ne [int]$fields.CACHED_UPGRADE_COUNT)){throw 'OPS_UPGRADE_COUNT_MISMATCH'}
    }
    foreach($key in @('HOST_IDENTITY','PROXY_CONFIG','ALLOWLIST','SERVICE_CONFIG')) {if ($fields[$key] -cne 'MATCH') {$findings.Add("${key}_NOT_MATCHED")}}
    foreach($pair in @(@('SERVICE_STATE','inactive'),@('DROPINS','NONE'),@('RELOAD_NEEDED','no'),@('LISTENER_COUNT','0'),@('WATCHDOG_UNIT_COUNT','0'),@('VPS_BOUND_PUBLIC_IPV4','130.250.191.137'),@('NTP_SYNCHRONIZED','yes'))) {
        if ($fields[$pair[0]] -cne $pair[1]) {$findings.Add("$($pair[0])_REVIEW")}
    }
    $clock='UNKNOWN';$cacheAge=$null
    if ($fields.UTC_EPOCH -cmatch '^\d{10}$') {
        $epoch=[long]$fields.UTC_EPOCH
        if ($epoch -ge ($Started.ToUnixTimeSeconds()-5) -and $epoch -le ($Received.ToUnixTimeSeconds()+5)) {$clock='WITHIN_MANUAL_COLLECTION_WINDOW'}
        else {$clock='OUTSIDE_MANUAL_COLLECTION_WINDOW';$findings.Add('CLOCK_OUTSIDE_COLLECTION_WINDOW')}
        if ($fields.APT_OLDEST_RELEASE_EPOCH -cmatch '^\d{10}$') {
            $cacheAge=[math]::Round(($epoch-[long]$fields.APT_OLDEST_RELEASE_EPOCH)/86400,3)
            if ($cacheAge -lt 0 -or ($cacheAge -gt 7 -and -not $refreshed)) {$findings.Add('APT_CACHE_DATE_REVIEW')}
        } else {$findings.Add('APT_CACHE_DATE_UNKNOWN')}
    } else {$findings.Add('SERVER_TIME_UNKNOWN')}
    if ($fields.CACHED_UPGRADE_COUNT -cnotmatch '^\d{1,6}$') {$findings.Add('CACHED_UPGRADE_COUNT_UNKNOWN')}
    elseif ([int]$fields.CACHED_UPGRADE_COUNT -gt 0) {$findings.Add('CACHED_UPGRADES_PRESENT')}
    if ($fields.REBOOT_MARKER -cne 'ABSENT') {$findings.Add('REBOOT_MARKER_REVIEW')}
    foreach($key in @('KERNEL','SSH_VERSION','PROXY_VERSION')) {if($fields[$key] -ceq 'UNKNOWN') {$findings.Add("${key}_UNKNOWN")}}
    [pscustomobject]@{
        fields=$fields;findings=@($findings.ToArray());clockComparison=$clock;oldestReleaseMetadataAgeDays=$cacheAge
        collectionWindowSeconds=[math]::Round(($Received-$Started).TotalSeconds,3)
        packageIndexesRefreshed=$refreshed;upgradeCandidates=$upgrades
        clockAccuracyProven=$false;applicationProxyEgressReobserved=$false;fullyPatchedProven=$false
    }
}
function Assert-PaytmAcceptedApplicationReport([string]$Path) {
    $file=Get-Item -LiteralPath $Path
    if ($file.Length -gt 2000000 -or $file.PSIsContainer) {throw 'OPS_APPLICATION_EVIDENCE_INVALID'}
    # Pin the exact owner-reviewed artifact; another run requires a separate review.
    $hash=(Get-FileHash -LiteralPath $file.FullName -Algorithm SHA256).Hash
    if ($hash -cne 'E7AD80D611B693FF892DD3765C87FF333E554A4343E2647C08D7725F5A804973') {throw 'OPS_ACCEPTED_APPLICATION_EVIDENCE_HASH_MISMATCH'}
    [pscustomobject]@{runId='223cdc084de64c90a80c527032ac6879';sha256=$hash}
}
function New-PaytmOperationsPayload([string]$RunId,[string]$Source,[switch]$RefreshReviewed) {
    if ($RunId -cnotmatch '^[a-f0-9]{32}$' -or $Source.Length -gt 16000 -or $Source.Contains([char]0) -or $Source.Contains('MB_OPERATIONS_READ_ONLY')) {throw 'OPS_PAYLOAD_INVALID'}
    if($RefreshReviewed){return "sudo -n timeout --kill-after=10s 420s bash <<'MB_OPERATIONS_READ_ONLY'`n" + $Source.Replace("`r`n","`n").TrimEnd() + "`npo_main '$RunId' refresh-reviewed`nMB_OPERATIONS_READ_ONLY`n"}
    "sudo -n timeout 180s bash <<'MB_OPERATIONS_READ_ONLY'`n" + $Source.Replace("`r`n","`n").TrimEnd() + "`npo_main '$RunId'`nMB_OPERATIONS_READ_ONLY`n"
}
function Get-PaytmWindowsSshInventory {
    # Read only the Windows-owned client metadata and agent service state. No keys/registry secrets.
    $result=[ordered]@{windowsOpenSshPresent=$false;clientVersion=$null;agentStatus='UNKNOWN';agentStartType='UNKNOWN';keyStoreInspected=$false}
    try {
        $client=Join-Path $env:WINDIR 'System32\OpenSSH\ssh.exe'
        if(Test-Path -LiteralPath $client -PathType Leaf){$result.windowsOpenSshPresent=$true;$result.clientVersion=[Diagnostics.FileVersionInfo]::GetVersionInfo($client).FileVersion}
        $service=Get-Service -Name ssh-agent -ErrorAction Stop
        $result.agentStatus=[string]$service.Status;$result.agentStartType=[string]$service.StartType
    } catch { } # Absence/denied read is unknown, not permission to install or start it.
    [pscustomobject]$result
}
