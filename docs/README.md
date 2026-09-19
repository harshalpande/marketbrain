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

G10.6 scoped cleanup is now completed and owner-accepted (E26). Granite was removed, Qwen 0.5B quarantined and Qwen 1.5B retained with unchanged SHA256; health stayed UP. Do not rerun removal or purge quarantine. Historical inventory/cleanup instructions below remain for traceability, not the next action. Broader runtime/job/config verification remains G10.3 work.

Close G00's remaining source-review coverage gap, verify the existing Upstox/data foundation, and establish G13/G14 data feasibility before claiming full coverage. The first numerical implementation remains a 20-session baseline, followed by required 5/60-session and intraday validation. Portal contracts and provider-access evidence can progress in parallel when authorized. Keep existing diagnostics, but do not confuse prompt optimization with model fitting. The V1 estimate and percentage are superseded as described in the roadmap and daily log.

### Current next action: evaluation engineering; Upstox reply pending (E54)

Owner reports the neutral clarification email sent; source-policy status is **PENDING_EXTERNAL_REPLY**. No ticket/reply supplied yet. Park that external dependency without closing the data gate. [Next-stage contract and session handoff](numerical-evaluation-engineering-plan.md) define synthetic numerical metrics, leakage tests and one-file offline evidence; implementation remains planned. No new collection, model fitting or inference run is requested by this documentation checkpoint.

### E52/E53 accepted export and source-policy review

The expanded spare export is verified: **600/600 arithmetic rows in 19.824s**, no blocked rows, no certified labels and no training authorization. [Review](evidence/numerical-expanded-research-spare-review-20260919.json). Do not rerun it or repeat the empty repair query. E53 checks official sources and existing ingestion: the corporate-actions connector already exists, but candle adjustment semantics and historical completeness remain unverified. [Prepared Upstox questions, code findings and bounded next steps](numerical-price-policy-open-questions.md). Documentation-only update: pull only; no Docker rebuild or model run.

### Previous expanded-export handoff (E51, completed by E52; do not rerun)

E50's spare repair capture is reviewed: **8.828s**, 600/600 calendar windows, all four stocks linked to reviewed completed backfill jobs, no capped evidence. It recovered **zero in-scope adjustment references/actions**; that does not mean no actions occurred. Do not repeat the unchanged repair query. [Recorded review](evidence/numerical-repair-review-20260919.json) and [remaining source-policy questions](numerical-price-policy-open-questions.md).

E51 advances export engineering without bypassing that gate: **150 dates / 600 research rows** from existing saved bars. Labels remain uncertified; no fitting, provider/DB/model calls or orders. Offline replay produced 600/600 arithmetic rows and preserved all 1,824 feature values of the previous 152 rows. This is not an improvement in prediction accuracy. After pulling and rebuilding the service with jobs idle and health UP:

```powershell
$parameters = @{
    ResearchExportPath = 'C:\MarketBrainData\Review\numerical-research-export-20260919-124431-2c76f7cab00a.json'
    RepairEvidencePath = 'C:\MarketBrainData\Review\numerical-repair-evidence-20260919-132809-11524efc7e3f.json'
}
& '.\ops\windows\ExportNumericalExpandedResearch.ps1' @parameters
```

Share **one** printed `numerical-expanded-research-*.json`. Compact JSON retains input bars, generated rows, price gates, provisional development layout, hashes, progress/timing and failure checkpoints. Expected status is `RESEARCH_EXPORT_TRAINING_BLOCKED`. A response already captured can be rechecked with `-ExistingExpandedReportPath <report.json>` without another server call. Persistent file locks may leave an extra pending checkpoint; preserve it. Do not rerun inference/history collection. Spare export runtime is pending; policy certification, frozen independent evaluation and fitting remain separate work.

Deployment recovery: the previous spare Git pull failed during automatic pack cleanup after fast-forward. Use `git -c maintenance.auto=false -c gc.auto=0 pull --ff-only origin main` to disable automatic housekeeping **for that command only**, check exit status and repository connectivity before building. Do not delete pack/lock files or disable security software. This does not fix or identify the process holding a file and does not stop separately scheduled Git maintenance.

### Previous action: collect stored repair provenance (completed, E50)

E47 confirms the 38-date export on spare: **152/152 rows, 3.975s**, no blocked arithmetic rows. Do not rerun export or download history. E48 has already prepared and replayed a **150-date / 600-row development expansion plan** from the saved bars, with provisional purges and boundary gaps. It is not yet a certified dataset or an untouched test. [Next work package](numerical-next-step.md) and [persisted date assignments](evidence/numerical-development-expansion-plan-20260919.json).

E49 extends the independent NSE calendar back to 2024-10-22. Offline replay of the saved export matched **600/600 feature windows and 600/600 outcome windows**, with no mismatches. The [persisted review](evidence/numerical-expanded-calendar-review-20260919.json) closes this sample's earlier calendar gap, not price certification or broader dataset readiness.

The owner has no separate adjustment report available. The new read-only repair endpoint recovers existing scoped resolution/revocation and corporate-action references; it does not redownload history, rewrite prices or certify missing evidence. After pulling and rebuilding **marketbrain-service only**, with jobs confirmed idle and health UP, run:

```powershell
& '.\ops\windows\GetNumericalRepairEvidence.ps1' -ResearchExportPath 'C:\MarketBrainData\Review\numerical-research-export-20260919-124431-2c76f7cab00a.json'
```

Share the single printed `numerical-repair-evidence-<timestamp>-<id>.json`. It includes calendar checks, scope, sanitized references, hashes, timing and failure checkpoints. `REPAIR_EVIDENCE_CAPTURED_TRAINING_BLOCKED` means captured for review, not that source evidence was sufficient. Empty/capped records remain unknown. No model run, provider call, DB write or order is initiated. Spare database compatibility/performance and actual contents remain unverified until that report. A saved response can be rechecked offline with `-ExistingRepairReportPath <report.json>`; no retry loop or old acquisition is needed.

### Previous action: export the saved-data multi-date research pilot (completed)

E45 confirms the missing outcome window on spare: 2.131s, **12/12 complete arithmetic paths**, zero blocked rows, but price provenance remains unknown. Do not rerun collection. E46 implements a stateless Java export from the two saved reports, expanding three decision dates to **38 dates / 152 rows** for this four-stock sample. This is dataset engineering, not model fitting or proof of predictive value.

After pulling and rebuilding/deploying the service **with other jobs idle**, wait for health UP and run:

```powershell
$exportParameters = @{
    FeatureEvidencePath = 'C:\MarketBrainData\Review\numerical-features-20260918-232403-546f747afe27.json'
    OutcomeEvidencePath = 'C:\MarketBrainData\Review\numerical-outcomes-20260919-121940-85dd7b401ee8.json'
}
& '.\ops\windows\ExportNumericalResearchDataset.ps1' @exportParameters
```

Share only the printed `numerical-research-export-*.json`. It embeds source bars, exact input hashes, calendars, captured price evidence, feature/outcome rows, timings and failure checkpoints. The endpoint performs **zero database/provider/model calls**; original files remain unchanged. Expected status is `RESEARCH_EXPORT_TRAINING_BLOCKED`. 152 rows are not 152 independent observations, and 38 overlapping dates cannot establish reliable out-of-time performance. Price-policy evidence, broader history/calendar export, frozen purged splits and numerical fitting remain required. See [the work package](numerical-baseline-plan.md#e46-multi-date-saved-evidence-research-export).

### Previous action: collect the missing stored outcome window (completed)

E43 confirms the coordinated preflight on spare in 2.68s with expected training blockers. Do not rerun it. E44 reads only the missing June 6-July 17 stored bars for the same four stocks and extends quality/action inspection through that outcome period. Pull, rebuild/deploy the service with jobs idle, wait for health UP, then run:

```powershell
& '.\ops\windows\GetNumericalOutcomeEvidence.ps1' -FeatureEvidencePath 'C:\MarketBrainData\Review\numerical-features-20260918-232403-546f747afe27.json'
```

Share one `numerical-outcomes-<timestamp>-<id>.json`. Completed review status is `OUTCOME_PREFLIGHT_COMPLETE_TRAINING_BLOCKED`; inspect `blockedOutcomeCount` and `partial` rather than reading COMPLETE as all rows passed. No history download, feature recalculation, provider/model calls or DB writes. The response is checkpointed before local review; `-ExistingOutcomeReportPath <saved-outcome-report.json>` can re-review it without service access. Price provenance and actual labelled training export remain pending. [Scope and remaining milestones](numerical-baseline-plan.md#e44-bounded-outcome-window-and-remaining-milestones).

### Previous N2 history handoff (completed; do not rerun)

The [numerical baseline work package](numerical-baseline-plan.md) records N1's accepted aggregate inspection: 476/500 eligible, 24 insufficient-history, one decision date. N2 adds a read-only Java diagnostic and machine-readable draft contract. Pull and rebuild/redeploy **marketbrain-service only**, after checking jobs are idle; wait for health UP, then run:

```powershell
& '.\ops\windows\GetNumericalHistoryEvidence.ps1' -DatasetRunId '5bdbfcc1-d990-48d8-9e98-d4927596d917' -LookbackDays 730
```

Share the single printed `numerical-history-<timestamp>-<id>.json`. It records 50-instrument pages (at most ten), within a 730-calendar-day window ending at the existing run's as-of date, plus persisted exclusion reasons and the draft contract. Progress/timing and partial results survive collection failures; persistent file locks may leave an additional recovery checkpoint. No inference, numerical training, dataset writes, provider calls, backfill or trades are initiated by the diagnostic. `WINDOW_COVERAGE_REVIEW_REQUIRED` is not training approval. Runtime SQL compatibility/performance and remaining point-in-time policies still need review; do not rerun the cleanup or old model sweeps.

### G10.6 read-only spare-laptop inventory

After pulling the inventory-tool commit on the spare laptop, run:

```powershell
& '.\ops\windows\GetSpareLlmCleanupInventory.ps1'
```

Windows PowerShell 5.1 or PowerShell 7 is supported by the script syntax; local offline verification was on 5.1, not a live spare-machine run. The tool never executes llama binaries or calls model inference, deletes models, downloads anything, stops existing processes, reads `.env`, or queries a database/broker. Its only filesystem writes are one uniquely named report and transient checkpoint files under `C:\MarketBrainData\Review`. Share the printed `llm-inventory-<timestamp>-<id>.json` only; timings, progress events and warnings are embedded. Reports contain local paths and model names: inspect them before sharing. A failed save may leave a pending checkpoint; do not rerun inference to recover it.

Ollama inspection uses only loopback [GET /api/tags](https://docs.ollama.com/api/tags) and [GET /api/ps](https://docs.ollama.com/api/ps), with 10-second request timeouts and no redirects. Unavailable or malformed responses mean UNKNOWN, not no models. The tool inspects process names/IDs, executable file-version metadata and Windows hardware counters; GPU AdapterRAM is explicitly not a reliable free-VRAM measurement. It does not verify Java jobs, scheduled tasks or actual live-service configuration.

Default GGUF roots are the user's Hugging Face hub cache, user/local-app-data llama.cpp caches, and `C:\MarketBrainTools\llama.cpp`. Add a specific nonstandard model directory using `-AdditionalModelDirectories @('D:\MyModelFolder')` only if that is your actual location. No whole-drive search. The scan has a cooperative 30-second / 10,000-entry / depth-10 limit, skips directory links and labels partial results. Slow filesystem/CIM operations can exceed the time budget; this is not a hard wall-clock guarantee. Model blobs are not hashed or loaded, shared/hardlinked size is not summed as recoverable space, and Ollama blob stores are not manually traversed.

Fixed-token source references provide dependency hints only; actual dependency review, retain/remove approval and cleanup remain pending. Normally allow a few minutes, not a model-evaluation session. Do not stop running jobs or start Ollama merely to force a green report; unavailable components are useful evidence too.

### G10.6 dependency follow-up (no removal)

Inventory E22 was received and reviewed: 13.25 seconds on spare PowerShell 7.6.6. It found Granite installed but unloaded, both Qwen GGUFs, and llama-cli/server. These facts do not prove Java jobs are idle. Run the follow-up after pulling, without rebuilding Docker:

```powershell
& '.\ops\windows\GetSpareLlmDependencyReview.ps1'
```

Share only the printed `llm-dependencies-<timestamp>-<id>.json`. The tool checkpoints progress/timings/errors into one report, reads service health, current process names/IDs, Ollama lists, fixed-token scheduled-task hints, and saved `status.json`/`sweep.json`/`comparison.json` files. Default review root is `C:\MarketBrainData\Review`; if the deployed volume uses another location, explicitly pass that location with `-ReviewDirectory`. No whole-drive scan, inference, downloads, stops, cleanup, `.env` dump, model contents or broker/database queries.

Task metadata uses Microsoft's [MSFT_ScheduledTask CIM class](https://github.com/microsoft/wmi/blob/master/server23h2/root/microsoft/windows/taskscheduler/MSFT_ScheduledTask.go). Only allowlisted tokens, opaque indices and state codes are exported, not names/accounts/action text. Generic shell tasks are included as hints; inspect indirect wrappers locally. A permissions failure becomes UNKNOWN. CIM has a 10-second operation timeout and a 1,000-task inspection cap. Saved evidence has a cooperative 20-second, 2,000-entry, depth-3, 2-MiB-per-file limit; links are skipped and incomplete scans marked partial. Slow underlying I/O can exceed cooperative bounds.

Important source finding: the Java GET job-status handler may persist `LOST_AFTER_RESTART`. The tool therefore never calls job-status endpoints. Saved RUNNING/QUEUED states require review, not automatic stopping; even terminal evidence does not establish no new jobs. No global read-only Java job-list API exists. Actual container configuration, Windows services, indirect wrappers and external schedulers remain outside this check. The report always says NOT CLEARED until operator/dependency review and exact removal approval. Confirm that no model-run terminals/jobs or planned experiments need the proposed removals; do not share credentials or full process arguments.

Typed preview and comparison defaults now select only `Qwen/Qwen2.5-1.5B-Instruct-GGUF:Q4_K_M`. Explicit `-ModelRef`/`-ModelRefs` overrides preserve historical experiments; using a retired reference can fetch it again. Legacy Granite scripts are retained for evidence reproduction, not part of this handoff. This default change is not model validation or retraining. Retain llama.cpp and Qwen 1.5B provisionally. Granite and 0.5B are removal candidates only after dependency review/approval; do not delete shared cache roots. No architectural runtime or Java change is deployed by this step.

### Guarded cleanup handoff (spare laptop only)

Owner authorized proceeding after E24 dependency review. `InvokeSpareApprovedLlmCleanup.ps1` previews by default; `-Apply` additionally requires typing `CLEANUP GRANITE AND QWEN05` at an interactive prompt. That confirms all model jobs/terminals are idle, scheduled/service consumers have been reviewed, no model jobs will be started during cleanup, and the exact removal/quarantine and recovery limitations are accepted. If these conditions are not known, cancel; do not bypass the prompt. No assertion that the stale saved RUNNING job is dead is made, and no status files are rewritten.

```powershell
# Optional non-mutating preview (writes only evidence; does read/hash selected model files):
& '.\ops\windows\InvokeSpareApprovedLlmCleanup.ps1'
# Apply only after reviewing the displayed targets and confirming idle/dependency conditions:
& '.\ops\windows\InvokeSpareApprovedLlmCleanup.ps1' -Apply
```

Scope is deliberately fixed to the reviewed installation:

- Delete only Ollama tag `ibm/granite4.1:8b`, only if its digest is still `444af1c4b2fedd6b54041aca558e7300b0b3d5c0468c44619126240323ba2852`, using the official [DELETE /api/delete](https://github.com/ollama/ollama/blob/main/docs/api.md#delete-a-model). HTTP timeout 120 seconds, no redirects, no automatic retry or download. Absence is verified afterward. A timeout may mean the deletion happened: the report records intent before the request; never assume rollback.
- Move exactly the existing 491,400,032-byte Qwen 0.5B GGUF from the current user's Hugging Face snapshot `9217f5db79a29953eb74d5343926648285ec7e67` into `C:\MarketBrainData\ModelQuarantine\<run-id>\qwen2.5-0.5b-instruct-q4_k_m.gguf`. The full paths and SHA256 are recorded before movement and verified afterward. No recursive directory moves/deletes, shared blobs/refs edits or cache-root removal. Linked paths/ancestors, cross-volume moves and overwrite destinations are refused.
- Retain the 1,117,320,736-byte Qwen 1.5B snapshot `91cad51170dc346986eccefdc2dd33a9da36ead9`; compare its SHA256 before/after. Preserve llama-cli/server, Ollama runtime, all existing reports, datasets, PostgreSQL data, Docker volumes and config. No inference, service/process stops or Docker rebuild.

Fresh preflight/step checks require Ollama lists to be available, no loaded model, no llama-cli/server process, and service health UP. These are not an atomic job lock: operator coordination is still mandatory. A changed target, missing retained model, unavailable API or failed checkpoint blocks further actions. Earlier successful actions are not automatically undone if a later action fails. Inspect `quarantineState` and `graniteState` in the single `llm-cleanup-<timestamp>-<id>.json` report. Checkpoint intents permit inspection after interruption; a uniquely named rerun skips targets already absent, without claiming it removed them or validating an earlier quarantine.

Recovery: same-volume Qwen quarantine is reversible by checking the recorded hash and moving that one file back to the recorded original path if it is absent; do not overwrite a newly downloaded file. Quarantine frees **no disk space**; retained cache refs may cause a future explicit 0.5B request to fetch the model again. Granite removal is not locally undoable; restoration needs a separately authorized re-download and tag content may have changed. C: free-space delta is observed, not attributed solely to cleanup. Keep the report/quarantined file until review, and do not purge quarantine as part of this step.

Allow a few minutes for selected-file hashing and API checks; no inference workload is involved. Share just the printed cleanup JSON. A successful run verifies this narrow removal/retention/health scope, not predictor quality or all G10 readiness. After owner review, proceed to the data-quality baseline and numerical prediction engine contract rather than another LLM sweep.
