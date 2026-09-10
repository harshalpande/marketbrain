# News and event intelligence design

Status: approved target design; permission register and disabled connector foundation are implemented.

## Purpose

MarketBrain will use market and company news as a governed secondary source of evidence for swing-trading research. News may raise, lower, or veto the confidence of a technically generated candidate. It must never independently place an order or bypass the risk engine and human approval.

## Sources and permission boundary

The source layer is provider-neutral:

- Marketaux is the initial API candidate for a quota-controlled, read-only pilot.
- NSE, BSE, SEBI, RBI and company investor-relations disclosures are primary evidence sources.
- RSS adapters are supported, but an individual feed remains disabled until its published terms explicitly allow the intended automated storage and analysis or the publisher provides written consent.
- A source-permission register records the permitted fields, attribution requirement, storage period, local-AI permission, review evidence and approval date.
- Full copyrighted articles are not stored unless the applicable licence explicitly permits it.

Personal and non-commercial use does not override a publisher's terms. Economic Times, Livemint and Business Standard are therefore permission-gated candidates rather than enabled feeds.

## Ingestion and governance

Every provider uses an independent checkpoint so a failure or quota exhaustion cannot corrupt another source. API polling is quota-aware; RSS polling uses conditional requests such as `ETag` and `If-Modified-Since` when supported.

Each accepted item records, subject to its source permission:

- provider item ID, canonical URL, source domain and content hash;
- headline and permitted snippet;
- provider publication time and MarketBrain first-seen time;
- matched instrument, symbol, ISIN and entity aliases;
- story-cluster ID for cross-source deduplication;
- event class, direction, materiality and expected horizon;
- verification state and supporting evidence links;
- model, prompt and rule versions used for derived fields.

The publication and first-seen timestamps are immutable. Historical analysis may use only information available at the evaluated point in time.

## Entity linking and verification

Entity matching must use symbol, ISIN, company identity and date-effective aliases. A name fragment alone is insufficient; for example, `Reliance` must not match every company containing that word, while `IDEA`, Vodafone Idea and Vi must map to the same governed identity.

Evidence states are:

| State | Meaning | Trading use |
| --- | --- | --- |
| `VERIFIED_PRIMARY` | Confirmed by an exchange, regulator or company filing. | Eligible as a feature. |
| `CORROBORATED` | Confirmed by at least two independent reputable sources. | Eligible subject to materiality and risk rules. |
| `UNVERIFIED` | Single-source, ambiguous or rumour-like report. | Informational only; cannot create a trade candidate. |
| `CONFLICTED` | Reliable sources disagree. | Blocks a news-driven action pending resolution. |

Typical event classes include earnings, guidance, dividends and corporate actions, regulation, litigation or fraud allegations, management changes, mergers and acquisitions, contracts, financing, credit ratings and macroeconomic events.

## Features, confidence and Ollama

News becomes a versioned point-in-time feature snapshot containing materiality, direction, source reliability, corroboration, novelty, event horizon, market reaction and elapsed time. Its incremental value is measured by comparing out-of-sample results with and without news features.

Confidence is produced by backtested and calibrated models. Ollama must not invent an 80–90 percent score. Ollama explains the cited evidence and conflicts in plain language; deterministic rules, calibrated models and the risk engine remain authoritative.

## Decision and alert policy

The risk engine evaluates technical evidence, news evidence, portfolio exposure, liquidity, volatility, signal validity and source quality. A single alarming headline can freeze new buys and create a `RISK_REVIEW`, but it cannot automatically sell a holding.

Supported news-related Telegram outcomes are:

- `NEWS_NOTE`: material information with no requested action;
- `RISK_REVIEW`: a holding or candidate needs human attention;
- `BUY` or `SELL_HOLDING`: a fully verified candidate that has passed the normal strategy and risk gates.

Actionable alerts retain the existing reference price, acceptable price zone, maximum slippage, validity window and source timestamp. Human approval is followed by a fresh quote and complete risk recheck. Duplicate articles in the same story cluster produce one evolving alert, not repeated notifications.

## Retention

Retention is driven by the source licence and audit needs:

- licensed full text, if any: short retention such as 30 days;
- permitted headline, URL and source metadata: normally 12 months;
- feed checkpoints and deduplication hashes: retained long enough to prevent re-ingestion;
- derived factual event records and numeric features: retained for audit and backtesting only where permitted;
- official exchange, regulator and company disclosures: retained according to the applicable official-source policy.

An audited cleanup job removes expired content without silently deleting feature provenance required by a reviewed model. If a licence requires stronger deletion, that source-specific rule wins.

## Initial delivery sequence

1. Create the source-permission register and reusable publisher permission request.
2. Implement disabled provider contracts and deterministic test fixtures.
3. Run a 7–14 day read-only Marketaux coverage pilot with a maximum of 100 accepted unique articles per day.
4. Measure NIFTY 500 relevance, latency, missed stories, duplicates and false entity matches.
5. Add official event sources and only explicitly permitted RSS feeds.
6. Persist reviewed point-in-time news features without signals or orders.
7. Backtest and calibrate technical-only versus technical-plus-news models.
8. Enable deduplicated Telegram notes, then separately review actionable paper-trading candidates.

The news module must not alter the already governed daily candle collection and technical snapshot pipelines until its own quality and point-in-time audits pass.

## Implemented foundation

The first implementation milestone creates:

- a database-backed source-permission register seeded with Marketaux, Economic Times RSS, Mint RSS, Business Standard RSS, NSE disclosures, BSE disclosures, SEBI public updates and RBI press releases;
- checkpoint, article-metadata, story-cluster, entity-match and derived-event tables;
- disabled-by-default Marketaux and RSS connector contracts, plus official-event connector registration with source-specific extractors still gated for review;
- guarded article persistence that stores only fields permitted by the source register;
- offline Marketaux and RSS parsers for deterministic fixture tests;
- `/api/v1/news/ingestion/status`, which reports source readiness without contacting providers;
- `/api/v1/news/ingestion/run-once`, which manually runs only sources that pass every global and source-level gate;
- `ops/windows/VerifyNewsIngestionFoundation.ps1`, which proves all eight sources are implemented, persisted, and blocked by governance.

The defaults keep `marketbrain.news.enabled=false` and `marketbrain.news.live-fetch-enabled=false`. Deployment of this foundation must not call providers, store articles, call Ollama, create news features, create signals, create orders, or perform broker actions.
