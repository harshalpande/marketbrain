[CmdletBinding()]
param(
    [Parameter()]
    [string]$DatasetRunId,

    [Parameter()]
    [string]$Model = 'qwen3:8b',

    [Parameter()]
    [ValidateRange(1, 25)]
    [int]$CandidateLimit = 12,

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
$stem = "prototype-swing-ollama-guided-ranking-$suffix-$safeModel-h$RankingHorizonSessions"
$resultPath = Join-Path $OutputDirectory "$stem.json"
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

    Write-Host 'Step 67: running guided Ollama training/playbook ranking preview...'
    Write-Host 'This uses a MarketBrain playbook, positive/negative labelled examples, JSON response schema, and guardrail validation.'
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
        -Uri "$BaseUrl/api/v1/training/prototype-swing-ollama-guided-ranking-preview" `
        -ContentType 'application/json' `
        -Body ($body | ConvertTo-Json -Depth 8) `
        -TimeoutSec 900

    $preview | ConvertTo-Json -Depth 16 |
        Set-Content -LiteralPath $resultPath -Encoding utf8
    $preview.prompt | Set-Content -LiteralPath $promptPath -Encoding utf8
    $preview.ollamaResponse | Set-Content -LiteralPath $responsePath -Encoding utf8

    $preview | Select-Object status, datasetRunId, model, candidateCount,
        trainingExampleCount, rankingHorizonSessions, instructionPackVersion,
        responseSchemaVersion, rubricVersion, playbookHash, promptHash,
        responseHash, responseParseableJson, responseSchemaValid,
        dailyFreshDataFeedbackLoopDesigned, dailyFreshDataUsedForTraining,
        databaseWritesPerformed, ollamaCallCount, signalsCreated,
        ordersCreated, actionExecutionEnabled |
        Format-List

    Write-Host ''
    Write-Host 'Response validation failures'
    @($preview.responseValidationFailures) | Format-Table -AutoSize

    Write-Host ''
    Write-Host 'Labelled training examples supplied to Ollama'
    $preview.trainingExamples |
        Select-Object scenarioType, symbol, targetNetReturnPercent,
            targetBenchmarkExcessReturnPercent, targetMaximumDrawdownPercent |
        Format-Table -AutoSize

    Write-Host ''
    Write-Host 'Candidate outcome comparison retained for human review'
    $preview.candidates |
        Select-Object symbol, netReturn5Sessions, netReturn20Sessions,
            netReturn60Sessions, benchmarkExcess20Sessions,
            maximumDrawdown20Sessions |
        Format-Table -AutoSize

    if ($preview.datasetContractVersion -ne 'PROTOTYPE_SWING_TRAINING_DATASET_V1' -or
        $preview.sourceUniverseCode -ne 'CURRENT_SNAPSHOT_PROTOTYPE' -or
        $preview.candidateCount -lt 1 -or
        $preview.candidateCount -gt $CandidateLimit -or
        $preview.trainingExampleCount -lt 6 -or
        $preview.rankingHorizonSessions -ne $RankingHorizonSessions -or
        $preview.promptHash -notmatch '^[0-9a-f]{64}$' -or
        $preview.responseHash -notmatch '^[0-9a-f]{64}$' -or
        [string]::IsNullOrWhiteSpace($preview.ollamaResponse) -or
        -not $preview.survivorshipRiskPresent -or
        -not $preview.prototypeTrainingEligible -or
        $preview.benchmarkTrainingEligible -or
        -not $preview.pointInTimeSafe -or
        -not $preview.futureLabelsSeparated -or
        $preview.databaseWritesPerformed -or
        $preview.ollamaCallCount -ne 1 -or
        $preview.signalsCreated -ne 0 -or
        $preview.ordersCreated -ne 0 -or
        $preview.actionExecutionEnabled -or
        -not $preview.dailyFreshDataFeedbackLoopDesigned -or
        $preview.dailyFreshDataUsedForTraining) {
        throw 'The guided Ollama ranking preview violated a safety checkpoint.'
    }

    Write-Host ''
    if ($preview.responseSchemaValid) {
        Write-Host 'STEP 67 COMPLETE: guided Ollama response passed schema guardrails and is ready for review.'
    }
    else {
        Write-Host 'STEP 67 GUARDED REVIEW: Ollama response was captured, but schema guardrails blocked acceptance.'
    }
    Write-Host 'No database write, signal, paper fill, order, broker action, or live trading action was created.'
    Write-Host "Result: $resultPath"
    Write-Host "Prompt: $promptPath"
    Write-Host "Response: $responsePath"
    Write-Host "Log: $logPath"
}
finally {
    if ($transcriptStarted) {
        Stop-Transcript | Out-Null
    }
}
