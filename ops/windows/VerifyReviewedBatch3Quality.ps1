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

$batchNumber = 3
$expectedJobId = [guid]'66826ff9-1aa0-4f13-980b-8e6ed9693301'
$expectedManifestHash = 'd48347ab883557877a46a39487d3bab8f9f03833883a8873a933bd008f661b4b'
$expectedPlanHashValue = '6c26708b6aeadd4988fafb1aefcf21289a22dd5a3205c0851bf9b7b10ce3e82c'
$expectedInstruments = 200
$expectedChunks = 2320
$expectedUpstoxCandles = 550050
$expectedRejectedRows = 6
$expectedFindings = 7036
$expectedSecondaryCandles = 1469
$expectedFeatureExclusions = 5479
$expectedProviderAdjustments = 20
$expectedVerifiedMoves = 68
$expectedAllSourceCandles = $expectedUpstoxCandles + $expectedSecondaryCandles
$manifestHash = $ReviewedManifestHash.Trim().ToLowerInvariant()
$planHash = $ExpectedPlanHash.Trim().ToLowerInvariant()

if ($JobId -ne $expectedJobId -or
    $manifestHash -ne $expectedManifestHash -or
    $planHash -ne $expectedPlanHashValue) {
    throw 'The supplied job, manifest, or plan hash is not the reviewed completed Batch 3 remediation.'
}

$analysisPath = Join-Path $OutputDirectory "expansion-batch-$batchNumber-corrected-analysis-$JobId.json"
$remediationPath = Join-Path $OutputDirectory "expansion-batch-$batchNumber-remediation-$JobId.json"
if (-not (Test-Path -LiteralPath $analysisPath -PathType Leaf) -or
    -not (Test-Path -LiteralPath $remediationPath -PathType Leaf)) {
    throw 'The reviewed corrected-analysis or completed-remediation report is missing.'
}

$analysis = Get-Content -LiteralPath $analysisPath -Raw | ConvertFrom-Json
$savedRemediation = Get-Content -LiteralPath $remediationPath -Raw | ConvertFrom-Json
$candidateCount = [int]$analysis.secondaryBackfillCandidateCount +
    [int]$analysis.featureExclusionCandidateCount +
    [int]$analysis.providerAdjustmentCandidateCount +
    [int]$analysis.verifiedMoveCandidateCount

if ([guid]$analysis.jobId -ne $JobId -or
    $analysis.planHash -ne $planHash -or
    -not $analysis.analysisComplete -or
    $analysis.unresolvedFindingCount -ne $expectedFindings -or
    $analysis.secondaryBackfillCandidateCount -ne $expectedSecondaryCandles -or
    $analysis.featureExclusionCandidateCount -ne $expectedFeatureExclusions -or
    $analysis.providerAdjustmentCandidateCount -ne $expectedProviderAdjustments -or
    $analysis.verifiedMoveCandidateCount -ne $expectedVerifiedMoves -or
    $candidateCount -ne $expectedFindings -or
    $analysis.keepOpenCount -ne 0 -or
    $analysis.sourceFailureCount -ne 0 -or
    $analysis.candlesWritten -or
    $analysis.resolutionsWritten -or
    [guid]$savedRemediation.jobId -ne $JobId -or
    $savedRemediation.planHash -ne $planHash -or
    $savedRemediation.status -ne 'COMPLETED' -or
    $savedRemediation.totalItems -ne $expectedFindings -or
    $savedRemediation.pendingItems -ne 0 -or
    $savedRemediation.completedItems -ne $expectedFindings -or
    $savedRemediation.failedItems -ne 0 -or
    $savedRemediation.secondaryBackfillItems -ne $expectedSecondaryCandles -or
    $savedRemediation.featureExclusionItems -ne $expectedFeatureExclusions -or
    $savedRemediation.providerAdjustmentItems -ne $expectedProviderAdjustments -or
    $savedRemediation.secondaryCandlesReady -ne $expectedSecondaryCandles -or
    $savedRemediation.upstoxDailyCandleCount -ne $expectedUpstoxCandles -or
    $savedRemediation.secondaryDailyCandleCount -ne $expectedSecondaryCandles -or
    $savedRemediation.allSourceDailyCandleCount -ne $expectedAllSourceCandles -or
    $savedRemediation.planResolutionsWritten -ne $expectedFindings -or
    $savedRemediation.currentResolutionCount -ne $expectedFindings -or
    $savedRemediation.unresolvedFindingCount -ne 0 -or
    $savedRemediation.workerEnabled -or
    -not $savedRemediation.finalProviderSpotCheckRequired) {
    throw 'The saved Batch 3 analysis or remediation report differs from the reviewed completed checkpoint.'
}

$health = Invoke-RestMethod "$BaseUrl/actuator/health" -TimeoutSec 60
if ($health.status -ne 'UP') {
    throw "MarketBrain health is $($health.status), not UP."
}

$latestBefore = Invoke-RestMethod "$BaseUrl/api/v1/market-data/backfills/latest" -TimeoutSec 60
if ([guid]$latestBefore.jobId -ne $JobId -or
    $latestBefore.jobType -ne 'EXPANSION' -or
    $latestBefore.batchNumber -ne $batchNumber -or
    $latestBefore.status -ne 'COMPLETED' -or
    $latestBefore.instruments -ne $expectedInstruments -or
    $latestBefore.totalChunks -ne $expectedChunks -or
    $latestBefore.completedChunks -ne $expectedChunks -or
    $latestBefore.failedChunks -ne 0 -or
    $latestBefore.acceptedRows -ne $expectedUpstoxCandles -or
    $latestBefore.rejectedRows -ne $expectedRejectedRows -or
    $latestBefore.workerEnabled) {
    throw 'The live job is not the exact reviewed completed Batch 3 checkpoint with a disabled worker.'
}

$encodedHash = [uri]::EscapeDataString($planHash)
$remediationBefore = Invoke-RestMethod `
    "$BaseUrl/api/v1/market-data/backfills/remaining-data-remediation/status?jobId=$JobId&expectedPlanHash=$encodedHash" `
    -TimeoutSec 1800
if ($remediationBefore.status -ne 'COMPLETED' -or
    $remediationBefore.totalItems -ne $expectedFindings -or
    $remediationBefore.pendingItems -ne 0 -or
    $remediationBefore.completedItems -ne $expectedFindings -or
    $remediationBefore.failedItems -ne 0 -or
    $remediationBefore.secondaryBackfillItems -ne $expectedSecondaryCandles -or
    $remediationBefore.featureExclusionItems -ne $expectedFeatureExclusions -or
    $remediationBefore.providerAdjustmentItems -ne $expectedProviderAdjustments -or
    $remediationBefore.secondaryCandlesReady -ne $expectedSecondaryCandles -or
    $remediationBefore.upstoxDailyCandleCount -ne $expectedUpstoxCandles -or
    $remediationBefore.secondaryDailyCandleCount -ne $expectedSecondaryCandles -or
    $remediationBefore.allSourceDailyCandleCount -ne $expectedAllSourceCandles -or
    $remediationBefore.planResolutionsWritten -ne $expectedFindings -or
    $remediationBefore.currentResolutionCount -ne $expectedFindings -or
    $remediationBefore.unresolvedFindingCount -ne 0 -or
    $remediationBefore.workerEnabled) {
    throw 'The live Batch 3 remediation checkpoint differs from the reviewed completed result.'
}

Write-Host 'Running the final database-only Batch 3 quality audit...'
$databaseQuality = Invoke-RestMethod `
    "$BaseUrl/api/v1/market-data/backfills/quality?jobId=$JobId" `
    -TimeoutSec 1800

Write-Host 'Running the final 200 read-only Upstox provider spot checks...'
$providerQuality = Invoke-RestMethod `
    "$BaseUrl/api/v1/market-data/backfills/quality?jobId=$JobId&providerSpotCheck=true" `
    -TimeoutSec 1800
$checks = @($providerQuality.providerSpotChecks | Where-Object { $null -ne $_ })
$nonMatches = @($checks | Where-Object { $_.status -ne 'MATCHED' })
$currentResolutions = @($providerQuality.currentResolutions | Where-Object { $null -ne $_ })

$stableMetrics = @(
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
$changedMetrics = @()
foreach ($metric in $stableMetrics) {
    $databaseProperty = $databaseQuality.PSObject.Properties[$metric]
    $providerProperty = $providerQuality.PSObject.Properties[$metric]
    if ($null -eq $databaseProperty -or
        $null -eq $providerProperty -or
        $databaseProperty.Value -ne $providerProperty.Value) {
        $changedMetrics += $metric
    }
}

$remediationAfter = Invoke-RestMethod `
    "$BaseUrl/api/v1/market-data/backfills/remaining-data-remediation/status?jobId=$JobId&expectedPlanHash=$encodedHash" `
    -TimeoutSec 1800
$latestAfter = Invoke-RestMethod "$BaseUrl/api/v1/market-data/backfills/latest" -TimeoutSec 60

$checkpointChanged =
    $remediationAfter.status -ne $remediationBefore.status -or
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
    $latestAfter.workerEnabled

New-Item -ItemType Directory -Path $OutputDirectory -Force | Out-Null
$databaseReportPath = Join-Path $OutputDirectory "expansion-batch-$batchNumber-final-database-quality-$JobId.json"
$providerReportPath = Join-Path $OutputDirectory "expansion-batch-$batchNumber-final-provider-quality-$JobId.json"
$databaseQuality | ConvertTo-Json -Depth 14 |
    Set-Content -LiteralPath $databaseReportPath -Encoding utf8
$providerQuality | ConvertTo-Json -Depth 14 |
    Set-Content -LiteralPath $providerReportPath -Encoding utf8

$eligible = $providerQuality.qualityStatus -eq 'PASS' -and
    $providerQuality.modelTrainingEligible -and
    $providerQuality.backtestingEligible

[pscustomobject]@{
    Status                                     = if ($eligible) { 'ELIGIBLE' } else { 'NOT_ELIGIBLE' }
    JobId                                      = $providerQuality.jobId
    BatchNumber                                = $latestAfter.batchNumber
    ManifestHash                               = $manifestHash
    PlanHash                                   = $planHash
    QualityStatus                              = $providerQuality.qualityStatus
    InstrumentCount                            = $providerQuality.instrumentCount
    QualityScopedUpstoxCandles                 = $providerQuality.totalCandles
    SecondaryDailyCandleCount                  = $remediationAfter.secondaryDailyCandleCount
    AllSourceDailyCandleCount                  = $remediationAfter.allSourceDailyCandleCount
    BlockingInstrumentCount                    = $providerQuality.blockingInstrumentCount
    MissingProviderDataInstrumentCount         = $providerQuality.missingProviderDataInstrumentCount
    ReviewInstrumentCount                      = $providerQuality.reviewInstrumentCount
    DuplicateRows                              = $providerQuality.duplicateRows
    InvalidRows                                = $providerQuality.invalidRows
    ResolvedFindingCount                       = $providerQuality.resolvedFindingCount
    CurrentResolutionCount                     = $currentResolutions.Count
    UnresolvedFindingCount                     = $providerQuality.unresolvedFindingCount
    TruncatedFindingCount                      = $providerQuality.truncatedFindingCount
    ProviderSpotCheckRequested                 = $providerQuality.providerSpotCheckRequested
    ProviderSpotCheckCount                     = $checks.Count
    ProviderMismatchCount                      = $providerQuality.providerMismatchCount
    ProviderCheckFailureCount                  = $providerQuality.providerCheckFailureCount
    DatabaseProviderMetricChanges              = $changedMetrics.Count
    ModelTrainingEligible                      = $providerQuality.modelTrainingEligible
    BacktestingEligible                        = $providerQuality.backtestingEligible
    RemediationOrJobCheckpointChanged          = $checkpointChanged
    WorkerEnabled                              = $latestAfter.workerEnabled
    FullDatabaseReportPath                     = $databaseReportPath
    FullProviderReportPath                     = $providerReportPath
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
    $providerQuality.instrumentCount -ne $expectedInstruments -or
    $providerQuality.totalCandles -ne $expectedUpstoxCandles -or
    $providerQuality.blockingInstrumentCount -ne 0 -or
    $providerQuality.missingProviderDataInstrumentCount -ne 0 -or
    $providerQuality.reviewInstrumentCount -ne 0 -or
    $providerQuality.duplicateRows -ne 0 -or
    $providerQuality.invalidRows -ne 0 -or
    $providerQuality.unresolvedMissingOfficialSessionCount -ne 0 -or
    $providerQuality.unresolvedMissingPeerConfirmedSessionCount -ne 0 -or
    $providerQuality.unresolvedSuspiciousGapCount -ne 0 -or
    $providerQuality.unresolvedLargeMoveCount -ne 0 -or
    $providerQuality.resolvedFindingCount -ne $expectedFindings -or
    $providerQuality.documentedFindingCount -ne 0 -or
    $currentResolutions.Count -ne $expectedFindings -or
    $providerQuality.unresolvedFindingCount -ne 0 -or
    $providerQuality.truncatedFindingCount -ne 0 -or
    -not $providerQuality.providerSpotCheckRequested -or
    $checks.Count -ne $expectedInstruments -or
    $nonMatches.Count -ne 0 -or
    $providerQuality.providerMismatchCount -ne 0 -or
    $providerQuality.providerCheckFailureCount -ne 0 -or
    $changedMetrics.Count -ne 0 -or
    -not $providerQuality.modelTrainingEligible -or
    -not $providerQuality.backtestingEligible -or
    $checkpointChanged) {
    throw 'The final Batch 3 provider-backed quality audit did not pass every reviewed invariant.'
}

Write-Host ''
Write-Host 'STEP 41 PASSED: Batch 3 is provider-verified and eligible for model training and backtesting.'
Write-Host 'The audit was read-only. Batch 4 may now be previewed with BatchSize 200; only the final 190 instruments will be selected.'

