# Synthetic numerical baseline bundle

2026-09-19. E58: spare bundle accepted, **35/35 checks in 29.200s**. [Persisted review](evidence/numerical-baseline-spare-review-20260919.json). No separate rerun needed. Next is the [combined robustness bundle](numerical-robustness-bundle.md). Owner authorized grouping associated numerical-prediction subgoals. Contract frozen before implementation; real-market training is not authorized.

## Scope and acceptance

1. **Comparators:** zero predicted return and mean training target, evaluated on exactly the same held-out synthetic rows as the learner.
2. **Learner:** deterministic two-feature ridge regression, fixed penalty 0.01, intercept unpenalized. No hyperparameter search or selection using held-out labels. Percentage-point targets, 20 synthetic sessions ahead.
3. **Preprocessing:** means and population scales fitted on TRAIN only; critical return feature missing/non-finite rejects input; optional volume-ratio feature uses the observed training mean when absent. All-missing optional training feature rejects fitting. Constant columns use scale 1. Fit requires every training label available strictly before the declared fit cutoff; features must be available by decision time.
4. **Scenarios:** linear relationship, constant target, and a relationship that reverses outside training. Fixed generated data, chronological same-date groups, 20-session labels and separated partitions. VALIDATION and TEST summaries are separate. These are synthetic fixtures, not uninspected market tests.
5. **Evaluation:** reuse error metrics and temporal guards; add per-date Spearman rank correlation with average ranks for ties, explicit unavailable counts for constant/single-item groups, and tie-inclusive top-prediction outcome means. Those are arithmetic summaries, not executable portfolio returns. Comparison uses equal-date MAE with a fixed 1e-9 tie tolerance; no automatic promotion. The reversal case must expose learner underperformance and the constant case must retain ties.
6. **Evidence and repeatability:** one compact JSON with input/model hashes, fitted parameters, held-out predictions, metrics, timings and safety checks. Shuffling training rows leaves the artifact unchanged. Changing held-out outcomes must not change fitted parameters or predictions. Serialized artifact parity is tested offline. Continue the previous 22-check evaluation regression suite in the same invocation.

No provider calls, DB access, model downloads, Spring endpoint, live/paper orders, real-data fitting or approved production feature mapping. Fit and prediction methods operate on supplied synthetic fixtures only through the CLI. The engineering gate remains distinct from approval of real data, source rights, availability, price/cost/universe policy and an untouched chronological market test.

Upstox clarification remains PENDING_EXTERNAL_REPLY. Preserve the verified 600-row research export and the previous smoke; do not repeat those as separate jobs. This package does not establish forecasting accuracy or finish G03.

## E57 implementation and verification

All six scoped components above are implemented and offline verified; E58 subsequently verified the spare Docker/PowerShell 7.6.6 run. **331 standard Java tests (9 new), Maven package, 35 synthetic CLI checks (22 regression + 13 new), and 51 PowerShell 5.1 workflow assertions (30 existing + 21 bundle) passed at E57 delivery.** The bundle workflow independently recomputes held-out error metrics, verifies comparator row/target identity, preserves ties and rejects corrupted evidence. Java tests additionally cover constant/collinear inputs, missingness, bounds/overflow and an actual JSON parameter round-trip. CLI checks only copy-artifact parity; do not confuse that with the separate serialization test.

Local JDK execution took **4.601s**, with one **418,268-byte JSON**. This is not a spare runtime promise. Staged progress and five-second child heartbeats are visible; the 120s child timeout (max 300) plus bounded setup/cleanup waits prevent an hours-long model loop. No retries, downloads or market-data access. Runtime/PowerShell version, source/runner/helper hashes and raw process streams are captured. The wrapper delegates to the same tested process/atomic checkpoint path as E55. A persistent file lock or forced host shutdown can leave a pending checkpoint; the previous report is never deleted to recover.

Each scenario has **120 TRAIN rows, 45 VALIDATION rows and 45 TEST rows** (3 synthetic instruments; 40/15/15 date groups). Twenty-session labels and five-session separation are declared against a generated synthetic calendar, not the NSE calendar. Train-only fitting and complete-manifest guarding are separate checks; the pure fitter is not a real-data certification API. Training data is reproducible from the fixed generator/source hash and fixture hash; the report embeds parameters and held-out predictions, not a new export of stored market data. `syntheticTrainingPerformed=true` and `realMarketTrainingAuthorized=false` deliberately distinguish the two.

Observed synthetic TEST equal-date MAE (percentage points):

| Scenario | Zero | Training mean | Ridge | Expected interpretation |
|---|---:|---:|---:|---|
| LINEAR_SIGNAL | 4.6213 | 4.5900 | 0.0659 | Learner recovers the constructed relationship |
| CONSTANT_TARGET | 2.0000 | 0.0000 | 0.0000 | Preserve mean/learner tie; no forced winner |
| REGIME_REVERSAL | 5.0867 | 5.0822 | 10.1229 | Learner loses; report the failure honestly |

These deliberately constructed results are not stock-market accuracy or model-selection evidence. Undefined rank correlations remain null, not zero. Top-outcome means omit costs and execution and are not portfolio returns. All model/policy promotion remains disabled. No Spring wiring or deployment setting changed.

## Historical spare handoff (completed E58; do not rerun separately)

Pull the committed revision, then run in the spare repository:

```powershell
& '.\ops\windows\TestNumericalPredictionBundle.ps1' -Runtime Docker -TimeoutSeconds 120
```

Use the already cached `maven:3.9.11-eclipse-temurin-21` image verified by E56; the script refuses automatic pulls. Local JDK 21+ is an alternative with `-Runtime Java`. No MarketBrain rebuild/restart, health request, dataset path, LLM or credentials are needed. Share **only** the printed `numerical-prediction-bundle-<timestamp>-<id>.json`. Expected envelope: `SYNTHETIC_CHECKS_PASSED_TRAINING_BLOCKED`; nested regression has 22 checks and baseline suite has 13 checks, three scenarios, zero failed checks.

## Next milestones and dependencies

1. **Completed E58:** all six engineering components verified in one spare run. Next use the robustness bundle; do not schedule six separate collections or repeat completed exports.
2. **Parallel external track:** await Upstox source-policy response and reconcile it with captured provenance. No new provider request or policy assumption is authorized here; external response time is unknown.
3. **Before any real-market fit:** approve target/price/cost/availability/universe contracts, eligible labels and leakage-safe chronological splits. Existing inspected shadow dates stay development-only. These gates cannot be closed by a synthetic pass or by a provider reply alone.
4. **After authorization and those gates:** use the same comparator/metric structure for a bounded real-data baseline, then genuinely out-of-time validation before paper integration. Intraday and 5/60-session targets, cost/portfolio simulation, uncertainty calibration, model registry and ongoing drift monitoring remain separate work, not claimed complete by this 20-session synthetic bundle.

Six bundled engineering components can be checked together; the end-to-end predictor has no justified completion percentage or finish-date guarantee yet. No need to wait for external policy evidence to verify this isolated implementation.
