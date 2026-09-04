[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [ValidatePattern('^[0-9a-fA-F]{64}$')]
    [string]$ReviewedManifestHash,
    [Parameter(Mandatory)]
    [ValidateNotNullOrEmpty()]
    [string]$ReviewedBy,
    [ValidateRange(1, 500)]
    [int]$BatchNumber = 2,
    [string]$BaseUrl = 'http://127.0.0.1:8080',
    [ValidateRange(1, 15)]
    [int]$Years = 15,
    [ValidateRange(1, 200)]
    [int]$BatchSize = 50,
    [string]$OutputDirectory = 'C:\MarketBrainData\Review'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$normalizedHash = $ReviewedManifestHash.Trim().ToLowerInvariant()
$reviewedPreviewPath = Join-Path $OutputDirectory `
    "expansion-batch-$BatchNumber-preview-$normalizedHash.json"
if (-not (Test-Path -LiteralPath $reviewedPreviewPath -PathType Leaf)) {
    throw "The reviewed Batch $BatchNumber preview was not found at $reviewedPreviewPath. Do not create the batch."
}

$reviewedReport = Get-Content -LiteralPath $reviewedPreviewPath -Raw | ConvertFrom-Json
$reviewedPreview = $reviewedReport.preview
$reviewedInstruments = @($reviewedPreview.instruments | ForEach-Object { $_ })
if ($null -eq $reviewedPreview -or
    $reviewedPreview.manifestHash -ne $normalizedHash -or
    $reviewedPreview.batchNumber -ne $BatchNumber -or
    $reviewedPreview.selectedInstruments -lt 1 -or
    $reviewedPreview.selectedInstruments -gt $BatchSize -or
    $reviewedInstruments.Count -ne $reviewedPreview.selectedInstruments -or
    -not $reviewedPreview.listingEvidenceComplete -or
    $reviewedPreview.databaseWritesPerformed) {
    throw "The saved Batch $BatchNumber preview does not match the approved manifest or failed its read-only evidence gate."
}

$health = Invoke-RestMethod "$BaseUrl/actuator/health"
if ($health.status -ne 'UP') {
    throw "MarketBrain health is $($health.status), not UP."
}

$latestAtStart = Invoke-RestMethod "$BaseUrl/api/v1/market-data/backfills/latest"
if ($latestAtStart.workerEnabled) {
    throw 'MARKETBRAIN_BACKFILL_WORKER_ENABLED must remain false during reviewed batch creation.'
}
$prerequisiteChecks = @(
    $reviewedReport.prerequisiteQuality.providerSpotChecks |
        Where-Object { $null -ne $_ }
)
$prerequisiteNonMatches = @(
    $prerequisiteChecks | Where-Object { $_.status -ne 'MATCHED' }
)
if ($reviewedReport.prerequisiteQuality.qualityStatus -ne 'PASS' -or
    $reviewedReport.prerequisiteQuality.jobId -ne $reviewedReport.prerequisiteJob.jobId -or
    $reviewedReport.prerequisiteQuality.instrumentCount -ne $reviewedReport.prerequisiteJob.instruments -or
    $reviewedReport.prerequisiteJob.status -ne 'COMPLETED' -or
    $reviewedReport.prerequisiteJob.failedChunks -ne 0 -or
    -not $reviewedReport.prerequisiteQuality.providerSpotCheckRequested -or
    $prerequisiteChecks.Count -ne $reviewedReport.prerequisiteQuality.instrumentCount -or
    $prerequisiteNonMatches.Count -ne 0 -or
    $reviewedReport.prerequisiteQuality.providerMismatchCount -ne 0 -or
    $reviewedReport.prerequisiteQuality.providerCheckFailureCount -ne 0 -or
    -not $reviewedReport.prerequisiteQuality.modelTrainingEligible -or
    -not $reviewedReport.prerequisiteQuality.backtestingEligible) {
    throw 'The saved preview does not belong to the current completed provider-verified prerequisite batch.'
}

$recoveredExistingJob = $false
$livePreview = $reviewedPreview
$liveInstruments = $reviewedInstruments

if ($latestAtStart.jobType -eq 'EXPANSION' -and
    $latestAtStart.batchNumber -eq $reviewedPreview.batchNumber -and
    $latestAtStart.status -eq 'CREATED') {
    # A previous request can succeed before its local post-creation checks are displayed.
    # Recover that exact inactive checkpoint read-only; never issue a second creation request.
    $recoveredExistingJob = $true
    $jobId = $latestAtStart.jobId
    $status = $latestAtStart
    $latestAfter = $latestAtStart
    $creation = [pscustomobject]@{
        job = $status
        batchNumber = $reviewedPreview.batchNumber
        selectedInstruments = $reviewedPreview.selectedInstruments
        remainingInstrumentsAfterBatch = $reviewedPreview.remainingInstrumentsAfterBatch
        maximumBatchSize = $reviewedPreview.maximumBatchSize
        manifestHash = $normalizedHash
        detail = 'Recovered and verified the already-created inactive batch; no creation request was sent.'
    }
} else {
    if ($latestAtStart.jobType -ne 'EXPANSION' -or
        $latestAtStart.status -ne 'COMPLETED' -or
        $latestAtStart.failedChunks -ne 0) {
        throw 'Creation requires the completed clean prior expansion batch, or the matching inactive batch for recovery.'
    }
    if ($reviewedReport.prerequisiteJob.jobId -ne $latestAtStart.jobId) {
        throw 'The saved preview does not belong to the current completed prerequisite batch.'
    }

    $livePreview = Invoke-RestMethod `
        "$BaseUrl/api/v1/market-data/backfills/nifty500/next-batch-preview?years=$Years&batchSize=$BatchSize"
    $liveInstruments = @($livePreview.instruments | ForEach-Object { $_ })
    $expectedBatchNumber = [int]$latestAtStart.batchNumber + 1
    if ($livePreview.manifestHash -ne $normalizedHash -or
        $livePreview.batchNumber -ne $expectedBatchNumber -or
        $livePreview.batchNumber -ne $BatchNumber -or
        $livePreview.selectedInstruments -ne $reviewedPreview.selectedInstruments -or
        $livePreview.remainingInstrumentsAfterBatch -ne $reviewedPreview.remainingInstrumentsAfterBatch -or
        $livePreview.totalChunks -ne $reviewedPreview.totalChunks -or
        $liveInstruments.Count -ne $livePreview.selectedInstruments -or
        -not $livePreview.listingEvidenceComplete -or
        $livePreview.databaseWritesPerformed) {
        throw "The live selection differs from the reviewed Batch $BatchNumber manifest. Preview and review it again."
    }

    $calculatedChunks = ($liveInstruments | Measure-Object -Property totalChunks -Sum).Sum
    if ($calculatedChunks -ne $livePreview.totalChunks) {
        throw 'The live manifest chunk total is inconsistent. Do not create the batch.'
    }

    $encodedHash = [uri]::EscapeDataString($normalizedHash)
    $creation = Invoke-RestMethod -Method Post `
        "$BaseUrl/api/v1/market-data/backfills/nifty500/next-batch?years=$Years&batchSize=$BatchSize&expectedManifestHash=$encodedHash"

    $jobId = $creation.job.jobId
    $status = Invoke-RestMethod "$BaseUrl/api/v1/market-data/backfills/status?jobId=$jobId"
    $latestAfter = Invoke-RestMethod "$BaseUrl/api/v1/market-data/backfills/latest"
}

$createdPayload = Invoke-RestMethod `
    "$BaseUrl/api/v1/market-data/backfills/instruments?jobId=$jobId"
$createdInstruments = @($createdPayload | ForEach-Object { $_ })

$manifestMismatchCount = 0
$expectedBySymbol = @{}
foreach ($instrument in $liveInstruments) {
    if ($null -eq $instrument.PSObject.Properties['symbol']) {
        throw 'The reviewed preview contains an instrument without a symbol property.'
    }
    $expectedBySymbol[$instrument.symbol] = $instrument
}
foreach ($instrument in $createdInstruments) {
    if ($null -eq $instrument.PSObject.Properties['symbol']) {
        throw 'The created-instrument response contains an item without a symbol property.'
    }
    $expected = $expectedBySymbol[$instrument.symbol]
    if ($null -eq $expected -or
        $instrument.providerInstrumentKey -ne $expected.providerInstrumentKey -or
        $instrument.totalChunks -ne $expected.totalChunks) {
        $manifestMismatchCount++
    }
}

$uniqueSymbols = @(
    $createdInstruments |
        ForEach-Object { $_.symbol } |
        Sort-Object -Unique
)
$createdChunkTotal = ($createdInstruments | Measure-Object -Property totalChunks -Sum).Sum
$nonPendingInstrumentCount = @(
    $createdInstruments | Where-Object {
        $_.pendingChunks -ne $_.totalChunks -or
        $_.runningChunks -ne 0 -or
        $_.retryChunks -ne 0 -or
        $_.completedChunks -ne 0 -or
        $_.failedChunks -ne 0
    }
).Count

if ($creation.manifestHash -ne $normalizedHash -or
    $creation.batchNumber -ne $livePreview.batchNumber -or
    $creation.selectedInstruments -ne $livePreview.selectedInstruments -or
    $creation.remainingInstrumentsAfterBatch -ne $livePreview.remainingInstrumentsAfterBatch -or
    $status.jobId -ne $jobId -or
    $status.jobType -ne 'EXPANSION' -or
    $status.batchNumber -ne $livePreview.batchNumber -or
    $status.status -ne 'CREATED' -or
    $status.fromDate -ne $livePreview.requestedFrom -or
    $status.toDate -ne $livePreview.requestedTo -or
    $status.instruments -ne $livePreview.selectedInstruments -or
    $status.totalChunks -ne $livePreview.totalChunks -or
    $status.pendingChunks -ne $status.totalChunks -or
    $status.runningChunks -ne 0 -or
    $status.retryChunks -ne 0 -or
    $status.completedChunks -ne 0 -or
    $status.failedChunks -ne 0 -or
    $status.acceptedRows -ne 0 -or
    $status.rejectedRows -ne 0 -or
    $status.workerEnabled -or
    $latestAfter.jobId -ne $jobId -or
    $latestAfter.status -ne 'CREATED' -or
    $createdInstruments.Count -ne $livePreview.selectedInstruments -or
    $uniqueSymbols.Count -ne $createdInstruments.Count -or
    $createdChunkTotal -ne $livePreview.totalChunks -or
    $manifestMismatchCount -ne 0 -or
    $nonPendingInstrumentCount -ne 0) {
    throw 'The batch was created, but one or more post-creation invariants differ. Keep the worker disabled and investigate.'
}

New-Item -ItemType Directory -Path $OutputDirectory -Force | Out-Null
$createdReportPath = Join-Path $OutputDirectory `
    "expansion-batch-$($creation.batchNumber)-created-$jobId.json"
[pscustomobject]@{
    createdAt = (Get-Date).ToUniversalTime().ToString('o')
    reviewedBy = $ReviewedBy.Trim()
    reviewedPreviewPath = $reviewedPreviewPath
    reviewedManifestHash = $normalizedHash
    recoveredExistingJob = $recoveredExistingJob
    prerequisiteJob = $reviewedReport.prerequisiteJob
    livePreview = $livePreview
    creation = $creation
    verifiedStatus = $status
    instruments = $createdInstruments
} | ConvertTo-Json -Depth 14 | Set-Content -LiteralPath $createdReportPath -Encoding utf8

[pscustomobject]@{
    Status                    = if ($recoveredExistingJob) {
        'RECOVERED_CREATED_NOT_STARTED'
    } else {
        'CREATED_NOT_STARTED'
    }
    JobId                     = $jobId
    BatchNumber               = $creation.batchNumber
    ReviewedBy                = $ReviewedBy.Trim()
    RecoveredExistingJob      = $recoveredExistingJob
    ManifestHash              = $creation.manifestHash
    SelectedInstruments       = $creation.selectedInstruments
    RemainingAfterBatch       = $creation.remainingInstrumentsAfterBatch
    TotalChunks               = $status.totalChunks
    PendingChunks             = $status.pendingChunks
    RunningChunks             = $status.runningChunks
    CompletedChunks           = $status.completedChunks
    FailedChunks              = $status.failedChunks
    ListingEvidenceComplete   = $livePreview.listingEvidenceComplete
    ManifestMismatchCount     = $manifestMismatchCount
    NonPendingInstrumentCount = $nonPendingInstrumentCount
    WorkerEnabled             = $status.workerEnabled
    FullCreationPath          = $createdReportPath
} | Format-List

Write-Host ''
Write-Host "Persisted Batch $BatchNumber instruments"
$createdInstruments |
    Sort-Object symbol |
    Format-Table symbol, totalChunks, pendingChunks, runningChunks, retryChunks, completedChunks, failedChunks -AutoSize

Write-Host ''
if ($recoveredExistingJob) {
    Write-Host "BATCH $BatchNumber CREATION RECOVERED: the existing inactive checkpoint matches the exact reviewed manifest."
} else {
    Write-Host "BATCH $BatchNumber CREATION COMPLETE: the exact reviewed manifest was created but not started."
}
Write-Host 'The worker remains disabled and every chunk remains PENDING.'
Write-Host "Share this complete output for review. Do not enable the worker or start Batch $BatchNumber yet."
