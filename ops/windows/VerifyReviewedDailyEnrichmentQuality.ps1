[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [ValidateNotNull()]
    [guid]$RunId,

    [Parameter(Mandatory)]
    [ValidatePattern('^[0-9a-f]{64}$')]
    [string]$ReviewedManifestHash,

    [Parameter()]
    [string]$BaseUrl = 'http://127.0.0.1:8080',

    [Parameter()]
    [string]$OutputDirectory = 'C:\MarketBrainData\Review'
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$expectedRunId = [guid]'8a0c3e77-827d-4dc5-a9a1-30ca7523bafe'
$expectedManifestHash = 'ff32112e159ab65e6f866888fcae02e8b20c2b4d3706d6d66cdf3868dd8e7a1e'
$expectedTargetDate = '2026-09-04'
$expectedInstruments = 500
$expectedChunks = 500
$expectedAcceptedRows = 1500
$expectedRejectedRows = 0
$manifestHash = $ReviewedManifestHash.Trim().ToLowerInvariant()

if ($RunId -ne $expectedRunId -or $manifestHash -ne $expectedManifestHash) {
    throw 'The supplied run or manifest hash is not the reviewed completed Step 51 checkpoint.'
}

New-Item -ItemType Directory -Path $OutputDirectory -Force | Out-Null
$savedRunPath = Join-Path $OutputDirectory "daily-enrichment-run-$RunId.json"
$databaseReportPath = Join-Path $OutputDirectory "daily-enrichment-database-quality-$RunId.json"
$providerReportPath = Join-Path $OutputDirectory "daily-enrichment-provider-quality-$RunId.json"
$checkpointPath = Join-Path $OutputDirectory "daily-enrichment-quality-checkpoints-$RunId.json"
$logPath = Join-Path $OutputDirectory "daily-enrichment-quality-$RunId.log"

if (-not (Test-Path -LiteralPath $savedRunPath -PathType Leaf)) {
    throw "The reviewed Step 51 result is missing: $savedRunPath"
}

$transcriptStarted = $false
try {
    Start-Transcript -Path $logPath -Force | Out-Null
    $transcriptStarted = $true

    $savedRun = Get-Content -LiteralPath $savedRunPath -Raw | ConvertFrom-Json
    if ([guid]$savedRun.runId -ne $RunId -or
        $savedRun.status -ne 'COMPLETED' -or
        [string]$savedRun.targetDate -ne $expectedTargetDate -or
        $savedRun.manifestHash -ne $manifestHash -or
        $savedRun.instruments -ne $expectedInstruments -or
        $savedRun.totalChunks -ne $expectedChunks -or
        $savedRun.completedChunks -ne $expectedChunks -or
        $savedRun.failedChunks -ne 0 -or
        $savedRun.acceptedRows -ne $expectedAcceptedRows -or
        $savedRun.rejectedRows -ne $expectedRejectedRows -or
        $savedRun.schedulerEnabled -or
        -not $savedRun.workerEnabled) {
        throw 'The saved Step 51 result differs from the reviewed completed checkpoint.'
    }

    $health = Invoke-RestMethod "$BaseUrl/actuator/health" -TimeoutSec 60
    if ($health.status -ne 'UP') {
        throw "MarketBrain health is $($health.status), not UP."
    }

    $encodedRunId = [uri]::EscapeDataString([string]$RunId)
    $runBefore = Invoke-RestMethod `
        "$BaseUrl/api/v1/market-data/daily-enrichment/runs/status?runId=$encodedRunId" `
        -TimeoutSec 60
    if ($runBefore.status -ne 'COMPLETED' -or
        [guid]$runBefore.runId -ne $RunId -or
        [string]$runBefore.targetDate -ne $expectedTargetDate -or
        $runBefore.manifestHash -ne $manifestHash -or
        $runBefore.instruments -ne $expectedInstruments -or
        $runBefore.totalChunks -ne $expectedChunks -or
        $runBefore.completedChunks -ne $expectedChunks -or
        $runBefore.failedChunks -ne 0 -or
        $runBefore.acceptedRows -ne $expectedAcceptedRows -or
        $runBefore.rejectedRows -ne $expectedRejectedRows -or
        $runBefore.connectivityFailureCount -ne 0 -or
        $runBefore.workerEnabled -or
        $runBefore.schedulerEnabled) {
        throw 'The live run is not the exact reviewed checkpoint with worker and scheduler disabled.'
    }

    Write-Host 'Running the database-only incremental quality audit...'
    $databaseQuality = Invoke-RestMethod `
        "$BaseUrl/api/v1/market-data/backfills/quality?jobId=$encodedRunId" `
        -TimeoutSec 1800

    Write-Host 'Running 500 read-only Upstox provider comparisons...'
    $providerQuality = Invoke-RestMethod `
        "$BaseUrl/api/v1/market-data/backfills/quality?jobId=$encodedRunId&providerSpotCheck=true" `
        -TimeoutSec 1800

    $checks = @($providerQuality.providerSpotChecks | Where-Object { $null -ne $_ })
    $nonMatches = @($checks | Where-Object status -ne 'MATCHED')
    $currentResolutions = @($providerQuality.currentResolutions | Where-Object { $null -ne $_ })

    $stableMetrics = @(
        'jobId', 'jobStatus', 'qualityStatus', 'requestedFrom', 'requestedTo',
        'instrumentCount', 'totalCandles', 'blockingInstrumentCount',
        'missingProviderDataInstrumentCount', 'reviewInstrumentCount', 'duplicateRows',
        'invalidRows', 'suspiciousGapCount', 'largeMoveCount', 'officialSpecialSessionCount',
        'missingOfficialSessionCount', 'unresolvedMissingOfficialSessionCount',
        'peerConfirmedSessionCount', 'missingPeerConfirmedSessionCount',
        'unresolvedMissingPeerConfirmedSessionCount', 'unresolvedSuspiciousGapCount',
        'unresolvedLargeMoveCount', 'resolvedFindingCount', 'documentedFindingCount',
        'unresolvedFindingCount', 'truncatedFindingCount', 'mutuallyAvailableTradingDateCount'
    )
    $changedMetrics = @()
    foreach ($metric in $stableMetrics) {
        $databaseProperty = $databaseQuality.PSObject.Properties[$metric]
        $providerProperty = $providerQuality.PSObject.Properties[$metric]
        if ($null -eq $databaseProperty -or $null -eq $providerProperty -or
            $databaseProperty.Value -ne $providerProperty.Value) {
            $changedMetrics += $metric
        }
    }

    $runAfter = Invoke-RestMethod `
        "$BaseUrl/api/v1/market-data/daily-enrichment/runs/status?runId=$encodedRunId" `
        -TimeoutSec 60
    $checkpointChanged =
        $runAfter.status -ne $runBefore.status -or
        $runAfter.completedChunks -ne $runBefore.completedChunks -or
        $runAfter.failedChunks -ne $runBefore.failedChunks -or
        $runAfter.acceptedRows -ne $runBefore.acceptedRows -or
        $runAfter.rejectedRows -ne $runBefore.rejectedRows -or
        $runAfter.workerEnabled -or
        $runAfter.schedulerEnabled

    $databaseQuality | ConvertTo-Json -Depth 14 |
        Set-Content -LiteralPath $databaseReportPath -Encoding utf8
    $providerQuality | ConvertTo-Json -Depth 14 |
        Set-Content -LiteralPath $providerReportPath -Encoding utf8

    $failures = @()
    if ([guid]$providerQuality.jobId -ne $RunId) { $failures += 'RunId' }
    if ($providerQuality.jobStatus -ne 'COMPLETED') { $failures += 'RunStatus' }
    if ($providerQuality.qualityStatus -ne 'PASS') { $failures += 'QualityStatus' }
    if ([string]$providerQuality.requestedFrom -ne '2026-09-02') { $failures += 'RequestedFrom' }
    if ([string]$providerQuality.requestedTo -ne $expectedTargetDate) { $failures += 'RequestedTo' }
    if ($providerQuality.instrumentCount -ne $expectedInstruments) { $failures += 'InstrumentCount' }
    if ($providerQuality.totalCandles -ne $expectedAcceptedRows) { $failures += 'ScopedCandleCount' }
    if ($providerQuality.blockingInstrumentCount -ne 0) { $failures += 'BlockingInstrumentCount' }
    if ($providerQuality.missingProviderDataInstrumentCount -ne 0) { $failures += 'MissingProviderData' }
    if ($providerQuality.reviewInstrumentCount -ne 0) { $failures += 'ReviewInstrumentCount' }
    if ($providerQuality.duplicateRows -ne 0) { $failures += 'DuplicateRows' }
    if ($providerQuality.invalidRows -ne 0) { $failures += 'InvalidRows' }
    if ($providerQuality.unresolvedMissingOfficialSessionCount -ne 0) { $failures += 'OfficialSessions' }
    if ($providerQuality.unresolvedMissingPeerConfirmedSessionCount -ne 0) { $failures += 'PeerSessions' }
    if ($providerQuality.unresolvedSuspiciousGapCount -ne 0) { $failures += 'SuspiciousGaps' }
    if ($providerQuality.unresolvedLargeMoveCount -ne 0) { $failures += 'LargeMoves' }
    if ($providerQuality.unresolvedFindingCount -ne 0) { $failures += 'UnresolvedFindings' }
    if ($providerQuality.truncatedFindingCount -ne 0) { $failures += 'TruncatedFindings' }
    if ($currentResolutions.Count -ne 0) { $failures += 'UnexpectedResolutions' }
    if (-not $providerQuality.providerSpotCheckRequested) { $failures += 'ProviderCheckNotRequested' }
    if ($checks.Count -ne $expectedInstruments) { $failures += 'ProviderCheckCount' }
    if ($nonMatches.Count -ne 0) { $failures += 'ProviderNonMatches' }
    if ($providerQuality.providerMismatchCount -ne 0) { $failures += 'ProviderMismatchCount' }
    if ($providerQuality.providerCheckFailureCount -ne 0) { $failures += 'ProviderFailureCount' }
    if (-not $providerQuality.modelTrainingEligible) { $failures += 'IncrementalTrainingEligibility' }
    if (-not $providerQuality.backtestingEligible) { $failures += 'IncrementalBacktestingEligibility' }
    if ($changedMetrics.Count -ne 0) { $failures += 'AuditMetricChanges' }
    if ($checkpointChanged) { $failures += 'RunCheckpointChanged' }

    $checkpoint = [pscustomobject]@{
        checkedAt                 = [DateTimeOffset]::Now
        status                    = if ($failures.Count -eq 0) { 'ELIGIBLE' } else { 'REVIEW_REQUIRED' }
        runId                     = $RunId
        manifestHash              = $manifestHash
        targetDate                = $expectedTargetDate
        instrumentCount           = $providerQuality.instrumentCount
        scopedCandleCount         = $providerQuality.totalCandles
        providerCheckCount        = $checks.Count
        providerNonMatchCount     = $nonMatches.Count
        unresolvedFindingCount    = $providerQuality.unresolvedFindingCount
        workerEnabled             = $runAfter.workerEnabled
        schedulerEnabled          = $runAfter.schedulerEnabled
        databaseWritesPerformed   = $false
        failedCheckpoints         = @($failures)
        changedAuditMetrics       = @($changedMetrics)
        databaseQualityReportPath = $databaseReportPath
        providerQualityReportPath = $providerReportPath
        fullLogPath               = $logPath
    }
    $checkpoint | ConvertTo-Json -Depth 8 |
        Set-Content -LiteralPath $checkpointPath -Encoding utf8

    $checkpoint | Format-List
    if ($nonMatches.Count -gt 0) {
        $nonMatches | Format-Table symbol, status, comparisonDate, storedClose, providerClose, differencePercent -AutoSize
    }
    if ($failures.Count -gt 0) {
        throw "STEP 52 REVIEW REQUIRED: failed checkpoints: $($failures -join ', ')."
    }

    Write-Host ''
    Write-Host 'STEP 52 COMPLETE: the first incremental run passed all database and 500 live provider checks.'
    Write-Host 'The audit was read-only. Keep the worker and scheduler disabled until scheduler activation is reviewed.'
}
finally {
    if ($transcriptStarted) {
        Stop-Transcript | Out-Null
    }
}
