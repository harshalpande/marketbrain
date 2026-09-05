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

$batchNumber = 3
$expectedInstrumentCount = 200
$expectedTotalChunks = 2320
$expectedAcceptedRows = 550050
$expectedRejectedRows = 6
$expectedLalPathLabChunks = 11
$normalizedHash = $ReviewedManifestHash.Trim().ToLowerInvariant()
$creationPath = Join-Path $OutputDirectory "expansion-batch-$batchNumber-created-$JobId.json"
$recoveryPath = Join-Path $OutputDirectory "expansion-batch-$batchNumber-lalpathlab-recovery-$JobId.json"

if (-not (Test-Path -LiteralPath $creationPath -PathType Leaf) -or
    -not (Test-Path -LiteralPath $recoveryPath -PathType Leaf)) {
    throw 'The reviewed Batch 3 creation or LALPATHLAB recovery report is missing. Do not audit another job.'
}

$creationReport = Get-Content -LiteralPath $creationPath -Raw | ConvertFrom-Json
$recoveryReport = Get-Content -LiteralPath $recoveryPath -Raw | ConvertFrom-Json
$recoveredInstruments = @($recoveryReport.instruments | Where-Object { $null -ne $_ })
$recoveredLalPathLab = @($recoveredInstruments | Where-Object { $_.symbol -eq 'LALPATHLAB' })
$recoveredFailures = @($recoveredInstruments | Where-Object { $_.failedChunks -gt 0 })

if ($creationReport.reviewedManifestHash -ne $normalizedHash -or
    $creationReport.creation.manifestHash -ne $normalizedHash -or
    $creationReport.creation.batchNumber -ne $batchNumber -or
    [guid]$creationReport.verifiedStatus.jobId -ne $JobId -or
    $creationReport.verifiedStatus.instruments -ne $expectedInstrumentCount -or
    $creationReport.verifiedStatus.totalChunks -ne $expectedTotalChunks -or
    $recoveryReport.reviewedManifestHash -ne $normalizedHash -or
    [guid]$recoveryReport.status.jobId -ne $JobId -or
    $recoveryReport.status.batchNumber -ne $batchNumber -or
    $recoveryReport.status.status -ne 'COMPLETED' -or
    $recoveryReport.status.instruments -ne $expectedInstrumentCount -or
    $recoveryReport.status.totalChunks -ne $expectedTotalChunks -or
    $recoveryReport.status.completedChunks -ne $expectedTotalChunks -or
    $recoveryReport.status.failedChunks -ne 0 -or
    $recoveryReport.status.acceptedRows -ne $expectedAcceptedRows -or
    $recoveryReport.status.rejectedRows -ne $expectedRejectedRows -or
    $recoveredInstruments.Count -ne $expectedInstrumentCount -or
    $recoveredFailures.Count -ne 0 -or
    $recoveredLalPathLab.Count -ne 1 -or
    $recoveredLalPathLab[0].totalChunks -ne $expectedLalPathLabChunks -or
    $recoveredLalPathLab[0].completedChunks -ne $expectedLalPathLabChunks -or
    $recoveredLalPathLab[0].failedChunks -ne 0) {
    throw 'The saved reports do not match the exact reviewed completed Batch 3 checkpoint.'
}

$health = Invoke-RestMethod "$BaseUrl/actuator/health"
if ($health.status -ne 'UP') {
    throw "MarketBrain health is $($health.status), not UP."
}

$latestBefore = Invoke-RestMethod "$BaseUrl/api/v1/market-data/backfills/latest"
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
    throw 'The live job is not the exact completed Batch 3 checkpoint with a disabled worker.'
}

New-Item -ItemType Directory -Path $OutputDirectory -Force | Out-Null

Write-Host 'Running the database-only quality audit across all 200 Batch 3 instruments...'
$databaseQuality = Invoke-RestMethod `
    "$BaseUrl/api/v1/market-data/backfills/quality?jobId=$JobId" `
    -TimeoutSec 1800
$databaseReportPath = Join-Path $OutputDirectory "expansion-batch-$batchNumber-database-quality-$JobId.json"
$databaseQuality | ConvertTo-Json -Depth 14 |
    Set-Content -LiteralPath $databaseReportPath -Encoding utf8

Write-Host 'Running 200 read-only Upstox provider spot checks...'
$providerQuality = Invoke-RestMethod `
    "$BaseUrl/api/v1/market-data/backfills/quality?jobId=$JobId&providerSpotCheck=true" `
    -TimeoutSec 1800
$providerReportPath = Join-Path $OutputDirectory "expansion-batch-$batchNumber-provider-quality-$JobId.json"
$providerQuality | ConvertTo-Json -Depth 14 |
    Set-Content -LiteralPath $providerReportPath -Encoding utf8

$providerChecks = @($providerQuality.providerSpotChecks | Where-Object { $null -ne $_ })
$nonMatches = @($providerChecks | Where-Object { $_.status -ne 'MATCHED' })
$qualityFindings = @($providerQuality.qualityFindings | Where-Object { $null -ne $_ })

$stableMetrics = @(
    'jobId',
    'jobStatus',
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
        if ($databaseQuality.PSObject.Properties[$metric].Value -ne
            $providerQuality.PSObject.Properties[$metric].Value) {
            $metric
        }
    }
)

$latestAfter = Invoke-RestMethod "$BaseUrl/api/v1/market-data/backfills/latest"
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
    $databaseQuality.totalCandles -lt 1 -or
    $databaseQuality.blockingInstrumentCount -ne 0 -or
    $databaseQuality.duplicateRows -ne 0 -or
    $databaseQuality.invalidRows -ne 0 -or
    $databaseQuality.truncatedFindingCount -ne 0 -or
    $databaseQuality.providerSpotCheckRequested -or
    $providerQuality.jobId -ne $JobId -or
    -not $providerQuality.providerSpotCheckRequested -or
    $providerChecks.Count -ne $expectedInstrumentCount -or
    $nonMatches.Count -ne 0 -or
    $providerQuality.providerMismatchCount -ne 0 -or
    $providerQuality.providerCheckFailureCount -ne 0 -or
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

[pscustomobject]@{
    Status                             = $auditStatus
    JobId                              = $providerQuality.jobId
    BatchNumber                        = $latestAfter.batchNumber
    ManifestHash                       = $normalizedHash
    JobStatus                          = $providerQuality.jobStatus
    InstrumentCount                    = $providerQuality.instrumentCount
    TotalCandles                       = $providerQuality.totalCandles
    AcceptedProviderRows               = $latestAfter.acceptedRows
    RejectedProviderRowsPreserved      = $latestAfter.rejectedRows
    QualityStatus                      = $providerQuality.qualityStatus
    BlockingInstrumentCount            = $providerQuality.blockingInstrumentCount
    MissingProviderDataInstrumentCount = $providerQuality.missingProviderDataInstrumentCount
    ReviewInstrumentCount              = $providerQuality.reviewInstrumentCount
    DuplicateRows                      = $providerQuality.duplicateRows
    InvalidRows                        = $providerQuality.invalidRows
    MissingOfficialSessionCount        = $providerQuality.missingOfficialSessionCount
    MissingPeerConfirmedSessionCount   = $providerQuality.missingPeerConfirmedSessionCount
    SuspiciousGapCount                 = $providerQuality.suspiciousGapCount
    LargeMoveCount                     = $providerQuality.largeMoveCount
    UnresolvedFindingCount             = $providerQuality.unresolvedFindingCount
    TruncatedFindingCount              = $providerQuality.truncatedFindingCount
    ProviderSpotCheckCount             = $providerChecks.Count
    ProviderMismatchCount              = $providerQuality.providerMismatchCount
    ProviderCheckFailureCount          = $providerQuality.providerCheckFailureCount
    DatabaseProviderChangedMetrics     = ($changedMetrics -join ', ')
    JobCheckpointChanged               = $jobCheckpointChanged
    ModelTrainingEligible              = $providerQuality.modelTrainingEligible
    BacktestingEligible                = $providerQuality.backtestingEligible
    WorkerEnabled                      = $latestAfter.workerEnabled
    FullDatabaseReportPath             = $databaseReportPath
    FullProviderReportPath             = $providerReportPath
} | Format-List

Write-Host ''
Write-Host 'Finding inventory (the complete records are in the saved JSON reports)'
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

Write-Host ''
Write-Host 'Eligibility reasons'
$providerQuality.eligibilityReasons

if ($structuralFailure) {
    throw 'Step 37 found a structural failure, provider mismatch, provider outage, or unexpected checkpoint change. Do not analyze or correct findings.'
}

Write-Host ''
if ($auditStatus -eq 'PASS') {
    Write-Host 'STEP 37 PASSED: Batch 3 has no unresolved quality finding and all 200 provider checks matched.'
} else {
    Write-Host 'STEP 37 REVIEW REQUIRED: structural checks and all provider comparisons passed; reviewed analysis is still required.'
}
Write-Host 'This audit was read-only. The six rejected provider rows remain preserved and no finding was corrected.'
Write-Host 'Share the complete output before preparing the one-pass analysis or Batch 4.'
