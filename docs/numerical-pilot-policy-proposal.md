# Numerical pilot: grouped policy proposal

2026-09-19. **DRAFT_OWNER_REVIEW — not runtime configuration, collection or fitting approval.** [Machine-readable proposal](../ops/data/numerical-pilot-policy-proposal-v1.json). This adds concrete review choices to the [approved two-track preparation](numerical-research-scope-decision.md); it does not replace the frozen historical evidence or silently fill runtime defaults.

## What is complete, and what this packet changes

E65 mapped the preserved development snapshot: **600 rows, 150 dates, four stocks, ten features**. Point-in-time eligible rows remain **0**; retrospective eligibility remains **unassessed**, not zero and not approved. E68 accepted the synthetic learner engineering. E69/E70's latest successful spare report verifies the bounded storage/recovery checks, not a live collector or prediction performance. Those accepted checks do not require another data export, model run or recollection.

This packet proposes the next operational and evaluation choices together. The pure offline validator checks consistency with prior contracts and enforces that every execution release stays false. It does not establish that these draft thresholds are statistically optimal, source-approved or owner-approved.

## Decision 1 — daily evidence pilot

Recommended first scope: **MARUTI, NATIONALUM, TARIL, LEMONTREE; one accepted daily snapshot per verified exchange session, initially 20 observation sessions**. This is collection feasibility, not completion of a 20-session predictive validation. The latest observation needs another 20-session target path to mature. Intraday and 5/60-session goals remain required separate expansions; no second-by-second feed is enabled here.

| Proposed setting | Purpose and boundary |
|---|---|
| Attempt from session close +30 minutes through +150 minutes, every 15 minutes | Nine attempts per instrument maximum; verified calendar times rather than assuming every session closes at the same clock time. Stop before any next-session opening boundary; a conflicting/special calendar requires review. |
| 15-second request timeout, 512 KiB response ceiling, 36 total provider calls/session | Four stocks × nine maximum attempts; each actual HTTP call, including retry/metadata calls, consumes the total budget. Approved provider limits may require lower limits. Respect Retry-After within the window; no catch-up burst. |
| Final daily bar for the required current session | Do not substitute yesterday's bar or label a late repair as information observed earlier. Provider documentation must establish what its bar timestamp means and how finality is determined. |
| At most 60 seconds from latest required input receipt to decision; clock skew ≤1,000 ms | **Processing latency**, not maximum daily-bar age. All required input receipt and local feature-completion times must precede the decision. Unknown clock health quarantines the observation. |
| 4,096 records / 16 MiB per append-only segment; 512 MiB pilot quota | Includes corrections and quarantined records. Quota exhaustion stops capture and preserves existing data. No overwrite or automatic deletion. |
| Proposed 400-day derived-evidence retention; raw payload retention disabled pending rights | Retention is an owner/source review proposal, not a legal entitlement. Hashes alone cannot replay inputs: require licensed immutable input references, or mark records not replay-certified. Backup location, encryption and rights must be approved first. |

**Retention limitation:** 400 calendar days is a bounded feasibility-pilot proposal, not sufficient storage planning for a wholly prospective 630-date evaluation plus gaps, warm-up and label maturity. Before expanding to full prospective validation, separately approve licensed, replayable archival retention spanning every partition, gap, warm-up, maturity and audit period. Do not silently enlarge retention, erase still-needed evidence or claim the pilot has accumulated an evaluation-ready dataset.

**Important implementation gap:** the existing synthetic ledger guard uses a single provider-event age limit. A daily bar timestamp may identify the session start or date, not publication. Do not pass a 60-second limit to that guard and reject valid daily bars, or replace the event timestamp with receipt to force a pass. A future capture adapter must separately validate session freshness, documented event semantics, actual local receipt, feature completion, processing latency and next-session boundaries. That adapter is not wired by this proposal.

Unknown original publication stays unknown. A verifiable current receipt may prove local possession from that receipt onward; it cannot prove when the provider originally published or revised historical values. Missing source price/action policy and rights remain independent gates. Append corrections with links; never rewrite a prior decision snapshot or silently shift a missing target path to a later session.

## Decision 2 — conservative numerical-research acceptance

Recommended candidate remains **ten-feature weighted ridge, alpha 0.01, no hyperparameter sweep**, against **zero-return and train-only weighted-mean return**. These are proposals for a restricted four-stock research claim; no Nifty500 generalization or executable-profit claim follows.

| Proposed criterion | Why it is proposed |
|---|---|
| At least 252 train dates, 126 validation dates, 252 genuinely untouched final-test dates; all four instruments | Separates development and final assessment across substantially more dates than the present 150-date snapshot. Four correlated stocks still cannot establish broad-market generalization. |
| Whole-date chronological partitions, at least 20 sessions between partitions plus actual label-end/availability purge | Avoids mixing instruments from the same date across partitions and leaking overlapping future labels. Warm-up and outcome maturity are additional requirements. |
| At least 95% forecast coverage overall, 90% per instrument; zero additional model abstention relative to baselines | Prevents selective reporting. Report every preregistered instrument/session, missing input, censored label and failure. Calculate comparative error only on common eligible observations. |
| Equal-date MAE improvement of at least 0.25 percentage points **and** 5% relative to **each** baseline | A proposed practical floor, not a measured gain or promised accuracy. Both conditions must pass; zero baseline error does not produce infinite relative gain. |
| Paired whole-date moving-block resampling, 2,000 draws, fixed seed, 95% intervals; 20-session blocks plus 40-session sensitivity | Lower gain bound must exceed zero against both baselines under both block lengths. Require at least six full 40-session blocks in the final period. These are dependence-sensitive heuristic intervals, not a 95% probability of profitable trades. |
| Freeze eligibility, source/label policy, model selection, code and final-window manifest before final outcomes | Current 600 rows have already been examined and remain development-only. Repeatedly adjusting the model to the final test would consume that holdout; preserve failures and require a new future final set rather than rename/retry it. |

The minimum partitions total 630 evaluated dates plus at least 40 boundary-gap sessions, before additional warm-up/maturity requirements. **The present 150-date development snapshot does not satisfy this draft acceptance design.** Do not shrink the requirements to make it fit. Approval of this proposal would not resolve rights, price/action semantics, historical availability, or produce new eligible data. If eligible coverage is insufficient, report `INSUFFICIENT_EVIDENCE` and do not release a fit/final evaluation. Any separate exploratory-fit contract would require an explicitly scoped, versioned review and must not be called final validation.

RMSE, bias, direction, rank and per-stock/period errors remain diagnostics. Retain all negative results. The 0/25/50/100-bps cost cases remain illustrative sensitivity scenarios, not verified broker charges or a portfolio simulator. Real usefulness must later be assessed with the separate paper ledger, execution assumptions, exposures and drawdowns. No MAE threshold approves trading.

## Grouped owner choices and next gate

1. **Capture:** approve the proposed daily four-stock policy subject to source/implementation gates, or revise the operating limits. This is not collection authorization.
2. **Evaluation:** approve the proposed conservative research criteria before final outcomes, or revise and version them now. Actual dates remain unset until an eligible uninspected cohort can be designated without opening its outcomes.

Both choices can be reviewed while the independent paper-ledger fixture work proceeds. Neither requires another model inference run. After policy approval, implement the session-aware capture/eligibility adapters and their grouped tests; only then request a separate bounded runtime release once source facts, rights and storage permissions are satisfied. No deadline is promised for the provider reply, eligible history or future market outcomes.
