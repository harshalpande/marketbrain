# Ten-feature numerical engineering bundle (E67)

**E68 current status: spare verification accepted; no repeat run.** Native Java 25.0.4.1 / PowerShell 7.6.6 completed all 32 checks in 8.900s. Source identities, raw checksum, semantic numeric parity, artifacts, metrics and safety counters independently reviewed. The Docker/Java21 path was not exercised by that report. [Acceptance evidence](evidence/numerical-ten-feature-spare-acceptance-20260919.json). Next is the [owner-approved two-track preparation](numerical-research-scope-decision.md), not another synthetic or mapping run. The E67 instructions below remain reference/recovery instructions.

2026-09-19. Owner approved implementing the complete **engineering** batch following the verification discussion. This delivers executable numerical machinery and fixed synthetic tests, not a market-trained predictor or permission to fit uncertified history. E66 remains the historical proposal; its unresolved real-data approval fields are not changed to true.

## Delivered together

| Subgoal | Implementation / verification | Remaining boundary |
|---|---|---|
| PF1 input/target | Exact ten-field order and units, separate inference/label metadata, unique instrument/decision join, synthetic 20-session label/calendar checks | Existing 600 mapped market rows remain ineligible; no market-data loader |
| PF2 transforms | Equal-date weights, TRAIN-only anchored weighted mean and two-pass population variance, constant flags/scale 1, no imputation; retained exclusions | No production feature range/calibration policy inferred |
| PF3 learner | Ten-feature weighted ridge, fixed engineering alpha 0.01, unpenalized intercept; zero and TRAIN-mean references | No parameter search or market-calibrated alpha |
| PF4 evaluation | Explicit session windows, whole-date partitions, gaps at both boundaries, actual label-availability purging, inspected-final-test rejection | Real final dates/minimum coverage remain unapproved |
| PF5 metrics | Equal-date MAE/RMSE/bias/direction, tied-rank diagnostics, common prediction population plus full exclusion denominator, all 0/25/50/100 bps illustrative costs; paired moving date-block resampling machinery | Synthetic confidence settings only; no certified winner, broker-cost estimate or executable portfolio return |
| PF6 persistence/reporting | Bounded versioned artifact, exact identity/hash checks, prediction reload parity, one checkpointed report, saved-result replay, bounded process timeout | No active-model registry, promotion, notifications or orders |

`NumericalTenFeatureEngineering` is JDK-only, has no Spring annotation/dependency, no endpoint, no bean, no SQL, no provider access and no application startup change. The executable accepts **only** `--synthetic-suite <codeRevision>` and builds fixed fixtures internally. Package-private numerical components are testable without creating a market-fit entry point. Real-market policy identifiers are rejected; synthetic identifiers are declarations inside this isolated lab, **not** a source certification mechanism for a future endpoint.

The old two-feature lab is unchanged. New source is pinned to the normalized UTF-8/LF E66 contract hash. The source itself, runner, reviewer, process/checkpoint helpers, contract and Git revision are bound into the collection report. A code/contract/source change must be reviewed and cannot silently resume an older report.

## Numerical and safety details

- Exact constants are preserved using anchored mean accumulation; this corrects floating-point drift exposed during development. No arbitrary near-zero cutoff silently discards a feature.
- A fixed 10x10 Cholesky solve checks positive pivots, finite intermediates and residuals. Failure does not trigger an unreported alpha change. Training data/parameters are immutable copies.
- Invalid rows retain partition, identity and reason. Duplicates, partition escapes, empty eligible partitions and numerical solve failures fail closed. Prediction failures abstain on a common population across all references; original denominator remains visible. Metric overflow fails rather than inventing a score.
- All features must be available by decision time. Training labels must be available before validation; validation labels before test. Inference requires no outcome and cannot precede the artifact's fit cutoff.
- Three fixtures have expanding training windows and deliberately different outcomes: LINEAR, FLAT, REVERSAL. They are independent synthetic scenarios, not evidence of generalization across market periods. Reversal underperformance must remain in the report. Synthetic session dates are explicitly generated test dates, **not** a production exchange calendar.
- Moving-block resampling retains paired date groups and their cross-sectional membership via equal-date error means. The fixture uses block length 2, 200 draws, seed 42 and nominal 95% intervals solely to exercise the machinery. Market block size, confidence, sample sufficiency and acceptance thresholds remain unset. The report explicitly distinguishes these fixture checks from unavailable market uncertainty.
- Artifact payload is bounded Base64 binary plus SHA256; metadata includes transforms, coefficients, constant flags, alpha/objective normalization, fit cutoff, train/eligibility/label/fold/inspection hashes, counts, code revision and runtime. Reload requires exact expected metadata and validates dimensions/policy. Checksums detect corruption; they are not digital signatures or a defence against an attacker controlling the trusted source and report together.

## Verification and evidence

The local verification record is [E67](evidence/numerical-ten-feature-local-review-20260919.json). Tests include independent one-dimensional and collinear closed-form ridge answers, hand-calculated unequal-date means/variance, held-out mutation isolation, overflow, both-boundary purges, all-inspected final-test rejection, actual disk artifact reload and bounded/paired uncertainty. The spare suite embeds 32 checks and all three scenario artifacts/results.

PowerShell independently reconstructs fixed synthetic inputs/targets and ridge predictions and recalculates equal-date errors, comparison improvement and hypothetical costs. Offline workflow tests deliberately corrupt flags, checks, model dimensions/coefficients, outcomes, metrics, costs, artifacts, uncertainty labels, coverage and source identity; each must be rejected. They also verify saved-result reuse, unchanged original files, timeout and failure checkpoint persistence.

**Local verification is not spare acceptance.** Docker/Java 21 and PowerShell 7 runtime verification remains for the spare. No local Docker/service/database/provider/LLM run is performed. Existing mapping E65 is reused without another market-data export or HTTP request.

## One spare-laptop command, no service deployment

After a clean fast-forward pull, run:

```powershell
& '.\ops\windows\TestNumericalTenFeatureBundle.ps1' -Runtime Auto -TimeoutSeconds 120 -OutputDirectory 'C:\MarketBrainData\Review'
```

Auto uses a local JDK if Java and javac are available, otherwise the **already cached** `maven:3.9.11-eclipse-temurin-21` image. It never downloads an image automatically. Docker runs a unique temporary container with no network, no application environment, read-only source/root filesystem, bounded memory/CPU/processes and only temporary scratch space; cleanup targets that unique container, never `marketbrain-service`. No compose build, application restart or health request is needed. A JDK older than 21 fails visibly; explicitly select Docker when the correct cached image is available.

The runner shows stage progress and a waiting heartbeat, not a guessed percentage of numerical checks. It writes one uniquely named `numerical-ten-feature-<timestamp>-<id>.json` containing manifest, embedded stdout/stderr, all checks, model artifacts, scenario metrics, timing, errors and safety flags. Share that single file. A process failure is not automatically retried. Interrupted runs leave the most recent completed checkpoint; forceful power loss cannot guarantee the final output is flushed.

If the JVM completed but the client review was interrupted, reuse its saved result:

```powershell
& '.\ops\windows\TestNumericalTenFeatureBundle.ps1' -ResumeReport 'C:\MarketBrainData\Review\numerical-ten-feature-EXACT-SAVED-FILE.json'
```

Replay requires identical code/file/contract identities, a successful bounded JVM result and its output checksum; it re-runs independent review into a new file without modifying the original or executing Java. It does **not** resume halfway through a solver: an interruption before a completed JVM result requires rerunning this short synthetic suite. Completed results must not be repeatedly rerun as a substitute for source evidence.

## Exit criteria and next decision

Engineering acceptance requires all local tests and the complete spare report to pass. Passing means implementation correctness on the covered fixtures, **not** forecast accuracy, percentage profit, production readiness or whole-goal completion.

After spare acceptance, close this engineering checkpoint. Do not initiate more identical mapping or synthetic runs. Next: resolve price/action, original availability and rights evidence; explicitly choose retrospective-only versus prospective scope if historical vintage proof is unavailable; freeze eligible-data evaluation windows and minimum coverage/effect/uncertainty/cost criteria; obtain scoped market-fit approval. Upstox stays PENDING_EXTERNAL_REPLY, 0/600 existing rows are eligible. The INR100,000 paper portal, required 5/60-session models and intraday work remain separate acceptance milestones. Live execution remains disconnected.
