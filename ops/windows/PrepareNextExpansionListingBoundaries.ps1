[CmdletBinding()]
param(
    [string]$BaseUrl = 'http://127.0.0.1:8080',
    [ValidateRange(1, 15)]
    [int]$Years = 15,
    [ValidateRange(1, 200)]
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
    $latest.workerEnabled) {
    throw 'Listing enrichment requires a completed expansion batch and a disabled worker.'
}

$previewBefore = Invoke-RestMethod `
    "$BaseUrl/api/v1/market-data/backfills/nifty500/next-batch-preview?years=$Years&batchSize=$BatchSize"
$encodedHash = [uri]::EscapeDataString($previewBefore.manifestHash)

Write-Host 'Downloading NSE listing evidence and checking earlier Upstox history...'
$result = Invoke-RestMethod -Method Post `
    "$BaseUrl/api/v1/market-data/backfills/nifty500/next-batch/listing-boundaries?years=$Years&batchSize=$BatchSize&expectedManifestHash=$encodedHash" `
    -TimeoutSec 3600

New-Item -ItemType Directory -Path $OutputDirectory -Force | Out-Null
$outputPath = Join-Path $OutputDirectory `
    "expansion-batch-$($result.batchNumber)-listing-evidence-$($result.sourceSha256).json"
$result | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $outputPath -Encoding utf8

[pscustomobject]@{
    Status                       = $result.status
    BatchNumber                  = $result.batchNumber
    InputManifestHash            = $result.inputManifestHash
    OutputManifestHash           = $result.outputManifestHash
    SourceSha256                 = $result.sourceSha256
    SourceRecordCount            = $result.sourceRecordCount
    CandidateCount               = $result.candidateCount
    MatchedEvidenceCount         = $result.matchedEvidenceCount
    BeforeRequestWindowCount     = $result.beforeRequestWindowCount
    ExistingBoundaryCount        = $result.existingBoundaryCount
    VerifiedBoundaryCount        = $result.verifiedBoundaryCount
    EarlierProviderHistoryCount  = $result.earlierProviderHistoryCount
    ProviderRequestCount         = $result.providerRequestCount
    ProviderCheckFailureCount    = $result.providerCheckFailureCount
    EvidenceRowsWritten          = $result.evidenceRowsWritten
    BoundariesApplied            = $result.boundariesApplied
    ListingEvidenceComplete      = $result.listingEvidenceComplete
    DatabaseWritesPerformed      = $result.databaseWritesPerformed
    FullEvidencePath             = $outputPath
} | Format-List

Write-Host ''
Write-Host 'Listing-boundary decisions'
$result.items |
    Sort-Object symbol |
    Format-Table symbol, nseReportedListedOn, existingListedOn, providerPrelistingCandleOn, reconciliationStatus, providerRequestCount, boundaryApplied -AutoSize

$classifiedCount = $result.beforeRequestWindowCount +
    $result.existingBoundaryCount +
    $result.verifiedBoundaryCount +
    $result.earlierProviderHistoryCount
if ($result.status -ne 'COMPLETED' -or
    $result.candidateCount -ne $previewBefore.selectedInstruments -or
    $result.matchedEvidenceCount -ne $result.candidateCount -or
    $classifiedCount -ne $result.candidateCount -or
    $result.providerCheckFailureCount -ne 0 -or
    $result.evidenceRowsWritten -ne $result.candidateCount -or
    -not $result.listingEvidenceComplete -or
    -not $result.databaseWritesPerformed -or
    $result.outputManifestHash -notmatch '^[0-9a-f]{64}$') {
    throw 'Listing-boundary enrichment did not pass every reviewed invariant. Do not create the batch.'
}

Write-Host ''
Write-Host 'LISTING-BOUNDARY ENRICHMENT COMPLETE.'
Write-Host 'NSE evidence and reconciled boundaries were written; no backfill job or candle was created.'
Write-Host 'Regenerating the read-only batch manifest now...'
Write-Host ''

& "$PSScriptRoot\PreviewNextExpansionBatch.ps1" `
    -BaseUrl $BaseUrl `
    -Years $Years `
    -BatchSize $BatchSize `
    -OutputDirectory $OutputDirectory
