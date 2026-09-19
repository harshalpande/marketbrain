# Roadmap and completion dashboard

Baseline: MB-PLAN-2026-09-18-V2. Authority: [documentation index](README.md). Evidence: [register](evidence-register.md). Daily changes: [progress log](daily-progress.md). PG1 is the complete intelligence/eventual live product; PG2 is its mandatory paper-first deployment. Goal IDs remain stable when scope is corrected.

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

The revised paper-first baseline is **12.4% engineering delivery**: `(8 × 40 + 92 × 10) / 100`. This replaces V1's 13% because history, fundamentals and governed learning now have explicit weights; **the -0.6 percentage-point change is scope rebaselining, not lost implementation or worse model performance**. Weights are declared planning weights, not measured effort or accuracy. G01 retains its narrowly scoped implementation-presence checkpoint; the other included goals have design credit only. No V/R/A delivery checkpoints are claimed. Owner agreement with the scope is not acceptance of an implemented feature.

This denominator covers the full paper-first target, including shared PG1 foundations, not the future live release. G12 remains separately tracked at 0%; do not call 100% of this dashboard 100% of PG1. **Live-order readiness is not approved; numerical predictive performance is unmeasured.**

| Goal | Scope | Weight | Checkpoints | Completion | Area status / pending work |
|---|---|---:|---|---:|---|
| G01 | Verify existing Upstox REST and historical/daily pipeline | 8 | D, I | 40% | Implemented foundation; refresh tests, runtime and data-coverage evidence |
| G02 | Point-in-time, multi-date prediction dataset | 8 | D | 10% | Prototype datasets exist; executable labels, vintage data and leakage controls pending |
| G03 | Numerical 20-session swing predictor | 12 | D | 10% | Design only; no fitted/calibrated predictor established |
| G04 | Upstox streaming and live aggregation | 7 | D | 10% | REST is not streaming; streaming implementation pending |
| G05 | Paytm live market data, read-only | 5 | D | 10% | Historical client exists; current live API/auth/entitlement verification and integration pending |
| G06 | Governed Marketaux ingestion and news features | 5 | D | 10% | Ingestion foundations exist; reliable entity/event pipeline pending |
| G07 | Required 5/60-session swing and separate intraday prediction | 8 | D | 10% | With G03 covers 5/20/60 sessions; 10 sessions optional, intraday initially 30/60 minutes |
| G08 | INR 100,000 paper account, orders and fills | 9 | D | 10% | SQL foundations exist; complete accounting/execution simulator pending |
| G09 | Functional portal, approval and notifications | 8 | D | 10% | Static UI and notification foundations; end-to-end paper workflow pending |
| G10 | Integrated security, operations and recovery | 5 | D | 10% | Existing safeguards to reuse; full release verification pending |
| G11 | Prospective month-plus paper validation | 8 | D | 10% | Trial protocol designed; final 60-session outcomes need additional maturation |
| G12 | Paytm real order execution | Excluded | None | 0% | Deferred; separate authorization and release decision required |
| G13 | 15+ year history target and frequency-specific coverage | 7 | D | 10% | Dedicated acquisition/licensing/membership/retention plan; actual coverage unverified |
| G14 | Point-in-time fundamental intelligence | 5 | D | 10% | Financial-statement, valuation and earnings features designed; implementation not established |
| G15 | Feedback, outcome learning and controlled retraining | 5 | D | 10% | Preference/outcome separation, challenger evaluation and promotion/rollback designed |

G00, the documentation/evidence-reset task, is tracked separately: **4/5 checkpoints (80%)** — inventory mapped, canonical plan written, evidence/uncertainty register written, and owner acceptance of the parent scope/clarifications recorded. Exhaustive source-review coverage remains pending. This does not approve detailed risk defaults, implementation or live trading. A broad repository scan is not a certified line-by-line audit.

## Parent-goal traceability

| Accepted requirement | Owning subgoals | Acceptance evidence |
|---|---|---|
| PG1: 15+ years, all eligible Nifty 500 companies | G13.1–G13.5, G01, G02 | Frequency-specific licensed coverage matrix; listing/membership history and explicit gaps |
| PG1: technical, quantitative, fundamental and news analysis | G02/G03, G06, G14.1–G14.5 | Point-in-time features, numerical validation and source-specific ablation |
| PG1: 5/20/60-session research/forecasts plus intraday | G03, G07.1–G07.5 | Separate lookback/forecast fields; independently validated horizons |
| PG1: autonomous analysis with Telegram ACCEPT/REJECT | G04/G05, G09.4, G09.6 | Scheduled/event-driven proposals; acceptance cannot bypass fresh risk/price checks |
| PG1: feedback and outcome learning | G15.1–G15.5 | Auditable feedback/outcomes, versioned challenger tests, governed promotion and rollback |
| PG1: eventually execute approved Paytm trades | G12.1–G12.5 | Separately approved live adapter, reconciliation, position monitoring and kill-switch tests |
| PG2: one INR 100,000 realistic paper account | G08.1–G08.6 | Cash/holdings reconciliation; conservative costs/fills; no double-spending |
| PG2: preserve production data/prediction/approval workflow | G08.5, G09.6, G10.5 | Shared contracts and adapter conformance; no broker order calls in paper mode |
| PG2: experimentation and comprehensive simulation | G08.6, G11, G15 | Isolated research simulation, frozen prospective cohorts and matured outcomes |

## Work items and acceptance gates

Legend: `DONE-SOURCE` = found in source, `PARTIAL` = reusable but incomplete for this goal, `DESIGNED` = specified here, `PENDING` = no accepted implementation/evidence. These labels are not additional numerical checkpoints.

The V1 working-day windows below are retained only as **prior core-work sequencing estimates**, not current delivery dates for the expanded V2 scope. The revised evidence-first scheduling gate at the end of this document supersedes the former overall estimate.

### Immediate start package — evidence and environment preflight

G10.6 scoped LLM cleanup is **completed and owner-accepted on 2026-09-18**, evidence E26. Granite removed, Qwen 0.5B quarantined, Qwen 1.5B retained with matching hashes, service health UP. Ollama and llama.cpp retained. Broader runtime/job inventory limitations remain under G10.3; no predictive-performance credit follows from cleanup.

Next: reuse existing Upstox quality evidence (E31) in G02's [numerical baseline work package](numerical-baseline-plan.md). N1 audit and N2 bounded history results are reviewed (E28/E30): 476/500 eligible, 24 insufficient-history. Research-label arithmetic is offline verified (E32); real calendar/price-policy integration, contract freeze and multi-date export remain pending. No repeat acquisition, provider validation sweep, model download or training is requested. Supporting components do not earn completion of the full prediction-grade dataset: weighted baseline remains 12.4%.

| First work lane | Bounded output | Boundary |
|---|---|---|
| Environment preflight: G10.6 | Completed: reviewed inventories, confirmed scoped cleanup and verification | No further removal; quarantine/report retained for recovery |
| Data readiness: G01/G13/G14 | Current revision, provider access and coverage matrix; identify usable historical data and fundamental-source gaps | Reuse saved reports first; bounded queries only after review; no broad backfill yet |
| First implementation design: G02/G08/G09 | 20-session feature/label contract plus INR 100,000 ledger/approval contract and portal wireframes | No application implementation until the owner approves the bounded slice; no live orders |

After evidence/contract approval, the proposed first build is the prediction-grade 20-session dataset and deterministic paper-account foundation. These are independent work lanes with a shared contract. Numerical baseline training follows dataset validation; required 5/60-session and intraday expansion follows separate evidence gates. LLM prompt tuning is not the critical path for this numerical engine.

### G01 — Existing Upstox REST and daily foundation

- G01.1 `DONE-SOURCE`: instrument import, quotes, historical/intraday candle import and corporate-action access; evidence E02.
- G01.2 `DONE-SOURCE`: persisted historical backfill, daily enrichment, technical snapshots; E03.
- G01.3 `PENDING`: verify tests at an identified revision, authentication, entitlement, canonical instrument mapping and current deployment configuration without exposing credentials.
- G01.4 `PENDING`: collect actual Nifty 500 coverage, missing sessions, duplicates, corporate-action adjustments, source priority, recovery and backup/restore evidence.
- Acceptance: all declared operations pass contract tests and a bounded spare-laptop check; coverage report explicitly lists unavailable symbols/dates; no claim of second-by-second streaming from REST. A data-readiness threshold is frozen before G02 acceptance; critical missing features cause exclusion, never silent imputation.
- Dependencies: G00 scope/evidence approval. Proposed window: D1–D10. Responsible roles: implementation engineer; owner supplies account/access evidence and accepts.

### G02 — Prediction-grade dataset

- G02.1 `PARTIAL`: prototype immutable runs and 5/20/60-session outcome labels exist; E04.
- G02.2 `PARTIAL`: history/features/calendar/quality linkage and outcome paths verified within scope; E47 confirms the 38-date export on spare. E50 verifies repair capture in 8.828s with four reviewed job links but no scoped adjustment references. E51 expands **uncertified** research arithmetic to 150 dates/600 rows offline, with previous values unchanged; spare export pending. No new acquisition or gate relaxation. Price/availability/universe policy, certified export, valid frozen folds and a genuinely untouched evaluation set remain pending. No training authorization or overall percentage increase from preparatory slices. Conditional engineering estimate remains in the numerical plan; full platform/paper observation separate.
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

- G07.1 `DESIGNED`: required 5/60-session models alongside G03's 20-session model, plus separate 30/60-minute intraday labels, calibration and policies. Ten-session forecasting is optional, not a substitute for 60 sessions.
- G07.2 `PENDING`: validate executable 5/60-session labels and obtain sufficient point-in-time intraday history with spread/volume/session constraints; existing prototype labels do not establish valid forecasting models.
- G07.3 `PENDING`: horizon-specific chronological validation and no-news versus news-feature ablation.
- G07.4 `PENDING`: session-close handling, position-horizon conflicts and bounded inference scheduling.
- G07.5 `DESIGNED`: distinguish historical lookback (including 5/20/60-session diagnostics) from forward forecast horizon; test each combination without future information. HOLD produces no order; unreliable evidence permits NO_TRADE/ABSTAIN.
- Acceptance: each advertised horizon independently meets G03-style evidence requirements. Insufficient intraday history blocks that mode. Disabled modes must be visibly disabled in the portal.
- Dependencies: G02/G03 validation framework; G04, G06 for full live/news-enabled scope. Window: D26–D45, possibly contingency. Owner: numerical-model/implementation role.

### G08 — Paper accounting and execution

- G08.1 `PARTIAL`: seed for INR 100,000 portfolio plus order/fill tables exist; no complete simulator demonstrated; E07.
- G08.2 `DESIGNED`: one shared cash ledger, reservations, positions, fees, realised/unrealised P&L and audit trail; intraday/swing cannot each spend the same capital.
- G08.3 `PENDING`: lifecycle, idempotency, fresh-price revalidation, partial fills, cancellation/expiry and conservative fill assumptions.
- G08.4 `PENDING`: corporate actions, settlement assumptions, restart/reconciliation, property tests and concurrent-approval tests.
- G08.5 `DESIGNED`: share data, prediction, proposal, risk, approval and order-intent contracts with the future production workflow; a separately authorized broker adapter will differ from the paper adapter. Require contract conformance, not identical fill outcomes.
- G08.6 `DESIGNED`: isolate the approved INR 100,000 portfolio from research simulation of rejected/unapproved proposals. Never reserve/spend approved-account cash for hypothetical trades; preserve distinct IDs, costs and assumptions.
- Acceptance: paise-level ledger reconciliation, no negative available cash/overselling, one approval cannot create duplicate fills, crash replay preserves balances. Real broker order placement remains absent/disabled by construction.
- Dependencies: approved risk/fill contracts; G01 for fixtures, G04/G05 for final runtime tests. Window: D6–D25. Owner: backend/implementation role.

### G09 — Portal and human decision workflow

- G09.1 `PARTIAL`: static React dashboard and Telegram/WhatsApp foundations exist; E08.
- G09.2 `DESIGNED`: screens in [system design](system-design.md), clear PAPER badge and INR 100,000 initial account.
- G09.3 `PENDING`: authenticated APIs/UI, evidence view, approvals, order/position history and integration health.
- G09.4 `PENDING`: Java-templated alerts with user-facing ACCEPT / REJECT; one-time expiring approvals shared across portal/Telegram; WhatsApp optional and non-blocking. ACCEPT maps to an approval event, not a guaranteed fill.
- G09.5 `PENDING`: accessible error states, stale-price expiry, duplicate-click tests, no accidental live controls and compact report export.
- G09.6 `DESIGNED`: preserve identical proposal/risk/approval semantics for paper and eventual live workflows; explicitly label PAPER versus RESEARCH SIMULATION results. HOLD records an assessment without order execution; accepting a BUY/SELL still allows risk rejection or order expiry.
- Acceptance: end-to-end proposal → human approval → price/risk revalidation → paper fill → ledger → report passes; expired/out-of-zone approval cannot buy. UI never presents a score as a guaranteed outcome.
- Dependencies: G08 contract; real predictions require G03/G07. Window: design D1–D5; implementation D11–D35. Owner: frontend/backend role; owner acceptance.

### G10 — Release hardening

- G10.1 `DESIGNED`: access, secret handling, audit, backup/restore and review-only execution boundary.
- G10.2 `PENDING`: tests for source outages, stale data, bad model output, approval races, disk full, power loss and restart.
- G10.3 `PENDING`: deployment revision/config evidence, dependency/security checks, health/readiness distinction and bounded load test.
- G10.4 `PENDING`: record response-time distributions, capacity and rejected/dropped work; rollback and runbook drill.
- G10.5 `DESIGNED`: shared-contract test suite and denied broker-order-call assertions for the paper release; future live-adapter tests cover partial fills, duplicate acknowledgements, unknown order states and reconciliation separately.
- G10.6 `COMPLETED-SCOPED / OWNER-ACCEPTED`: spare-machine approved LLM cleanup, E22–E26. All five **scoped cleanup** stages are closed; not a complete runtime/job/security audit and not a new weighted product goal:
  - Tooling available: `ops/windows/GetSpareLlmCleanupInventory.ps1`, with offline mocked tests. Run on the spare laptop and review its single JSON before crediting C1; tool implementation alone does not complete the inventory or cleanup.
  - C1 `DONE-SCOPED`: E22 inventories installed tags, known GGUF paths/sizes, processes and hardware counters; unavailable file versions/usable VRAM are explicitly unknown, not invented.
  - C2 `DONE-SCOPED`: source references/defaults reviewed, E24 runtime hints inspected, E26 records operator confirmation of idle/dependency conditions. Not independent proof of no queued Java job; partial scan and stale RUNNING evidence remain preserved.
  - C3 `DONE`: exact targets/recovery boundaries confirmed interactively (`operatorConfirmed=true`) and owner accepted the cleanup report in chat. No uninstall/process-stop authorization was used.
  - C4 `DONE`: digest-matched Granite removed via Ollama API; one Qwen 0.5B GGUF moved to verified same-volume quarantine; no recursive/shared-cache deletion.
  - C5 `DONE-SCOPED`: after list empty, 1.5B SHA256 unchanged, health UP, observed C: free-space increase 5,347,913,728 bytes. Quarantine recoverable; Granite restoration needs download. No inference or independent proof of all job/service health.
- Residual operational gaps move forward explicitly under G10.3: executable build provenance, actual usable VRAM, complete job/scheduler/deployed-config inventory and restart reconciliation. Owner acceptance closes **the scoped cleanup**, not those gaps. Keep quarantine/evidence; do not rerun removal. Cleanup does not earn G10's full I/V/R/A checkpoints or change the 12.4% weighted project baseline.
- Acceptance: no unresolved critical safety/security defect; restore test passes; one compact daily evidence bundle; all advertised workflows meet a written measured latency/capacity budget. Hardware capacity is measured, not assumed.
- Dependencies: G01–G09 plus G13–G15 for the full advertised paper scope. Prior core window: D36–D45, with tests throughout; revised dates follow the V2 scheduling gate. Owner: implementation/operator role.

### G11 — Prospective paper validation

- G11.1 `DESIGNED`: frozen model/policy versions, cash balance, benchmark, metrics and cohort dates before starting.
- G11.2 `PENDING`: at least **30 elapsed calendar days AND 20 actual exchange trading sessions**, whichever takes longer, with daily completeness checks.
- G11.3 `PENDING`: record all eligible proposals, approvals/rejections, abstentions, fills, costs, incidents and matched baseline outcomes—not just winners.
- G11.4 `PENDING`: obtain sufficient opportunities across declared modes; suggested operational floor of 20 decision dates per horizon and 10 closed paper trades overall requires owner approval and is **not** statistical proof. Extend observation if evidence is sparse; never manufacture trades to meet a quota.
- G11.5 `PENDING`: wait for every advertised horizon's final labels to mature, including the full 60-session forecast window; review uncertainty, risk, accounting and operating reliability; owner accepts, extends or rejects. A month of operation does not complete 60-session validation.
- Acceptance: data/audit continuity and reconciliation pass; no critical safety violation; predeclared model criteria pass on prospective evidence. A model with uncertain benefit remains advisory/disabled. Real money is still a separate decision under G12.
- Dependencies: accepted, advertised G01–G10 and G13–G15 scope, plus owner trial-start approval. An explicitly restricted pilot is possible but is not full G11 acceptance. Material changes open a new cohort and restart affected stability measurements; preserve old failures.

### G12 — Future Paytm execution, deliberately deferred

- G12.1 `PENDING`: separate feasibility, account permissions, policy/compliance and operational review.
- G12.2 `PENDING`: separately authorized design for create/modify/cancel orders, broker reconciliation, protective actions and kill switches.
- G12.3 `PENDING`: staged limits and independent go/no-go review after G11; passing a paper month is necessary evidence, not sufficient proof of live performance.
- G12.4 `PENDING`: broker acknowledgement/partial-fill/timeout/unknown-state reconciliation, idempotency, cancellation and manual recovery; never resend an uncertain order blindly.
- G12.5 `PENDING`: monitor actual positions and holdings after fills; refresh risk/exits, reconcile broker state and audit protective actions. Human approval or an explicitly preapproved protective rule remains authoritative, not model autonomy.
- No implementation date, current release weight or permission to place real orders. The portal must not gain live execution through a simple configuration toggle.

### G13 — 15+ year historical-data target

- G13.1 `DESIGNED`: inventory each required series by instrument, date range, frequency, provider, licence, publication/vintage availability and missing intervals. Separate daily, minute/tick, fundamentals and news coverage; do not assume one entitlement supplies all four.
- G13.2 `PENDING`: verify/acquire at least 15 years of daily price/volume history where the instrument existed and licensed sources permit, or since listing for newer companies. Exceptions require visible owner acceptance; unavailable data is not fabricated.
- G13.3 `PENDING`: version Nifty 500 membership over time, symbol/ISIN changes, delistings and corporate actions. Distinguish today's 500-company backfill from historical-universe evaluation.
- G13.4 `PENDING`: resumable bounded ingestion, reconciled gaps and revised data, immutable provenance, storage/retention and backup capacity; preserve raw versus adjusted values.
- G13.5 `PENDING`: publish frequency-specific coverage and quality dashboards, including intraday/news/fundamental limitations. Freeze required depth and tolerable gaps per mode before accepting it.
- Acceptance: audited coverage matrix and recovery test; missing or unlicensed series prevent full-coverage claims. A limited dataset may support an explicitly limited pilot, not completion of this goal.
- Dependencies: G01, source access and approved storage/licence budgets; informs G02/G07/G14. Owner: data engineer plus owner for entitlements. Timeline: feasibility during the first five authorized working days; acquisition ETA only after volume/rate-limit evidence.

### G14 — Point-in-time fundamental intelligence

- G14.1 `DESIGNED`: select authorized sources for financial statements, earnings, balance-sheet/cash-flow quality, valuation inputs and share counts; record separate historical depth/rights.
- G14.2 `PENDING`: normalize standalone/consolidated statements, reporting periods, currencies/units and company identifiers with provenance.
- G14.3 `PENDING`: preserve original publication/first-seen times, amendments and restatements; calculations use only the version available at prediction time.
- G14.4 `PENDING`: calculate versioned growth, profitability, leverage, cash-flow and valuation features; explicit stale/missing/sector-specific applicability rules.
- G14.5 `PENDING`: test ratio arithmetic and temporal joins, then compare numerical models with/without fundamentals on the same held-out dates and costs.
- Acceptance: no restatement leakage, validated calculations and coverage; inclusion in active prediction requires evidence of value, not merely successful ingestion. Report unsupported sectors/fields explicitly.
- Dependencies: G13 source feasibility, G02 identity/time contracts and G03 validation framework. Owner: data/numerical-model role. Timeline: source decision at the first scheduling gate; implementation estimate after sample-data review.

### G15 — Feedback, outcomes and controlled learning

- G15.1 `DESIGNED`: persist ACCEPT/REJECT/expiry and optional reasons separately from market outcome labels, forecast quality and execution quality. User preference is not proof of predictive correctness.
- G15.2 `PENDING`: attribute outcomes at each forecast horizon; track approved paper trades, hypothetical research trades and eventual real trades as distinct populations; include rejected/abstained opportunities where evaluation is defined.
- G15.3 `PENDING`: monitor drift, calibration, coverage and cost-adjusted performance; predefine cadence/triggers and minimum data before retraining. Never retrain on immature future labels.
- G15.4 `PENDING`: produce versioned challengers through bounded training/validation; predeclared improvement and risk gates, explicit promotion, frozen trial cohorts and rollback. An inconclusive challenger retains the incumbent.
- G15.5 `PENDING`: test corrupt feedback, duplicate outcomes, source corrections, regime shifts and rollback; audit why every model version was accepted or rejected.
- Acceptance: reproducible end-to-end feedback-to-challenger workflow, no preference/outcome conflation or active-model mutation during a frozen trial; no promise that every retraining cycle improves results.
- Dependencies: G03/G07 forecast contracts and mature outcomes, G08/G09 audit records; collect feedback early, promote only after validation. Owner: numerical-model/implementation role with owner promotion authority. Timeline: instrumentation alongside portal work, first retraining gate after sufficient mature data; no fixed improvement date.

## Parallel work and sequential gates

| Can progress concurrently when capacity permits | Must wait |
|---|---|
| G01 evidence, G05 provider/access questions, G09 wireframes, G06 licence review | No model acceptance before G02 data validation |
| G08 simulator using fixtures and G02 historical dataset | No paper fill integration before accounting/risk contracts |
| G04 feed adapter and G03 offline modelling | No live inference claim before feed freshness/recovery tests |
| G06 news pipeline and G09 portal against versioned contracts | No full multi-horizon acceptance before G07 validation |
| G13 coverage/licensing and G14 source samples alongside G08/G09 fixture work | No 15-year/fundamental completeness claim before audited coverage |
| G15 feedback instrumentation alongside portal implementation | No challenger promotion before mature outcomes and untouched validation |
| Daily documentation and tests alongside all authorized work | No G11 clock before integrated trial-entry gate; no G12 from paper results alone |

Roles are work lanes, **not an assumption of multiple developers**. With one engineer, parallel-ready tasks are interleaved; provider waiting and data collection can overlap. Model inference stays concurrency 1. No uncontrolled permutation loop or unbounded experiment search.

## Conditional timeline and daily cadence

**The former 45–60-working-day estimate and illustrative calendar dates are withdrawn for the expanded V2 scope.** Adding 15-year acquisition, fundamentals, 60-session validation and controlled learning requires data/access and capacity evidence before a credible replacement estimate. This is a scheduling reassessment, not an assertion that the work is impossible or already underway.

After explicit implementation authorization, use this first-five-working-day planning timebox (one engineering lane, no assumed extra staffing):

| Day | Bounded output | Owner/dependency |
|---|---|---|
| D1 | G10.6 read-only LLM/runtime inventory and dependency/cleanup proposal; deployed/source revision, review-coverage inventory and existing data reports | Engineer; owner runs bounded spare checks and approves exact cleanup targets before changes |
| D2 | G13 coverage/licensing/storage matrix and data-acquisition questions | Engineer; owner/provider for entitlement answers |
| D3 | G14 sample/source assessment; required 5/20/60-session and intraday contracts | Engineer; source samples/access may remain blocked |
| D4 | G08/G09/G15 shared order, approval, research-account and learning contracts | Engineer; owner reviews unresolved business rules |
| D5 | Publish revised goal-by-goal estimates, parallel dependencies, contingency and trial-entry forecast | Engineer and owner; unresolved external gaps remain explicit |

D5 is the deadline to **publish what is known and blocked**, not a guarantee that providers answered or the exhaustive audit finished. On D10 review actual velocity and update the forecast again. Unanswered external dependencies get owner/next-review dates, not invented completion dates. Detailed risk defaults and the implementation slice still require approval.

After the trial-entry gate, observation lasts at least 30 elapsed calendar days and 20 actual exchange sessions, whichever is longer. Each final prediction still needs its own outcome window: a final 60-session prediction needs 60 trading sessions from its defined entry, not 60 calendar days. Operational trial completion and complete multi-horizon validation are separate milestones. No live launch or guaranteed model-improvement date is promised.

Daily routine on days worked:

1. Select bounded subitems and expected acceptance evidence before coding; record blockers and the single active implementation lane.
2. Implement only authorized scope; run relevant offline tests. Runtime/model work runs on the spare laptop.
3. Record actual results, timings and failures in [daily progress](daily-progress.md). Update only evidence-earned checkpoints here.
4. Commit/push verified scoped work with relevant docs and the current diagram when changed; give a safe spare-laptop script for that milestone.
5. Re-estimate weekly from completed subitems and unresolved dependencies. Do not turn a deadline into permission to lower quality gates.

Next decision: approve detailed risk/fill rules and the initial evidence/implementation work slice including G13/G14 feasibility. The owner has accepted the parent goals and alignment clarifications. **That documentation approval does not silently authorize application implementation or any broker transaction.**
