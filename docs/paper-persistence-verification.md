# Isolated paper account persistence

2026-10-08. This batch moves the verified in-memory paper account into a bounded PostgreSQL engineering adapter. The next spare run tests actual database transactions and restart recovery without deploying the application or touching its database. Upstox's unanswered source-policy questions remain open; they do not block these synthetic accounting tests.

## Storage and transaction contract

The adapter accepts only uniquely named `paper_verify_<32 hex>` schemas. Explicit initialization creates one engineering account with INR100,000, a frozen policy, a revision and an accounting snapshot, plus a command journal. It cannot initialize `public`, reuse an existing schema, automatically reseed a missing account, or migrate the existing application tables. No Spring bean, endpoint, schedule or configuration switch activates it.

Each command takes a row lock on account 1, replays at most 256 commands under their recorded fixture times, reconciles the accounting snapshot, validates the new action through the existing paper core, then commits the command and new snapshot together. Queries use the account primary key and ordered command primary key with an explicit limit. Commands are at most 16 KiB; lock waits are limited to three seconds and SQL statements to ten seconds. Synchronous commit is requested. PostgreSQL holds the account's row lock until transaction completion, preventing competing writers from spending the same cash. [PostgreSQL locking reference](https://www.postgresql.org/docs/17/explicit-locking.html), [transaction-local settings](https://www.postgresql.org/docs/17/sql-set.html).

The command ID binds the entire payload, including its event time. An identical retry returns the current reconciled account without applying the action again; a different payload using that ID fails. After an uncertain commit acknowledgement, reconnect and retry the exact same ID and payload. Do not create a new ID or run automatic blind retries. Fill and approval IDs retain the domain core's own duplicate/conflict protections across restarts.

Sequence, hash-chain, policy, command and accounting mismatches stop processing; no automatic repair overwrites evidence. The hash chain detects accidental alteration, not forgery by a database administrator who can rewrite all records and hashes. Explicit expiry releases remaining reservations; opening a store does not fabricate fills, expire orders silently or replace historical timestamps with the current clock.

## Verification

Local verification passes the full Maven package with **434 tests, no failures/errors/skips**, including 24 new JUnit cases using mocked JDBC transactions. **33 PowerShell assertions** cover report mutations and the runner's success/failure/cleanup paths with every Docker call mocked. These prove application control flow and report checks, **not PostgreSQL runtime behaviour**. The spare fixture checks that behaviour with 21 preparation cases and three recovery cases:

- Committed state reconstructs on a new connection; partial fills, cancellation and HOLD retain correct accounting.
- Duplicate commands and fills do not spend twice; changed payloads, overfill and unowned sells fail without an append.
- Failures before commit roll back the journal and projection; backend termination rolls back an uncommitted transaction.
- A deliberately committed transaction followed by a simulated lost acknowledgement is recovered by an identical retry. This is not a network fault-injection test.
- Competing approvals cannot double-spend, simultaneous duplicate IDs produce one commit, and a held account lock times out without a partial write.
- Corrupt hashes/projections, missing accounts, changed policy and clock rollback fail closed. Capacity exhaustion preserves old IDs rather than evicting them.
- A real restart of the disposable PostgreSQL container is followed by a fresh JVM, duplicate retry and explicit expiry. This is orderly restart evidence, not laptop power-loss, disk-loss, replica or backup/restore certification.

The handoff independently recomputes fixture cash, quantities and fees. Before restart, cash is 9,919,970 paise, reserved cash 20,300 paise and holdings eight shares. After explicit expiry following restart, cash and holdings remain unchanged and the reservation becomes zero. The resulting history has eight commands and three fills. This does not measure investment return.

## Spare machine execution and isolation

Run `ops/windows/TestPaperPersistenceBundle.ps1` after pulling the implementation. Docker Desktop must be running with Linux containers. The first run builds a dedicated verification image and obtains `postgres:17`, so allow time for image/dependency downloads; it is not the previous four-second JVM check. Every stage has a timeout, visible progress and captured output. The report records the exact image IDs and database version used.

The runner uses a uniquely labelled **internal-only Docker network**, no published ports, no host-directory mounts, no application Compose deployment and no `.env` credentials. PostgreSQL receives disposable fixture credentials, not the application credentials. Only the isolated database receives synthetic writes. The ordinary application service/database and installed LLMs are not started, stopped or modified.

One compact `paper-persistence-<timestamp>-<id>.json` contains stages, source/image identities, raw outputs, results, timing, errors and cleanup records. Successful fixtures remove only this run's ownership-checked containers and anonymous test volumes after saving evidence; images and the report remain. Failed fixtures are preserved with stop requested so evidence can be investigated; their resource names are in the report. No global Docker prune, existing-volume deletion or automatic repeat of the failed suite occurs. A successful test's removed synthetic database is recoverable only by rerunning the fixtures, not from the summary report; it contains no user or market data.

Expected status: `ISOLATED_PERSISTENCE_PASSED_APPLICATION_RELEASE_BLOCKED`. Database verification is pending until that spare report is reviewed. A failed test is not permission to retry the same live action or relax a guard.

## Remaining integration work

This bounded replay design is an engineering adapter, not a high-throughput production ledger. Its 256-command ceiling deliberately stops rather than pruning idempotency evidence; scaling needs a reviewed snapshot/retention design. Recorded times and risk permits are trusted fixture inputs, not authenticated runtime authority. Authentication, account-version-bound risk assessment, schema migration and transactional projection into the existing application, realistic fees/taxes/liquidity/settlement, P&L, portal/Telegram approvals and the operational paper trial remain separate work.

The legacy `paper_fill` constraint allowing only one fill per order remains untouched. Application integration requires a reviewed migration and rollback plan; do not simply wire this isolated adapter to the existing portfolio or create a second active INR100,000 account. Passing these tests authorizes neither market-data fitting nor trading. Full-goal roadmap percentages remain unchanged.
