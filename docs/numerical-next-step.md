# Next numerical work package: reuse history, recover provenance, widen dates

Prepared 2026-09-19 from E47; E49 implementation update below. This is not permission for fitting or trading.

## Current: E56 smoke accepted; E57 bundled numerical-engine testing next

EV1-EV3 passed the spare Docker smoke: 22/22 checks in 15.537s, cleanup successful. [Persisted review](evidence/numerical-evaluation-spare-review-20260919.json). The next [combined synthetic bundle](numerical-baseline-bundle.md) fits a small numerical learner and two reference predictors on synthetic inputs only, tests three conditions, adds ranking/repeatability checks and repeats the old guard checks in one invocation. Pull and run its standalone script; share one JSON. No MarketBrain rebuild, source query, inference or export repetition. Source-policy reply remains pending, and real-market training stays disabled. Synthetic passes are not a measurement of forecast quality.

## E54 awaiting Upstox; evaluation-engineering contract prepared

The owner reports sending the neutral Upstox email and will share replies in a subsequent session. Mark the source-policy step **PENDING_EXTERNAL_REPLY**, not completed. No repeat query, resend, export or rebuild is requested. Next independent work is [EV1-EV3 evaluation engineering](numerical-evaluation-engineering-plan.md): synthetic metric fixtures, leakage guards and compact offline evidence. This turn prepares that contract; it does not implement an evaluator or authorize real-data fitting. The linked handoff preserves context for the provider-response review.

## E52 spare export accepted; E53 source-policy clarification

The spare report `numerical-expanded-research-20260919-140603-9785384a9616.json` completed in **19.824 seconds**, with **600/600 arithmetic rows**, zero blocked rows, zero certified labels and training disabled. Saved-input reconstruction/result validation passed; 1,824 feature values and 152 outcomes from the previous export are unchanged. [Persisted review](evidence/numerical-expanded-research-spare-review-20260919.json). This supersedes the spare-pending status in the historical E51 implementation notes below. No repeated export, rebuild or inference is needed.

E53 reviewed official Upstox documentation and existing ingestion code. A corporate-actions connector already exists, but neither its existence nor the public reference proves the adjustment policy of stored candles. Its sync operation writes event metadata; it is not a read-only diagnostic. [Evidence matrix and exact next action](numerical-price-policy-open-questions.md#e53-public-source-and-ingestion-review-2026-09-19). Obtain authoritative policy/coverage evidence before any scoped acquisition, adjustment or certification. This is an external evidence gate, not another model-training retry.

## E50/E51: repair capture reviewed; expanded research arithmetic implemented

The received `numerical-repair-evidence-20260919-132809-11524efc7e3f.json` (SHA256 `2359ED18BB9B3E0B45EAD50906B1D3A33CF25E114C362AFA8D6B8DCD0448980B`) completed in 8.828s. Independent replay checks input binding, calendar windows, instrument scope and safety flags. All 600 feature/outcome windows match; five jobs observed, no cap. All four stocks link to reviewed completed jobs covering the requested period. Ledger inspections were 12/12/13/1 for MARUTI/NATIONALUM/TARIL/LEMONTREE, but **none were relevant adjustment records for the scoped period**; corporate-action rows and exported references are also zero. No provider/model/order calls or DB writes reported. This closes collector runtime verification, not the price gate. CRLF-normalized hashes of the three helpers/collector and calendar match the spare hashes; files were not assumed identical from versions alone. [Persisted summary](evidence/numerical-repair-review-20260919.json).

The earlier ordered plan's **certified** export remains blocked. E51 advances only its engineering portion using a separate `POST /api/v1/training/numerical-expanded-research-export` profile: 430 pinned reviewed session dates, 150 decisions from 2025-10-27..2026-06-05, <=4 stocks/700 bars each, <=2 MiB request. Both legacy and expanded endpoints share one in-flight slot and reject overlap with 429, with no queue. Existing feature/outcome formulas are reused; every blocked row stays visible; neither endpoint can authorize training or produce certified labels. No database, provider, model, persistence or order dependency was added, and no migration/configuration is required.

`ExportNumericalExpandedResearch.ps1` binds the saved research and repair artifacts, recomputes calendar checks, and preserves the full source request and response. It checks every outcome and feature source window independently, with no automatic POST retry. It labels the operation `UNCERTIFIED_STORED_PRICE_RESEARCH_ONLY`; the previously reviewed SHADOW_TEST remains development-only. A complete empty repair capture may support this engineering export but can never certify adjustment policy. Capped/inconsistent repair evidence blocks request construction. Source hashes identify artifacts, not truth.

The report is one compact JSON, with atomic checkpoints and optional offline response reuse. The expanded writer waits at most 12 attempts for sharing/lock violations only (6.6s total configured sleep plus file I/O); it never deletes the last report or reruns the calculation. A persistent lock retains the last report/pending snapshot and fails. Older collectors retain their six-attempt/default formatting behavior. Compact serialization prevents pretty-print whitespace from inflating the 600-row evidence beyond practical sharing/replay sizes.

Offline actual-data replay generated **600/600 arithmetic rows** and reproduced all **1,824 feature values and 152 outcomes** from the previous export. PowerShell separately checked the 600 result rows against the captured bars. These are arithmetic/regression checks, not certified returns, new independent samples or predictive intelligence. Full deployment/round-trip remains pending on spare.

Verification: **309 standard Java tests plus one explicit real-evidence replay**, **132 PowerShell 5.1 workflow assertions** and **58 history/checkpoint assertions** passed. Tests cover profile separation, bounds/shared concurrency, future-price isolation, retained missing rows, source binding, unsafe flags, outcome parity, file checkpoints, compact output, timeout/no-retry and offline reuse. Package build verified separately. No local live service, database, provider or inference was run; PowerShell 7/spare export remains pending.

Remaining order: obtain authoritative adjustment/action coverage and approve research conventions ([prepared questions](numerical-price-policy-open-questions.md)); certify eligible labels; freeze purged development folds plus a genuinely uninspected evaluation; fit and compare numerical baselines. No repeated empty repair check, full history acquisition or LLM sweep is requested. Provider/source response time is unknown, so no guaranteed completion date or percentage of prediction improvement.

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
