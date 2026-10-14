# Protected writer credential staging

Accepted E131, 2026-10-14: all five database stages succeeded, 11 source hashes matched, custody verified, both roles NOLOGIN, 24.077s. Owner continuation closes this package at100%. Do not rerun Stage. Continue with [bounded application authentication and revocation](paper-writer-authentication.md); the historical staging instructions below remain for reference only.

2026-10-14. The isolated Telegram/writer bundle is accepted: 18/18 checks, zero failures, 250.791 seconds, with no real Telegram calls or application database access. Its bounded package is 100% after owner acceptance (E129). Do not repeat it.

The next package creates a dedicated writer credential without allowing the writer to log in. It combines protected Windows storage, fresh installed-permission checks, rollback rehearsal, narrowly scoped password staging and independent readback. This is preparation for application-route authentication, not Telegram or trading activation.

## What changes

- Creates `C:\MarketBrainData\Secrets\PaperReviewWriter\writer.dpapi` under a private owner/SYSTEM ACL. DPAPI CurrentUser binds recovery to the same Windows identity and machine. A separate empty `credential.lock` serializes local runs. Do not share either file or the Secrets directory.
- Generates 32 random password bytes, represented as 64 lowercase hexadecimal characters for the future Java client, and an independent 16-byte salt. The protected payload binds to the accepted database, port, database OID, cluster ID and installation plan. Existing custody is reused, never overwritten or regenerated automatically.
- Stages a SCRAM-SHA-256 verifier only on `marketbrain_paper_review_writer`. The database receives no cleartext writer password. Both writer and helper remain `NOLOGIN`; no role membership, grant, account row, HBA, firewall, Tailscale, Compose or application setting changes.
- Existing application credentials and stored paper funds are untouched. No model, provider, Telegram, order or fill call is made. This package creates no runtime plaintext file or Docker mount.

PostgreSQL accepts an already formatted [SCRAM verifier](https://www.postgresql.org/docs/18/sql-createrole.html). The construction follows the [PostgreSQL SCRAM implementation](https://github.com/postgres/postgres/blob/master/src/common/scram-common.c), with PBKDF2-HMAC-SHA256, 4096 iterations, StoredKey and ServerKey. The ASCII-only random password does not require Unicode normalization. A separate Node crypto implementation supplies the offline golden vector. A verifier remains sensitive; database administrators and their server logs/backups require protection even though no cleartext password is sent in SQL.

## Guards and recovery

The exact accepted installation report is required (E104, SHA256 `E213A645E4CD39D16E63BA69097E1D32B45E60DC49BF08EBE0B4B52DBD95B33D`). The script rechecks its target, installed role identities, fixed function bodies and permissions against the actual database. It stops on unexpected roles, sessions, grants, target identity or an existing different password. It does not repair those findings automatically.

First staging runs `Inspect → Rehearse/ROLLBACK → Inspect → Stage/COMMIT → Verify`. The second inspection must prove the rehearsal did not retain its password change. Stage is attempted at most once. Each database call has a 120-second outer deadline, 15-second statement timeout, three-second lock timeout and heartbeat; SQL operates on bounded catalogs rather than scanning market/account data. A database advisory lock prevents overlapping instances of this operation; it is not protection against an independent administrator changing roles concurrently.

If the existing database verifier already matches protected custody, a rerun performs only inspection and reports `EXISTING_CREDENTIAL_VERIFIED_NO_CHANGE`. If commit or readback fails, its outcome remains unknown and custody is retained. **Do not delete the blob, choose another password, or automatically retry.** Share the report; `-Mode Verify` then provides a read-only reconciliation path. Missing, truncated, corrupt or differently bound custody stops before database access. No cross-user or different-machine restore is implied by DPAPI recovery; rotation, revocation and runtime handoff remain later work.

Reports contain only validated receipts, timing, source hashes and bounded diagnostic codes/locations. Passwords, verifier, protected bytes, SQL and raw driver output are excluded. Temporary byte buffers are cleared; PowerShell/.NET immutable string copies cannot be guaranteed erased from process memory. Keep the laptop owner/admin session trusted.

## Spare laptop command

Run in **PowerShell 7 as the usual Windows owner**. A PostgreSQL administrator password is requested locally; Windows elevation is not required solely for this script. Leave the existing application running. No Docker build or application restart is needed.

```powershell
$ErrorActionPreference = 'Stop'
if ($PSVersionTable.PSVersion.Major -lt 7) { throw 'Open PowerShell 7.' }
Set-Location 'C:\Users\Harshal S Pande\Documents\workspace\marketbrain'
$changes = @(git status --porcelain)
if ($LASTEXITCODE -ne 0 -or $changes.Count -gt 0) { throw 'Preserve/review local changes before pulling.' }
git -c gc.auto=0 -c maintenance.auto=false pull --ff-only origin main
if ($LASTEXITCODE -ne 0) { throw 'Pull failed; stop.' }

$installationPath = 'C:\MarketBrainData\Review\paper-writer-install-20261012-151121-ca9707876fe9.json'
if (-not (Test-Path -LiteralPath $installationPath -PathType Leaf)) {
    $installationPath = Read-Host 'Paste the full path of the original successful paper-writer-install-20261012-151121-ca9707876fe9.json'
}
& '.\ops\windows\SetPaperWriterCredential.ps1' -InstallationReportPath $installationPath -Mode Stage
```

Confirm the displayed database name, type `STAGE_DISABLED_WRITER`, then enter the PostgreSQL administrator username/password locally. The writer password is generated for you and never displayed. Share only the resulting `paper-writer-credential-<timestamp>-<id>.json`, including on failure.

Success is `WRITER_CREDENTIAL_STAGED_LOGIN_DISABLED`, with custody verified, both login flags false, no account writes and execution disabled. A first run requires five successful database stages; an already matching credential requires only one. Success proves guarded credential staging and catalog readback, **not successful writer authentication**. That distinction remains explicit in the report and progress scorecard.

## Completion and next milestone

Frozen scope: target-bound protected custody, SCRAM verifier generation, no-overwrite/resume behavior, guarded NOLOGIN password staging, rollback/readback and one-file evidence. Checkpoints are D10/I30/V20/R20/A20; local verification can earn 60%, with spare staging and owner acceptance pending. Whole-roadmap progress remains 12.4%; this is not a forecast-accuracy gain.

Offline verification passes265 assertions across20 runner scenarios on both PowerShell5.1 and7.6.6, plus263 existing installer regression assertions on7.6.6. Synthetic Windows custody is exercised and removed; PostgreSQL is mocked. The first actual database staging will run the mandatory rollback rehearsal before any commit. Java/Spring/application configuration is unchanged, so this handoff does not require another application build or model test.

After acceptance, prepare controlled runtime credential handoff and fresh positive/negative authentication from the application route, including rotation/revocation and the remaining effective-access findings. Then agree explicit review-policy limits and test real private Telegram publication, ACCEPT/REJECT and durable outcomes with execution still disabled. Paper reservations, fills, fees, holdings and P&L follow separately. The phone portal and Tailscale are not prerequisites, and neither is changed here.
