# Numerical prediction baseline: bounded work package

Status: N1 aggregate audit received and reviewed (E28). N2 draft contract and bounded history collector implemented/offline verified (E29); spare history evidence and contract acceptance PENDING. Owner authorized this next bounded slice. No LLM training, numerical fitting, new dataset persistence, backfill or trading execution in this handoff. Governing goals: G01/G13 evidence, G02 dataset, then G03 numerical baseline. Required 5/60-session and intraday horizons remain in G07, not silently dropped.

## Sequence and gates

| Milestone | Output and acceptance | State | Effort estimate after prerequisites |
|---|---|---|---|
| N1: inspect existing run | One compact report; exact UUID/hash/date; reconcile classifications and 5/20/60 horizon counts, expose exclusions and source limitations | Completed within aggregate-audit scope, E28; not training readiness | Evidence reviewed |
| N2: freeze prediction-grade data contract | Review feature availability, entry/exit convention, calendar, corporate actions, membership and source rights; no future columns in inference | Machine-readable draft plus bounded diagnostic offline verified; runtime review and freeze pending | 1–2 working days after coverage evidence and policy decisions |
| N3: immutable multi-date export | Versioned rows/manifests; leakage/duplicate/gap tests; actual usable dates; no alteration of prototype run | Not implemented | 3–5 working days after N2/source feasibility |
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
