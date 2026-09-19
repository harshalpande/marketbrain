# Price-policy evidence still needed, without recollecting history

2026-09-19, E54 update: **PENDING_EXTERNAL_REPLY**. The owner reports sending the neutral technical clarification email to Upstox support. No reply, delivery acknowledgement or ticket number has been supplied. The assistant has not sent any message. This is a source-evidence requirement, not a model-training failure; preserve existing history and repair work. No new provider download is authorized by this note.

The owner requested no disclosure of project purpose. The revised email asks general API questions only, without naming the project, stored dataset or pilot stocks. The stock-specific questions below remain internal review requirements, not a claim about the email actually sent. Do not resend automatically. [Parallel evaluation-engineering work and session handoff](numerical-evaluation-engineering-plan.md).

The bounded repair report completed in 8.828s and linked all four scoped stocks to previously reviewed completed backfill jobs. It inspected ledger rows but recovered **zero relevant adjustment references and zero corporate-action rows** for 2024-10-22..2026-07-06. This is not evidence that no corporate actions occurred. Repeating the unchanged query will not resolve the missing policy.

The official [Upstox Historical Candle V3 documentation](https://upstox.com/developer/api-documentation/v3/get-historical-candle-data/) was checked on 2026-09-19. It defines OHLCV and availability/request limits, but the retrieved page does not specify split/bonus/dividend adjustment semantics, factor vintages or volume rebasing. Do not infer historical-API behavior from a chart product or another broker. This is a limited page review, not proof that no provider statement exists elsewhere.

## Internal clarification checklist (earlier draft; not the neutral email)

For NSE cash-equity daily candles returned by Upstox Historical Candle API, please confirm:

1. Are historical open/high/low/close raw exchange prices or adjusted? Which corporate actions are included (splits, bonuses, dividends, rights, mergers/demergers)? Is volume adjusted, and by which convention?
2. When a later action occurs, are earlier candles restated? Are adjustment factors and their effective/publication dates available, and can a historical data vintage be reproduced?
3. Does this policy apply to previously collected responses, or can behavior differ by API version, interval, security or collection date? Please provide an official reference and applicable period/version rather than assuming a current answer proves older stored values.
4. What authoritative action history/factors can establish the treatment for MARUTI, NATIONALUM, TARIL and LEMONTREE over 2024-10-22..2026-07-06, including any later actions that could restate that stored window?

No credentials/account details are needed in the shared answer. Match evidence to actual recorded instrument identities, provider endpoint and collection timestamps. The owner need not reconstruct prior assistant actions from memory. A provider policy alone does not certify that every stored row followed it: match it to captured vintages and bounded official action/price evidence. Any further acquisition or adjustment implementation needs explicit reviewed scope; never redownload everything or infer a split from a large price move alone.

## What can progress while this remains open

- Export deterministic features and **uncertified stored-price arithmetic** from already saved bars; keep source hashes, exclusions, unknown availability and blocked rows.
- Preserve the provisional development layout, without declaring it frozen or unbiased. The shadow-test dates were already inspected.
- Design policy/fold tests and deterministic numerical comparators, but do not fit/promote a predictor or claim executable backtest performance from these labels.

After evidence review, separately approve price-only versus total-return convention, action/factor handling, next-session entry/exit rules, fees/slippage sensitivities, source rights and point-in-time universe/availability assumptions. Then produce certified labels, freeze a genuinely uninspected chronological evaluation and fit the first numerical baseline. There is no guaranteed number of reruns or accuracy percentage.

## E53: public-source and ingestion review, 2026-09-19

The official [corporate-actions API documentation](https://upstox.com/developer/api-documentation/get-corporate-actions/) exposes a per-ISIN event endpoint with event dates, amounts and ratios. The page does not establish complete historical coverage, candle adjustment policy or reproducible adjustment vintages. An empty response cannot certify an action-free interval. No authenticated request was made during this review.

| Evidence inspected | Established | Not established |
|---|---|---|
| Historical Candle V3 reference | OHLCV contract and daily availability/request limits | Raw versus adjusted OHLCV; retrospective revisions and volume factors |
| Corporate-actions reference | Event retrieval by ISIN | Historical completeness, entitlement on the spare account, or how events affect candle values |
| `UpstoxReadOnlyClient.fetchCorporateActions` | This API integration already exists; do not build a duplicate connector | A successful current-account call or complete event coverage |
| `UpstoxCandleBatchNormalizer` | Canonical India trading dates; provider timestamps; scoped duplicate merging and named BEML/LALPATHLAB/SUZLON repair evidence | A general adjustment policy or certification for the four research stocks |
| `UpstoxMarketDataService.persistCandles` | Persists normalized OHLCV; rejects conflicting stored values; sets `source_published_at` NULL | Point-in-time publication time or immutable response/factor vintage. Matching reimports update `received_at`; that is not first availability |
| `syncCorporateActions` | Stores event evidence without modifying candles | A no-write diagnostic: this method writes event/source metadata and must not be run as a read-only check |
| Saved E50 report | No relevant action/adjustment references recovered within the bounded scope | No actions occurred, or previously repaired data is wrong |

These findings apply to inspected paths, not a claim that every historical import/repair path was re-audited. Other brokers' policies, Upstox chart-product documentation and generic adjusted-price explanations are not substitutes for this API's policy.

### Next action and stop condition

1. **Pending:** owner has reported sending the neutral email and will share a reply/reference when available. No further send, reminder or repeated diagnostic is requested. Preserve the eventual reply with secrets removed and distinguish provider statements from our interpretation.
2. Review the answer against stored instrument identities, collection evidence and the 2024-10-22..2026-07-06 source window; account for later actions that may restate it. A current generic policy alone is insufficient.
3. If provider confirmation is unavailable, agree a separate bounded acquisition of official action history and exchange-price samples for only these four instruments. Reuse the existing connector where appropriate; specify permissions, coverage and preservation first. Do not invoke the DB-writing sync endpoint as a diagnostic or recollect the full history.
4. Only evidence-backed eligible windows advance to price-policy approval and certified labels. Unsupported rows stay excluded/uncertified; never infer factors from price jumps. Freeze independent evaluation before fitting.

**Stop repeating unchanged exports/repair queries.** E52 closes the expanded-export runtime check. The next input is source evidence, not another retry or model upgrade. This review changed documentation only; no prices, database rows, runtime settings or training gates changed.
