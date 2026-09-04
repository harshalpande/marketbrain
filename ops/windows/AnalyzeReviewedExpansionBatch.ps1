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

$normalizedHash = $ReviewedManifestHash.Trim().ToLowerInvariant()
$creationPath = Join-Path $OutputDirectory "expansion-batch-2-created-$JobId.json"
$recoveryPath = Join-Path $OutputDirectory "expansion-batch-2-beml-recovery-$JobId.json"
$databaseAuditPath = Join-Path $OutputDirectory "expansion-batch-2-database-quality-$JobId.json"
$providerAuditPath = Join-Path $OutputDirectory "expansion-batch-2-provider-quality-$JobId.json"
$requiredPaths = @($creationPath, $recoveryPath, $databaseAuditPath, $providerAuditPath)
if (@($requiredPaths | Where-Object { -not (Test-Path -LiteralPath $_ -PathType Leaf) }).Count -ne 0) {
    throw 'One or more reviewed Batch 2 checkpoint or Step 28 audit reports are missing.'
}

$creationReport = Get-Content -LiteralPath $creationPath -Raw | ConvertFrom-Json
$recoveryReport = Get-Content -LiteralPath $recoveryPath -Raw | ConvertFrom-Json
$databaseAudit = Get-Content -LiteralPath $databaseAuditPath -Raw | ConvertFrom-Json
$providerAudit = Get-Content -LiteralPath $providerAuditPath -Raw | ConvertFrom-Json
$providerAuditChecks = @($providerAudit.providerSpotChecks | Where-Object { $null -ne $_ })
$providerAuditNonMatches = @($providerAuditChecks | Where-Object { $_.status -ne 'MATCHED' })
$auditResolutions = @($providerAudit.currentResolutions | Where-Object { $null -ne $_ })

if ($creationReport.reviewedManifestHash -ne $normalizedHash -or
    $recoveryReport.reviewedManifestHash -ne $normalizedHash -or
    [guid]$creationReport.verifiedStatus.jobId -ne $JobId -or
    [guid]$recoveryReport.status.jobId -ne $JobId -or
    [guid]$databaseAudit.jobId -ne $JobId -or
    [guid]$providerAudit.jobId -ne $JobId) {
    throw 'The reviewed manifest, checkpoint reports, and Step 28 reports do not identify the same Batch 2 job.'
}

Assert-EqualQualityMetrics `
    -Expected $providerAudit `
    -Actual $databaseAudit `
    -FailureMessage 'The saved Step 28 database and provider reports do not agree.'

if ($recoveryReport.status.status -ne 'COMPLETED' -or
    $recoveryReport.status.completedChunks -ne 623 -or
    $recoveryReport.status.failedChunks -ne 0 -or
    $recoveryReport.status.acceptedRows -ne 149636 -or
    $recoveryReport.status.rejectedRows -ne 0 -or
    $providerAudit.jobStatus -ne 'COMPLETED' -or
    $providerAudit.instrumentCount -ne 50 -or
    $providerAudit.totalCandles -ne 149636 -or
    $providerAudit.blockingInstrumentCount -ne 0 -or
    $providerAudit.duplicateRows -ne 0 -or
    $providerAudit.invalidRows -ne 0 -or
    $providerAudit.missingOfficialSessionCount -ne 423 -or
    $providerAudit.unresolvedMissingOfficialSessionCount -ne 423 -or
    $providerAudit.missingPeerConfirmedSessionCount -ne 71 -or
    $providerAudit.unresolvedMissingPeerConfirmedSessionCount -ne 71 -or
    $providerAudit.suspiciousGapCount -ne 1 -or
    $providerAudit.unresolvedSuspiciousGapCount -ne 1 -or
    $providerAudit.largeMoveCount -ne 19 -or
    $providerAudit.unresolvedLargeMoveCount -ne 19 -or
    $providerAudit.unresolvedFindingCount -ne 515 -or
    $providerAudit.truncatedFindingCount -ne 0 -or
    -not $providerAudit.providerSpotCheckRequested -or
    $providerAuditChecks.Count -ne 50 -or
    $providerAuditNonMatches.Count -ne 0 -or
    $providerAudit.providerMismatchCount -ne 0 -or
    $providerAudit.providerCheckFailureCount -ne 0) {
    throw 'The saved Step 28 evidence does not match the reviewed Batch 2 quality checkpoint.'
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

$qualityBefore = Invoke-RestMethod `
    "$BaseUrl/api/v1/market-data/backfills/quality?jobId=$JobId" `
    -TimeoutSec 900
$resolutionsBefore = @(Get-CurrentResolutions -ApiBaseUrl $BaseUrl -BackfillJobId $JobId)

Assert-EqualQualityMetrics `
    -Expected $providerAudit `
    -Actual $qualityBefore `
    -FailureMessage 'The live quality checkpoint has drifted since Step 28.'
if ($resolutionsBefore.Count -ne $auditResolutions.Count) {
    throw 'The number of Batch 2 quality resolutions has changed since Step 28.'
}

Write-Host 'Analyzing all 515 unresolved Batch 2 findings in one read-only request...'
$analysis = Invoke-RestMethod `
    "$BaseUrl/api/v1/market-data/backfills/remaining-data-analysis?jobId=$JobId" `
    -TimeoutSec 3600
$items = @($analysis.items | Where-Object { $null -ne $_ })
$candidateCount = $analysis.secondaryBackfillCandidateCount +
    $analysis.featureExclusionCandidateCount +
    $analysis.providerAdjustmentCandidateCount +
    $analysis.verifiedMoveCandidateCount

if ([guid]$analysis.jobId -ne $JobId -or
    $analysis.unresolvedFindingCount -ne 515 -or
    $analysis.officialSessionFindingCount -ne 423 -or
    $analysis.peerSessionFindingCount -ne 71 -or
    $analysis.coverageGapFindingCount -ne 2 -or
    $analysis.largeMoveFindingCount -ne 19 -or
    $items.Count -ne 515 -or
    $candidateCount + $analysis.keepOpenCount -ne 515 -or
    $analysis.candlesWritten -or
    $analysis.resolutionsWritten -or
    $analysis.planHash -notmatch '^[0-9a-f]{64}$') {
    throw 'The Batch 2 analysis does not contain one valid outcome for every reviewed finding.'
}

$qualityAfter = Invoke-RestMethod `
    "$BaseUrl/api/v1/market-data/backfills/quality?jobId=$JobId" `
    -TimeoutSec 900
$resolutionsAfter = @(Get-CurrentResolutions -ApiBaseUrl $BaseUrl -BackfillJobId $JobId)
$latestAfter = Invoke-RestMethod "$BaseUrl/api/v1/market-data/backfills/latest" -TimeoutSec 60

Assert-EqualQualityMetrics `
    -Expected $qualityBefore `
    -Actual $qualityAfter `
    -FailureMessage 'Quality metrics changed during the read-only Batch 2 analysis.'
if ($resolutionsAfter.Count -ne $resolutionsBefore.Count -or
    $latestAfter.jobId -ne $latestBefore.jobId -or
    $latestAfter.status -ne $latestBefore.status -or
    $latestAfter.completedChunks -ne $latestBefore.completedChunks -or
    $latestAfter.failedChunks -ne $latestBefore.failedChunks -or
    $latestAfter.acceptedRows -ne $latestBefore.acceptedRows -or
    $latestAfter.rejectedRows -ne $latestBefore.rejectedRows -or
    $latestAfter.workerEnabled) {
    throw 'A resolution or backfill checkpoint changed during the read-only Batch 2 analysis.'
}

New-Item -ItemType Directory -Path $OutputDirectory -Force | Out-Null
$outputPath = Join-Path $OutputDirectory "expansion-batch-2-analysis-$JobId.json"
$analysis | ConvertTo-Json -Depth 14 |
    Set-Content -LiteralPath $outputPath -Encoding utf8

$analysisStatus = if ($analysis.analysisComplete -and
    $analysis.keepOpenCount -eq 0 -and
    $analysis.sourceFailureCount -eq 0 -and
    $candidateCount -eq 515) {
    'COMPLETED'
} else {
    'REVIEW_REQUIRED'
}

[pscustomobject]@{
    Status                              = $analysisStatus
    JobId                               = $analysis.jobId
    BatchNumber                         = $latestAfter.batchNumber
    ManifestHash                        = $normalizedHash
    PlanHash                            = $analysis.planHash
    UnresolvedFindingCount              = $analysis.unresolvedFindingCount
    OfficialSessionFindingCount         = $analysis.officialSessionFindingCount
    PeerSessionFindingCount             = $analysis.peerSessionFindingCount
    CoverageGapFindingCount             = $analysis.coverageGapFindingCount
    LargeMoveFindingCount               = $analysis.largeMoveFindingCount
    SourceRequestCount                  = $analysis.sourceRequestCount
    SecondaryBackfillCandidateCount     = $analysis.secondaryBackfillCandidateCount
    FeatureExclusionCandidateCount      = $analysis.featureExclusionCandidateCount
    ProviderAdjustmentCandidateCount    = $analysis.providerAdjustmentCandidateCount
    VerifiedMoveCandidateCount          = $analysis.verifiedMoveCandidateCount
    CandidateCount                      = $candidateCount
    KeepOpenCount                       = $analysis.keepOpenCount
    SourceFailureCount                  = $analysis.sourceFailureCount
    CandlesBefore                       = $qualityBefore.totalCandles
    CandlesAfter                        = $qualityAfter.totalCandles
    ResolutionsBefore                   = $resolutionsBefore.Count
    ResolutionsAfter                    = $resolutionsAfter.Count
    WorkerEnabled                       = $latestAfter.workerEnabled
    FullPlanPath                        = $outputPath
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
Write-Host 'Peer-confirmed omission incidents'
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
    Write-Host 'Items that the application step must not change'
    $keepOpenItems |
        Sort-Object findingType, symbol, findingDate |
        Format-Table findingType, symbol, findingDate, analysisStatus, detail -Wrap
}

Write-Host ''
if ($analysisStatus -eq 'COMPLETED') {
    Write-Host 'STEP 29 COMPLETE: all 515 findings have one proposed action in a single immutable plan.'
    Write-Host 'Share the complete summary for review. Do not apply the plan until its hash and counts are approved.'
} else {
    Write-Host 'STEP 29 REVIEW REQUIRED: no data changed, but at least one source request or recommendation is incomplete.'
    Write-Host 'Share the complete summary. Rerunning this read-only command is safe after the source issue is reviewed.'
}
Write-Host 'No market candle, exclusion, or quality resolution was written.'
