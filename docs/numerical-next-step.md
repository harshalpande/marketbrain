# Next numerical work package: reuse history, recover provenance, widen dates

Prepared 2026-09-19 from E47; E49 implementation update below. This is not permission for fitting or trading.

## E49: calendar prerequisite closed within sample; repair collector ready

Official NSE sources independently establish the earlier cash-market calendar: [2024 holidays](https://nsearchives.nseindia.com/content/circulars/CMTR59722.pdf), [Muhurat live session](https://nsearchives.nseindia.com/content/circulars/CMTR64628.pdf), [November 20 election closure](https://nsearchives.nseindia.com/content/circulars/CMTR64960.pdf), [2025 holidays](https://nsearchives.nseindia.com/content/circulars/CMTR65587.pdf), and [NSE Indices confirmation of the February 1 Budget session](https://www.niftyindices.com/Press_Release/ind_prs24012025_3.pdf). Budget circular CMTR65729 is cited by the last source, not claimed to have been directly retrieved. This adds 110 live dates for 2024-10-22..2025-03-31. Special live sessions override routine closures; dates outside reviewed coverage are not inferred.

Actual saved-export replay: **150 dates, 600/600 feature windows and 600/600 outcome windows matched**, zero date/quality-blocked windows, provisional layout unchanged. [Replay summary](evidence/numerical-expanded-calendar-review-20260919.json). No 600-row feature/label export or fitting occurred; the existing shadow-test contamination warning still applies.

`GetNumericalRepairEvidence.ps1` now checkpoints those calendar checks and reads `GET /api/v1/training/numerical-repair-evidence` once for the same four instruments and full 2024-10-22..2026-07-06 scope. It reuses the bounded price-evidence job/ledger selector, retaining current RESOLVE/REVOKE identities, then fetches at most 200 resolution references and 200 corporate-action references by primary key. Current-state evidence does not reconstruct historical policy or guarantee older/out-of-catalog jobs and later actions were covered.

No raw notes, reviewer names, arbitrary source strings or private/query-bearing URLs are shared. Approved public NSE archive paths are retained; original notes/source/URL bytes are hashed, and up to eight narrowly parsed numeric factor hints per record are labelled unverified. These are recorded claims, not applied or approved factors. The collector does not fetch links or scan unrelated files. Broader before/after repair details may remain only in existing job artifacts and are not claimed captured by these hashes.

Safety: <=4 stocks, existing bounded selector plus at most two primary-key queries (<=17 queries total), 3-second statement timeouts and read-only repeatable-read transaction timeout 60s; HTTP timeout 90s, no automatic DB retry. These are resource guards, not a guaranteed end-to-end runtime. Caps, missing reference rows and upstream partial results propagate `partial=true`. Report status never authorizes training, even when nothing is found. No migrations/config changes, data writes, provider/model calls or trades. Actual spare SQL execution/performance remains pending; schema/index review and mocked JDBC tests are not EXPLAIN evidence.

One uniquely named JSON embeds windows, references, source/tool hashes, timing/progress and partial failure checkpoints. Offline saved-response replay is supported. **305 standard Java tests and 115 PowerShell 5.1 assertions passed**; no actual local runtime/DB/provider/model used. PowerShell 7 and live spare verification await handoff. Next: inspect recovered evidence, explicitly resolve any remaining price-policy/coverage gaps, then expand the Java export and freeze valid evaluation before fitting. No overall completion percentage increase or accuracy promise.

## Accepted result

`numerical-research-export-20260919-124431-2c76f7cab00a.json`, SHA256 `37449BE9E8A330D4C7DB9790736898C6776D2D430A1337ADF1ECFE42641CD845`: spare completed in **3.975 seconds**. 38 dates, 152/152 complete arithmetic rows, zero blocked rows, no reported DB/provider/model/order calls. Independent local replay of the saved request/result passed. Zero certified labels; training remains blocked. This closes the bounded export runtime checkpoint, not a forecasting-quality milestone.

The owner no longer has a separate adjustment-policy report and recalls earlier AI-assisted repairs. Do **not** ask the owner to reconstruct those repairs from memory or repeat the history acquisition. Do not infer which assistant performed them or assume all repairs were persisted.

## What can be reused now

The saved file contains **524 bars per instrument** for MARUTI, NATIONALUM, TARIL and LEMONTREE. A fixed, outcome-independent development layout can provisionally use:

| Item | Proposed scope |
|---|---|
| Decision dates | 150 observed dates, 2025-10-27 through 2026-06-05 |
| Feature + outcome union | 2024-10-22 through 2026-07-06, 421 observed dates/instrument |
| Candidate rows | 600 = 150 dates x 4 instruments |
| Retained development rows | 400 = (60 TRAIN + 20 VALIDATION + 20 SHADOW_TEST dates) x 4 |
| Purge | 20 dates before each following partition: label end must be strictly before its boundary |
| Boundary gap | First five dates of VALIDATION and SHADOW_TEST withheld |
| Provisional boundaries | VALIDATION 2026-02-19; SHADOW_TEST 2026-04-30 |

All four instruments have the 421 **observed** dates, with no missing, excluded or invalid OHLC/volume in that sequence. This does not establish the absence of missing exchange sessions: 110 of those dates precede the reviewed calendar's start. Within existing reviewed coverage, no missing/extra calendar dates were found. No download is justified by this plan alone. Do not intersect away a stock's missing date; the planner keeps a first-instrument anchor and reports other instruments' gaps.

The 150/60/20/20 sizes and five-date gap are **engineering pilot choices**, not statistically validated sample-size requirements. The boundary gap is a conservative forward holdout buffer, not a claim to implement every form of cross-validation embargo. Counts must be regenerated after calendar review; do not preserve them by silently skipping a missing session. The plan uses no outcome returns to choose boundaries. No features or labels for these 600 rows have yet been exported.

**SHADOW_TEST is not an untouched final test.** All 20 retained shadow-test dates already appear in the reviewed 38-date pilot. Freeze a separate, genuinely uninspected chronological evaluation period before fitting/tuning. Do not report accuracy on this development layout as unbiased performance or assume 400 overlapping rows are independent samples.

Full date assignments, source hashes, per-instrument scope, gaps and explicit gates are persisted in [the prepared plan](evidence/numerical-development-expansion-plan-20260919.json). No need to run the same planner again to discover these results.

## Recovering earlier repairs: verified pointers, not blanket certification

Source inspection and Git history show `UpstoxCandleBatchNormalizer.java` records named BEML split-rounding, LALPATHLAB bonus-adjusted variance and SUZLON official-mismatch exceptions, including dates, retained/discarded OHLCV and source references. These examples prove **some explicit repair logic exists**, not that the four selected stocks have a universal certified adjustment policy. Do not apply those instrument-specific exceptions to unrelated stocks.

`V10__create_governed_market_data_review.sql` defines `market_data_quality_resolution_event` with `evidence_source`, `evidence_url`, `notes`, `reviewed_by`, resolution type, dates and RESOLVE/REVOKE actions. This proves the storage mechanism exists, not that the needed rows are present on spare. E35 previously reviewed saved final-quality summaries; aggregate resolved-finding counts do not establish per-price adjustment factors. Existing numerical price evidence deliberately omitted raw notes/URLs and covered only 2025-04-03 onward, so it cannot rule out earlier relevant records.

### Ordered implementation and acceptance

1. **Recover provenance, scoped to four instruments and the proposed 2024-10-22..2026-07-06 range.** Inspect existing saved repair artifacts and the persistent resolution ledger, retaining latest revocations and relevant job membership. Export bounded, sanitized source references and before/after/factor evidence if present; no arbitrary file scan, provider calls, DB writes or fabricated PASS. Source notes must be treated as data and reviewed for secrets before sharing. If absent, explicitly report which evidence is missing and obtain authoritative clarification/records; do not infer adjustment factors from price jumps alone.
2. **Extend the independent NSE calendar through 2024-10-22..2025-03-31.** Verify exchange circulars, holidays, special live sessions and amendments; never derive the authoritative calendar from observed bars. Recheck every planned 252-session feature window and 20-session outcome path. No external calendar is declared reviewed by this planning pass.
3. **Widen the saved-data export after those checks.** Reuse Java formulas, keep observed/raw versus analysis/execution prices explicit, preserve exclusions, versions and source hashes, and retain all blocked rows. Approve research return/cost/availability/universe conventions. Missing listing/membership, licences and historical-vintage evidence remains visible. No broad training-readiness declaration from four stocks.
4. **Freeze valid folds and a new untouched evaluation set; then fit a numerical baseline.** Train-only preprocessing, deterministic comparators, overlapping-window purge, documented cost sensitivities, counts/uncertainty and challenger promotion rules. No online self-modification or live orders. Predictions may fail to beat a baseline; that is a result, not grounds to tune on the final test.

Calendar work and provenance recovery can progress independently; broader certified export depends on both. Numerical fitting depends on the approved contract and usable frozen dataset. Engineering timeline remains conditional on source evidence, not a promise of a fixed number of reruns or accuracy improvement.

## Reproduction, only if wanted

`PrepareNumericalExpansionPlan.ps1 -ResearchExportPath <saved-export.json>` creates one unique JSON without Java, Docker, DB, provider or model access. It validates the saved export, reports gaps rather than fetching anything, preserves failure checkpoints, and never authorizes training. Only PowerShell/docs changed in E48, so no rebuild is needed. 99 PS5.1 assertions including upstream suites passed; PowerShell 7 spare reproduction remains optional/unverified. Java was unchanged and its previous 300-test result was not rerun for this planning-only change.
