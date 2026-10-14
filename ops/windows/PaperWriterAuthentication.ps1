# Definitions only. Import never opens a connection or changes a role.
. (Join-Path $PSScriptRoot 'PaperWriterCredential.ps1')

function New-PaperAuthenticationSql([ValidateSet('Lease','Revoke','Drain','Readback')][string]$Phase,$Envelope,[string]$Verifier,[string]$RunId) {
    if($RunId -cnotmatch '^[a-f0-9]{32}$'){throw 'AUTH_RUN_ID_INVALID'}
    # This also validates the plan, verifier and installed verification template before any interpolation.
    $full=New-PaperCredentialSql 'Verify' $Envelope $Verifier
    $original='MarketBrain staged writer v1 '+$Envelope.planHash
    $leased='MarketBrain authentication lease v1 '+$RunId+' '+$Envelope.planHash
    $prefix="BEGIN; SET LOCAL statement_timeout='15s'; SET LOCAL lock_timeout='3s'; SET LOCAL idle_in_transaction_session_timeout='20s'; SET LOCAL search_path=pg_catalog; SET LOCAL standard_conforming_strings=on;`n"
    if($Phase -ceq 'Lease') {
        $index=$full.LastIndexOf("SELECT jsonb_build_object('version','PAPER_WRITER_CREDENTIAL_CHECK_V1'",[StringComparison]::Ordinal)
        if($index -lt 0){throw 'AUTH_SQL_TEMPLATE_INVALID'}
        $prefix=$full.Substring(0,$index).Replace('SET TRANSACTION READ ONLY;','')
    }
    # Revoke deliberately does NOT depend on the large grant/HBA check: drift must not prevent disabling login.
    # Role-comment ownership + target + unchanged secret prevent reverting an unrelated activation.
    $guard=@'
DO $auth$
DECLARE r record; marker text; hba bytea;
BEGIN
 IF NOT (SELECT rolsuper FROM pg_catalog.pg_roles WHERE rolname=current_user) THEN RAISE EXCEPTION 'Authentication administrator required'; END IF;
 IF current_database()<>'__DATABASE__' OR (SELECT oid::text FROM pg_catalog.pg_database WHERE datname=current_database())<>'__OID__'
 OR (SELECT system_identifier::text FROM pg_catalog.pg_control_system())<>'__CLUSTER__' OR current_setting('port')<>'5432' THEN RAISE EXCEPTION 'Authentication target mismatch'; END IF;
 IF NOT pg_catalog.pg_try_advisory_xact_lock(1987654321,14) THEN RAISE EXCEPTION 'Authentication operation already running'; END IF;
 SELECT * INTO STRICT r FROM pg_catalog.pg_authid WHERE rolname='marketbrain_paper_review_writer';
 marker:=pg_catalog.shobj_description(r.oid,'pg_authid');
 IF r.rolpassword IS DISTINCT FROM '__VERIFIER__' THEN RAISE EXCEPTION 'Authentication credential changed'; END IF;
 __CHECK__
 __MUTATION__
END $auth$;
'@
    $check="IF marker IS DISTINCT FROM '__LEASED__' AND NOT (marker='__ORIGINAL__' AND NOT r.rolcanlogin) THEN RAISE EXCEPTION 'Authentication lease ownership mismatch'; END IF;"
    $mutation=''
    if($Phase -ceq 'Lease') {
        $check=@'
 IF marker IS DISTINCT FROM '__ORIGINAL__' OR r.rolcanlogin OR (r.rolvaliduntil IS NOT NULL AND r.rolvaliduntil<>'infinity'::timestamptz) THEN RAISE EXCEPTION 'Authentication initial role state changed'; END IF;
 hba:=pg_catalog.pg_read_binary_file(current_setting('hba_file'),0,1048577);
 IF octet_length(hba)>1048576 OR upper(encode(sha256(hba),'hex'))<>'A74AAF33772B93982AF6A0C1EDBC3024469CA7DA0FAE6AE6DFC75B0970664F39'
 OR EXISTS(SELECT 1 FROM pg_catalog.pg_hba_file_rules WHERE error IS NOT NULL) THEN RAISE EXCEPTION 'Authentication HBA drift'; END IF;
'@
        $mutation="EXECUTE format('ALTER ROLE marketbrain_paper_review_writer LOGIN VALID UNTIL %L',(clock_timestamp()+interval '120 seconds')::text); COMMENT ON ROLE marketbrain_paper_review_writer IS '__LEASED__';"
    } elseif($Phase -ceq 'Revoke') {
        $mutation="ALTER ROLE marketbrain_paper_review_writer NOLOGIN VALID UNTIL 'infinity'; COMMENT ON ROLE marketbrain_paper_review_writer IS '__ORIGINAL__';"
    } else {
        $check+="`nIF r.rolcanlogin OR marker IS DISTINCT FROM '__ORIGINAL__' THEN RAISE EXCEPTION 'Authentication revocation not complete'; END IF;"
        if($Phase -ceq 'Drain') {
            # NOLOGIN is already durably committed. Drain only this exact dedicated role, never application/admin sessions.
            $mutation="IF (SELECT count(*) FROM pg_catalog.pg_stat_activity WHERE usesysid=r.oid)>8 THEN RAISE EXCEPTION 'Authentication session bound exceeded'; END IF; PERFORM pg_catalog.pg_terminate_backend(pid,5000) FROM pg_catalog.pg_stat_activity WHERE usesysid=r.oid;"
        } else {
            $check+="`nIF EXISTS(SELECT 1 FROM pg_catalog.pg_stat_activity WHERE usesysid=r.oid) THEN RAISE EXCEPTION 'Authentication sessions remain'; END IF;"
        }
    }
    $guard=$guard.Replace('__CHECK__',$check).Replace('__MUTATION__',$mutation).Replace('__ORIGINAL__',$original).Replace('__LEASED__',$leased).Replace('__VERIFIER__',$Verifier).Replace('__DATABASE__',$Envelope.plan.database).Replace('__OID__',$Envelope.plan.databaseOid).Replace('__CLUSTER__',$Envelope.plan.clusterId)
    # Receipt after COMMIT: a missing/failed receipt is unknown, never assumed to be rollback.
    $receipt=@'
SELECT jsonb_build_object('version','PAPER_WRITER_AUTH_DB_V1','phase','__PHASE__','runId','__RUN_ID__',
 'writerLoginEnabled',(SELECT rolcanlogin FROM pg_catalog.pg_roles WHERE rolname='marketbrain_paper_review_writer'),
 'helperLoginEnabled',(SELECT rolcanlogin FROM pg_catalog.pg_roles WHERE rolname='marketbrain_paper_review_helper'),
 'writerSessions',(SELECT count(*) FROM pg_catalog.pg_stat_activity WHERE usename='marketbrain_paper_review_writer'),
 'leaseSecondsRemaining',(SELECT CASE WHEN rolcanlogin THEN extract(epoch FROM rolvaliduntil-clock_timestamp()) ELSE 0 END FROM pg_catalog.pg_authid WHERE rolname='marketbrain_paper_review_writer'),
 'serverStartEpoch',extract(epoch FROM pg_catalog.pg_postmaster_start_time())::text,
 'accountRowsWritten',false,'applicationWriterActivated',false,'actionExecutionEnabled',false);
'@
    return $prefix+$guard+"`nCOMMIT;`n"+$receipt.Replace('__PHASE__',$Phase).Replace('__RUN_ID__',$RunId)
}
function Assert-PaperAuthenticationReceipt($Value,[string]$Phase,[string]$RunId) {
    if($Value.version -cne 'PAPER_WRITER_AUTH_DB_V1' -or $Value.phase -cne $Phase -or $Value.runId -cne $RunId -or $Value.serverStartEpoch -cnotmatch '^[0-9]{1,12}\.[0-9]{1,6}$'){throw 'AUTH_RECEIPT_IDENTITY'}
    foreach($flag in @('helperLoginEnabled','accountRowsWritten','applicationWriterActivated','actionExecutionEnabled')){if($Value.$flag -isnot [bool] -or $Value.$flag){throw 'AUTH_RECEIPT_UNSAFE'}}
    if($Value.writerLoginEnabled -isnot [bool] -or $Value.writerLoginEnabled -ne ($Phase -ceq 'Lease')){throw 'AUTH_LOGIN_STATE_INVALID'}
    if($Phase -ceq 'Lease' -and (($Value.leaseSecondsRemaining -isnot [double] -and $Value.leaseSecondsRemaining -isnot [decimal] -and $Value.leaseSecondsRemaining -isnot [long] -and $Value.leaseSecondsRemaining -isnot [int]) -or $Value.leaseSecondsRemaining -le 60 -or $Value.leaseSecondsRemaining -gt 120)){throw 'AUTH_LEASE_EXPIRY_INVALID'}
    if(($Value.writerSessions -isnot [int] -and $Value.writerSessions -isnot [long]) -or $Value.writerSessions -lt 0 -or ($Phase -ceq 'Readback' -and $Value.writerSessions -ne 0)){throw 'AUTH_SESSION_STATE_INVALID'}
}
function Assert-PaperAuthenticationProbe($Value,[string]$Phase,[string]$RunId) {
    if($Value.version -cne 'PAPER_WRITER_AUTH_PROBE_V1' -or $Value.phase -cne $Phase -or $Value.runId -cne $RunId -or $Value.status -cne 'PASSED' -or $Value.connectorSha256 -cnotmatch '^[a-f0-9]{64}$' -or $Value.driverSha256 -cnotmatch '^[a-f0-9]{64}$'){throw 'AUTH_PROBE_INVALID'}
    foreach($flag in @('accountRowsWritten','applicationWriterActivated','actionExecutionEnabled')){if($Value.$flag -isnot [bool] -or $Value.$flag){throw 'AUTH_PROBE_UNSAFE'}}
}
function Invoke-PaperAuthenticationWindow([scriptblock]$Checkpoint,[scriptblock]$Lease,[scriptblock]$Probe,[scriptblock]$Revoke,[scriptblock]$Drain,[scriptblock]$Readback) {
    # Checkpoint MUST durably succeed before LOGIN can be attempted. Finally also covers an unknown lease commit.
    & $Checkpoint
    try { & $Lease; & $Probe }
    finally { & $Revoke; & $Drain; & $Readback }
}
function Invoke-PaperAuthenticationProcess([string]$Executable,[string[]]$Arguments,[string]$WorkingDirectory,[byte[]]$InputBytes,[int]$LimitSeconds=55) {
    if($null -eq $InputBytes -or $InputBytes.Length -ne 64 -or $LimitSeconds -lt 1 -or $LimitSeconds -gt 55){throw 'AUTH_PROCESS_INPUT_INVALID'}
    $p=[Diagnostics.Process]::new();$p.StartInfo=[Diagnostics.ProcessStartInfo]::new()
    $p.StartInfo.FileName=$Executable;$p.StartInfo.WorkingDirectory=$WorkingDirectory;$p.StartInfo.UseShellExecute=$false;$p.StartInfo.CreateNoWindow=$true
    $p.StartInfo.RedirectStandardInput=$true;$p.StartInfo.RedirectStandardOutput=$true;$p.StartInfo.RedirectStandardError=$true
    foreach($argument in $Arguments){$p.StartInfo.ArgumentList.Add($argument)}
    $watch=[Diagnostics.Stopwatch]::StartNew();$started=$false
    try {
        $started=$p.Start();if(-not $started){throw 'AUTH_PROCESS_START_FAILED'}
        $stdout=$p.StandardOutput.ReadToEndAsync();$stderr=$p.StandardError.ReadToEndAsync()
        $write=$p.StandardInput.BaseStream.WriteAsync($InputBytes,0,$InputBytes.Length)
        if(-not $write.Wait(5000)){throw 'AUTH_PROCESS_INPUT_TIMEOUT'};$p.StandardInput.Close()
        while(-not $p.WaitForExit(1000)) {
            if($watch.Elapsed.TotalSeconds -ge $LimitSeconds){throw 'AUTH_PROCESS_TIMEOUT'}
        }
        if(-not $stdout.Wait(5000) -or -not $stderr.Wait(5000)){throw 'AUTH_PROCESS_OUTPUT_TIMEOUT'}
        return @{exitCode=$p.ExitCode;stdout=$stdout.Result;stderrCharacters=$stderr.Result.Length;elapsedSeconds=$watch.Elapsed.TotalSeconds}
    } finally {
        if($started -and -not $p.HasExited){try{$p.Kill($true);[void]$p.WaitForExit(5000)}catch{}}
        $p.Dispose()
    }
}
