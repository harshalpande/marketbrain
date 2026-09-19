# Next work package: numerical evaluation engineering

2026-09-19, E54. Status: **PLANNED / CONTRACT PREPARED**, not implemented or training-ready. The owner requested parking the Upstox clarification and advancing the next stage. This package prepares independent engineering while that external reply is pending; it does not certify data or bypass N2/N3/N4.

## Two separate tracks

| Track | Current state | Exit condition |
|---|---|---|
| Price-policy clarification | PENDING_EXTERNAL_REPLY; owner reports email sent; no ticket/reply supplied | Review authoritative response against captured instrument/vintage/action evidence; approve the applicable policy, or explicitly retain unresolved windows |
| Evaluation engineering | Contract and acceptance plan prepared below | Deterministic metric and leakage tests pass on synthetic fixtures; evidence/report format verified; real-data fitting remains disabled |

Source: E52 accepts the saved 600-row export in 19.824s, but zero labels are certified. All 20 retained SHADOW_TEST dates were already inspected. Neither this package nor a successful Upstox answer turns that development period into an untouched final test.

## Implementation sequence and acceptance

Estimates are active engineering effort after starting each item, not unattended execution, fixed deadlines or prediction-confidence estimates. No waiting on the provider is included.

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

Read this file, `numerical-price-policy-open-questions.md`, the current roadmap and E52-E54 in the evidence register. Preserve the provider's redacted wording, date, reference/ticket and scope; do not assume current API behaviour proves previously stored vintages. The owner does not want project details disclosed. No automatic external message or provider fetch is authorized.

The accepted artifact is `numerical-expanded-research-20260919-140603-9785384a9616.json`, SHA256 `E983F6EE5B0B6DDA2DE40DC27D37451B2DD58C5D360CBBE092672B9EFD419CA8`; its small review is in `docs/evidence/numerical-expanded-research-spare-review-20260919.json`. No need to rerun that export or the empty repair query. Review the reply as new evidence, then specify any remaining bounded acquisition before changing stored data.
