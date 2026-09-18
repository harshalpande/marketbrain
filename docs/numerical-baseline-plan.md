# Numerical prediction baseline: bounded work package

Status: first evidence collector OFFLINE VERIFIED; spare audit result PENDING. Scope owner authorized moving to next steps after accepting G10.6 cleanup. No LLM training, numerical fitting, new dataset persistence, backfill or trading execution in the current handoff. Governing goals: G01/G13 evidence, G02 dataset, then G03 numerical baseline. Required 5/60-session and intraday horizons remain in G07, not silently dropped.

## Sequence and gates

| Milestone | Output and acceptance | State | Effort estimate after prerequisites |
|---|---|---|---|
| N1: inspect existing run | One compact report; exact UUID/hash/date; reconcile classifications and 5/20/60 horizon counts, expose exclusions and source limitations | Collector verified offline, spare result pending | Current handoff; review within next working session |
| N2: freeze prediction-grade data contract | Review feature availability, entry/exit convention, calendar, corporate actions, membership and source rights; no future columns in inference | Draft below; not executable/accepted dataset | 1–2 working days after N1 evidence |
| N3: immutable multi-date export | Versioned rows/manifests; leakage/duplicate/gap tests; actual usable dates; no alteration of prototype run | Not implemented | 3–5 working days after N2/source feasibility |
| N4: chronological evaluation | Freeze train/tune/untouched-test date boundaries; purge overlapping label windows; deterministic fold manifests | Not implemented | 1–2 working days after N3 |
| N5: first numerical challenger | Compare simple fitted model to no-model baselines; out-of-sample error/rank/net-outcome and latency report | Not implemented | 2–3 working days after N4 |

These are scoped engineering estimates, not a promise of prediction quality or calendar completion. History acquisition, provider permissions and future-label maturation may take longer. Failure to beat baseline is a valid outcome, not a reason to tune against the untouched test set. Independent paper-ledger/UI contract design may proceed without model fitting, but implementation and runtime actions remain explicitly scoped. No arbitrary 10–15% improvement or guaranteed BUY/SELL accuracy target.

## N1 handoff

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
