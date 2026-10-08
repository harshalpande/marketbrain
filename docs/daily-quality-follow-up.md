# October 8 daily quality review

The daily collection completed, but the feature snapshot remains blocked by one open POLICYBZR large-move finding. Review the exact finding and the withheld feature classifications without importing history, changing prices, writing resolutions or restarting automation.

## Accepted evidence and open questions

- Input `daily-quality-diagnostic-2026-10-08-369f62ae337f4ce595bf124565d9e4bc.json`, SHA256 `230A527C2F8399290FCF4DB8A8D309D4BA848DF275461986A323631A84080122`, captured October 8 at 11:44:46 UTC.
- Daily run `eebff875-3621-4064-a2ea-9de0b269681e`: September 19 through October 8, 500 instruments, 6,500 accepted candles and no rejected rows. Audit reports 499 PASS and one REVIEW; no duplicates, invalid rows or unresolved session gaps. This is scoped collection/quality evidence, not certification of the full historical dataset.
- POLICYBZR on September 24: previous close INR1,886.30, close INR1,207.20, absolute move 36.0017%; 20% review threshold. The finding is OPEN. Do not change the price or threshold based only on its size.
- Automation recorded 487 eligible and 13 withheld instruments, no feature snapshot run ID. Individual reasons were absent. TECHNICAL_V1 requires at least 252 nonexcluded daily observations; the new report distinguishes insufficient history, stale and absent data instead of assuming all 13 have the same cause.
- An October 8 web search returned matching price/date values for the [NSE quote page](https://www.nseindia.com/get-quote/equity/POLICYBZR/PB-Fintech-Limited), but opening it returned only an unpopulated page and a direct archive attempt was inaccessible. Search-index corroboration is a lead, not retained official archive evidence or permission to resolve the finding. No corporate-action explanation is established.

## One report handoff

Run `ops/windows/GetDailyQualityFollowUp.ps1` on spare after pulling. No Docker rebuild, application restart, model run or old persistence-suite rerun is needed. The script deliberately binds this reviewed incident, not arbitrary jobs or dates.

Five sequential GET requests: health, exact daily run metadata, database-only quality audit (`providerSpotCheck=false`), one all-500 universe feature preview, and POLICYBZR large-move evidence. The last endpoint reads NSE Bhavcopy through the existing Java client; it does not contact Upstox or import archive data. Before that call, the fresh audit must still contain exactly the reviewed POLICYBZR date and price pair. Response scope and no-resolution-write flags are checked again. The endpoint repeats its audit internally; a concurrent data change is not an atomic snapshot and will require review, not acceptance.

The quality query is constrained to the reviewed 20-calendar-day job. The existing universe preview streams historical candles in one bulk query with fetch size 1,000 and a 600-second statement timeout; it is not row-bounded to 252 and can take several minutes. HTTP limits are 15/30/180/660/180 seconds, respectively. No automatic retry. A client timeout does not guarantee server query cancellation; preserve the partial report and do not immediately launch another copy. Run only one collector at a time, outside heavy validation jobs. Existing daily scheduling is not modified.

Progress shows actual completed stages and the current request limit, not fabricated progress within a database query. One uniquely named `daily-quality-follow-up-2026-10-08-<id>.json` checkpoints responses, request timings, classifications, withholding details, manifest comparison, official source status and partial failures. A changed feature manifest is disclosed rather than silently equated to the earlier automation attempt. No attached text is executed. Loopback HTTP only, redirects disabled, no credentials collected.

Expected collection status is `CAPTURED_REVIEW_REQUIRED`, including when NSE reports source unavailability or a price mismatch. It means evidence collection finished, not data acceptance. Review `officialEvidence.findings[].evidenceStatus`, source URL, identity/date, both prices, corporate-action hints and withholding reasons. A verified move may warrant a separately reviewed append-only resolution; a mismatch or unavailable source stays open. Exclusion windows or price repairs require explicit evidence and scoped approval. After a resolution, preview readiness before any separately approved feature persistence/retry. Do not infer the runtime scheduler will retry REVIEW_REQUIRED automatically.

The existing preview's `pointInTimeSafe` flag means its date-filtered technical contract; it does not settle historical receipt-time availability, survivorship, corporate-action policy, rights or numerical training eligibility.

## Verification and next work

E77: 70 offline PowerShell 5.1 assertions with HTTP mocked verify expected collection, single-file partial reporting, wrong/widened job scope, unsafe/missing flags, duplicate symbols, future dates, inconsistent counts, insufficient-history classification, changed manifest, timeout, source outage and attempted resolution-write rejection. No real service/provider/database/model was called locally. Spare report pending.

E76 separately closes the isolated PostgreSQL checkpoint: 24/24 passed, 18m44s end to end, exact account reconciliation and cleanup reviewed. Do not repeat it. Paper application integration, migration, authenticated approvals, realistic fills and portal remain pending. Neither result improves measured predictive accuracy or completes G08 as a whole.
