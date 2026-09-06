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

$batchNumber = 4
$expectedJobId = [guid]'30d59236-017c-406c-bc31-ef4bb1d4ee47'
$expectedManifestHash = '9c11c15a4cf82a840cdbbd3e52cbc872b7916c405172ce5571ecab549568614c'
$expectedPlanHashValue = 'bdf4965b15c3e35f4bdd7ee3bb1493c5bd62f517a881e632b0656c0efd9835ec'
$expectedInstruments = 190
$expectedChunks = 2190
$expectedUpstoxCandles = 520018
$expectedRejectedRows = 29
$expectedFindings = 6685
$expectedSecondaryCandles = 1278
$expectedFeatureExclusions = 5287
$expectedProviderAdjustments = 25
$expectedVerifiedMoves = 95
$expectedAllSourceCandles = $expectedUpstoxCandles + $expectedSecondaryCandles
$manifestHash = $ReviewedManifestHash.Trim().ToLowerInvariant()
$planHash = $ExpectedPlanHash.Trim().ToLowerInvariant()

if ($JobId -ne $expectedJobId -or
    $manifestHash -ne $expectedManifestHash -or
    $planHash -ne $expectedPlanHashValue) {
    throw 'The supplied job, manifest, or plan hash is not the reviewed completed Batch 4 remediation.'
}

$analysisPath = Join-Path $OutputDirectory "expansion-batch-$batchNumber-corrected-analysis-$JobId.json"
$investigationPath = Join-Path $OutputDirectory "expansion-batch-$batchNumber-open-findings-investigation-$JobId.json"
$checkpointPath = Join-Path $OutputDirectory "expansion-batch-$batchNumber-remediation-checkpoints-$JobId.json"
$remediationPath = Join-Path $OutputDirectory "expansion-batch-$batchNumber-remediation-$JobId.json"
$requiredPaths = @($analysisPath, $investigationPath, $checkpointPath, $remediationPath)
if (@($requiredPaths | Where-Object { -not (Test-Path -LiteralPath $_ -PathType Leaf) }).Count -ne 0) {
    throw 'One or more reviewed Batch 4 investigation, analysis, checkpoint, or remediation reports are missing.'
}

New-Item -ItemType Directory -Path $OutputDirectory -Force | Out-Null
$databaseReportPath = Join-Path $OutputDirectory `
    "expansion-batch-$batchNumber-final-database-quality-$JobId.json"
$providerReportPath = Join-Path $OutputDirectory `
    "expansion-batch-$batchNumber-final-provider-quality-$JobId.json"
$finalCheckpointPath = Join-Path $OutputDirectory `
    "expansion-batch-$batchNumber-final-quality-checkpoints-$JobId.json"
$logPath = Join-Path $OutputDirectory `
    "expansion-batch-$batchNumber-final-quality-$JobId.log"

$transcriptStarted = $false
try {
    Start-Transcript -Path $logPath -Force | Out-Host
    $transcriptStarted = $true

    $analysis = Get-Content -LiteralPath $analysisPath -Raw | ConvertFrom-Json
    $investigation = Get-Content -LiteralPath $investigationPath -Raw | ConvertFrom-Json
    $checkpoint = Get-Content -LiteralPath $checkpointPath -Raw | ConvertFrom-Json
    $savedRemediation = Get-Content -LiteralPath $remediationPath -Raw | ConvertFrom-Json
    $candidateCount = [int]$analysis.secondaryBackfillCandidateCount +
        [int]$analysis.featureExclusionCandidateCount +
        [int]$analysis.providerAdjustmentCandidateCount +
        [int]$analysis.verifiedMoveCandidateCount
    $checkpointFailures = @($checkpoint.checkpoints | Where-Object { -not $_.Passed })

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
        $investigation.status -ne 'COMPLETED' -or
        [guid]$investigation.jobId -ne $JobId -or
        $investigation.reviewedManifestHash -ne $manifestHash -or
        $investigation.openFindingCount -ne 7 -or
        $investigation.archiveRequestCount -ne 7 -or
        $investigation.databaseWritesPerformed -or
        $checkpoint.status -ne 'PASSED' -or
        [guid]$checkpoint.jobId -ne $JobId -or
        $checkpoint.manifestHash -ne $manifestHash -or
        $checkpoint.correctedPlanHash -ne $planHash -or
        $checkpoint.failedCheckpointCount -ne 0 -or
        $checkpointFailures.Count -ne 0 -or
        $checkpoint.databaseWritesPerformed -or
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
        throw 'The saved Batch 4 evidence, analysis, or remediation report differs from the reviewed completed checkpoint.'
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
        throw 'The live job is not the exact reviewed completed Batch 4 checkpoint with a disabled worker.'
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
        throw 'The live Batch 4 remediation checkpoint differs from the reviewed completed result.'
    }

    Write-Host 'Running the final database-only Batch 4 quality audit...'
    $databaseQuality = Invoke-RestMethod `
        "$BaseUrl/api/v1/market-data/backfills/quality?jobId=$JobId" `
        -TimeoutSec 1800

    Write-Host 'Running the final 190 read-only Upstox provider spot checks...'
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

    $databaseQuality | ConvertTo-Json -Depth 14 |
        Set-Content -LiteralPath $databaseReportPath -Encoding utf8
    $providerQuality | ConvertTo-Json -Depth 14 |
        Set-Content -LiteralPath $providerReportPath -Encoding utf8

    $eligible = $providerQuality.qualityStatus -eq 'PASS' -and
        $providerQuality.modelTrainingEligible -and
        $providerQuality.backtestingEligible
    $finalFailures = @()
    if ([guid]$providerQuality.jobId -ne $JobId) { $finalFailures += 'JobId' }
    if ($providerQuality.jobStatus -ne 'COMPLETED') { $finalFailures += 'JobStatus' }
    if ($providerQuality.qualityStatus -ne 'PASS') { $finalFailures += 'QualityStatus' }
    if ($providerQuality.instrumentCount -ne $expectedInstruments) { $finalFailures += 'InstrumentCount' }
    if ($providerQuality.totalCandles -ne $expectedUpstoxCandles) { $finalFailures += 'QualityScopedUpstoxCandles' }
    if ($providerQuality.blockingInstrumentCount -ne 0) { $finalFailures += 'BlockingInstrumentCount' }
    if ($providerQuality.missingProviderDataInstrumentCount -ne 0) { $finalFailures += 'MissingProviderDataInstrumentCount' }
    if ($providerQuality.reviewInstrumentCount -ne 0) { $finalFailures += 'ReviewInstrumentCount' }
    if ($providerQuality.duplicateRows -ne 0) { $finalFailures += 'DuplicateRows' }
    if ($providerQuality.invalidRows -ne 0) { $finalFailures += 'InvalidRows' }
    if ($providerQuality.unresolvedMissingOfficialSessionCount -ne 0) { $finalFailures += 'UnresolvedOfficialSessions' }
    if ($providerQuality.unresolvedMissingPeerConfirmedSessionCount -ne 0) { $finalFailures += 'UnresolvedPeerSessions' }
    if ($providerQuality.unresolvedSuspiciousGapCount -ne 0) { $finalFailures += 'UnresolvedSuspiciousGaps' }
    if ($providerQuality.unresolvedLargeMoveCount -ne 0) { $finalFailures += 'UnresolvedLargeMoves' }
    if ($providerQuality.resolvedFindingCount -ne $expectedFindings) { $finalFailures += 'ResolvedFindingCount' }
    if ($providerQuality.documentedFindingCount -ne 0) { $finalFailures += 'DocumentedFindingCount' }
    if ($currentResolutions.Count -ne $expectedFindings) { $finalFailures += 'CurrentResolutionCount' }
    if ($providerQuality.unresolvedFindingCount -ne 0) { $finalFailures += 'UnresolvedFindingCount' }
    if ($providerQuality.truncatedFindingCount -ne 0) { $finalFailures += 'TruncatedFindingCount' }
    if (-not $providerQuality.providerSpotCheckRequested) { $finalFailures += 'ProviderSpotCheckRequested' }
    if ($checks.Count -ne $expectedInstruments) { $finalFailures += 'ProviderSpotCheckCount' }
    if ($nonMatches.Count -ne 0) { $finalFailures += 'ProviderNonMatchCount' }
    if ($providerQuality.providerMismatchCount -ne 0) { $finalFailures += 'ProviderMismatchCount' }
    if ($providerQuality.providerCheckFailureCount -ne 0) { $finalFailures += 'ProviderCheckFailureCount' }
    if ($changedMetrics.Count -ne 0) { $finalFailures += 'DatabaseProviderMetricChanges' }
    if (-not $providerQuality.modelTrainingEligible) { $finalFailures += 'ModelTrainingEligible' }
    if (-not $providerQuality.backtestingEligible) { $finalFailures += 'BacktestingEligible' }
    if ($checkpointChanged) { $finalFailures += 'RemediationOrJobCheckpointChanged' }

    [pscustomobject]@{
        checkedAt = [DateTimeOffset]::Now
        status = if ($finalFailures.Count -eq 0) { 'ELIGIBLE' } else { 'NOT_ELIGIBLE' }
        jobId = $JobId
        manifestHash = $manifestHash
        planHash = $planHash
        failedInvariantCount = $finalFailures.Count
        failedInvariants = $finalFailures
        databaseProviderChangedMetrics = $changedMetrics
        remediationOrJobCheckpointChanged = $checkpointChanged
        databaseWritesPerformed = $false
    } | ConvertTo-Json -Depth 8 |
        Set-Content -LiteralPath $finalCheckpointPath -Encoding utf8

    [pscustomobject]@{
        Status = if ($eligible -and $finalFailures.Count -eq 0) { 'ELIGIBLE' } else { 'NOT_ELIGIBLE' }
        JobId = $providerQuality.jobId
        BatchNumber = $latestAfter.batchNumber
        ManifestHash = $manifestHash
        PlanHash = $planHash
        QualityStatus = $providerQuality.qualityStatus
        InstrumentCount = $providerQuality.instrumentCount
        QualityScopedUpstoxCandles = $providerQuality.totalCandles
        SecondaryDailyCandleCount = $remediationAfter.secondaryDailyCandleCount
        AllSourceDailyCandleCount = $remediationAfter.allSourceDailyCandleCount
        RejectedProviderRowsPreserved = $latestAfter.rejectedRows
        BlockingInstrumentCount = $providerQuality.blockingInstrumentCount
        MissingProviderDataInstrumentCount = $providerQuality.missingProviderDataInstrumentCount
        ReviewInstrumentCount = $providerQuality.reviewInstrumentCount
        DuplicateRows = $providerQuality.duplicateRows
        InvalidRows = $providerQuality.invalidRows
        ResolvedFindingCount = $providerQuality.resolvedFindingCount
        CurrentResolutionCount = $currentResolutions.Count
        UnresolvedFindingCount = $providerQuality.unresolvedFindingCount
        TruncatedFindingCount = $providerQuality.truncatedFindingCount
        ProviderSpotCheckRequested = $providerQuality.providerSpotCheckRequested
        ProviderSpotCheckCount = $checks.Count
        ProviderMismatchCount = $providerQuality.providerMismatchCount
        ProviderCheckFailureCount = $providerQuality.providerCheckFailureCount
        DatabaseProviderMetricChanges = $changedMetrics.Count
        ModelTrainingEligible = $providerQuality.modelTrainingEligible
        BacktestingEligible = $providerQuality.backtestingEligible
        RemediationOrJobCheckpointChanged = $checkpointChanged
        WorkerEnabled = $latestAfter.workerEnabled
        FullDatabaseReportPath = $databaseReportPath
        FullProviderReportPath = $providerReportPath
        FullCheckpointPath = $finalCheckpointPath
        FullLogPath = $logPath
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

    if ($finalFailures.Count -gt 0) {
        Write-Host ''
        Write-Host 'Failed final invariants'
        $finalFailures | ForEach-Object { Write-Host $_ }
        throw 'The final Batch 4 provider-backed quality audit did not pass every reviewed invariant.'
    }

    Write-Host ''
    Write-Host 'FINAL BATCH 4 AUDIT PASSED: all 190 instruments are provider-verified and eligible for model training and backtesting.'
    Write-Host 'The audit was read-only; no candle, resolution, remediation item, or job checkpoint changed.'
} finally {
    if ($transcriptStarted) {
        Stop-Transcript | Out-Host
    }
}
