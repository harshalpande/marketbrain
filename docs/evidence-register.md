# Evidence register and verification procedure

Baseline inspection: 2026-09-18; source revision **142f3bd** before this documentation-only reset. This register separates source inspection from execution evidence. **No application build, database query, inference run or spare-laptop deployment was performed for this documentation task.**

## Evidence vocabulary

- `SOURCE_VERIFIED`: relevant implementation was inspected; not proof of runtime success.
- `HISTORICAL_REPORT_ONLY`: prior docs/logs claim a result; revision/environment and continued validity need verification.
- `OFFLINE_VERIFIED`: reproducible test result at an identified revision.
- `RUNTIME_VERIFIED`: identified spare-laptop revision/config and matching integration evidence.
- `DOCUMENTED_ONLY`: design exists, implementation not established.
- `PARTIAL`: some required components exist but the goal is incomplete.
- `UNKNOWN`: evidence unavailable; do not convert to success or failure.
- `FAIL`: observed criterion failure, with version and scope.

## Findings and missing proof

Paths below are repository-relative. Existing source can be reused without claiming the new scope is complete.

| ID | Finding and source pointers | Evidence class | What remains to establish |
|---|---|---|---|
| E01 | Baseline inventory: 512 tracked files; 259 main Java files, 118 Java test files, 25 SQL migrations, 74 PowerShell files; selected textual inventory 496 files / 52,724 lines | SOURCE_VERIFIED inventory | Inventory is not proof every line was reviewed; counts refer to pre-reset revision |
| E02 | `marketbrain-service/src/main/java/in/marketbrain/marketdata/upstox/UpstoxReadOnlyClient.java`, `UpstoxMarketDataController.java`: instrument, quote, historical/intraday candle and corporate-action operations | SOURCE_VERIFIED | Current account entitlements, successful runtime requests, coverage and reconnect behaviour; no streaming implementation established |
| E03 | `feature/TechnicalFeatureCalculator.java`, `FeaturePreviewService.java`, `FeatureUniversePreviewService.java`; `marketdata/daily/DailyEnrichmentScheduler.java` under the same Java package root: technical indicators, source selection, snapshots and scheduled daily enrichment | SOURCE_VERIFIED | Actual persisted coverage, freshness, missing sessions, adjustments, historical revisions and restore evidence |
| E04 | `training/SwingTrainingDatasetPreviewService.java`, `SwingOutcomeLabelCalculator.java`; immutable training migrations: prototype 5/20/60-session labels, reference-close returns and constant cost assumptions | SOURCE_VERIFIED / PARTIAL | Prediction-grade executable labels, multi-date data, historical membership, availability-time controls and actual exchange calendar; 10-session target not yet supported |
| E05 | `marketdata/paytm/PaytmMoneyHistoricalClient.java`: enabled/credential-gated historical chart client, not real execution | SOURCE_VERIFIED / PARTIAL | Current live-market-feed contract, authentication, entitlement, egress/network evidence; no create/modify/cancel-order integration claimed |
| E06 | `news/MarketauxNewsConnector.java`, `NewsIngestionRunService.java`, `NewsArticleRepository.java`, news governance migrations: connector, ingestion audits and permission foundations | SOURCE_VERIFIED / PARTIAL | Durable entity/event matching, scheduling, effective daily quota enforcement, consistent request timeouts, retention and end-to-end news-triggered workflow |
| E07 | Initial SQL paper portfolio seed INR 100,000, paper order/fill tables; deterministic sizing and revalidation helpers | SOURCE_VERIFIED / PARTIAL | Complete ledger, reservations, fill simulation, reconciliation and crash-safe lifecycle; tables alone do not establish a working paper account |
| E08 | `marketbrain-ui/src/App.tsx` and dashboard source are static-preview foundations; Java Telegram/WhatsApp notification and approval handling exists | SOURCE_VERIFIED / PARTIAL | Functional portal and connected paper execution. Approval remains blocked pending fresh quote in existing flow; no completed fill workflow inferred |
| E09 | Training/preview services and PowerShell sweeps implement heuristics, typed contracts, experiments and evidence collection; no fitted numerical training/inference pipeline found in inspected source | SOURCE_VERIFIED absence within inspected scope / DOCUMENTED_ONLY new engine | Numerical datasets, model fitting, validation, calibration and model artifact lifecycle |
| E10 | Six untracked `marketbrain-service/src/main/java/in/marketbrain/news/watch/` Java drafts were present before this reset | UNACCEPTED DRAFTS | `NewsWatchContract`, `NewsWatchController`, `NewsWatchEngine`, `NewsWatchFixtures`, `NewsWatchPredictor`, `NewsWatchReplayService` are not counted as accepted implementation; obtain disposition before a local build that includes them |
| E11 | Test source is substantial, but some checks assert contracts/source strings; service Docker build uses Maven with tests skipped | SOURCE_VERIFIED; current execution UNKNOWN | Run actual clean-revision tests and integration checks before earning V/R. Earlier reported test counts do not certify this revision or dirty drafts |
| E12 | Official Upstox feed/analytics docs and Marketaux docs reviewed; Paytm public developer portal identified | EXTERNAL DOCUMENTATION, checked 2026-09-18 | Current account-specific entitlements/contracts; public product capability is not project integration evidence |
| E13 | V1 documentation reset: 25 active relative links, valid XML, eight preserved originals, weights 100 and then-baseline 13% | HISTORICAL DOCUMENTATION VERIFIED | V1 checks passed as recorded in the daily log; V2 progress/verification supersedes these counts, without changing the archived originals |
| E14 | Earlier typed-decision records described 64 schema-valid responses but only 7 business-valid and no diagnostic successes in that reported run; separate all-REJECT diagnostics were discussed | HISTORICAL_REPORT_ONLY | Do not reuse these as a current benchmark without matching run ID, artifacts and revision. The newest diagnostic outcome is not established by this reset |
| E15 | `PrototypeSwingOllamaGuidedRankingPreviewService.java` can draw labelled examples from the same dataset run; independent typed-decision prompts are a separate path | SOURCE_VERIFIED risk | Audit timestamp/symbol exclusion and future-outcome leakage per prompt version; success in guided historical ranking cannot be counted as unseen predictive skill |
| E16 | Owner accepted PG1/PG2 alignment corrections: dedicated 15+ year coverage, fundamentals and controlled-learning goals; 5/20/60 sessions; ACCEPT/REJECT; isolated research simulation and shared paper/live contracts | OWNER SCOPE DECISION / DOCUMENTED_ONLY capabilities | G13–G15 implementation/runtime evidence absent from this documentation review; acceptance of scope is not feature acceptance |
| E17 | V2 coverage/forecast contract separates daily versus intraday/news/fundamental history, listing dates, historical membership, lookback versus forecast, and 60-session label maturity | DOCUMENTED_ONLY | Actual licensed depth, source samples, row-level availability/revisions and sufficient mature outcomes; no claim all 500 companies have 15 years of every data type |
| E18 | V2: 14 paper-first goals weighted to 100, baseline 12.4%; 74 unique subitems with defined references, 24 active relative links and valid SVG XML; documentation-only diff, archive untouched | DOCUMENTATION VERIFIED | G12 excluded/deferred. V1 13% -> V2 12.4% is scope rebaselining, not a model regression; former overall schedule withdrawn pending D5 evidence-based estimates. No application tests or runtime proof implied |

E10 describes the V1 reset's historical working-tree observation. At the V2 documentation update the working tree started clean and the `news/watch` directory was absent; this review neither removed those drafts nor infers their disposition. Check the actual source state before future builds instead of treating the historical note as current inventory.

Package-relative pointers in E03–E09 start at `marketbrain-service/src/main/java/in/marketbrain/`; exact migration and UI files are discoverable from the tracked inventory. Report missing/renamed pointers rather than guessing.

## What we can and cannot conclude now

- Upstox integration must receive explicit credit. Paytm historical-client presence does not mean Paytm live feeds or trading are finished.
- Data collection, technical calculations, prototype labels, notification foundations and experiment tooling are genuine reusable work.
- Source-level safeguards and experiment logs are not live-system certification. Runtime completeness, current database coverage and newest model-comparison performance are unknown until matched evidence is supplied.
- JSON/grammar conformity demonstrates communication reliability for the tested inputs. Java agreement demonstrates rule agreement. Neither proves market opportunity prediction or profitability.
- The previous project scan mapped major paths; it was **not an exhaustive file-by-file, line-by-line review**. G00 retains that limitation rather than asserting an audit that did not happen.

## Evidence-first sequence

1. Freeze the revision and scope. Record tracked/untracked status; do not include or delete the six drafts without an explicit decision. Separate source defects, environment defects and missing business capability.
2. Maintain a source-review coverage manifest for the requested deep audit: path, revision/hash, complete/partial/not-reviewed, reviewer/date, findings and test links. Review all maintained source/configuration/docs; classify binary/generated/vendor assets explicitly. Mark G00 audit complete only when coverage is actually complete.
3. Collect existing spare-laptop run artifacts first. Use run IDs, timestamps, model hashes and deployed Git revision to associate results. Do not rerun expensive inference simply because console progress was lost.
4. Refresh bounded offline tests on the agreed source revision. For data/provider checks, use a small specified symbol/date scope with recorded quota/cost impact; inspect query plans for new broad SQL. Manual import endpoints may write data and are not read-only diagnostics.
5. Collect runtime health **and readiness**: provider access, dataset coverage, source freshness, key failures, storage/restore, and revision/config fingerprint. Never export secrets or the full environment/Compose-resolved configuration.
6. Reconcile evidence against goal checkpoints. An unexpected result opens a defect with reproduction and acceptance criteria; do not adjust thresholds after seeing holdout performance just to pass.

## Compact evidence requested from the owner/operator

Do not send credentials, tokens, full articles without permission, or account-identifying data. Prefer a redacted ZIP containing one summary JSON and one readable log.

| Evidence | Why needed | Scope/cost guard |
|---|---|---|
| Spare-laptop Git revision and deployment timestamp; service health/readiness | Link results to actual deployed code | Read-only; no rebuild required merely to collect it |
| Latest completed comparison/sweep summary, run ID, elapsed timings and failed-case details | Establish actual current model baseline | Reuse existing files; no automatic inference rerun |
| Existing historical/daily coverage report with date range and per-source gaps | Decide which numerical horizons can be trained honestly | Use existing bounded reporting; no unreviewed full-table scan |
| Upstox/Paytm enabled API products, feed limits and auth/egress requirements, with secrets removed | Separate code readiness from account readiness | Documentation/account confirmation first, bounded calls only when authorized |
| Marketaux plan limits and retention rights | Govern ingestion and historical news features | Provider terms/plan evidence; no key needed |
| Frequency-specific 15-year/since-listing coverage and historical constituent mappings | Establish G13 completeness without survivorship or invented history | Existing manifests/sample coverage first; no unbounded paid downloads |
| Licensed financial-statement samples with publication and revision timestamps | Establish G14 feasibility and prevent restatement leakage | Small redacted/permitted samples; do not assume price-data access includes fundamentals |
| Feedback/outcome identifiers and model-version history, when implemented | Separate user preference, forecast correctness and actual versus simulated performance | Reuse persisted records; do not count hypothetical returns as actual fills |
| Backup/restore drill and relevant failure logs | Prove resilience after shutdown | Do not restore over the live dataset; use an isolated authorized drill |

Evidence absence blocks only the affected checkpoint. Portal design, fixtures and safe offline work can progress alongside account verification after implementation authorization.

## Evidence record schema

Every accepted result should identify: evidence ID, goal/subitem, status, Git revision, deployed revision if different, environment, UTC event times (IST display allowed), dataset/split/model/policy versions, command/test scope, expected versus actual result, counts and denominators, elapsed time, artifact paths/hashes, limitations and owner acceptance when applicable.

Never infer total project completion from an intelligence scorecard's `100 - score` field. Use only the [roadmap checkpoints](roadmap.md).

## External primary references

- Upstox streaming contract: [Market Data Feed V3](https://upstox.com/developer/api-documentation/v3/get-market-data-feed/).
- Upstox read-only access option: [Analytics Token](https://upstox.com/developer/api-documentation/analytics-token/).
- Marketaux response/filter reference: [API documentation](https://www.marketaux.com/documentation).
- Paytm account-specific integration entry point: [official developer portal](https://developer.paytmmoney.com/). Detailed current contracts remain to be obtained/verified; older marketing material is not an implementation specification.
