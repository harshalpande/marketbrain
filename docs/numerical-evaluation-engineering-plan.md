# Next work package: numerical evaluation engineering

2026-09-19, E55/E56. Status: **IMPLEMENTED / OFFLINE AND SPARE SMOKE VERIFIED**, not training-ready. E56 accepted 22/22 spare checks in 15.537s; no separate repeat needed. Next is the [E57 combined synthetic baseline bundle](numerical-baseline-bundle.md). E54 prepared the original contract; the owner then authorized implementation. These packages advance independent engineering while the Upstox reply remains pending; they do not certify data or bypass N2/N3/N4.

## Two separate tracks

| Track | Current state | Exit condition |
|---|---|---|
| Price-policy clarification | PENDING_EXTERNAL_REPLY; owner reports email sent; no ticket/reply supplied | Review authoritative response against captured instrument/vintage/action evidence; approve the applicable policy, or explicitly retain unresolved windows |
| Evaluation engineering | EV1-EV3 implemented and spare-verified E56; next E57 bundle | Deterministic metric and leakage tests pass on synthetic fixtures; evidence/report format verified; real-data fitting remains disabled |

Source: E52 accepts the saved 600-row export in 19.824s, but zero labels are certified. All 20 retained SHADOW_TEST dates were already inspected. Neither this package nor a successful Upstox answer turns that development period into an untouched final test.

## E55 delivery and verification

The E55 bullets below preserve delivery-time scope/results. E56 subsequently verified the Docker success path; its report does not identify PowerShell version. E57 adds `--synthetic-baselines` and a `-Suite Baselines` runner option while retaining the default 22-check smoke. No CLI market-data input exists. Historical no-fitting statements refer to E55; E57 explicitly fits synthetic fixtures only.

- `NumericalEvaluationEngineering.java` contains pure metric/guard methods and a fixed synthetic-only CLI. No Spring bean, new endpoint, provider/model/DB dependency, migration or configuration change. Returns use explicit percentage-point units and one horizon/policy/predictor per metric batch. Empty metrics are unavailable; overflow/non-finite inputs fail closed. Input order is normalized, with row- and equal-date-weighted metrics reported separately; equal-date RMSE is the square root of mean daily MSE, not mean daily RMSE.
- Guard rejects (does not silently purge/drop) overlapping labels at both TRAIN/VALIDATION and VALIDATION/TEST boundaries, same-date partition mixing, duplicate identities, invalid horizon ends, insufficient **session** gaps, unknown/future feature availability and inspected/unknown final-test provenance. The five-name synthetic inference allowlist is not an approved production feature list or a mapping from existing snapshots. Declared timestamps/inspection metadata are tested, not independently certified. No production split is frozen.
- CLI has only `--synthetic-smoke`, no market-data input or fitting flag. JDK 21+ runs it using documented [Java source-file mode](https://docs.oracle.com/en/java/javase/21/docs/specs/man/java.html#using-source-file-mode-to-launch-single-file-source-code-programs). Compilation stays in memory; the application is not started. Fixed fixtures and canonical per-case hashes plus source hash make results traceable.
- `TestNumericalEvaluationEngineering.ps1` produces **one compact JSON** (about 16 KiB in local verification) with fixture configuration, baseline fixture rows, checks/hashes, source/script hashes, Java version, stdout/stderr, timing, failures and progress events. Uses the existing atomic writer; unique filenames and an upfront Windows path-length check avoid overwrite/path failures. Staged progress is not an estimate of predictor completion.
- Auto runtime uses local Java when both `java` and `javac` are available; otherwise it uses the cached `maven:3.9.11-eclipse-temurin-21` Docker image. Docker runs a uniquely named temporary container with network disabled, read-only source/root, bounded CPU/memory/PIDs and a temporary `/tmp`; it never starts or rebuilds MarketBrain. No automatic image pull. If the image is missing, explicitly prepare it or use a local JDK. Runtime identity is recorded. No credentials or host environment file is mounted.
- Child execution limit defaults to 120s (maximum 300); image inspection/targeted cleanup use 15s bounds, with bounded pipe drain/termination waits. A timeout is a failure, not an automatic calculation retry. Failure results preserve available evidence; persistent checkpoint locks retain the pending snapshot as defined by the existing writer. Cleanup targets only this invocation's container. Host/process termination can still prevent final reporting; last atomic checkpoint remains useful.
- Verification: **322 standard Java tests passed**, including **13 new tests**; `mvn package` passed. Old saved-market-data evidence probes were not rerun or counted. **22 CLI synthetic checks** plus **30 PowerShell 5.1 workflow assertions** passed, including independent metric expectations, tampered reports, repeat preservation, real native-child failure/timeout and simulated Docker-probe failure. One local full smoke took **2.905s**, not a spare-laptop performance promise. Docker success path and PowerShell 7 runtime await spare confirmation; no local Docker/service/DB/provider/model run occurred.

### Spare smoke (completed E56; no separate rerun)

After pulling the committed changes, run:

```powershell
& '.\ops\windows\TestNumericalEvaluationEngineering.ps1' -Runtime Auto
```

If no JDK is installed and the cached image is unavailable, explicitly run `docker pull maven:3.9.11-eclipse-temurin-21` (checking its exit code) once, then use `-Runtime Docker`. Image download is setup, not an offline test or market-data request. Share only the printed `numerical-evaluation-smoke-*.json`. Expected status: `SYNTHETIC_CHECKS_PASSED_TRAINING_BLOCKED`, 22 checks and zero failures. This validates engineering, not trading accuracy. Do not rerun the 600-row export or an LLM sweep.

## Implementation sequence and acceptance

The table preserves the original E54 estimates, not remaining effort. All three bounded components are now offline and spare verified. These were active engineering estimates, not deadlines or prediction-confidence estimates.

| Step | Bounded deliverable | Required checks | Estimate |
|---|---|---|---|
| EV1 | Pure numerical metric calculator consuming explicit predicted/observed pairs; no fitting or data access | Hand-calculated fixtures for MAE, RMSE, signed bias and direction agreement; counts and units; invalid/duplicate/empty inputs; deterministic output | 1 working day |
| EV2 | Date-grouped evaluation guard and synthetic chronological fixtures | Same decision date never crosses partitions; overlap at a boundary is rejected/purged; unknown availability cannot pass; already inspected data cannot be labelled untouched; future outcome fields excluded from inference contract | 1 working day |
| EV3 | Compact offline evidence/report contract for the two components | One JSON with configuration/version, fixture hashes, counts, metrics, failures and timings; visible progress; atomic unique output; no service/provider/model/DB dependency or fitting switch | 0.5-1 working day |

Do not deploy an endpoint, run a parameter sweep or introduce a model dependency for these pure engineering components. Reuse established source/evidence validation rather than duplicate it. Local verification uses synthetic fixtures only; any spare check is a short offline smoke test, not another historical collection. Full platform work and the month-long paper observation are outside this estimate.

### EV1 contract before implementation

- Each row has an instrument identifier, decision date, prediction identifier, predicted return and observed return. Return values use percentage points, not fractions; evaluation is one horizon and one unit/policy per batch. Reject mixed contracts and non-finite values.
- Unique identity is prediction identifier + instrument + decision date. Reject duplicates rather than silently overweight them. Order changes must not change results beyond documented floating-point tolerance.
- MAE is mean absolute prediction error; RMSE is square root of mean squared error; signed bias uses predicted minus observed. Direction agreement compares negative/zero/positive signs, with zero explicitly treated as flat. It is not a BUY/SELL policy or probability calibration.
- Report row count and distinct-date count, plus row-weighted and equal-date-weighted summaries where applicable. Empty input is unavailable, never zero error or 100% accuracy. Reject unsafe numerical overflow; do not silently emit NaN/Infinity.
- A fixture can supply fixed predictions (for example zero), but no predictor is fitted and no real-data scores are promoted. Train-only mean fitting, rank/top-k metrics, cost/portfolio simulation and date-dependent uncertainty require later contracts and tests; they are not implied by EV1.

### EV2 contract before implementation

- Partition manifests carry explicit decision, label-end and feature-availability times; horizon, gap/embargo convention and inspected-period provenance are inputs, not inferred from a passing score.
- Group all instruments on a decision date together. Conservatively reject/purge training labels ending on or after the next evaluation boundary; invalid/missing timestamps remain failures.
- Exercise boundary equality, gaps, missing availability, shuffled input, duplicates and deliberately contaminated test periods. Synthetic guards test declared metadata; they cannot prove real-world source availability or historical constituent membership.
- Do not freeze production dates, select a winning configuration or inspect a new final test during this package. Preserve the existing 600-row artifact and its provisional development-only layout.

## What remains blocked

Real-data model fitting/promotion, certified returns, final evaluation release, live/paper order generation and claims of improved forecasting. The existing training flag stays false. A provider reply alone is not sufficient: approved price/cost/availability/universe conventions, eligible labels and a genuinely independent evaluation still precede fitting.

## Handoff when the provider replies in another session

Read this file, `numerical-price-policy-open-questions.md`, `numerical-baseline-bundle.md`, `numerical-robustness-bundle.md`, the current roadmap and E52-E59 in the evidence register. Preserve the provider's redacted wording, date, reference/ticket and scope; do not assume current API behaviour proves previously stored vintages. The owner does not want project details disclosed. No automatic external message or provider fetch is authorized.

The accepted artifact is `numerical-expanded-research-20260919-140603-9785384a9616.json`, SHA256 `E983F6EE5B0B6DDA2DE40DC27D37451B2DD58C5D360CBBE092672B9EFD419CA8`; its small review is in `docs/evidence/numerical-expanded-research-spare-review-20260919.json`. No need to rerun that export or the empty repair query. Review the reply as new evidence, then specify any remaining bounded acquisition before changing stored data.
