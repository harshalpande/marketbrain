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

function Get-CurrentResolutions {
    param(
        [Parameter(Mandatory = $true)][string]$ApiBaseUrl,
        [Parameter(Mandatory = $true)][guid]$BackfillJobId
    )

    $response = Invoke-RestMethod `
        "$ApiBaseUrl/api/v1/market-data/backfills/quality-resolutions?jobId=$BackfillJobId" `
        -TimeoutSec 900
    return @($response | Where-Object { $null -ne $_ })
}

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

$batchNumber = 3
$expectedInstrumentCount = 200
$expectedTotalChunks = 2320
$expectedCandles = 550050
$expectedRejectedRows = 6
$expectedOfficialFindings = 1450
$expectedPeerFindings = 5469
$expectedCoverageFindings = 28
$expectedLargeMoveFindings = 89
$expectedUnresolvedFindings = 7036
$normalizedHash = $ReviewedManifestHash.Trim().ToLowerInvariant()

$creationPath = Join-Path $OutputDirectory "expansion-batch-$batchNumber-created-$JobId.json"
$recoveryPath = Join-Path $OutputDirectory "expansion-batch-$batchNumber-lalpathlab-recovery-$JobId.json"
$databaseAuditPath = Join-Path $OutputDirectory "expansion-batch-$batchNumber-database-quality-$JobId.json"
$providerAuditPath = Join-Path $OutputDirectory "expansion-batch-$batchNumber-provider-quality-$JobId.json"
$requiredPaths = @($creationPath, $recoveryPath, $databaseAuditPath, $providerAuditPath)
if (@($requiredPaths | Where-Object { -not (Test-Path -LiteralPath $_ -PathType Leaf) }).Count -ne 0) {
    throw 'One or more reviewed Batch 3 checkpoint or Step 37 audit reports are missing.'
}

$creationReport = Get-Content -LiteralPath $creationPath -Raw | ConvertFrom-Json
$recoveryReport = Get-Content -LiteralPath $recoveryPath -Raw | ConvertFrom-Json
$databaseAudit = Get-Content -LiteralPath $databaseAuditPath -Raw | ConvertFrom-Json
$providerAudit = Get-Content -LiteralPath $providerAuditPath -Raw | ConvertFrom-Json
$providerAuditChecks = @($providerAudit.providerSpotChecks | Where-Object { $null -ne $_ })
$providerAuditNonMatches = @($providerAuditChecks | Where-Object { $_.status -ne 'MATCHED' })
$auditResolutions = @($providerAudit.currentResolutions | Where-Object { $null -ne $_ })

if ($creationReport.reviewedManifestHash -ne $normalizedHash -or
    $creationReport.creation.manifestHash -ne $normalizedHash -or
    $recoveryReport.reviewedManifestHash -ne $normalizedHash -or
    [guid]$creationReport.verifiedStatus.jobId -ne $JobId -or
    [guid]$recoveryReport.status.jobId -ne $JobId -or
    [guid]$databaseAudit.jobId -ne $JobId -or
    [guid]$providerAudit.jobId -ne $JobId) {
    throw 'The reviewed manifest, checkpoint reports, and Step 37 reports do not identify the same Batch 3 job.'
}

Assert-EqualQualityMetrics `
    -Expected $providerAudit `
    -Actual $databaseAudit `
    -FailureMessage 'The saved Step 37 database and provider reports do not agree.'

if ($recoveryReport.status.status -ne 'COMPLETED' -or
    $recoveryReport.status.instruments -ne $expectedInstrumentCount -or
    $recoveryReport.status.totalChunks -ne $expectedTotalChunks -or
    $recoveryReport.status.completedChunks -ne $expectedTotalChunks -or
    $recoveryReport.status.failedChunks -ne 0 -or
    $recoveryReport.status.acceptedRows -ne $expectedCandles -or
    $recoveryReport.status.rejectedRows -ne $expectedRejectedRows -or
    $providerAudit.jobStatus -ne 'COMPLETED' -or
    $providerAudit.qualityStatus -ne 'MISSING_PROVIDER_DATA' -or
    $providerAudit.instrumentCount -ne $expectedInstrumentCount -or
    $providerAudit.totalCandles -ne $expectedCandles -or
    $providerAudit.blockingInstrumentCount -ne 0 -or
    $providerAudit.duplicateRows -ne 0 -or
    $providerAudit.invalidRows -ne 0 -or
    $providerAudit.missingOfficialSessionCount -ne $expectedOfficialFindings -or
    $providerAudit.unresolvedMissingOfficialSessionCount -ne $expectedOfficialFindings -or
    $providerAudit.missingPeerConfirmedSessionCount -ne $expectedPeerFindings -or
    $providerAudit.unresolvedMissingPeerConfirmedSessionCount -ne $expectedPeerFindings -or
    $providerAudit.suspiciousGapCount -ne 21 -or
    $providerAudit.unresolvedSuspiciousGapCount -ne 21 -or
    $providerAudit.largeMoveCount -ne $expectedLargeMoveFindings -or
    $providerAudit.unresolvedLargeMoveCount -ne $expectedLargeMoveFindings -or
    $providerAudit.unresolvedFindingCount -ne $expectedUnresolvedFindings -or
    $providerAudit.truncatedFindingCount -ne 0 -or
    -not $providerAudit.providerSpotCheckRequested -or
    $providerAuditChecks.Count -ne $expectedInstrumentCount -or
    $providerAuditNonMatches.Count -ne 0 -or
    $providerAudit.providerMismatchCount -ne 0 -or
    $providerAudit.providerCheckFailureCount -ne 0) {
    throw 'The saved Step 37 evidence does not match the reviewed Batch 3 quality checkpoint.'
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
    $latestBefore.acceptedRows -ne $expectedCandles -or
    $latestBefore.rejectedRows -ne $expectedRejectedRows -or
    $latestBefore.workerEnabled) {
    throw 'The live backfill is not the reviewed completed Batch 3 checkpoint with a disabled worker.'
}

$qualityBefore = Invoke-RestMethod `
    "$BaseUrl/api/v1/market-data/backfills/quality?jobId=$JobId" `
    -TimeoutSec 1800
$resolutionsBefore = @(Get-CurrentResolutions -ApiBaseUrl $BaseUrl -BackfillJobId $JobId)

Assert-EqualQualityMetrics `
    -Expected $providerAudit `
    -Actual $qualityBefore `
    -FailureMessage 'The live quality checkpoint has drifted since Step 37.'
if ($resolutionsBefore.Count -ne $auditResolutions.Count) {
    throw 'The number of Batch 3 quality resolutions has changed since Step 37.'
}

Write-Host 'Analyzing all 7036 unresolved Batch 3 findings in one read-only request...'
Write-Host 'This can take time because each distinct trading date is checked against an official NSE archive.'
$analysis = Invoke-RestMethod `
    "$BaseUrl/api/v1/market-data/backfills/remaining-data-analysis?jobId=$JobId" `
    -TimeoutSec 7200
$items = @($analysis.items | Where-Object { $null -ne $_ })
$candidateCount = $analysis.secondaryBackfillCandidateCount +
    $analysis.featureExclusionCandidateCount +
    $analysis.providerAdjustmentCandidateCount +
    $analysis.verifiedMoveCandidateCount

if ([guid]$analysis.jobId -ne $JobId -or
    $analysis.unresolvedFindingCount -ne $expectedUnresolvedFindings -or
    $analysis.officialSessionFindingCount -ne $expectedOfficialFindings -or
    $analysis.peerSessionFindingCount -ne $expectedPeerFindings -or
    $analysis.coverageGapFindingCount -ne $expectedCoverageFindings -or
    $analysis.largeMoveFindingCount -ne $expectedLargeMoveFindings -or
    $items.Count -ne $expectedUnresolvedFindings -or
    $candidateCount + $analysis.keepOpenCount -ne $expectedUnresolvedFindings -or
    $analysis.candlesWritten -or
    $analysis.resolutionsWritten -or
    $analysis.planHash -notmatch '^[0-9a-f]{64}$') {
    throw 'The Batch 3 analysis does not contain one valid outcome for every reviewed finding.'
}

$qualityAfter = Invoke-RestMethod `
    "$BaseUrl/api/v1/market-data/backfills/quality?jobId=$JobId" `
    -TimeoutSec 1800
$resolutionsAfter = @(Get-CurrentResolutions -ApiBaseUrl $BaseUrl -BackfillJobId $JobId)
$latestAfter = Invoke-RestMethod "$BaseUrl/api/v1/market-data/backfills/latest" -TimeoutSec 60

Assert-EqualQualityMetrics `
    -Expected $qualityBefore `
    -Actual $qualityAfter `
    -FailureMessage 'Quality metrics changed during the read-only Batch 3 analysis.'
if ($resolutionsAfter.Count -ne $resolutionsBefore.Count -or
    $latestAfter.jobId -ne $latestBefore.jobId -or
    $latestAfter.status -ne $latestBefore.status -or
    $latestAfter.completedChunks -ne $latestBefore.completedChunks -or
    $latestAfter.failedChunks -ne $latestBefore.failedChunks -or
    $latestAfter.acceptedRows -ne $latestBefore.acceptedRows -or
    $latestAfter.rejectedRows -ne $latestBefore.rejectedRows -or
    $latestAfter.workerEnabled) {
    throw 'A resolution or backfill checkpoint changed during the read-only Batch 3 analysis.'
}

New-Item -ItemType Directory -Path $OutputDirectory -Force | Out-Null
$outputPath = Join-Path $OutputDirectory "expansion-batch-$batchNumber-analysis-$JobId.json"
$analysis | ConvertTo-Json -Depth 14 |
    Set-Content -LiteralPath $outputPath -Encoding utf8

$analysisStatus = if ($analysis.analysisComplete -and
    $analysis.keepOpenCount -eq 0 -and
    $analysis.sourceFailureCount -eq 0 -and
    $candidateCount -eq $expectedUnresolvedFindings) {
    'COMPLETED'
} else {
    'REVIEW_REQUIRED'
}

[pscustomobject]@{
    Status                          = $analysisStatus
    JobId                           = $analysis.jobId
    BatchNumber                     = $latestAfter.batchNumber
    ManifestHash                    = $normalizedHash
    PlanHash                        = $analysis.planHash
    UnresolvedFindingCount          = $analysis.unresolvedFindingCount
    OfficialSessionFindingCount     = $analysis.officialSessionFindingCount
    PeerSessionFindingCount         = $analysis.peerSessionFindingCount
    CoverageGapFindingCount         = $analysis.coverageGapFindingCount
    LargeMoveFindingCount           = $analysis.largeMoveFindingCount
    SourceRequestCount              = $analysis.sourceRequestCount
    SecondaryBackfillCandidateCount = $analysis.secondaryBackfillCandidateCount
    FeatureExclusionCandidateCount  = $analysis.featureExclusionCandidateCount
    ProviderAdjustmentCandidateCount = $analysis.providerAdjustmentCandidateCount
    VerifiedMoveCandidateCount      = $analysis.verifiedMoveCandidateCount
    CandidateCount                  = $candidateCount
    KeepOpenCount                   = $analysis.keepOpenCount
    SourceFailureCount              = $analysis.sourceFailureCount
    CandlesBefore                   = $qualityBefore.totalCandles
    CandlesAfter                    = $qualityAfter.totalCandles
    RejectedProviderRowsPreserved   = $latestAfter.rejectedRows
    ResolutionsBefore               = $resolutionsBefore.Count
    ResolutionsAfter                = $resolutionsAfter.Count
    WorkerEnabled                   = $latestAfter.workerEnabled
    FullPlanPath                    = $outputPath
} | Format-List

Write-Host ''
Write-Host 'Recommendation summary'
$items |
    Group-Object findingType, analysisStatus, recommendedResolutionType |
    Sort-Object Name |
    Select-Object Count, Name |
    Format-Table -AutoSize

$officialItems = @($items | Where-Object { $_.findingType -eq 'OFFICIAL_SPECIAL_SESSION' })
Write-Host ''
Write-Host 'Official special-session recommendations grouped by date'
$officialItems |
    Group-Object findingDate, analysisStatus, recommendedResolutionType |
    Sort-Object Name |
    Select-Object Count, Name |
    Format-Table -AutoSize

$peerItems = @($items | Where-Object { $_.findingType -eq 'PEER_CONFIRMED_SESSION' })
Write-Host ''
Write-Host 'Peer-confirmed omission recommendations grouped by instrument'
$peerItems |
    Group-Object symbol, analysisStatus, recommendedResolutionType |
    ForEach-Object {
        $group = @($_.Group)
        [pscustomobject]@{
            Symbol                    = $group[0].symbol
            FindingCount              = $group.Count
            FirstDate                 = ($group.findingDate | Sort-Object | Select-Object -First 1)
            LastDate                  = ($group.findingDate | Sort-Object | Select-Object -Last 1)
            AnalysisStatus            = $group[0].analysisStatus
            RecommendedResolutionType = $group[0].recommendedResolutionType
        }
    } |
    Sort-Object Symbol, FirstDate |
    Format-Table -AutoSize

$coverageItems = @($items | Where-Object {
    $_.findingType -in @('LEADING_COVERAGE_GAP', 'TRAILING_COVERAGE_GAP', 'SUSPICIOUS_GAP')
})
Write-Host ''
Write-Host 'Coverage recommendations'
$coverageItems |
    Sort-Object symbol, findingDate |
    Format-Table symbol, findingType, findingDate, relatedDate, exclusionFrom, exclusionTo, `
        recommendedResolutionType -AutoSize

$largeMoveItems = @($items | Where-Object { $_.findingType -eq 'LARGE_MOVE' })
Write-Host ''
Write-Host 'Large-move recommendations'
$largeMoveItems |
    Sort-Object symbol, findingDate |
    Format-Table symbol, findingDate, analysisStatus, recommendedResolutionType, `
        storedReturnPercent, officialReturnPercent, returnDifferencePercentagePoints -AutoSize

$keepOpenItems = @($items | Where-Object { $null -eq $_.recommendedResolutionType })
if ($keepOpenItems.Count -gt 0) {
    Write-Host ''
    Write-Host 'Items the application stage must keep open (grouped; complete records are in the plan JSON)'
    $keepOpenItems |
        Group-Object findingType, analysisStatus, symbol |
        Sort-Object Name |
        Select-Object Count, Name |
        Format-Table -AutoSize
}

Write-Host ''
if ($analysisStatus -eq 'COMPLETED') {
    Write-Host 'STEP 38 COMPLETE: all 7036 Batch 3 findings have one proposed action in a single immutable plan.'
    Write-Host 'Share the complete summary for review. Do not apply the plan until its hash and counts are approved.'
} else {
    Write-Host 'STEP 38 REVIEW REQUIRED: no data changed, but at least one source request or recommendation is incomplete.'
    Write-Host 'Share the complete summary. Rerunning this read-only command is safe after the source issue is reviewed.'
}
Write-Host 'No market candle, exclusion, quality resolution, or backfill checkpoint was written.'
