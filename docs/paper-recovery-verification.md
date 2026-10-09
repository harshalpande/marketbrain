# Paper backup recovery and audit permissions

2026-10-09. Application approval storage and key setup passed on the spare laptop (E96): 12/12 isolated checks, verified application key, INR100,000 cash, zero reserves and ledger revision 0. Total elapsed time was 734.530 seconds, including operator confirmations; the isolated portion took 84.005 seconds. No repeat storage deployment is needed.

The next batch, E97, combines **14 new checks** for database backup/restore, encrypted evidence recovery, quarantine after restoration and a restricted audit role. These are engineering checks on synthetic data. They do not restore the owner's actual application backup or activate approval transport.

## Recovery contract

The runner creates a labelled internal Docker network and a disposable PostgreSQL instance, without host mounts or published ports. Two preparation checks seed one synthetic account, eight token hashes, one review receipt and four delivery states: PENDING, SENT, UNCERTAIN and SENDING. The fixture key is synthetic; the real key file and application configuration are never read.

A custom-format `pg_dump` exports only the synthetic schema into the fixture container. The report records its SHA256. `createdb` creates a separate `paper_restore` database from template0, and `pg_restore --exit-on-error --single-transaction` restores the archive there. The runner never drops or cleans an existing database. The PostgreSQL container is restarted, then a fresh JVM compares deterministic hashes of every fixture table before any quarantine changes. Each table has a 1,000-row inspection ceiling and the schema has a 256-table ceiling; exceeding either fails this small fixture test.

These commands follow the official [pg_dump](https://www.postgresql.org/docs/17/app-pgdump.html) and [pg_restore](https://www.postgresql.org/docs/17/app-pgrestore.html) interfaces. This is a schema-level logical restore in one disposable cluster, not a machine-loss recovery or point-in-time recovery test. Roles and grants are deliberately omitted from the archive and provisioned separately for the isolated audit test.

After checking restored rows, ciphertext and the original key binding, the verifier deactivates only the restored fixture's Telegram binding. Pending delivery becomes REVOKED when inspected; SENT, UNCERTAIN and SENDING are not resent. Callbacks cannot request quotes while the binding is inactive. The original fixture database remains unchanged. Restore success alone must never restart a dispatcher: a backup can predate an external acknowledgement, so even a restored PENDING row requires reconciliation before any future reactivation.

## Restricted audit access

The candidate `paper/approval-audit-v1.sql` exposes only account amounts/revision and delivery ID/state/timestamps plus a reviewed boolean. It is **outside Flyway**. A separate disposable non-owner login receives SELECT on those two views and no base-table rights. Tests deny token/ciphertext/key/private-binding reads, money or review mutations, orders, DDL, temporary tables, trigger disabling and role escalation. Negative permission checks require SQLSTATE 42501; a syntax or connection error cannot masquerade as a permission pass.

This is an **audit reader**, not the approval writer. The application's existing metadata datasource is unchanged. The internal review code currently locks account and binding rows, which requires privileges beyond SELECT; see the [PostgreSQL SELECT privilege rules](https://www.postgresql.org/docs/17/sql-select.html). Granting cash-update rights simply to allow locking is not an acceptable writer boundary. A separately reviewed lock/command interface and scoped writer credential are still required. Do not install the fixture credentials or grants in the application database.

## Spare laptop handoff

Use PowerShell 7 with Docker Desktop running. This builds an isolated verifier image only; no service deployment, application migration, production backup, token, key or model is needed.

```powershell
$ErrorActionPreference = 'Stop'
Set-Location 'C:\Users\Harshal S Pande\Documents\workspace\marketbrain'
if ($PSVersionTable.PSVersion.Major -lt 7) { throw 'Use PowerShell 7.' }
$pending = @(git status --porcelain)
if ($LASTEXITCODE -ne 0 -or $pending.Count -gt 0) { throw 'Preserve/review local changes before pulling.' }
git -c gc.auto=0 -c maintenance.auto=false pull --ff-only origin main
if ($LASTEXITCODE -ne 0) { throw 'Pull failed; stop here.' }
& '.\ops\windows\TestPaperPersistenceBundle.ps1' -ApprovalRecovery -BuildTimeoutSeconds 1800
```

Expected status: `ISOLATED_RECOVERY_PASSED_APPLICATION_RELEASE_BLOCKED`. Share only the printed **paper-recovery-<timestamp>-<id>.json**, also on failure. It contains source hashes, backup hash, stage timings, preparation/restoration results and cleanup. No automatic suite retry occurs. Successful owned containers, anonymous volumes and network are removed; the synthetic archive disappears with its container. Failed owned fixtures are preserved with stop requested. Reports and built images remain. No global Docker pruning occurs.

## Remaining release gates

Passing this bundle closes only the synthetic restore and audit-reader checkpoint. It does not establish actual application backup restorability, secure key-backup custody, point-in-time recovery, governed key rotation, a production approval-writer role or safe reactivation after uncertain delivery. Those remain explicit gates, followed by controlled real private Telegram/Upstox review-only acceptance, approved risk limits and atomic paper reservation/fill/cost/P&L integration. No numerical prediction performance or full G08/G09 completion is claimed; the parent baseline remains 12.4%.
