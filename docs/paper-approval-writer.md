# Restricted paper approval writer

The next checkpoint is an isolated approval-writer candidate, not activation in the application. It reuses the accepted review rules and verifies that a dedicated backend database login can record a terminal review without direct permission to change account balances, issue proposals or create orders. The portal READ token is not a writer credential.

## Permission boundary

`PaperApprovalReview.restrictedWriter` uses two candidate database functions. `paper_review_lock` verifies the active recipient and token-linked proposal, then locks binding, proposal, portfolio and ledger rows. `paper_review_record` rechecks those bindings and permits only a bounded, review-only terminal receipt. Existing immutable evidence triggers and callback uniqueness remain authoritative. Java fetches a quote outside the transaction locks and rechecks account state, policy, expiry and price constraints afterward. Accepted reviews remain `ACCEPTED_EXECUTION_BLOCKED`.

The login has SELECT access to the proposal/token-hash, recipient-binding, account and instrument evidence needed by trusted review code. It cannot read delivery ciphertext or key-binding records. It has EXECUTE on just the two candidate functions and no direct table write or schema creation rights. It cannot issue proposals, mutate recipients, update receipts directly, change cash/reserves/positions, or insert orders/fills.

The functions belong to a separate **NOLOGIN, non-owner, non-superuser** helper. PostgreSQL requires UPDATE privilege on at least one column to take these row locks; the helper receives only identifier-column locking privileges and terminal receipt-column updates, not money-column updates. The login cannot assume the helper role. Functions use a fixed trusted search path with `pg_temp` last; PUBLIC execution is revoked inside installation's transaction. These boundaries follow the official [SELECT locking permissions](https://www.postgresql.org/docs/17/sql-select.html) and [security-definer guidance](https://www.postgresql.org/docs/17/sql-createfunction.html#SQL-CREATEFUNCTION-SECURITY).

This protects database mutation boundaries, not the truthfulness of a compromised backend. Transport-authenticated user/chat identity, trusted quotes and policy calculations remain Java responsibilities. The writer receives sensitive review evidence and must never be exposed to a browser, model or arbitrary caller. A review receipt is not execution permission.

Candidate SQL remains outside Flyway. The fixture installer only accepts generated disposable schema names and fixed synthetic roles. It is not an application migration or credential-provisioning tool. No new Spring bean, HTTP endpoint, Telegram worker or application datasource is enabled.

## Frozen candidate checkpoint criteria

| Checkpoint | Weight | Required evidence |
|---|---:|---|
| D | 10% | Authorized review-only scope; explicit role, lock, write and activation boundaries |
| I | 30% | Restricted JDBC path, candidate functions, isolated installer and compact-report runner implemented |
| V | 20% | Java unit/regression package and offline PowerShell validation/failure-path tests pass |
| R | 20% | All 26 isolated PostgreSQL checks pass on spare, with expected hashes, zero external calls and unchanged cash/order state |
| A | 20% | Evidence reviewed and owner accepts this isolated candidate |

This work package excludes application migration/credential activation, real Telegram/Upstox acceptance and paper execution. Those are subsequent packages, not implied by 100% candidate completion. See the [daily scorecard](daily-scorecard.md).

## Spare verification

Run in PowerShell 7 with Docker Desktop available. No application idle period, production token, model, provider credential or Docker Compose rebuild is required. The test builds one verification image and uses a labelled internal network and disposable database; no published ports or application/host data mounts. A successful run removes its owned containers, anonymous volumes and network. Failed fixtures are stopped where possible and preserved for diagnosis; do not prune unrelated resources.

```powershell
$ErrorActionPreference = 'Stop'
Set-Location 'C:\Users\Harshal S Pande\Documents\workspace\marketbrain'
if ($PSVersionTable.PSVersion.Major -lt 7) { throw 'Use PowerShell 7.' }
$pending = @(git status --porcelain)
if ($LASTEXITCODE -ne 0 -or $pending.Count -gt 0) { throw 'Preserve/review local changes before pulling.' }
git -c gc.auto=0 -c maintenance.auto=false pull --ff-only origin main
if ($LASTEXITCODE -ne 0) { throw 'Pull failed; stop here.' }
& '.\ops\windows\TestPaperPersistenceBundle.ps1' -ApprovalWriter -BuildTimeoutSeconds 1800
```

Expected status: `ISOLATED_WRITER_PASSED_APPLICATION_ACTIVATION_BLOCKED`. Share only the printed **paper-writer-<timestamp>-<id>.json**, even if it fails. It includes 23 preparation and 3 post-restart checks, per-check/stage timing, source hashes, raw/parsed output and owned-resource cleanup. No automatic test retry occurs. The runner has a 30-minute image-build limit; other stages have separate bounded limits, so that is not a whole-run duration promise.

The suite checks allowed ACCEPT/REJECT, duplicate/opposing replay, wrong recipient/token, non-private chat, binding revocation during quotes, expiry, unavailable/out-of-zone quotes, account changes, concurrent duplicate callbacks, forbidden table writes and secret reads, privilege escalation, PUBLIC execution, malformed/unsafe receipts, callback collision, lock timeout and restart preservation. No real Telegram, Upstox, model or trading call is made.

## Next gate

After candidate acceptance, prepare a separately reviewed application migration and dedicated credential setup with rollback/readback. Then exercise controlled real private Telegram and quote review without orders. Actual application backup restoration, key rotation/reconciliation and approved paper risk/fill/cost/P&L remain release gates. Numerical forecasting accuracy is independent of these engineering checks.
