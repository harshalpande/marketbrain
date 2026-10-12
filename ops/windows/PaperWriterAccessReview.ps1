# Definitions and fixed contracts only.
function Read-PaperFirewallOutput([string]$Text,[bool]$Interrupted) {
    if($Text.Length -gt 32MB){throw 'ACCESS_FIREWALL_OUTPUT_LIMIT'}
    $last=$null;$malformed=$false;$lineCount=0
    foreach($line in ($Text -split '\r?\n')){
        if(-not $line.Trim()){continue}
        $lineCount++
        if($lineCount -gt 24 -or [Text.Encoding]::UTF8.GetByteCount($line) -gt 1MB){$malformed=$true;break}
        try {
            $v=$line|ConvertFrom-Json
            if($v.version -cne 'PAPER_FIREWALL_SNAPSHOT_V2' -or $v.status -cnotin @('RUNNING','FAILED','METADATA_CAPTURED_REVIEW_REQUIRED')){throw 'Invalid checkpoint'}
            if(@($v.rules).Count -gt 1000 -or @($v.profiles).Count -gt 3){throw 'Invalid checkpoint size'}
            foreach($flag in @('configurationChanged','effectiveAccessProven','truncated')){if($v.$flag -isnot [bool]){throw 'Invalid flag'}}
            if($v.configurationChanged -or $v.effectiveAccessProven){throw 'Unsafe checkpoint'}
            foreach($field in @('inboundRuleCount','scannedRuleCount','candidateRuleCount')){
                if(($v.$field -isnot [int] -and $v.$field -isnot [long]) -or $v.$field -lt 0 -or $v.$field -gt 2001){throw 'Invalid count'}
            }
            if($v.candidateRuleCount -ne @($v.rules).Count -or $v.scannedRuleCount -gt $v.inboundRuleCount){throw 'Inconsistent count'}
            if($v.status -ceq 'METADATA_CAPTURED_REVIEW_REQUIRED' -and ($v.truncated -or $v.failureCode -or @($v.profiles).Count -ne 3 -or $v.scannedRuleCount -ne $v.inboundRuleCount)){throw 'Incomplete success'}
            # Only diagnostic metadata belongs in the retained report, never arbitrary extra fields.
            $last=$v|Select-Object version,status,inboundRuleCount,scannedRuleCount,candidateRuleCount,truncated,failureCode,elapsedSeconds,configurationChanged,effectiveAccessProven
            $last|Add-Member -NotePropertyName profiles -NotePropertyValue @($v.profiles|Select-Object Name,Enabled,DefaultInboundAction,AllowInboundRules,AllowLocalFirewallRules)
            $last|Add-Member -NotePropertyName rules -NotePropertyValue @($v.rules|Select-Object name,action,profile,protocol,localPort,remotePort,localAddress,remoteAddress,program,service,edgeTraversal,policySourceType)
            if($last.failureCode -and $last.failureCode -cnotmatch '^FIREWALL_[A-Z_]+$'){$last.failureCode='FIREWALL_QUERY_FAILED'}
        }catch{$malformed=$true;break}
    }
    if($null -eq $last){throw 'ACCESS_FIREWALL_OUTPUT_INVALID'}
    if($Interrupted -or $malformed -or $last.status -ceq 'RUNNING'){
        $last.status='FAILED';$last.truncated=$true
        $last.failureCode=if($Interrupted){'FIREWALL_PROCESS_INTERRUPTED'}elseif($malformed){'FIREWALL_OUTPUT_INVALID'}else{'FIREWALL_OUTPUT_INCOMPLETE'}
    }
    return $last
}

function Assert-PaperFoundationEvidence($Saved) {
    if($Saved.version -cne 'PAPER_WRITER_FOUNDATION_V1' -or $Saved.status -cne 'FOUNDATION_CAPTURED_PRIVATE_BOUNDARY_REVIEW_REQUIRED' -or
       $Saved.failureCode -or $Saved.checkCount -ne 15 -or @($Saved.checks|Select-Object -Unique).Count -ne 15 -or
       $Saved.privateBoundary.status -cne 'OBSERVATIONS_CAPTURED_REVIEW_REQUIRED' -or $Saved.privateBoundary.failureCode){throw 'ACCESS_FOUNDATION_NOT_ACCEPTABLE'}
    foreach($field in @('databaseContacted','databaseWritesPerformed','realCredentialsCreated','hbaChanged','applicationWriterActivated','actionExecutionEnabled')){
        if($Saved.$field -isnot [bool] -or $Saved.$field){throw 'ACCESS_FOUNDATION_UNSAFE'}
    }
}
function New-PaperAccessReviewSql($Envelope) {
    $sql=New-PaperConnectionReviewSql $Envelope
    if(-not $sql.EndsWith('ROLLBACK;')){throw 'ACCESS_SQL_BOUNDARY_INVALID'}
    return $sql.Substring(0,$sql.Length-9)+"`nSELECT jsonb_build_object('serverStartEpoch',extract(epoch FROM pg_catalog.pg_postmaster_start_time())::text);`nROLLBACK;"
}
function Assert-PaperApplicationRoute($Route,$Inventory,$Server,[string]$RunId) {
    if(($Route.serverPort -isnot [int] -and $Route.serverPort -isnot [long]) -or
       [string]$Route.databaseOid -cnotmatch '^[0-9]{1,12}$' -or [string]$Route.serverStartEpoch -cnotmatch '^[0-9]{1,12}\.[0-9]{1,6}$'){throw 'ACCESS_ROUTE_METADATA_INVALID'}
    if($Route.version -cne 'PAPER_APPLICATION_ROUTE_V1' -or $Route.status -cne 'READ_ONLY_APPLICATION_ROUTE_OBSERVED' -or
       $Route.database -cne $Inventory.database -or [string]$Route.databaseOid -cne [string]$Inventory.databaseOid -or
       $Route.serverPort -ne $Inventory.serverPort -or [string]$Route.serverStartEpoch -cne [string]$Server.serverStartEpoch -or
       $Route.applicationName -cne ('mb-route-'+$RunId) -or $Route.applicationUser -cne $Route.sessionUser -or
       $Route.applicationUser -cnotmatch '^[A-Za-z_][A-Za-z0-9_]{0,62}$' -or $Route.readOnly -isnot [bool] -or -not $Route.readOnly){throw 'ACCESS_ROUTE_IDENTITY_MISMATCH'}
    foreach($field in @('databaseWritesPerformed','writerLoginAttempted','actionExecutionEnabled')){if($Route.$field -isnot [bool] -or $Route.$field){throw 'ACCESS_ROUTE_UNSAFE'}}
    foreach($field in @('clientAddress','serverAddress')){$address=$null;if(-not [Net.IPAddress]::TryParse([string]$Route.$field,[ref]$address)){throw 'ACCESS_ROUTE_ADDRESS_INVALID'}}
}
function Get-PaperAccessFindings($Inventory,$Firewall,$Route) {
    $findings=[Collections.Generic.List[string]]::new()
    $findings.Add('WRITER_CREDENTIAL_AND_CROSS_DATABASE_RESTRICTION_STILL_REQUIRED')
    if($Firewall.status -cne 'METADATA_CAPTURED_REVIEW_REQUIRED' -or $Firewall.truncated){$findings.Add('FIREWALL_EVIDENCE_INCOMPLETE')}
    foreach($profile in @($Firewall.profiles)){
        if([string]$profile.Enabled -notin @('True','1') -or [string]$profile.DefaultInboundAction -notin @('Block','4')){$findings.Add('FIREWALL_PROFILE_REQUIRES_REVIEW');break}
    }
    if(@($Firewall.profiles).Count -ne 3){$findings.Add('FIREWALL_PROFILE_SET_UNEXPECTED')}
    if(@($Firewall.rules|Where-Object {$_.action -ceq 'Allow'}).Count){$findings.Add('POSTGRES_PORT_CANDIDATE_ALLOW_RULES_REQUIRE_SCOPE_REVIEW')}
    foreach($rule in @($Inventory.hbaRules)){
        if($rule.hasError -or $rule.optionsPresent){$findings.Add('HBA_ERROR_OR_OPTIONS_REQUIRE_REVIEW');continue}
        if($rule.type -ceq 'local' -or $rule.authMethod -ceq 'reject'){continue}
        $loopback=($rule.address -ceq '127.0.0.1' -and $rule.netmask -ceq '255.255.255.255') -or
                  ($rule.address -ceq '::1' -and $rule.netmask -ceq 'ffff:ffff:ffff:ffff:ffff:ffff:ffff:ffff')
        if(-not $loopback){$findings.Add('NON_LOOPBACK_OR_COMPLEX_HBA_ALLOW_REQUIRES_REVIEW')}
        if($rule.authMethod -cne 'scram-sha-256'){$findings.Add('NON_SCRAM_AUTHENTICATION_REQUIRES_REVIEW')}
    }
    if($Route.clientAddress -notin @('127.0.0.1','::1')){$findings.Add('APPLICATION_SOURCE_NOT_LOOPBACK_REVIEW_EXACT_HBA_SCOPE')}
    return @($findings.ToArray()|Select-Object -Unique)
}
