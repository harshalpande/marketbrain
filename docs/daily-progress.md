# Daily progress and decision log

Current percentages live in [the roadmap](roadmap.md). Evidence definitions and limitations live in [the register](evidence-register.md). Entries are appended on days worked; no autonomous daily updating is implied. Do not rewrite an old failure as a success—append a correction or subsequent result.

## 2026-09-18 — Spare inventory evidence and bounded dependency follow-up

- Authorization: owner asked to proceed with dependency check and cleanup preparation. No approval for actual deletion, service stops, downloads or model inference was inferred.
- E22: reviewed the supplied single JSON; SHA256 recorded in evidence register. Inventory took 13.25 seconds on spare PS7.6.6. Granite remains installed (not loaded), both Qwen sizes exist, llama.cpp executables exist. Hardware/process snapshot is not live-job clearance. About 607 GiB free on C: means storage capacity is not the immediate issue. Unloaded-model deletion is not a measured inference speedup.
- Added one-report dependency review with health, process names, Ollama lists, redacted scheduled-task hints and bounded persisted-job scan; atomic checkpoints, timings, visible progress and unknown/partial states. Never auto-clears cleanup. Operator must confirm actual review-volume mapping, outstanding jobs/terminals and indirect dependencies.
- Source finding: Java job GET may write LOST_AFTER_RESTART to saved status. It is excluded from this read-only tool; no Java changes or rebuild needed.
- Typed preview/comparison defaults now use Qwen 1.5B only. Legacy models remain explicitly selectable for reproduction; default replacement does not train/validate the retained model. Architecture candidate annotation updated, full design unchanged.
- Verification: 29 dependency assertions and 41 inventory assertions passed offline on local Windows PowerShell 5.1. Tests use mocks/temporary fixtures, never real local model jobs/APIs. Changed scripts parsed with the local parser; runtime verification of new tool on PS7 awaits spare report. Temporary fixtures retained, no destructive test cleanup.
- C1/C2 now PARTIAL, not complete; C3/C4/C5 remain pending; 0/5 fully closed cleanup checkpoints. Weighted project baseline remains 12.4%; no predictive improvement claimed.
- Next handoff: pull, run `GetSpareLlmDependencyReview.ps1`, share its single JSON and confirm whether any model test terminals/jobs remain active. No Docker rebuild, inference or cleanup command in this handoff.

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

## 2026-09-18 — Supplied diagnostic reviewed and spare documentation sync noted

- Owner supplied `diagnostics.json`, `diagnostics.log.txt`, the diagnostic console attachment and a separate documentation-pull transcript; requested that the update be noted. Review/persistence only: no implementation, deployment or inference authorized/performed.
- E19 records run `typed-diagnostics-20260918-175424-560053`, Qwen2.5-1.5B Q4_K_M, 20 paired calls across four synthetic cases/five configurations. Completed in approximately 4m30s; all 20 processes exited successfully, no timeouts; full input echo verified and runtime lines report no truncation.
- Quality finding: all 16 extracted decisions are REJECT, as are the four fenced raw one-field answers. All 12 full seven-field outputs fail business checks; positive cases remain missed. One-field free-form schema failures include Markdown fences, with stricter parsing than the seven-field evaluator. Detailed counts, failure overlap, timings, provenance and SHA-256 hashes are persisted in the evidence register.
- E20: supplied spare-machine output confirms a documentation Git fast-forward from `142f3bd` to `9536ad0`, with success text and no rebuild/model rerun. This proves the reported checkout update only, not running-container revision or service/provider readiness. Diagnostic execution preceded that documentation update.
- Progress: additional evidence, **no delivery checkpoint earned**. G00 remains 80%; weighted paper-first baseline remains 12.4%; predictive readiness is unproven. The paired synthetic diagnostic is not directly comparable to earlier real-candidate runs or a market accuracy percentage.
- Next: retain original evidence and use it for the deferred parser/runtime review if model diagnostics resume; do not repeat this completed run or launch a new sweep automatically. Continue the agreed evidence-first numerical/data/portal plan when separately authorized.
- Change scope: evidence register and this daily log only; no architecture or safety-policy change. Source/log cross-checks and documentation validation recorded with this note; no application tests or runtime requests performed.

## 2026-09-18 — Restart priorities and spare-machine cleanup reminder

- Owner asked where to restart from the baselined goals and explicitly reminded us that several LLMs are installed on the spare machine and need cleanup. Recorded as G10.6 with five evidence-gated checklist items: inventory, dependency review, exact owner-approved plan, scoped cleanup, verification.
- Current installed tags/files and active processes remain unknown. Previous Granite/0.5B/1.5B discussions are historical context, not a current inventory. Qwen2.5-1.5B is a possible retained diagnostic reference, not a production-qualified decision engine.
- Immediate priority: read-only environment inventory and existing data-readiness evidence. Proposed first build after approval: G02 prediction-grade 20-session dataset and G08 paper-account foundation; G09 portal contracts/wireframes alongside these. No new LLM sweep is required to begin the numerical/data work.
- Scope of this turn: documentation reminder and next-work recommendation only. No spare-machine command, model deletion/download, process termination, code change, provider request or deployment performed. Cleanup remains 0/5; G00 remains 80%; weighted product baseline remains 12.4%.
- Preserve all prior experiment evidence, databases, configuration, shared model-cache dependencies and any running jobs. Removal targets and recoverability must be reviewed before cleanup. Independent source/data/design work can proceed without waiting for file deletion once its scope is authorized.

## 2026-09-18 — G10.6 read-only inventory tool implemented

- Owner authorized proceeding with the immediately proposed read-only spare-machine inventory. Implemented a single-report collector and offline tests, not deletion or model selection. No application/Java, architecture, deployment, provider or broker behaviour changed.
- Tool: `ops/windows/GetSpareLlmCleanupInventory.ps1`; one unique JSON with incremental atomic checkpoints, progress events, timings, script hashes, limitations and per-section unknown states. Collects only local read-only Ollama lists, runtime file/process metadata, bounded GGUF path metadata, hardware counters and allowlisted source-reference tokens. No model inference/download, process stop, credential dump, .env access, full configuration export or cleanup.
- Verification E21: offline tests using fake HTTP responses, dummy non-model files, an isolated directory junction and mocked integration collectors passed 41 assertions under Windows PowerShell 5.1. First atomic-save test exposed PowerShell's null-string conversion in File.Replace; fixed using NullString and verified successive checkpoints. Tests left small uniquely named fixtures in the local temporary directory, not in the repo or model caches. No live Ollama, Java, hardware collection or model inference was performed here; PowerShell 7 runtime verification remains for the spare laptop.
- G10.6 C1–C5 remain pending (0/5) until the real inventory is returned and reviewed; overall paper-first delivery remains 12.4%. A supporting inventory script is not the complete G10 implementation checkpoint.
- Handoff: pull this commit, run the inventory script on the spare laptop, share only the printed JSON. No Docker rebuild or model run. Use the result to propose exact retain/remove targets and dependencies; cleanup remains separately approved.

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
