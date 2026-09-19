# Consolidated real-market research contract review

2026-09-19, E61. **PARTIALLY_APPROVED_RESEARCH_SCOPE / REMAINING_EVIDENCE_PENDING**. E62 records the owner's subsequent approval of the first 20-session price-return research scope and restricted development cohort, and confirmation of the documentation commit. Remaining feature/evaluation/cost/source criteria are not blanket-approved. [E63 bounded preparation implementation](numerical-research-mapping.md) maps saved features and eligibility without fitting or certification. The original six-item proposal below is retained; its historical approval requests are superseded only for those two owner scope decisions.

E65 subsequently verifies mapping/recovery on spare. [E66 pre-fit contract](numerical-prefit-contract.md) supplies detailed learner/preprocessing/evaluation/artifact proposals and code-consistency tests together; it does not settle the open source facts, practical-effect criteria or final-fit approval. The original mapping-future-work wording below is historical; the ten-feature mapper is now verified, while the ten-feature learner remains unimplemented.

**E68 superseding status:** the ten-feature synthetic engineering implementation is now spare-verified (32/32 checks), so the historical learner-unimplemented wording above/below no longer describes that engineering component. It still is not a market-trained predictor. Use the [current research-scope packet](numerical-research-scope-decision.md) for the remaining retrospective/prospective choice and evidence/evaluation decisions. Do not repeat accepted mapping or synthetic checks.

## Why this is the next milestone

The engineering checks for fixed numerical baselines, train-only transforms, temporal guards, synthetic 5/20/60-session folds and hypothetical costs have passed on spare. They do not show that stored market labels or input vintages are fit for a real model. Repeating those checks will not resolve price adjustment semantics, publication timing, constituent history or final-test independence.

This package groups the outstanding decisions instead of requesting separate deployments for each one. Reuse the existing history, 150-date/600-row research export and previous evidence; do not repeat collection. G02/G03/G07 retain their existing goal-level percentages. E60 establishes engineering acceptance only, not owner acceptance of production predictive quality.

## Six associated subgoals, reviewed together

| ID | Proposed contract / work | Existing evidence to reuse | What is still needed |
|---|---|---|---|
| RC1 Target and clock | First real research baseline: daily 20-session, decision at 16:00 Asia/Kolkata only when required data is available; next verified session OPEN entry, entry+19-session CLOSE exit. Separate gross percentage-point return and net scenarios. Missing/non-executable path is censored, never shifted to a convenient date | Existing NumericalDataContract draft and NumericalResearchLabelCalculator; E45/E52 stored-price arithmetic | Owner approval of the research convention, verified calendar/price mapping and row eligibility. This is not a promise of fills at an auction open |
| RC2 Prices and costs | Proposed price-return target, no total-return/dividend-reinvestment claim. Keep feature adjustments distinct from executable prices; no inferred split factors. Preserve versioned hypothetical total round-trip 0/25/50/100bps scenarios from the existing research export | E50/E53 price-policy findings, E52 export; E59 separately tested 0/25/100bps | Provider/action/vintage evidence and explicit treatment approved before certification. Actual fee/slippage assumptions remain unapproved; no cost level chosen for favourable test results |
| RC3 Features and availability | Review the existing ten-feature candidate list below as one mapping contract; exclude future labels/ranks, future news and post-decision approvals. All transformations train-only; critical missing or unverifiable-at-cutoff data cannot silently pass | NumericalDataContract, snapshot calculator/metadata, E37/E39/E52 | Exact production DTO/calculator mapping, units, warm-up/missingness policy and evidence of historical availability. Backfilled received_at is not original publication time |
| RC4 Universe and eligibility | Existing four stocks/150 dates are a development cohort, not all Nifty 500 or 15 years. Keep exclusions, instrument IDs, listing/constituent versions and censored rows visible | E28/E30 universe diagnostics and E52 scoped export | Source rights, point-in-time membership or an explicitly approved restricted retrospective research scope. Restricted research cannot be relabelled as an unbiased Nifty 500 final test |
| RC5 Folds and evaluation | Group by date, purge overlapping labels at both boundaries, train transforms only before cutoff, retain every fold. Propose equal-date MAE against train-mean/zero references as the primary regression metric; also report ranks, direction and coverage. Compare existing deterministic ranking separately without pretending its score is a predicted return | E55-E60 engineering; known inspected SHADOW_TEST periods | Eligible date/cohort counts, actual calendar/split boundaries, minimum effect and uncertainty method must be pre-registered BEFORE opening an untouched market test. No synthetic date layout copied into production |
| RC6 Release boundary | Research-only model artifacts and report; no API/Telegram trading proposals or paper/live orders automatically enabled. Insufficient or negative evidence keeps the baseline and abstention. INR100,000 paper-first/human approval remains the eventual path | Existing roadmap PG1/PG2 and risk/approval boundaries | Owner-approved scoped fit after RC1-RC5 evidence; separate prediction validation and paper integration acceptance. No profit/confidence percentage promised |

## Existing feature proposal, not a newly invented mapping

`NumericalDataContract.draft()` currently lists:

- dailyReturnPercent, closeToSma20Percent, closeToSma50Percent, closeToSma200Percent;
- ema12ToEma26Percent, rsi14, atr14ToClosePercent;
- annualizedVolatility20Percent, volumeRatio20, rangePosition252Percent.

The two-feature synthetic ridge input (`return5`, `volumeRatio20`) is **not** this production feature contract. The current fitter is a fixed two-feature lab, not a generic ten-feature production model. A versioned mapper and appropriate feature-matrix learner implementation remain scoped future work after contract approval. Do not silently rename dailyReturnPercent to return5 or feed the whole evidence envelope into inference. Snapshot E36 uses 252 observed bars; E39's scoped calendar checks do not certify every possible historical window. Financial/news features and intraday data need their own availability contracts and remain outside this first baseline.

## Decisions and evidence required, in one review

1. **Owner decision:** approve or amend the first research target: price-return, daily 20-session next-open/20th-session-close, no dividend/total-return claim, no trading activation. This carries forward the existing draft rather than inventing another target. Required 5/60-session and intraday goals are retained, not cancelled by sequencing 20 sessions first.
2. **Owner decision:** approve or amend restricted development-cohort research as the initial stage, explicitly not full-universe validation. Future data expansion must be bounded and separately authorized; do not recollect the existing history.
3. **External input:** share the redacted Upstox response when received. Status remains PENDING_EXTERNAL_REPLY; no resend or API fetch is authorized. A current generic statement alone does not establish old stored vintages or action completeness.
4. **Before final split release, not after results:** agree minimum practically useful effect, date-dependent uncertainty procedure, actual cost assumptions and the independent evaluation protocol once eligible coverage is known. These are UNSET, not assumed satisfied by an approval of items 1-2. Never choose them to make existing outcomes pass.

Owner approval can settle intended conventions, but cannot replace missing source evidence. Unknown availability remains unknown. If retrospective source vintages cannot be established, return with an explicit restricted-research or prospective-evidence proposal instead of fabricating timestamps, broad recollection or automatic gate relaxation.

## Parallel and sequential work

- **Now / prepared together:** target-and-clock proposal; source/price/cost evidence map; feature/universe mapping checklist; chronological evaluation/release checklist. All six RC items are reviewable in this packet, not marked implemented or approved.
- **Parallel:** owner reviews intended scope; provider reply supplies external facts. No machine run, credentials, new support message or deployment is needed. External reply time cannot be promised.
- **After decisions and evidence:** one bounded implementation plan can combine the real feature mapper, row eligibility ledger, target certification and coverage-driven fold manifest. Exact export/query scope must be reviewed first. Preserve original history and capture exclusions rather than silently repair data.
- **Then:** authorize the real baseline fit and independent evaluation. Positive synthetic results do not authorize this step; paper/live integration follows separate acceptance.

The earlier 6-10 active-working-day engineering estimate after source/policy prerequisites remains conditional, not a countdown. No new deadline or guaranteed number of retries is asserted here. Further synthetic execution is warranted only for an actual code change/regression, not as a substitute for this review.
