[CmdletBinding()]
param(
    [string]$BaseUrl = 'http://127.0.0.1:8080',
    [string]$OutputDirectory = 'C:\MarketBrainData\Review'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$reviewedJobId = 'e1d9ea5d-fcb2-4a81-b839-c154bb602243'
$reviewedPlanHash = '3ea264d124b3618dc793a66677e1b040736d65ad49b230309b60647b1c64b7f8'

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
    throw 'The latest backfill is not the exact completed 50-stock job reviewed in Steps 20 and 21.'
}
if ($latest.workerEnabled) {
    throw 'MARKETBRAIN_BACKFILL_WORKER_ENABLED must remain false during final verification.'
}

$encodedHash = [uri]::EscapeDataString($reviewedPlanHash)
$remediationBefore = Invoke-RestMethod `
    "$BaseUrl/api/v1/market-data/backfills/remaining-data-remediation/status?jobId=$reviewedJobId&expectedPlanHash=$encodedHash"

if ($remediationBefore.status -ne 'COMPLETED' -or
    $remediationBefore.completedItems -ne 331 -or
    $remediationBefore.failedItems -ne 0 -or
    $remediationBefore.secondaryCandlesReady -ne 277 -or
    $remediationBefore.currentResolutionCount -ne 353 -or
    $remediationBefore.unresolvedFindingCount -ne 0) {
    throw 'Step 21 is not at its reviewed completed checkpoint.'
}

$quality = Invoke-RestMethod `
    "$BaseUrl/api/v1/market-data/backfills/quality?jobId=$reviewedJobId&providerSpotCheck=true" `
    -TimeoutSec 900
$checks = @($quality.providerSpotChecks | Where-Object { $null -ne $_ })
$nonMatches = @($checks | Where-Object { $_.status -ne 'MATCHED' })

New-Item -ItemType Directory -Path $OutputDirectory -Force | Out-Null
$outputPath = Join-Path $OutputDirectory "final-provider-quality-$reviewedJobId.json"
$quality | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $outputPath -Encoding utf8

[pscustomobject]@{
    Status                                      = if ($quality.modelTrainingEligible -and $quality.backtestingEligible) {
        'ELIGIBLE'
    } else {
        'NOT_ELIGIBLE'
    }
    JobId                                       = $quality.jobId
    QualityStatus                               = $quality.qualityStatus
    InstrumentCount                             = $quality.instrumentCount
    QualityScopedUpstoxCandles                   = $quality.totalCandles
    BlockingInstrumentCount                     = $quality.blockingInstrumentCount
    MissingProviderDataInstrumentCount           = $quality.missingProviderDataInstrumentCount
    ReviewInstrumentCount                       = $quality.reviewInstrumentCount
    DuplicateRows                               = $quality.duplicateRows
    InvalidRows                                 = $quality.invalidRows
    RawMissingOfficialSessionCount               = $quality.missingOfficialSessionCount
    UnresolvedMissingOfficialSessionCount        = $quality.unresolvedMissingOfficialSessionCount
    RawMissingPeerConfirmedSessionCount          = $quality.missingPeerConfirmedSessionCount
    UnresolvedMissingPeerConfirmedSessionCount   = $quality.unresolvedMissingPeerConfirmedSessionCount
    RawLargeMoveCount                            = $quality.largeMoveCount
    UnresolvedLargeMoveCount                     = $quality.unresolvedLargeMoveCount
    ResolvedFindingCount                         = $quality.resolvedFindingCount
    DocumentedFindingCount                       = $quality.documentedFindingCount
    UnresolvedFindingCount                       = $quality.unresolvedFindingCount
    TruncatedFindingCount                        = $quality.truncatedFindingCount
    ProviderSpotCheckRequested                   = $quality.providerSpotCheckRequested
    ProviderSpotCheckCount                       = $checks.Count
    ProviderMismatchCount                        = $quality.providerMismatchCount
    ProviderCheckFailureCount                    = $quality.providerCheckFailureCount
    ModelTrainingEligible                        = $quality.modelTrainingEligible
    BacktestingEligible                          = $quality.backtestingEligible
    WorkerEnabled                                = $latest.workerEnabled
    FullReportPath                               = $outputPath
} | Format-List

Write-Host ''
Write-Host 'Provider spot checks'
$checks |
    Sort-Object symbol |
    Format-Table symbol, status, comparisonDate, storedClose, providerClose, differencePercent -AutoSize

if ($nonMatches.Count -gt 0) {
    Write-Host ''
    Write-Host 'Provider checks requiring attention'
    $nonMatches |
        Format-Table symbol, status, comparisonDate, storedClose, providerClose, differencePercent -AutoSize
}

$quality.eligibilityReasons

$remediationAfter = Invoke-RestMethod `
    "$BaseUrl/api/v1/market-data/backfills/remaining-data-remediation/status?jobId=$reviewedJobId&expectedPlanHash=$encodedHash"

if ($remediationAfter.completedItems -ne $remediationBefore.completedItems -or
    $remediationAfter.secondaryCandlesReady -ne $remediationBefore.secondaryCandlesReady -or
    $remediationAfter.currentResolutionCount -ne $remediationBefore.currentResolutionCount -or
    $remediationAfter.unresolvedFindingCount -ne $remediationBefore.unresolvedFindingCount) {
    throw 'The read-only final verification unexpectedly changed a Step 21 invariant.'
}

if ($quality.jobId -ne $reviewedJobId -or
    $quality.qualityStatus -ne 'PASS' -or
    $quality.instrumentCount -ne 50 -or
    $quality.totalCandles -ne 124858 -or
    $quality.blockingInstrumentCount -ne 0 -or
    $quality.missingProviderDataInstrumentCount -ne 0 -or
    $quality.reviewInstrumentCount -ne 0 -or
    $quality.duplicateRows -ne 0 -or
    $quality.invalidRows -ne 0 -or
    $quality.unresolvedMissingOfficialSessionCount -ne 0 -or
    $quality.unresolvedMissingPeerConfirmedSessionCount -ne 0 -or
    $quality.unresolvedSuspiciousGapCount -ne 0 -or
    $quality.unresolvedLargeMoveCount -ne 0 -or
    $quality.resolvedFindingCount -ne 353 -or
    $quality.documentedFindingCount -ne 0 -or
    $quality.unresolvedFindingCount -ne 0 -or
    $quality.truncatedFindingCount -ne 0 -or
    -not $quality.providerSpotCheckRequested -or
    $checks.Count -ne 50 -or
    $nonMatches.Count -ne 0 -or
    $quality.providerMismatchCount -ne 0 -or
    $quality.providerCheckFailureCount -ne 0 -or
    -not $quality.modelTrainingEligible -or
    -not $quality.backtestingEligible) {
    throw 'The final provider-backed quality gate did not pass every reviewed invariant.'
}

Write-Host ''
Write-Host 'FINAL 50-STOCK QUALITY GATE PASSED.'
Write-Host 'All 50 provider checks matched and the dataset is eligible for model training and backtesting.'
Write-Host 'This command was read-only; the full verification report was saved locally.'
Write-Host 'Share the complete summary before starting expansion batch 2.'

