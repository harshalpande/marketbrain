# MarketBrain: canonical project baseline

Version: **MB-PLAN-2026-09-18-V2**. Owner/acceptance authority: Harshal. Status: owner accepted the two parent goals and alignment clarifications; this revision records them. Application implementation, detailed risk thresholds and live execution still require their respective approvals.

## Agreed parent goals

### PG1 — AI-powered trading intelligence and eventual approved execution

Maintain a 15+ year historical-data target and live data for Nifty 500 research, with technical, fundamental, quantitative and news-driven analysis. Use validated numerical forecasts and controlled learning from feedback and market outcomes to produce BUY/SELL/HOLD recommendations. Required multi-session forecasts and historical evaluations are **5/20/60 trading sessions**; intraday has separate within-session horizons. Telegram offers **ACCEPT / REJECT**. Ultimately, an accepted proposal may be executed through Paytm Money only after fresh risk/price validation and a separately authorized live release. Autonomous analysis does not mean unapproved trading; improvement is measured, never guaranteed.

The history target is subject to listing dates, historical constituent membership, source licensing and actual coverage at each data frequency. Missing history is reported, not fabricated. Detailed scope and acceptance are in G13–G15 and the system design.

### PG2 — Paper trading and simulation as the first deployment

Build a comprehensive portal with **one INR 100,000 virtual account**, sharing the intended production data, prediction, alert, human-approval and order contracts. Accepted and revalidated BUY/SELL proposals execute only in the paper engine. HOLD is recorded without an order. A separate research simulation evaluates unapproved/rejected proposals without touching the approved account. Exercise strategy validation, feature experiments, reporting, feedback and controlled model refinement here before considering any Paytm live execution.

PG2 is PG1's mandatory first deployment and validation environment, not a simplified independent application. The execution adapter differs; human approval, risk and audit requirements do not.

### Shared scope and constraints

Combine historical data, current/live prices and Marketaux news for Nifty 500 research. Java prepares facts and enforces risk; a numerical model estimates future outcomes; a small language model may extract news facts. Separate intraday and swing assessments become understandable proposals. The owner approves or rejects them. **Initially every accepted order and fill stays inside our paper portal, backed by one INR 100,000 virtual account. No order is posted to Paytm Money.**

Upstox is an existing primary data integration, not a pending discovery. Paytm live-data integration is a separate required track. Paytm live order execution is a later, separately authorized goal, after at least one month of meaningful paper operation and evidence review. A profitable month alone is not permission for live trading.

## Document authority

| Document | Owns |
| --- | --- |
| [Roadmap](roadmap.md) | Goal/subtask IDs, progress calculation, dependencies, milestones, conditional timeline and release gates |
| [System design](system-design.md) | Java/model responsibilities, provider boundaries, predictor contracts, portal behaviour and safety |
| [Evidence register](evidence-register.md) | What is observed, only reported, unknown or missing; how to verify it safely |
| [Daily progress](daily-progress.md) | Append-only daily outcomes, changes in percentages, blockers, decisions and next actions |
| [Architecture](marketbrain-architecture.svg) | One current target diagram with existing/planned/deferred boundaries |
| [Archive](archive/2026-09-18/INDEX.md) | Superseded history only; never an active command or acceptance authority |

Use the roadmap as the only progress ledger and system-design safety rules as the execution boundary. Never interpret a plan as permission to change credentials, infrastructure, broker settings or live-order behaviour. Discuss unclear scope before implementation. Add a dated decision when scope changes; do not silently rewrite old evidence.

## Operating rules

1. Existing data, raw model outputs and failed experiments are retained subject to source licences and privacy limits. Do not reset results to improve scores.
2. Completion means evidence-backed delivery checkpoints, not prediction confidence, probability of profit, time consumed or lines of code.
3. Keep implemented, test-verified, spare-laptop-verified and owner-accepted states distinct. Unknown means unknown.
4. Before coding a goal, freeze its input/output contract, test plan, safety constraints and acceptance criteria.
5. Human review latency, approximately two minutes, belongs in execution simulation and fresh-price revalidation.
6. Single local LLM inference concurrency remains 1. Async Java work must not cause unbounded model queues or stale decisions.
7. Authorized implementation handoffs include offline verification, scoped commit/push and a complete spare-laptop PowerShell script. Never stage unrelated changes or secrets. Documentation-only changes require no build.
8. At each worked day's end update goal/subtask evidence and the daily log. No unattended daily updating or background implementation is implied; days not worked record no progress when next reviewed.
9. Code changes are not authorized by this documentation update. Inspect the working tree before each build; historical unaccepted drafts are not accepted features (see E10).
10. User ACCEPT/REJECT feedback and realised market outcomes are separate evidence. Retraining creates a challenger; evaluation and explicit promotion precede active-model replacement. Paper and live account outcomes must remain distinguishable.

## First action, not another model sweep

Close G00's remaining source-review coverage gap, verify the existing Upstox/data foundation, and establish G13/G14 data feasibility before claiming full coverage. The first numerical implementation remains a 20-session baseline, followed by required 5/60-session and intraday validation. Portal contracts and provider-access evidence can progress in parallel when authorized. Keep existing diagnostics, but do not confuse prompt optimization with model fitting. The V1 estimate and percentage are superseded as described in the roadmap and daily log.
