# Price-policy evidence still needed, without recollecting history

2026-09-19, E50. This is a source-evidence requirement, not a model-training failure. Preserve the existing history and repair work. No message has been sent to Upstox, and no new provider download is authorized by this note.

The bounded repair report completed in 8.828s and linked all four scoped stocks to previously reviewed completed backfill jobs. It inspected ledger rows but recovered **zero relevant adjustment references and zero corporate-action rows** for 2024-10-22..2026-07-06. This is not evidence that no corporate actions occurred. Repeating the unchanged query will not resolve the missing policy.

The official [Upstox Historical Candle V3 documentation](https://upstox.com/developer/api-documentation/v3/get-historical-candle-data/) was checked on 2026-09-19. It defines OHLCV and availability/request limits, but the retrieved page does not specify split/bonus/dividend adjustment semantics, factor vintages or volume rebasing. Do not infer historical-API behavior from a chart product or another broker. This is a limited page review, not proof that no provider statement exists elsewhere.

## Prepared question for authoritative clarification

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
