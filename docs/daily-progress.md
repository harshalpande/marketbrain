# Daily progress and decision log

Current percentages live in [the roadmap](roadmap.md). Evidence definitions and limitations live in [the register](evidence-register.md). Entries are appended on days worked; no autonomous daily updating is implied. Do not rewrite an old failure as a success—append a correction or subsequent result.

## 2026-09-18 — Documentation reset and scope baseline

- Scope: documentation and design only, at owner request. No new application implementation, model inference, database mutation, deployment or broker action.
- Source baseline: `142f3bd`; documentation revision: the commit containing this entry. Six existing untracked Java news-watch drafts remain untouched and excluded from the documentation commit.
- Completed: archived eight superseded documents/assets; created one canonical documentation entry point, roadmap, responsibility/portal design, evidence register, daily log and current architecture diagram.
- G00: inventory mapped, plan written, evidence/uncertainty register written = 3/5 checkpoints (60%). Exhaustive source-review coverage and owner acceptance still pending. No claim of every source line having been reviewed.
- Product baseline: **13% weighted engineering delivery**, according to the newly declared checkpoint method. G01 has source-presence credit (40%); G02–G11 have design credit (10% each). This is a new scope baseline, not a measured regression from an older quoted percentage and not a model-success probability.
- Numerical predictive performance: **not established**. Current runtime verification: pending collection. No fresh model-quality improvement or expected profit percentage claimed.
- Verification: 25 active relative-document links resolve; architecture SVG parses as XML; 11 weighted goals sum to 100 and calculate to a 13% baseline; all eight archived document bodies/assets match their originals apart from declared headings/notices/title. UTF-8 decoding was required in the archive checker to avoid an initial false mismatch. Git whitespace checks passed. Only documentation is staged for this change. Application tests were not run; this is a docs-only change.
- Work duration: not separately measured; no engineering-hours or model-runtime claim.

### Decisions recorded

1. Owner requested a fresh authoritative plan with evidence-based percentages, parallel/sequential work, daily tracking and guarded timelines. Historical documents are superseded and retained for traceability, not active instructions.
2. Upstox remains an existing data foundation. Paytm live market data is explicit current-target scope; Paytm real order execution is separate and deferred.
3. The first functional portal uses **one INR 100,000 virtual account**, with all accepted orders/fills internal. Initial scope is paper operation; there is no authorization to send real broker orders.
4. Intraday and swing are separate prediction horizons. Marketaux is the identified news provider. Proposed initial instrument scope and risk thresholds require owner review.
5. Java owns calculations, data/risk/approval/accounting. A numerical model must demonstrate predictive value; a small language model is optional for news interpretation. Qwen/Granite prompt experiments do not establish a numerical forecasting model or calibrated trading confidence.
6. Trial protocol: at least 30 elapsed calendar days and 20 actual trading sessions, sufficient opportunities and matured labels. Material changes create new identifiable cohorts. Passing the trial does not automatically authorize live trading.
7. Proposed implementation forecast: 45–60 engineering working days after authorization/access readiness, then prospective observation and label maturation. Dates are conditional, not delivery commitments.

### Open decisions / blockers

- Owner acceptance of this baseline, proposed risk/fill assumptions and the next implementation slice.
- Current spare-laptop revision, coverage, provider entitlements and latest matched experiment evidence.
- Explicit disposition of six pre-existing untracked news-watch drafts before a local application build. They are not silently removed or treated as accepted features.
- Historical constituent/vintage and intraday coverage availability; any limitations must affect scope and validation claims.
- Paytm live-data authentication/permissions/static-egress evidence, separately from future trading authority.

### Next authorized work proposed

1. G00/G01: complete review-coverage inventory and refresh bounded evidence first; collect existing reports without rerunning lengthy inference unnecessarily.
2. G02: approve point-in-time feature/label/split contracts and implement audited multi-date fixtures/export when authorized.
3. G08/G09: approve ledger/fill/approval contracts and portal wireframes; these can progress independently of model training using fixtures.
4. G05/G06 access/licensing questions can progress while local data/accounting work proceeds. No infrastructure changes implied.

## 2026-09-18 — V2 parent-goal alignment approved and documented

- Authorization: owner accepted the recommendations/clarifications and asked to add them to documentation. This entry records scope acceptance, not application implementation or live-order authorization.
- Source baseline for this update: `f58d4f1`; documentation revision: the commit containing this entry. Starting working tree was clean; the historically recorded `news/watch` drafts were absent. No source files were added, removed or edited in this update.
- Added PG1 (full intelligence/eventual approved execution) and PG2 (mandatory shared-workflow paper deployment) to the canonical index, with requirement-to-subgoal traceability.
- Added G13 for 15+ year, frequency-specific historical coverage and membership; G14 for point-in-time fundamental data/analysis; G15 for separate feedback/outcomes and controlled retraining/promotion/rollback. Corrected G07 to required 5/60-session models alongside G03's 20-session baseline; 10 sessions are optional, intraday horizons separate.
- Added explicit ACCEPT/REJECT display semantics, HOLD-without-order and NO_TRADE/ABSTAIN; autonomous analysis never bypasses approval/risk. Approved INR 100,000 account and research simulation use isolated accounting. Paper and future live workflows share contracts, not assumed-identical fills or an unrestricted LIVE switch.
- Progress: G00 60% -> 80% for owner acceptance of the parent scope; exhaustive source-review coverage remains outstanding. Detailed risk defaults still need separate approval. No implementation V/R/A checkpoints earned.
- Paper-first scope baseline: V1 13% -> **V2 12.4%**, a **-0.6 percentage-point scope/weight change**, not lost work or worse prediction. Fourteen included goals have weights totalling 100; G01 weight 8 at 40%, remaining weight 92 at 10%. Deferred G12 stays 0%, outside this denominator. Full PG1 has no claimed overall completion percentage.
- Timeline: withdrew V1's 45–60-day overall estimate/calendar dates for this expanded scope. The first five authorized working days now culminate in a published evidence-based estimate/blocker review; D10 revisits velocity. This is not a start-date commitment. A month of operation and full 60-session outcome maturation are separate acceptance milestones.
- Next: obtain current coverage/entitlement/fundamental-source evidence and approve a bounded implementation slice. No expensive model rerun, Docker rebuild or broker call is required for this documentation update.
- Verification passed: 24 active relative links resolve; SVG parses as XML; 14 weighted goals sum to 100 and calculate to 12.4%; all 74 subitem IDs are unique and referenced subitems exist. No stale required 5/10-session wording remains in active design/index/diagram. Git whitespace and documentation-only scope checks pass; archive untouched. Application tests were not run for this documentation-only change.

## Daily entry template

Copy this section for the next worked day; keep empty fields explicitly unknown rather than filling with guesses.

```text
Date (IST):
Scope authorized / owner decision reference:
Git revision / deployed revision:
Goal and subitem IDs:
Planned bounded work / effort estimate:
Actual work and measured effort:
Evidence IDs / artifact paths / run IDs:
Tests and expected versus actual results:
Metrics (numerator, denominator, elapsed time, p50/p95 where meaningful):
Dataset / split / model / policy / configuration versions:
Safety effects (DB writes, notifications, paper actions, broker actions):
Failures / limitations / unresolved blockers:
Checkpoints earned or invalidated and reason:
Previous completion -> new completion (goal and weighted overall):
Next day bounded work / dependencies / revised timeline:
Verification, commit/push and spare-machine handoff:
Owner acceptance, if any:
```

## Updating rules

- Change the roadmap dashboard only after linking evidence to the exact checkpoint; then append the delta here.
- Use percentage points for absolute changes and explicitly name the denominator for relative improvements. Do not blend schema success, alignment, financial outcomes and engineering completion.
- Keep the untouched final evaluation set untouched. A newly tuned run is not a new independent holdout result.
- A blocked provider goal can remain pending while independent fixture/portal work progresses. Do not claim parallel staffing or run concurrent model jobs to meet a schedule.
- Update relevant design sections and the one active diagram when authorized architecture changes; old archived docs stay superseded.
- Commit/push only verified scoped changes; provide a spare-machine script only appropriate to the change. Documentation-only updates need no Docker rebuild or model rerun.
