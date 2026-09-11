[CmdletBinding()]
param(
    [Parameter()]
    [string]$DatasetRunId,

    [Parameter()]
    [string]$Model = 'llama3.1:8b',

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
$stem = "prototype-swing-ollama-ranking-$suffix-$safeModel-h$RankingHorizonSessions"
$resultPath = Join-Path $OutputDirectory "$stem.json"
$responsePath = Join-Path $OutputDirectory "$stem-response.md"
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

    Write-Host 'Step 66: running governed Ollama prototype swing-ranking preview...'
    Write-Host 'This calls Ollama once for research review only.'
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
        -Uri "$BaseUrl/api/v1/training/prototype-swing-ollama-ranking-preview" `
        -ContentType 'application/json' `
        -Body ($body | ConvertTo-Json -Depth 8) `
        -TimeoutSec 600

    $preview | ConvertTo-Json -Depth 12 |
        Set-Content -LiteralPath $resultPath -Encoding utf8
    $preview.prompt | Set-Content -LiteralPath $promptPath -Encoding utf8
    $preview.ollamaResponse | Set-Content -LiteralPath $responsePath -Encoding utf8

    $preview | Select-Object status, datasetRunId, datasetContractVersion,
        sourceUniverseCode, asOf, labelThrough, datasetManifestHash, model,
        candidateLimit, candidateCount, rankingHorizonSessions, promptHash,
        responseHash, survivorshipRiskPresent, prototypeTrainingEligible,
        benchmarkTrainingEligible, pointInTimeSafe, futureLabelsSeparated,
        databaseWritesPerformed, ollamaCallCount, signalsCreated,
        ordersCreated, actionExecutionEnabled |
        Format-List

    Write-Host ''
    Write-Host 'Candidate outcome comparison retained for review'
    $preview.candidates |
        Select-Object symbol, netReturn5Sessions, netReturn20Sessions,
            netReturn60Sessions, benchmarkExcess20Sessions,
            maximumDrawdown20Sessions |
        Format-Table -AutoSize

    Write-Host ''
    Write-Host 'Ollama response'
    Write-Host $preview.ollamaResponse

    if ($preview.status -ne 'REVIEW_REQUIRED' -or
        $preview.datasetContractVersion -ne 'PROTOTYPE_SWING_TRAINING_DATASET_V1' -or
        $preview.sourceUniverseCode -ne 'CURRENT_SNAPSHOT_PROTOTYPE' -or
        $preview.candidateCount -lt 1 -or
        $preview.candidateCount -gt $CandidateLimit -or
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
        $preview.actionExecutionEnabled) {
        throw 'The governed Ollama ranking preview did not satisfy every safety checkpoint.'
    }

    Write-Host ''
    Write-Host 'STEP 66 COMPLETE: governed Ollama ranking preview is ready for human review.'
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
