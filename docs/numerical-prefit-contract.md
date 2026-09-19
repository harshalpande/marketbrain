# One pre-fit package: learner, validation and evidence

2026-09-19, E66. **PROPOSED_CONTRACT_NOT_EXECUTABLE**. Owner authorized progressing with multiple associated subgoals after E65 mapping acceptance. This package specifies them together; it does not approve missing source evidence, fit a market model or change any runtime gate.

Machine-readable specification: [numerical-prefit-contract-v1.json](../ops/data/numerical-prefit-contract-v1.json). `NumericalPrefitContractTest` checks agreement with the actual ten-field Java DTO, existing target contract and accepted E65 evidence. The JSON is a review artifact, **not loaded by a service, fitting endpoint or inference process**. Its false approval fields document unresolved decisions; editing them would not authorize a run.

Verification: six contract-consistency tests and the full **353-test Java suite/package** pass with zero failures/errors/skips. [Evidence record](evidence/numerical-prefit-contract-local-review-20260919.json). This verifies repository alignment, not prediction quality or numerical correctness of a ten-feature solver that has not yet been implemented.

## Six subgoals in one review and implementation boundary

| ID | Specification delivered now | Reuse / subsequent implementation |
|---|---|---|
| PF1 | Exact ten-feature input order/units; separate identity, availability and target metadata; 20-session price-return target | Reuse E63/E65 mapper. Still need evidence-backed eligibility and certified target join; never feed the whole evidence envelope to a learner |
| PF2 | Train-only weighted standardization, complete-feature policy, constant-feature handling, no hidden clipping/imputation | New ten-feature transformer still to implement; existing two-feature optional-volume imputation is NOT inherited |
| PF3 | Zero-return and weighted train-mean references; one deterministic ridge challenger and explicit objective | New ten-feature solver still to implement. No model/LLM sweep, no parameter search and no market fit in this milestone |
| PF4 | Date-grouped chronological folds, both-boundary purging, label availability, inspection ledger and sealed final assessment | Reuse temporal-guard concepts. Actual eligible coverage and final dates remain unset; no existing inspected window becomes an untouched test |
| PF5 | Equal-date primary error, coverage/rank diagnostics, all hypothetical cost cases, date-dependent uncertainty proposal | Exact practical-effect, sample-size and uncertainty parameters require review before opening a final test; none selected to manufacture a winner |
| PF6 | Versioned model/transform artifact, replay parity, full failure ledger, one shareable run report, explicit release gates | New ten-feature persistence/prediction implementation remains future work. No automatic promotion, notifications or orders |

These are **specification deliverables**, not six implemented/production-accepted capabilities. Whole-goal percentages are unchanged; prediction quality remains unmeasured. The mapper and existing synthetic evaluator retain their already earned, separately scoped evidence.

## PF1: what the future learner will consume

Use `NumericalResearchMapping.Vector`'s exact ten fields, in declared order. `volumeRatio20` is a ratio, RSI an index, other mapped inputs percent measures. Do not rename `dailyReturnPercent` to the synthetic lab's `return5`.

Identity and provenance remain outside the vector: immutable instrument ID, decision instant, evidence-backed feature availability instant, source/eligibility hashes. Target metadata joins separately on unique instrument ID and decision instant, with matching calendar/price/label policies. Inference must be possible without a target. Reject duplicates, mismatched policies, unknown availability, future inputs or non-finite values. The current E65 ledger's `mappingReady=true` is not an eligibility certificate.

Target: existing approved intended daily 20-session **price return in percentage points**, next verified session OPEN to entry+19 verified sessions CLOSE. Do not claim dividend-reinvested returns or obtainable auction fills. Missing/non-executable paths remain censored and visible, never shifted. Intraday and 5/60-session objectives remain separate required work, not silently dropped or pooled with horizon 20.

## PF2-PF3: concrete algorithm proposal

For each training date `d` with `n_d` eligible rows and `D` training dates, propose row weight `w_i = 1/(D*n_d)`. These weights sum to one and give each date equal influence. Only the TRAIN partition supplies means, population variances and the target mean. Validation/test use those frozen statistics. Store constant-feature flags; a constant training column uses scale 1. No feature selection, clipping, target normalization or missing-feature imputation in V1. Retain excluded/abstained rows and reasons; never reduce the denominator invisibly.

Proposed references: prediction zero, and the weighted TRAIN target mean. Challenger: ten-feature ridge minimizing:

`sum_i w_i * (y_i - intercept - standardizedFeatures_i dot beta)^2 + alpha * sum_j beta_j^2`

The intercept is unpenalized. Propose fixed alpha 0.01 for the initial engineering contract, **not a calibrated market setting or approval to fit**. No automatic adjustment of alpha after solver failure; reject non-finite inputs/intermediates or an unstable solve. The normalized objective must be recorded because alpha values are not interchangeable across sum-loss and average-loss implementations. Persist double-precision finite statistics/parameters with reproducible serialization; declare prediction-parity tolerance before implementation acceptance.

The old two-feature synthetic solver uses equally weighted rows and can impute missing volume with its training mean. This new proposal differs deliberately: ten required features, explicit equal-date weights, no imputation. It must be a separately versioned implementation, not a quiet alteration of the accepted lab. No Python/scikit-learn dependency is added. The [official ridge reference](https://scikit-learn.org/stable/modules/generated/sklearn.linear_model.Ridge.html) documents the L2-regularized objective; our weighting/normalization and alpha are project proposals, not source-certified trading recommendations.

Training-only preprocessing prevents held-out information from influencing the model. This is consistent with the [official leakage guidance](https://scikit-learn.org/stable/common_pitfalls.html#data-leakage). Future tests must mutate held-out features/targets and show that fitted TRAIN statistics and coefficients do not change.

## PF4: chronological evaluation without reusing an examined test

Keep all instruments on each verified exchange-session date in the same partition. No random row split. For each development fold, expand training chronologically; propose a conservative 20-session gap at both TRAIN/VALIDATION and VALIDATION/TEST boundaries, **and** independently require earlier labels to have ended and become available before the next partition boundary. A gap alone does not establish availability or eliminate all dependence.

Use explicit reviewed session indexes, not calendar-day subtraction or weekends guessed as exchange sessions. [TimeSeriesSplit documentation](https://scikit-learn.org/stable/modules/generated/sklearn.model_selection.TimeSeriesSplit.html) motivates ordered/gapped evaluation, but its row-count gap does not implement our multi-instrument/date-grouped, label-availability rules. No unmodified library splitter is claimed sufficient.

All existing 600 rows/150 dates are development evidence for this proposal. Previously inspected SHADOW_TEST periods cannot become a final untouched test by renaming the file. Final windows, minimum train/validation/test date counts and instrument coverage remain **null/unapproved** until admissible coverage is established. Approval of the final protocol must precede examining the final outcomes. Keep every fold, including losses; don't select the best few folds and call them generalization.

## PF5: what counts as evidence, not a promised winner

Propose **equal-date MAE in percentage points** as primary; secondary RMSE, signed bias, direction agreement, within-date rank correlation, coverage and abstention reasons. Compare learner and references on the same rows/dates, but also retain the full eligibility/abstention ledger so common-row filtering cannot hide failures. Existing deterministic Java scores get a separate ranking comparison, not return-MAE comparisons against an arbitrary score. Relative improvement is unavailable if baseline MAE is zero.

Keep all existing hypothetical total round-trip **0/25/50/100 bps** scenarios. These are not approved broker fees. Their independent-observation arithmetic is not a capital-constrained portfolio: it does not establish feasible fills, overlapping-position returns, drawdown or a Sharpe ratio for an executable strategy. The later INR100,000 paper account remains a separate acceptance milestone.

Proposed uncertainty approach: paired resampling of contiguous date groups of learner-versus-reference errors, retaining all instruments in each selected date. Do not independently bootstrap stock rows as if 600 rows were 600 independent trials. Block length, resample count, seed, confidence level and minimum effective coverage are **unset** and require review for the observed dependence and eligible history before a sealed assessment. This is a method proposal, not a statistical sufficiency claim for 150 overlapping dates/four stocks.

Also unset: minimum absolute/relative MAE improvement, maximum acceptable coverage loss and actual cost/slippage policy. Until these are explicitly approved, output may be research observations only: no certified winner, promotion or probability-of-profit claim. Requested 10-15% improvement is an aspiration, not a manufactured acceptance threshold or forecast.

## PF6: artifact, observability and regression work in the same batch

A future model artifact must bind code/contract/feature versions, ordered means/scales/coefficients, constant flags, intercept/alpha/objective normalization, fit cutoff, training source/eligibility/label hashes, fold and inspection-ledger hashes, row/date counts and runtime version. Reload must reproduce predictions within the declared tolerance or fail closed. Unknown/mixed feature or policy versions reject, not silently coerce.

The same implementation batch should include all eleven regression categories in the JSON: ten-feature alignment, held-out mutation isolation, evidence/missingness rejection, constant/collinear inputs, overflow/unstable solve, deterministic ordering, both-boundary purging, untouched-test governance, artifact parity, negative-result retention and absence of gate bypasses.

Keep one shareable future-run artifact containing manifest, timing, model identity, every fold/cost result, attempts, exclusions and failures. Save checkpoints with unique run IDs; resume only matching input/contract/code/artifact identities. Real progress must count completed work, not elapsed guessed percentages. This is a future implementation requirement; no new runner is introduced now.

## Dependency order and no-repetition rule

1. **Done:** E65 verifies the mapping/recovery checkpoint. Reuse it; do not rerun.
2. **This milestone:** PF1-PF6 specification and repository consistency tests together. Contract tests are local development checks, not another spare data-processing request.
3. **Next engineering batch after contract review:** implement ten-feature transformer/solver, references, evaluation/abstention reporting and artifact round-trip together; verify with focused deterministic fixtures. No market-data fit is implied by unit tests.
4. **External track:** Upstox reply remains PENDING_EXTERNAL_REPLY. Match its facts to actual stored provenance; review rights and original availability separately. No new support message, provider request or history recollection here.
5. **Real fit release:** evidence-backed eligible rows, price/availability scope, final evaluation criteria and scoped fit approval must all be established. Currently 0/600 rows qualify. If original-vintage proof is unavailable, return for an explicit retrospective-only versus prospective-capture scope decision; do not silently loosen the gate or wait through repeated identical exports.

No fixed deadline is promised for external evidence. The owner does not need to run anything on spare for E66, beyond an optional Git documentation/contract sync. No Docker rebuild, Java endpoint call, model download or inference.
