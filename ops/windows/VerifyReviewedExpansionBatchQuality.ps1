[CmdletBinding()]
param(
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

function Assert-EqualQualityMetrics {
    param(
        [Parameter(Mandatory = $true)]$Expected,
        [Parameter(Mandatory = $true)]$Actual,
        [Parameter(Mandatory = $true)][string]$FailureMessage
    )

    $metricNames = @(
        'jobId',
        'jobStatus',
        'qualityStatus',
        'requestedFrom',
        'requestedTo',
        'instrumentCount',
        'totalCandles',
        'blockingInstrumentCount',
        'missingProviderDataInstrumentCount',
        'reviewInstrumentCount',
        'duplicateRows',
        'invalidRows',
        'suspiciousGapCount',
        'largeMoveCount',
        'officialSpecialSessionCount',
        'missingOfficialSessionCount',
        'unresolvedMissingOfficialSessionCount',
        'peerConfirmedSessionCount',
        'missingPeerConfirmedSessionCount',
        'unresolvedMissingPeerConfirmedSessionCount',
        'unresolvedSuspiciousGapCount',
        'unresolvedLargeMoveCount',
        'resolvedFindingCount',
        'documentedFindingCount',
        'unresolvedFindingCount',
        'truncatedFindingCount',
        'mutuallyAvailableTradingDateCount'
    )

    foreach ($metricName in $metricNames) {
        $expectedProperty = $Expected.PSObject.Properties[$metricName]
        $actualProperty = $Actual.PSObject.Properties[$metricName]
        if ($null -eq $expectedProperty -or
            $null -eq $actualProperty -or
            $expectedProperty.Value -ne $actualProperty.Value) {
            throw "$FailureMessage Metric: $metricName."
        }
    }
}

$normalizedManifestHash = $ReviewedManifestHash.Trim().ToLowerInvariant()
$normalizedPlanHash = $ExpectedPlanHash.Trim().ToLowerInvariant()
$reviewedJobId = [guid]'7e8a79ec-045c-4474-b3e8-78e716e11143'
$reviewedManifestHash = '0f226d9fcf174f597a0d3c4bc510693a5fbe2e524bd089ffb1056d399fe356c8'
$reviewedPlanHash = '8c61857a5ba64acdf66f4de4f1d658ecbb80bd1ff582066f89d773317336bc96'
if ($JobId -ne $reviewedJobId -or
    $normalizedManifestHash -ne $reviewedManifestHash -or
    $normalizedPlanHash -ne $reviewedPlanHash) {
    throw 'The supplied job, manifest, or plan hash is not the reviewed completed Batch 2 remediation.'
}

$analysisPath = Join-Path $OutputDirectory "expansion-batch-2-analysis-$JobId.json"
$remediationPath = Join-Path $OutputDirectory "expansion-batch-2-remediation-$JobId.json"
if (-not (Test-Path -LiteralPath $analysisPath -PathType Leaf) -or
    -not (Test-Path -LiteralPath $remediationPath -PathType Leaf)) {
    throw 'The reviewed Step 29 analysis or Step 30 remediation report is missing.'
}

$analysis = Get-Content -LiteralPath $analysisPath -Raw | ConvertFrom-Json
$savedRemediation = Get-Content -LiteralPath $remediationPath -Raw | ConvertFrom-Json
if ([guid]$analysis.jobId -ne $JobId -or
    $analysis.planHash -ne $normalizedPlanHash -or
    -not $analysis.analysisComplete -or
    $analysis.unresolvedFindingCount -ne 515 -or
    $analysis.keepOpenCount -ne 0 -or
    $analysis.sourceFailureCount -ne 0 -or
    [guid]$savedRemediation.jobId -ne $JobId -or
    $savedRemediation.planHash -ne $normalizedPlanHash -or
    $savedRemediation.status -ne 'COMPLETED' -or
    $savedRemediation.totalItems -ne 515 -or
    $savedRemediation.completedItems -ne 515 -or
    $savedRemediation.failedItems -ne 0 -or
    $savedRemediation.secondaryCandlesReady -ne 478 -or
    $savedRemediation.currentResolutionCount -ne 515 -or
    $savedRemediation.unresolvedFindingCount -ne 0) {
    throw 'The saved Step 29 and Step 30 reports do not match the reviewed completed Batch 2 checkpoint.'
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
    throw 'The live backfill is not the reviewed completed Batch 2 checkpoint with a disabled worker.'
}

$encodedHash = [uri]::EscapeDataString($normalizedPlanHash)
$remediationBefore = Invoke-RestMethod `
    "$BaseUrl/api/v1/market-data/backfills/remaining-data-remediation/status?jobId=$JobId&expectedPlanHash=$encodedHash" `
    -TimeoutSec 900
if ($remediationBefore.status -ne 'COMPLETED' -or
    $remediationBefore.totalItems -ne 515 -or
    $remediationBefore.pendingItems -ne 0 -or
    $remediationBefore.completedItems -ne 515 -or
    $remediationBefore.failedItems -ne 0 -or
    $remediationBefore.secondaryBackfillItems -ne 478 -or
    $remediationBefore.featureExclusionItems -ne 18 -or
    $remediationBefore.providerAdjustmentItems -ne 1 -or
    $remediationBefore.secondaryCandlesReady -ne 478 -or
    $remediationBefore.upstoxDailyCandleCount -ne 149636 -or
    $remediationBefore.secondaryDailyCandleCount -ne 478 -or
    $remediationBefore.allSourceDailyCandleCount -ne 150114 -or
    $remediationBefore.planResolutionsWritten -ne 515 -or
    $remediationBefore.currentResolutionCount -ne 515 -or
    $remediationBefore.unresolvedFindingCount -ne 0 -or
    $remediationBefore.workerEnabled) {
    throw 'The live Step 30 remediation is not at its reviewed completed checkpoint.'
}

Write-Host 'Running the final database-only Batch 2 quality audit...'
$databaseQuality = Invoke-RestMethod `
    "$BaseUrl/api/v1/market-data/backfills/quality?jobId=$JobId" `
    -TimeoutSec 900

Write-Host 'Running the final 50 read-only Upstox provider spot checks...'
$providerQuality = Invoke-RestMethod `
    "$BaseUrl/api/v1/market-data/backfills/quality?jobId=$JobId&providerSpotCheck=true" `
    -TimeoutSec 900
$checks = @($providerQuality.providerSpotChecks | Where-Object { $null -ne $_ })
$nonMatches = @($checks | Where-Object { $_.status -ne 'MATCHED' })
$currentResolutions = @($providerQuality.currentResolutions | Where-Object { $null -ne $_ })

Assert-EqualQualityMetrics `
    -Expected $databaseQuality `
    -Actual $providerQuality `
    -FailureMessage 'The database and provider-backed final quality reports do not agree.'

$remediationAfter = Invoke-RestMethod `
    "$BaseUrl/api/v1/market-data/backfills/remaining-data-remediation/status?jobId=$JobId&expectedPlanHash=$encodedHash" `
    -TimeoutSec 900
$latestAfter = Invoke-RestMethod "$BaseUrl/api/v1/market-data/backfills/latest" -TimeoutSec 60

if ($remediationAfter.status -ne $remediationBefore.status -or
    $remediationAfter.pendingItems -ne $remediationBefore.pendingItems -or
    $remediationAfter.completedItems -ne $remediationBefore.completedItems -or
    $remediationAfter.failedItems -ne $remediationBefore.failedItems -or
    $remediationAfter.secondaryCandlesReady -ne $remediationBefore.secondaryCandlesReady -or
    $remediationAfter.allSourceDailyCandleCount -ne $remediationBefore.allSourceDailyCandleCount -or
    $remediationAfter.currentResolutionCount -ne $remediationBefore.currentResolutionCount -or
    $remediationAfter.unresolvedFindingCount -ne $remediationBefore.unresolvedFindingCount -or
    $latestAfter.jobId -ne $latestBefore.jobId -or
    $latestAfter.status -ne $latestBefore.status -or
    $latestAfter.completedChunks -ne $latestBefore.completedChunks -or
    $latestAfter.failedChunks -ne $latestBefore.failedChunks -or
    $latestAfter.acceptedRows -ne $latestBefore.acceptedRows -or
    $latestAfter.rejectedRows -ne $latestBefore.rejectedRows -or
    $latestAfter.workerEnabled) {
    throw 'The read-only final audit unexpectedly changed a remediation or backfill checkpoint.'
}

New-Item -ItemType Directory -Path $OutputDirectory -Force | Out-Null
$databaseReportPath = Join-Path $OutputDirectory "expansion-batch-2-final-database-quality-$JobId.json"
$providerReportPath = Join-Path $OutputDirectory "expansion-batch-2-final-provider-quality-$JobId.json"
$databaseQuality | ConvertTo-Json -Depth 14 |
    Set-Content -LiteralPath $databaseReportPath -Encoding utf8
$providerQuality | ConvertTo-Json -Depth 14 |
    Set-Content -LiteralPath $providerReportPath -Encoding utf8

$eligible = $providerQuality.qualityStatus -eq 'PASS' -and
    $providerQuality.modelTrainingEligible -and
    $providerQuality.backtestingEligible

[pscustomobject]@{
    Status                                      = if ($eligible) { 'ELIGIBLE' } else { 'NOT_ELIGIBLE' }
    JobId                                       = $providerQuality.jobId
    BatchNumber                                 = $latestAfter.batchNumber
    ManifestHash                                = $normalizedManifestHash
    PlanHash                                    = $normalizedPlanHash
    QualityStatus                               = $providerQuality.qualityStatus
    InstrumentCount                             = $providerQuality.instrumentCount
    QualityScopedUpstoxCandles                  = $providerQuality.totalCandles
    SecondaryDailyCandleCount                   = $remediationAfter.secondaryDailyCandleCount
    AllSourceDailyCandleCount                   = $remediationAfter.allSourceDailyCandleCount
    BlockingInstrumentCount                     = $providerQuality.blockingInstrumentCount
    MissingProviderDataInstrumentCount          = $providerQuality.missingProviderDataInstrumentCount
    ReviewInstrumentCount                       = $providerQuality.reviewInstrumentCount
    DuplicateRows                               = $providerQuality.duplicateRows
    InvalidRows                                 = $providerQuality.invalidRows
    RawMissingOfficialSessionCount              = $providerQuality.missingOfficialSessionCount
    UnresolvedMissingOfficialSessionCount       = $providerQuality.unresolvedMissingOfficialSessionCount
    RawMissingPeerConfirmedSessionCount         = $providerQuality.missingPeerConfirmedSessionCount
    UnresolvedMissingPeerConfirmedSessionCount  = $providerQuality.unresolvedMissingPeerConfirmedSessionCount
    RawSuspiciousGapCount                       = $providerQuality.suspiciousGapCount
    UnresolvedSuspiciousGapCount                = $providerQuality.unresolvedSuspiciousGapCount
    RawLargeMoveCount                           = $providerQuality.largeMoveCount
    UnresolvedLargeMoveCount                    = $providerQuality.unresolvedLargeMoveCount
    ResolvedFindingCount                        = $providerQuality.resolvedFindingCount
    DocumentedFindingCount                      = $providerQuality.documentedFindingCount
    CurrentResolutionCount                      = $currentResolutions.Count
    UnresolvedFindingCount                      = $providerQuality.unresolvedFindingCount
    TruncatedFindingCount                       = $providerQuality.truncatedFindingCount
    ProviderSpotCheckRequested                  = $providerQuality.providerSpotCheckRequested
    ProviderSpotCheckCount                      = $checks.Count
    ProviderMismatchCount                       = $providerQuality.providerMismatchCount
    ProviderCheckFailureCount                   = $providerQuality.providerCheckFailureCount
    ModelTrainingEligible                       = $providerQuality.modelTrainingEligible
    BacktestingEligible                         = $providerQuality.backtestingEligible
    RemediationCheckpointChanged                = $false
    JobCheckpointChanged                        = $false
    WorkerEnabled                               = $latestAfter.workerEnabled
    FullDatabaseReportPath                      = $databaseReportPath
    FullProviderReportPath                      = $providerReportPath
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

Write-Host ''
Write-Host 'Eligibility reasons'
$providerQuality.eligibilityReasons

if ([guid]$providerQuality.jobId -ne $JobId -or
    $providerQuality.jobStatus -ne 'COMPLETED' -or
    $providerQuality.qualityStatus -ne 'PASS' -or
    $providerQuality.instrumentCount -ne 50 -or
    $providerQuality.totalCandles -ne 149636 -or
    $providerQuality.blockingInstrumentCount -ne 0 -or
    $providerQuality.missingProviderDataInstrumentCount -ne 0 -or
    $providerQuality.reviewInstrumentCount -ne 0 -or
    $providerQuality.duplicateRows -ne 0 -or
    $providerQuality.invalidRows -ne 0 -or
    $providerQuality.missingOfficialSessionCount -ne 423 -or
    $providerQuality.unresolvedMissingOfficialSessionCount -ne 0 -or
    $providerQuality.missingPeerConfirmedSessionCount -ne 71 -or
    $providerQuality.unresolvedMissingPeerConfirmedSessionCount -ne 0 -or
    $providerQuality.suspiciousGapCount -ne 1 -or
    $providerQuality.unresolvedSuspiciousGapCount -ne 0 -or
    $providerQuality.largeMoveCount -ne 19 -or
    $providerQuality.unresolvedLargeMoveCount -ne 0 -or
    $providerQuality.resolvedFindingCount -ne 515 -or
    $providerQuality.documentedFindingCount -ne 0 -or
    $currentResolutions.Count -ne 515 -or
    $providerQuality.unresolvedFindingCount -ne 0 -or
    $providerQuality.truncatedFindingCount -ne 0 -or
    -not $providerQuality.providerSpotCheckRequested -or
    $checks.Count -ne 50 -or
    $nonMatches.Count -ne 0 -or
    $providerQuality.providerMismatchCount -ne 0 -or
    $providerQuality.providerCheckFailureCount -ne 0 -or
    -not $providerQuality.modelTrainingEligible -or
    -not $providerQuality.backtestingEligible) {
    throw 'The final Batch 2 provider-backed quality gate did not pass every reviewed invariant.'
}

Write-Host ''
Write-Host 'FINAL BATCH 2 QUALITY GATE PASSED.'
Write-Host 'All 50 provider checks matched, and Batch 2 is eligible for model training and backtesting.'
Write-Host 'This command was read-only; the complete database and provider reports were saved locally.'
Write-Host 'Share the complete result before preparing expansion Batch 3.'
