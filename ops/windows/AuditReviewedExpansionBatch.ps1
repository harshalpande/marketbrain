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

$normalizedHash = $ReviewedManifestHash.Trim().ToLowerInvariant()
$creationPath = Join-Path $OutputDirectory "expansion-batch-2-created-$JobId.json"
$recoveryPath = Join-Path $OutputDirectory "expansion-batch-2-beml-recovery-$JobId.json"
if (-not (Test-Path -LiteralPath $creationPath -PathType Leaf) -or
    -not (Test-Path -LiteralPath $recoveryPath -PathType Leaf)) {
    throw 'The reviewed Step 25 creation report or Step 27 recovery report is missing. Do not audit another job.'
}

$creationReport = Get-Content -LiteralPath $creationPath -Raw | ConvertFrom-Json
$recoveryReport = Get-Content -LiteralPath $recoveryPath -Raw | ConvertFrom-Json
if ($creationReport.reviewedManifestHash -ne $normalizedHash -or
    $recoveryReport.reviewedManifestHash -ne $normalizedHash -or
    [guid]$creationReport.verifiedStatus.jobId -ne $JobId -or
    [guid]$recoveryReport.status.jobId -ne $JobId -or
    $recoveryReport.status.status -ne 'COMPLETED' -or
    $recoveryReport.status.completedChunks -ne 623 -or
    $recoveryReport.status.failedChunks -ne 0 -or
    $recoveryReport.status.acceptedRows -ne 149636 -or
    $recoveryReport.status.rejectedRows -ne 0) {
    throw 'The saved reports do not match the reviewed completed Batch 2 checkpoint.'
}

$health = Invoke-RestMethod "$BaseUrl/actuator/health"
if ($health.status -ne 'UP') {
    throw "MarketBrain health is $($health.status), not UP."
}

$latestBefore = Invoke-RestMethod "$BaseUrl/api/v1/market-data/backfills/latest"
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
    throw 'The live job is not the exact completed Batch 2 checkpoint with a disabled worker.'
}

Write-Host 'Running the database-only Batch 2 quality audit...'
$databaseQuality = Invoke-RestMethod `
    "$BaseUrl/api/v1/market-data/backfills/quality?jobId=$JobId" `
    -TimeoutSec 900

New-Item -ItemType Directory -Path $OutputDirectory -Force | Out-Null
$databaseReportPath = Join-Path $OutputDirectory "expansion-batch-2-database-quality-$JobId.json"
$databaseQuality | ConvertTo-Json -Depth 14 |
    Set-Content -LiteralPath $databaseReportPath -Encoding utf8

Write-Host 'Running 50 read-only Upstox provider spot checks...'
$providerQuality = Invoke-RestMethod `
    "$BaseUrl/api/v1/market-data/backfills/quality?jobId=$JobId&providerSpotCheck=true" `
    -TimeoutSec 900
$providerReportPath = Join-Path $OutputDirectory "expansion-batch-2-provider-quality-$JobId.json"
$providerQuality | ConvertTo-Json -Depth 14 |
    Set-Content -LiteralPath $providerReportPath -Encoding utf8

$providerChecks = @($providerQuality.providerSpotChecks | Where-Object { $null -ne $_ })
$nonMatches = @($providerChecks | Where-Object { $_.status -ne 'MATCHED' })
$missingOfficial = @($providerQuality.missingOfficialSessions | Where-Object { $null -ne $_ })
$missingPeer = @($providerQuality.missingPeerConfirmedSessions | Where-Object { $null -ne $_ })
$gaps = @($providerQuality.suspiciousGaps | Where-Object { $null -ne $_ })
$largeMoves = @($providerQuality.largeMoves | Where-Object { $null -ne $_ })

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
$changedMetricCount = 0
foreach ($metric in $stableMetrics) {
    if ($databaseQuality.PSObject.Properties[$metric].Value -ne
        $providerQuality.PSObject.Properties[$metric].Value) {
        $changedMetricCount++
    }
}

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
    $databaseQuality.instrumentCount -ne 50 -or
    $databaseQuality.totalCandles -lt 1 -or
    $databaseQuality.blockingInstrumentCount -ne 0 -or
    $databaseQuality.duplicateRows -ne 0 -or
    $databaseQuality.invalidRows -ne 0 -or
    $databaseQuality.truncatedFindingCount -ne 0 -or
    $databaseQuality.providerSpotCheckRequested -or
    $providerQuality.jobId -ne $JobId -or
    -not $providerQuality.providerSpotCheckRequested -or
    $providerChecks.Count -ne 50 -or
    $nonMatches.Count -ne 0 -or
    $providerQuality.providerMismatchCount -ne 0 -or
    $providerQuality.providerCheckFailureCount -ne 0 -or
    $changedMetricCount -ne 0 -or
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
    Status                                    = $auditStatus
    JobId                                     = $providerQuality.jobId
    BatchNumber                               = $latestAfter.batchNumber
    ManifestHash                              = $normalizedHash
    JobStatus                                 = $providerQuality.jobStatus
    InstrumentCount                           = $providerQuality.instrumentCount
    TotalCandles                              = $providerQuality.totalCandles
    QualityStatus                             = $providerQuality.qualityStatus
    BlockingInstrumentCount                   = $providerQuality.blockingInstrumentCount
    MissingProviderDataInstrumentCount         = $providerQuality.missingProviderDataInstrumentCount
    ReviewInstrumentCount                     = $providerQuality.reviewInstrumentCount
    DuplicateRows                             = $providerQuality.duplicateRows
    InvalidRows                               = $providerQuality.invalidRows
    MissingOfficialSessionCount               = $providerQuality.missingOfficialSessionCount
    MissingPeerConfirmedSessionCount          = $providerQuality.missingPeerConfirmedSessionCount
    SuspiciousGapCount                        = $providerQuality.suspiciousGapCount
    LargeMoveCount                            = $providerQuality.largeMoveCount
    UnresolvedFindingCount                    = $providerQuality.unresolvedFindingCount
    TruncatedFindingCount                     = $providerQuality.truncatedFindingCount
    ProviderSpotCheckCount                    = $providerChecks.Count
    ProviderMismatchCount                     = $providerQuality.providerMismatchCount
    ProviderCheckFailureCount                 = $providerQuality.providerCheckFailureCount
    DatabaseProviderMetricChangeCount         = $changedMetricCount
    JobCheckpointChanged                      = $jobCheckpointChanged
    ModelTrainingEligible                     = $providerQuality.modelTrainingEligible
    BacktestingEligible                       = $providerQuality.backtestingEligible
    WorkerEnabled                             = $latestAfter.workerEnabled
    FullDatabaseReportPath                    = $databaseReportPath
    FullProviderReportPath                    = $providerReportPath
} | Format-List

Write-Host ''
Write-Host 'Instrument quality'
$providerQuality.instruments |
    Sort-Object symbol |
    Format-Table symbol, firstCandleDate, lastCandleDate, candleCount, `
        missingOfficialSessionCount, missingPeerConfirmedSessionCount, suspiciousGapCount, largeMoveCount, `
        duplicateRows, invalidRows, status -AutoSize

Write-Host ''
Write-Host "Missing official sessions ($($missingOfficial.Count))"
$missingOfficial |
    Sort-Object tradingDate, symbol |
    Format-Table symbol, tradingDate, sessionType, evidenceType, status -AutoSize

Write-Host ''
Write-Host "Missing peer-confirmed sessions ($($missingPeer.Count))"
$missingPeer |
    Sort-Object tradingDate, symbol |
    Format-Table symbol, tradingDate, sessionType, evidenceType, status -AutoSize

Write-Host ''
Write-Host "Suspicious calendar gaps ($($gaps.Count))"
$gaps |
    Sort-Object symbol, previousTradingDate |
    Format-Table symbol, previousTradingDate, nextTradingDate, calendarGapDays -AutoSize

Write-Host ''
Write-Host "Large moves ($($largeMoves.Count))"
$largeMoves |
    Sort-Object symbol, tradingDate |
    Format-Table symbol, tradingDate, previousClose, close, absoluteMovePercent -AutoSize

Write-Host ''
Write-Host 'Provider spot checks'
$providerChecks |
    Sort-Object symbol |
    Format-Table symbol, status, comparisonDate, storedClose, providerClose, differencePercent -AutoSize

Write-Host ''
Write-Host 'Eligibility reasons'
$providerQuality.eligibilityReasons

if ($structuralFailure) {
    throw 'Step 28 found a structural failure, provider mismatch, provider outage, or unexpected write. Do not analyze or correct findings yet.'
}

Write-Host ''
if ($auditStatus -eq 'PASS') {
    Write-Host 'STEP 28 PASSED: Batch 2 has no unresolved quality finding and all provider checks matched.'
} else {
    Write-Host 'STEP 28 REVIEW REQUIRED: structural checks and provider comparisons passed; review findings remain.'
}
Write-Host 'This audit was read-only. Share the complete summary and finding tables before applying any resolution.'
