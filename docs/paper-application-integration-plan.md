# Paper account application integration

2026-10-09. Owner authorized the plan and next implementation phase. Target: one preserved INR100,000 virtual account connected to proposals, authenticated approval, deterministic risk, simulated execution and a usable portal. No Paytm live execution is authorized. Development/offline verification stay here; deployment/database/model runtime stay on the spare laptop. Retain private access; this phase does not configure Tailscale or expose public ports.

## Accepted foundations

E73 closes paper-core preparation; E76 closes all 24 isolated PostgreSQL persistence/restart checks. E84 closes the October 8 feature checkpoint: 487 eligible instruments, 13 withheld, same reconciliation audit on read-only replay, notification status SENT. Do not repeat accepted checkpoints. They do not establish investment accuracy or complete application readiness.

## Delivery sequence

| Phase | Deliverable | Acceptance gate | Estimated working days |
| --- | --- | --- | --- |
| 1 | Existing-account visibility, integration contracts and evidence closure | Stored balances preserved, no new account, token-gated read API/portal, one spare report | 1–2 |
| 2 | Application ledger, reservations and durable order lifecycle | Reviewed migration/rollback; partial fills, cancellation, expiry, restart and concurrent duplicate protection | 3–4 |
| 3 | Proposal, risk and approval integration | Authenticated ACCEPT/REJECT, expiry, fresh quote and account-version-bound risk; HOLD creates no order | 3–4 |
| 4 | Operational portal | Reconciled cash, positions, approvals, orders, fills, audit and P&L | 3–4 |
| 5 | Simulation and controlled pilot release | Approved fill/cost/liquidity policy, stale-data rejection, backup/restore and end-to-end checks | 3–5 |

Approximately 3–4 working weeks is the initial allowance, dependent on runtime findings and approved policies, not a guaranteed deadline. Once contracts are stable, portal work, approval preparation and numerical research can progress alongside backend work; ledger correctness precedes execution. This does not claim parallel staffing or unattended work.

The operational trial remains at least 30 elapsed days and 20 trading sessions with meaningful activity; 60-session forecasts need additional label maturation. Synthetic/manual proposals must be distinguishable from evaluated model proposals. Engineering success and prediction quality are separate measures.

## Phase 1 implemented scope

`GET /api/v1/paper/account/overview` reads existing V1 tables in a read-only REPEATABLE_READ transaction with a ten-second deadline. At most two active accounts are selected in primary-key order; two is a lower bound, not an exact count. Two further primary-key-ordered LIMIT 1 reads detect any legacy orders/fills, including inactive-account history. No unbounded export/count, write, migration, seeding, provider/model call or notification is performed.

A unique PAPER account with unchanged INR100,000 and no history is only `EMPTY_ACCOUNT_REVIEWABLE`, never execution-ready. Missing/multiple accounts, changed cash and legacy history require review, not repair. The response always states `READ_ONLY_EXECUTION_BLOCKED`. Money remains exact decimal strings; the portal does not convert it through floating point. Current cash is not verified buying power. Reservations, positions and P&L remain unavailable rather than fabricated as zero.

The route requires `MARKETBRAIN_PAPER_READ_TOKEN`, 32–128 ASCII letters/digits/underscore/hyphen. Missing/invalid configuration or non-PAPER mode disables access. Invalid callers are rejected before database access. Responses are not cached. This local/private credential is not user identity or approval authority and does not secure unrelated existing backend routes. Do not expose the service publicly; write APIs need separately scoped authentication and replay protection.

The UI proxies only this exact GET route. Tokens stay in page memory, not browser storage or URLs. Clear and lock aborts a pending read and discards balances. Failed refreshes clear stale values. No polling or fallback to demo trades occurs.

## Spare deployment and acceptance

Use PowerShell 7, pull the reviewed revision, then run `ops/windows/DeployPaperAccountReadPhase.ps1 -Deploy`. Confirm all application jobs are idle by typing `IDLE`. Enter a private 32–128-character read token chosen in your password manager; enter the same token in the portal. Never share it in chat.

The runner passes the token through process/container configuration, never `.env` or the shareable report, and restores the caller's environment afterward. The container retains it across ordinary restarts. Future recreation without a configured token disables read access; supply it again through this runner. No persistent credential store is added here.

Compose configuration is checked without printing secrets. Only service/UI are built/recreated; database/volumes are retained. Existing configured schedules remain unchanged and can resume after restart. The new GET has no writes; startup can still apply previously pending Flyway migrations. Deploy from the accepted V26 baseline and retain normal backup practice. This phase introduces no migration.

Health waiting, Docker stages and HTTP reads are bounded. Tests cover anonymous denial on ports 8080/8081, authenticated proxy read, no-store headers, denial of another API route and HTML-shell availability. One compact `paper-account-read-<id>.json` stores revision, timings, stages, bounded redacted Docker output, readback and failures. No automatic redeployment occurs. If deployment succeeded but a read failed, inspect evidence and use the runner without `-Deploy` for a read-only check.

Open `http://127.0.0.1:8081` on the spare laptop. Enter the token, refresh and compare cash/account identity with the report; Clear and lock must remove amounts. Browser display remains an owner check. Local tests mock HTTP/JDBC and do not certify real Docker/proxy/database/browser operation.

## Phase 2 migration contract

2026-10-09: E86 accepts Phase 1 spare evidence and owner-reported portal behavior. E87 implements the [durable ledger candidate and verification](paper-application-ledger.md). Candidate SQL is outside Flyway; internal commands are not wired to application APIs. Next gate is 31 isolated database checks, followed by reviewed runtime adoption. This does not repeat the old standalone adapter's accepted persistence test.

Use Phase 1 account identity/cash/history flags before selecting the migration path. Never create a second active funded account or reset balances. Existing history requires reconciliation before import. Support multiple fills per order through a reviewed migration, preserving legacy data and immutable transaction IDs. Define rollback that retains newly committed evidence; no ad-hoc deletion/reseed.

The isolated adapter's 256-command fixture ceiling is not production storage. Phase 2 requires durable projections/checkpoints and idempotency retention, account locks, exact-money invariants and bounded indexed reads. Freeze risk percentages, quote authority, costs, liquidity, P&L cost basis and settlement assumptions before execution; do not inherit unapproved fixture defaults.

## Progress accounting

Phase 1 spare verification and owner acceptance are recorded in E86. Phase 2 candidate implementation/offline verification is recorded in E87; actual PostgreSQL and application adoption gates remain open. G08/G09 parent implementation and runtime checkpoints remain incomplete; these partial milestones do not increase the full-goal weighted 12.4% baseline. Numerical predictive performance is unmeasured. Upstox historical-source questions remain open but do not block read-only portal or synthetic accounting work.
