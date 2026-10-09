# Phase 2: durable paper-account ledger

2026-10-09. E86 closes the Phase 1 read-only spare checkpoint. E87 implements the next ledger candidate and its verification bundle. **Application migration and execution are not enabled.** This is new application-ledger work, not a repeat of E76's accepted standalone persistence adapter.

## Implemented contract

- Separate account, command, decision, order, position and fill tables link to the existing portfolio. The candidate SQL attaches only the pristine, uniquely active PAPER account #1 with unchanged INR100,000 and no legacy order/fill history. It never creates or funds an account. Missing, ambiguous or changed accounts remain unattached for review.
- Integer-paise cash and share reservations commit with order/position projections, immutable command receipts and the legacy cash mirror in one transaction. BUY reserves cash plus a fee allowance; SELL reserves owned shares. Multiple partial fills are supported. Cancellation and explicit due expiry release only the remaining reservation. HOLD records a decision, not an order.
- Every command locks the existing portfolio and ledger row in the same order, checks the expected account revision and validates the stored head. Primary/unique-key lookups avoid lifetime replay. Command identities are retained beyond the old 256-command fixture ceiling. An identical retry returns its original receipt; reuse with a changed payload fails.
- Supplied quote/risk evidence must match the proposal, time window and price zone. Arithmetic overflow, overfill, excess fees, unowned sells and projection divergence fail closed. Three-second lock and ten-second statement deadlines bound database operations.
- Immutable command/decision/fill rows reject ordinary UPDATE/DELETE. Projection checksums and head hashes detect tested accidental corruption, not a privileged database attacker. Historical reconciliation and recovery tooling are still required before operational release.

## Deliberate release boundaries

`src/main/resources/paper/ledger-v1.sql` is **outside Flyway**. `PaperLedgerStore` is not a Spring bean, controller or scheduler. No public command endpoint, Telegram action, automatic fill or application balance write is connected. The accepted read-only portal remains unchanged.

Risk permits, timestamps and policies currently come from the internal caller. They are not proof of authenticated user approval or trusted quote provenance. Phase 3 must bind those authorities to the account revision and reject replay. Fixture costs, liquidity and timing are not approved production policy. P&L cost basis, settlement, corporate actions, backup/restore and operational expiry scheduling remain pending.

The candidate migration takes short table locks and runs transactionally. On failure, roll back the transaction; do not delete/reseed legacy data. Future application adoption needs a freshly reviewed account preflight, backup, exclusion of legacy writers and promotion of the reviewed SQL into a versioned migration. Once any ledger commands exist, recovery must preserve them: disable command ingress and forward-fix/reconcile, never reset cash or drop evidence as a rollback shortcut. No application adoption command is included in this milestone.

## Verification and acceptance

Local evidence: clean Maven package, **518 tests**, zero failures/errors/skips; **80 offline PowerShell assertions** (56 existing orchestration plus 24 new-ledger assertions); **17 UI tests**, production build and npm audit with zero reported vulnerabilities. These are offline/mock checks, not actual PostgreSQL migration or locking evidence.

One spare bundle exercises **31 new checks**: safe attachment/refusal, cash/share reservations, partial fills, duplicate/conflicting identities, cancellation/expiry, HOLD, stale revision, rollback after projection writes, lost commit acknowledgement, concurrent commands, lock deadline, corruption detection, 270 retained commands and PostgreSQL restart recovery. It builds a separate verification image, creates an internal-only disposable database, and uses fresh synthetic schemas. It does not use `.env`, publish ports, mount application data, rebuild/restart the service, use a model or require the portal token.

Run on the spare laptop from the repository:

```powershell
& '.\ops\windows\TestPaperPersistenceBundle.ps1' -ApplicationLedger -BuildTimeoutSeconds 1800
```

Expected status: `ISOLATED_LEDGER_PASSED_APPLICATION_MIGRATION_PENDING`. Share only the printed `paper-ledger-<timestamp>-<id>.json`; it includes source hashes, timings, progress stages, checks, captured logs, failure and cleanup records. Build/download time is machine/cache dependent; 1,800 seconds is a build deadline, not an ETA. Do not automatically rerun failures. Successful owned fixture containers/anonymous volumes are removed; failed resources are preserved with stop requested. Never prune unrelated Docker resources.

After this evidence passes: review migration/runtime adoption, connect ledger read views, then authenticated approval/risk and governed simulation. No predictive-performance or full-goal completion percentage is earned by this isolated test alone.

## Dependency maintenance

The Phase 1 deployment log's npm warning was traced to `source-map-js`. The lockfile now resolves 1.2.2, the [upstream patched release](https://github.com/7rulnik/source-map-js/releases/tag/v1.2.2). Local install/tests/build/audit pass. The running spare UI image is not updated by this isolated ledger bundle; carry the patch into the next reviewed UI deployment.
