# Numerical robustness bundle: frozen synthetic contract

2026-09-19. E58 accepts the previous spare bundle. E59 groups the following engineering work; no real-market fitting or trading is authorized.

1. Three expanding chronological folds for each of 5, 20 and 60 synthetic sessions. All instruments on a decision date stay together; labels must mature before the next partition. Five additional unused sessions separate label horizons from the next decision partition. Each fold has 10 validation dates and 10 test dates; previous test periods cannot reappear in later test sets. Mature past observations may enter later training, as in walk-forward evaluation. Final market-test release is not implemented.
2. Fixed ridge penalty 0.01, ZERO and TRAIN_MEAN references; train-only imputation/scaling. No tuning, validation-driven selection, best-fold selection or automatic promotion. Each horizon is evaluated separately. Aggregate error summaries use all disjoint test predictions, retaining every fold and failures; overlapping forward labels are not independent observations.
3. Hypothetical long-only opportunity arithmetic at fixed **total round-trip** costs of 0/25/100 basis points. Select only predictions strictly greater than the assumed cost in percentage points; net observation = observed percentage return minus that cost. Non-selected rows have zero contribution. Report selected count, coverage, mean selected net (null when none), and equal-date mean contribution. No positions, cash, compounding, SELL policy, broker fees, capital allocation or portfolio return is implied. These are synthetic stress constants, not approved trading thresholds or Indian fee estimates. Costs are never chosen using test results.
4. Explicit engineering/readiness separation: successful synthetic checks still leave price provenance, source availability/universe, real target/cost policy, certified labels and untouched market evaluation unresolved. No report can enable training or orders. Previous 35 checks run inside the same invocation to catch regressions; one compact JSON includes all folds, model/input hashes, predictions, metrics, costs, timings, checks and blockers.

Generated fixtures use 400 ordered artificial session dates, three artificial instruments and a fixed coefficient reversal from session index 160. These targets are algebraic synthetic labels, not returns derived from real candles. They exercise horizon plumbing, chronology and detection of underperformance, not horizon forecasting skill. Every fold is retained. No claim of statistical significance, calibrated confidence or market accuracy is permitted.

This is the next bounded engineering bundle, not an endless prerequisite testing loop. After its spare verification, engineering evidence is retained; real-data fitting stays paused until the named policy/data gates are addressed. Further independent modules require a separately scoped implementation decision.

## Implementation and verification

The JDK-only `Robustness` lab reuses the train-only fitter and guarded metrics from E57. Ranking/comparison functions now accept an explicit horizon contract; their previous 20-session overloads remain unchanged. Each horizon has three expanding training windows (180/270/360 observations), 30 validation and 30 test observations per fold. All 90 test observations/30 decision dates per horizon and comparator are retained in the pooled summary. Horizon labels and prior inspection windows are recorded in each manifest. No Spring bean, endpoint, database, migration, provider, LLM, portfolio ledger or runtime configuration change.

The standalone `--synthetic-robustness` CLI contains the prior 35 checks plus 12 new checks. All fixture configurations are fixed; it cannot load external market files. The PowerShell collector reuses the bounded isolated process and checkpoint writer, records raw/parsed output, source hashes, parameters, manifests, predictions, counters, timing and readiness blockers in **one JSON**. It independently checks pooled rows against all fold outputs, recomputes error metrics and all 27 predictor/horizon/cost combinations, and rejects malformed reports. Child execution is bounded at 120 seconds by default (max 300); setup/cleanup and report validation take additional time. Staged progress/heartbeats are not a model-accuracy percentage. Persistent filesystem locks or shutdown can leave the last atomic checkpoint/pending snapshot; no automatic retraining retry or deletion.

Verification: **340 standard Java tests (9 new), Maven package, 47 synthetic CLI checks and 77 PowerShell 5.1 workflow assertions**. No saved-market-data probes, local service/Docker, provider or LLM runs. The previous E58 report verifies PowerShell 7.6.6 and Docker Java 21.0.9 for the baseline package; the new bundle's spare path remains pending until its report is reviewed. Do not claim new spare success from old evidence.

## One spare-machine run

After pulling the committed revision in the spare repository:

```powershell
& '.\ops\windows\TestNumericalRobustnessBundle.ps1' -Runtime Docker -TimeoutSeconds 120
```

No service rebuild/restart or model download. Uses the already cached Java image with networking disabled; no automatic pull. `-Runtime Java` is an alternative for a local JDK 21+. Share only the printed **numerical-robustness-bundle-<timestamp>-<id>.json**. Expected envelope: `SYNTHETIC_CHECKS_PASSED_TRAINING_BLOCKED`; nested robustness/baseline/evaluation check counts are 12/13/22, total 47; nine folds; zero failures. Full report is approximately 1.7 MiB in local verification, including embedded raw output.

After review, no separate replay of baseline, smoke, history export or LLM sweep is requested. Review the unresolved real-data contracts/evidence before enabling any market fit. The readiness summary is an explicit snapshot of known blockers, not an automated provider-policy certification service. Percentages for full G02/G03/G07 remain unchanged.
