# Restricted research mapping and eligibility ledger

2026-09-19: E62 owner scope approval; E63 implementation; E64 spare response reviewed and timestamp/replay compatibility fixed. The original spare collector stopped during client validation, not Java mapping.

## Approval boundary

Owner confirmed the E61 documentation and authorized proceeding with the first daily **20-session price-return research** stage on the restricted development cohort. Intraday and 5/60-session goals remain. This approves intended research scope, not historical source truth, the whole six-part contract, actual costs, final-test thresholds, model fitting or trading.

Upstox remains **PENDING_EXTERNAL_REPLY**. An approval cannot certify adjusted/executable prices or original publication timestamps. The implementation below is preparation for research, not a workaround around those gates.

## Three associated implementation deliverables

1. **Versioned ten-feature mapper:** reconstruct the existing features from saved bars, map explicit units, and expose a features-only DTO. No identity, future return, actual rank, label or approval is included in that DTO. Do not send the entire evidence report to a learner.
2. **Per-row eligibility ledger:** preserve every row, source candle IDs, proposed cutoff, missing/late stored-receipt diagnostics and blockers. `mappingReady` means arithmetic mapping worked; it does not mean `trainingEligible`. Every row remains training-ineligible in this preparation version. There is no override parameter.
3. **Coverage and compact evidence:** grouped date counts and blocker counts, source/request/script hashes, phase timings, durable checkpoints, one uniquely named JSON for sharing. No date split selected, no best-row filtering and no market-data fit.

## Mapping contract: NUMERICAL_RESEARCH_MAPPING_V1

Inputs use E52's existing bounded snapshot calculation and calendar validation. The current decision-date close is taken from the same instrument's validated saved bars. Derived percentages are rounded to eight decimal places, HALF_UP. No scaling is fitted here.

| Feature | Definition / units |
|---|---|
| dailyReturnPercent | Existing snapshot daily close return, percent; not return5 |
| closeToSma20Percent / closeToSma50Percent / closeToSma200Percent | `100 * (close - SMA) / SMA` |
| ema12ToEma26Percent | `100 * (EMA12 - EMA26) / EMA26` |
| rsi14 | Existing Wilder RSI, 0..100 |
| atr14ToClosePercent | `100 * ATR14 / close` |
| annualizedVolatility20Percent | Existing sample log-return volatility, annualized percent |
| volumeRatio20 | Existing ratio, not a percentage; denominator excludes current bar |
| rangePosition252Percent | Existing close-based range position, 0..100; flat range = 50 |

The existing 252-observed-bar warm-up and calendar-window checks remain authoritative for this engineering mapping. Missing/excluded windows and invalid denominators remain in the ledger with no vector; no imputation or backward substitution. Stored receipt time is not assumed to be original publication time, even if it precedes the proposed 16:00 Asia/Kolkata cutoff. This is a **research mapping proposal implemented for inspection**, not approved production feature availability.

The fixed two-feature synthetic ridge learner is unchanged and cannot consume this ten-feature DTO. A separately reviewed learner/matrix contract is still required before fitting.

## Resource and execution boundaries

`POST /api/v1/training/numerical-research-mapping` accepts the existing expanded-export input. It recomputes bounded snapshots rather than trusting caller-provided vectors or outcome fields. It shares one non-queuing semaphore with the two saved-evidence export routes, accepts <=2 MiB, <=4 instruments/700 bars each and the pinned 430-session calendar. No repository/provider/model/order dependency, migration or configuration change. Malformed inputs return 400, oversized requests 413, overlapping preparation 429; release the slot even on failure.

`PrepareNumericalResearchMapping.ps1` accepts **only the previously accepted E52 file bytes**, SHA256 `E983F6EE5B0B6DDA2DE40DC27D37451B2DD58C5D360CBBE092672B9EFD419CA8`. It is intentionally not a general arbitrary-dataset runner. If that file is missing or differs, stop and locate the accepted artifact; do not recollect automatically or change the pin to force acceptance. Source hashes identify evidence, not truth.

The script posts once with a 90-second HTTP timeout, no automatic calculation retry. It checkpoints the response before independently comparing all 6,000 feature values against the accepted snapshot formulas, as well as identities, source windows, cutoff, receipt diagnostics, blockers, date coverage and safety counters. The saved request has the original bars so analysis survives shutdown. Output is one `numerical-research-mapping-<timestamp>-<id>.json`; partial failures preserve the prior checkpoint. `SavedMappingResultPath` accepts either a raw mapping response or a complete/partial collector envelope containing a full response. Envelope replay verifies pinned source hash and saved-request equality before reviewing every result; no Java/health call or automatic retry. The old file is never overwritten. Round-trip time includes HTTP/Java processing, not isolated Java CPU timing. Offline reports identify execution mode, prior status/timing/file hash, PowerShell version, culture, local zone and cutoff value type; the replay itself does not claim a new Java round trip.

## E64 timestamp defect and recovery

The supplied `numerical-research-mapping-20260919-172002-1b29d58ed442.json` preserves all 600 rows/150 date groups. Source/request binding and CRLF script/reviewer hashes match E63. Original run: 1.474s total, 0.782s mapping round trip, 0.070s failed reviewer. First cutoff is `2025-10-27T10:30:00Z`, exactly 16:00 IST. Independent saved-response review checks all 6,000 features; no Java recomputation or data modification is needed.

The old reviewer cast the timestamp to `[string]` before parsing. PowerShell 7 can deserialize a JSON timestamp as a typed `DateTime`; display-string conversion discards `Kind`/offset and becomes culture/local-time dependent. [Microsoft's date parsing documentation](https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.utility/convertfrom-json?view=powershell-7.5#notes) describes UTC/local/offset/string behavior. E64 compares UTC ticks using the original type: UTC/local DateTime, DateTimeOffset, or invariant ISO text with an explicit timezone. Unspecified DateTime, timezone-free text, invalid dates and real one-tick deviations fail; no timestamp is coerced to the expected answer. Original 5.1-only testing missed this compatibility fault.

Recovery: pull scripts only and replay that exact partial JSON with `PrepareNumericalResearchMapping.ps1 -ExpandedResearchPath <accepted E52 file> -SavedMappingResultPath <partial E63 report>`. **No rebuild, running service, data export, model or Java call required.** Preserve the earlier file and share only the new single JSON. E64's stored evidence distinguishes accepted Java output from the originally failed client workflow and the corrected spare replay still to be confirmed.

## Expected spare result and next gate

Both local reconstruction and reviewed spare Java response: **600/600 mapped rows, 150 date groups, 0 training-eligible rows, 0 certified labels**. `MAPPED_RESEARCH_TRAINING_BLOCKED` is expected, not a failed model. Corrected spare client replay remains pending; do not conflate the old validation exception with bad numerical features.

After spare parity, reuse this ledger; do not repeat mapping runs without a relevant change. Resolve the provider/price and historical-availability evidence, review the production feature and evaluation policies, then prepare eligible-date-driven folds and request scoped fitting approval. If historical vintages cannot be recovered, propose an explicitly limited retrospective study or prospective capture; neither is silently substituted here. No prediction accuracy or completion-date promise follows from mapping success.
