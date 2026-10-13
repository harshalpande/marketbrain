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

## Recorded progress on 2026-10-13

E125 accepts actual spare staging: 13/13 subprocesses, 11 matching source hashes, zero parse errors, four added rules, preserved application access and completed diagnostic cleanup. Runtime review moved staging 60% to 80%; the owner's go-ahead closes acceptance at 100% (+40pp since the previous handoff). No real rollback was needed. Total 2447.284s includes 15.521s measured subprocess time; remaining time is not separately attributed. E126's narrow read-only network follow-up is part of outstanding access findings, not a new percentage package. Its 222 offline assertions pass; spare review is pending. Earlier entries below are historical.

E124 update: spare rehearsal correction accepted after 434 workflow assertions and 134 separate descriptor checks in 34.540s, five matching script hashes and successful legacy permission/recovery checks. Owner authorized actual guarded staging. This removes the rehearsal blocker, but does not complete the frozen runtime checkpoint: real HBA staging and fresh PostgreSQL/application connections remain pending. Staging 60%, additional gain 0pp, full roadmap 12.4%. No repeat rehearsal is required for the unchanged reviewed scripts. E123/E122 notes below are historical.

E123 update: the legacy auto-inherited metadata difference is reproduced and a narrow binary comparison correction is implemented with replacement/recovery regressions. Spare correction acceptance is pending; staging stays60%, repair gain0pp, full roadmap12.4%. E122's earlier unknown-cause note below is historical.

E122 update: the spare generated-file rehearsal failed before real HBA staging. Exact cause is unconfirmed. Safe mismatch diagnostics and additional permission-layout tests are implemented; the next handoff is rehearsal only. No runtime/owner-acceptance credit is added and repair gain is0pp. The table's E121 local-verification credit remains separate from this failed spare run.

Frozen package: restricted writer Stage 1 preparation only. Scope is byte-preserving rule generation, synthetic replacement/recovery and bounded collection of missing selectors for saved firewall candidates. Real HBA staging, ACL preservation, PostgreSQL authentication and writer activation are excluded and remain required later.

E118 accepts the56.77-second spare comparison:40 checks,264 scanned rules,126 full candidates, no missing fields, nine source matches. Preparation reached80% with runtime verification and100% with the owner's go-ahead after report review. Missing identities and unbaselined candidates remain policy findings, not permission to edit firewall rules. E120 now accepts E119's separately bounded read-only file-plan package after10 successful subprocess steps in23.890s and owner go-ahead. E121 freezes the next package at protected backup, exact replacement, owner/group/DACL preservation, fresh DB/application checks, rollback, independent recovery and one report. Activation and firewall changes are excluded.

| Area / bounded package | Opening % | Current % | Change (pp) | Evidence | Pending |
|---|---:|---:|---:|---|---|
| Writer restriction preparation, Stage 1 | 0% | 100% | +100 | D/I/V/R/A; E118 runtime evidence and owner go-ahead | Closed for collection; policy findings carry forward |
| Read-only actual HBA file plan, Stage 2 planning subset | 0% | 100% | +100 | D/I/V/R/A; E119/E120; [scope](paper-writer-hba-plan.md) | Closed; live staging is a distinct package |
| Guarded actual HBA staging and recovery | 0% | 100% | +100 | D/I/V/R/A; E121-E125; actual staging and owner acceptance complete | Closed for this scope; retain backup, do not reapply; writer activation separate |
| Existing targeted access review | 80% | 80% | 0 | E113 retained; E126 prepares narrow follow-up | Review two rule/address mappings, then policy acceptance; no duplicate runtime credit |
| Full paper-first roadmap | 12.4% | 12.4% | 0 | Parent checkpoint scope unchanged | Integrated application writer and later paper workflow gates |

No real application/database/inference/firewall activity was performed locally. E125 records real staging on the spare only, with no database data writes or writer activation. The staging package moved 60% to 100% (+40pp) since its prior handoff; the daily table retains its original 0% opening baseline. E126 tests mock all system calls. Do not average these rows or describe test pass rates as prediction improvement.

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
| Connection security inventory only | 0% | 100% | +100 | D/I/V E105/E106; R/A [E107](evidence/paper-writer-connection-spare-acceptance-20261012.json) | Closed; not proof of writer login or private application route |
| Local writer foundation candidate | 0% | 100% | +100 | D/I/V E108; R/A [E109](evidence/paper-writer-foundation-spare-acceptance-20261012.json) | Closed; real credential handoff and application wiring remain separate |
| Targeted writer access review | 0% | 80% | +80 | D/I/V E110-E112; R [E113](evidence/paper-writer-access-spare-verification-20261012.json), 57.98s; [frozen scope](paper-writer-access-review.md) | Policy findings review and owner acceptance; [restriction plan](paper-writer-restricted-access-plan.md) prepared, not applied |
| Full paper-first roadmap | 12.4% | 12.4% | 0 | Parent checkpoint scope unchanged | Complete integrated parent-goal gates |

The candidate percentage is **not** the completion of the production writer, paper portal, entire approval area or predictor. Its latest change is **60% to 100%, +40 percentage points**; the table's +100 is the cumulative change from today's opening 0%, not an additional gain. Runtime: 287.297 seconds total, 200.120 seconds build and 15.838 seconds Java checks. No application deployment or production-writer activation is credited. Preflight and candidate package scores are not averaged into a project percentage.

## Proposed sequence

Current E113: corrected spare access review completed all 10 stages with 14 matching sources, 57.98s. Latest gain is 60% to 80%, +20pp for R; the table's +80 is cumulative from today's opening 0%. A remains pending. Prepare exact-writer restriction and targeted firewall-selector review without blanket ACL changes or live edits. No new percentage for the plan; full roadmap 12.4%. Earlier retry instructions below are historical; do not repeat the unchanged diagnostic.

E112 repair: firewall collection and both database queries succeeded, but PostgreSQL host-mask formatting failed route validation after 66.08s. Corrected producer/parser and evidence retention; 720 Java tests plus 186 contract/firewall and 216 runner assertions passed. Retry diagnostic only, no rebuild. Access review remains 60%, repair gain 0pp, full roadmap 12.4%; previous foundation acceptance is unchanged.

E111 repair: elevated access inspection reached the old candidate-rule cap after 42.47s, without database access. Revised collector passes 128 contract/firewall and 160 runner assertions, including larger rule sets and partial evidence retention. Retry access collection only. Package remains 60%; repair gain 0pp and full roadmap 12.4% unchanged.

Current E109/E110 handoff: foundation closes60% to100%,+40pp,26.49s spare run. Access-review implementation is60%, with719 Java tests and62+139 separately scoped PowerShell assertions passed. No application login activation or trading credit; full roadmap12.4%. Run the combined access review once; do not repeat foundation/installation. Earlier next-handoff statements below are historical.

Current E107/E108 handoff: connection inventory closes 60% to 100% (+40pp), 16.181s total and 0.410s database stage. The owner approved TLS deferral for the private same-machine policy. The separate foundation candidate is 60%, with 708 Java tests, 120 mocked boundary assertions and 15 synthetic custody checks passed locally; spare acceptance remains pending. No actual writer login, application deployment or execution is credited. Full roadmap remains 12.4%. Earlier retry/next-step statements below are historical.

E106 repair: connection collection stopped at saved-report validation before database access. Int32/Int64 compatibility and safe diagnostics are corrected; no new progress checkpoint is earned. Connection inventory remains60%, NOLOGIN staging100%, full roadmap12.4%. Repeat only the read-only collection after pulling the correction.

E104 current update: permission staging **60% to100%, +40pp this handoff**;62.346s including owner prompts,1.706s total database stages, no account mutation. New connection-inventory package D/I/V60%; R/A pending. These package gains are not additive project gains. Credentials, application wiring and actual transport checks remain separate. Full roadmap12.4%, model accuracy unmeasured. Earlier handoff statements below are historical.

E103 repair update: the spare administrator rehearsal failed SQL parsing before Apply/COMMIT. The CASE-expression correction and expanded offline diagnostics/regression checks do not earn a new checkpoint. Staging stays60%, with R/A pending; full-roadmap change0pp. Do not count a failed rehearsal as completed runtime verification.

Latest handoff gains: preflight 60% to 100% (+40 pp), plus a separately scoped NOLOGIN staging package 0% to 60% (+60 pp). These are not additive project gains. Full roadmap stays 12.4%; there is no forecast-quality gain to report. R/A for installation cannot be credited until the spare report and review.

1. Restricted approval-writer permissions and command boundary: isolated tests must prove review operations work while money/order mutation, secret disclosure and privilege escalation fail. Do not grant cash-update privileges just to acquire a lock. Application adoption needs a separate guarded migration/readback.
2. Controlled private Telegram and fresh Upstox quote review: authorized sender/recipient, expiry, duplicate/opposing callbacks, account revision, price zone and uncertain delivery. Acceptance still records review only, without orders.
3. Approved paper risk and execution policy: atomic reservations, realistic fills/costs, cancellation, holdings and P&L, with restart/replay tests. Obtain owner decisions on risk limits before activation.
4. Operational portal and integrated recovery: proposal lifecycle and ledger views, actual application backup recovery rehearsal with safe custody, and end-to-end acceptance.
5. Prospective paper pilot: at least 30 elapsed calendar days and 20 trading sessions, with longer-horizon outcomes allowed to mature. Live release and numerical-model promotion remain independent gates.

Policy decisions and portal contracts can be prepared alongside backend work. Do not bypass the sequential permission, integration, execution and pilot gates or repeat accepted tests without a relevant change.
