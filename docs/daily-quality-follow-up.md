# October 8 daily quality review

Current E82 result: the POLICYBZR resolution and October 8 snapshot are saved; all 500 stored items and their manifest passed verification. The prior resolution reviewer-label caveat remains. Do not repeat the diagnostic, resolution or snapshot POST below. Next use [E83 guarded automation reconciliation](reviewed-feature-reconciliation.md); earlier handoffs remain for traceability.

## Reviewed October snapshot persistence

E80 [acceptance](evidence/policybzr-resolution-acceptance-20261008.json) verifies source SHA256 `91F75E59F91A17696687801CECBCA281EDBA6BD614173E8E982C645B0C6FC69F`, resolution `19bc5ced-9ec0-497b-a2d2-ff86768249cd`, 133.922 seconds, zero unresolved findings, 487 eligible and 13 insufficient-history stocks. The previous `reviewedBy` contains `RESOLVE POLICYBZR 2026-09-24`, not a proper reviewer name. Retain it unchanged; do not silently edit/revoke an append-only audit event. Next approval obtains a separate self-declared actual name and explicitly preserves the caveat. Authentication remains future work.

E81 `SaveReviewedOctoberFeatureSnapshot.ps1` uses only existing loopback endpoints. Default is read-only preview/reconciliation. With `-Apply`, the operator separately confirms scope, with other data collection, repair and review jobs idle. The script verifies the accepted evidence digest and embedded evidence, health, exact current resolution and idle automation, fresh daily quality PASS/500 coverage and both manifests. It requires 487 eligible / 13 withheld, no stale/no-data/quality failures. An existing completed snapshot is read back without another POST. Otherwise it checkpoints intent, sends at most one snapshot POST, and verifies persisted quality: 500 items, 487 complete vectors, 13 withheld, zero partial/withheld-vector violations and recomputed manifest equality. Stage progress and request timings are saved in ONE unique JSON, including partial failures.

No raw candle, exclusion, resolution, model, signal, order or scheduler changes. The existing server endpoint writes the feature run and its items transactionally; `expectedManifestHash` rejects feature drift. Client fresh quality checks are not an atomic server compare-and-set. The shared local review mutex protects only the same Windows session; single-operator/no-concurrent-jobs remains required. HTTP timeout does not prove server cancellation. No new SQL, Spring beans, migrations or application build is introduced.

### Run on spare laptop

Keep the existing service running. This is pull-only: no Docker rebuild or restart. Supply the accepted report file, not a regenerated diagnostic. Run in PowerShell:

```powershell
$ErrorActionPreference = 'Stop'
Set-Location 'C:\Users\Harshal S Pande\Documents\workspace\marketbrain'
$branch = git branch --show-current
if ($LASTEXITCODE -ne 0 -or $branch -ne 'main') { throw 'Expected main branch; stop and review.' }
if (@(git status --porcelain).Count -ne 0) { throw 'Working tree has changes; stop and review them.' }
if ($LASTEXITCODE -ne 0) { throw 'Git status failed.' }
git -c maintenance.auto=false -c gc.auto=0 pull --ff-only origin main
if ($LASTEXITCODE -ne 0) { throw 'Git pull failed; do not continue.' }

$parameters = @{
    EvidencePath = 'C:\MarketBrainData\Review\policybzr-reviewed-resolution-2798223d024e493b8dc060a828532a6c.json'
    ReviewedBy = (Read-Host 'Enter your actual name, NOT the confirmation phrase')
    Apply = $true
}
& '.\ops\windows\SaveReviewedOctoberFeatureSnapshot.ps1' @parameters
```

At the separate confirmation prompt type `PERSIST FEATURES 2026-10-08`. Success is `FEATURE_SNAPSHOT_VERIFIED_RELEASE_BLOCKED`, not trading readiness. Share the one printed `reviewed-feature-snapshot-<id>.json`. The request limits are 660 seconds for fresh preview, 900 for persistence and 180 for persisted quality; these are ceilings, not measured runtime promises. Progress is per completed stage, not a fabricated percentage during a server request.

### Uncertain write or failed verification

If the write timed out, or stored quality failed, preserve the report and wait until the server operation is known idle. Do not automatically rerun with Apply. Read-only reconciliation uses the same evidence:

```powershell
& '.\ops\windows\SaveReviewedOctoberFeatureSnapshot.ps1' -EvidencePath 'C:\MarketBrainData\Review\policybzr-reviewed-resolution-2798223d024e493b8dc060a828532a6c.json'
```

`PREVIEW_READY_NO_WRITE` means no matching completed snapshot was established; it is not proof an earlier in-flight operation rolled back. Share the report before another write. An existing conflicting/incomplete snapshot, changed manifest or new quality blocker stops the script. A verified snapshot does not repair the old REVIEW_REQUIRED automation row or send a fresh Telegram completion; reconcile that workflow separately after this evidence is reviewed.

### Verification and remaining gates

Offline `TestReviewedOctoberFeatureSnapshot.ps1`: 137 assertions using synthetic fixtures and mocked HTTP, confirmation and digest. Covers preview/apply/cancel, identity and manifest drift, active automation, conflict, before-write race, name validation, encoded reviewer query, lost acknowledgement, read-only recovery, partial/mismatched quality and one-file reporting. Resolution regression suite: 59 assertions. Actual supplied report guard/digest replayed separately. Runtime persistence is pending spare evidence. No local application, database, provider or model is run.

Eight existing Java service/controller/preview tests also pass with mocked dependencies; no Java changes or connected-database verification are claimed.

97.4% feature availability is not predictive accuracy. The 13 short-history stocks remain withheld; no synthetic backfill is created. Upstox source policy, original information availability, numerical validation and full paper-portal integration remain separate gates. Neither the individual finding's legacy `allowsTraining` flag nor TECHNICAL_V1's cutoff flag establishes permission to fit or trade.

## Accepted diagnostic and guarded resolution

E78 [accepted the spare follow-up](evidence/daily-quality-follow-up-acceptance-20261008.json): 155.008 seconds, all five requests returned. NSE UDIFF comparison matched POLICYBZR by ISIN/EQ with exactly the stored previous close and close, zero differences. All 13 withheld stocks have fewer than 252 eligible observations (198-245), none are stale or absent, and the feature manifest is unchanged. Do not repeat the diagnostic or invent missing history. The saved report includes parsed official evidence and source URL, not the original archive bytes. Empty corporate-action hints are not a proof of absence.

Owner authorized the next scoped handoff. E79 `ResolveReviewedPolicyBzrMove.ps1` previews by default; `-Apply` plus typing `RESOLVE POLICYBZR 2026-09-24` appends exactly one `VERIFIED_EXCHANGE_MOVE` event through the existing API, with the named reviewer, exact source URL and accepted report SHA256 in its notes. It does not update candles or add an exclusion. The legacy `allowsTraining` flag becomes true for this individual finding; it does not authorize fitting or waive broader source-policy, rights, point-in-time or evaluation gates.

The default evidence path is the exact accepted `daily-quality-follow-up-2026-10-08-fb41949416494625817181ede0b86c55.json` under `C:\MarketBrainData\Review`. Pass `-EvidencePath` only if that same file was moved. SHA256 is pinned to `190CE4143E39B84AADC14B34570E2278D7AB60F78448BEB2D81A0FB9910B4349`; a mismatch stops before HTTP. Do not substitute a newly generated report. The script embeds the accepted evidence, body, responses, request timings and write state in one uniquely named `policybzr-reviewed-resolution-*.json`.

Before writing it verifies the exact run/manifest, current resolution, stopped REVIEW_REQUIRED automation and fresh database audit: same price pair, only the single open finding, no new corporate-action hints or quality blockers. It rechecks current resolution after confirmation. Exact already-applied payloads are read back without another POST; conflicting or multiple resolutions stop without revocation. No Upstox/NSE refetch, import, model, feature snapshot, signal, order or scheduler reset is requested.

Run one copy only, with no other quality reviewers, feature jobs or data repairs operating concurrently. A local named mutex blocks another copy in the same Windows session, not other sessions/hosts or API clients. The existing server endpoint checks before insertion but has no atomic evidence-bound compare-and-set; this script is not a general concurrent write protocol. Human-reviewed single-writer operation is a prerequisite, not a claim that a client precheck eliminates every race.

Intent is checkpointed as `UNKNOWN_PENDING_RECONCILIATION` before the only POST. A timeout, malformed acknowledgement or interrupted client may still mean the event committed. Never retry with `-Apply` blindly: run without `-Apply` to read the current record first and share the report. If no record appears, that alone does not authorize repeating an uncertain in-flight write. No rollback or price repair is automatic. API calls have explicit limits (15-second health, 30-second metadata/write/readback, 180-second audit, 660-second feature preview), no HTTP redirects and no request retries. Client timeout does not guarantee server cancellation.

After verifying persistence, the script performs only a daily automation preview. Expected successful outcome: `RESOLUTION_VERIFIED_FEATURE_READY_NOT_PERSISTED`, with 487 eligible and 13 short-history instruments and the same manifest. Other blockers remain `RESOLUTION_VERIFIED_FEATURE_REVIEW_REQUIRED`; a preview failure does not undo a recorded resolution. `REVIEW_REQUIRED` automation is not automatically reclaimed by the scheduler. Feature persistence/requeue is a separate next action after report review; a warning Telegram message will not be retroactively replaced by this script.

Verification: 59 offline PowerShell 5.1 assertions cover preview/apply/cancel, exact existing record, conflict, changed evidence digest, active automation, changed prices/action hints, one-POST limit, simulated commit with lost acknowledgement followed by read-only reconciliation, remaining feature blockers and preview failure after a verified write. HTTP, confirmation and fixture digest are mocked; the actual accepted attachment also passes the evidence guards independently. No real resolution has been written locally, no Java source changed, no app rebuild needed. Spare write/readiness outcome remains pending.

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

E77: 70 offline PowerShell 5.1 assertions with HTTP mocked verify expected collection, single-file partial reporting, wrong/widened job scope, unsafe/missing flags, duplicate symbols, future dates, inconsistent counts, insufficient-history classification, changed manifest, timeout, source outage and attempted resolution-write rejection. No real service/provider/database/model was called locally. E78 above closes the spare diagnostic checkpoint; E79 resolution remains pending.

E76 separately closes the isolated PostgreSQL checkpoint: 24/24 passed, 18m44s end to end, exact account reconciliation and cleanup reviewed. Do not repeat it. Paper application integration, migration, authenticated approvals, realistic fills and portal remain pending. Neither result improves measured predictive accuracy or completes G08 as a whole.
