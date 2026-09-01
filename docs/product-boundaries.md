# Product boundaries

## Personal use and execution safety

MarketBrain is designed only for the owner's personal research and trading workflow. It does not publish recommendations or support external users.

The initial execution mode is always `PAPER`:

- virtual starting capital is INR 100,000;
- market data can be live, but trades are simulated;
- a Telegram approval can create only a paper order;
- Paytm Money order placement is prohibited in PAPER mode;
- a later LIVE mode requires a separate explicit release decision.

## Telegram alert policy

Only three alert types exist:

| Type | Purpose | Action |
| --- | --- | --- |
| `NOTE` | Warn that a watch condition may require action in a stated time window. | None. |
| `BUY` | Request a buy decision after signal and risk validation. | Approve, reject, or view details. |
| `SELL_HOLDING` | Request sale of an existing holding after an exit condition. | Approve, reject, or view details. |

The system must suppress duplicate and non-actionable alerts. Telegram actions are received using outbound long polling, so no public callback is required. The bot accepts actions only from the configured private user and chat, and every action uses an expiring, one-time token with idempotent processing. No private service is exposed publicly.

The current Telegram foundation supports secure pairing and fixed test alerts only. An APPROVE test callback is audited but blocked; it cannot create a paper fill until live quote retrieval and risk revalidation are implemented.

## Signal validity

Every actionable signal carries a reference price, acceptable price zone, maximum slippage, validity window, and source timestamp. A fresh quote and risk reassessment are required immediately before a paper order is created. A BUY outside its zone must not be chased. A protective sell can remain valid during adverse movement under explicit exit-risk rules.
