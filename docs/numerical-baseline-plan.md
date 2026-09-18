# Numerical prediction baseline: bounded work package

Status: N1 aggregate audit reviewed (E28); N2 bounded history diagnostic verified on the spare laptop (E30). Contract freeze remains pending. Research label arithmetic implemented/offline verified (E32), not connected to export/training. E37 verifies the bounded feature-only snapshot at runtime; E38 checks its 12 windows against an independent bounded calendar offline. Reuse the existing Upstox quality work (E31/E35); do not repeat acquisition or blanket validation. No LLM training, numerical fitting, database dataset persistence, backfill or trading execution in this handoff. Governing goals: G01/G13 evidence, G02 dataset, then G03 numerical baseline. Required 5/60-session and intraday horizons remain in G07, not silently dropped.

## Sequence and gates

| Milestone | Output and acceptance | State | Effort estimate after prerequisites |
|---|---|---|---|
| N1: inspect existing run | One compact report; exact UUID/hash/date; reconcile classifications and 5/20/60 horizon counts, expose exclusions and source limitations | Completed within aggregate-audit scope, E28; not training readiness | Evidence reviewed |
| N2: freeze prediction-grade data contract | Review feature availability, entry/exit convention, calendar, corporate actions, membership and source rights; no future columns in inference | Runtime window evidence reviewed; reusable label arithmetic offline verified; policy freeze pending | 1–2 working days after existing evidence linkage and policy decisions |
| N3: immutable multi-date export | Versioned rows/manifests; leakage/duplicate/gap tests; actual usable dates; no alteration of prototype run | Feature-only snapshot runtime verified (E37), bounded calendar windows checked offline (E38). Labelled training export NOT implemented | 3–5 working days after N2/source feasibility |
| N4: chronological evaluation | Freeze train/tune/untouched-test date boundaries; purge overlapping label windows; deterministic fold manifests | Not implemented | 1–2 working days after N3 |
| N5: first numerical challenger | Compare simple fitted model to no-model baselines; out-of-sample error/rank/net-outcome and latency report | Not implemented | 2–3 working days after N4 |

These are scoped engineering estimates, not a promise of prediction quality or calendar completion. History acquisition, provider permissions and future-label maturation may take longer. Failure to beat baseline is a valid outcome, not a reason to tune against the untouched test set. Independent paper-ledger/UI contract design may proceed without model fitting, but implementation and runtime actions remain explicitly scoped. No arbitrary 10–15% improvement or guaranteed BUY/SELL accuracy target.

## N1 handoff

Historical handoff, already completed: E28 reported 500 instruments, 476 eligible/fully labelled (95.2%), 24 insufficient-history (4.8%), and 476 labels per 5/20/60-session horizon. One decision date (2026-06-05); label-through 2026-09-08. No stale/no-data/right-censored classifications or failed aggregate checkpoints. Collection took 1.5 seconds. These are prototype sample counts, not prediction accuracy, multi-date completeness or permission to fit a model. No N1 rerun is needed for this handoff.

Run `ops/windows/GetNumericalPredictionDataReadiness.ps1 -DatasetRunId <explicit-UUID>` on spare laptop after pull. Default: GET health (10 seconds), then one GET `/api/v1/training/prototype-swing-dataset-audit?datasetRunId=<UUID>` (60 seconds, capped at 120, no retries/redirects). No latest-run selection, provider access, model call or dataset creation. Optional `-ExistingAuditPath <raw-audit.json>` reuses saved evidence with a SHA256 and makes no HTTP request. Do not pass an LLM ranking report or the readiness wrapper as a raw audit.

Share one `numerical-data-readiness-<timestamp>-<id>.json`; it embeds the audit, local assessment, timestamps/progress, script hashes and failures. Audit outcome examples are diagnostic future data, **never features or inference input**. Readiness percentages are per selected run, not total Nifty 500/history coverage, model accuracy or project completion. No field named `auditReadyForOllamaRanking` authorizes inference here.

Expected successful inspection status: `PROTOTYPE_AUDIT_CONSISTENT_NOT_TRAINING_READY`. This means aggregate checks passed but the dataset is still a single-date prototype. `AUDIT_BLOCKED` names discrepancies. `FAILED_PARTIAL_REPORT` means collection/parsing failed; preserve the file and investigate rather than blindly retrying. HTTP timeout does not cancel a database query. No Docker rebuild needed; Java source unchanged.

Source/performance review: `PrototypeSwingTrainingDatasetAuditService.audit` is read-only, accepts an explicit UUID, loads run metadata by PK, aggregates classifications by `run_id`, and joins labels through selected-run items. V25 defines `(run_id,instrument_id)`, `(run_id,symbol)` and `(item_id,horizon_sessions)` unique indexes; best/worst examples use LIMIT 5 per horizon. Query cost is scoped to selected-run rows, not 15 years of raw candles; this is not a row-independent constant bound. Index presence/query plans on the deployed database and actual execution time remain unverified. No new SQL or migration introduced. The old audit compares some metadata counts, so passing is not an independent row-level correctness guarantee.

## N2 draft contract

- Unit: canonical instrument ID plus decision timestamp, feature/source version, membership-vintage ID and data-availability cutoff. Start with daily end-of-session decisions; intraday is separate.
- Features: trailing-only price returns over declared 5/10/20-session lookbacks, volatility/ATR, volume ratios, trend/relative-strength measures with explicit warm-up and missingness rules. Freeze the final allowlist after source coverage evidence. Historical labels, `actualRank`, forward return, hindsight trap selection and future classifications cannot be inputs. Fit scalers/imputation only on training partitions; critical missing data excludes a row, not silently filled.
- Targets: separate 20-session forward gross/net return and risk outcomes, based on a declared next-executable-price entry and exchange-session exit rule. No promise of getting the as-of close after using its full bar. Historical prototype labels require convention review before reuse.
- Universe: current Nifty 500 membership is not historical constituent membership. Tag research restricted to current members as survivorship-biased; no official 15-year benchmark claim. Handle listing dates, delistings, suspensions and corporate actions explicitly; adjusted features and executable prices have distinct roles.
- Costs: versioned cost/slippage assumptions, not inferred profits. Persist gross and net outcomes separately. Exclude or mark censored incomplete horizons; never manufacture future labels.
- Splits: date-based, never random stock-row splitting; cross-sectional rows from the same decision date stay together. Remove training observations whose label/availability interval overlaps validation/test boundaries; freeze gaps and any embargo before fitting. Reserve a final untouched period. Minimum usable independent dates/regimes and uncertainty estimates must be agreed after coverage evidence; 500 symbols on one date are not 500 independent temporal tests.
- Evaluation: compare constant/train-only mean, existing deterministic score/rank and a simple regularized numerical model before adding complexity. Report MAE/median error, rank correlation and top-k outcome spread, sample/date counts, net-after-cost results, drawdown assumptions and latency. Direction probabilities, if trained, require out-of-sample calibration metrics, not token probabilities. Report date-dependent uncertainty; no superiority claim from reused tuning samples.
- Promotion: technical validity, risk gates and incremental out-of-sample value are separate. A model may abstain/NO_TRADE. HOLD creates no order. All eventual execution remains INR100,000 paper-first with human approval/revalidation; real Paytm orders remain disabled and separately authorized.

## What N1 cannot establish

It does not audit all raw candles, missing exchange sessions per symbol, 15-year coverage, financial/news vintages, historical membership, leakage-free multi-date features or predictor performance. These stay UNKNOWN/PENDING until their own evidence exists. The first report determines what can be reused and which bounded data query/export is justified next.

## N2 implementation and spare-laptop handoff

`NumericalDataContract.draft()` exposes `NUMERICAL_SWING_20_V1_DRAFT` with `trainingAuthorized=false`. Proposed decision cutoff is 16:00 Asia/Kolkata on an independently verified exchange session. Entry is the next exchange-session open; exit is the close of entry session + 19 sessions. Missing/non-executable entry is censored, not moved to a convenient later session. This is a research-label proposal, not a fill simulation or executable label implementation. Old reference-close prototype labels remain unchanged.

Initial candidate feature allowlist (not yet a frozen feature implementation):

| Field | Draft numeric definition |
|---|---|
| dailyReturnPercent | `100 * (close / previous-session close - 1)` |
| closeToSma20/50/200Percent | `100 * (close / trailing SMA(window) - 1)` |
| ema12ToEma26Percent | `100 * (EMA12 / EMA26 - 1)` |
| rsi14 | Trailing 14-session RSI; smoothing and seed must be versioned |
| atr14ToClosePercent | `100 * ATR14 / close`; true-range smoothing/seed must be versioned |
| annualizedVolatility20Percent | `100 * sample SD(last 20 daily log returns) * sqrt(252)` |
| volumeRatio20 | Current volume / trailing 20-session mean volume, including current session |
| rangePosition252Percent | `100 * (close - lowest low252) / (highest high252 - lowest low252)` |

Zero/invalid denominators and inadequate warm-up cannot silently become valid values. Prices, volume adjustments, smoothing and availability still require final policy and fixture parity before freezing. Required longer-lookback, benchmark, fundamental and news features remain future, separately validated additions. Feature names alone do not certify existing calculators implement these formulas.

The new GET `/api/v1/training/numerical-history-coverage` takes explicit `datasetRunId`, `offset` (0..499), `limit` (1..50) and `lookbackDays` (252..730 calendar days). It only reads a completed immutable prototype run and current stored daily history. The default 730-day window ends at its as-of date, not today. It returns the persisted classification/reason for every selected instrument, first/last observed dates, observed/nonexcluded/excluded date counts, source row counts and ingestion-after-cutoff counts. The existing feature pipeline requires 252 eligible observations; inspecting its 24 exclusions does not yet identify listing age versus missing/backfilled data.

Safety/performance: index-shaped instrument/opened_at bounds use the V24 partial daily-complete index; selected-run items use V25 indexes. Current exclusion ranges are materialized once per page rather than recomputing the governed-resolution view per candle. At most 2,001 source rows per instrument enter the aggregate; the extra row flags truncation, making the report PARTIAL. SQL may inspect more rows internally; this is not a constant-time guarantee. JDBC statement timeouts are 5/15 seconds and the read-only transaction timeout is 30 seconds. No new migration. Actual PostgreSQL execution plan/index presence and runtime performance are **not locally verified**. A failed/slow first page stops collection instead of retrying heavy SQL.

Deploy the Java service first, then run:

```powershell
& '.\ops\windows\GetNumericalHistoryEvidence.ps1' -DatasetRunId '5bdbfcc1-d990-48d8-9e98-d4927596d917' -LookbackDays 730
```

The collector issues one health GET and at most ten sequential 50-instrument pages, each with 60-second HTTP timeout, no redirects or HTTP retries. Progress, page timing, draft contract, per-instrument evidence and failures are checkpointed into **one** unique `numerical-history-<timestamp>-<id>.json`. Scope/hash/count/window drift and duplicate/incomplete pages fail closed. Windows sharing/lock errors during atomic replacement alone get six bounded attempts (1.5 seconds total scheduled delay). Persistent save failure retains the previous JSON and a pending checkpoint; share those on failure, do not delete them. Evidence files are local writes; database/model/provider/order side effects are zero for the diagnostic.

Expected result: `WINDOW_COVERAGE_REVIEW_REQUIRED`, or `PARTIAL_WINDOW_COVERAGE_REVIEW_REQUIRED` if capped. Neither authorizes training. `FAILED_PARTIAL_REPORT` preserves completed evidence: share it rather than rerunning inference. Restarting the service for deployment requires idle jobs and may invoke pre-existing configured startup/scheduled behaviour; this diagnostic does not disable or certify unrelated automation.

Limitations: date counts are not canonical source/OHLC checks or a missing-session audit. Both sources on one date are not automatically bad duplicates. Exclusion policies are current, not historical vintages. Late ingestion often reflects backfill; it is not proof the price was unknowable historically. Pages are separate reads, not a single atomic history snapshot. This does not certify 15 years, listing age, source rights, adjustment correctness or leakage-free inputs.

Next decision after E29 runtime evidence: resolve the 24 persisted exclusions individually, determine a defensible multi-date span, confirm calendar/price/cost/availability policies, then freeze N2. Only afterward implement N3 multi-date export and leakage tests; N4 splits precede N5 fitting. If coverage is insufficient, propose a bounded acquisition/remediation scope before any backfill.

## Reuse validated history; distinguish research availability from live availability

Owner reports approximately 6–8 days spent collecting and repeatedly checking Upstox history against historical events. Preserve that investment. Source review confirms governed quality resolutions, corporate-action/provider-adjustment classifications, listing-boundary evidence, official/peer session checks, gap/large-move investigation and provider-backed batch/daily verification scripts. These are existing capabilities, not tasks to restart. Script expected values are not fresh proof every old batch passed; link saved artifacts and their exact scopes instead of discarding prior work or expanding it to unverified coverage.

E30's 730-day diagnostic completed all 500 instruments in 6.18 seconds, with 237,200 rows and no truncation/errors. All 24 insufficient-history instruments have 112–251 nonexcluded dates, consistent with the 252-observation requirement; no listed exclusion ranges affected this window. First stored date is not necessarily an IPO/listing date. No need to re-download these candles or reduce warm-up to force acceptance. The window is not the complete 15-year database.

All inspected rows arrived after the 2026-06-05 decision cutoff. That is consistent with historical backfill and does not contradict prior price/event validation. Almost exclusively Upstox source rows do not mean internet/exchange-event validation was never done: candle source and external validation evidence are different records.

Proposed policy distinction, to freeze with the export contract:

- **Retrospective research:** reuse existing validated history with explicit backfilled/revised-data and current-universe disclosures, source/evidence references and immutable export hashes. No claim that the application possessed those exact versions historically. Review adjustment policy and time-aware joins; retrospective data is not automatically leakage-free.
- **As-known/live replay:** require actual availability/version evidence at decision time. Do not change `received_at` to create fictional history or simply disable availability checks to pass a gate. User feedback, future labels and later news remain forbidden inputs in either mode.

Pure `NumericalResearchLabelCalculator` is the first arithmetic building block. It consumes an explicit ordered session calendar, canonical executable OHLC bars, calendar/price/cost policy versions and caller-supplied round-trip costs. It uses next-session open and the close of session 20, reports gross/net percent separately, and returns explicit unavailable/missing/invalid/non-executable statuses with no fabricated return. It requires the complete 20-session path, never skips forward and never authorizes training. The test cost of 50 basis points is a fixture, not a selected production assumption. Supplied calendar/executability/policy names are not independently verified by this calculator. It has no Spring bean, endpoint, repository dependency or active call site; the old prototype calculator is unchanged. Adjustment handling, feature export, actual calendar binding and split manifests still need implementation.

Historical E34 handoff (do not rerun for E38): `GetExistingDataValidationEvidence.ps1` reads saved final outcomes only: final provider/database quality reports, final checkpoints and daily-enrichment quality. It writes one unique compact report with file SHA256, selected summary metrics, timestamps and progress. No service/DB/provider/model access. It does not execute old scripts or export full findings, URLs, tokens or article text. Bounds: first 1,000 top-level JSON directory entries, 50 matching files within that listing, 16 MiB/file, 96 MiB total and cooperative 60 seconds; no recursion, file links/root link refused. Optional `-IncludeIntermediate` retains the broader naming families but orders final outcomes first. Skip reasons distinguish link, per-file limit and total-byte budget. Slow filesystem calls can exceed the cooperative budget. Missing/oversized/unreadable reports are not evidence that earlier validation failed.

Review `existing-data-validation-<timestamp>-<id>.json` to associate previous quality results with explicit job IDs/date ranges. Older `modelTrainingEligible` flags describe those quality gates only, not permission for this numerical model. Saved PASS counts cannot be summed into unique universe coverage without resolving overlapping scopes. Finalize the export policy and reuse eligible canonical history; investigate only missing scope evidence or new contradictions. If saved files are unavailable, propose a bounded read of persisted resolution evidence before any repeat provider validation.

E33 returned 31 selected/inspected files, 21 captured summaries and ten size/budget skips in 8.27 seconds. Captured final daily enrichment has 500/500 provider matches and PASS, Batch 2 final has 50/50 and PASS, and Batch 2/3/4 remediation snapshots show zero unresolved findings with no failed items. Batch 4 final checkpoint says ELIGIBLE. Earlier Batch 3/4 MISSING_PROVIDER_DATA reports precede completed remediation and must not be treated as present failures. However, full final Batch 3/4 reports and the pilot final were skipped by V1; their final metrics remain unreviewed here. This blocks full final-history acceptance, not all offline engineering.

V1's 10 MiB/file and 50 MiB total limits were too small: final Batch 3/4 files are roughly 12–13 MiB, and intermediate reports consumed the overall allowance. V2 is sized against the returned inventory: the 11 selected final artifacts total 52.81 MiB, largest 12.70 MiB, fitting the new explicit limits. This is a collector correction, not a reason to rerun data acquisition/provider checks. Re-read saved files once, review final outcomes, then decide the export gate. No training or new dataset accepted on partial evidence.

## E36 implemented: bounded feature-only multi-date snapshot

This is N3 preparation, not completion of N2/N3 and not training. GET `/api/v1/training/numerical-feature-snapshot?datasetRunId=<UUID>&offset=0&limit=4` selects at most four instruments in stable instrument-ID order from the existing run. Decision dates are run as-of, minus four weeks and minus eight weeks, returned ascending. These are **calendar-week offsets**, not 20/40-session offsets. Dates are fixed before inspecting prices; a missing date blocks its row rather than shifting to a convenient observation. This gives at most 12 rows, not a sufficient modelling sample.

One repeatable-read, read-only transaction loads the run metadata, selected items and 730 calendar days ending at run as-of. No future label bars are queried. There are at most six SQL statements, each with a five-second statement timeout and a 30-second transaction timeout. Instrument/time predicates follow the V24 index, selected items the V25 index. Exclusion ranges are materialized per selected instrument. Each source query returns at most 2,001 rows; the sentinel blocks **all** feature rows for that instrument. This bounds returned data, not underlying database work; actual query plan/index presence and spare execution latency remain unverified. No new migration or schema write.

Canonicalization prefers NSE_BHAVCOPY, then UPSTOX; within source/date, latest received timestamp then largest candle ID wins. Current governed exclusions are retained, not silently dropped. Each row uses exactly the last 252 observed bars through its requested date; future bars cannot enter the calculator. Full canonical source OHLCV, candle IDs, ingestion times and exclusion flags are embedded once per instrument. Each row lists its input IDs and late/missing ingestion counts. These are retrospective stored versions, not proof of what the application knew at the historical cutoff. The full evidence envelope contains bars later than its earliest feature row and must never be passed wholesale as inference input.

The **existing** `TechnicalFeatureCalculator` is reused without changing old callers. Snapshot version `OBSERVED_252_FEATURE_SNAPSHOT_V1` freezes these implementation definitions for inspection, not production approval:

- EMA12/26 seeds at the first close in the exact 252-bar window. RSI14 uses initial 14 changes and Wilder smoothing; ATR14 uses initial 14 true ranges (first bar high-low) and Wilder smoothing.
- Volatility uses sample standard deviation of the last 20 log returns, annualized with sqrt(252).
- `volumeRatio20` divides current volume by the **previous** 20-bar mean, excluding current. Missing/zero denominator blocks the row.
- `rangePosition252Percent` uses **close** minimum/maximum, not high/low; a flat range returns 50.
- Existing values are rounded to six decimals. SMA/EMA/ATR and previous close remain raw price-valued diagnostics, not a frozen normalized model feature vector. Draft normalized features above are still proposals. The volume/range definitions above differ from that draft intentionally and visibly; do not compare them as identical metrics.

Missing exact-date bars, short history, invalid OHLC/volume, exclusion flags, unavailable volume ratios and source truncation produce explicit blocked rows with null features. Successful arithmetic is labelled `FEATURES_ONLY_CALENDAR_UNVERIFIED`: 252 observed bars do not certify consecutive exchange sessions. The independent official calendar, adjustment/executability/cost policies, prior quality-job membership (including original ten-stock pilot), historical membership and label/split manifests remain open gates. **Zero targets are generated; trainingAuthorized stays false.** No prediction accuracy or readiness percentage increase is claimed.

Run `GetNumericalFeatureSnapshot.ps1 -DatasetRunId <UUID>` only after deploying the Java changes on the spare laptop. One health GET and one snapshot GET, no redirects/retry, 10/60-second HTTP timeouts. One unique `numerical-features-<timestamp>-<id>.json` contains the payload, source data, server payload SHA256, local script hash, row counts, elapsed time, progress events and failures. The server hash covers its exact Jackson payload serialization, not the whole wrapper or a PowerShell reserialization. It detects changes; it does not prove provenance. The collector checkpoints its own unique report, never overwrites an earlier run, and retains a partial report on failure. No live runtime calls were made locally.

After the first snapshot: inspect computed/blocked rows, source choice and timing; resolve only observed discrepancies. Then bind the independent session calendar and reviewed price policy, link saved validation scopes, add the separately tested 20-session labels, and expand to immutable multi-date data. Chronological split manifests and untouched evaluation must precede model fitting. Do not treat this feature-only artifact as the final training export.

## E38 current handoff: offline session-calendar binding

E37 supplied snapshot completed in 2.21 seconds: MARUTI, NATIONALUM, TARIL and LEMONTREE, each with 495 canonical Upstox bars in the queried window. Dates 2026-04-10, 2026-05-08 and 2026-06-05 each have 252 feature inputs. All 12 rows computed, none blocked/truncated; no model/provider/order/database side effects reported. Prior arithmetic review independently matched all 144 feature values within six-decimal rounding tolerance. All feature inputs arrived after their historical cutoffs, consistent with backfill, not as-known replay. Preserve this file; do not query again just to check dates.

`ReviewNumericalFeatureCalendar.ps1 -EvidencePath <exact-existing-feature-report.json>` binds each row's candle IDs to dates, then compares its ordered inputs to the last 252 sessions of `ops/data/nse-cm-calendar-20250401-20260605-v1.json`. The calendar is independent of candle presence: weekdays minus declared trading closures plus special live sessions. Reviewed scope is **2025-04-01 through 2026-06-05 only**. Unknown dates and insufficient calendar warm-up block; there is no inference outside coverage, no peer-date proxy, and no silent shift of missing sessions. Special live sessions count once even when the annual list marks that date as a regular-market holiday. This is session-date checking, not an intraday market-hours/fill policy.

Official NSE capital-market sources, reviewed 2026-09-18:

| Source | Use in this bounded calendar |
|---|---|
| [CMTR65587](https://nsearchives.nseindia.com/content/circulars/CMTR65587.pdf) | 2025 trading holidays, restricted to supported dates |
| [CMTR70319](https://nsearchives.nseindia.com/content/circulars/CMTR70319.pdf) | Live Muhurat session on 2025-10-21; overrides routine closure |
| [CMTR71775](https://nsearchives.nseindia.com/content/circulars/CMTR71775.pdf) | 2026 trading holidays, restricted to supported dates |
| [CMTR72260](https://nsearchives.nseindia.com/content/circulars/CMTR72260.pdf) | Additional 2026-01-15 municipal-election closure |
| [CMTR72349](https://nsearchives.nseindia.com/content/circulars/CMTR72349.pdf) | Sunday live Budget session on 2026-02-01 |

Date facts are transcribed with source IDs and publication dates. The file is a versioned, bounded retrospective reference, not an automatically current exchange feed or a claim of 15-year calendar completeness. Future amendments require a reviewed new version. It must not be reused for settlement calendars, other segments/exchanges, future trading hours or labels outside scope.

The offline reviewer checks identity/version/bounds, source ID/date uniqueness/order, exact window sequence, missing/extra dates, exclusion flags, input counts, unresolved/duplicate IDs, upstream blocked states and source caps. It does not change the original report or its `FEATURES_ONLY_CALENDAR_UNVERIFIED` status; the separate review reports `MATCHES_REVIEWED_CALENDAR` or `BLOCKED` per row. Even all matches leave `trainingAuthorized=false`, zero labels and explicit remaining gates. Full-envelope source prices, source rights, corporate actions, execution availability and membership are not certified by date agreement.

Input limit 16 MiB; at most four instruments, three rows each, 2,001 canonical bars/instrument and 252 referenced IDs/row. One byte read supplies both the original input SHA256 and parsed data. Server payload SHA256 is retained as a reported identifier, not falsely recomputed from PowerShell serialization. A unique single `numerical-calendar-<timestamp>-<id>.json` embeds the calendar and sources, row discrepancies, input/calendar/reviewer hashes, timing, progress and remaining gates. Checkpoints and failure reports reuse the existing bounded atomic-save helper. Original input is unchanged; report reruns cannot overwrite previous reports. No network, live DB, inference, Java build or Docker restart. Only local output files are written.

E38 offline verification: 37 assertions passed on Windows PowerShell 5.1 (normal/Muhurat/Budget sessions, closure, missing/extra/future/reordered/duplicate/excluded inputs, unknown scope/version/source, unsafe flags, malformed metadata, repeat-run preservation, input hash and failed-read evidence). The actual E37 artifact also matched all 12 windows with zero missing/extra dates. This closes that narrow calendar-window check, not N2 policy freeze or N3 labelled export. PS7 spare confirmation is pending; no Java code changed or Java-suite rerun required.

Next implementation: bind per-instrument stored quality-job/resolution evidence to the selected feature/label periods; establish adjusted-versus-executable price conventions and explicit cost scenarios. Then extend the independently sourced calendar through required label exits, generate next-open/20-session labels, and freeze chronological split manifests before any numerical fitting. Current 12-row success is not a forecast score or a reason to repeat LLM training.
