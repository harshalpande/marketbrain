[CmdletBinding()]
param(
    [Parameter()]
    [string]$DatasetRunId,

    [Parameter()]
    [string]$Model = 'ibm/granite4.1:8b',

    [Parameter()]
    [int[]]$CandidateLimits = @(5, 8, 12),

    [Parameter()]
    [ValidateSet(5, 20, 60)]
    [int]$RankingHorizonSessions = 20,

    [Parameter()]
    [string]$BaseUrl = 'http://127.0.0.1:8080',

    [Parameter()]
    [string]$OutputDirectory = 'C:\MarketBrainData\Review'
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

foreach ($limit in $CandidateLimits) {
    if ($limit -lt 1 -or $limit -gt 25) {
        throw 'CandidateLimits values must be between 1 and 25.'
    }
}
if ($CandidateLimits.Count -gt 5) {
    throw 'At most five candidate limits can be calibrated in one run.'
}

New-Item -ItemType Directory -Path $OutputDirectory -Force | Out-Null
$suffix = if ([string]::IsNullOrWhiteSpace($DatasetRunId)) { 'latest' } else { $DatasetRunId }
$safeModel = $Model -replace '[^A-Za-z0-9._-]', '_'
$limitText = ($CandidateLimits | ForEach-Object { [string]$_ }) -join '-'
$stem = "prototype-swing-ollama-score-calibration-$suffix-$safeModel-h$RankingHorizonSessions-limits-$limitText"
$resultPath = Join-Path $OutputDirectory "$stem.json"
$logPath = Join-Path $OutputDirectory "$stem.log"
$transcriptStarted = $false

try {
    Start-Transcript -Path $logPath -Force | Out-Null
    $transcriptStarted = $true

    $health = Invoke-RestMethod "$BaseUrl/actuator/health" -TimeoutSec 60
    if ($health.status -ne 'UP') {
        throw "MarketBrain health is $($health.status), not UP."
    }

    Write-Host 'Step 69: calibrating Ollama score scale across bounded candidate batches...'
    Write-Host 'This may call Ollama once per candidate limit and remains review-only.'
    Write-Host 'No database write, signal, paper fill, order, broker action, or live trading action will be created.'

    $body = [ordered]@{
        model                  = $Model
        candidateLimits        = @($CandidateLimits)
        rankingHorizonSessions = $RankingHorizonSessions
    }
    if (-not [string]::IsNullOrWhiteSpace($DatasetRunId)) {
        $body['datasetRunId'] = $DatasetRunId
    }

    $preview = Invoke-RestMethod `
        -Method Post `
        -Uri "$BaseUrl/api/v1/training/prototype-swing-ollama-score-calibration-preview" `
        -ContentType 'application/json' `
        -Body ($body | ConvertTo-Json -Depth 8) `
        -TimeoutSec 2400

    $preview | ConvertTo-Json -Depth 32 |
        Set-Content -LiteralPath $resultPath -Encoding utf8

    $preview | Select-Object status, datasetRunId, model, asOf, labelThrough,
        rankingHorizonSessions, calibrationVersion, candidateLimits, batchCount,
        schemaValidBatchCount, calibrationPassedBatchCount,
        calibrationWarningBatchCount, calibrationWeakBatchCount, ollamaCallCount,
        databaseWritesPerformed, signalsCreated, ordersCreated, actionExecutionEnabled |
        Format-List

    Write-Host ''
    Write-Host 'Aggregate calibration failures / warnings'
    @($preview.aggregateFailures) | Format-Table -AutoSize

    Write-Host ''
    Write-Host 'Score calibration by candidate limit'
    $preview.batches |
        Select-Object candidateLimit, candidateCount, responseSchemaValid,
            rankingQualityStatus, scoreCalibrationStatus, minimumScore,
            maximumScore, scoreSpread, scoreRankCorrelation, topScoreSymbol,
            topScoreActualRank, bestActualSymbol, bestActualScore,
            highConfidenceMissCount, negativeReturnTopThreeCount |
        Format-Table -AutoSize

    if ($preview.databaseWritesPerformed -or
        $preview.ollamaCallCount -ne $preview.batchCount -or
        $preview.signalsCreated -ne 0 -or
        $preview.ordersCreated -ne 0 -or
        $preview.actionExecutionEnabled) {
        throw 'The Ollama score calibration preview violated a safety checkpoint.'
    }

    Write-Host ''
    Write-Host 'STEP 69 COMPLETE: Ollama score calibration review finished.'
    Write-Host 'If calibration is WEAK, treat it as prompt/rubric feedback, not as a trading signal.'
    Write-Host "Result: $resultPath"
    Write-Host "Log: $logPath"
}
finally {
    if ($transcriptStarted) {
        Stop-Transcript | Out-Null
    }
}
