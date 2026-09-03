# Market data provider feasibility

MarketBrain does not scrape exchange or broker websites. Every collected market value will retain its provider, retrieval time, and provider timestamp. A stale, missing, or contradictory feed blocks an actionable signal.

## Upstox: primary read-only market-data provider

The Upstox Analytics Token was manually verified from the spare laptop against a read-only market quote endpoint. The implementation now supports four manually invoked operations:

- import the official Upstox NSE instrument master and retain only `NSE_EQ` cash equities;
- retrieve a full quote with provider and last-trade timestamps;
- retrieve and persist a deliberately bounded historical-candle range.
- retrieve corporate actions by ISIN and store them as evidence without changing raw candles.

The provider remains disabled by default. The one-year Analytics Token must exist only in the spare laptop's ignored `.env` file. No Upstox order, funds, holdings, positions, or portfolio endpoint is implemented.

Every quote is classified as `FRESH`, `STALE`, or `INVALID`. Only a quote inside MarketBrain's configured 90-second freshness window is eligible for a future actionable signal. Stale quotes may be retained for audit but are not actionable. Historical rows must pass timestamp, positive-price, OHLC, and non-negative-volume checks before persistence.

The spare-laptop REST verification passed for instrument import, a fresh INFY quote, and a historical sample. The next controlled increment records the official current NIFTY 500 snapshot and backfills ten pilot stocks in resumable yearly chunks. It does not activate full-universe collection or live WebSocket streaming.

## Paytm Money: deferred broker candidate

The codebase retains a read-only client for Paytm Money's documented historical-data endpoint. It supports the documented `NSE` equity candle fields (`exchange`, `symbol`, `instType`, `interval`, `fromDate`, and `toDate`) and sends the local `x-jwt-token` only when explicitly enabled.

- The endpoint is documented by Paytm Money as beta, so its coverage, limits, and response quality must be tested before it becomes a production collector.
- `MARKETBRAIN_PAYTM_ENABLED=false` is the safe default. When it is disabled or the local token is absent, the client returns `NOT_CONFIGURED` without a network request.
- This client can retrieve historical data only. It has no order, holdings, or position implementation.
- A later feasibility run will request a small, read-only candle sample and validate timestamp, OHLC, volume, duplicates, gaps, and date coverage before any bulk backfill.

Paytm Money API access and tokens must remain in the spare laptop's untracked `.env` file. Never paste a token, password, OTP, or API secret into chat, source code, or Git.

## Nifty 500 membership history

The official current constituent file is obtained from the NIFTY Indices NIFTY 500 page. MarketBrain records the retrieval date, source URL, SHA-256 digest, complete source membership, and whether each row matched the current Upstox instrument master. This is an observed current snapshot only; it is never presented as historical membership.

The pilot backfill uses ten configured symbols from the latest current snapshot. A 15-year pilot becomes 150 independently checkpointed yearly chunks. The worker is disabled by default and requires an explicit job start. Data and authentication failures are retried at most three times. Connectivity, rate-limit, and temporary provider failures instead enter a persisted `WAITING_FOR_CONNECTIVITY` state with 1, 5, and 15 minute backoff, do not consume data attempts, and automatically continue when a retry succeeds. No credential-bearing provider error text is stored.

After completion, a read-only quality audit reports per-symbol coverage, logical duplicates, invalid OHLC/volume rows, calendar gaps over seven days, and close-to-close moves over 20 percent. Gaps and large moves are review candidates rather than automatic errors because listings, suspensions, splits, and bonuses can produce them. An optional one-request-per-instrument Upstox spot comparison verifies the latest stored close in the completed job range without mutating stored candles.

Quality decisions are append-only. A reviewer can document a provider omission, verify a genuine exchange move, associate a move with stored corporate-action evidence, record a provider adjustment, confirm an approved secondary-source backfill, or define an explicit feature-exclusion window. Confirming an omission alone does not permit training. Corporate-action, provider-adjustment, and manual-exclusion resolutions require an exclusion window, which is exposed through the `market_data_feature_exclusion` database view. Structural duplicates and invalid OHLCV data remain non-overridable.

Backtesting requires date-effective index membership to avoid survivor bias. The initial import format is:

```csv
symbol,isin,companyName,effectiveFrom,effectiveTo
INFY,INE009A01021,Infosys Limited,2026-01-01,
```

- Dates are ISO `YYYY-MM-DD`.
- `effectiveTo` is blank for an active membership period.
- Company names containing commas must be quoted using normal CSV syntax.
- The separate date-effective parser validates this historical format but does not claim that current constituents were historical constituents.
- We will obtain membership history through an official or appropriately licensed source, record the source/version, validate it, and then add a separately reviewed persistence job.
