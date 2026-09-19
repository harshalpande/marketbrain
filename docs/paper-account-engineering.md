# Offline paper-account engineering slice

This is the first bounded G08 accounting slice, not an activated paper account or a complete simulator. `PaperAccountEngineering` is a standalone JDK-only class. It is not a Spring bean, has no endpoint, writes no database, and makes no provider/model/broker/notification calls. The only command-line entry point is `--synthetic-paper`, using fixed synthetic inputs. No real proposal or user-supplied model is accepted by the CLI.

## Implemented and checked

- Exact integer paise; initial virtual capital INR 100,000 (10,000,000 paise); overflow rejects before balance mutation.
- Long-only fully funded BUY, owned-quantity SELL, and HOLD with no order. Whole-share quantities only.
- Independent cash and share reservations prevent concurrent double-spend or oversell. BUY reserves remaining quantity at the approved zone ceiling plus unspent caller-supplied fee budget.
- Approval IDs and order IDs are bound; identical command retries do not create new reservations. Fill IDs are bound to their full payload; duplicate fills do not debit twice, even after expiry. Conflicting retries fail.
- Explicit injected clock; validity-window, freshness, instrument, price-zone and reference-slippage validation. Future timestamps and clock rollback fail. Fill quote and risk evidence cannot predate actual approval; risk assessment cannot predate the supplied executable quote.
- Each fill requires fresh caller-supplied risk permission; this validates evidence structure/time, not the actual economic adequacy of a risk calculation.
- Caller supplies executable quote, fill price and costs. BUY fills cannot improve on that quote; SELL fills cannot improve on it. Fees are nonnegative, cumulative and bounded by the approval budget; SELL fees cannot exceed that fill's proceeds.
- Partial fills, full fills, cancellation and expiry preserve completed fills and release only remaining reservations. Terminal orders do not reopen.
- Immutable snapshots and in-memory chronological approval/fill/cancel/expiry journal support independent cash, fees and holdings reconciliation. Failed commands leave balances and reservations unchanged. All account mutations are synchronized; this is not multi-process concurrency control.
- Explicit bounded policy, approval and fill capacity: exhaustion fails without evicting idempotency evidence. Fixture limits are not approved runtime settings.

There are 26 embedded source-launch checks and 20 JUnit tests, including independent journal reconciliation, partial BUY/SELL expiry, concurrent approval double-spend, boundary timestamps, stale risk versus newer quote, idempotency, overfill, fee limits and overflow. Tests do not establish exchange-realistic fills or market profitability.

## One-file verification evidence

The parent preparation runner combines this suite with policy/source checks into one JSON. Paper output version is `PAPER_ACCOUNT_ENGINEERING_V1`. Production action counters remain zero; `accountingEvidence.syntheticOrdersCreated` and `syntheticFillCount` separately report ephemeral fixture activity. They must not be confused with zero synthetic work.

The reconciliation example buys 10 synthetic shares in two fills, sells 2 of a 4-share sell order and cancels its remainder, then reserves a new 2-share BUY. Its frozen invariants are:

| Item | Exact value |
|---|---:|
| Initial cash | 10,000,000 paise |
| BUY debits including fees | 100,020 paise |
| SELL credits after fees | 19,990 paise |
| Total paid fees | 30 paise |
| Ending cash | 9,919,970 paise |
| Reserved cash | 20,300 paise |
| Available cash | 9,899,670 paise |
| Owned shares / reserved SELL shares | 8 / 0 |
| Synthetic orders / fills / journal events | 3 / 3 / 7 |

The verifier must independently recompute initial cash plus credits minus debits, available cash, fees, filled quantities, holdings and active reservations from the journal/order records; the suite's boolean results alone are insufficient.

## Existing foundation preserved

V1 already seeds `Default Paper Portfolio` with INR100,000 and defines paper order/fill tables. `PaperPositionSizingService` already implements a separate risk sizing rule. Neither was changed or wired to this new component. The existing schema has a unique fill per order and lacks the full reservation/partial-fill lifecycle; safely integrating this core will require a reviewed persistence contract and migration. Existing risk-service percentages were not silently adopted as approved new simulator settings.

## Still pending before an actual paper pilot

1. Approval of production risk, expiry, quote source/freshness, slippage, realistic fee/tax/rounding and fill policies. The fixtures do not represent an exchange fee schedule or regulatory policy.
2. Durable transactions, restart/replay/reconciliation, cross-process locking and authenticated exactly-once approval ingestion. This ephemeral account is not attached to the separately tested evidence store. A JVM restart loses it.
3. Market calendar/session controls, executable bid/ask and quantity/liquidity handling, market impact, auctions, circuit limits, lot/tick sizes, instrument identity, settlement and corporate actions.
4. Portfolio risk/position sizing and authenticated risk permits bound to the precise proposal, quote and account revision; the current permit is trusted synthetic caller evidence, not a signed authorization.
5. Cost-basis/realized and unrealized P&L, marks/equity/drawdown, ledger storage, portal, alerts and user ACCEPT/REJECT lifecycle integration.
6. A real paper run with frozen settings and matured market outcomes. No live trading route is enabled by this slice.

No retrospective fitting, price-policy gate, data-rights gate or live collection permission changes as a consequence of passing these accounting tests.
