# Definitions and fixed contracts only.
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
