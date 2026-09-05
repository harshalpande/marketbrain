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
    [string]$ReviewedPlanHash,
    [Parameter(Mandatory)]
    [ValidatePattern('^[0-9a-fA-F]{64}$')]
    [string]$ReviewedInvestigationHash,
    [string]$BaseUrl = 'http://127.0.0.1:8080',
    [string]$OutputDirectory = 'C:\MarketBrainData\Review'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$batchNumber = 3
$expectedInstrumentCount = 200
$expectedTotalChunks = 2320
$expectedUpstoxCandles = 550050
$expectedRejectedRows = 6
$expectedFindings = 7036
$minimumSecondaryItems = 1466
$maximumSecondaryItems = 1469
$expectedAdjustmentItems = 20
$expectedVerifiedMoveItems = 68
$reviewer = $ReviewedBy.Trim()
$manifestHash = $ReviewedManifestHash.Trim().ToLowerInvariant()
$incompletePlanHash = $ReviewedPlanHash.Trim().ToLowerInvariant()
$investigationHash = $ReviewedInvestigationHash.Trim().ToLowerInvariant()
$reviewedInvestigationHash = 'ca4e015b127f9593689f8895081f2bdd9c59d252f871cbbffedd6bf94dfb0ca2'
$reviewedCorrectedPlanHash = '6c26708b6aeadd4988fafb1aefcf21289a22dd5a3205c0851bf9b7b10ce3e82c'
$investigationPath = Join-Path $OutputDirectory `
    "expansion-batch-$batchNumber-open-findings-investigation-$JobId.json"
$correctedAnalysisPath = Join-Path $OutputDirectory `
    "expansion-batch-$batchNumber-corrected-analysis-$JobId.json"
$checkpointPath = Join-Path $OutputDirectory `
    "expansion-batch-$batchNumber-step40-checkpoints-$JobId.json"
$logPath = Join-Path $OutputDirectory `
    "expansion-batch-$batchNumber-step40-$JobId.log"

New-Item -ItemType Directory -Path $OutputDirectory -Force | Out-Null

if ([string]::IsNullOrWhiteSpace($reviewer)) {
    throw 'ReviewedBy must contain the name of the person approving the investigated Batch 3 corrections.'
}
if ($investigationHash -ne $reviewedInvestigationHash) {
    throw 'The supplied investigation hash is not the reviewed Step 39 evidence hash.'
}
if (-not (Test-Path -LiteralPath $investigationPath -PathType Leaf)) {
    throw 'The complete reviewed Step 39 investigation report is missing.'
}

$investigation = Get-Content -LiteralPath $investigationPath -Raw | ConvertFrom-Json
if ($investigation.status -ne 'COMPLETED' -or
    [guid]$investigation.jobId -ne $JobId -or
    $investigation.batchNumber -ne $batchNumber -or
    $investigation.reviewedManifestHash -ne $manifestHash -or
    $investigation.reviewedPlanHash -ne $incompletePlanHash -or
    $investigation.investigationHash -ne $investigationHash -or
    $investigation.openFindingCount -ne 10 -or
    $investigation.sourceFailureFindingCount -ne 4 -or
    $investigation.historicalIdentityFindingCount -ne 5 -or
    $investigation.prelistingFindingCount -ne 1 -or
    $investigation.archiveRequestCount -ne 7 -or
    $investigation.candlesBefore -ne $expectedUpstoxCandles -or
    $investigation.candlesAfter -ne $expectedUpstoxCandles -or
    $investigation.resolutionsBefore -ne 0 -or
    $investigation.resolutionsAfter -ne 0 -or
    $investigation.workerEnabled) {
    throw 'The saved Step 39 report is not the exact reviewed read-only investigation.'
}

function Get-CurrentResolutions {
    param(
        [Parameter(Mandatory)][string]$ApiBaseUrl,
        [Parameter(Mandatory)][guid]$BackfillJobId
    )

    $response = Invoke-RestMethod `
        "$ApiBaseUrl/api/v1/market-data/backfills/quality-resolutions?jobId=$BackfillJobId" `
        -TimeoutSec 900
    return @($response | Where-Object { $null -ne $_ })
}

function Get-IsoDate {
    param([Parameter(Mandatory)]$Value)
    return ([datetime]$Value).ToString('yyyy-MM-dd')
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
    $latestBefore.completedChunks -ne $expectedTotalChunks -or
    $latestBefore.failedChunks -ne 0 -or
    $latestBefore.acceptedRows -ne $expectedUpstoxCandles -or
    $latestBefore.rejectedRows -ne $expectedRejectedRows -or
    $latestBefore.workerEnabled) {
    throw 'The live job is not the exact reviewed completed Batch 3 checkpoint.'
}

$analysis = $null
$persistedPlan = $null
if (Test-Path -LiteralPath $correctedAnalysisPath -PathType Leaf) {
    $savedAnalysis = Get-Content -LiteralPath $correctedAnalysisPath -Raw | ConvertFrom-Json
    if ([guid]$savedAnalysis.jobId -eq $JobId -and
        $savedAnalysis.planHash -match '^[0-9a-f]{64}$' -and
        $savedAnalysis.analysisComplete) {
        $analysis = $savedAnalysis
        try {
            $encodedSavedHash = [uri]::EscapeDataString($analysis.planHash)
            $persistedPlan = Invoke-RestMethod `
                "$BaseUrl/api/v1/market-data/backfills/remaining-data-remediation/status?jobId=$JobId&expectedPlanHash=$encodedSavedHash" `
                -TimeoutSec 900
        } catch {
            $statusCode = 0
            if ($null -ne $_.Exception.Response) {
                $statusCode = [int]$_.Exception.Response.StatusCode
            }
            if ($statusCode -ne 404) {
                throw
            }
        }
    }
}

$qualityBefore = Invoke-RestMethod "$BaseUrl/api/v1/market-data/backfills/quality?jobId=$JobId" -TimeoutSec 1800
$resolutionsBefore = @(Get-CurrentResolutions -ApiBaseUrl $BaseUrl -BackfillJobId $JobId)
if ($null -eq $persistedPlan -and
    ($qualityBefore.totalCandles -ne $expectedUpstoxCandles -or
     $qualityBefore.unresolvedFindingCount -ne $expectedFindings -or
     $resolutionsBefore.Count -ne 0)) {
    throw 'The live database is not the exact reviewed pre-remediation Batch 3 checkpoint.'
}

if ($null -eq $analysis) {
    Write-Host 'Regenerating all 7036 recommendations with the reviewed parser, identities, and pre-listing rule...'
    $analysis = Invoke-RestMethod `
        "$BaseUrl/api/v1/market-data/backfills/remaining-data-analysis?jobId=$JobId" `
        -TimeoutSec 7200
} elseif ($null -ne $persistedPlan) {
    Write-Host "Resuming durable plan $($analysis.planHash); completed items will not be repeated."
} else {
    Write-Host "Reusing locally saved corrected plan $($analysis.planHash); the live database is still unchanged."
}
$items = @($analysis.items | Where-Object { $null -ne $_ })
$candidateCount = $analysis.secondaryBackfillCandidateCount +
    $analysis.featureExclusionCandidateCount +
    $analysis.providerAdjustmentCandidateCount +
    $analysis.verifiedMoveCandidateCount
$formerlyOpenItems = @($items | Where-Object {
    $findingDate = Get-IsoDate $_.findingDate
    ($_.findingType -eq 'LARGE_MOVE' -and $_.symbol -eq 'CGCL' -and
        $findingDate -in @('2011-11-28', '2012-08-07')) -or
    ($_.findingType -eq 'LARGE_MOVE' -and $_.symbol -eq 'COFORGE' -and
        $findingDate -in @('2020-03-23', '2020-03-25')) -or
    ($_.findingType -eq 'LARGE_MOVE' -and $_.symbol -eq 'LTFOODS' -and
        $findingDate -eq '2013-08-20') -or
    ($_.findingType -eq 'LARGE_MOVE' -and $_.symbol -eq 'DELHIVERY' -and
        $findingDate -eq '2016-03-08') -or
    ($_.findingType -eq 'PEER_CONFIRMED_SESSION' -and
        $_.symbol -in @('DELHIVERY', 'HOMEFIRST', 'KFINTECH', 'LATENTVIEW') -and
        $findingDate -eq '2020-07-13')
})
$unresolvedFormerlyOpenItems = @($formerlyOpenItems | Where-Object {
    $null -eq $_.recommendedResolutionType
})
$formerlyOpenFeatureExclusions = @($formerlyOpenItems | Where-Object {
    $_.recommendedResolutionType -eq 'FEATURE_WINDOW_EXCLUDED'
})
$formerlyOpenVerifiedMoves = @($formerlyOpenItems | Where-Object {
    $_.recommendedResolutionType -eq 'VERIFIED_EXCHANGE_MOVE'
})
$formerlyOpenProviderAdjustments = @($formerlyOpenItems | Where-Object {
    $_.recommendedResolutionType -eq 'PROVIDER_ADJUSTMENT'
})
$historicalIdentityMatches = @($formerlyOpenItems | Where-Object {
    $_.officialSymbol -in @('MMFSL', 'NIITTECH', 'DAAWAT') -and
    $_.matchBasis -in @('HISTORICAL_ISIN', 'HISTORICAL_SYMBOL')
})
$correctedSecondaryItems = [int]$analysis.secondaryBackfillCandidateCount
$correctedExclusionItems = [int]$analysis.featureExclusionCandidateCount
$correctedAllSourceCandles = $expectedUpstoxCandles + $correctedSecondaryItems

$expectedExclusionItems = $expectedFindings - $correctedSecondaryItems -
    $expectedAdjustmentItems - $expectedVerifiedMoveItems
$checkpointResults = @(
    [pscustomobject]@{ Checkpoint = 'JobId'; Expected = [string]$JobId; Actual = [string]$analysis.jobId; Passed = ([string]$analysis.jobId -eq [string]$JobId) }
    [pscustomobject]@{ Checkpoint = 'AnalysisComplete'; Expected = 'True'; Actual = [string]$analysis.analysisComplete; Passed = [bool]$analysis.analysisComplete }
    [pscustomobject]@{ Checkpoint = 'UnresolvedFindingCount'; Expected = [string]$expectedFindings; Actual = [string]$analysis.unresolvedFindingCount; Passed = ($analysis.unresolvedFindingCount -eq $expectedFindings) }
    [pscustomobject]@{ Checkpoint = 'OfficialSessionFindingCount'; Expected = '1450'; Actual = [string]$analysis.officialSessionFindingCount; Passed = ($analysis.officialSessionFindingCount -eq 1450) }
    [pscustomobject]@{ Checkpoint = 'PeerSessionFindingCount'; Expected = '5469'; Actual = [string]$analysis.peerSessionFindingCount; Passed = ($analysis.peerSessionFindingCount -eq 5469) }
    [pscustomobject]@{ Checkpoint = 'CoverageGapFindingCount'; Expected = '28'; Actual = [string]$analysis.coverageGapFindingCount; Passed = ($analysis.coverageGapFindingCount -eq 28) }
    [pscustomobject]@{ Checkpoint = 'LargeMoveFindingCount'; Expected = '89'; Actual = [string]$analysis.largeMoveFindingCount; Passed = ($analysis.largeMoveFindingCount -eq 89) }
    [pscustomobject]@{ Checkpoint = 'SourceRequestCount'; Expected = '2074'; Actual = [string]$analysis.sourceRequestCount; Passed = ($analysis.sourceRequestCount -eq 2074) }
    [pscustomobject]@{ Checkpoint = 'SecondaryBackfillCandidateCount'; Expected = "$minimumSecondaryItems..$maximumSecondaryItems"; Actual = [string]$correctedSecondaryItems; Passed = ($correctedSecondaryItems -ge $minimumSecondaryItems -and $correctedSecondaryItems -le $maximumSecondaryItems) }
    [pscustomobject]@{ Checkpoint = 'FeatureExclusionCandidateCount'; Expected = [string]$expectedExclusionItems; Actual = [string]$correctedExclusionItems; Passed = ($correctedExclusionItems -eq $expectedExclusionItems) }
    [pscustomobject]@{ Checkpoint = 'ProviderAdjustmentCandidateCount'; Expected = [string]$expectedAdjustmentItems; Actual = [string]$analysis.providerAdjustmentCandidateCount; Passed = ($analysis.providerAdjustmentCandidateCount -eq $expectedAdjustmentItems) }
    [pscustomobject]@{ Checkpoint = 'VerifiedMoveCandidateCount'; Expected = [string]$expectedVerifiedMoveItems; Actual = [string]$analysis.verifiedMoveCandidateCount; Passed = ($analysis.verifiedMoveCandidateCount -eq $expectedVerifiedMoveItems) }
    [pscustomobject]@{ Checkpoint = 'CandidateCount'; Expected = [string]$expectedFindings; Actual = [string]$candidateCount; Passed = ($candidateCount -eq $expectedFindings) }
    [pscustomobject]@{ Checkpoint = 'KeepOpenCount'; Expected = '0'; Actual = [string]$analysis.keepOpenCount; Passed = ($analysis.keepOpenCount -eq 0) }
    [pscustomobject]@{ Checkpoint = 'SourceFailureCount'; Expected = '0'; Actual = [string]$analysis.sourceFailureCount; Passed = ($analysis.sourceFailureCount -eq 0) }
    [pscustomobject]@{ Checkpoint = 'PlanHash'; Expected = $reviewedCorrectedPlanHash; Actual = [string]$analysis.planHash; Passed = ($analysis.planHash -eq $reviewedCorrectedPlanHash) }
    [pscustomobject]@{ Checkpoint = 'CandlesWritten'; Expected = 'False'; Actual = [string]$analysis.candlesWritten; Passed = (-not [bool]$analysis.candlesWritten) }
    [pscustomobject]@{ Checkpoint = 'ResolutionsWritten'; Expected = 'False'; Actual = [string]$analysis.resolutionsWritten; Passed = (-not [bool]$analysis.resolutionsWritten) }
    [pscustomobject]@{ Checkpoint = 'AnalysisItemCount'; Expected = [string]$expectedFindings; Actual = [string]$items.Count; Passed = ($items.Count -eq $expectedFindings) }
    [pscustomobject]@{ Checkpoint = 'InvestigatedItemCount'; Expected = '10'; Actual = [string]$formerlyOpenItems.Count; Passed = ($formerlyOpenItems.Count -eq 10) }
    [pscustomobject]@{ Checkpoint = 'UnresolvedInvestigatedItemCount'; Expected = '0'; Actual = [string]$unresolvedFormerlyOpenItems.Count; Passed = ($unresolvedFormerlyOpenItems.Count -eq 0) }
    [pscustomobject]@{ Checkpoint = 'InvestigatedFeatureExclusionCount'; Expected = '5'; Actual = [string]$formerlyOpenFeatureExclusions.Count; Passed = ($formerlyOpenFeatureExclusions.Count -eq 5) }
    [pscustomobject]@{ Checkpoint = 'InvestigatedVerifiedMoveCount'; Expected = '3'; Actual = [string]$formerlyOpenVerifiedMoves.Count; Passed = ($formerlyOpenVerifiedMoves.Count -eq 3) }
    [pscustomobject]@{ Checkpoint = 'InvestigatedProviderAdjustmentCount'; Expected = '2'; Actual = [string]$formerlyOpenProviderAdjustments.Count; Passed = ($formerlyOpenProviderAdjustments.Count -eq 2) }
    [pscustomobject]@{ Checkpoint = 'HistoricalIdentityMatchCount'; Expected = '5'; Actual = [string]$historicalIdentityMatches.Count; Passed = ($historicalIdentityMatches.Count -eq 5) }
)
$failedCheckpoints = @($checkpointResults | Where-Object { -not $_.Passed })

# Preserve the expensive read-only response before any reviewed checkpoint can fail.
$analysis | ConvertTo-Json -Depth 14 |
    Set-Content -LiteralPath $correctedAnalysisPath -Encoding utf8

$checkpointReport = [pscustomobject]@{
    status = if ($failedCheckpoints.Count -eq 0) { 'PASSED' } else { 'REVIEW_REQUIRED' }
    checkedAt = [DateTimeOffset]::Now
    jobId = $JobId
    correctedAnalysisPath = $correctedAnalysisPath
    checkpointPath = $checkpointPath
    logPath = $logPath
    failedCheckpointCount = $failedCheckpoints.Count
    checkpoints = $checkpointResults
    investigatedItems = $formerlyOpenItems
}
$checkpointReport | ConvertTo-Json -Depth 10 |
    Set-Content -LiteralPath $checkpointPath -Encoding utf8

$logSections = @(
    "MarketBrain Batch 3 Step 40 checkpoint report"
    "Checked at: $([DateTimeOffset]::Now.ToString('o'))"
    "Job ID: $JobId"
    "Failed checkpoint count: $($failedCheckpoints.Count)"
    "Full analysis: $correctedAnalysisPath"
    "Checkpoint JSON: $checkpointPath"
    ''
    'All checkpoints'
    ($checkpointResults | Format-Table Checkpoint, Expected, Actual, Passed -AutoSize | Out-String)
    'Ten investigated findings selected by type, symbol, and date'
    ($formerlyOpenItems | Sort-Object symbol, findingDate |
        Format-Table symbol, findingType, findingDate, analysisStatus,
            recommendedResolutionType, officialSymbol, matchBasis -AutoSize | Out-String)
)
$logSections | Set-Content -LiteralPath $logPath -Encoding utf8

if ($failedCheckpoints.Count -gt 0) {
    Write-Host ''
    Write-Host 'Corrected analysis checkpoint failures'
    $failedCheckpoints | Format-Table Checkpoint, Expected, Actual -AutoSize
    Write-Host "Full analysis saved to $correctedAnalysisPath"
    Write-Host "Checkpoint report saved to $checkpointPath"
    Write-Host "Shareable text log saved to $logPath"
    throw "The corrected analysis failed $($failedCheckpoints.Count) reviewed checkpoint(s); no remediation was requested. Share the checkpoint JSON and text log."
}

[pscustomobject]@{
    Status = 'CORRECTED_PLAN_VERIFIED'
    JobId = $analysis.jobId
    InvestigationHash = $investigationHash
    CorrectedPlanHash = $analysis.planHash
    TotalItems = $candidateCount
    SecondaryBackfillItems = $analysis.secondaryBackfillCandidateCount
    FeatureExclusionItems = $analysis.featureExclusionCandidateCount
    ProviderAdjustmentItems = $analysis.providerAdjustmentCandidateCount
    VerifiedMoveItems = $analysis.verifiedMoveCandidateCount
    KeepOpenCount = $analysis.keepOpenCount
    SourceFailureCount = $analysis.sourceFailureCount
    FullCorrectedAnalysisPath = $correctedAnalysisPath
} | Format-List

Write-Host ''
Write-Host 'The ten previously open findings now have these governed actions'
$formerlyOpenItems |
    Sort-Object symbol, findingDate |
    Format-Table symbol, findingType, findingDate, analysisStatus, recommendedResolutionType, `
        officialSymbol, matchBasis -AutoSize

Write-Host ''
Write-Host 'Every corrected-plan invariant passed. Applying all 7036 reviewed actions now...'
$request = @{
    jobId = $JobId
    expectedPlanHash = $analysis.planHash
    reviewedBy = $reviewer
} | ConvertTo-Json

$result = $null
try {
    $result = Invoke-RestMethod `
        -Method Post `
        -Uri "$BaseUrl/api/v1/market-data/backfills/remaining-data-remediation/apply" `
        -ContentType 'application/json' `
        -Body $request `
        -TimeoutSec 7200
} catch {
    Write-Warning 'The application response was interrupted. Checking the durable checkpoint before failing.'
    try {
        $encodedHash = [uri]::EscapeDataString($analysis.planHash)
        $result = Invoke-RestMethod `
            "$BaseUrl/api/v1/market-data/backfills/remaining-data-remediation/status?jobId=$JobId&expectedPlanHash=$encodedHash" `
            -TimeoutSec 900
    } catch {
        throw 'The correction response and durable checkpoint are unavailable. Do not alter data; rerun this exact command after connectivity returns.'
    }
}

$resultPath = Join-Path $OutputDirectory "expansion-batch-$batchNumber-remediation-$JobId.json"
$result | ConvertTo-Json -Depth 14 | Set-Content -LiteralPath $resultPath -Encoding utf8

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
    $failures | Format-Table symbol, findingType, findingDate, errorCode, detail -Wrap
}

if ([guid]$result.jobId -ne $JobId -or
    $result.planHash -ne $analysis.planHash -or
    $result.status -ne 'COMPLETED' -or
    $result.totalItems -ne $expectedFindings -or
    $result.pendingItems -ne 0 -or
    $result.completedItems -ne $expectedFindings -or
    $result.failedItems -ne 0 -or
    $result.secondaryBackfillItems -ne $correctedSecondaryItems -or
    $result.featureExclusionItems -ne $correctedExclusionItems -or
    $result.providerAdjustmentItems -ne $expectedAdjustmentItems -or
    $result.secondaryCandlesReady -ne $correctedSecondaryItems -or
    $result.upstoxDailyCandleCount -ne $expectedUpstoxCandles -or
    $result.secondaryDailyCandleCount -ne $correctedSecondaryItems -or
    $result.allSourceDailyCandleCount -ne $correctedAllSourceCandles -or
    $result.planResolutionsWritten -ne $expectedFindings -or
    $result.currentResolutionCount -ne $expectedFindings -or
    $result.unresolvedFindingCount -ne 0 -or
    $result.workerEnabled -or
    -not $result.finalProviderSpotCheckRequired) {
    throw 'The Batch 3 remediation returned, but one or more reviewed final invariants differ.'
}

Write-Host ''
Write-Host 'STEP 40 COMPLETE: all 7036 reviewed Batch 3 corrections are durable and every checkpoint passed.'
Write-Host "The original $expectedUpstoxCandles Upstox candles were preserved; $correctedSecondaryItems official NSE candles were added separately."
Write-Host "$correctedExclusionItems feature exclusions, $expectedAdjustmentItems provider adjustments, and $expectedVerifiedMoveItems verified moves were recorded."
Write-Host "The complete result was saved to $resultPath."
Write-Host 'A final read-only provider quality audit is required before Batch 4 is prepared.'
