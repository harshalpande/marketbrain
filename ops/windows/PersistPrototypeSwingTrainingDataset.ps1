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
    [string]$ReviewedBy = 'Harshal Pande',

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
$stem = "prototype-swing-training-dataset-$asOfText-through-$labelThroughText"
$previewPath = Join-Path $OutputDirectory "$stem-preview.json"
$resultPath = Join-Path $OutputDirectory "$stem-result.json"
$logPath = Join-Path $OutputDirectory "$stem.log"
$transcriptStarted = $false

try {
    Start-Transcript -Path $logPath -Force | Out-Null
    $transcriptStarted = $true

    $health = Invoke-RestMethod "$BaseUrl/actuator/health" -TimeoutSec 60
    if ($health.status -ne 'UP') {
        throw "MarketBrain health is $($health.status), not UP."
    }

    Write-Host "Step 64: previewing prototype swing-training dataset for $asOfText through $labelThroughText..."
    Write-Host 'This current-snapshot dataset is useful for prototype learning, not official historical NIFTY 500 benchmarking.'
    $previewUri = "$BaseUrl/api/v1/training/swing-cohort-preview" +
        "?asOf=$asOfText" +
        "&labelThrough=$labelThroughText" +
        "&assumedRoundTripCostBps=$AssumedRoundTripCostBps"
    $preview = Invoke-RestMethod -Uri $previewUri -TimeoutSec 1800
    $preview | ConvertTo-Json -Depth 15 |
        Set-Content -LiteralPath $previewPath -Encoding utf8

    $preview | Select-Object status, datasetContractVersion, featureSetVersion,
        asOf, labelThrough, instrumentCount, featureEligibleCount,
        fullyLabeledCount, rightCensoredCount, insufficientHistoryCount,
        staleCount, noEligibleDataCount, historicalMembershipStatus,
        survivorshipBiasPresent, trainingEligible, pointInTimeSafe,
        futureLabelsSeparated, manifestHash, databaseWritesPerformed,
        ollamaCallCount, signalsCreated, ordersCreated |
        Format-List

    if ($preview.status -ne 'REVIEW_REQUIRED' -or
        $preview.datasetContractVersion -ne 'SWING_TRAINING_V1' -or
        $preview.featureSetVersion -ne 'TECHNICAL_V1' -or
        $preview.fullyLabeledCount -le 0 -or
        -not $preview.survivorshipBiasPresent -or
        $preview.trainingEligible -or
        -not $preview.pointInTimeSafe -or
        -not $preview.futureLabelsSeparated -or
        [string]$preview.manifestHash -notmatch '^[0-9a-f]{64}$' -or
        $preview.databaseWritesPerformed -or
        $preview.ollamaCallCount -ne 0 -or
        $preview.signalsCreated -ne 0 -or
        $preview.ordersCreated -ne 0) {
        throw 'The prototype swing-training preflight preview is not safe to persist.'
    }

    Write-Host ''
    Write-Host 'Persisting the exact manifest-bound prototype dataset...'
    $persistUri = "$BaseUrl/api/v1/training/prototype-swing-dataset" +
        "?asOf=$asOfText" +
        "&labelThrough=$labelThroughText" +
        "&assumedRoundTripCostBps=$AssumedRoundTripCostBps" +
        "&expectedManifestHash=$($preview.manifestHash)" +
        "&reviewedBy=$([uri]::EscapeDataString($ReviewedBy))"
    $result = Invoke-RestMethod -Method Post -Uri $persistUri -TimeoutSec 1800
    $result | ConvertTo-Json -Depth 10 |
        Set-Content -LiteralPath $resultPath -Encoding utf8

    $result | Select-Object status, persistenceAction, datasetRunId,
        datasetContractVersion, sourceUniverseCode, asOf, labelThrough,
        universeSnapshotId, featureSetVersion, inputFeatureManifestHash,
        datasetManifestHash, assumedRoundTripCostBps, benchmarkDefinition,
        historicalMembershipStatus, reviewedBy, instrumentCount,
        featureEligibleCount, fullyLabeledCount, rightCensoredCount,
        insufficientHistoryCount, staleCount, noEligibleDataCount,
        persistedItemCount, persistedLabelCount, survivorshipRiskPresent,
        prototypeTrainingEligible, benchmarkTrainingEligible, pointInTimeSafe,
        futureLabelsSeparated, databaseWritesPerformed, ollamaCallCount,
        signalsCreated, ordersCreated |
        Format-List

    if ($result.status -ne 'COMPLETED' -or
        $result.persistenceAction -notin @('CREATED', 'ALREADY_PERSISTED') -or
        $result.datasetContractVersion -ne 'PROTOTYPE_SWING_TRAINING_DATASET_V1' -or
        $result.sourceUniverseCode -ne 'CURRENT_SNAPSHOT_PROTOTYPE' -or
        $result.datasetManifestHash -ne $preview.manifestHash -or
        $result.persistedItemCount -ne $result.instrumentCount -or
        $result.persistedLabelCount -le 0 -or
        -not $result.survivorshipRiskPresent -or
        -not $result.prototypeTrainingEligible -or
        $result.benchmarkTrainingEligible -or
        -not $result.pointInTimeSafe -or
        -not $result.futureLabelsSeparated -or
        $result.ollamaCallCount -ne 0 -or
        $result.signalsCreated -ne 0 -or
        $result.ordersCreated -ne 0) {
        throw 'The prototype swing-training persistence result did not reach every reviewed checkpoint.'
    }

    Write-Host ''
    Write-Host 'STEP 64 COMPLETE: prototype swing-training dataset persisted or safely reused.'
    Write-Host 'This creates an immutable training artifact for prototype learning only.'
    Write-Host 'It does not train Ollama, create signals, create paper fills, or place broker orders.'
    Write-Host "Preview: $previewPath"
    Write-Host "Result: $resultPath"
    Write-Host "Log: $logPath"
}
finally {
    if ($transcriptStarted) {
        Stop-Transcript | Out-Null
    }
}
