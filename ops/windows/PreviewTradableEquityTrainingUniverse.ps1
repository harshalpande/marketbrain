[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [datetime]$AsOf,

    [Parameter()]
    [ValidateRange(1, 5000)]
    [int]$MinimumEligibleObservations = 252,

    [Parameter()]
    [string]$BaseUrl = 'http://127.0.0.1:8080',

    [Parameter()]
    [string]$OutputDirectory = 'C:\MarketBrainData\Review'
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$asOfText = $AsOf.ToString('yyyy-MM-dd')
New-Item -ItemType Directory -Path $OutputDirectory -Force | Out-Null
$stem = "tradable-equity-training-universe-preview-$asOfText"
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

    Write-Host "Previewing the governed fallback NSE tradable-equity training universe for $asOfText..."
    Write-Host 'This is not historical NIFTY 500 membership and it does not train Ollama or create signals.'
    $uri = "$BaseUrl/api/v1/training/tradable-equity-universe-preview" +
        "?asOf=$asOfText" +
        "&minimumEligibleObservations=$MinimumEligibleObservations"
    $preview = Invoke-RestMethod -Uri $uri -TimeoutSec 1800

    $preview | ConvertTo-Json -Depth 10 |
        Set-Content -LiteralPath $resultPath -Encoding utf8

    $preview | Select-Object status, universeContractVersion, universeCode,
        asOf, minimumEligibleObservations, totalInstrumentCount,
        activeNseInstrumentCount, eligibleInstrumentCount,
        insufficientHistoryCount, staleCount, noEligibleDataCount,
        canonicalObservationCount, eligibleObservationCount,
        excludedObservationCount, earliestObservationDate, latestObservationDate,
        currentTradableUniverse, nifty500HistoricalMembershipRequired,
        survivorshipRiskPresent, prototypeTrainingUniverseReady,
        benchmarkTrainingEligible, pointInTimeSafe, databaseWritesPerformed,
        ollamaCallCount, signalsCreated, ordersCreated, manifestHash |
        Format-List

    Write-Host ''
    Write-Host 'Candidate universe classification'
    $preview.instruments |
        Group-Object status |
        Sort-Object Name |
        Select-Object Name, Count |
        Format-Table -AutoSize

    $notEligible = @(
        $preview.instruments | Where-Object { $_.status -ne 'ELIGIBLE' }
    )
    if ($notEligible.Count -gt 0) {
        Write-Host ''
        Write-Host 'Sample instruments not eligible'
        $notEligible |
            Select-Object -First 25 symbol, status, latestCandleDate,
                eligibleObservationCount, excludedObservationCount, latestSource, detail |
            Format-Table -AutoSize
    }

    $classifiedCount = [int]$preview.eligibleInstrumentCount +
        [int]$preview.insufficientHistoryCount +
        [int]$preview.staleCount +
        [int]$preview.noEligibleDataCount
    $failedCheckpoints = @($preview.failedCheckpoints)

    if ($preview.status -notin @('REVIEW_REQUIRED', 'SOURCE_REVIEW_REQUIRED') -or
        $preview.universeContractVersion -ne 'TRADEABLE_EQUITY_TRAINING_UNIVERSE_V1' -or
        $preview.universeCode -ne 'AVAILABLE_NSE_EQUITY_DATA' -or
        $preview.activeNseInstrumentCount -le 0 -or
        $preview.instruments.Count -ne $preview.activeNseInstrumentCount -or
        $classifiedCount -ne $preview.activeNseInstrumentCount -or
        -not $preview.currentTradableUniverse -or
        $preview.nifty500HistoricalMembershipRequired -or
        -not $preview.survivorshipRiskPresent -or
        $preview.benchmarkTrainingEligible -or
        -not $preview.pointInTimeSafe -or
        $preview.databaseWritesPerformed -or
        $preview.ollamaCallCount -ne 0 -or
        $preview.signalsCreated -ne 0 -or
        $preview.ordersCreated -ne 0 -or
        [string]$preview.manifestHash -notmatch '^[0-9a-f]{64}$' -or
        ($preview.prototypeTrainingUniverseReady -and $preview.eligibleInstrumentCount -le 0) -or
        (-not $preview.prototypeTrainingUniverseReady -and $failedCheckpoints.Count -eq 0)) {
        throw 'The tradable-equity training universe preview did not reach every reviewed checkpoint.'
    }

    Write-Host ''
    Write-Host 'TRADEABLE EQUITY TRAINING UNIVERSE PREVIEW COMPLETE.'
    Write-Host 'The result is read-only and can guide the next prototype training-dataset step.'
    Write-Host 'It remains explicitly separate from licensed historical NIFTY 500 benchmark training.'
    Write-Host 'No database row, Ollama request, signal, order, or broker action was created.'
    Write-Host "Result: $resultPath"
    Write-Host "Log: $logPath"
}
finally {
    if ($transcriptStarted) {
        Stop-Transcript | Out-Null
    }
}
