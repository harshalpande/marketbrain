[CmdletBinding()]
param(
    [Parameter()]
    [string]$DatasetRunId,

    [Parameter()]
    [string]$Model = 'qwen3:8b',

    [Parameter()]
    [ValidateRange(1, 25)]
    [int]$CandidateLimit = 5,

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

New-Item -ItemType Directory -Path $OutputDirectory -Force | Out-Null
$suffix = if ([string]::IsNullOrWhiteSpace($DatasetRunId)) { 'latest' } else { $DatasetRunId }
$safeModel = $Model -replace '[^A-Za-z0-9._-]', '_'
$stem = "prototype-swing-ollama-guided-ranking-evaluation-$suffix-$safeModel-h$RankingHorizonSessions"
$resultPath = Join-Path $OutputDirectory "$stem.json"
$guidedPath = Join-Path $OutputDirectory "$stem-guided-preview.json"
$responsePath = Join-Path $OutputDirectory "$stem-response.json"
$promptPath = Join-Path $OutputDirectory "$stem-prompt.txt"
$logPath = Join-Path $OutputDirectory "$stem.log"
$transcriptStarted = $false

try {
    Start-Transcript -Path $logPath -Force | Out-Null
    $transcriptStarted = $true

    $health = Invoke-RestMethod "$BaseUrl/actuator/health" -TimeoutSec 60
    if ($health.status -ne 'UP') {
        throw "MarketBrain health is $($health.status), not UP."
    }

    Write-Host 'Step 68: evaluating guided Ollama ranking against hidden prototype labels...'
    Write-Host 'This calls Ollama once, validates JSON/schema, compares rank quality, and remains review-only.'
    Write-Host 'No database write, signal, paper fill, order, broker action, or live trading action will be created.'

    $body = [ordered]@{
        model                  = $Model
        candidateLimit         = $CandidateLimit
        rankingHorizonSessions = $RankingHorizonSessions
    }
    if (-not [string]::IsNullOrWhiteSpace($DatasetRunId)) {
        $body['datasetRunId'] = $DatasetRunId
    }

    $preview = Invoke-RestMethod `
        -Method Post `
        -Uri "$BaseUrl/api/v1/training/prototype-swing-ollama-guided-ranking-evaluation-preview" `
        -ContentType 'application/json' `
        -Body ($body | ConvertTo-Json -Depth 8) `
        -TimeoutSec 900

    $preview | ConvertTo-Json -Depth 24 |
        Set-Content -LiteralPath $resultPath -Encoding utf8
    $preview.guidedPreview | ConvertTo-Json -Depth 20 |
        Set-Content -LiteralPath $guidedPath -Encoding utf8
    $preview.guidedPreview.prompt | Set-Content -LiteralPath $promptPath -Encoding utf8
    $preview.guidedPreview.ollamaResponse | Set-Content -LiteralPath $responsePath -Encoding utf8

    $preview | Select-Object status, datasetRunId, model, candidateCount,
        trainingExampleCount, rankingHorizonSessions, instructionPackVersion,
        responseSchemaVersion, rubricVersion, evaluationVersion, responseParseableJson,
        responseSchemaValid, rankingQualityStatus, topPickSymbol, topPickActualRank,
        topPickNetReturnPercent, bestActualSymbol, bestActualOllamaRank,
        bestActualNetReturnPercent, topThreeOverlapCount, rankCorrelationScore,
        highConfidenceMissCount, negativeReturnTopThreeCount, weakReasonCount,
        dailyFreshDataFeedbackLoopDesigned, dailyFreshDataUsedForTraining,
        databaseWritesPerformed, ollamaCallCount, signalsCreated,
        ordersCreated, actionExecutionEnabled |
        Format-List

    Write-Host ''
    Write-Host 'Response validation failures'
    @($preview.responseValidationFailures) | Format-Table -AutoSize

    Write-Host ''
    Write-Host 'Evaluation failures / warnings'
    @($preview.evaluationFailures) | Format-Table -AutoSize

    Write-Host ''
    Write-Host 'Ollama rank vs hidden future outcome'
    $preview.candidateEvaluations |
        Select-Object symbol, ollamaRank, actualRank, rankError, ollamaScore,
            ollamaConfidence, targetNetReturnPercent,
            targetBenchmarkExcessReturnPercent, targetMaximumDrawdownPercent,
            qualityBucket, highConfidenceMiss, topThreeNegativeReturn,
            reasonMentionsKnownFeature |
        Format-Table -AutoSize

    if ($preview.datasetContractVersion -ne 'PROTOTYPE_SWING_TRAINING_DATASET_V1' -or
        $preview.sourceUniverseCode -ne 'CURRENT_SNAPSHOT_PROTOTYPE' -or
        $preview.candidateCount -lt 1 -or
        $preview.candidateCount -gt $CandidateLimit -or
        $preview.trainingExampleCount -lt 6 -or
        $preview.rankingHorizonSessions -ne $RankingHorizonSessions -or
        -not $preview.responseParseableJson -or
        -not $preview.responseSchemaValid -or
        $preview.databaseWritesPerformed -or
        $preview.ollamaCallCount -ne 1 -or
        $preview.signalsCreated -ne 0 -or
        $preview.ordersCreated -ne 0 -or
        $preview.actionExecutionEnabled -or
        -not $preview.dailyFreshDataFeedbackLoopDesigned -or
        $preview.dailyFreshDataUsedForTraining) {
        throw 'The guided Ollama ranking evaluation violated a safety checkpoint.'
    }

    Write-Host ''
    Write-Host 'STEP 68 COMPLETE: guided Ollama ranking was evaluated against hidden prototype labels.'
    Write-Host "Ranking quality status: $($preview.rankingQualityStatus)"
    Write-Host 'This is not a trading signal and did not create any order or paper fill.'
    Write-Host "Result: $resultPath"
    Write-Host "Guided preview: $guidedPath"
    Write-Host "Prompt: $promptPath"
    Write-Host "Response: $responsePath"
    Write-Host "Log: $logPath"
}
finally {
    if ($transcriptStarted) {
        Stop-Transcript | Out-Null
    }
}
