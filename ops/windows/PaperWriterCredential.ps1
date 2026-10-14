# Definitions only. No database contact or credential creation on import.
. (Join-Path $PSScriptRoot 'PaperWriterCustody.ps1')
. (Join-Path $PSScriptRoot 'PaperWriterHbaStage.ps1')
. (Join-Path $PSScriptRoot 'PaperWriterInstallation.ps1')
. (Join-Path $PSScriptRoot 'PaperWriterConnectionReview.ps1')

function Get-PaperCredentialEntropy($Saved) {
    Assert-PaperInstalledReport $Saved
    $identity='PAPER_WRITER_CREDENTIAL_V1|{0}|{1}|{2}|{3}|{4}' -f $Saved.plan.planHash,$Saved.target.database,$Saved.target.port,$Saved.plan.plan.databaseOid,$Saved.plan.plan.clusterId
    return ,[Text.Encoding]::UTF8.GetBytes($identity)
}
function Read-PaperCredential([string]$Path,[byte[]]$Entropy) {
    $full=Assert-PaperCustodyPath $Path
    Assert-PaperPrivateAcl ([IO.Path]::GetDirectoryName($full)); Assert-PaperPrivateAcl $full
    $cipher=$null;$plain=$null
    try {
        $stream=[IO.File]::Open($full,'Open','Read','Read')
        try {
            if($stream.Length -lt 64 -or $stream.Length -gt 4096){throw 'CREDENTIAL_ENVELOPE_SIZE'}
            $cipher=New-Object byte[] ([int]$stream.Length);$offset=0
            while($offset -lt $cipher.Length){$n=$stream.Read($cipher,$offset,$cipher.Length-$offset);if($n -eq 0){throw 'CREDENTIAL_TRUNCATED'};$offset+=$n}
        } finally {$stream.Dispose()}
        $plain=[Security.Cryptography.ProtectedData]::Unprotect($cipher,$Entropy,[Security.Cryptography.DataProtectionScope]::CurrentUser)
        # 32 random password bytes (encoded as 64 hex characters by the client), then 16 independent salt bytes.
        if($plain.Length -ne 48){[Array]::Clear($plain,0,$plain.Length);throw 'CREDENTIAL_PAYLOAD_SIZE'}
        return ,$plain
    } finally {if($cipher){[Array]::Clear($cipher,0,$cipher.Length)}}
}
function Save-PaperCredential([string]$Path,[byte[]]$Payload,[byte[]]$Entropy) {
    $full=Assert-PaperCustodyPath $Path
    Assert-PaperPrivateAcl ([IO.Path]::GetDirectoryName($full))
    if($null -eq $Payload -or $Payload.Length -ne 48){throw 'CREDENTIAL_PAYLOAD_SIZE'}
    $cipher=$null
    try {
        $cipher=[Security.Cryptography.ProtectedData]::Protect($Payload,$Entropy,[Security.Cryptography.DataProtectionScope]::CurrentUser)
        # CreateNew never overwrites. A partial file is retained and rejected, not silently regenerated.
        $stream=[IO.File]::Open($full,'CreateNew','Write','None')
        try {$stream.Write($cipher,0,$cipher.Length);$stream.Flush($true)} finally {$stream.Dispose()}
        Protect-PaperHbaBackupAcl $full
    } finally {if($cipher){[Array]::Clear($cipher,0,$cipher.Length)}}
}
function New-PaperCredentialVerifier([byte[]]$Payload) {
    if($null -eq $Payload -or $Payload.Length -ne 48){throw 'CREDENTIAL_PAYLOAD_SIZE'}
    $password=$null;$salt=$null;$salted=$null;$client=$null;$stored=$null;$server=$null;$pbkdf=$null;$hmac=$null;$hash=$null
    try {
        $password=[Text.Encoding]::ASCII.GetBytes(([BitConverter]::ToString($Payload,0,32)).Replace('-','').ToLowerInvariant())
        $salt=New-Object byte[] 16;[Array]::Copy($Payload,32,$salt,0,16)
        $pbkdf=[Security.Cryptography.Rfc2898DeriveBytes]::new($password,$salt,4096,[Security.Cryptography.HashAlgorithmName]::SHA256)
        $salted=$pbkdf.GetBytes(32);$hmac=[Security.Cryptography.HMACSHA256]::new($salted)
        $client=$hmac.ComputeHash([Text.Encoding]::ASCII.GetBytes('Client Key'))
        $server=$hmac.ComputeHash([Text.Encoding]::ASCII.GetBytes('Server Key'))
        $hash=[Security.Cryptography.SHA256]::Create();$stored=$hash.ComputeHash($client)
        return 'SCRAM-SHA-256$4096:'+ [Convert]::ToBase64String($salt)+'$'+[Convert]::ToBase64String($stored)+':'+[Convert]::ToBase64String($server)
    } finally {
        foreach($buffer in @($password,$salt,$salted,$client,$stored,$server)){if($null -ne $buffer){[Array]::Clear($buffer,0,$buffer.Length)}}
        foreach($resource in @($pbkdf,$hmac,$hash)){if($resource){$resource.Dispose()}}
    }
}
function New-PaperCredentialSql([ValidateSet('Inspect','Rehearse','Stage','Verify')][string]$Phase,$Envelope,[string]$Verifier) {
    if($Verifier -cnotmatch '^SCRAM-SHA-256\$4096:[A-Za-z0-9+/]{22}==\$[A-Za-z0-9+/]{43}=:[A-Za-z0-9+/]{43}=$'){throw 'CREDENTIAL_VERIFIER_FORMAT'}
    $verify=New-PaperWriterInstallSql 'Verify' $Envelope
    $marker="SELECT jsonb_build_object('version','PAPER_WRITER_INSTALL_CHECK_V1'"
    $index=$verify.LastIndexOf($marker,[StringComparison]::Ordinal)
    if($index -lt 0 -or -not $verify.EndsWith('ROLLBACK;')){throw 'CREDENTIAL_VERIFICATION_TEMPLATE'}
    $prefix=$verify.Substring(0,$index)
    if($Phase -cin @('Rehearse','Stage')){$prefix=$prefix.Replace('SET TRANSACTION READ ONLY;','')}
    # Preserve installed target/role/function/permission guards. No table scans or account writes.
    $body=@'
DO $credential$
DECLARE current_secret text; target_oid oid;
BEGIN
 IF NOT (SELECT rolsuper FROM pg_catalog.pg_roles WHERE rolname=current_user) THEN RAISE EXCEPTION 'Credential administrator required'; END IF;
 IF NOT pg_catalog.pg_try_advisory_xact_lock(1987654321,14) THEN RAISE EXCEPTION 'Credential operation already running'; END IF;
 SELECT oid,rolpassword INTO STRICT target_oid,current_secret FROM pg_catalog.pg_authid WHERE rolname='marketbrain_paper_review_writer';
 IF EXISTS (SELECT 1 FROM pg_catalog.pg_stat_activity WHERE usesysid=target_oid) THEN RAISE EXCEPTION 'Writer sessions must be absent'; END IF;
 IF current_secret IS NOT NULL AND current_secret IS DISTINCT FROM '__VERIFIER__' THEN RAISE EXCEPTION 'Existing credential differs preserve custody'; END IF;
 __MUTATION__
END $credential$;
SELECT jsonb_build_object('version','PAPER_WRITER_CREDENTIAL_CHECK_V1','phase','__PHASE__',
 'planHash','__PLAN_HASH__','state',(SELECT CASE WHEN rolpassword IS NULL THEN 'MISSING' WHEN rolpassword='__VERIFIER__' THEN 'MATCH' ELSE 'OTHER' END FROM pg_catalog.pg_authid WHERE rolname='marketbrain_paper_review_writer'),
 'writerLoginEnabled',(SELECT rolcanlogin FROM pg_catalog.pg_roles WHERE rolname='marketbrain_paper_review_writer'),
 'helperLoginEnabled',(SELECT rolcanlogin FROM pg_catalog.pg_roles WHERE rolname='marketbrain_paper_review_helper'),
 'accountRowsWritten',false,'applicationWriterActivated',false,'actionExecutionEnabled',false);
'@
    $mutation=if($Phase -cin @('Rehearse','Stage')){"IF current_secret IS NULL THEN ALTER ROLE marketbrain_paper_review_writer NOLOGIN PASSWORD '__VERIFIER__'; END IF;"}else{''}
    $body=$body.Replace('__MUTATION__',$mutation).Replace('__VERIFIER__',$Verifier).Replace('__PHASE__',$Phase).Replace('__PLAN_HASH__',$Envelope.planHash)
    return $prefix+$body+$(if($Phase -ceq 'Stage'){"`nCOMMIT;"}else{"`nROLLBACK;"})
}
function Assert-PaperCredentialReceipt($Value,[string]$Phase,[string]$PlanHash) {
    if($Value.version -cne 'PAPER_WRITER_CREDENTIAL_CHECK_V1' -or $Value.phase -cne $Phase -or $Value.planHash -cne $PlanHash -or $Value.state -cnotin @('MISSING','MATCH')){throw 'CREDENTIAL_RECEIPT_IDENTITY'}
    foreach($flag in @('writerLoginEnabled','helperLoginEnabled','accountRowsWritten','applicationWriterActivated','actionExecutionEnabled')){
        if($Value.$flag -isnot [bool] -or $Value.$flag){throw 'CREDENTIAL_RECEIPT_UNSAFE'}
    }
    if($Phase -cin @('Rehearse','Stage','Verify') -and $Value.state -cne 'MATCH'){throw 'CREDENTIAL_NOT_VERIFIED'}
}
function Invoke-PaperCredentialSequence([scriptblock]$Execute,[string]$PlanHash,[switch]$VerifyOnly) {
    # Execute must validate native exit/deadline before returning a parsed receipt.
    $initial=& $Execute 'Inspect'; Assert-PaperCredentialReceipt $initial 'Inspect' $PlanHash
    if($initial.state -ceq 'MATCH'){return 'EXISTING_CREDENTIAL_VERIFIED_NO_CHANGE'}
    if($VerifyOnly){throw 'CREDENTIAL_MISSING_STAGE_REQUIRED'}
    $rehearsal=& $Execute 'Rehearse'; Assert-PaperCredentialReceipt $rehearsal 'Rehearse' $PlanHash
    $rollback=& $Execute 'Inspect'; Assert-PaperCredentialReceipt $rollback 'Inspect' $PlanHash
    if($rollback.state -cne 'MISSING'){throw 'CREDENTIAL_ROLLBACK_NOT_PROVEN'}
    $applied=& $Execute 'Stage'; Assert-PaperCredentialReceipt $applied 'Stage' $PlanHash
    $readback=& $Execute 'Verify'; Assert-PaperCredentialReceipt $readback 'Verify' $PlanHash
    return 'CREDENTIAL_COMMITTED_AND_VERIFIED'
}
