[CmdletBinding()]
param(
    [string]$BaseUrl = 'http://127.0.0.1:8080',
    [ValidateRange(1, 15)]
    [int]$Years = 15,
    [ValidateRange(1, 50)]
    [int]$BatchSize = 50,
    [string]$OutputDirectory = 'C:\MarketBrainData\Review'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$health = Invoke-RestMethod "$BaseUrl/actuator/health"
if ($health.status -ne 'UP') {
    throw "MarketBrain health is $($health.status), not UP."
}

$latest = Invoke-RestMethod "$BaseUrl/api/v1/market-data/backfills/latest"
if ($latest.jobType -ne 'EXPANSION' -or
    $latest.status -ne 'COMPLETED' -or
    $latest.failedChunks -ne 0 -or
    $latest.instruments -lt 1) {
    throw 'The latest expansion batch is not complete and clean.'
}
if ($latest.workerEnabled) {
    throw 'MARKETBRAIN_BACKFILL_WORKER_ENABLED must remain false while previewing the next batch.'
}

Write-Host 'Revalidating the completed batch before selecting any additional stocks...'
$quality = Invoke-RestMethod `
    "$BaseUrl/api/v1/market-data/backfills/quality?jobId=$($latest.jobId)&providerSpotCheck=true" `
    -TimeoutSec 900
$checks = @($quality.providerSpotChecks | Where-Object { $null -ne $_ })
$nonMatches = @($checks | Where-Object { $_.status -ne 'MATCHED' })

if ($quality.qualityStatus -ne 'PASS' -or
    $quality.instrumentCount -ne $latest.instruments -or
    $quality.blockingInstrumentCount -ne 0 -or
    $quality.missingProviderDataInstrumentCount -ne 0 -or
    $quality.reviewInstrumentCount -ne 0 -or
    $quality.duplicateRows -ne 0 -or
    $quality.invalidRows -ne 0 -or
    $quality.unresolvedFindingCount -ne 0 -or
    $quality.truncatedFindingCount -ne 0 -or
    -not $quality.providerSpotCheckRequested -or
    $checks.Count -ne $quality.instrumentCount -or
    $nonMatches.Count -ne 0 -or
    $quality.providerMismatchCount -ne 0 -or
    $quality.providerCheckFailureCount -ne 0 -or
    -not $quality.modelTrainingEligible -or
    -not $quality.backtestingEligible) {
    throw 'The completed batch no longer passes its provider-backed quality gate. Do not preview or create another batch.'
}

$preview = Invoke-RestMethod `
    "$BaseUrl/api/v1/market-data/backfills/nifty500/next-batch-preview?years=$Years&batchSize=$BatchSize"
$instruments = @($preview.instruments | Where-Object { $null -ne $_ })
$uniqueSymbols = @($instruments.symbol | Sort-Object -Unique)
$expectedBatchNumber = [int]$latest.batchNumber + 1

if ($preview.batchNumber -ne $expectedBatchNumber -or
    $preview.selectedInstruments -lt 1 -or
    $preview.selectedInstruments -gt $BatchSize -or
    $instruments.Count -ne $preview.selectedInstruments -or
    $uniqueSymbols.Count -ne $instruments.Count -or
    @($instruments | Where-Object { $_.totalChunks -lt 1 }).Count -ne 0 -or
    $preview.manifestHash -notmatch '^[0-9a-f]{64}$' -or
    $preview.databaseWritesPerformed) {
    throw 'The next-batch preview failed one or more manifest invariants.'
}

$calculatedChunks = ($instruments | Measure-Object -Property totalChunks -Sum).Sum
if ($preview.totalChunks -ne $calculatedChunks) {
    throw 'The preview total chunk count does not equal the instrument manifest.'
}

$latestAfter = Invoke-RestMethod "$BaseUrl/api/v1/market-data/backfills/latest"
if ($latestAfter.jobId -ne $latest.jobId -or
    $latestAfter.status -ne $latest.status -or
    $latestAfter.completedChunks -ne $latest.completedChunks -or
    $latestAfter.acceptedRows -ne $latest.acceptedRows) {
    throw 'The read-only preview unexpectedly changed the latest backfill checkpoint.'
}

New-Item -ItemType Directory -Path $OutputDirectory -Force | Out-Null
$outputPath = Join-Path $OutputDirectory `
    "expansion-batch-$($preview.batchNumber)-preview-$($preview.manifestHash).json"
[pscustomobject]@{
    generatedAt = (Get-Date).ToUniversalTime().ToString('o')
    prerequisiteJob = $latest
    prerequisiteQuality = $quality
    preview = $preview
} | ConvertTo-Json -Depth 14 | Set-Content -LiteralPath $outputPath -Encoding utf8

[pscustomobject]@{
    Status                         = 'REVIEW_REQUIRED'
    CompletedBatchJobId            = $latest.jobId
    CompletedBatchNumber           = $latest.batchNumber
    CompletedBatchQualityStatus    = $quality.qualityStatus
    CompletedBatchProviderChecks   = $checks.Count
    NextBatchNumber                = $preview.batchNumber
    Years                          = $preview.years
    RequestedFrom                  = $preview.requestedFrom
    RequestedTo                    = $preview.requestedTo
    SelectedInstruments            = $preview.selectedInstruments
    RemainingInstrumentsAfterBatch = $preview.remainingInstrumentsAfterBatch
    TotalChunks                    = $preview.totalChunks
    ManifestHash                   = $preview.manifestHash
    DatabaseWritesPerformed        = $preview.databaseWritesPerformed
    WorkerEnabled                  = $latest.workerEnabled
    FullPreviewPath                = $outputPath
} | Format-List

Write-Host ''
Write-Host 'Proposed next-batch instruments'
$instruments |
    Sort-Object symbol |
    Format-Table symbol, providerInstrumentKey, listedOn, effectiveFrom, totalChunks -AutoSize

Write-Host ''
Write-Host 'NEXT EXPANSION BATCH PREVIEW COMPLETE.'
Write-Host 'No backfill job, chunk, candle, finding, or resolution was written.'
Write-Host 'Share this complete output for review. Do not create or start the batch yet.'
