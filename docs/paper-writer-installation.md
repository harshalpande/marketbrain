# Guarded paper writer permission installation

Accepted installation, 2026-10-12. [E104](evidence/paper-writer-install-spare-acceptance-20261012.json) verifies the successful rollback rehearsal, original-plan restoration, commit and independent readback. All five stages exited zero, all nine source hashes matched, total62.346s. **Do not repeat Apply.** The current handoff is the [read-only connection security review](paper-writer-connection-review.md). E99's 26 isolated writer checks and E101 preflight remain accepted; do not repeat them.

**Historical E103 correction:** the administrator run at 14:58 stopped during rehearsal with SQLSTATE 42601, before Apply or COMMIT. The verification condition now parenthesizes its SQL CASE expression so its inner THEN cannot terminate the PL/pgSQL IF condition. E104 subsequently passed the corrected installation on spare; no database reset or administrator-credential change was needed.

The [PostgreSQL 18 parser](https://github.com/postgres/postgres/blob/REL_18_STABLE/src/pl/plpgsql/src/pl_gram.y) reads IF conditions through a top-level THEN and tracks parenthesis depth. [E103 verification](evidence/paper-writer-install-fix-20261012.json): 263 offline installer assertions and 682 Java regression tests passed; Maven package 57.292s. E104 supplies the subsequent spare acceptance.

This installation stages **two NOLOGIN roles and two review-only functions**. It does not create a usable writer credential, connect an application datasource, restart MarketBrain, send messages, write account rows or enable trading. Application credential activation and controlled review transport are separate gates.

## Exact change and safeguards

1. Native PostgreSQL 18 `psql.exe` on spare connects to `127.0.0.1`, default port 5432/database `marketbrain`. The owner confirms this is the actual application database. The plan records database OID and PostgreSQL cluster identity; it does not infer identity from the service or `.env`.
2. Read a bounded catalog plan (maximum 128 roles, 256 memberships, 512 non-system relations). Require PostgreSQL 18, a superuser, twelve expected ordinary non-RLS tables, no proposed role/function collision, no PUBLIC schema CREATE or callable non-system security-definer functions, and no administrator function-default-ACL override. Unsupported findings stop the run, not widen grants.
3. Show the exact existing roles receiving explicit TEMP preservation, including non-login and predefined roles. Require a retained restorable database backup, a short idle maintenance window with no concurrent administrator/schema changes, and `APPROVE_ROLES`. Existing effective TEMP is preserved for **every pre-existing role that has it**. This also creates explicit grants for some roles that previously obtained it indirectly; that enduring policy consequence is part of approval. Future roles need reviewed explicit grants or membership.
4. In one transaction, take an installer advisory lock and compare a fresh catalog fingerprint with the approved plan; preserve existing TEMP, then revoke **only TEMP on the target database from PUBLIC**, using RESTRICT. No broad fixture-wide PUBLIC revokes, ownership takeover or overwrite of existing objects.
5. Create `marketbrain_paper_review_writer` and `marketbrain_paper_review_helper` with NOLOGIN, no password, no elevated attributes or memberships. Roles are cluster-wide objects, but this script grants privileges only on the target database. It does not certify safe future login access to every database in the cluster.
6. Grant SELECT on eight review tables to both roles. Only the helper receives identifier-column UPDATE for row locking and three terminal-receipt columns on proposals. Neither receives cash/order/fill mutation privileges. Install the accepted function bodies, transfer ownership to the helper using temporary schema CREATE, immediately remove CREATE and grant the writer function EXECUTE. Functions have a fixed trusted search path and no PUBLIC execution. They are never invoked by the installer.
7. Verify role attributes/membership, preserved old TEMP access, expected reads, denied non-approved reads/writes/DDL, exact function signatures/body hashes/owner/search path/ACL, and no public privileged entry point. Rehearse this exact transaction and **ROLLBACK**. On a new connection, require the original catalog fingerprint to match, proving restoration within the inspected scope.
8. Only after `INSTALL <displayed fingerprint>` repeat the guarded transaction with COMMIT. A fresh read-only connection verifies the installed state. No automatic retry, credential activation or application restart follows.

Each SQL statement has a 15-second deadline and 3-second lock limit; each psql stage has a 120-second outer deadline. Console progress, stage timing, source hashes and safe SQLSTATE/fixed assertion labels are checkpointed to one JSON. Raw stderr and credentials are not embedded. The admin password is prompted securely and passed only through the child process environment, removed after use; equally privileged operating-system processes can still inspect process memory/environment. Do not use a shared untrusted session.

Diagnostics now retain bounded numeric psql input-line and inline-block locations, mapped to fixed installer section names where available. They do not expose source lines, raw database errors or passwords. `POSTGRESQL_ADMIN_REQUIRED` distinguishes the wrong database role from `SQL_SYNTAX_ERROR`; a location can be absent if PostgreSQL does not emit a recognized format. The first rehearsal failure report withheld its exact error line, so the CASE diagnosis is source-supported rather than an exact server-line capture. The correction's lexical regression detects the original malformed IF boundary; full SQL/runtime verification still occurs on spare, not in mocked offline tests.

MD5 catalog/body fingerprints detect accidental drift, not cryptographic authentication. Run reviewed repository code with a clean worktree; retain the SHA256 source manifest and report. Idle coordination is required: the advisory lock serializes this installer, not arbitrary administrator commands.

PostgreSQL documents [additive PUBLIC privileges and REVOKE](https://www.postgresql.org/docs/18/sql-revoke.html), [NOLOGIN attributes](https://www.postgresql.org/docs/18/sql-createrole.html) and [psql error-stop behaviour](https://www.postgresql.org/docs/18/app-psql.html). A role-specific revoke does not cancel a PUBLIC grant.

## Frozen package and evidence

| Checkpoint | Weight | Acceptance |
|---|---:|---|
| D | 10% | Owner-approved targeted TEMP preservation, backup/idle/confirmation and NOLOGIN boundaries |
| I | 30% | Bounded native installer, rollback rehearsal, independent readback and one-report recovery |
| V | 20% | Offline SQL-generation/contract and mocked success/failure/drift/uncertain-commit tests; Java regression passes |
| R | 20% | Spare rehearsal, committed metadata and independent permission verification succeed |
| A | 20% | Report/source/target/side-effect review accepted; credentials and execution remain disabled |

Current **100% (D/I/V/R/A)** after E104, up40percentage points from60%. Offline tests do not execute PostgreSQL SQL or the PS7 native process wrapper; E104 supplies that installation runtime evidence. Full roadmap stays **12.4%**, and predictive accuracy remains unmeasured. This scope is permission staging, not completion of production approval integration.

## Historical installation command

This command is retained for the installation contract, not the next run. The current spare installation is accepted. Use the [connection review handoff](paper-writer-connection-review.md#run-on-spare), not another Apply.

Use PowerShell 7. Have PostgreSQL administrator credentials locally, know the application database name, retain a current restorable backup and arrange a short idle maintenance window. No Docker build or service restart is needed.

```powershell
$ErrorActionPreference = 'Stop'
Set-Location 'C:\Users\Harshal S Pande\Documents\workspace\marketbrain'
if ($PSVersionTable.PSVersion.Major -lt 7) { throw 'Use PowerShell 7.' }
$pending = @(git status --porcelain)
if ($LASTEXITCODE -ne 0 -or $pending.Count -gt 0) { throw 'Preserve/review local changes before pulling.' }
git -c gc.auto=0 -c maintenance.auto=false pull --ff-only origin main
if ($LASTEXITCODE -ne 0) { throw 'Pull failed; stop here.' }
& '.\ops\windows\InstallPaperApprovalWriter.ps1' -Apply
```

Defaults: `-DatabaseName marketbrain -DatabasePort 5432 -PostgreSqlBin 'C:\Program Files\PostgreSQL\18\bin'`. Override explicitly if the verified installation differs; do not create a second database to accommodate defaults. Omitting `-Apply` produces a catalog plan only. Administrator is a PostgreSQL role; running Windows as Administrator alone is not enough.

Share only `paper-writer-install-<timestamp>-<id>.json` at the printed path, even on failure. Expected final status: `STAGED_WRITER_VERIFIED_LOGIN_AND_ACTIONS_DISABLED`, with `commitOutcome=COMMITTED_AND_VERIFIED`. Report contains role names/metadata but no credential; share privately.

## Interrupted or failed run

Before commit, disconnect/error rolls back transactional changes. Rehearsal success alone does not prove installation. After an attempted commit, a lost response can leave the outcome uncertain; never re-run Apply blindly. No automatic post-commit undo is attempted because it could remove later legitimate changes.

Retain the report and use **read-only** reconciliation after review:

```powershell
& '.\ops\windows\InstallPaperApprovalWriter.ps1' -VerifyReportPath 'C:\MarketBrainData\Review\YOUR-EXACT-paper-writer-install-report.json'
```

Use the same target overrides if applicable. This cannot repair or overwrite objects. Failed verification requires inspection of saved plan/current catalogs before any separately approved rollback; do not drop roles, reset cash, restore a whole database or regrant PUBLIC privileges as a blanket fix. Backup confirmation is an owner assertion, not a performed restore test.

After acceptance: dedicated credential custody and scoped application wiring, then controlled private Telegram/fresh-quote review with actions disabled. Paper risk/reservations, fills/costs/P&L, actual application recovery and the prospective pilot remain pending.
