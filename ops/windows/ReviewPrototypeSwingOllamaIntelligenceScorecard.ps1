param(
    [Parameter(Mandatory = $true)]
    [string]$ResultPath,

    [string]$BaseUrl = 'http://127.0.0.1:8080',

    [string]$OutputDirectory = 'C:\MarketBrainData\Review',

    [int]$TimeoutSeconds = 300
)

$ErrorActionPreference = 'Stop'

function Write-StepProgress {
    param(
        [int]$Percent,
        [string]$Message
    )
    Write-Progress -Activity 'Step 86 Granite intelligence scorecard' -Status $Message -PercentComplete $Percent
    Write-Host ("[{0}%] {1}" -f $Percent, $Message)
}

if (-not (Test-Path -LiteralPath $ResultPath)) {
    throw "ResultPath does not exist: $ResultPath"
}

New-Item -ItemType Directory -Path $OutputDirectory -Force | Out-Null

$inputItem = Get-Item -LiteralPath $ResultPath
$stem = [System.IO.Path]::GetFileNameWithoutExtension($inputItem.Name)
$timestamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$scorecardPath = Join-Path $OutputDirectory "$stem-intelligence-scorecard-$timestamp.json"
$logPath = Join-Path $OutputDirectory "$stem-intelligence-scorecard-$timestamp.log"

Start-Transcript -Path $logPath -Force | Out-Null

try {
    Write-StepProgress 0 'Validating service health...'
    $health = Invoke-RestMethod "$BaseUrl/actuator/health" -TimeoutSec 30
    if ($health.status -ne 'UP') {
        throw "Service health is not UP. Current status: $($health.status)"
    }

    Write-StepProgress 20 'Reading completed chunked ranking JSON...'
    $body = Get-Content -LiteralPath $ResultPath -Raw
    if ([string]::IsNullOrWhiteSpace($body)) {
        throw "Result JSON is empty: $ResultPath"
    }

    Write-StepProgress 45 'Requesting Java-owned intelligence scorecard...'
    $scorecard = Invoke-RestMethod `
        -Method Post `
        -Uri "$BaseUrl/api/v1/training/prototype-swing-ollama-intelligence-scorecard" `
        -ContentType 'application/json' `
        -Body $body `
        -TimeoutSec $TimeoutSeconds

    Write-StepProgress 75 'Persisting scorecard JSON...'
    $scorecard |
        ConvertTo-Json -Depth 80 |
        Set-Content -LiteralPath $scorecardPath -Encoding UTF8

    Write-StepProgress 90 'Printing scorecard summary...'
    $scorecard |
        Select-Object `
            status,
            model,
            overallIntelligenceScorePercent,
            pendingImprovementPercent,
            maturityBand,
            pipelineReliabilityPercent,
            cleanPassPercent,
            schemaDisciplinePercent,
            scoreCalibrationPercent,
            rankingQualityPercent,
            finalistQualityPercent,
            failedChunkCount,
            warningChunkCount,
            passedChunkCount,
            finalistCount,
            ollamaCallCount,
            databaseWritesPerformed,
            signalsCreated,
            ordersCreated,
            actionExecutionEnabled |
        Format-List

    Write-Host ''
    Write-Host 'Dimension scorecard'
    $scorecard.dimensions |
        Select-Object name, scorePercent, status, @{Name='evidence'; Expression={ ($_.evidence -join '; ') }} |
        Format-Table -AutoSize

    Write-Host ''
    Write-Host 'Chunk intelligence scorecard'
    $scorecard.chunks |
        Select-Object `
            chunkNumber,
            chunkStatus,
            acceptedRankingQualityStatus,
            acceptedScoreCalibrationStatus,
            intelligenceScorePercent,
            topFinalistSymbol,
            topFinalistActualRank,
            finalistCount,
            @{Name='warningCount'; Expression={ @($_.warnings).Count }} |
        Format-Table -AutoSize

    Write-Host ''
    Write-Host 'Top improvement actions'
    foreach ($action in $scorecard.topImprovementActions) {
        Write-Host "- $action"
    }

    Write-StepProgress 100 'Scorecard complete.'
    Write-Host ''
    Write-Host 'STEP 86 COMPLETE: Granite intelligence scorecard generated.'
    Write-Host "Scorecard: $scorecardPath"
    Write-Host "Log: $logPath"
}
finally {
    Stop-Transcript | Out-Null
}
