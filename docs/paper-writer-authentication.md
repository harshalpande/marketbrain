# Bounded application-container writer authentication

2026-10-14. E131 accepts protected credential staging: five database stages, 11 source matches, 24.077 seconds, both roles NOLOGIN. That bounded package is complete. Do not rerun installation, HBA staging or password creation.

## Purpose and frozen scope

Prove that the existing protected credential works through the actual application container and its deployed restricted connector, and that access can be closed again. This combines credential handoff, positive/negative authentication, selected read-permission checks, revocation, original application-access regression and recovery in one report. It does not activate the application's writer worker or Telegram review configuration.

Success enables the next separately reviewed step: persistent runtime secret handoff and a controlled Telegram approval round trip with explicit risk/expiry policy. It does **not** authorize paper fills, money updates, real orders or model promotion. The wider access-policy finding remains open; a same-machine test is not an external firewall/VPN penetration test.

## Exactly what changes

1. Reuse the accepted `writer.dpapi` under the same Windows user. Hold its existing exclusive lock. No new password, rotation, plaintext file, mount or change to the approval encryption key.
2. Compile two standalone JDK21 diagnostics and copy them to a uniquely owned temporary directory in the existing running application container. No application rebuild/restart, schema migration or endpoint is added. The probe loads the connector and JDBC driver from `/app/app.jar`, records their hashes and checks connector construction before enabling login.
3. Recheck pinned installation/credential evidence, installed grants/function bodies, absent writer sessions and NOLOGIN. Prove a fresh connection is denied. The exact accepted HBA file hash and zero parser errors are required before opening a lease; the file is not edited/reloaded.
4. After explicit local confirmation, change only `marketbrain_paper_review_writer` to LOGIN with a **120-second server-clock password validity**, and a run-owned role comment. The helper remains NOLOGIN. Require more than60 seconds remaining before the45-second probe. Persist the recovery identity before attempting the change; lost responses are treated as unknown commits.
5. Pass the writer password only over the redirected stdin pipe of `docker exec -i`, not command arguments, environment variables, reports or files. The Java process has a45-second watchdog; the launcher has a55-second deadline. Passwords necessarily exist briefly in process memory; this is not a claim against privileged memory inspection. No existing application password is used for the writer probe.
6. Use the deployed connector for a correct-secret connection, verify server identity and loopback route, and run four zero-row forbidden SELECT checks. Check wrong-secret rejection (`28P01`) and rejection of the same credential against the `postgres` database (`28000`). These are selected access tests, not proof of every possible database/network route. Full catalog grant verification is separate; no DML is attempted merely to obtain a read-only-transaction error.
7. Commit NOLOGIN **before** session cleanup. Restore the original role comment and unlimited password validity (`infinity`, semantically unlimited like the previously null expiry). Terminate only remaining sessions for this exact dedicated writer role, bounded to eight; never terminate the general application/admin connection. Read back zero writer sessions and disabled writer/helper, then reverify all installed grants and the credential. Test login denial again and a fresh original application connection.
8. Remove only the two owned diagnostic class files/directories. Retain a single compact JSON containing stages, outcomes, hashes and timings. No raw SQL, native errors, credentials, verifier, account data or message contents are exported.

PostgreSQL's [`VALID UNTIL`](https://www.postgresql.org/docs/18/sql-createrole.html) expires password authentication, not the role or existing sessions. Therefore expiry is a crash backstop, **not** completed revocation. [`pg_terminate_backend`](https://www.postgresql.org/docs/18/functions-admin.html) is used only after committed NOLOGIN and only for this writer's sessions. Normal failure runs restoration; a machine shutdown or administrator change may still require the explicit recovery below. Do not promise that scripts cannot fail.

The remaining role comment/NOLOGIN/expiry changes are database role metadata writes. Account rows, cash, orders, fills, provider/model jobs, Telegram, HBA, firewall and Tailscale are not changed by this test. Native administrator SQL includes the sensitive SCRAM verifier for comparison; server-admin logs/backups must remain private.

## Spare-laptop run

Use PowerShell7 as the **same Windows user who staged custody**, with Docker Desktop and the existing MarketBrain service already running, JDK21+ (`javac`) on PATH and PostgreSQL18 native tools available. Windows elevation is not required by this script. Enter PostgreSQL administrator credentials locally only. Keep other writer/deployment work stopped and the laptop awake. This is expected to be a short diagnostic, not a model run; actual time is measured, not guaranteed.

```powershell
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'Continue'
if ($PSVersionTable.PSVersion.Major -lt 7) { throw 'Open PowerShell 7 first.' }
Set-Location 'C:\Users\Harshal S Pande\Documents\workspace\marketbrain'
if (@(git status --porcelain).Count -or $LASTEXITCODE -ne 0) {
    throw 'Working tree needs review. Do not discard changes.'
}
git -c gc.auto=0 -c maintenance.auto=false pull --ff-only origin main
if ($LASTEXITCODE -ne 0) { throw 'Git pull failed. Stop here.' }

$parameters = @{
    InstallationReportPath = 'C:\MarketBrainData\Review\paper-writer-install-20261012-151121-ca9707876fe9.json'
    CredentialReportPath   = 'C:\MarketBrainData\Review\paper-writer-credential-20261014-163918-bfbf37646181.json'
    Mode                   = 'Test'
}
foreach ($name in 'InstallationReportPath', 'CredentialReportPath') {
    if (-not (Test-Path -LiteralPath $parameters[$name] -PathType Leaf)) {
        throw "Accepted report missing: $($parameters[$name]). Locate that exact file; do not select a newer report."
    }
}
& '.\ops\windows\TestPaperWriterAuthentication.ps1' @parameters
```

Confirm `marketbrain`, then `TEST_TEMPORARY_LOGIN`. Expected result: `WRITER_AUTHENTICATION_PASSED_LOGIN_DISABLED`, `revocationVerified=true`, `cleanupComplete=true`, writer/helper false, writerSessions0, no action/account writes. Share only the printed `paper-writer-authentication-*.json`. Never share the Secrets directory or passwords.

## Interrupted or failed run

Do not automatically retry Test. On `RECOVERY_REQUIRED_DO_NOT_RETEST`, or after shutdown during the window, keep the preserved checkpoint and run the same script in recovery mode. The exact saved run-owned role marker must match (or already be restored with NOLOGIN); target/credential mismatch requires manual review, not forced changes. Recovery never grants LOGIN, starts a container or runs inference:

```powershell
$parameters = @{
    InstallationReportPath = 'C:\MarketBrainData\Review\paper-writer-install-20261012-151121-ca9707876fe9.json'
    CredentialReportPath   = 'C:\MarketBrainData\Review\paper-writer-credential-20261014-163918-bfbf37646181.json'
    Mode                   = 'Recover'
    RecoveryReportPath     = (Read-Host 'Full path of the interrupted paper-writer-authentication JSON')
}
& '.\ops\windows\TestPaperWriterAuthentication.ps1' @parameters
```

Confirm `RESTORE_NOLOGIN`. `WRITER_NOLOGIN_RECOVERED_RETEST_PENDING` proves restoration and current grants, **not** successful authentication testing. Recovery does not claim cleanup of an earlier interrupted container's diagnostic files; `priorDiagnosticCleanupVerified=false` retains that limitation. Do not delete custody, the original HBA backup or unrelated Docker resources. Share the new report before another test.

## Verification and progress

E132 records offline contracts, failure injection, real harmless stdin/timeout child checks and Java tests including isolated Boot-jar class loading. Database/Docker operations are mocked locally; actual SQL execution and runtime authentication remain the spare checkpoint. No new Spring bean, property binding, dependency, datasource or scheduled job is registered; the application-startup boundary remains unchanged.

Frozen checkpoints: design10%, implementation30%, offline verification20%, spare-runtime verification20%, owner acceptance20%. Locally verified package60%; actual runtime and owner acceptance remain pending. Credential staging is100% (E131), access-policy review80%, full paper-first roadmap12.4% unchanged. None of these percentages measures prediction accuracy.
