[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [datetime]$NextTargetDate,

    [Parameter()]
    [string]$BaseUrl = 'http://127.0.0.1:8080',

    [Parameter()]
    [string]$OutputDirectory = 'C:\MarketBrainData\Review'
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$reviewedRunId = [guid]'8a0c3e77-827d-4dc5-a9a1-30ca7523bafe'
$reviewedManifestHash = 'ff32112e159ab65e6f866888fcae02e8b20c2b4d3706d6d66cdf3868dd8e7a1e'
$expectedInstrumentCount = 500
$expectedEarliestFromDate = [datetime]'2026-09-05'
$dateText = $NextTargetDate.ToString('yyyy-MM-dd')
$expectedCalendarDays = (($NextTargetDate.Date - $expectedEarliestFromDate.Date).Days + 1) *
    $expectedInstrumentCount
$indiaNow = [TimeZoneInfo]::ConvertTimeBySystemTimeZoneId(
    [DateTimeOffset]::UtcNow,
    'India Standard Time'
)

if ($NextTargetDate.Date -ne $indiaNow.Date) {
    throw "The readiness target must be today's India date, $($indiaNow.ToString('yyyy-MM-dd'))."
}
if ($indiaNow.TimeOfDay -ge [TimeSpan]::FromHours(18)) {
    throw 'Run scheduler readiness before the 18:00 India-time provider cutoff.'
}

New-Item -ItemType Directory -Path $OutputDirectory -Force | Out-Null
$qualityCheckpointPath = Join-Path $OutputDirectory `
    "daily-enrichment-quality-checkpoints-$reviewedRunId.json"
$readinessPath = Join-Path $OutputDirectory "daily-enrichment-scheduler-readiness-$dateText.json"
$logPath = Join-Path $OutputDirectory "daily-enrichment-scheduler-readiness-$dateText.log"

if (-not (Test-Path -LiteralPath $qualityCheckpointPath -PathType Leaf)) {
    throw "The reviewed Step 52 checkpoint is missing: $qualityCheckpointPath"
}

$transcriptStarted = $false
try {
    Start-Transcript -Path $logPath -Force | Out-Null
    $transcriptStarted = $true

    $qualityCheckpoint = Get-Content -LiteralPath $qualityCheckpointPath -Raw | ConvertFrom-Json
    if ($qualityCheckpoint.status -ne 'ELIGIBLE' -or
        [guid]$qualityCheckpoint.runId -ne $reviewedRunId -or
        $qualityCheckpoint.manifestHash -ne $reviewedManifestHash -or
        $qualityCheckpoint.instrumentCount -ne $expectedInstrumentCount -or
        $qualityCheckpoint.scopedCandleCount -ne 1500 -or
        $qualityCheckpoint.providerCheckCount -ne $expectedInstrumentCount -or
        $qualityCheckpoint.providerNonMatchCount -ne 0 -or
        $qualityCheckpoint.unresolvedFindingCount -ne 0 -or
        $qualityCheckpoint.workerEnabled -or
        $qualityCheckpoint.schedulerEnabled -or
        $qualityCheckpoint.databaseWritesPerformed -or
        @($qualityCheckpoint.failedCheckpoints).Count -ne 0 -or
        @($qualityCheckpoint.changedAuditMetrics).Count -ne 0) {
        throw 'The saved Step 52 quality checkpoint is not the exact reviewed eligible result.'
    }

    $health = Invoke-RestMethod "$BaseUrl/actuator/health" -TimeoutSec 60
    if ($health.status -ne 'UP') {
        throw "MarketBrain health is $($health.status), not UP."
    }

    $telegram = Invoke-RestMethod "$BaseUrl/api/v1/telegram/status" -TimeoutSec 60
    if (-not $telegram.enabled -or -not $telegram.configured -or -not $telegram.paired -or
        $telegram.transport -ne 'LONG_POLLING' -or -not $telegram.privateChatOnly -or
        $telegram.executionMode -ne 'PAPER' -or $telegram.testAlertsEnabled) {
        throw 'Private action-free Telegram notifications are not ready for daily status delivery.'
    }

    $encodedReviewedRunId = [uri]::EscapeDataString([string]$reviewedRunId)
    $reviewedRun = Invoke-RestMethod `
        "$BaseUrl/api/v1/market-data/daily-enrichment/runs/status?runId=$encodedReviewedRunId" `
        -TimeoutSec 60
    if ($reviewedRun.status -ne 'COMPLETED' -or
        $reviewedRun.manifestHash -ne $reviewedManifestHash -or
        $reviewedRun.instruments -ne $expectedInstrumentCount -or
        $reviewedRun.completedChunks -ne $expectedInstrumentCount -or
        $reviewedRun.failedChunks -ne 0 -or
        $reviewedRun.acceptedRows -ne 1500 -or
        $reviewedRun.rejectedRows -ne 0) {
        throw 'The live first daily run no longer matches the reviewed completed checkpoint.'
    }
    if (-not $reviewedRun.workerEnabled -or -not $reviewedRun.schedulerEnabled) {
        throw 'Both the persisted worker and daily scheduler must be enabled for activation readiness.'
    }

    $preview = Invoke-RestMethod `
        "$BaseUrl/api/v1/market-data/daily-enrichment/preview?targetDate=$dateText" `
        -TimeoutSec 180
    if ($preview.databaseWritesPerformed -or
        -not $preview.workerEnabled -or
        -not $preview.schedulerEnabled -or
        $preview.schedulerCron -ne '0 0/15 16-17 * * MON-FRI' -or
        $preview.finalAttemptCron -ne '0 0 18 * * MON-FRI' -or
        [string]$preview.providerWindowStart -ne '16:00' -or
        [string]$preview.providerWindowCutoff -ne '18:00' -or
        $preview.readinessProbeCount -ne 5 -or
        $preview.targetDateFetchMode -ne 'UPSTOX_INTRADAY_DAILY' -or
        $preview.instrumentCount -ne $expectedInstrumentCount -or
        $preview.fetchInstruments -ne $expectedInstrumentCount -or
        $preview.upToDateInstruments -ne 0 -or
        $preview.blockedInstruments -ne 0 -or
        [string]$preview.earliestFromDate -ne $expectedEarliestFromDate.ToString('yyyy-MM-dd') -or
        [string]$preview.targetDate -ne $dateText -or
        $preview.totalRequestedCalendarDays -ne $expectedCalendarDays -or
        [string]$preview.manifestHash -notmatch '^[0-9a-f]{64}$') {
        throw 'The next automatic daily-enrichment preview differs from the reviewed activation checkpoint.'
    }

    $readiness = [pscustomobject]@{
        checkedAt                     = [DateTimeOffset]::Now
        status                        = 'READY_FOR_AUTOMATIC_WINDOW'
        reviewedRunId                 = $reviewedRunId
        reviewedQualityStatus         = $qualityCheckpoint.status
        nextTargetDate                = $preview.targetDate
        nextManifestHash              = $preview.manifestHash
        instrumentCount               = $preview.instrumentCount
        fetchInstruments              = $preview.fetchInstruments
        blockedInstruments            = $preview.blockedInstruments
        earliestFromDate              = $preview.earliestFromDate
        totalRequestedCalendarDays    = $preview.totalRequestedCalendarDays
        workerEnabled                 = $preview.workerEnabled
        schedulerEnabled              = $preview.schedulerEnabled
        schedulerCron                 = $preview.schedulerCron
        finalAttemptCron              = $preview.finalAttemptCron
        providerWindowStart           = $preview.providerWindowStart
        providerWindowCutoff          = $preview.providerWindowCutoff
        readinessProbeCount           = $preview.readinessProbeCount
        targetDateFetchMode           = $preview.targetDateFetchMode
        telegramEnabled               = $telegram.enabled
        telegramPaired                = $telegram.paired
        telegramTransport             = $telegram.transport
        scheduledWindowIndiaTime      = "$dateText 16:00-18:00 Asia/Kolkata"
        databaseWritesPerformed       = $false
        qualityCheckpointPath         = $qualityCheckpointPath
        fullReadinessPath             = $readinessPath
        fullLogPath                   = $logPath
    }
    $readiness | ConvertTo-Json -Depth 8 |
        Set-Content -LiteralPath $readinessPath -Encoding utf8
    $readiness | Format-List

    Write-Host ''
    Write-Host 'STEP 53 COMPLETE: automatic daily enrichment is armed for provider-gated attempts from 16:00 India time.'
    Write-Host 'No job, chunk, or candle was written by this readiness check. Keep the spare laptop awake and online.'
}
finally {
    if ($transcriptStarted) {
        Stop-Transcript | Out-Null
    }
}
