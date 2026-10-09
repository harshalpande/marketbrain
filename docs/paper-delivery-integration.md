# Phase 3: delivery and quote integration rehearsal

**Accepted update:** E94 closes this 24-case spare checkpoint in 199.542s. Do not repeat its handoff below. E95 [application storage/key setup](paper-approval-storage.md) is next and supersedes the earlier outside-Flyway statement: V28 now promotes these schemas, while real transport and execution remain disabled.

2026-10-09. E92 accepts the previous **32/32** isolated approval checks in **185.262 seconds**. No repeat of that bundle is requested. E93 connects the internal publication, delivery, callback and quote-review components in a new **24-case isolated rehearsal**. This is partial Phase 3 engineering, not activated application approval or execution.

## What is implemented

- Atomic proposal/token/delivery creation, including concurrent duplicate publication and rollback. Reusing the same proposal identity and exact payload reconciles publication without generating new tokens.
- A durable delivery record with AES-256-GCM-encrypted action tokens, associated with the proposal identity. Approval lookup still stores token hashes. Explicit key injection is required; the all-zero key exists only in isolated synthetic fixtures. No credential or action token is exported in the shareable report.
- A single application send attempt per proposal. PENDING can be claimed as SENDING before network I/O. A validated acknowledgement becomes SENT; a missing or invalid acknowledgement becomes UNCERTAIN. SENDING after a crash and all attempted states are **never automatically resent**. This does not claim exactly-once delivery by Telegram or its HTTP infrastructure. Operational reconciliation/key recovery remains a release gate, not an automatic repair.
- A private `mbp:` callback branch in the existing authenticated Telegram long-poll handler. It remains disabled when the optional `PaperApprovalCallback` bean is absent; this package deliberately registers no such bean. Existing notification handling remains unchanged. A database failure propagates without acknowledging the action, preserving retry through the existing polling cursor. A saved terminal receipt makes callback retries idempotent.
- Explicitly constructed Telegram and Upstox HTTP adapters: pinned HTTPS hosts/paths, no redirects, a three-second HTTP response/body deadline with cancellation, bounded 32KiB response, no adapter-level retry, and sanitized failures. Quote I/O occurs outside approval database locks. JDBC connection acquisition remains subject to the eventual application's pool configuration; the HTTP deadline is not an end-to-end database-plus-network guarantee.
- Exact active instrument/provider mapping and strict quote identity, numeric-price and time checks. LTP freshness uses `last_trade_time`, not merely the timestamp of a newly received snapshot. Only tiny price representation noise (at most INR0.00001 from a two-decimal value) is rounded; other non-paise prices fail closed. LTP is not a simulated execution price or proof of liquidity.

The adapters follow the official [Upstox full-market-quote contract](https://upstox.com/developer/api-documentation/get-full-market-quote/) and [Telegram sendMessage/callback contract](https://core.telegram.org/bots/api#sendmessage). Actual entitlement, payload compatibility, market-hours freshness and private callback transport remain unverified until a separately controlled spare test. A recipient can revoke binding after the send claim: this cannot atomically recall a message, but approval rechecks the current private binding and expiry.

## What is deliberately not activated

`paper/delivery-v1.sql` and `paper/approval-v1.sql` remain **outside Flyway**. There is no application publication endpoint, dispatch worker/scheduler, callback bean registration, credential provisioning or approval-table migration. The current account/portal stays read-only. No real Telegram message or Upstox request is made by this rehearsal. No LLM, new market data, account reset, reservation, order, fill or Paytm call is involved.

`ACCEPTED_EXECUTION_BLOCKED` is a durable review receipt, not spending authority. A future paper execution transaction must obtain a new fresh quote and recheck account/risk/expiry before atomic reservation. Fixture risk limits are not approved operating policy.

## One combined verification bundle

The disposable PostgreSQL suite contains **21 prepare + 3 restart checks**:

| Group | What is checked |
| --- | --- |
| Publication | Atomic creation, replay, conflicting identity, rollback, concurrent duplicate, revoked recipient |
| Delivery | Successful/concurrent send, expiry, revocation, wrong key, lost acknowledgement, interrupted SENDING, immutable terminal evidence |
| Review | ACCEPT with strict quote adapter, REJECT without quote, mismatched instrument, disabled provider mapping, old trade in fresh snapshot, callback replay |
| Restart | Pending delivery can send once; SENT/UNCERTAIN cannot resend; review receipt and account are preserved |

The suite uses actual PostgreSQL but **fake in-process HTTP responses**, not external transports. Separate offline unit tests cover the HTTP request/parser, size/deadline controls and optional Spring callback wiring. Final recovery must show INR100,000, zero reserved cash, revision/orders/fills zero, one review receipt, three delivery records and one uncertain delivery. Counts describe the final recovery fixture; negative cases deliberately change other synthetic schemas.

The runner validates exact scenario names, booleans, accounting, timings and safety counters. One report embeds revision/source hashes, phase checks, progress, Docker output and cleanup. The local PowerShell workflow also tests malformed reports, simulated failures and cleanup paths without running Docker. See [local verification](evidence/paper-delivery-local-20261009.json).

## Run on the spare laptop

Use PowerShell 7 with Docker Desktop running. No application restart or deployment, database backup, read token, provider token or bot secret is needed for this isolated test.

```powershell
$ErrorActionPreference = 'Stop'
Set-Location 'C:\Users\Harshal S Pande\Documents\workspace\marketbrain'
if ($PSVersionTable.PSVersion.Major -lt 7) { throw 'Please use PowerShell 7.' }
$pending = @(git status --porcelain)
if ($LASTEXITCODE -ne 0) { throw 'Cannot inspect repository.' }
if ($pending.Count -gt 0) { throw 'Local changes found; preserve/review them before pulling.' }
git -c gc.auto=0 -c maintenance.auto=false pull --ff-only origin main
if ($LASTEXITCODE -ne 0) { throw 'Git pull failed; do not run the test.' }
& '.\ops\windows\TestPaperPersistenceBundle.ps1' -ApprovalDelivery -BuildTimeoutSeconds 1800
```

Expected status: `ISOLATED_DELIVERY_PASSED_LIVE_TRANSPORT_AND_EXECUTION_BLOCKED`. Share **only the printed `paper-delivery-<timestamp>-<id>.json`** from `C:\MarketBrainData\Review`, including on failure. The 30-minute build limit is a ceiling, not a duration forecast. Image/dependency download time varies; stage heartbeats and elapsed times show actual progress. No automatic suite retry occurs.

Successful labelled fixture containers, their anonymous volumes and internal network are removed. Failed fixtures are retained with stop requested; inspect cleanup evidence. Reports and built images remain. No application resources are pruned. Fixtures have no host mounts or published ports and use an internal Docker network; image builds/pulls do require internet access.

## Next gates, in order

1. Accept this one spare report. Fix only evidenced discrepancies; do not repeat earlier accepted suites unnecessarily.
2. Implement/review application migration, least-privilege access, persistent encryption-key provisioning/rotation and operator recovery for uncertain delivery. Keep credentials out of reports and chat. Establish governed publication/dispatch and real private callback wiring.
3. With explicit operator consent, verify **review-only** real Telegram delivery/callback and entitled Upstox quotes. Use approved risk limits and known account state; never assume synthetic checks establish external reliability.
4. Integrate fresh atomic paper reservation/execution, operational portfolio views and approved fill/cost/liquidity/P&L policy. HOLD remains order-free; concurrent receipts are not independent spending permits.
5. Complete end-to-end and backup/restore acceptance before the month-plus pilot. Numerical predictive validation is a separate gate. Paytm real orders remain disconnected.

E93 does not complete G08/G09 or increase the **12.4% full-scope parent baseline**. This measures a bounded engineering milestone, not forecast accuracy.
