# Paper account application integration

2026-10-15 E136/E137: the isolated runtime test is accepted at100%:18 unique Linux checks repeated after restart, protected synthetic handoff, final LOCKED and cleanup verified in91.716s. Do not rerun it. Next is the [guarded application handoff](paper-runtime-application-handoff.md), locally verified60% with236 offline assertions/12 mocked scenarios. It rebuilds/recreates only the service, briefly hands over the existing protected credential, verifies locked restart and re-locks. PostgreSQL remains NOLOGIN; no proposal publication or account writes. Real deployment verification and owner acceptance are pending; full-roadmap12.4% and effective-access review80% remain unchanged. Earlier next-action paragraphs below are historical.

2026-10-09. Owner authorized the plan and next implementation phase. Target: one preserved INR100,000 virtual account connected to proposals, authenticated approval, deterministic risk, simulated execution and a usable portal. No Paytm live execution is authorized. Development/offline verification stay here; deployment/database/model runtime stay on the spare laptop. Retain private access; this phase does not configure Tailscale or expose public ports.

## Accepted foundations

2026-10-15 E134: owner-approved policy and restart custody are implemented and locally verified; the [isolated synthetic handoff](paper-runtime-credential-handoff.md) is next. Package60%, spare pending. Do not deploy the candidate memory overlay yet. Actual local unlock/application rollout, bounded proposal publication, durable private Telegram outcomes and accounting reconciliation follow; no money/order authority is added. Earlier policy-choice questions below are resolved, not repeated.

2026-10-14 E133: deployed authentication/revocation is accepted at100%; do not repeat it. No persistent worker is active. Follow the [runtime review implementation sequence](paper-runtime-review-plan.md): decide restart custody and test limits, then verify bounded publication, private Telegram receipts and unchanged accounting. These unresolved choices block activation, not the already completed authentication milestone.

2026-10-14 E131/E132: credential staging is accepted at100%; do not rerun it. [Bounded authentication/revocation](paper-writer-authentication.md) now combines actual deployed-connector login, wrong-secret/other-database denial, four forbidden-read checks, NOLOGIN/session cleanup, original application-access regression and recovery in one handoff. Local package60%, spare pending. This diagnostic is not persistent application-writer activation. Runtime handoff, rotation, explicit policy limits, controlled Telegram publication/receipt and subsequent simulated execution remain required.

2026-10-14 E127/E128: HBA staging is accepted and targeted network metadata is captured. The owner confirms phone usage is **Telegram only**, not the portal. Next is [default-off Telegram callback/writer wiring and its isolated verification](telegram-paper-review-integration.md), not another permission installation or phone connectivity test. This source-level bridge does not issue real credentials or publish messages. Application writer authentication/custody, controlled real Telegram round trip and later paper fills remain pending; keep Tailscale unchanged. Older handoffs below are historical.

E114's [restricted writer preparation](paper-writer-restricted-access-plan.md) is now implemented and locally verified at 60%. Run its single-report spare bundle to rehearse rules/recovery and collect missing firewall selectors without changing the real HBA file, logging into PostgreSQL or activating anything. E113 remains 80% pending policy acceptance. Real staging, credential custody and application review wiring remain subsequent gates.

E104 NOLOGIN staging, E107 inventory and E109 foundation are accepted. E113 verifies the corrected access runtime: 10 stages, 14 matching sources, 57.98s; policy findings keep that package at 80%. Next is the [restricted writer access plan](paper-writer-restricted-access-plan.md), not another inventory run. Preserve the current app identity and shared ACLs; review writer-specific connection isolation and missing firewall selectors. TLS stays deferred; connector remains unwired. No LOGIN, credential creation or order execution follows from this plan. Older handoffs below are historical.

Current E101/E102 handoff: catalog preflight accepted; proceed with [guarded NOLOGIN installation](paper-writer-installation.md), not the older preflight/recovery commands below. Administrator permission, exact existing-role TEMP preservation approval, backup and idle confirmations, rollback rehearsal and independent readback are mandatory. This stages permissions only; credentials, application review wiring and orders stay disabled.

2026-10-12: E97 synthetic recovery passed 14/14 and E99 accepts the restricted writer's 26/26 spare checks. The current handoff is [application permission preflight](paper-writer-application-preflight.md): catalog-only metadata from the configured database, one report, no application restart or permission changes. Review PUBLIC privileges, object collisions and administrator authority before the application writer installation. No previous storage/recovery/writer suite is repeated. Real transport and paper execution remain later gates; older next-handoff statements below are historical.

Current E96/E97: V28 storage/key attachment is accepted on spare (12/12 checks). The next active handoff is [backup recovery and audit permissions](paper-recovery-verification.md):14 new isolated checks and one report, without application restart or real credentials. It verifies a restricted audit reader, not the pending approval writer. Do not rerun the historical E95 deployment below.

Latest E94/E95: 24/24 delivery/recovery checks are accepted. [Application storage/key setup](paper-approval-storage.md) is now the active handoff: 12 new isolated checks followed by guarded V28 deployment and status/account verification, with one shareable report. It requires database and key backups. Earlier isolated commands below are historical; do not rerun them separately. Notification/approval/execution activation stays disabled.

Latest E92/E93: the 32 approval database/restart checks are accepted (185.262s). The next batch is [delivery and quote integration rehearsal](paper-delivery-integration.md), with 24 new combined checks and one report. Durable encrypted publication and transport adapters are implemented but application activation, credentials, approved risk and execution are not. Earlier E91 pending wording and commands below are historical; use only the latest handoff.

Current E90/E91 update: V27 application attachment/readback and visible portal read/lock are accepted. The existing account remains INR100,000 with zero reservations and revision0. Phase 3 begins with the [internal approval review candidate](paper-approval-review.md) and 32 isolated PostgreSQL checks pending on spare. No runtime approval, quote adapter or simulated execution is activated. Older deployment-pending text below records prior checkpoints, not the next instruction.

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

Current E89 handoff: use PowerShell 7, retain a current database backup, pull the reviewed revision, then run `ops/windows/DeployPaperAccountReadPhase.ps1 -Deploy -AttachLedger`. Confirm jobs are idle, enter the CURRENT private read token and confirm `BACKED_UP` only if true. Fresh account preflight must pass before deployment. See [complete attachment contract](paper-application-ledger.md#application-attachment-handoff). Never share the token in chat.

The runner passes the token through process/container configuration, never `.env` or the shareable report, and restores the caller's environment afterward. The container retains it across ordinary restarts. Future recreation without a configured token disables read access; supply it again through this runner. No persistent credential store is added here.

Compose configuration is checked without printing secrets. Only service/UI are built/recreated; database/volumes are retained. Existing configured schedules remain unchanged and can resume after restart. The GET has no writes; startup now applies additive V27 over the accepted V26 baseline. V27 creates ledger tables and attaches only the pristine existing account without changing cash or legacy history. Approval/execution remain unavailable.

Health waiting, Docker stages and HTTP reads are bounded. Tests cover anonymous denial on ports 8080/8081, authenticated proxy read, no-store headers, denial of another API route and HTML-shell availability. One compact `paper-ledger-read-<id>.json` stores revision, preflight, owner backup confirmation, timings, stages, bounded redacted Docker output, readback and failures. No automatic redeployment occurs. If deployment succeeded but a read failed, inspect evidence and use `-RequireLedger` without `-Deploy` for a read-only check.

Open `http://127.0.0.1:8081` on the spare laptop. Enter the token, refresh and compare cash/account identity with the report; Clear and lock must remove amounts. Browser display remains an owner check. Local tests mock HTTP/JDBC and do not certify real Docker/proxy/database/browser operation.

## Phase 2 migration contract

Current E88/E89 update: all 31 isolated checks passed on spare (218.014s). V27 now promotes that same SQL, and a V2 read-only ledger view plus guarded deploy/preflight is implemented. See [application attachment handoff](paper-application-ledger.md#application-attachment-handoff). Application deployment/readback remains pending. E87 candidate-only wording below is retained as the previous checkpoint, not current release state.

2026-10-09: E86 accepts Phase 1 spare evidence and owner-reported portal behavior. E87 implements the [durable ledger candidate and verification](paper-application-ledger.md). Candidate SQL is outside Flyway; internal commands are not wired to application APIs. Next gate is 31 isolated database checks, followed by reviewed runtime adoption. This does not repeat the old standalone adapter's accepted persistence test.

Use Phase 1 account identity/cash/history flags before selecting the migration path. Never create a second active funded account or reset balances. Existing history requires reconciliation before import. Support multiple fills per order through a reviewed migration, preserving legacy data and immutable transaction IDs. Define rollback that retains newly committed evidence; no ad-hoc deletion/reseed.

The isolated adapter's 256-command fixture ceiling is not production storage. Phase 2 requires durable projections/checkpoints and idempotency retention, account locks, exact-money invariants and bounded indexed reads. Freeze risk percentages, quote authority, costs, liquidity, P&L cost basis and settlement assumptions before execution; do not inherit unapproved fixture defaults.

## Progress accounting

Phase 1 spare verification and owner acceptance are recorded in E86. E88 closes the isolated ledger PostgreSQL checkpoint; E89 implements guarded application attachment/read views, with spare deployment/readback pending. G08/G09 parent implementation and runtime checkpoints remain incomplete; these partial milestones do not increase the full-goal weighted 12.4% baseline. Numerical predictive performance is unmeasured. Upstox historical-source questions remain open but do not block read-only portal or synthetic accounting work.
