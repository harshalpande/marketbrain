[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [ValidateNotNull()]
    [guid]$JobId,
    [Parameter(Mandatory)]
    [ValidatePattern('^[0-9a-fA-F]{64}$')]
    [string]$ReviewedManifestHash,
    [string]$BaseUrl = 'http://127.0.0.1:8080',
    [string]$OutputDirectory = 'C:\MarketBrainData\Review'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$batchNumber = 4
$expectedJobId = [guid]'30d59236-017c-406c-bc31-ef4bb1d4ee47'
$expectedManifestHash = '9c11c15a4cf82a840cdbbd3e52cbc872b7916c405172ce5571ecab549568614c'
$expectedInstrumentCount = 190
$expectedTotalChunks = 2190
$expectedAcceptedRows = 520018
$expectedRejectedRows = 29
$expectedSuzlonChunks = 15
$normalizedHash = $ReviewedManifestHash.Trim().ToLowerInvariant()
$creationPath = Join-Path $OutputDirectory "expansion-batch-$batchNumber-created-$JobId.json"
$evidencePath = Join-Path $OutputDirectory "expansion-batch-$batchNumber-suzlon-investigation-$JobId.json"
$recoveryPath = Join-Path $OutputDirectory "expansion-batch-$batchNumber-suzlon-recovery-$JobId.json"
$logPath = Join-Path $OutputDirectory "expansion-batch-$batchNumber-quality-audit-$JobId.log"
$transcriptStarted = $false

if ($JobId -ne $expectedJobId -or $normalizedHash -ne $expectedManifestHash) {
    throw 'The supplied job or manifest is not the reviewed completed Batch 4 checkpoint.'
}
foreach ($path in @($creationPath, $evidencePath, $recoveryPath)) {
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        throw "A reviewed Batch 4 checkpoint is missing at $path. Do not audit another job."
    }
}

New-Item -ItemType Directory -Path $OutputDirectory -Force | Out-Null
try {
    Start-Transcript -Path $logPath -Force | Out-Host
    $transcriptStarted = $true

    $creationReport = Get-Content -LiteralPath $creationPath -Raw | ConvertFrom-Json
    $evidenceReport = Get-Content -LiteralPath $evidencePath -Raw | ConvertFrom-Json
    $recoveryReport = Get-Content -LiteralPath $recoveryPath -Raw | ConvertFrom-Json
    $recoveredInstruments = @($recoveryReport.instruments | Where-Object { $null -ne $_ })
    $recoveredSuzlon = @($recoveredInstruments | Where-Object { $_.symbol -eq 'SUZLON' })
    $recoveredFailures = @($recoveredInstruments | Where-Object { $_.failedChunks -gt 0 })

    if ($creationReport.reviewedManifestHash -ne $normalizedHash -or
        $creationReport.creation.manifestHash -ne $normalizedHash -or
        $creationReport.creation.batchNumber -ne $batchNumber -or
        [guid]$creationReport.verifiedStatus.jobId -ne $JobId -or
        $creationReport.verifiedStatus.instruments -ne $expectedInstrumentCount -or
        $creationReport.verifiedStatus.totalChunks -ne $expectedTotalChunks -or
        $evidenceReport.status -ne 'EVIDENCE_CAPTURED' -or
        [guid]$evidenceReport.jobId -ne $JobId -or
        $evidenceReport.reviewedManifestHash -ne $normalizedHash -or
        $evidenceReport.symbol -ne 'SUZLON' -or
        $evidenceReport.providerInstrumentKey -ne 'NSE_EQ|INE040H01021' -or
        $evidenceReport.providerRowCount -ne 247 -or
        $evidenceReport.duplicateTradingDateCount -ne 1 -or
        @($evidenceReport.targetRows | Where-Object { $null -ne $_ }).Count -ne 2 -or
        @($evidenceReport.officialRows | Where-Object { $null -ne $_ }).Count -ne 1 -or
        $evidenceReport.databaseWritesPerformed -or
        $recoveryReport.reviewedManifestHash -ne $normalizedHash -or
        $recoveryReport.evidencePath -ne $evidencePath -or
        [guid]$recoveryReport.status.jobId -ne $JobId -or
        $recoveryReport.status.batchNumber -ne $batchNumber -or
        $recoveryReport.status.status -ne 'COMPLETED' -or
        $recoveryReport.status.instruments -ne $expectedInstrumentCount -or
        $recoveryReport.status.totalChunks -ne $expectedTotalChunks -or
        $recoveryReport.status.pendingChunks -ne 0 -or
        $recoveryReport.status.runningChunks -ne 0 -or
        $recoveryReport.status.retryChunks -ne 0 -or
        $recoveryReport.status.completedChunks -ne $expectedTotalChunks -or
        $recoveryReport.status.failedChunks -ne 0 -or
        $recoveryReport.status.acceptedRows -ne $expectedAcceptedRows -or
        $recoveryReport.status.rejectedRows -ne $expectedRejectedRows -or
        $recoveredInstruments.Count -ne $expectedInstrumentCount -or
        $recoveredFailures.Count -ne 0 -or
        $recoveredSuzlon.Count -ne 1 -or
        $recoveredSuzlon[0].totalChunks -ne $expectedSuzlonChunks -or
        $recoveredSuzlon[0].completedChunks -ne $expectedSuzlonChunks -or
        $recoveredSuzlon[0].failedChunks -ne 0) {
        throw 'The saved reports do not match the exact reviewed completed Batch 4 checkpoint.'
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
        $latestBefore.instruments -ne $expectedInstrumentCount -or
        $latestBefore.totalChunks -ne $expectedTotalChunks -or
        $latestBefore.pendingChunks -ne 0 -or
        $latestBefore.runningChunks -ne 0 -or
        $latestBefore.retryChunks -ne 0 -or
        $latestBefore.completedChunks -ne $expectedTotalChunks -or
        $latestBefore.failedChunks -ne 0 -or
        $latestBefore.acceptedRows -ne $expectedAcceptedRows -or
        $latestBefore.rejectedRows -ne $expectedRejectedRows -or
        $latestBefore.workerEnabled) {
        throw 'The live job is not the exact completed Batch 4 checkpoint with a disabled worker.'
    }

    Write-Host 'Running the database-only quality audit across all 190 Batch 4 instruments...'
    $databaseQuality = Invoke-RestMethod `
        "$BaseUrl/api/v1/market-data/backfills/quality?jobId=$JobId" `
        -TimeoutSec 1800

    Write-Host 'Running 190 read-only Upstox provider spot checks...'
    $providerQuality = Invoke-RestMethod `
        "$BaseUrl/api/v1/market-data/backfills/quality?jobId=$JobId&providerSpotCheck=true" `
        -TimeoutSec 1800

    $providerChecks = @($providerQuality.providerSpotChecks | Where-Object { $null -ne $_ })
    $nonMatches = @($providerChecks | Where-Object { $_.status -ne 'MATCHED' })
    $qualityFindings = @($providerQuality.qualityFindings | Where-Object { $null -ne $_ })
    $databaseResolutions = @($databaseQuality.currentResolutions | Where-Object { $null -ne $_ })
    $providerResolutions = @($providerQuality.currentResolutions | Where-Object { $null -ne $_ })

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
    $changedMetrics = @(
        foreach ($metric in $stableMetrics) {
            $databaseProperty = $databaseQuality.PSObject.Properties[$metric]
            $providerProperty = $providerQuality.PSObject.Properties[$metric]
            if ($null -eq $databaseProperty -or
                $null -eq $providerProperty -or
                $databaseProperty.Value -ne $providerProperty.Value) {
                $metric
            }
        }
    )

    $latestAfter = Invoke-RestMethod "$BaseUrl/api/v1/market-data/backfills/latest" -TimeoutSec 60
    $jobCheckpointChanged =
        $latestAfter.jobId -ne $latestBefore.jobId -or
        $latestAfter.status -ne $latestBefore.status -or
        $latestAfter.completedChunks -ne $latestBefore.completedChunks -or
        $latestAfter.failedChunks -ne $latestBefore.failedChunks -or
        $latestAfter.acceptedRows -ne $latestBefore.acceptedRows -or
        $latestAfter.rejectedRows -ne $latestBefore.rejectedRows -or
        $latestAfter.workerEnabled

    $structuralFailure =
        $databaseQuality.jobId -ne $JobId -or
        $databaseQuality.jobStatus -ne 'COMPLETED' -or
        $databaseQuality.instrumentCount -ne $expectedInstrumentCount -or
        $databaseQuality.totalCandles -ne $expectedAcceptedRows -or
        $databaseQuality.blockingInstrumentCount -ne 0 -or
        $databaseQuality.duplicateRows -ne 0 -or
        $databaseQuality.invalidRows -ne 0 -or
        $databaseQuality.truncatedFindingCount -ne 0 -or
        $databaseQuality.providerSpotCheckRequested -or
        $databaseResolutions.Count -ne 0 -or
        $providerQuality.jobId -ne $JobId -or
        -not $providerQuality.providerSpotCheckRequested -or
        $providerChecks.Count -ne $expectedInstrumentCount -or
        $nonMatches.Count -ne 0 -or
        $providerQuality.providerMismatchCount -ne 0 -or
        $providerQuality.providerCheckFailureCount -ne 0 -or
        $providerResolutions.Count -ne 0 -or
        $changedMetrics.Count -ne 0 -or
        $jobCheckpointChanged

    $auditStatus = if ($structuralFailure) {
        'FAILED'
    } elseif ($providerQuality.qualityStatus -eq 'PASS' -and
        $providerQuality.unresolvedFindingCount -eq 0) {
        'PASS'
    } else {
        'REVIEW_REQUIRED'
    }

    $databaseReportPath = Join-Path $OutputDirectory `
        "expansion-batch-$batchNumber-database-quality-$JobId.json"
    $providerReportPath = Join-Path $OutputDirectory `
        "expansion-batch-$batchNumber-provider-quality-$JobId.json"
    $checkpointReportPath = Join-Path $OutputDirectory `
        "expansion-batch-$batchNumber-quality-checkpoints-$JobId.json"
    $databaseQuality | ConvertTo-Json -Depth 14 |
        Set-Content -LiteralPath $databaseReportPath -Encoding utf8
    $providerQuality | ConvertTo-Json -Depth 14 |
        Set-Content -LiteralPath $providerReportPath -Encoding utf8

    [pscustomobject]@{
        auditedAt = (Get-Date).ToUniversalTime().ToString('o')
        status = $auditStatus
        jobId = $JobId
        batchNumber = $batchNumber
        reviewedManifestHash = $normalizedHash
        creationPath = $creationPath
        evidencePath = $evidencePath
        recoveryPath = $recoveryPath
        databaseReportPath = $databaseReportPath
        providerReportPath = $providerReportPath
        databaseProviderChangedMetrics = $changedMetrics
        jobCheckpointChanged = $jobCheckpointChanged
        databaseResolutionCount = $databaseResolutions.Count
        providerResolutionCount = $providerResolutions.Count
        databaseWritesPerformed = $false
    } | ConvertTo-Json -Depth 8 |
        Set-Content -LiteralPath $checkpointReportPath -Encoding utf8

    [pscustomobject]@{
        Status = $auditStatus
        JobId = $providerQuality.jobId
        BatchNumber = $latestAfter.batchNumber
        ManifestHash = $normalizedHash
        JobStatus = $providerQuality.jobStatus
        InstrumentCount = $providerQuality.instrumentCount
        TotalCandles = $providerQuality.totalCandles
        AcceptedProviderRows = $latestAfter.acceptedRows
        RejectedProviderRowsPreserved = $latestAfter.rejectedRows
        QualityStatus = $providerQuality.qualityStatus
        BlockingInstrumentCount = $providerQuality.blockingInstrumentCount
        MissingProviderDataInstrumentCount = $providerQuality.missingProviderDataInstrumentCount
        ReviewInstrumentCount = $providerQuality.reviewInstrumentCount
        DuplicateRows = $providerQuality.duplicateRows
        InvalidRows = $providerQuality.invalidRows
        MissingOfficialSessionCount = $providerQuality.missingOfficialSessionCount
        MissingPeerConfirmedSessionCount = $providerQuality.missingPeerConfirmedSessionCount
        SuspiciousGapCount = $providerQuality.suspiciousGapCount
        LargeMoveCount = $providerQuality.largeMoveCount
        UnresolvedFindingCount = $providerQuality.unresolvedFindingCount
        TruncatedFindingCount = $providerQuality.truncatedFindingCount
        CurrentResolutionCount = $providerResolutions.Count
        ProviderSpotCheckCount = $providerChecks.Count
        ProviderMismatchCount = $providerQuality.providerMismatchCount
        ProviderCheckFailureCount = $providerQuality.providerCheckFailureCount
        DatabaseProviderChangedMetrics = ($changedMetrics -join ', ')
        JobCheckpointChanged = $jobCheckpointChanged
        ModelTrainingEligible = $providerQuality.modelTrainingEligible
        BacktestingEligible = $providerQuality.backtestingEligible
        WorkerEnabled = $latestAfter.workerEnabled
        FullDatabaseReportPath = $databaseReportPath
        FullProviderReportPath = $providerReportPath
        FullCheckpointReportPath = $checkpointReportPath
        FullLogPath = $logPath
    } | Format-List

    Write-Host ''
    Write-Host 'Finding inventory (complete records are saved in the JSON reports)'
    $qualityFindings |
        Group-Object findingType, rawStatus, reviewStatus |
        Sort-Object Name |
        Select-Object Name, Count |
        Format-Table -AutoSize

    Write-Host ''
    Write-Host 'Instrument quality'
    $providerQuality.instruments |
        Sort-Object symbol |
        Format-Table symbol, firstCandleDate, lastCandleDate, candleCount, `
            missingOfficialSessionCount, missingPeerConfirmedSessionCount, suspiciousGapCount, largeMoveCount, `
            duplicateRows, invalidRows, status -AutoSize

    Write-Host ''
    Write-Host 'Provider spot checks'
    $providerChecks |
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

    if ($structuralFailure) {
        throw 'The Batch 4 audit found a structural failure, provider mismatch, provider outage, pre-existing resolution, or checkpoint change. Do not analyze or correct findings.'
    }

    Write-Host ''
    if ($auditStatus -eq 'PASS') {
        Write-Host 'BATCH 4 QUALITY PASSED: no unresolved finding remains and all 190 provider checks matched.'
    } else {
        Write-Host 'BATCH 4 REVIEW REQUIRED: structural checks and all 190 provider comparisons passed; governed analysis is still required.'
    }
    Write-Host 'This verification was read-only. The 29 rejected provider rows remain preserved and no finding was corrected.'
    Write-Host 'Share the complete summary and finding inventory before preparing the one-pass Batch 4 analysis.'
} finally {
    if ($transcriptStarted) {
        Stop-Transcript | Out-Host
    }
}
