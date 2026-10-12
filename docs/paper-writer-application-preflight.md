# Paper writer application permission preflight

**Accepted 2026-10-12 (E101):** the spare catalog report and owner review close this preflight-only package at 100%. Its administrator/PUBLIC TEMP findings feed the [guarded NOLOGIN installation](paper-writer-installation.md). Do not rerun the historical preflight command below. Installation and activation are not implied by acceptance.

The isolated writer candidate passed 26/26 PostgreSQL checks on the spare laptop ([E99](evidence/paper-writer-spare-acceptance-20261012.json)). The next step inspects the configured application database before preparing its writer installation. It does not install a role, create a credential, restart MarketBrain, publish a notification or approve a trade.

## Why inspect the application first

The disposable fixture revoked PUBLIC database, schema and function permissions. Copying those revocations into the application could disrupt other database clients. The actual database may also have a different owner, missing role-management authority, existing function names, row-security policies or inherited PUBLIC permissions. These facts determine the narrow installation and rollback plan; do not relax the accepted writer boundary to accommodate them.

The standalone inspector reads PostgreSQL catalogs only. It does not query account balances, recipient identities, approval payloads, passwords, encrypted delivery records or historical market data. No new Spring bean, endpoint, Flyway migration, scheduler or worker is added.

## Scope and limits

- One repeatable-read, read-only transaction; 18 bounded catalog SELECTs with 5-second statement/query limits, 1-second lock limit, 5-second connection and 10-second socket limits. The outer inspector deadline is 180 seconds; there is no automatic retry. The connection rolls back after inspection.
- Twelve named relations, two proposed role names, two function names, PUBLIC schema CREATE and publicly callable non-system security-definer functions. Lists stop at 21 rows and explicitly flag the bound. No table scans, attempted DML, function invocation, grant, revocation or temporary table creation.
- Uses the existing repository `.env` and current process environment overrides, passing **only database configuration** to a separate constrained container. It does not read the running service's environment or claim that the configured target is independently proven identical to the running service's database. The report is installation input, never installation approval.
- Supported JDBC URLs are ordinary PostgreSQL host/database URLs, optionally with `sslmode`. Embedded credentials and arbitrary driver options are rejected, not rewritten. A nonstandard URL requires review; do not weaken TLS or change the application's URL merely to run this diagnostic.
- PUBLIC findings are review items, not instructions to revoke broad grants. Existing proposed roles/functions are collisions, not objects to overwrite. Administrator involvement, if needed, is requested after evidence review; never share credentials in chat.
- The script starts no application services and publishes no ports. It removes only its unique standalone Compose project; built images and the single report remain. Native output is withheld because expanded configuration/errors can contain secrets. The JSON retains stage exit codes, timing, source hashes and sanitized Java failure type/SQLSTATE.

PostgreSQL documents the [privilege inquiry functions](https://www.postgresql.org/docs/current/functions-info.html#FUNCTIONS-INFO-ACCESS-TABLE) and [read-only transaction restrictions](https://www.postgresql.org/docs/current/sql-set-transaction.html). Read-only mode alone is not a complete sandbox: fixed catalog SQL, no application function calls and restricted connection options also form this inspector's boundary.

## Frozen preflight package checkpoints

This is a separate package from the accepted isolated writer and from application installation.

| Checkpoint | Weight | Complete when |
|---|---:|---|
| Design | 10% | Authorized catalog-only scope, privacy, limits and installation boundary fixed |
| Implementation | 30% | Standalone inspector, constrained container and one-report runner implemented |
| Offline verification | 20% | Java regression and mocked PowerShell success/failure/timeout/cleanup tests pass |
| Spare verification | 20% | Inspector completes against the configured database and produces the guarded contract |
| Acceptance | 20% | Findings, target identity assumptions and required administrator actions reviewed with owner |

The preflight can capture useful evidence while reporting installation blockers. Neither a complete report nor a 100% preflight package score activates the writer.

## Run on the spare laptop

Use PowerShell 7 with Docker Desktop available. Retain the existing `.env`; do not paste its values here. No idle confirmation or read token is required because the running application is untouched. The new image build has a 30-minute ceiling, not an expected duration.

```powershell
$ErrorActionPreference = 'Stop'
Set-Location 'C:\Users\Harshal S Pande\Documents\workspace\marketbrain'
if ($PSVersionTable.PSVersion.Major -lt 7) { throw 'Use PowerShell 7.' }
$pending = @(git status --porcelain)
if ($LASTEXITCODE -ne 0 -or $pending.Count -gt 0) { throw 'Preserve/review local changes before pulling.' }
git -c gc.auto=0 -c maintenance.auto=false pull --ff-only origin main
if ($LASTEXITCODE -ne 0) { throw 'Pull failed; stop here.' }
& '.\ops\windows\GetPaperWriterPreflight.ps1'
```

Share only **paper-writer-preflight-<timestamp>-<id>.json** from the printed path, including on failure. Expected capture status: `CATALOG_EVIDENCE_CAPTURED_INSTALLATION_REVIEW_REQUIRED`. Do not rerun the accepted 26-case writer fixture or storage/recovery deployments.

## What follows the report

Review target and permission findings, then prepare the exact application migration and private dedicated credential setup with backup, transaction rollback and readback. Broad PUBLIC permission changes or new administrator authority require a separately reviewed impact decision. After installation acceptance, integrate controlled private Telegram and fresh-quote review while orders remain disabled. Approved paper risk, fill/cost/P&L policy, actual application recovery and the prospective pilot remain later gates.
