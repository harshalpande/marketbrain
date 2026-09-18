# MarketBrain: canonical project baseline

Version: **MB-PLAN-2026-09-18-V1**. Owner/acceptance authority: Harshal. Status: documentation and design baseline; implementation sequencing and proposed risk thresholds require owner review.

## Agreed product goal

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
9. Code changes are not authorized by this documentation reset. The six untracked `news/watch` draft files are excluded from the delivered baseline and must be explicitly disposed of or reviewed before a development-machine build.

## First action, not another model sweep

Close G00's evidence and owner-review gaps, verify the existing Upstox/data foundation, then create the versioned multi-date dataset for the first 20-session numerical predictor. Portal design and provider-access evidence can progress in parallel. Keep existing diagnostic evidence, but do not confuse prompt optimization with model fitting.
