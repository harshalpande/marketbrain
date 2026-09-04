[CmdletBinding()]
param(
    [string]$BaseUrl = 'http://127.0.0.1:8080',
    [string]$OutputDirectory = 'C:\MarketBrainData\Review'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Get-CurrentResolutions {
    param(
        [Parameter(Mandatory = $true)][string]$ApiBaseUrl,
        [Parameter(Mandatory = $true)]$JobId
    )

    $response = Invoke-RestMethod `
        "$ApiBaseUrl/api/v1/market-data/backfills/quality-resolutions?jobId=$JobId"
    return @($response | Where-Object { $null -ne $_ })
}

$health = Invoke-RestMethod "$BaseUrl/actuator/health"
if ($health.status -ne 'UP') {
    throw "MarketBrain health is $($health.status), not UP."
}

$latest = Invoke-RestMethod "$BaseUrl/api/v1/market-data/backfills/latest"
if ($latest.status -ne 'COMPLETED' -or
    $latest.instruments -ne 50 -or
    $latest.completedChunks -ne 750 -or
    $latest.failedChunks -ne 0) {
    throw 'Step 20 requires the completed 50-instrument, 750-chunk backfill.'
}
if ($latest.workerEnabled) {
    throw 'MARKETBRAIN_BACKFILL_WORKER_ENABLED must remain false during Step 20.'
}

$jobId = $latest.jobId
$beforeQuality = Invoke-RestMethod "$BaseUrl/api/v1/market-data/backfills/quality?jobId=$jobId"
$beforeResolutions = @(Get-CurrentResolutions -ApiBaseUrl $BaseUrl -JobId $jobId)

if ($beforeQuality.totalCandles -ne 124858 -or
    $beforeQuality.duplicateRows -ne 0 -or
    $beforeQuality.invalidRows -ne 0 -or
    $beforeQuality.unresolvedFindingCount -ne 331 -or
    $beforeQuality.unresolvedLargeMoveCount -ne 6 -or
    $beforeResolutions.Count -ne 22) {
    throw 'The reviewed Step 19 checkpoint has drifted. No Step 20 analysis was accepted.'
}

$analysis = Invoke-RestMethod `
    "$BaseUrl/api/v1/market-data/backfills/remaining-data-analysis?jobId=$jobId"
$items = @($analysis.items | Where-Object { $null -ne $_ })

if ($analysis.jobId -ne $jobId -or
    $analysis.unresolvedFindingCount -ne $beforeQuality.unresolvedFindingCount -or
    $items.Count -ne $analysis.unresolvedFindingCount) {
    throw 'The analysis does not contain exactly one item for every unresolved finding.'
}
if ($analysis.candlesWritten -or $analysis.resolutionsWritten) {
    throw 'Step 20 unexpectedly reported a database write.'
}
if ($analysis.planHash -notmatch '^[0-9a-f]{64}$') {
    throw 'Step 20 did not produce a valid SHA-256 plan hash.'
}

$afterQuality = Invoke-RestMethod "$BaseUrl/api/v1/market-data/backfills/quality?jobId=$jobId"
$afterResolutions = @(Get-CurrentResolutions -ApiBaseUrl $BaseUrl -JobId $jobId)

if ($afterQuality.totalCandles -ne $beforeQuality.totalCandles -or
    $afterQuality.unresolvedFindingCount -ne $beforeQuality.unresolvedFindingCount -or
    $afterResolutions.Count -ne $beforeResolutions.Count) {
    throw 'Candles, findings, or resolutions changed during the read-only Step 20 analysis.'
}

New-Item -ItemType Directory -Path $OutputDirectory -Force | Out-Null
$outputPath = Join-Path $OutputDirectory "remaining-data-analysis-$jobId.json"
$analysis | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $outputPath -Encoding utf8

[pscustomobject]@{
    Status                              = if ($analysis.analysisComplete) { 'COMPLETED' } else { 'REVIEW_REQUIRED' }
    JobId                               = $jobId
    PlanHash                            = $analysis.planHash
    UnresolvedFindingCount              = $analysis.unresolvedFindingCount
    OfficialSessionFindingCount         = $analysis.officialSessionFindingCount
    PeerSessionFindingCount             = $analysis.peerSessionFindingCount
    CoverageGapFindingCount              = $analysis.coverageGapFindingCount
    LargeMoveFindingCount                = $analysis.largeMoveFindingCount
    SourceRequestCount                   = $analysis.sourceRequestCount
    SecondaryBackfillCandidateCount      = $analysis.secondaryBackfillCandidateCount
    FeatureExclusionCandidateCount       = $analysis.featureExclusionCandidateCount
    ProviderAdjustmentCandidateCount     = $analysis.providerAdjustmentCandidateCount
    VerifiedMoveCandidateCount           = $analysis.verifiedMoveCandidateCount
    KeepOpenCount                        = $analysis.keepOpenCount
    SourceFailureCount                   = $analysis.sourceFailureCount
    CandlesBefore                        = $beforeQuality.totalCandles
    CandlesAfter                         = $afterQuality.totalCandles
    ResolutionsBefore                    = $beforeResolutions.Count
    ResolutionsAfter                     = $afterResolutions.Count
    WorkerEnabled                        = $latest.workerEnabled
    FullPlanPath                         = $outputPath
} | Format-List

Write-Host ''
Write-Host 'Recommendation summary'
$items |
    Group-Object findingType, analysisStatus, recommendedResolutionType |
    Sort-Object Name |
    Select-Object Count, Name |
    Format-Table -AutoSize

$sessionItems = @($items | Where-Object {
    $_.findingType -in @('OFFICIAL_SPECIAL_SESSION', 'PEER_CONFIRMED_SESSION')
})
if ($sessionItems.Count -gt 0) {
    Write-Host ''
    Write-Host 'Missing-session analysis grouped by date'
    $sessionItems |
        Group-Object findingDate, analysisStatus, recommendedResolutionType |
        Sort-Object Name |
        Select-Object Count, Name |
        Format-Table -AutoSize
}

$coverageItems = @($items | Where-Object {
    $_.findingType -in @('LEADING_COVERAGE_GAP', 'TRAILING_COVERAGE_GAP', 'SUSPICIOUS_GAP')
})
if ($coverageItems.Count -gt 0) {
    Write-Host ''
    Write-Host 'Coverage recommendations'
    $coverageItems |
        Sort-Object symbol, findingDate |
        Format-Table symbol, findingType, findingDate, relatedDate, exclusionFrom, exclusionTo,
            recommendedResolutionType -AutoSize
}

$largeMoveItems = @($items | Where-Object { $_.findingType -eq 'LARGE_MOVE' })
if ($largeMoveItems.Count -gt 0) {
    Write-Host ''
    Write-Host 'Remaining large-move recommendations'
    $largeMoveItems |
        Sort-Object symbol, findingDate |
        Format-Table symbol, findingDate, analysisStatus, recommendedResolutionType,
            storedReturnPercent, officialReturnPercent, returnDifferencePercentagePoints -AutoSize
}

$keepOpenItems = @($items | Where-Object { $null -eq $_.recommendedResolutionType })
if ($keepOpenItems.Count -gt 0) {
    Write-Host ''
    Write-Host 'Items that Step 21 must not change'
    $keepOpenItems |
        Sort-Object findingType, symbol, findingDate |
        Format-Table findingType, symbol, findingDate, analysisStatus, detail -Wrap
}

Write-Host ''
if ($analysis.analysisComplete) {
    Write-Host 'STEP 20 COMPLETE: every unresolved finding has one proposed action.'
} else {
    Write-Host 'STEP 20 NEEDS REVIEW: one or more findings remain open or a source request failed.'
}
Write-Host 'No market candle or quality resolution was written. Only the local JSON review file was created.'
Write-Host 'Share this summary before Step 21. Do not edit the JSON or start the next expansion batch.'
