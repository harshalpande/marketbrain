[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [datetime]$AsOf,

    [Parameter(Mandatory = $true)]
    [datetime]$LabelThrough,

    [Parameter()]
    [ValidateRange(0, 1000)]
    [int]$AssumedRoundTripCostBps = 50,

    [Parameter()]
    [string]$BaseUrl = 'http://127.0.0.1:8080',

    [Parameter()]
    [string]$OutputDirectory = 'C:\MarketBrainData\Review'
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$asOfText = $AsOf.ToString('yyyy-MM-dd')
$labelThroughText = $LabelThrough.ToString('yyyy-MM-dd')
New-Item -ItemType Directory -Path $OutputDirectory -Force | Out-Null
$stem = "swing-training-preview-$asOfText-through-$labelThroughText"
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

    Write-Host "Building the read-only swing-training cohort for $asOfText..."
    Write-Host "Future labels are bounded through $labelThroughText at 5, 20, and 60 market sessions."
    Write-Host 'Current constituent membership is exposed as survivor-biased; this preview cannot train a model.'
    $uri = "$BaseUrl/api/v1/training/swing-cohort-preview" +
        "?asOf=$asOfText" +
        "&labelThrough=$labelThroughText" +
        "&assumedRoundTripCostBps=$AssumedRoundTripCostBps"
    $preview = Invoke-RestMethod -Uri $uri -TimeoutSec 1800

    $preview | ConvertTo-Json -Depth 15 |
        Set-Content -LiteralPath $resultPath -Encoding utf8

    $preview | Select-Object status, datasetContractVersion, featureSetVersion,
        asOf, labelThrough, universeSnapshotId, universeObservedOn,
        inputFeatureManifestHash, instrumentCount, featureEligibleCount,
        fullyLabeledCount, rightCensoredCount, insufficientHistoryCount,
        staleCount, noEligibleDataCount, horizonsSessions,
        assumedRoundTripCostBps, benchmarkDefinition,
        historicalMembershipStatus, survivorshipBiasPresent, trainingEligible,
        pointInTimeSafe, futureLabelsSeparated, manifestHash,
        databaseWritesPerformed, ollamaCallCount, signalsCreated, ordersCreated |
        Format-List

    Write-Host ''
    Write-Host 'Outcome-date benchmark proxies'
    $preview.benchmarkOutcomes |
        Select-Object horizonSessions, outcomeDate, constituentLabelCount,
            equalWeightGrossReturnPercent |
        Format-Table -AutoSize

    Write-Host ''
    Write-Host 'Cohort classification'
    $preview.instruments |
        Group-Object status |
        Sort-Object Name |
        Select-Object Name, Count |
        Format-Table -AutoSize

    $notFullyLabeled = @(
        $preview.instruments | Where-Object { $_.status -ne 'LABELED' }
    )
    if ($notFullyLabeled.Count -gt 0) {
        Write-Host ''
        Write-Host 'Instruments not fully labeled'
        $notFullyLabeled |
            Select-Object symbol, status, missingHorizons,
                @{Name = 'FeatureStatus'; Expression = { $_.featureInput.status }}, detail |
            Format-Table -AutoSize
    }

    $classifiedFeatures = [int]$preview.featureEligibleCount +
        [int]$preview.insufficientHistoryCount +
        [int]$preview.staleCount +
        [int]$preview.noEligibleDataCount
    $classifiedEligible = [int]$preview.fullyLabeledCount +
        [int]$preview.rightCensoredCount
    $expectedHorizons = @($preview.horizonsSessions) -join ','
    $benchmarkFailures = @(
        $preview.benchmarkOutcomes | Where-Object {
            $_.horizonSessions -notin @(5, 20, 60) -or
            $null -eq $_.outcomeDate -or
            $_.constituentLabelCount -le 0 -or
            $null -eq $_.equalWeightGrossReturnPercent
        }
    )
    $itemFailures = @(
        $preview.instruments | Where-Object {
            $item = $_
            $labels = @($item.labels)
            $missingHorizons = @($item.missingHorizons)
            $classifiedForLabels = $item.status -in @('LABELED', 'RIGHT_CENSORED')
            $item.featureInput.requestedAsOf -ne $asOfText -or
            -not $item.featureInput.pointInTimeSafe -or
            $item.featureInput.databaseWritesPerformed -or
            ($classifiedForLabels -and $item.featureInput.status -ne 'ELIGIBLE') -or
            (-not $classifiedForLabels -and $labels.Count -ne 0) -or
            ($item.status -eq 'LABELED' -and
                (($labels.horizonSessions -join ',') -ne '5,20,60' -or
                    $missingHorizons.Count -ne 0)) -or
            ($item.status -eq 'RIGHT_CENSORED' -and
                ($missingHorizons.Count -eq 0 -or
                    $labels.Count + $missingHorizons.Count -ne 3)) -or
            @($labels | Where-Object {
                ([datetime]$_.outcomeDate).Date -le $AsOf.Date -or
                ([datetime]$_.outcomeDate).Date -gt $LabelThrough.Date -or
                $null -eq $_.benchmarkProxyReturnPercent -or
                $null -eq $_.benchmarkExcessReturnPercent
            }).Count -gt 0
        }
    )

    if ($preview.status -ne 'REVIEW_REQUIRED' -or
        $preview.datasetContractVersion -ne 'SWING_TRAINING_V1' -or
        $preview.featureSetVersion -ne 'TECHNICAL_V1' -or
        $preview.instrumentCount -ne 500 -or
        $preview.instruments.Count -ne 500 -or
        $classifiedFeatures -ne 500 -or
        $classifiedEligible -ne $preview.featureEligibleCount -or
        $preview.fullyLabeledCount -le 0 -or
        $expectedHorizons -ne '5,20,60' -or
        $preview.benchmarkDefinition -ne 'CURRENT_SNAPSHOT_EQUAL_WEIGHT_PROXY' -or
        $preview.benchmarkOutcomes.Count -ne 3 -or
        $benchmarkFailures.Count -ne 0 -or
        $itemFailures.Count -ne 0 -or
        $preview.historicalMembershipStatus -ne 'CURRENT_SNAPSHOT_ONLY' -or
        -not $preview.survivorshipBiasPresent -or
        $preview.trainingEligible -or
        -not $preview.pointInTimeSafe -or
        -not $preview.futureLabelsSeparated -or
        [string]$preview.manifestHash -notmatch '^[0-9a-f]{64}$' -or
        $preview.databaseWritesPerformed -or
        $preview.ollamaCallCount -ne 0 -or
        $preview.signalsCreated -ne 0 -or
        $preview.ordersCreated -ne 0) {
        throw 'The swing-training preview did not reach every reviewed Step 60 checkpoint.'
    }

    Write-Host ''
    Write-Host 'STEP 60 COMPLETE: the governed 5/20/60-session label contract is deterministic and reviewable.'
    Write-Host 'This current-constituent cohort remains blocked from training because historical membership is absent.'
    Write-Host 'No dataset, model, Ollama request, signal, order, candle, or other database row was written.'
    Write-Host 'Share this complete summary and JSON artifact before historical membership work is prepared.'
    Write-Host "Result: $resultPath"
    Write-Host "Log: $logPath"
}
finally {
    if ($transcriptStarted) {
        Stop-Transcript | Out-Null
    }
}
