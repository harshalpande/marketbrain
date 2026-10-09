# Phase 3: durable approval review candidate

**Accepted update, 2026-10-09:** E92 verifies all 32 spare checks in 185.262s; [acceptance](evidence/paper-approval-spare-acceptance-20261009.json). Do not rerun the historical handoff below. E93's [24-case delivery/quote rehearsal](paper-delivery-integration.md) is next and supersedes the earlier unimplemented-adapter/outbox descriptions. Approval tables and external transport remain application-disabled; execution is still blocked.

2026-10-09. E90 accepts the deployed read-only ledger and the owner's Read/Refresh and Clear/Lock screenshots. E91 begins approval/risk integration with an internal candidate and a **32-case isolated PostgreSQL suite**. It does not activate Telegram actions, application writes or execution. The existing read-only portal remains unchanged.

## Implemented boundary

`PaperApprovalReview` is not a Spring bean, controller or scheduler. Candidate SQL `paper/approval-v1.sql` stays outside Flyway. There is no application migration for approval tables in this package. The existing Telegram action processor continues to block approvals pending fresh-quote integration.

An internal publisher can issue separate 256-bit random ACCEPT and REJECT tokens for one immutable proposal. Only SHA256 token hashes persist in the candidate approval tables. The proposal binds the portfolio, instrument, exact terms, account revision, recipient user/chat and policy fingerprint. The read-only portal token is not approval authority. HOLD cannot create action tokens; its eventual recording path remains separate.

The review flow is:

1. Validate private callback identity against the active binding and hashed token before fetching a quote.
2. Obtain a server-owned quote outside database transactions/locks.
3. Recheck binding and proposal, lock the account in ledger lock order, then recheck expiry, revision and quote/risk evidence.
4. Persist one terminal review receipt. Identical-token retries return it, even after expiry. The opposite action cannot reverse it. Callback IDs are unique across proposals.

Checks cover instrument/provider identity, observation/receipt times, freshness, acceptable price zone, slippage, quantity/notional, cash including existing reservations/fee allowance and owned shares excluding reservations. A changed policy fingerprint blocks acceptance even if its identifier was reused. Ledger head/checksum and cash-mirror inconsistency block acceptance. Indexed primary/unique-key reads avoid full journal scans; database lock/statement/idle transaction deadlines are 3/10/15 seconds.

`ACCEPTED_EXECUTION_BLOCKED` means the bounded review passed, **not permission to trade**. No ledger revision, cash, reservation, order or fill is changed by this class. Acceptance must be revalidated when a future execution transaction reserves funds. Two otherwise valid proposals can both receive review receipts against the same revision; these are not spending permits.

## Verification and evidence

- Offline Java covers decision boundaries, identity/token contracts, arithmetic and absent runtime wiring. Offline PowerShell covers exact-case validation, numeric/safety mutations, partial failure, one-report checkpointing and owned-resource cleanup.
- Spare suite: 30 preparation cases and two fresh-JVM recovery cases after restarting only disposable PostgreSQL. It exercises actual transactions, duplicate races, recipient revocation/account changes during quote loading, policy drift, immutability, expiry and durable receipt recovery. Fixtures start from real V1/V2/V3 and the accepted ledger SQL in isolated schemas; this is not proof of an application migration against all deployed tables.
- External provider, Telegram and model call counts must remain zero. Final recovery fixture cash is 10,000,000 paise, reserved cash/revision/orders/fills zero, one terminal review receipt. Some negative/race fixtures deliberately alter synthetic state; report totals describe the recovery fixture, not aggregates over all schemas.
- The restart fixture retains one synthetic token in a separate disposable helper table to replay it after restart. Production candidate tables store hashes only; no raw token is exported in the report. Checksums detect tested corruption, not a privileged database attacker.
- [Local verification](evidence/paper-approval-local-20261009.json). Runtime acceptance remains pending until the owner shares the new report. Do not rerun accepted Phase 1/2 suites as the next action.

## Spare-laptop handoff

Use PowerShell 7 in the spare repository. Docker Desktop must be running. No application token, provider key or database credential is requested. The runner builds a separate verification image, creates a labelled internal network with no published ports/host mounts, runs the fixed suite, restarts only its fixture database, and writes **one** `paper-approval-<timestamp>-<id>.json` under `C:\MarketBrainData\Review`. Progress, timings, revision/source hashes and stdout/stderr are embedded. Image pulls/builds need network access; fixture tests do not access market providers.

```powershell
$ErrorActionPreference = 'Stop'
Set-Location 'C:\Users\Harshal S Pande\Documents\workspace\marketbrain'
if ($PSVersionTable.PSVersion.Major -lt 7) { throw 'Please use PowerShell 7.' }
$pending = @(git status --porcelain)
if ($LASTEXITCODE -ne 0) { throw 'Cannot inspect repository.' }
if ($pending.Count -gt 0) { throw 'Local changes found; preserve/review them before pulling.' }
git -c gc.auto=0 -c maintenance.auto=false pull --ff-only origin main
if ($LASTEXITCODE -ne 0) { throw 'Git pull failed; do not run the test.' }
& '.\ops\windows\TestPaperPersistenceBundle.ps1' -ApprovalReview -BuildTimeoutSeconds 1800
```

Expected success: `ISOLATED_APPROVAL_PASSED_TRANSPORT_AND_EXECUTION_BLOCKED`. Share the single printed report, including on failure. A 30-minute build ceiling is a timeout, not an expected duration; actual timing depends on image/dependency caches. Do not automatically retry a failed suite. Successful owned fixture containers/anonymous volumes/network are removed; failed fixtures are preserved with stop requested. Built images and the report remain. No global prune or application restart occurs.

## Still required before application approval release

1. Review this spare result, then freeze a migration and least-privilege application write boundary. The candidate is not deployed by this test.
2. Connect the existing authenticated Telegram long-poll handler to proposal-level tokens. Caller-supplied user/chat fields are not trusted identity on their own. Implement durable publication/outbox and uncertain-issuance recovery; the current internal issuance returns raw tokens once and is not a production notification publisher.
3. Approve the quote provider, strict adapter network deadline/cancellation and risk thresholds. `QuoteSource` is an unwired interface, not an implemented network timeout. Fixture freshness/slippage/quantity settings are not production defaults. Broader daily exposure/loss/concentration, session and data-quality rules remain required.
4. Bind accepted reviews to an idempotent ledger reservation/execution transaction with a new fresh quote/risk/account check; never turn these receipts directly into fill authority.
5. Add operational account/order/holdings views and approve fill/cost/liquidity/P&L/settlement policy. Current portal correctly says P&L is not calculated. Complete backup/restore and end-to-end acceptance before the month-long pilot. Real Paytm orders remain disconnected.

These are partial G08/G09 engineering milestones. They do not establish predictive accuracy, complete Phase 3, or change the 12.4% weighted parent-goal baseline.
