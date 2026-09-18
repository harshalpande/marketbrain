# Roadmap and completion dashboard

Baseline: 2026-09-18. Authority: [documentation index](README.md). Evidence: [register](evidence-register.md). Daily changes: [progress log](daily-progress.md).

## How percentages work

These percentages measure engineering delivery, **not investment accuracy, probability of profit, or confidence in a model**. This is a new, broader scope; it must not be compared with old experimental scorecards or a previously quoted project percentage.

Each delivery goal has five binary checkpoints. A checkpoint earns its entire weight only when its stated scope is complete; partial work remains visible in the subitems without earning the whole checkpoint.

| Checkpoint | Weight | Required evidence |
|---|---:|---|
| D: design recorded | 10% | Reviewable scope, contracts, safety boundary and acceptance criteria in this baseline; owner acceptance is a separate checkpoint |
| I: implementation present | 30% | Complete scoped implementation in versioned source; presence is not proof of correctness |
| V: offline verified | 20% | Reproducible passing tests against the identified implementation revision |
| R: runtime verified | 20% | Spare-laptop evidence satisfying the goal's integration criteria |
| A: accepted | 20% | Owner accepts the scoped evidence and all goal-specific safety/quality criteria |

No credit for anticipated results, expired evidence, undocumented assumptions or a failed test. A superseding change invalidates affected verification checkpoints until rechecked. Record numerator/denominator as well as percentages. Historical functionality is acknowledged, but old runtime claims do not establish current deployment readiness.

## Current dashboard

The weighted baseline is **13% engineering delivery**: `(10 × 40 + 90 × 10) / 100`. Ten percent of each goal is the design now recorded. G01 receives an additional implementation-presence checkpoint for its narrowly scoped existing REST/daily pipeline. No current V/R/A checkpoints are claimed. **Live-order readiness is not approved; numerical predictive performance is unmeasured.**

| Goal | Scope | Weight | Checkpoints | Completion | Area status / pending work |
|---|---|---:|---|---:|---|
| G01 | Verify existing Upstox REST and historical/daily pipeline | 10 | D, I | 40% | Implemented foundation; refresh tests, runtime and data-coverage evidence |
| G02 | Point-in-time, multi-date prediction dataset | 10 | D | 10% | Prototype datasets exist; executable labels, vintage data and leakage controls pending |
| G03 | Numerical 20-session swing predictor | 15 | D | 10% | Design only; no fitted/calibrated predictor established |
| G04 | Upstox streaming and live aggregation | 10 | D | 10% | REST is not streaming; streaming implementation pending |
| G05 | Paytm live market data, read-only | 5 | D | 10% | Historical client exists; current live API/auth/entitlement verification and integration pending |
| G06 | Governed Marketaux ingestion and news features | 5 | D | 10% | Ingestion foundations exist; reliable entity/event pipeline pending |
| G07 | 5/10-session swing and 30/60-minute intraday prediction | 10 | D | 10% | Design only; horizon-specific datasets and validation pending |
| G08 | INR 100,000 paper account, orders and fills | 10 | D | 10% | SQL foundations exist; complete accounting/execution simulator pending |
| G09 | Functional portal, approval and notifications | 10 | D | 10% | Static UI and notification foundations; end-to-end paper workflow pending |
| G10 | Integrated security, operations and recovery | 5 | D | 10% | Existing safeguards to reuse; full release verification pending |
| G11 | Prospective month-plus paper validation | 10 | D | 10% | Trial protocol designed; no qualifying trial claimed |
| G12 | Paytm real order execution | Excluded | None | 0% | Deferred; separate authorization and release decision required |

G00, the documentation/evidence-reset task, is tracked separately from product delivery: **3/5 checkpoints (60%)** — inventory mapped, canonical plan written, evidence/uncertainty register written; exhaustive source-review coverage and owner acceptance remain pending. A broad repository scan is not a certified line-by-line audit. This explicitly preserves the outstanding depth of the earlier audit request.

## Work items and acceptance gates

Legend: `DONE-SOURCE` = found in source, `PARTIAL` = reusable but incomplete for this goal, `DESIGNED` = specified here, `PENDING` = no accepted implementation/evidence. These labels are not additional numerical checkpoints.

### G01 — Existing Upstox REST and daily foundation

- G01.1 `DONE-SOURCE`: instrument import, quotes, historical/intraday candle import and corporate-action access; evidence E02.
- G01.2 `DONE-SOURCE`: persisted historical backfill, daily enrichment, technical snapshots; E03.
- G01.3 `PENDING`: verify tests at an identified revision, authentication, entitlement, canonical instrument mapping and current deployment configuration without exposing credentials.
- G01.4 `PENDING`: collect actual Nifty 500 coverage, missing sessions, duplicates, corporate-action adjustments, source priority, recovery and backup/restore evidence.
- Acceptance: all declared operations pass contract tests and a bounded spare-laptop check; coverage report explicitly lists unavailable symbols/dates; no claim of second-by-second streaming from REST. A data-readiness threshold is frozen before G02 acceptance; critical missing features cause exclusion, never silent imputation.
- Dependencies: G00 scope/evidence approval. Proposed window: D1–D10. Responsible roles: implementation engineer; owner supplies account/access evidence and accepts.

### G02 — Prediction-grade dataset

- G02.1 `PARTIAL`: prototype immutable runs and 5/20/60-session outcome labels exist; E04.
- G02.2 `DESIGNED`: introduce versioned feature/label contracts, exchange calendar, next-executable-price convention, actual availability times, corporate-action handling and membership history.
- G02.3 `PENDING`: multi-date export; identify survivorship limitations when historical constituents are unavailable; separate adjusted features from tradable prices.
- G02.4 `PENDING`: chronological train/tune/final partitions, overlap purging, future-field exclusion, duplicate/vintage checks and reproducible hashes.
- G02.5 `PENDING`: tests for suspended stocks, missing bars, insufficient warm-up, holidays, delisting and stale news.
- Acceptance: every feature is available by decision time; outcomes are excluded from inference; split manifests reproducible; all leakage and label tests pass. Unresolved source coverage/licensing gaps block the affected dataset, not silently disappear.
- Dependencies: G01 data evidence; source permissions. Window: D6–D20. Owner: data/implementation role.

### G03 — Numerical 20-session swing predictor

- G03.1 `DESIGNED`: compare no-action/current deterministic baseline with a simple linear learner and a bounded small tree-model search; no guaranteed winner.
- G03.2 `PENDING`: fit numerical models on training data only; record parameters, feature versions, seeds, cost assumptions and rejected experiments.
- G03.3 `PENDING`: rolling validation, calibration where probabilities are emitted, cost sensitivity, date-grouped uncertainty and stability by sector/regime.
- G03.4 `PENDING`: untouched final test; inference parity check; versioned model promotion/rollback and stale-input abstention.
- G03.5 `PENDING`: compare AI-assisted decisions against Java-only decisions using the same dates, universe, costs and risk limits.
- Acceptance: pre-register the primary out-of-sample metric and minimum effect before opening final test results; assess drawdown, turnover and uncertainty as well as return. If the edge is inconclusive or negative, retain the baseline and mark this goal unaccepted. A valid JSON response or Java agreement is not predictive evidence.
- Dependencies: G02; cannot train first and fix leakage afterward. Window: D11–D30. Owner: numerical-model/implementation role.

### G04 — Upstox live feed

- G04.1 `DESIGNED`: streaming adapter, instrument mapping, connection lifecycle and event/receipt timestamps; E12.
- G04.2 `PENDING`: bounded queue, reconnect/backoff, gap detection, deduplication and persisted minute bars.
- G04.3 `PENDING`: freshness/source-health rules; halt affected decisions on stale or incomplete input; controlled historical backfill.
- G04.4 `PENDING`: replay and market-hours load test for subscribed Nifty 500 coverage within actual account limits.
- Acceptance: supported subscription limits are recorded; simulated disconnects cannot silently produce fresh-looking signals; measured queue lag, dropped events, bar completeness and reconnect times satisfy frozen operational limits. No assumption that every symbol receives a tick every second.
- Dependencies: G01 identity/auth evidence; streaming entitlement. Window: D16–D30. Owner: provider/implementation role.

### G05 — Paytm live data only

- G05.1 `PARTIAL`: historical price-chart client exists; this is not live-data or order integration; E05.
- G05.2 `PENDING`: obtain current official account-specific auth, market-feed contract, exchange entitlement, rate limits and static-egress requirements; no secrets in documentation.
- G05.3 `DESIGNED`: normalized read-only adapter, source provenance, explicit preference/failover policy and divergence alarms.
- G05.4 `PENDING`: test expiration, reconnect, throttling, permissions, duplicate/missing data and cross-provider consistency.
- Acceptance: bounded live-data checks pass and failure cannot trigger broker orders; read-only credentials/permissions used where supported; no create/modify/cancel-order call path enabled. Missing account/network prerequisites remain an external blocker.
- Dependencies: provider approval/network setup separately authorized; G01 identifiers; G04 shared feed contract. Window: access work D1 onward, implementation D26–D35 if ready. Owner: owner for access, engineer for integration.

### G06 — Marketaux and company events

- G06.1 `PARTIAL`: connector, ingestion audit and permission-related tables exist; E06.
- G06.2 `PENDING`: durable company/ISIN mapping, ambiguous-match rejection, first-seen versus publication times, clustering and revisions.
- G06.3 `PENDING`: enforce actual daily quotas, network timeouts, backoff, scheduling and licensed retention/deletion.
- G06.4 `DESIGNED`: optional small-model structured extraction with article evidence, bounded enums, uncertainty and adversarial-input tests; model cannot issue executable commands.
- G06.5 `PENDING`: news-triggered reassessment of eligible companies; event features and historical availability tests.
- Acceptance: labelled entity/event evaluation and error categories documented; no ambiguous entity silently routes a trade proposal; duplicate news does not duplicate proposals; no future news enters historical features. Degrade explicitly to a no-news baseline when permitted, otherwise abstain.
- Dependencies: source entitlement and G02/G04 input contracts. Window: D6–D35 alongside provider waiting periods. Owner: data/implementation role; owner confirms subscription rights.

### G07 — Additional horizons and intraday

- G07.1 `DESIGNED`: separate 5/10-session and 30/60-minute labels, calibration and decision policies; 20-session model is not reused as an intraday predictor without validation.
- G07.2 `PENDING`: obtain sufficient point-in-time intraday history with spread/volume/session constraints; new 10-session label support.
- G07.3 `PENDING`: horizon-specific chronological validation and no-news versus news-feature ablation.
- G07.4 `PENDING`: session-close handling, position-horizon conflicts and bounded inference scheduling.
- Acceptance: each advertised horizon independently meets G03-style evidence requirements. Insufficient intraday history blocks that mode. Disabled modes must be visibly disabled in the portal.
- Dependencies: G02/G03 validation framework; G04, G06 for full live/news-enabled scope. Window: D26–D45, possibly contingency. Owner: numerical-model/implementation role.

### G08 — Paper accounting and execution

- G08.1 `PARTIAL`: seed for INR 100,000 portfolio plus order/fill tables exist; no complete simulator demonstrated; E07.
- G08.2 `DESIGNED`: one shared cash ledger, reservations, positions, fees, realised/unrealised P&L and audit trail; intraday/swing cannot each spend the same capital.
- G08.3 `PENDING`: lifecycle, idempotency, fresh-price revalidation, partial fills, cancellation/expiry and conservative fill assumptions.
- G08.4 `PENDING`: corporate actions, settlement assumptions, restart/reconciliation, property tests and concurrent-approval tests.
- Acceptance: paise-level ledger reconciliation, no negative available cash/overselling, one approval cannot create duplicate fills, crash replay preserves balances. Real broker order placement remains absent/disabled by construction.
- Dependencies: approved risk/fill contracts; G01 for fixtures, G04/G05 for final runtime tests. Window: D6–D25. Owner: backend/implementation role.

### G09 — Portal and human decision workflow

- G09.1 `PARTIAL`: static React dashboard and Telegram/WhatsApp foundations exist; E08.
- G09.2 `DESIGNED`: screens in [system design](system-design.md), clear PAPER badge and INR 100,000 initial account.
- G09.3 `PENDING`: authenticated APIs/UI, evidence view, approvals, order/position history and integration health.
- G09.4 `PENDING`: Java-templated alerts; one-time expiring approvals shared across portal/Telegram; WhatsApp optional and non-blocking.
- G09.5 `PENDING`: accessible error states, stale-price expiry, duplicate-click tests, no accidental live controls and compact report export.
- Acceptance: end-to-end proposal → human approval → price/risk revalidation → paper fill → ledger → report passes; expired/out-of-zone approval cannot buy. UI never presents a score as a guaranteed outcome.
- Dependencies: G08 contract; real predictions require G03/G07. Window: design D1–D5; implementation D11–D35. Owner: frontend/backend role; owner acceptance.

### G10 — Release hardening

- G10.1 `DESIGNED`: access, secret handling, audit, backup/restore and review-only execution boundary.
- G10.2 `PENDING`: tests for source outages, stale data, bad model output, approval races, disk full, power loss and restart.
- G10.3 `PENDING`: deployment revision/config evidence, dependency/security checks, health/readiness distinction and bounded load test.
- G10.4 `PENDING`: record response-time distributions, capacity and rejected/dropped work; rollback and runbook drill.
- Acceptance: no unresolved critical safety/security defect; restore test passes; one compact daily evidence bundle; all advertised workflows meet a written measured latency/capacity budget. Hardware capacity is measured, not assumed.
- Dependencies: G01–G09 integrated scope. Window: D36–D45, with tests added throughout. Owner: implementation/operator role.

### G11 — Prospective paper validation

- G11.1 `DESIGNED`: frozen model/policy versions, cash balance, benchmark, metrics and cohort dates before starting.
- G11.2 `PENDING`: at least **30 elapsed calendar days AND 20 actual exchange trading sessions**, whichever takes longer, with daily completeness checks.
- G11.3 `PENDING`: record all eligible proposals, approvals/rejections, abstentions, fills, costs, incidents and matched baseline outcomes—not just winners.
- G11.4 `PENDING`: obtain sufficient opportunities across declared modes; suggested operational floor of 20 decision dates per horizon and 10 closed paper trades overall requires owner approval and is **not** statistical proof. Extend observation if evidence is sparse; never manufacture trades to meet a quota.
- G11.5 `PENDING`: wait for the final predictions' horizon labels to mature; review uncertainty, risk, accounting and operating reliability; owner accepts, extends or rejects.
- Acceptance: data/audit continuity and reconciliation pass; no critical safety violation; predeclared model criteria pass on prospective evidence. A model with uncertain benefit remains advisory/disabled. Real money is still a separate decision under G12.
- Dependencies: accepted, advertised G01–G10 scope and owner trial-start approval. Material changes open a new cohort and restart affected stability measurements; preserve old failures.

### G12 — Future Paytm execution, deliberately deferred

- G12.1 `PENDING`: separate feasibility, account permissions, policy/compliance and operational review.
- G12.2 `PENDING`: separately authorized design for create/modify/cancel orders, broker reconciliation, protective actions and kill switches.
- G12.3 `PENDING`: staged limits and independent go/no-go review after G11; passing a paper month is necessary evidence, not sufficient proof of live performance.
- No implementation date, current release weight or permission to place real orders. The portal must not gain live execution through a simple configuration toggle.

## Parallel work and sequential gates

| Can progress concurrently when capacity permits | Must wait |
|---|---|
| G01 evidence, G05 provider/access questions, G09 wireframes, G06 licence review | No model acceptance before G02 data validation |
| G08 simulator using fixtures and G02 historical dataset | No paper fill integration before accounting/risk contracts |
| G04 feed adapter and G03 offline modelling | No live inference claim before feed freshness/recovery tests |
| G06 news pipeline and G09 portal against versioned contracts | No full multi-horizon acceptance before G07 validation |
| Daily documentation and tests alongside all authorized work | No G11 clock before integrated trial-entry gate; no G12 from paper results alone |

Roles are work lanes, **not an assumption of multiple developers**. With one engineer, parallel-ready tasks are interleaved; provider waiting and data collection can overlap. Model inference stays concurrency 1. No uncontrolled permutation loop or unbounded experiment search.

## Conditional timeline and daily cadence

Planning estimate: **45–60 engineering working days**, then the observation window and label maturation. This is a scope forecast, not a completion guarantee. It assumes one sustained implementation lane, accessible historical/intraday data, timely owner decisions and provider access. Establish measured velocity after the first five days and revise the forecast transparently.

If implementation is authorized for Monday **2026-09-21**:

| Working-day window | Illustrative weekdays, before local holidays | Deliverable/review |
|---|---|---|
| D1–D5 | Sep 21–25 | Evidence, source-review inventory, contracts, risk proposals and test fixtures |
| D6–D15 | Sep 28–Oct 9 | Dataset and paper-account foundations; portal contracts |
| D16–D25 | Oct 12–23 | Numerical baseline validation, live-feed work, paper lifecycle |
| D26–D35 | Oct 26–Nov 6 | Paytm data, news, portal integration and additional horizons |
| D36–D45 | Nov 9–20 | Integrated recovery/security/performance and trial-entry decision |
| D46–D60, if needed | Nov 23–Dec 11 | Explicit contingency for defects, data or integration gaps |

These are sequential total-capacity windows, not a promise to finish every overlapping goal independently in that time. Weekends, holidays, provider delays and limited work hours change dates. A best-case Nov 23 trial start reaches 30 elapsed days on Dec 23; exchange-session requirements may push it later. Final 20-session predictions need a further 20 trading sessions to mature, potentially into January 2027. No live-trading launch date is promised.

Daily routine on days worked:

1. Select bounded subitems and expected acceptance evidence before coding; record blockers and the single active implementation lane.
2. Implement only authorized scope; run relevant offline tests. Runtime/model work runs on the spare laptop.
3. Record actual results, timings and failures in [daily progress](daily-progress.md). Update only evidence-earned checkpoints here.
4. Commit/push verified scoped work with relevant docs and the current diagram when changed; give a safe spare-laptop script for that milestone.
5. Re-estimate weekly from completed subitems and unresolved dependencies. Do not turn a deadline into permission to lower quality gates.

Next decision: approve this baseline, proposed risk/fill rules and the initial G00/G01/G02/G08/G09 work slice. **Documentation approval does not silently authorize all future implementation or any broker transaction.**
