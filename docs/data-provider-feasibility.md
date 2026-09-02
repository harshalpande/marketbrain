# Market data provider feasibility

MarketBrain does not scrape exchange or broker websites. Every collected market value will retain its provider, retrieval time, and provider timestamp. A stale, missing, or contradictory feed blocks an actionable signal.

## Upstox: primary read-only market-data provider

The Upstox Analytics Token was manually verified from the spare laptop against a read-only market quote endpoint. The implementation now supports three manually invoked operations:

- import the official Upstox NSE instrument master and retain only `NSE_EQ` cash equities;
- retrieve a full quote with provider and last-trade timestamps;
- retrieve and persist a deliberately bounded historical-candle range.

The provider remains disabled by default. The one-year Analytics Token must exist only in the spare laptop's ignored `.env` file. No Upstox order, funds, holdings, positions, or portfolio endpoint is implemented.

Every quote is classified as `FRESH`, `STALE`, or `INVALID`. Only a quote inside MarketBrain's configured 90-second freshness window is eligible for a future actionable signal. Stale quotes may be retained for audit but are not actionable. Historical rows must pass timestamp, positive-price, OHLC, and non-negative-volume checks before persistence.

This REST increment is a prerequisite for, but separate from, the Upstox V3 live WebSocket collector. Streaming will be added only after the spare-laptop REST verification passes.

## Paytm Money: deferred broker candidate

The codebase retains a read-only client for Paytm Money's documented historical-data endpoint. It supports the documented `NSE` equity candle fields (`exchange`, `symbol`, `instType`, `interval`, `fromDate`, and `toDate`) and sends the local `x-jwt-token` only when explicitly enabled.

- The endpoint is documented by Paytm Money as beta, so its coverage, limits, and response quality must be tested before it becomes a production collector.
- `MARKETBRAIN_PAYTM_ENABLED=false` is the safe default. When it is disabled or the local token is absent, the client returns `NOT_CONFIGURED` without a network request.
- This client can retrieve historical data only. It has no order, holdings, or position implementation.
- A later feasibility run will request a small, read-only candle sample and validate timestamp, OHLC, volume, duplicates, gaps, and date coverage before any bulk backfill.

Paytm Money API access and tokens must remain in the spare laptop's untracked `.env` file. Never paste a token, password, OTP, or API secret into chat, source code, or Git.

## Nifty 500 membership history

Backtesting requires date-effective index membership to avoid survivor bias. The initial import format is:

```csv
symbol,isin,companyName,effectiveFrom,effectiveTo
INFY,INE009A01021,Infosys Limited,2026-01-01,
```

- Dates are ISO `YYYY-MM-DD`.
- `effectiveTo` is blank for an active membership period.
- Company names containing commas must be quoted using normal CSV syntax.
- The current parser validates this file only; it does not download, scrape, or change the database.
- We will obtain membership history through an official or appropriately licensed source, record the source/version, validate it, and then add a separately reviewed persistence job.
