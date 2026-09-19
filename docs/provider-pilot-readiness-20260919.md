# Provider pilot readiness — 2026-09-19

Status: **READ_ONLY_REVIEW_COMPLETE; ACCOUNT_AND_SOURCE_EVIDENCE_PENDING**.

This is the provider lane of the parallel pilot preparation. Repository inspection and public official-documentation browsing only: no provider API requests, local services, account/network changes, source re-collection, support messages, model calls or orders. Existing history and the pending Upstox email reply are preserved. Public product support is not proof that this account is entitled, currently configured or working.

## Code, runtime evidence and remaining work

| Area | Code present and inspected | Account/runtime evidence | Missing before a connected pilot |
|---|---|---|---|
| Upstox REST/history | `UpstoxReadOnlyClient`: NSE master, full quote, Historical V3, intraday candles and corporate-action GET calls; enabled/token gating; explicit 10s connect/45s read timeouts; provider error classification. Controller delegates import/quote/sync operations to persistence services. | Earlier project reports establish collection and bounded saved-data diagnostics; this pass does not recheck account/session validity. The archive records earlier quote verification, not a current freshness guarantee. | Current token scope/expiry/entitlement without exposing token; exact price-adjustment/revision policy and reconciliation with the stored data; approved capture policy. |
| Upstox streaming | No WebSocket/Protobuf market streamer found in the inspected Java source/POM. REST intraday support does not constitute streaming. | No connected-stream, reconnect or market-hours load evidence established here. | Auth/authorization flow, Protobuf decoder, bounded queue, timestamps, reconnect/backoff, gap/dedup checks, aggregation and controlled runtime acceptance. |
| Paytm market data | `PaytmMoneyHistoricalClient` is a gated, manually callable historical-chart POST wrapper using `x-jwt-token`; raw response still needs validation. No order placement in this client. | Current account activation, token scope, entitlements and public static egress are **unverified**. Earlier project correspondence recorded the static-egress requirement; it is not a new confirmation in this pass. | Current account-specific auth/session and read-only live-feed contract; product/limits; instrument mapping; approved egress setup; timeout/error hardening and bounded read-only proof. No live execution work in this lane. |
| Marketaux news | Connector requests India/English articles and filtered entities; parser extracts publication time, entity identifiers and provider sentiment/match scores. Ingestion checks global, live-fetch and source-permission gates. Repository uses content hashes/conflict suppression, permission-controlled headline/snippet storage and optional expiry. | No current subscription, quota remaining, complete Nifty 500 entity coverage or licensed retention evidence verified. | Account limits/rights, company/ISIN resolution, first-seen/revision records, durable entity linkage, daily request accounting, request timeout wiring, bounded backoff, expiry enforcement and news-triggered reassessment. |

The default `application.yml` keeps Upstox, Paytm and news/live-fetch switches off. This says nothing about the spare laptop's ignored environment overrides; none were read. No credentials are required in shared evidence.

## Facts resolved from official documentation

- Upstox Analytics Token documentation currently lists historical, quote and WebSocket categories under read-only access, with one-year token validity and no static-IP requirement for those listed market-data categories. This removes the need to assume that a separate trading token or Paytm-style static IP is inherently needed for the Upstox market-data pilot. The actual account/token must still be checked. [Official Analytics Token reference](https://upstox.com/developer/api-documentation/analytics-token/).
- Upstox Feed V3 uses WebSocket and Protobuf with authenticated redirection. The normal table lists two connections per user and distinct single-mode/combined subscription limits; normal full-mode single-category capacity is 2,000 instruments. A 500-stock design therefore fits the published count on paper, but bandwidth, freshness, account permissions and runtime capacity still need measurement. Preserve provider timestamps separately from local receipt time; neither substitutes for the other. [Official Feed V3 contract](https://upstox.com/developer/api-documentation/v3/get-market-data-feed/).
- Historical V3 advertises daily history from January 2000 and minute/hour history from January 2022, with unit-dependent request windows. Therefore the 15+ year objective must be frequency-specific, not a claim of 15 years of minute data from this endpoint. The inspected page's candle fields and timestamp semantics do not establish the adjustment/version history of our stored snapshot. [Official Historical V3 contract](https://upstox.com/developer/api-documentation/v3/get-historical-candle-data/).
- Marketaux documents article publication time, entity fields and plan-dependent page limits. It distinguishes usage exhaustion (402), endpoint entitlement (403) and short-period rate limits (429). These are separate control paths; `limit` is not a daily consumption budget. Our receipt/first-seen time must be captured independently. API field documentation is not a retention licence. [Official Marketaux reference](https://www.marketaux.com/documentation).
- The official Paytm developer portal was reachable but exposed no usable contract text to this review tool. This is not evidence that Paytm lacks documentation or functionality. Current account-visible documents or a redacted provider response are needed before implementing auth/live feed semantics. [Official Paytm developer portal](https://developer.paytmmoney.com/).

Public pages are changeable; recheck contracts before connected deployment. No unofficial article was used to infer account rights or endpoint behaviour.

## Concrete code gaps kept separate from source questions

1. Upstox controller comments use “read-only” in the broker sense. `/instruments/nse/import`, `/quote`, `/candles/import` and `/corporate-actions/sync` can persist application data. **Do not call them as supposedly non-mutating diagnostics.** Corporate-action event presence does not prove candle adjustment policy or historical event vintages.
2. Marketaux's `maximumArticlesPerDay` currently becomes the per-request `limit`; the inspected ingestion path does not maintain a daily request/consumption ledger. `requestTimeoutSeconds` exists in configuration but is not applied by this connector. A property name is not enforced behaviour.
3. The Marketaux parser creates entity candidates, but `NewsArticleRepository.saveCandidate` does not persist those entity candidates in its article insert. Symbol parsing alone does not establish durable, unambiguous Nifty 500 mapping. Unknown publication times remain null rather than invented.
4. Paytm's client does not configure explicit connect/read timeouts, and its error result does not distinguish HTTP throttling/entitlement from other REST exceptions. Fixes require a separately scoped integration batch; none were made during this readiness review.

## What remains genuinely unknown

| Evidence needed | Owner / next evidence | Closure rule |
|---|---|---|
| Whether each affected historical OHLCV series is raw or adjusted, actions covered, factors/effective dates, price-versus-volume treatment and revision/backfill policy | Provider answer already requested; then reconcile to preserved ingestion/repair evidence | Keep `PENDING_EXTERNAL_REPLY`. A generic current provider answer is insufficient if it cannot be linked to the stored series/version. No resend or automatic price repair. |
| Original historical availability and earlier data versions | Existing preserved source/version records if any; otherwise prospective receipt evidence | Retrospective snapshot remains explicitly limited. Today's receipt timestamp cannot be backdated into historical availability. |
| Applicable storage, derived research and sharing/retention scope | Owner supplies redacted plan/terms references, effective date and permitted scope; no keys | Record the actual applicable source rights, not inferred rights from successful HTTP access. |
| Paytm auth/callback state, request-token naming, expiry/refresh/logout and market-data scopes | Redacted current account documentation/provider answer | Auth design and read-only probe remain blocked until semantics and egress prerequisites are resolved. |
| Actual provider capacity and news coverage | Redacted product/limit screen or current contract, then separately approved bounded verification | Limits, runtime observations and exclusions recorded separately; no all-500 assumption based on a successful small sample. |

## Safe next work and stopping rules

**Now:** reuse stored evidence, review the already-pending Upstox reply when received, and obtain only redacted product/terms information already available to the owner. Provider waiting does not block deterministic paper-ledger fixtures, replay tests or capture-policy preparation.

**After explicit connected-pilot release:** validate one approved instrument/small read-only scope with a fixed call/time budget, sanitized failure categories and one evidence JSON. Use no automatic retry on authentication/permission failure, no full-universe scan, no provider import/sync route labelled read-only, and no trade endpoint. Confirm quotas and timeouts first. Streaming verification additionally needs an approved subscription duration, instrumentation and stop conditions. This document does not authorize or schedule any such request.

**Never use this review to:** reset stored history, clear evidence gates, treat provider sentiment as calibrated prediction probability, start model fitting, enable collection, provision a static-IP gateway, or activate real orders. Upstox, Paytm and Marketaux readiness are separate; one provider's green check cannot certify another.

## Inspection record

Source root: `marketbrain-service/src/main/java/in/marketbrain/`.

- `marketdata/upstox/UpstoxReadOnlyClient.java`, `UpstoxMarketDataController.java`.
- `marketdata/paytm/PaytmMoneyHistoricalClient.java`.
- `news/MarketauxNewsConnector.java`, `MarketauxNewsResponseParser.java`, `NewsIngestionRunService.java`, `NewsArticleRepository.java`; source search across `news` for timeout, quota, scheduling and entity use.
- `configuration/MarketBrainProperties.java`, `NewsProperties.java`; `marketbrain-service/src/main/resources/application.yml`.
- Source/POM search for WebSocket/Protobuf streamer implementation; this was a scoped readiness inspection, not a new full-project or live-system audit.
- `docs/roadmap.md`, `docs/system-design.md`, `docs/evidence-register.md`, `docs/numerical-research-scope-decision.md` and archived `docs/archive/2026-09-18/data-provider-feasibility.md` (historical claims clearly distinguished from fresh verification).

No application test suite was rerun for this documentation-only provider lane. Parent milestone verification covers any separate engineering changes.
