[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [ValidateNotNullOrEmpty()]
    [string]$ReviewedBy,
    [Parameter(Mandatory)]
    [ValidateNotNull()]
    [guid]$JobId,
    [Parameter(Mandatory)]
    [ValidatePattern('^[0-9a-fA-F]{64}$')]
    [string]$ReviewedManifestHash,
    [Parameter(Mandatory)]
    [ValidatePattern('^[0-9a-fA-F]{64}$')]
    [string]$ExpectedPlanHash,
    [string]$BaseUrl = 'http://127.0.0.1:8080',
    [string]$OutputDirectory = 'C:\MarketBrainData\Review'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$normalizedManifestHash = $ReviewedManifestHash.Trim().ToLowerInvariant()
$normalizedPlanHash = $ExpectedPlanHash.Trim().ToLowerInvariant()
$reviewer = $ReviewedBy.Trim()
if ([string]::IsNullOrWhiteSpace($reviewer)) {
    throw 'ReviewedBy must contain the name of the person who approved the Step 29 plan.'
}

$reviewedJobId = [guid]'7e8a79ec-045c-4474-b3e8-78e716e11143'
$reviewedManifestHash = '0f226d9fcf174f597a0d3c4bc510693a5fbe2e524bd089ffb1056d399fe356c8'
$reviewedPlanHash = '8c61857a5ba64acdf66f4de4f1d658ecbb80bd1ff582066f89d773317336bc96'
if ($JobId -ne $reviewedJobId -or
    $normalizedManifestHash -ne $reviewedManifestHash -or
    $normalizedPlanHash -ne $reviewedPlanHash) {
    throw 'The supplied job, manifest, or plan hash is not the reviewed completed Step 29 plan.'
}

$analysisPath = Join-Path $OutputDirectory "expansion-batch-2-analysis-$JobId.json"
if (-not (Test-Path -LiteralPath $analysisPath -PathType Leaf)) {
    throw 'The reviewed Step 29 analysis report is missing. Do not reconstruct or apply a plan manually.'
}

$analysis = Get-Content -LiteralPath $analysisPath -Raw | ConvertFrom-Json
$analysisItems = @($analysis.items | Where-Object { $null -ne $_ })
$candidateCount = $analysis.secondaryBackfillCandidateCount +
    $analysis.featureExclusionCandidateCount +
    $analysis.providerAdjustmentCandidateCount +
    $analysis.verifiedMoveCandidateCount
if ([guid]$analysis.jobId -ne $JobId -or
    $analysis.planHash -ne $normalizedPlanHash -or
    -not $analysis.analysisComplete -or
    $analysis.unresolvedFindingCount -ne 515 -or
    $analysis.officialSessionFindingCount -ne 423 -or
    $analysis.peerSessionFindingCount -ne 71 -or
    $analysis.coverageGapFindingCount -ne 2 -or
    $analysis.largeMoveFindingCount -ne 19 -or
    $analysis.sourceRequestCount -ne 95 -or
    $analysis.secondaryBackfillCandidateCount -ne 478 -or
    $analysis.featureExclusionCandidateCount -ne 18 -or
    $analysis.providerAdjustmentCandidateCount -ne 1 -or
    $analysis.verifiedMoveCandidateCount -ne 18 -or
    $candidateCount -ne 515 -or
    $analysis.keepOpenCount -ne 0 -or
    $analysis.sourceFailureCount -ne 0 -or
    $analysis.candlesWritten -or
    $analysis.resolutionsWritten -or
    $analysisItems.Count -ne 515) {
    throw 'The saved Step 29 report does not match the reviewed complete 515-item plan.'
}

$health = Invoke-RestMethod "$BaseUrl/actuator/health" -TimeoutSec 60
if ($health.status -ne 'UP') {
    throw "MarketBrain health is $($health.status), not UP."
}

$latestBefore = Invoke-RestMethod "$BaseUrl/api/v1/market-data/backfills/latest" -TimeoutSec 60
if ([guid]$latestBefore.jobId -ne $JobId -or
    $latestBefore.jobType -ne 'EXPANSION' -or
    $latestBefore.batchNumber -ne 2 -or
    $latestBefore.status -ne 'COMPLETED' -or
    $latestBefore.instruments -ne 50 -or
    $latestBefore.totalChunks -ne 623 -or
    $latestBefore.completedChunks -ne 623 -or
    $latestBefore.failedChunks -ne 0 -or
    $latestBefore.acceptedRows -ne 149636 -or
    $latestBefore.rejectedRows -ne 0 -or
    $latestBefore.workerEnabled) {
    throw 'The live job is not the reviewed completed Batch 2 checkpoint with a disabled worker.'
}

$request = @{
    jobId = $JobId
    expectedPlanHash = $normalizedPlanHash
    reviewedBy = $reviewer
} | ConvertTo-Json

$result = $null
try {
    $result = Invoke-RestMethod `
        -Method Post `
        -Uri "$BaseUrl/api/v1/market-data/backfills/remaining-data-remediation/apply" `
        -ContentType 'application/json' `
        -Body $request `
        -TimeoutSec 3600
} catch {
    Write-Warning 'The application response was interrupted. Checking the durable plan checkpoint before failing.'
    try {
        $encodedHash = [uri]::EscapeDataString($normalizedPlanHash)
        $result = Invoke-RestMethod `
            "$BaseUrl/api/v1/market-data/backfills/remaining-data-remediation/status?jobId=$JobId&expectedPlanHash=$encodedHash" `
            -TimeoutSec 900
    } catch {
        throw 'The Step 30 response and checkpoint status are currently unavailable. Do not change the plan; rerun this exact command after connectivity returns.'
    }
}

New-Item -ItemType Directory -Path $OutputDirectory -Force | Out-Null
$resultPath = Join-Path $OutputDirectory "expansion-batch-2-remediation-$JobId.json"
$result | ConvertTo-Json -Depth 14 |
    Set-Content -LiteralPath $resultPath -Encoding utf8

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

if ([guid]$result.jobId -ne $JobId -or $result.planHash -ne $normalizedPlanHash) {
    throw 'The returned remediation identity does not match the reviewed Batch 2 job and Step 29 plan.'
}
if ($result.workerEnabled) {
    throw 'The backfill worker became enabled during Step 30.'
}
if ($result.status -ne 'COMPLETED') {
    throw 'Step 30 is not complete. Correct only the reported environmental problem, then rerun this exact command.'
}
if ($result.totalItems -ne 515 -or
    $result.pendingItems -ne 0 -or
    $result.completedItems -ne 515 -or
    $result.failedItems -ne 0 -or
    $result.secondaryBackfillItems -ne 478 -or
    $result.featureExclusionItems -ne 18 -or
    $result.providerAdjustmentItems -ne 1 -or
    $result.secondaryCandlesReady -ne 478 -or
    $result.upstoxDailyCandleCount -ne 149636 -or
    $result.secondaryDailyCandleCount -ne 478 -or
    $result.allSourceDailyCandleCount -ne 150114 -or
    $result.planResolutionsWritten -ne 515 -or
    $result.currentResolutionCount -ne 515 -or
    $result.unresolvedFindingCount -ne 0 -or
    -not $result.finalProviderSpotCheckRequired) {
    throw 'Step 30 returned COMPLETED, but one or more reviewed final invariants differ.'
}

Write-Host ''
Write-Host 'STEP 30 COMPLETE: all 515 reviewed Batch 2 actions are durable and every checkpoint passed.'
Write-Host 'The original 149636 Upstox candles were preserved; 478 official NSE BhavCopy candles were added separately.'
Write-Host 'Eighteen feature exclusions, one provider adjustment, and eighteen verified moves were recorded.'
Write-Host "The complete result was saved to $resultPath."
Write-Host 'A final read-only provider quality audit is required before Batch 2 becomes eligible or Batch 3 is prepared.'
