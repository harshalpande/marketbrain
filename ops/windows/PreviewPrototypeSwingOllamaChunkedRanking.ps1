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

    Write-Host 'Step 70: running chunked calibrated Ollama ranking with visible progress...'
    Write-Host "Chunk size: $ChunkSize; total candidate limit: $TotalCandidateLimit; max retries per chunk: $MaxRetriesPerChunk"
    Write-Host 'Each chunk is called separately, guarded, evaluated, optionally retried, and summarized.'
    Write-Host 'No database write, signal, paper fill, order, broker action, or live trading action will be created.'

    $chunkCountTarget = [int][Math]::Ceiling($TotalCandidateLimit / [double]$ChunkSize)
    $chunkPreviews = New-Object System.Collections.Generic.List[object]
    $rootCauseRecords = New-Object System.Collections.Generic.List[object]

    for ($chunkIndex = 0; $chunkIndex -lt $chunkCountTarget; $chunkIndex++) {
        $offset = $chunkIndex * $ChunkSize
        $currentLimit = [Math]::Min($ChunkSize, $TotalCandidateLimit - $offset)
        $percentBefore = [int][Math]::Floor(($chunkIndex / [double]$chunkCountTarget) * 100)
        $percentAfter = [int][Math]::Floor((($chunkIndex + 1) / [double]$chunkCountTarget) * 100)
        $chunkNumber = $chunkIndex + 1

        Write-Progress `
            -Activity 'Step 70 chunked Ollama ranking' `
            -Status "Starting chunk $chunkNumber of $chunkCountTarget ($percentBefore% complete)" `
            -PercentComplete $percentBefore
        Write-Host ''
        Write-Host ("[{0}%] Starting chunk {1}/{2}; offset={3}; limit={4}" -f `
            $percentBefore, $chunkNumber, $chunkCountTarget, $offset, $currentLimit)

        $body = [ordered]@{
            model                  = $Model
            startOffset            = $offset
            totalCandidateLimit    = $currentLimit
            chunkSize              = $ChunkSize
            finalistsPerChunk      = $FinalistsPerChunk
            maxRetriesPerChunk     = $MaxRetriesPerChunk
            rankingHorizonSessions = $RankingHorizonSessions
        }
        if (-not [string]::IsNullOrWhiteSpace($DatasetRunId)) {
            $body['datasetRunId'] = $DatasetRunId
        }

        try {
            $chunkPreview = Invoke-RestMethod `
                -Method Post `
                -Uri "$BaseUrl/api/v1/training/prototype-swing-ollama-chunked-ranking-preview" `
                -ContentType 'application/json' `
                -Body ($body | ConvertTo-Json -Depth 8) `
                -TimeoutSec 1800

            $chunkPreviews.Add($chunkPreview)
            foreach ($chunk in $chunkPreview.chunks) {
                Write-Host ("[{0}%] Chunk {1}/{2} returned {3}; candidates={4}; attempts={5}; acceptedAttempt={6}" -f `
                    $percentAfter, $chunkNumber, $chunkCountTarget, $chunk.chunkStatus, `
                    ($chunk.candidateSymbols -join ','), $chunk.attemptCount, $chunk.acceptedAttemptNumber)
                foreach ($attempt in $chunk.attempts) {
                    Write-Host ("       Attempt {0}: schemaValid={1}; ranking={2}; calibration={3}; accepted={4}" -f `
                        $attempt.attemptNumber, $attempt.responseSchemaValid, `
                        $attempt.rankingQualityStatus, $attempt.scoreCalibrationStatus, `
                        $attempt.acceptedForChunkSummary)
                    if (@($attempt.responseValidationFailures).Count -gt 0 -or
                        @($attempt.evaluationFailures).Count -gt 0 -or
                        @($attempt.calibrationFailures).Count -gt 0) {
                        $rootCauseRecords.Add([pscustomobject][ordered]@{
                            kind                       = 'CHUNK_ATTEMPT_GUARDRAIL'
                            chunkNumber                = $chunk.chunkNumber
                            attemptNumber              = $attempt.attemptNumber
                            candidateSymbols           = @($attempt.candidateSymbols)
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
        catch {
            $statusCode = $null
            $responseBody = $null
            if ($_.Exception.Response -and $_.Exception.Response.StatusCode) {
                $statusCode = [int]$_.Exception.Response.StatusCode
            }
            if ($_.ErrorDetails -and $_.ErrorDetails.Message) {
                $responseBody = $_.ErrorDetails.Message
            }
            $record = [pscustomobject][ordered]@{
                kind             = 'CHUNK_EXCEPTION'
                chunkNumber      = $chunkNumber
                offset           = $offset
                requestedLimit   = $currentLimit
                exceptionType    = $_.Exception.GetType().FullName
                message          = $_.Exception.Message
                httpStatusCode   = $statusCode
                responseBody     = $responseBody
                scriptStackTrace = $_.ScriptStackTrace
            }
            $rootCauseRecords.Add($record)
            Write-Host ("[{0}%] Chunk {1}/{2} failed with exception: {3}" -f `
                $percentAfter, $chunkNumber, $chunkCountTarget, $_.Exception.Message)
        }

        Write-Progress `
            -Activity 'Step 70 chunked Ollama ranking' `
            -Status "Completed chunk $chunkNumber of $chunkCountTarget ($percentAfter% complete)" `
            -PercentComplete $percentAfter
    }

    Write-Progress -Activity 'Step 70 chunked Ollama ranking' -Completed

    $allChunkList = New-Object System.Collections.Generic.List[object]
    $mergedFinalistList = New-Object System.Collections.Generic.List[object]
    $aggregateFailureList = New-Object System.Collections.Generic.List[string]
    foreach ($chunkPreview in $chunkPreviews) {
        foreach ($chunk in @($chunkPreview.chunks)) {
            if ($null -ne $chunk) {
                $allChunkList.Add($chunk)
            }
        }
        foreach ($finalist in @($chunkPreview.mergedFinalists)) {
            if ($null -ne $finalist) {
                $mergedFinalistList.Add($finalist)
            }
        }
        foreach ($failure in @($chunkPreview.aggregateFailures)) {
            if (-not [string]::IsNullOrWhiteSpace([string]$failure)) {
                $aggregateFailureList.Add([string]$failure)
            }
        }
    }
    foreach ($record in $rootCauseRecords) {
        if ($record.kind -eq 'CHUNK_EXCEPTION') {
            $aggregateFailureList.Add("CHUNK_$($record.chunkNumber)_EXCEPTION")
        }
    }

    $allChunks = $allChunkList.ToArray()
    $mergedFinalists = $mergedFinalistList.ToArray() |
        Sort-Object -Property `
            @{ Expression = { if ($null -eq $_.ollamaScore) { [int]::MinValue } else { [int]$_.ollamaScore } }; Descending = $true },
            @{ Expression = { [string]$_.symbol }; Descending = $false }
    $aggregateFailures = @($aggregateFailureList.ToArray() |
        Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) } |
        Select-Object -Unique)

    $passedChunkCount = @($allChunks | Where-Object { $_.chunkStatus -eq 'CHUNK_PASSED' }).Count
    $warningChunkCount = @($allChunks | Where-Object { $_.chunkStatus -eq 'CHUNK_ACCEPTED_WITH_WARNINGS' }).Count
    $failedChunkCount = @($allChunks | Where-Object { $_.chunkStatus -eq 'CHUNK_FAILED' }).Count +
        @($rootCauseRecords | Where-Object { $_.kind -eq 'CHUNK_EXCEPTION' }).Count
    $ollamaCallCount = 0
    foreach ($chunk in $allChunks) {
        $ollamaCallCount += [int]$chunk.attemptCount
    }

    $firstPreview = @($chunkPreviews | Select-Object -First 1)
    $processedCandidateCount = 0
    foreach ($chunk in $allChunks) {
        $processedCandidateCount += [int]$chunk.candidateCount
    }

    $preview = [pscustomobject][ordered]@{
        status                   = if ($failedChunkCount -eq 0 -and @($aggregateFailures).Count -eq 0) { 'REVIEW_REQUIRED' } else { 'REVIEW_WITH_WARNINGS' }
        datasetRunId             = if ($firstPreview.Count -gt 0) { $firstPreview[0].datasetRunId } else { $DatasetRunId }
        model                    = $Model
        asOf                     = if ($firstPreview.Count -gt 0) { $firstPreview[0].asOf } else { $null }
        labelThrough             = if ($firstPreview.Count -gt 0) { $firstPreview[0].labelThrough } else { $null }
        totalCandidateLimit      = $TotalCandidateLimit
        chunkSize                = $ChunkSize
        finalistsPerChunk        = $FinalistsPerChunk
        maxRetriesPerChunk       = $MaxRetriesPerChunk
        rankingHorizonSessions   = $RankingHorizonSessions
        chunkedRankingVersion    = if ($firstPreview.Count -gt 0) { $firstPreview[0].chunkedRankingVersion } else { 'MARKETBRAIN_OLLAMA_CHUNKED_RANKING_V1' }
        chunkCount               = @($allChunks).Count
        passedChunkCount         = $passedChunkCount
        warningChunkCount        = $warningChunkCount
        failedChunkCount         = $failedChunkCount
        processedCandidateCount  = $processedCandidateCount
        finalistCount            = @($mergedFinalists).Count
        ollamaCallCount          = $ollamaCallCount
        chunks                   = @($allChunks)
        mergedFinalists          = @($mergedFinalists)
        aggregateFailures        = @($aggregateFailures)
        rootCauseRecords         = @($rootCauseRecords.ToArray())
        databaseWritesPerformed  = $false
        signalsCreated           = 0
        ordersCreated            = 0
        actionExecutionEnabled   = $false
        detail                   = 'Step 70 processed chunks one-by-one from PowerShell with percentage progress and root-cause logging.'
    }

    $preview | ConvertTo-Json -Depth 40 |
        Set-Content -LiteralPath $resultPath -Encoding utf8
    @($rootCauseRecords.ToArray()) | ConvertTo-Json -Depth 20 |
        Set-Content -LiteralPath $rootCausePath -Encoding utf8

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

    Write-Host ''
    Write-Host 'Root cause / exception records'
    @($preview.rootCauseRecords) |
        Select-Object kind, chunkNumber, attemptNumber, exceptionType,
            message, responseValidationFailures, evaluationFailures,
            calibrationFailures |
        Format-Table -AutoSize

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
    Write-Host "Root causes: $rootCausePath"
    Write-Host "Log: $logPath"
}
finally {
    if ($transcriptStarted) {
        Stop-Transcript | Out-Null
    }
}
