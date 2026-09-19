# Next stage: choose research scope, then preregister market evaluation

**Subsequent implementation E69:** after owner approval to proceed, the [evidence-layer batch](numerical-evidence-layer.md) implements read-only snapshot assessment and standalone record-store infrastructure. The preparation decisions below remain the baseline, not a claim that no later engineering occurred. Actual capture/fit remains unreleased; the next spare action is E69's new persistence verification, not repeating E65/E68.

2026-09-19, following E68. **BOTH-TRACK PREPARATION OWNER-APPROVED / NO MARKET FIT OR COLLECTION RELEASED.** The owner answered: "Prepare both tracks (recommended)". [Versioned preparation plan](../ops/data/numerical-two-track-plan-v1.json), a document rather than runtime configuration.

The ten-feature engineering checkpoint is complete: 32/32 checks on the spare laptop in 8.900s, native Java 25.0.4.1 / PowerShell 7.6.6. [Acceptance record](evidence/numerical-ten-feature-spare-acceptance-20260919.json). Do not rerun it or the accepted mapping/export merely to reconfirm completion. No new data-processing script is needed for this decision.

## Recommended next scope: prepare two tracks, without merging their claims

| Track | Useful question | Limitations and prerequisites |
|---|---|---|
| A: restricted retrospective snapshot research | Can the existing ten-feature model describe/predict held-out outcomes within this stored historical snapshot better than simple references? | Reuse the four-stock/150-date/600-row development cohort. Explicitly allow only a retrospective interpretation; original feature vintages and point-in-time universe membership remain unknown. This cannot demonstrate what could actually have been predicted live. Price/action handling and applicable data rights still require evidence/review before fitting. No broad recollection, silent adjustments or fake availability timestamps. |
| B: prospective timestamped validation preparation | What must we preserve now so later forecasts can be compared against outcomes using demonstrably available inputs? | Design immutable decision-time feature/source snapshots, feed arrival and provider event timestamps, policy/model hashes, exclusions, forecast artifacts and matured outcome joins. This turn does not start collection, subscriptions, schedules, fitting or notifications. Prospective arrival evidence does not automatically resolve price/action semantics or source rights. |

Alternative: keep all market-data research paused until historical evidence is sufficient, and prepare only the prospective design if separately authorized. An Upstox reply may clarify provider policy but need not prove how the old stored snapshot was adjusted or which version was available on an earlier date.

**Owner decision recorded:** prepare both tracks. This acknowledges their different claims; it does not certify the stored data, authorize a fit, accept source terms or enable orders. Existing `trainingEligible=false` records and the E66 contract stay unchanged. Any future retrospective eligibility must be a separate versioned policy and report, never an overwrite of failed point-in-time checks.

## Concrete preparation completed in this packet

**Track A pins existing evidence:** MARUTI, NATIONALUM, TARIL and LEMONTREE; 600 rows/150 decision dates from 2025-10-27 to 2026-06-05. E52 source and E65 mapping file hashes were rechecked locally against preserved files, without a Java/API/provider/model run. All rows remain development-only. The new plan distinguishes 0 point-in-time eligible rows from **unknown/not-yet-assessed** retrospective eligibility; it does not falsely claim a relaxed policy has been implemented or passed.

**Track B specifies the evidence record:** stable instrument identity, universe/provider/source revisions, separate provider-event/receipt/decision/input-availability instants, clock health, raw-input hashes, feature order/units/values/calculator revision, calendar and price-action policy identities, rights-scope reference, quality and exclusion reasons. Proposed initial scope is the same four-stock daily/20-session pilot, not second-by-second Nifty500 deployment. Intraday and 5/60-session goals remain separate required expansions.

Records must be append-only; corrections reference earlier records. Identical identity/payload repeats deduplicate; changed payload at the same decision becomes a visible revision/conflict. Never infer the provider's publication time from local receipt. An arbitrary 16:00 timestamp cannot make delayed inputs eligible. Store matured outcomes separately; forecasts, once a model is approved, must be frozen before those outcomes. No prediction is fabricated while no eligible trained model exists.

No credentials enter shared evidence. Source rights and privacy determine whether raw payloads can be retained; storage/backup, retention, staleness and clock-skew limits, provider timeouts and scheduling need operational review before a collector is implemented or deployed. These fields are explicit nulls in the plan, not hidden unlimited/default policies.

## Group the next deliverables to avoid repeated runs

The scope choice is now recorded. The plan groups the following deliverables; evidence-dependent release fields remain pending rather than silently approved. Reuse saved evidence; do not schedule another machine export as a prerequisite for this planning work.

1. **Scope and evidence matrix:** identify which claims the chosen research scope can support; distinguish owner policy choices from missing source facts. List price/action handling, rights, universe restrictions and historical availability separately. Keep the Upstox response pending; no new support message or provider request.
2. **Eligible-cohort and clock contract:** pin existing input/label/feature hashes, the initial 20-session target, verified sessions and exclusions. Do not change the intended intraday and 5/60-session goals; they remain separate work. All already inspected 600 rows are development evidence, not a fresh final holdout.
3. **Evaluation preregistration:** freeze the chosen learner and baseline definitions, chronological/purged folds, date and instrument coverage requirements, acceptance effect and uncertainty rules before opening any final outcomes. If eligible coverage is insufficient, report insufficient evidence rather than reduce the requirements after seeing results.
4. **Prospective evidence design, if chosen:** define a bounded capture scope and durable record contracts using existing providers where allowed; specify idempotency, timestamp quality, missing/stale-data rejection, storage and retention before implementation. Actual capture needs a reviewed operational plan and authorization, not a new shell loop added opportunistically.
5. **Single later execution handoff:** only after evidence, criteria and explicit fit scope are resolved, implement the necessary market-data adapter/gates and give one bounded combined script with one report. No active-model promotion or trade/alert pipeline is implied.

## Proposed evaluation structure versus decisions not yet frozen

The existing proposal keeps equal-date MAE as the primary return-prediction metric and compares the learner against **both** zero-return and TRAIN-mean baselines on common observations, with full exclusion/coverage denominators. Direction, ranking, bias and errors by chronological period remain diagnostics, not substitutes for primary failure. Keep all negative folds and all illustrative cost cases.

The exact minimum train/validation/final-test dates and instruments, minimum absolute and relative MAE gain, permitted coverage loss, block-resampling length/count/seed/confidence, final windows and real fee/slippage assumptions remain **UNSET**. They must be agreed from the allowed use and eligible coverage, not selected to make the learner win. The synthetic 95%/200-draw settings are test fixtures only. No synthetic improvement percentage is a target achieved on stocks.

Neither an owner scope choice nor a documentation commit resolves source evidence. A sealed uninspected final evaluation needs genuinely uninspected eligible data; renaming the current cohort cannot provide it. Later paper acceptance additionally needs conservative executable fills, overlapping-position accounting, risk/approval behaviour and the INR100,000 ledger. A 20-session forecast needs those future sessions to mature; an engineering runtime is not the validation horizon.

## Current action boundary

- Completed now: durable E68 acceptance, owner-approved two-track preparation, a hash-bound retrospective scope, prospective evidence-record contract, current documentation/diagram alignment and the versioned planning JSON.
- Still requiring operational/evaluation approval: actual capture settings and market evaluation criteria, followed by implementation/collection/fit release. The track choice is not approval of arbitrary thresholds or source exceptions.
- Awaiting evidence: source price/action facts, applicable rights, availability appropriate to the chosen claim.
- No application code, deployment, model/data run or collection in this turn. No spare action beyond optional Git synchronization. No fixed deadline for external evidence, no promised number of retries and no forecast-quality percentage.
