[CmdletBinding()]
param(
    [Parameter()]
    [string]$DatasetRunId,

    [Parameter()]
    [string]$Model = 'gemma3:4b',

    [Parameter()]
    [ValidateRange(1, 100)]
    [int]$TotalCandidateLimit = 12,

    [Parameter()]
    [ValidateRange(1, 5)]
    [int]$ChunkSize = 4,

    [Parameter()]
    [ValidateRange(1, 5)]
    [int]$FinalistsPerChunk = 2,

    [Parameter()]
    [ValidateRange(0, 3)]
    [int]$MaxRetriesPerChunk = 1,

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

if ($FinalistsPerChunk -gt $ChunkSize) {
    throw 'FinalistsPerChunk cannot be greater than ChunkSize.'
}

New-Item -ItemType Directory -Path $OutputDirectory -Force | Out-Null
$suffix = if ([string]::IsNullOrWhiteSpace($DatasetRunId)) { 'latest' } else { $DatasetRunId }
$safeModel = $Model -replace '[^A-Za-z0-9._-]', '_'
$stem = "prototype-swing-ollama-chunked-ranking-$suffix-$safeModel-h$RankingHorizonSessions-total$TotalCandidateLimit-chunk$ChunkSize"
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

    Write-Host 'Step 70: running chunked calibrated Ollama ranking...'
    Write-Host "Chunk size: $ChunkSize; total candidate limit: $TotalCandidateLimit; max retries per chunk: $MaxRetriesPerChunk"
    Write-Host 'Each chunk is guarded, evaluated, optionally retried, and summarized.'
    Write-Host 'No database write, signal, paper fill, order, broker action, or live trading action will be created.'

    $body = [ordered]@{
        model                  = $Model
        totalCandidateLimit    = $TotalCandidateLimit
        chunkSize              = $ChunkSize
        finalistsPerChunk      = $FinalistsPerChunk
        maxRetriesPerChunk     = $MaxRetriesPerChunk
        rankingHorizonSessions = $RankingHorizonSessions
    }
    if (-not [string]::IsNullOrWhiteSpace($DatasetRunId)) {
        $body['datasetRunId'] = $DatasetRunId
    }

    $preview = Invoke-RestMethod `
        -Method Post `
        -Uri "$BaseUrl/api/v1/training/prototype-swing-ollama-chunked-ranking-preview" `
        -ContentType 'application/json' `
        -Body ($body | ConvertTo-Json -Depth 8) `
        -TimeoutSec 3600

    $preview | ConvertTo-Json -Depth 36 |
        Set-Content -LiteralPath $resultPath -Encoding utf8

    $preview | Select-Object status, datasetRunId, model, asOf, labelThrough,
        totalCandidateLimit, chunkSize, finalistsPerChunk, maxRetriesPerChunk,
        rankingHorizonSessions, chunkedRankingVersion, chunkCount,
        passedChunkCount, warningChunkCount, failedChunkCount,
        processedCandidateCount, finalistCount, ollamaCallCount,
        databaseWritesPerformed, signalsCreated, ordersCreated, actionExecutionEnabled |
        Format-List

    Write-Host ''
    Write-Host 'Chunk loop results'
    foreach ($chunk in $preview.chunks) {
        Write-Host ("Chunk {0}: {1}; offset={2}; candidates={3}; attempts={4}; acceptedAttempt={5}" -f `
            $chunk.chunkNumber, $chunk.chunkStatus, $chunk.offset, `
            ($chunk.candidateSymbols -join ','), $chunk.attemptCount, $chunk.acceptedAttemptNumber)
        foreach ($attempt in $chunk.attempts) {
            Write-Host ("  Attempt {0}: schemaValid={1}; ranking={2}; calibration={3}; accepted={4}" -f `
                $attempt.attemptNumber, $attempt.responseSchemaValid, `
                $attempt.rankingQualityStatus, $attempt.scoreCalibrationStatus, `
                $attempt.acceptedForChunkSummary)
            if (@($attempt.responseValidationFailures).Count -gt 0) {
                Write-Host ("    Response failures: {0}" -f (@($attempt.responseValidationFailures) -join ', '))
            }
            if (@($attempt.calibrationFailures).Count -gt 0) {
                Write-Host ("    Calibration failures: {0}" -f (@($attempt.calibrationFailures) -join ', '))
            }
        }
    }

    Write-Host ''
    Write-Host 'Merged finalists summary'
    $preview.mergedFinalists |
        Select-Object chunkNumber, symbol, chunkOllamaRank, chunkActualRank,
            ollamaScore, ollamaConfidence, targetNetReturnPercent,
            targetBenchmarkExcessReturnPercent, targetMaximumDrawdownPercent,
            qualityBucket |
        Format-Table -AutoSize

    Write-Host ''
    Write-Host 'Aggregate failures / warnings'
    @($preview.aggregateFailures) | Format-Table -AutoSize

    if ($preview.databaseWritesPerformed -or
        $preview.signalsCreated -ne 0 -or
        $preview.ordersCreated -ne 0 -or
        $preview.actionExecutionEnabled) {
        throw 'The chunked Ollama ranking preview violated a safety checkpoint.'
    }

    Write-Host ''
    Write-Host 'STEP 70 COMPLETE: chunked calibrated Ollama ranking review finished.'
    Write-Host 'This is a model-quality review only. It is not a trading signal.'
    Write-Host "Result: $resultPath"
    Write-Host "Log: $logPath"
}
finally {
    if ($transcriptStarted) {
        Stop-Transcript | Out-Null
    }
}
