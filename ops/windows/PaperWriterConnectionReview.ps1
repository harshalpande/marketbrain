# Definitions only. Reuse the accepted native psql deadline and credential-handling boundary.
function Assert-PaperInstalledReport($Saved) {
    if($Saved.version -cne 'PAPER_WRITER_INSTALL_BUNDLE_V1' -or
       $Saved.status -cne 'STAGED_WRITER_VERIFIED_LOGIN_AND_ACTIONS_DISABLED' -or
       $Saved.commitOutcome -cne 'COMMITTED_AND_VERIFIED' -or $Saved.failure -or $Saved.failureCode){throw 'A successful committed installation report is required.'}
    foreach($flag in @('backupConfirmed','maintenanceConfirmed','targetConfirmed','rolesApproved','rehearsalRollbackVerified','applyRequested','applyAttempted')) {
        if($Saved.$flag -isnot [bool] -or -not $Saved.$flag){throw 'Installation acceptance flag missing.'}
    }
    foreach($flag in @('applicationWriterActivated','actionExecutionEnabled','credentialsSaved')) {
        if($Saved.$flag -isnot [bool] -or $Saved.$flag){throw 'Installation safety flag invalid.'}
    }
    Assert-PaperWriterInstallPlan $Saved.plan
    if($Saved.target.host -cne '127.0.0.1' -or $Saved.target.database -cne $Saved.plan.plan.database -or
       ($Saved.target.port -isnot [int] -and $Saved.target.port -isnot [long]) -or $Saved.target.port -lt 1 -or $Saved.target.port -gt 65535){throw 'Invalid installation target.'}
    $phases=@('Plan','Rehearse','Plan','Apply','Verify')
    if(@($Saved.steps).Count -ne 5){throw 'Incomplete installation stages.'}
    for($i=0;$i -lt 5;$i++) {
        $s=$Saved.steps[$i]
        if($s.phase -cne $phases[$i] -or $s.exitCode -isnot [int] -or $s.exitCode -ne 0 -or $s.timedOut -isnot [bool] -or $s.timedOut){throw 'Installation stage failed.'}
    }
    Assert-PaperWriterInstallReceipt $Saved.rehearsal 'Rehearse' $Saved.plan.planHash
    Assert-PaperWriterInstallReceipt $Saved.applyReceipt 'Apply' $Saved.plan.planHash
    Assert-PaperWriterInstallReceipt $Saved.verification 'Verify' $Saved.plan.planHash
}
function New-PaperConnectionReviewSql($Envelope) {
    $verify=New-PaperWriterInstallSql 'Verify' $Envelope
    if(-not $verify.EndsWith('ROLLBACK;')){throw 'Unexpected verification boundary.'}
    $inventory=[IO.File]::ReadAllText((Join-Path $PSScriptRoot '../../marketbrain-service/src/main/resources/paper/writer-connection-review-v1.sql'))
    # Fresh permission assertion and inventory in one read-only repeatable-read transaction.
    return $verify.Substring(0,$verify.Length-9).Replace('SET TRANSACTION READ ONLY;','SET TRANSACTION ISOLATION LEVEL REPEATABLE READ, READ ONLY;')+"`n"+$inventory+"`nROLLBACK;"
}
function Assert-PaperConnectionReview($Review,$Envelope,[int]$Port) {
    foreach($field in @('serverPort','serverVersion')){if($Review.$field -isnot [int] -and $Review.$field -isnot [long]){throw 'Invalid server metadata type.'}}
    if($Review.version -cne 'PAPER_WRITER_CONNECTION_REVIEW_V1' -or $Review.database -cne $Envelope.plan.database -or
       $Review.databaseOid -cne $Envelope.plan.databaseOid -or $Review.clusterId -cne $Envelope.plan.clusterId -or
       $Review.serverPort -ne $Port -or $Review.serverVersion -lt 180000 -or $Review.serverVersion -ge 190000 -or
       $Review.hbaEvidence -cne 'CURRENT_FILE_NOT_PROOF_OF_LOADED_RULES_OR_CLIENT_ROUTE'){throw 'Connection inventory identity mismatch.'}
    if($Review.adminSuperuser -isnot [bool] -or -not $Review.adminSuperuser){throw 'Administrator inspection required.'}
    foreach($flag in @('writerLoginEnabled','databaseWritesPerformed','credentialsSaved','applicationWriterActivated','actionExecutionEnabled')) {
        if($Review.$flag -isnot [bool] -or $Review.$flag){throw 'Connection inventory safety mismatch.'}
    }
    $dbs=@($Review.databases);$rules=@($Review.hbaRules)
    if($dbs.Count -lt 1 -or $dbs.Count -gt 128 -or $rules.Count -lt 1 -or $rules.Count -gt 256){throw 'Inventory bounds exceeded or empty; manual review required.'}
    if(@($dbs|Select-Object -ExpandProperty oid -Unique).Count -ne $dbs.Count -or
       @($dbs|Where-Object {$_.name -ceq $Envelope.plan.database -and $_.oid -ceq $Envelope.plan.databaseOid}).Count -ne 1){throw 'Incomplete database identity inventory.'}
    foreach($db in $dbs){foreach($flag in @('allowsConnections','template','writerConnect','writerCreate','writerTemp')){if($db.$flag -isnot [bool]){throw 'Invalid database permission flag.'}}}
    foreach($rule in $rules){
        foreach($flag in @('optionsPresent','hasError')){if($rule.$flag -isnot [bool]){throw 'Invalid HBA metadata flag.'}}
        if(-not $rule.hasError -and (($rule.ruleNumber -isnot [int] -and $rule.ruleNumber -isnot [long]) -or $rule.ruleNumber -lt 1 -or -not $rule.authMethod)){throw 'Incomplete valid HBA rule.'}
    }
}
function Get-PaperConnectionFindings($Review) {
    $findings=@('CREDENTIAL_CUSTODY_NOT_IMPLEMENTED','APPLICATION_CLIENT_ROUTE_UNVERIFIED','LOGIN_AND_APPLICATION_ACTIVATION_NOT_AUTHORIZED_BY_REPORT')
    if(@($Review.databases|Where-Object {$_.name -cne $Review.database -and $_.allowsConnections -and $_.writerConnect}).Count){$findings+='OTHER_DATABASE_CONNECT_ACL_REQUIRES_REVIEW'}
    if(@($Review.databases|Where-Object {$_.writerCreate -or $_.writerTemp}).Count){$findings+='CROSS_DATABASE_CREATE_OR_TEMP_ACL_REQUIRES_REVIEW'}
    if(@($Review.hbaRules|Where-Object {$_.hasError}).Count){$findings+='HBA_FILE_PARSE_ERRORS'}
    if(@($Review.hbaRules|Where-Object {$_.authMethod -ceq 'trust'}).Count){$findings+='HBA_TRUST_RULE_PRESENT_REVIEW_APPLICABILITY'}
    if(@($Review.hbaRules|Where-Object {$_.optionsPresent}).Count){$findings+='HBA_OPTIONS_WITHHELD_REVIEW_LOCALLY'}
    if($Review.passwordEncryption -cne 'scram-sha-256'){$findings+='PASSWORD_ENCRYPTION_POLICY_REQUIRES_REVIEW'}
    if($Review.ssl -cne 'on'){$findings+='TRANSPORT_PROTECTION_REQUIRES_REVIEW'}
    return $findings
}
