# Phase 2: durable paper-account ledger

2026-10-09. E88 accepts all 31 isolated database checks in 218.014 seconds. E89 promotes the verified SQL to V27 and implements the read-only application attachment described below. **Application deployment is pending; execution remains disabled.** E86 remains the accepted Phase 1 portal checkpoint.

## Implemented contract

- Separate account, command, decision, order, position and fill tables link to the existing portfolio. The candidate SQL attaches only the pristine, uniquely active PAPER account #1 with unchanged INR100,000 and no legacy order/fill history. It never creates or funds an account. Missing, ambiguous or changed accounts remain unattached for review.
- Integer-paise cash and share reservations commit with order/position projections, immutable command receipts and the legacy cash mirror in one transaction. BUY reserves cash plus a fee allowance; SELL reserves owned shares. Multiple partial fills are supported. Cancellation and explicit due expiry release only the remaining reservation. HOLD records a decision, not an order.
- Every command locks the existing portfolio and ledger row in the same order, checks the expected account revision and validates the stored head. Primary/unique-key lookups avoid lifetime replay. Command identities are retained beyond the old 256-command fixture ceiling. An identical retry returns its original receipt; reuse with a changed payload fails.
- Supplied quote/risk evidence must match the proposal, time window and price zone. Arithmetic overflow, overfill, excess fees, unowned sells and projection divergence fail closed. Three-second lock and ten-second statement deadlines bound database operations.
- Immutable command/decision/fill rows reject ordinary UPDATE/DELETE. Projection checksums and head hashes detect tested accidental corruption, not a privileged database attacker. Historical reconciliation and recovery tooling are still required before operational release.

## Deliberate release boundaries

`src/main/resources/paper/ledger-v1.sql` remains the accepted fixture reference. V27 now contains the same executable SQL; an offline equality test prevents drift. Flyway will create the six ledger tables and attach the pristine account on deployment, without changing legacy cash/history. `PaperLedgerStore` is not a Spring bean, controller or scheduler. No public command endpoint, Telegram action or automatic fill is connected.

The V2 account overview adds ledger state, cash, reserved cash, unreserved cash and revision. This release verifies only the opening attachment: account #1, INR100,000, zero reserves, revision zero, null policy/time, initial hash and no account-scoped ledger activity. Nine bounded reads share the existing ten-second read-only REPEATABLE_READ transaction. Activity or disagreement with legacy balances withholds ledger amounts and requires reconciliation. This is not an operational account reconciliation engine or buying-power authorization. Positions and P&L are still unavailable.

Risk permits, timestamps and policies currently come from the internal caller. They are not proof of authenticated user approval or trusted quote provenance. Phase 3 must bind those authorities to the account revision and reject replay. Fixture costs, liquidity and timing are not approved production policy. P&L cost basis, settlement, corporate actions, backup/restore and operational expiry scheduling remain pending.

V27 takes short table locks and runs transactionally; attachment predicates are rechecked under those locks. Missing/ambiguous/changed accounts retain their data but are not attached. SQL failure rolls back the migration; do not delete/reseed or mark failed migrations successful. Source inspection found no application writer for legacy paper orders/fills/cash and no caller wiring the new command store. This is not protection against an external privileged database writer.

Before deployment, retain a current restorable database backup and confirm all jobs are idle. The deploy runner requires the CURRENT read token and a successful read-only pristine-account preflight before building. It accepts existing V1 read responses only for preflight and requires V2 afterward. Backup confirmation is owner-reported, not a backup/restore drill. It does not run the old dataset-specific backup script or copy your database into the shareable report.

If startup applied V27 but later UI verification failed, preserve the tables and report. Retry only the read check first. An older service can ignore the new additive tables while execution stays disabled, but never delete Flyway history, reset balances or drop committed evidence to roll back. Any future writes require forward-compatible recovery planning before release.

## Verification and acceptance

E89 local verification: clean Maven package **532 tests**, zero failures/errors/skips; **27 UI tests** and production build; **146 mocked PowerShell read/deploy assertions**. Tests include SQL parity, ledger row mapping, unchanged authentication/POST rejection, withheld inconsistent amounts, existing V1 preflight compatibility, credential collection before preflight, backup refusal before Docker and post-deployment mismatch handling. Actual V27 application startup, proxy readback and browser rendering await the spare handoff.

Local evidence: clean Maven package, **518 tests**, zero failures/errors/skips; **80 offline PowerShell assertions** (56 existing orchestration plus 24 new-ledger assertions); **17 UI tests**, production build and npm audit with zero reported vulnerabilities. These are offline/mock checks, not actual PostgreSQL migration or locking evidence.

One spare bundle exercises **31 new checks**: safe attachment/refusal, cash/share reservations, partial fills, duplicate/conflicting identities, cancellation/expiry, HOLD, stale revision, rollback after projection writes, lost commit acknowledgement, concurrent commands, lock deadline, corruption detection, 270 retained commands and PostgreSQL restart recovery. It builds a separate verification image, creates an internal-only disposable database, and uses fresh synthetic schemas. It does not use `.env`, publish ports, mount application data, rebuild/restart the service, use a model or require the portal token.

Run on the spare laptop from the repository:

```powershell
& '.\ops\windows\TestPaperPersistenceBundle.ps1' -ApplicationLedger -BuildTimeoutSeconds 1800
```

Expected status: `ISOLATED_LEDGER_PASSED_APPLICATION_MIGRATION_PENDING`. Share only the printed `paper-ledger-<timestamp>-<id>.json`; it includes source hashes, timings, progress stages, checks, captured logs, failure and cleanup records. Build/download time is machine/cache dependent; 1,800 seconds is a build deadline, not an ETA. Do not automatically rerun failures. Successful owned fixture containers/anonymous volumes are removed; failed resources are preserved with stop requested. Never prune unrelated Docker resources.

E88 has passed; do not repeat this isolated bundle for the current handoff. Next is deployment/readback below, then authenticated approval/risk and governed simulation. No predictive-performance or full-goal completion percentage is earned by isolated accounting success.

## Application attachment handoff

Use PowerShell 7 on the spare laptop, with the existing service running and a retained database backup. After pulling the reviewed code:

```powershell
& '.\ops\windows\DeployPaperAccountReadPhase.ps1' -Deploy -AttachLedger
```

Confirm `IDLE`, enter the existing private read token, then confirm `BACKED_UP` only if true. The script builds/recreates service and UI only; Flyway applies V27 at startup. Existing schedules/configuration remain unchanged, so choose an idle maintenance window. PostgreSQL service/data volumes are not recreated. It checks anonymous denial, authenticated proxy read, no-store, restricted routing, page availability and exact opening ledger amounts. One `paper-ledger-read-<id>.json` records preflight, timings, migration intent, owner backup confirmation, postflight and failures. Never share the token.

Expected status: `LEDGER_ATTACHED_READ_ONLY_VERIFIED_EXECUTION_BLOCKED`. In the portal expect current cash INR100,000, unreserved INR100,000, reserved INR0 and revision 0. Clear and lock must hide the values. No BUY/SELL/approval controls are added. Browser rendering remains an owner check.

If deployment already completed but verification failed, inspect the report and run only:

```powershell
& '.\ops\windows\DeployPaperAccountReadPhase.ps1' -RequireLedger
```

This retry performs GETs only and does not deploy, reapply SQL or create an account. Do not type backup confirmation without a backup; arrange one first if missing.

## Dependency maintenance

The Phase 1 deployment log's npm warning was traced to `source-map-js`. The lockfile now resolves 1.2.2, the [upstream patched release](https://github.com/7rulnik/source-map-js/releases/tag/v1.2.2). Local install/tests/build/audit pass. The running spare UI image is not updated by this isolated ledger bundle; carry the patch into the next reviewed UI deployment.
