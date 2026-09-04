[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [ValidatePattern('^[0-9a-fA-F]{64}$')]
    [string]$ReviewedManifestHash,
    [Parameter(Mandatory)]
    [ValidateNotNullOrEmpty()]
    [string]$ReviewedBy,
    [string]$BaseUrl = 'http://127.0.0.1:8080',
    [ValidateRange(1, 15)]
    [int]$Years = 15,
    [ValidateRange(1, 50)]
    [int]$BatchSize = 50,
    [string]$OutputDirectory = 'C:\MarketBrainData\Review'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$normalizedHash = $ReviewedManifestHash.Trim().ToLowerInvariant()
$reviewedPreviewPath = Join-Path $OutputDirectory `
    "expansion-batch-2-preview-$normalizedHash.json"
if (-not (Test-Path -LiteralPath $reviewedPreviewPath -PathType Leaf)) {
    throw "The reviewed Step 24 preview was not found at $reviewedPreviewPath. Do not create the batch."
}

$reviewedReport = Get-Content -LiteralPath $reviewedPreviewPath -Raw | ConvertFrom-Json
$reviewedPreview = $reviewedReport.preview
if ($null -eq $reviewedPreview -or
    $reviewedPreview.manifestHash -ne $normalizedHash -or
    -not $reviewedPreview.listingEvidenceComplete -or
    $reviewedPreview.databaseWritesPerformed) {
    throw 'The saved Step 24 preview does not match the approved manifest or failed its read-only evidence gate.'
}

$health = Invoke-RestMethod "$BaseUrl/actuator/health"
if ($health.status -ne 'UP') {
    throw "MarketBrain health is $($health.status), not UP."
}

$latestBefore = Invoke-RestMethod "$BaseUrl/api/v1/market-data/backfills/latest"
if ($latestBefore.jobType -ne 'EXPANSION' -or
    $latestBefore.status -ne 'COMPLETED' -or
    $latestBefore.failedChunks -ne 0 -or
    $latestBefore.workerEnabled) {
    throw 'Creation requires the completed clean prior expansion batch and a disabled worker.'
}
if ($reviewedReport.prerequisiteJob.jobId -ne $latestBefore.jobId -or
    $reviewedReport.prerequisiteQuality.qualityStatus -ne 'PASS') {
    throw 'The saved preview does not belong to the current completed provider-verified prerequisite batch.'
}

$livePreview = Invoke-RestMethod `
    "$BaseUrl/api/v1/market-data/backfills/nifty500/next-batch-preview?years=$Years&batchSize=$BatchSize"
$liveInstruments = @($livePreview.instruments | Where-Object { $null -ne $_ })
$expectedBatchNumber = [int]$latestBefore.batchNumber + 1
if ($livePreview.manifestHash -ne $normalizedHash -or
    $livePreview.batchNumber -ne $expectedBatchNumber -or
    $livePreview.selectedInstruments -ne $BatchSize -or
    $liveInstruments.Count -ne $livePreview.selectedInstruments -or
    -not $livePreview.listingEvidenceComplete -or
    $livePreview.databaseWritesPerformed) {
    throw 'The live selection differs from the reviewed Step 24 manifest. Preview and review it again.'
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
$createdInstruments = @(
    Invoke-RestMethod "$BaseUrl/api/v1/market-data/backfills/instruments?jobId=$jobId"
)

$manifestMismatchCount = 0
$expectedBySymbol = @{}
foreach ($instrument in $liveInstruments) {
    $expectedBySymbol[$instrument.symbol] = $instrument
}
foreach ($instrument in $createdInstruments) {
    $expected = $expectedBySymbol[$instrument.symbol]
    if ($null -eq $expected -or
        $instrument.providerInstrumentKey -ne $expected.providerInstrumentKey -or
        $instrument.totalChunks -ne $expected.totalChunks) {
        $manifestMismatchCount++
    }
}

$uniqueSymbols = @($createdInstruments.symbol | Sort-Object -Unique)
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
    prerequisiteJob = $latestBefore
    livePreview = $livePreview
    creation = $creation
    verifiedStatus = $status
    instruments = $createdInstruments
} | ConvertTo-Json -Depth 14 | Set-Content -LiteralPath $createdReportPath -Encoding utf8

[pscustomobject]@{
    Status                    = 'CREATED_NOT_STARTED'
    JobId                     = $jobId
    BatchNumber               = $creation.batchNumber
    ReviewedBy                = $ReviewedBy.Trim()
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
Write-Host 'Persisted Batch 2 instruments'
$createdInstruments |
    Sort-Object symbol |
    Format-Table symbol, totalChunks, pendingChunks, runningChunks, retryChunks, completedChunks, failedChunks -AutoSize

Write-Host ''
Write-Host 'STEP 25 COMPLETE: the exact reviewed Batch 2 manifest was created but not started.'
Write-Host 'The worker remains disabled and every chunk remains PENDING.'
Write-Host 'Share this complete output for review. Do not enable the worker or start Batch 2 yet.'
