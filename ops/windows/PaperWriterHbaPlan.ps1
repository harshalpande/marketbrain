# Pure contracts and bounded read-only local-file observation. No apply operation.
function Read-PaperHbaPreparation([string]$Path) {
    if((Get-Item -LiteralPath $Path).Length -gt 2MB){throw 'HBA_PLAN_EVIDENCE_SIZE'}
    $bytes=[IO.File]::ReadAllBytes($Path)
    if((Get-PaperRestrictionHash $bytes) -cne '9B1B2C9E4B3D87F8C7F6D37BD2C8798AF637A7406AB11A42DF23A841BCA9000E'){throw 'HBA_PLAN_EVIDENCE_HASH_MISMATCH'}
    $v=[Text.Encoding]::UTF8.GetString($bytes).TrimStart([char]0xFEFF)|ConvertFrom-Json
    if($v.status -cne 'PREPARATION_CAPTURED_STAGING_BLOCKED' -or $v.failureCode -or $v.tests.checkCount -ne 40 -or $v.tests.status -cne 'PASSED' -or -not $v.tests.fixtureCleanupComplete -or -not $v.firewallScope.currentCandidatesCollected -or -not $v.firewallScope.ruleSetStableAtEnd){throw 'HBA_PLAN_PREPARATION_INCOMPLETE'}
    foreach($flag in @('databaseContacted','databaseWritesPerformed','realHbaRead','hbaChanged','firewallChanged','writerLoginAttempted','credentialsCreated','applicationWriterActivated','actionExecutionEnabled')){
        if($v.$flag -isnot [bool] -or $v.$flag){throw 'HBA_PLAN_EVIDENCE_UNSAFE'}
    }
    return $v
}
function New-PaperHbaMetadataSql {
    # Fixed catalog/file metadata, one row, no table scans or dynamic SQL. File read capped at 1MB+1.
    return @'
BEGIN READ ONLY;
SET LOCAL statement_timeout='10s';
SET LOCAL lock_timeout='2s';
SET LOCAL search_path=pg_catalog;
WITH f AS MATERIALIZED (
 SELECT current_setting('hba_file') AS path,
        pg_read_binary_file(current_setting('hba_file'),0,1048577) AS bytes
), h AS MATERIALIZED (SELECT error FROM pg_hba_file_rules LIMIT 257)
SELECT jsonb_build_object(
 'version','PAPER_HBA_METADATA_V1',
 'database',current_database(),
 'databaseOid',(SELECT oid::text FROM pg_database WHERE datname=current_database()),
 'clusterId',(SELECT system_identifier::text FROM pg_control_system()),
 'serverPort',current_setting('port')::int,
 'serverVersion',current_setting('server_version_num')::int,
 'serverStartEpoch',extract(epoch FROM pg_postmaster_start_time())::text,
 'adminSuperuser',(SELECT rolsuper FROM pg_roles WHERE rolname=current_user),
 'writerCount',(SELECT count(*) FROM pg_roles WHERE rolname='marketbrain_paper_review_writer'),
 'writerLoginEnabled',(SELECT rolcanlogin FROM pg_roles WHERE rolname='marketbrain_paper_review_writer'),
 'hbaPath',f.path,'hbaBytes',octet_length(f.bytes),'hbaHash',upper(encode(sha256(f.bytes),'hex')),
 'hbaRuleCount',(SELECT count(*) FROM h),'hbaErrorCount',(SELECT count(*) FROM h WHERE error IS NOT NULL),
 'readOnly',current_setting('transaction_read_only')='on'
) FROM f;
ROLLBACK;
'@
}
function Assert-PaperHbaMetadata($Value) {
    if($Value.version -cne 'PAPER_HBA_METADATA_V1' -or $Value.database -cne 'marketbrain' -or $Value.databaseOid -cne '16389' -or $Value.clusterId -cne '7679149914381758260' -or $Value.serverPort -ne 5432){throw 'HBA_PLAN_DATABASE_IDENTITY_MISMATCH'}
    foreach($field in @('serverPort','serverVersion','writerCount','hbaBytes','hbaRuleCount','hbaErrorCount')){if($Value.$field -isnot [int] -and $Value.$field -isnot [long]){throw 'HBA_PLAN_METADATA_TYPE_INVALID'}}
    if($Value.serverVersion -lt 180000 -or $Value.serverVersion -ge 190000 -or $Value.serverStartEpoch -cnotmatch '^[0-9]{1,12}\.[0-9]{1,6}$'){throw 'HBA_PLAN_SERVER_UNSUPPORTED'}
    foreach($field in @('adminSuperuser','readOnly')){if($Value.$field -isnot [bool] -or -not $Value.$field){throw 'HBA_PLAN_READ_ONLY_ADMIN_REQUIRED'}}
    if($Value.writerCount -ne 1 -or $Value.writerLoginEnabled -isnot [bool] -or $Value.writerLoginEnabled){throw 'HBA_PLAN_WRITER_NOT_DISABLED'}
    if($Value.hbaBytes -lt 1 -or $Value.hbaBytes -gt 1MB -or $Value.hbaHash -cnotmatch '^[A-F0-9]{64}$' -or $Value.hbaRuleCount -lt 1 -or $Value.hbaRuleCount -gt 256 -or $Value.hbaErrorCount -ne 0){throw 'HBA_PLAN_FILE_METADATA_INVALID'}
    if($Value.hbaPath -isnot [string] -or $Value.hbaPath.Length -gt 1024){throw 'HBA_PLAN_FILE_PATH_INVALID'}
}
function Assert-PaperHbaRoute($Route,$Metadata,[string]$RunId){
    Assert-PaperApplicationRoute $Route $Metadata $Metadata $RunId
    if($Route.applicationUser -cne 'marketbrain_app' -or $Route.clientAddress -cne '127.0.0.1' -or $Route.serverAddress -cne '127.0.0.1'){throw 'HBA_PLAN_APPLICATION_ROUTE_CHANGED'}
}
function New-PaperHbaFilePlan([byte[]]$Bytes,$Metadata,[string]$AclSddl){
    Assert-PaperHbaMetadata $Metadata
    if($Bytes.Length -ne $Metadata.hbaBytes -or (Get-PaperRestrictionHash $Bytes) -cne $Metadata.hbaHash){throw 'HBA_PLAN_LOCAL_SERVER_FILE_MISMATCH'}
    if([string]::IsNullOrWhiteSpace($AclSddl) -or $AclSddl.Length -gt 65536){throw 'HBA_PLAN_ACL_UNAVAILABLE'}
    $candidate=New-PaperRestrictionCandidate $Bytes $Metadata.hbaHash
    # The only disclosed diff is our fixed prefix. Existing comments/content never leave memory.
    return [pscustomobject]@{
        version='PAPER_HBA_FILE_PLAN_V1';originalHash=$Metadata.hbaHash;originalBytes=$Bytes.Length
        candidateHash=(Get-PaperRestrictionHash $candidate);candidateBytes=$candidate.Length
        aclFingerprint=(Get-PaperRestrictionHash ([Text.Encoding]::UTF8.GetBytes($AclSddl)))
        addedBlock=(New-PaperWriterRestrictionBlock);existingBytesPreserved=$true
        applyImplemented=$false;hbaChanged=$false;backupCreated=$false;writerLoginEnabled=$false
        findings=@('REAL_REPLACEMENT_AND_ACL_PRESERVATION_NOT_TESTED','PROTECTED_BACKUP_AND_RECOVERY_REQUIRED','FIREWALL_EFFECTIVE_ACCESS_UNPROVEN','PLAN_EXPIRES_ON_FILE_ACL_ROUTE_OR_SERVER_DRIFT')
    }
}
function Read-PaperHbaLocalPlan($Metadata){
    Assert-PaperHbaMetadata $Metadata
    $path=Assert-PaperCustodyPath ($Metadata.hbaPath.Replace('/','\'))
    if([IO.Path]::GetFileName($path) -ine 'pg_hba.conf' -or -not(Test-Path -LiteralPath $path -PathType Leaf)){throw 'HBA_PLAN_FILE_PATH_INVALID'}
    $stream=[IO.File]::Open($path,[IO.FileMode]::Open,[IO.FileAccess]::Read,[IO.FileShare]::Read)
    try {
        if($stream.Length -lt 1 -or $stream.Length -gt 1MB){throw 'HBA_PLAN_LOCAL_FILE_SIZE'}
        $bytes=New-Object byte[] ([int]$stream.Length);$offset=0
        while($offset -lt $bytes.Length){$n=$stream.Read($bytes,$offset,$bytes.Length-$offset);if($n -eq 0){throw 'HBA_PLAN_FILE_READ_INCOMPLETE'};$offset+=$n}
        $acl=Get-Acl -LiteralPath $path
        $sddl=$acl.GetSecurityDescriptorSddlForm([Security.AccessControl.AccessControlSections]'Owner,Group,Access')
        return New-PaperHbaFilePlan $bytes $Metadata $sddl
    } finally {$stream.Dispose()}
}
