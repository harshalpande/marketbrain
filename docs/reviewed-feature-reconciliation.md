# Reviewed October feature checkpoint reconciliation

The October 8 feature snapshot is saved and verified (E82); do not generate it again. The next step (E83) links that snapshot to the stopped daily automation checkpoint, preserves the old warning and records who approved the reconciliation. It does not enable training or trading.

## Accepted snapshot and remaining checkpoint

[E82 evidence](evidence/reviewed-feature-snapshot-acceptance-20261009.json) confirms 500 stored items, 487 complete vectors, 13 insufficient-history classifications, zero vector violations and an identical recomputed manifest. The run took 104.796 seconds on October 9 for the October 8 trading date. The snapshot reviewer is Harshal Pande; the earlier resolution's confirmation-phrase reviewer caveat remains retained, not corrected retroactively.

The last captured automation row still said REVIEW_REQUIRED / DATABASE_QUALITY. Saving a snapshot manually does not reset that row. E83 reconciles only daily run `eebff875-3621-4064-a2ea-9de0b269681e`, snapshot `fc15cbe7-15c7-46ab-989e-f09ba7978858`, manifest `50e0749dfdfbc3e370f4cd5d0f23069021154bf69baafcc815cffcb509cbbb62` and accepted report SHA256 `128C921E4C21734E9CC0801B39735ECDF9152A43C9906FB3695FEE44ACB62324`. This is not a general retry endpoint or a bypass for other dates/findings.

## Contract and safety boundary

- GET `/api/v1/features/daily-automation/reviewed-reconciliation` verifies scope, existing stored-vector integrity and current stored-data quality without provider calls or feature calculation. It returns READY_TO_RECONCILE or ALREADY_RECONCILED. A changed, active, conflicting or unaudited completed checkpoint fails closed.
- POST to that route requires the pinned `evidenceSha256` and an actual self-declared `reviewedBy`. It rechecks quality, locks the automation row using NOWAIT, and writes an audit plus the COMPLETED checkpoint in one REPEATABLE_READ transaction with a 180-second timeout. It links the already saved snapshot, clears the current error and leaves attempt/count/manifest values unchanged. Previous state/error/attempts/timestamps are preserved in the audit.
- Migration V26 creates only the reconciliation audit table and its UPDATE/DELETE rejection trigger. It does not update existing data on deployment. A unique target date and matching audit make replay read-only. Existing snapshot, raw prices, exclusions, resolution events, model state, signals and orders remain untouched.
- Scope lookup uses the automation unique target date, job/snapshot primary keys and notification unique keys; stored quality is bounded by the selected 500-item snapshot. Current quality audit reuses the existing job-scoped service and its cost is still data-dependent. There is no new unbounded repair or history import. Transaction consistency is not proof that concurrent later source repairs cannot happen; keep data/review jobs idle.
- Service and controller have explicit constructor injection. The public transactional entrypoints are called through Spring proxies; no self-invoked transaction boundary is relied on. Read-only GET never invokes the POST logic with write enabled.

## Telegram behavior

The existing FEATURE_WARNING record must be SENT and is never deleted, reset or resent. After commit, normal automation can discover COMPLETED and deliver a separate FEATURE_COMPLETION notification through the existing durable notice/fanout mechanism. No network delivery occurs inside the reconciliation transaction. Replaying this endpoint does not reset the notification ledger. Delivery can still be pending or fail; neither exactly-once external delivery nor receipt on Telegram is claimed from checkpoint success. The report captures observed notification status. If automation is disabled, delivery waits; this step does not enable it.

## Deploy and run on the spare laptop

Unlike the earlier script-only snapshot step, this change requires rebuilding the service and applying V26 at startup. Confirm all jobs are idle before restarting. Keep the existing `.env` and database; do not prune Docker, reset the database or rerun earlier diagnostics. A deployment transcript is retained for failures; after success share only the compact reconciliation JSON.

```powershell
$ErrorActionPreference = 'Stop'
Set-Location 'C:\Users\Harshal S Pande\Documents\workspace\marketbrain'
if ((Read-Host 'Confirm all MarketBrain processing/review jobs are idle. Type IDLE') -cne 'IDLE') {
    throw 'Cancelled; do not restart an active job.'
}
$branch = git branch --show-current
if ($LASTEXITCODE -ne 0 -or $branch -ne 'main') { throw 'Expected main branch.' }
$changes = @(git status --porcelain)
if ($LASTEXITCODE -ne 0 -or $changes.Count -ne 0) { throw 'Git check failed or local changes exist.' }

$reviewDir = 'C:\MarketBrainData\Review'
[void](New-Item -ItemType Directory -Path $reviewDir -Force)
$deployLog = Join-Path $reviewDir ('feature-reconcile-deploy-' + [guid]::NewGuid().ToString('N') + '.log')
Start-Transcript -Path $deployLog
try {
    git -c maintenance.auto=false -c gc.auto=0 pull --ff-only origin main
    if ($LASTEXITCODE -ne 0) { throw 'Pull failed.' }
    Write-Host '[10%] Checking Compose configuration...'
    docker compose --env-file .env config --quiet
    if ($LASTEXITCODE -ne 0) { throw 'Compose validation failed.' }
    Write-Host '[20%] Building and restarting marketbrain-service only...'
    docker compose --env-file .env up -d --build --no-deps marketbrain-service
    if ($LASTEXITCODE -ne 0) { throw 'Build/deployment failed.' }
    $healthy = $false
    for ($attempt = 1; $attempt -le 30; $attempt++) {
        Write-Host "[80%] Waiting for service and migration: attempt $attempt/30"
        Write-Progress -Activity 'Waiting for MarketBrain' -Status "Attempt $attempt/30" -PercentComplete ([int](100*$attempt/30))
        try {
            $health = Invoke-RestMethod 'http://127.0.0.1:8080/actuator/health' -TimeoutSec 10 -MaximumRedirection 0
            if ($health.status -eq 'UP') { $healthy = $true; break }
        } catch { Write-Host 'Service not ready yet.' }
        if ($attempt -lt 30) { Start-Sleep -Seconds 5 }
    }
    if (-not $healthy) { throw 'Health checks exhausted. Preserve deployment log; do not apply.' }
    Write-Host '[100%] Service is UP. Starting the separately confirmed reconciliation.'
    $parameters = @{
        EvidencePath = 'C:\MarketBrainData\Review\reviewed-feature-snapshot-7b3af00824bc43e6b1b2e00cc84c0529.json'
        ReviewedBy = (Read-Host 'Enter your actual reviewer name')
        Apply = $true
    }
    & '.\ops\windows\ReconcileReviewedOctoberFeatures.ps1' @parameters
} finally {
    Write-Progress -Activity 'Waiting for MarketBrain' -Completed
    Stop-Transcript
    Write-Host "Deployment log retained: $deployLog"
}
```

At the separate prompt type `RECONCILE FEATURES 2026-10-08`. Expected report status: `AUTOMATION_RECONCILED_RELEASE_BLOCKED`. Share the ONE printed `feature-reconciliation-<id>.json`; the transcript is only needed for deployment/startup failures. Stage timings are captured; progress does not pretend a blocked server request has completed.

## Interrupted response or failure

Do not repeat a timed-out POST. Wait until the server is idle and run read-only reconciliation without Apply:

```powershell
& '.\ops\windows\ReconcileReviewedOctoberFeatures.ps1' -EvidencePath 'C:\MarketBrainData\Review\reviewed-feature-snapshot-7b3af00824bc43e6b1b2e00cc84c0529.json'
```

An existing matching completed audit is returned without another write. READY_TO_RECONCILE does not prove an earlier in-flight transaction rolled back; share the report before another Apply. Conflict or failing quality requires review, not a forced status reset. Success closes the October 8 incident checkpoint only; source-policy, prediction and paper-portal gates remain.

## Verification

The PowerShell suite passes 84 mocked assertions covering preview, one confirmed POST, cancellation, exact evidence/scope, malformed flags, failed/readback responses, no snapshot/trade routes and read-only recovery after a lost acknowledgement. Source report guards/digest are replayed independently. The Java suite passes 469 tests (35 new), zero failures/errors/skips. New tests cover scope/state/quality rejection, matching replay, controller mapping/HTTP diagnostic details, audit migration constraints and Spring transaction proxy commit/rollback requests. These use mocked JDBC, not a live database; PostgreSQL migration, row locking and applied reconciliation require spare verification. No provider, model, Docker or application database is used locally.
