# Daily delivery scorecard

Established 2026-10-12 at the owner's request. This scorecard measures delivered scope, not confidence in forecasts or profitability. The [roadmap](roadmap.md) remains authoritative for full-goal progress; [daily progress](daily-progress.md) retains dated evidence.

## Measurement rules

1. Before implementing a bounded work package, freeze its scope, acceptance criteria and five checkpoints: design accepted (10%), implementation complete (30%), offline verification passed (20%), spare-runtime verification passed (20%), owner acceptance (20%). Award each checkpoint only when all its declared criteria are met; otherwise report partial work without its percentage credit. A package can remain at 0% while its design is being prepared.
2. Record the opening percentage, closing percentage and difference in **percentage points**, with evidence references. A rise from 40% to 60% is +20 percentage points, not a claim of 20% better predictions.
3. Keep work-package progress separate from the roadmap's weighted parent-goal checkpoints. Never average packages of unequal scope or transfer a small package's completion to its whole parent area. Publish any scope/weight revision explicitly; do not silently change denominators.
4. Show local verification, spare acceptance, deployment and owner acceptance separately. Include test counts, failures, elapsed time where measured, and side-effect boundaries. Do not sum overlapping regression assertions or describe test pass rate as project completion.
5. Record blockers with an owner/next action. Unknown or unmeasured performance stays unknown, not zero or an invented confidence percentage. No guarantee that a model will become profitable follows from engineering progress.
6. Keep historical evidence dated to the actual run. Recording a previously completed result today does not earn today's runtime gain again.
7. Update the scorecard after each completed work package and provide a consolidated report when the owner asks to log off. This document does not create a background monitoring or scheduled-report job.

## End-of-day format

| Area / bounded package | Opening % | Closing % | Change (pp) | Completed checkpoints / evidence | Pending / blocker / next action |
|---|---:|---:|---:|---|---|
| One row per frozen package | Measured | Measured | Closing minus opening | D / I / V / R / A with references | Specific remaining gate |

Also report: full-roadmap percentage and change; new versus previously accepted tests; measured runtime; deployments; preserved cash/action restrictions; and the next achievable milestone. Estimates and unverified claims must be labelled.

## Opening position: 2026-10-12

- Full paper-first roadmap: **12.4%**, unchanged. This coarse measure excludes the separately gated live-order goal and does not fully describe progress within unfinished parent checkpoints.
- Latest recovery suite: **14/14 checks passed (100% test pass rate)** on October 10; synthetic backup/restore and audit-reader scope only. This is not 100% recovery readiness or today's new work.
- Current application: read-only paper account/ledger and verified approval storage; no activated paper or live execution.
- Proposed next bounded package, restricted approval writer: **0/5 checkpoints, 0%** under this new scorecard. Existing reusable review code is retained; this is not a claim that the entire approval area has no implementation. Freeze detailed permission and acceptance criteria before awarding design credit.
- Other future packages have not yet been baselined here; do not assign them guessed percentages. Numerical predictive performance remains unmeasured.

## Recorded progress on 2026-10-12

| Area / bounded package | Opening % | Current % | Change (pp) | Evidence | Pending |
|---|---:|---:|---:|---|---|
| Approval/security: isolated restricted-writer candidate | 0% | 100% | +100 | D/I/V [E98](evidence/paper-writer-local-20261012.json); R/A [E99](evidence/paper-writer-spare-acceptance-20261012.json), 26/26 spare checks accepted | Candidate closed; application adoption is separate |
| Application adoption: catalog preflight only | 0% | 100% | +100 | D/I/V E100; R/A [E101](evidence/paper-writer-preflight-spare-acceptance-20261012.json), 110.692s spare catalog report and authorized administrator/TEMP review | Closed; installation is separate |
| Application adoption: NOLOGIN permission staging | 0% | 100% | +100 | D/I/V E102/E103; R/A [E104](evidence/paper-writer-install-spare-acceptance-20261012.json) | Closed; usable credentials/application activation excluded |
| Connection security inventory only | 0% | 60% | +60 | D/I/V E105; [frozen scope](paper-writer-connection-review.md) | R/A: spare read-only authentication/cross-database report and findings review |
| Full paper-first roadmap | 12.4% | 12.4% | 0 | Parent checkpoint scope unchanged | Complete integrated parent-goal gates |

The candidate percentage is **not** the completion of the production writer, paper portal, entire approval area or predictor. Its latest change is **60% to 100%, +40 percentage points**; the table's +100 is the cumulative change from today's opening 0%, not an additional gain. Runtime: 287.297 seconds total, 200.120 seconds build and 15.838 seconds Java checks. No application deployment or production-writer activation is credited. Preflight and candidate package scores are not averaged into a project percentage.

## Proposed sequence

E104 current update: permission staging **60% to100%, +40pp this handoff**;62.346s including owner prompts,1.706s total database stages, no account mutation. New connection-inventory package D/I/V60%; R/A pending. These package gains are not additive project gains. Credentials, application wiring and actual transport checks remain separate. Full roadmap12.4%, model accuracy unmeasured. Earlier handoff statements below are historical.

E103 repair update: the spare administrator rehearsal failed SQL parsing before Apply/COMMIT. The CASE-expression correction and expanded offline diagnostics/regression checks do not earn a new checkpoint. Staging stays60%, with R/A pending; full-roadmap change0pp. Do not count a failed rehearsal as completed runtime verification.

Latest handoff gains: preflight 60% to 100% (+40 pp), plus a separately scoped NOLOGIN staging package 0% to 60% (+60 pp). These are not additive project gains. Full roadmap stays 12.4%; there is no forecast-quality gain to report. R/A for installation cannot be credited until the spare report and review.

1. Restricted approval-writer permissions and command boundary: isolated tests must prove review operations work while money/order mutation, secret disclosure and privilege escalation fail. Do not grant cash-update privileges just to acquire a lock. Application adoption needs a separate guarded migration/readback.
2. Controlled private Telegram and fresh Upstox quote review: authorized sender/recipient, expiry, duplicate/opposing callbacks, account revision, price zone and uncertain delivery. Acceptance still records review only, without orders.
3. Approved paper risk and execution policy: atomic reservations, realistic fills/costs, cancellation, holdings and P&L, with restart/replay tests. Obtain owner decisions on risk limits before activation.
4. Operational portal and integrated recovery: proposal lifecycle and ledger views, actual application backup recovery rehearsal with safe custody, and end-to-end acceptance.
5. Prospective paper pilot: at least 30 elapsed calendar days and 20 trading sessions, with longer-horizon outcomes allowed to mature. Live release and numerical-model promotion remain independent gates.

Policy decisions and portal contracts can be prepared alongside backend work. Do not bypass the sequential permission, integration, execution and pilot gates or repeat accepted tests without a relevant change.
