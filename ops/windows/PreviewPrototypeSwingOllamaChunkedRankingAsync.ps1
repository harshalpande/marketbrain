[CmdletBinding()]
param(
    [Parameter()]
    [string]$DatasetRunId,

    [Parameter()]
    [string]$Model = 'ibm/granite4.1:8b',

    [Parameter()]
    [ValidateRange(1, 100)]
    [int]$TotalCandidateLimit = 24,

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
    [ValidateRange(2, 30)]
    [int]$PollSeconds = 5,

    [Parameter()]
    [ValidateRange(60, 14400)]
    [int]$TimeoutSeconds = 7200,

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
$stem = "prototype-swing-ollama-chunked-ranking-async-$suffix-$safeModel-h$RankingHorizonSessions-total$TotalCandidateLimit-chunk$ChunkSize"
$resultPath = Join-Path $OutputDirectory "$stem.json"
$rootCausePath = Join-Path $OutputDirectory "$stem-root-causes.json"
$logPath = Join-Path $OutputDirectory "$stem.log"
$transcriptStarted = $false

try {
    Start-Transcript -Path $logPath -Force | Out-Null
    $transcriptStarted = $true

    $health = Invoke-RestMethod "$BaseUrl/actuator/health" -TimeoutSec 60
    if ($health.status -ne 'UP') {
        throw "MarketBrain health is $($health.status), not UP."
    }

    Write-Host 'Step 70 async: starting Java-owned chunked calibrated Ollama ranking job...'
    Write-Host 'Java runs the job in the background; local Ollama model concurrency remains fixed at 1.'
    Write-Host "Chunk size: $ChunkSize; total candidate limit: $TotalCandidateLimit; max retries per chunk: $MaxRetriesPerChunk"
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

    $job = Invoke-RestMethod `
        -Method Post `
        -Uri "$BaseUrl/api/v1/training/prototype-swing-ollama-chunked-ranking-jobs" `
        -ContentType 'application/json' `
        -Body ($body | ConvertTo-Json -Depth 8) `
        -TimeoutSec 60

    $jobId = [string]$job.jobId
    if ([string]::IsNullOrWhiteSpace($jobId)) {
        throw 'The backend did not return a jobId.'
    }
    Write-Host "Started Ollama ranking job: $jobId"

    $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
    $lastPrinted = ''
    do {
        Start-Sleep -Seconds $PollSeconds
        $status = Invoke-RestMethod `
            -Uri "$BaseUrl/api/v1/training/prototype-swing-ollama-chunked-ranking-jobs/$jobId" `
            -TimeoutSec 60

        $progress = [int]$status.progressPercent
        $statusLine = "[{0}%] status={1}; completed={2}/{3}; activeChunk={4}; passed={5}; failed={6}; detail={7}" -f `
            $progress, $status.status, $status.completedChunkCount, $status.targetChunkCount, `
            $status.activeChunkNumber, $status.passedChunkCount, $status.failedChunkCount, $status.detail

        Write-Progress `
            -Activity 'Step 70 async Ollama ranking job' `
            -Status $statusLine `
            -PercentComplete ([Math]::Min(100, [Math]::Max(0, $progress)))

        if ($statusLine -ne $lastPrinted) {
            Write-Host $statusLine
            $lastPrinted = $statusLine
        }

        if ($status.status -in @('COMPLETED', 'FAILED')) {
            break
        }
        if ((Get-Date) -ge $deadline) {
            throw "Timed out waiting for Ollama ranking job $jobId after $TimeoutSeconds seconds."
        }
    } while ($true)

    Write-Progress -Activity 'Step 70 async Ollama ranking job' -Completed

    $status | ConvertTo-Json -Depth 80 | Set-Content -LiteralPath $resultPath -Encoding utf8

    $rootCauseRecords = New-Object System.Collections.Generic.List[object]
    $attemptTelemetryRecords = New-Object System.Collections.Generic.List[object]
    if ($null -ne $status.result) {
        foreach ($chunk in @($status.result.chunks)) {
            foreach ($attempt in @($chunk.attempts)) {
                $promptPath = Join-Path $OutputDirectory ("$stem-chunk{0}-attempt{1}-prompt.txt" -f $chunk.chunkNumber, $attempt.attemptNumber)
                $responsePath = Join-Path $OutputDirectory ("$stem-chunk{0}-attempt{1}-ollama-response.json" -f $chunk.chunkNumber, $attempt.attemptNumber)
                if (-not [string]::IsNullOrWhiteSpace([string]$attempt.prompt)) {
                    [string]$attempt.prompt |
                        Set-Content -LiteralPath $promptPath -Encoding utf8
                }
                if (-not [string]::IsNullOrWhiteSpace([string]$attempt.ollamaResponse)) {
                    [string]$attempt.ollamaResponse |
                        Set-Content -LiteralPath $responsePath -Encoding utf8
                }
                $attemptTelemetryRecords.Add([pscustomobject][ordered]@{
                    kind                       = 'CHUNK_ATTEMPT_TELEMETRY'
                    jobId                      = $jobId
                    chunkNumber                = $chunk.chunkNumber
                    chunkStatus                = $chunk.chunkStatus
                    attemptNumber              = $attempt.attemptNumber
                    acceptedForChunkSummary    = $attempt.acceptedForChunkSummary
                    expectedCandidateIds       = @($attempt.expectedCandidateIds)
                    candidateSymbols           = @($attempt.candidateSymbols)
                    promptPath                 = $promptPath
                    promptHash                 = $attempt.promptHash
                    promptCharacterCount       = $attempt.promptCharacterCount
                    responsePath               = $responsePath
                    responseHash               = $attempt.responseHash
                    responseCharacterCount     = $attempt.responseCharacterCount
                    ollamaElapsedMillis        = $attempt.ollamaElapsedMillis
                    ollamaTotalDurationNanos   = $attempt.ollamaTotalDurationNanos
                    ollamaPromptEvalCount      = $attempt.ollamaPromptEvalCount
                    ollamaEvalCount            = $attempt.ollamaEvalCount
                    responseParseableJson      = $attempt.responseParseableJson
                    responseSchemaValid        = $attempt.responseSchemaValid
                    rankingQualityStatus       = $attempt.rankingQualityStatus
                    scoreCalibrationStatus     = $attempt.scoreCalibrationStatus
                    responseValidationFailures = @($attempt.responseValidationFailures)
                    evaluationFailures         = @($attempt.evaluationFailures)
                    calibrationFailures        = @($attempt.calibrationFailures)
                })
                if (@($attempt.responseValidationFailures).Count -gt 0 -or
                    @($attempt.evaluationFailures).Count -gt 0 -or
                    @($attempt.calibrationFailures).Count -gt 0) {
                    $rootCauseRecords.Add([pscustomobject][ordered]@{
                        kind                       = 'CHUNK_ATTEMPT_GUARDRAIL'
                        jobId                      = $jobId
                        chunkNumber                = $chunk.chunkNumber
                        attemptNumber              = $attempt.attemptNumber
                        repairInstruction          = $attempt.repairInstruction
                        expectedCandidateIds       = @($attempt.expectedCandidateIds)
                        candidateSymbols           = @($attempt.candidateSymbols)
                        promptPath                 = $promptPath
                        promptHash                 = $attempt.promptHash
                        promptCharacterCount       = $attempt.promptCharacterCount
                        responsePath               = $responsePath
                        responseHash               = $attempt.responseHash
                        responseCharacterCount     = $attempt.responseCharacterCount
                        ollamaElapsedMillis        = $attempt.ollamaElapsedMillis
                        ollamaTotalDurationNanos   = $attempt.ollamaTotalDurationNanos
                        ollamaPromptEvalCount      = $attempt.ollamaPromptEvalCount
                        ollamaEvalCount            = $attempt.ollamaEvalCount
                        responseParseableJson      = $attempt.responseParseableJson
                        responseSchemaValid        = $attempt.responseSchemaValid
                        rankingQualityStatus       = $attempt.rankingQualityStatus
                        scoreCalibrationStatus     = $attempt.scoreCalibrationStatus
                        responseValidationFailures = @($attempt.responseValidationFailures)
                        evaluationFailures         = @($attempt.evaluationFailures)
                        calibrationFailures        = @($attempt.calibrationFailures)
                        acceptedForChunkSummary    = $attempt.acceptedForChunkSummary
                    })
                }
            }
        }
    }
    $attemptTelemetryPath = Join-Path $OutputDirectory "$stem-attempt-telemetry.json"
    $attemptTelemetryRecords | ConvertTo-Json -Depth 80 | Set-Content -LiteralPath $attemptTelemetryPath -Encoding utf8
    $rootCauseRecords | ConvertTo-Json -Depth 80 | Set-Content -LiteralPath $rootCausePath -Encoding utf8

    if ($status.status -eq 'FAILED') {
        throw "Ollama ranking job failed safely: $($status.errorMessage)"
    }

    $status.result |
        Select-Object status, model, chunkCount, passedChunkCount, warningChunkCount,
            failedChunkCount, processedCandidateCount, finalistCount, ollamaCallCount,
            databaseWritesPerformed, signalsCreated, ordersCreated, actionExecutionEnabled |
        Format-List

    Write-Host ''
    Write-Host 'Chunk summary'
    $status.result.chunks |
        Select-Object chunkNumber, chunkStatus, candidateCount, attemptCount, acceptedAttemptNumber |
        Format-Table -AutoSize

    Write-Host ''
    Write-Host 'Merged finalists summary'
    $status.result.mergedFinalists |
        Select-Object chunkNumber, symbol, chunkOllamaRank, chunkActualRank, ollamaScore,
            ollamaConfidence, targetNetReturnPercent, targetBenchmarkExcessReturnPercent,
            targetMaximumDrawdownPercent, qualityBucket |
        Format-Table -AutoSize

    Write-Host ''
    Write-Host 'STEP 70 ASYNC COMPLETE: Java-owned chunked Ollama ranking job finished.'
    Write-Host 'This is a model-quality review only. It is not a trading signal.'
    Write-Host "Result: $resultPath"
    Write-Host "Attempt telemetry: $attemptTelemetryPath"
    Write-Host "Root causes: $rootCausePath"
    Write-Host "Log: $logPath"
}
finally {
    Write-Progress -Activity 'Step 70 async Ollama ranking job' -Completed
    if ($transcriptStarted) {
        Stop-Transcript | Out-Null
    }
}
