[CmdletBinding()]
param(
    [string]$BaseUrl = 'http://127.0.0.1:8080',
    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$ReviewedBy,
    [string]$ExpectedPlanHash = '3ea264d124b3618dc793a66677e1b040736d65ad49b230309b60647b1c64b7f8'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$reviewedJobId = 'e1d9ea5d-fcb2-4a81-b839-c154bb602243'
$reviewedPlanHash = '3ea264d124b3618dc793a66677e1b040736d65ad49b230309b60647b1c64b7f8'

if ($ExpectedPlanHash -ne $reviewedPlanHash) {
    throw "ExpectedPlanHash must equal the reviewed Step 20 hash $reviewedPlanHash."
}

$health = Invoke-RestMethod "$BaseUrl/actuator/health"
if ($health.status -ne 'UP') {
    throw "MarketBrain health is $($health.status), not UP."
}

$latest = Invoke-RestMethod "$BaseUrl/api/v1/market-data/backfills/latest"
if ($latest.jobId -ne $reviewedJobId -or
    $latest.status -ne 'COMPLETED' -or
    $latest.instruments -ne 50 -or
    $latest.completedChunks -ne 750 -or
    $latest.failedChunks -ne 0) {
    throw 'The latest backfill is not the exact completed 50-stock job reviewed in Step 20.'
}
if ($latest.workerEnabled) {
    throw 'MARKETBRAIN_BACKFILL_WORKER_ENABLED must remain false during Step 21.'
}

$request = @{
    jobId = $reviewedJobId
    expectedPlanHash = $ExpectedPlanHash
    reviewedBy = $ReviewedBy.Trim()
} | ConvertTo-Json

if ([string]::IsNullOrWhiteSpace($ReviewedBy.Trim())) {
    throw 'ReviewedBy must contain the name of the person who reviewed Step 20.'
}

$result = Invoke-RestMethod `
    -Method Post `
    -Uri "$BaseUrl/api/v1/market-data/backfills/remaining-data-remediation/apply" `
    -ContentType 'application/json' `
    -Body $request `
    -TimeoutSec 900

$result |
    Select-Object status, jobId, planHash, totalItems, pendingItems, completedItems, failedItems,
        secondaryBackfillItems, featureExclusionItems, providerAdjustmentItems,
        secondaryCandlesReady, upstoxDailyCandleCount, secondaryDailyCandleCount,
        allSourceDailyCandleCount, planResolutionsWritten, currentResolutionCount,
        unresolvedFindingCount, workerEnabled, finalProviderSpotCheckRequired |
    Format-List

$failures = @($result.failures | Where-Object { $null -ne $_ })
if ($failures.Count -gt 0) {
    Write-Host ''
    Write-Host 'Failed checkpoints'
    $failures |
        Format-Table symbol, findingType, findingDate, errorCode, detail -Wrap
}

if ($result.jobId -ne $reviewedJobId -or $result.planHash -ne $reviewedPlanHash) {
    throw 'The returned Step 21 identity does not match the reviewed job and plan.'
}
if ($result.workerEnabled) {
    throw 'The backfill worker became enabled during Step 21.'
}
if ($result.status -ne 'COMPLETED') {
    throw 'Step 21 is not complete. Correct only the reported environmental problem, then rerun this same command.'
}
if ($result.totalItems -ne 331 -or
    $result.pendingItems -ne 0 -or
    $result.completedItems -ne 331 -or
    $result.failedItems -ne 0 -or
    $result.secondaryBackfillItems -ne 277 -or
    $result.featureExclusionItems -ne 48 -or
    $result.providerAdjustmentItems -ne 6 -or
    $result.secondaryCandlesReady -ne 277 -or
    $result.upstoxDailyCandleCount -ne 125167 -or
    $result.secondaryDailyCandleCount -ne 277 -or
    $result.allSourceDailyCandleCount -ne 125444 -or
    $result.planResolutionsWritten -ne 331 -or
    $result.currentResolutionCount -ne 353 -or
    $result.unresolvedFindingCount -ne 0) {
    throw 'Step 21 returned COMPLETED, but one or more reviewed final invariants differ.'
}

Write-Host ''
Write-Host 'STEP 21 COMPLETE: all 331 reviewed corrections are durable and all checkpoints passed.'
Write-Host 'The original 125167 raw Upstox candles were not rewritten; 277 NSE BhavCopy candles were added separately.'
Write-Host 'The quality audit uses 124858 Upstox candles inside effective listing and job boundaries.'
Write-Host 'The final live provider spot check is still required before model-training or backtesting eligibility.'
Write-Host 'Do not start expansion batch 2 yet. Share this complete summary for review.'
