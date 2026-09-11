[CmdletBinding()]
param(
    [Parameter()]
    [string]$DatasetRunId,

    [Parameter()]
    [string]$BaseUrl = 'http://127.0.0.1:8080',

    [Parameter()]
    [string]$OutputDirectory = 'C:\MarketBrainData\Review'
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

New-Item -ItemType Directory -Path $OutputDirectory -Force | Out-Null
$suffix = if ([string]::IsNullOrWhiteSpace($DatasetRunId)) { 'latest' } else { $DatasetRunId }
$stem = "prototype-swing-training-dataset-audit-$suffix"
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

    Write-Host 'Step 65: auditing the immutable prototype swing-training dataset...'
    Write-Host 'This is read-only: no Ollama request, signal, paper fill, order, or broker action will be created.'
    $uri = "$BaseUrl/api/v1/training/prototype-swing-dataset-audit"
    if (-not [string]::IsNullOrWhiteSpace($DatasetRunId)) {
        $uri = "${uri}?datasetRunId=$DatasetRunId"
    }
    $audit = Invoke-RestMethod -Uri $uri -TimeoutSec 300
    $audit | ConvertTo-Json -Depth 12 |
        Set-Content -LiteralPath $resultPath -Encoding utf8

    $audit | Select-Object status, datasetRunId, datasetContractVersion,
        sourceUniverseCode, asOf, labelThrough, datasetManifestHash,
        assumedRoundTripCostBps, instrumentCount, featureEligibleCount,
        fullyLabeledCount, rightCensoredCount, insufficientHistoryCount,
        staleCount, noEligibleDataCount, persistedItemCount,
        persistedLabelCount, survivorshipRiskPresent, prototypeTrainingEligible,
        benchmarkTrainingEligible, pointInTimeSafe, futureLabelsSeparated,
        auditReadyForOllamaRanking, databaseWritesPerformed, ollamaCallCount,
        signalsCreated, ordersCreated |
        Format-List

    Write-Host ''
    Write-Host 'Classification counts'
    $audit.classificationCounts |
        Sort-Object classification |
        Format-Table -AutoSize

    Write-Host ''
    Write-Host 'Horizon return audit'
    $audit.horizonAudits |
        Select-Object horizonSessions, labelCount, averageNetReturnPercent,
            medianNetReturnPercent, minimumNetReturnPercent, maximumNetReturnPercent,
            positiveNetReturnPercent, benchmarkOutperformPercent,
            averageMaximumDrawdownPercent |
        Format-Table -AutoSize

    Write-Host ''
    Write-Host 'Best net-return examples'
    $audit.bestOutcomes |
        Select-Object horizonSessions, symbol, netReturnPercent,
            benchmarkExcessReturnPercent, maximumDrawdownPercent |
        Format-Table -AutoSize

    Write-Host ''
    Write-Host 'Worst net-return examples'
    $audit.worstOutcomes |
        Select-Object horizonSessions, symbol, netReturnPercent,
            benchmarkExcessReturnPercent, maximumDrawdownPercent |
        Format-Table -AutoSize

    $failedCheckpoints = @($audit.failedCheckpoints)
    $horizons = @($audit.horizonAudits)
    $badHorizonCounts = @(
        $horizons | Where-Object {
            $_.horizonSessions -notin @(5, 20, 60) -or
            $_.labelCount -ne $audit.fullyLabeledCount
        }
    )

    if ($audit.status -ne 'REVIEW_REQUIRED' -or
        $audit.datasetContractVersion -ne 'PROTOTYPE_SWING_TRAINING_DATASET_V1' -or
        $audit.sourceUniverseCode -ne 'CURRENT_SNAPSHOT_PROTOTYPE' -or
        $audit.persistedItemCount -ne $audit.instrumentCount -or
        $audit.persistedLabelCount -ne ($audit.fullyLabeledCount * 3) -or
        $horizons.Count -ne 3 -or
        $badHorizonCounts.Count -ne 0 -or
        -not $audit.survivorshipRiskPresent -or
        -not $audit.prototypeTrainingEligible -or
        $audit.benchmarkTrainingEligible -or
        -not $audit.pointInTimeSafe -or
        -not $audit.futureLabelsSeparated -or
        -not $audit.auditReadyForOllamaRanking -or
        $audit.databaseWritesPerformed -or
        $audit.ollamaCallCount -ne 0 -or
        $audit.signalsCreated -ne 0 -or
        $audit.ordersCreated -ne 0 -or
        $failedCheckpoints.Count -ne 0) {
        throw 'The prototype swing-training dataset audit did not reach every reviewed checkpoint.'
    }

    Write-Host ''
    Write-Host 'STEP 65 COMPLETE: prototype swing-training dataset audit is ready for review.'
    Write-Host 'No database write, Ollama call, signal, paper fill, order, or broker action was created.'
    Write-Host "Result: $resultPath"
    Write-Host "Log: $logPath"
}
finally {
    if ($transcriptStarted) {
        Stop-Transcript | Out-Null
    }
}
