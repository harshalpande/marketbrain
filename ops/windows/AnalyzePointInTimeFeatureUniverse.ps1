[CmdletBinding()]
param(
    [Parameter()]
    [datetime]$AsOf,

    [Parameter()]
    [string]$BaseUrl = 'http://127.0.0.1:8080',

    [Parameter()]
    [string]$OutputDirectory = 'C:\MarketBrainData\Review'
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

if (-not $PSBoundParameters.ContainsKey('AsOf')) {
    $indiaNow = [TimeZoneInfo]::ConvertTimeBySystemTimeZoneId(
        [DateTimeOffset]::UtcNow,
        'India Standard Time'
    )
    $AsOf = $indiaNow.Date
}

$asOfText = $AsOf.ToString('yyyy-MM-dd')
New-Item -ItemType Directory -Path $OutputDirectory -Force | Out-Null
$resultPath = Join-Path $OutputDirectory "feature-universe-preview-$asOfText.json"
$logPath = Join-Path $OutputDirectory "feature-universe-preview-$asOfText.log"
$transcriptStarted = $false

try {
    Start-Transcript -Path $logPath -Force | Out-Null
    $transcriptStarted = $true

    $health = Invoke-RestMethod "$BaseUrl/actuator/health" -TimeoutSec 60
    if ($health.status -ne 'UP') {
        throw "MarketBrain health is $($health.status), not UP."
    }

    Write-Host "Analyzing point-in-time TECHNICAL_V1 features for all 500 NIFTY instruments through $asOfText..."
    Write-Host 'This is database-only and can take several minutes; it does not fetch provider data or write features.'
    $analysis = Invoke-RestMethod `
        "$BaseUrl/api/v1/features/universe-preview?asOf=$asOfText" `
        -TimeoutSec 1800

    $analysis | ConvertTo-Json -Depth 12 |
        Set-Content -LiteralPath $resultPath -Encoding utf8

    $analysis | Select-Object status, featureSetVersion, requestedAsOf,
        universeSnapshotId, universeObservedOn, instrumentCount, eligibleCount,
        staleCount, insufficientHistoryCount, noEligibleDataCount, featureVectorCount,
        canonicalObservationCount, eligibleObservationCount, excludedObservationCount,
        manifestHash, pointInTimeSafe, databaseWritesPerformed | Format-List

    Write-Host ''
    Write-Host 'Universe classification'
    $analysis.instruments |
        Group-Object status |
        Sort-Object Name |
        Select-Object Name, Count |
        Format-Table -AutoSize

    $requiresReview = @(
        $analysis.instruments | Where-Object { $_.status -ne 'ELIGIBLE' }
    )
    if ($requiresReview.Count -gt 0) {
        Write-Host ''
        Write-Host 'Instruments not current-date eligible'
        $requiresReview |
            Select-Object symbol, status, effectiveAsOf, eligibleObservationCount,
                excludedObservationCount, detail |
            Format-Table -AutoSize
    }

    $classifiedCount = [int]$analysis.eligibleCount +
        [int]$analysis.staleCount +
        [int]$analysis.insufficientHistoryCount +
        [int]$analysis.noEligibleDataCount
    $manifestValid = [string]$analysis.manifestHash -match '^[0-9a-f]{64}$'
    $itemsWithVectors = @(
        $analysis.instruments | Where-Object { $null -ne $_.features }
    ).Count
    $itemCheckpointFailures = @(
        $analysis.instruments | Where-Object {
            $_.featureSetVersion -ne 'TECHNICAL_V1' -or
            ([datetime]$_.requestedAsOf).Date -ne $AsOf.Date -or
            -not $_.pointInTimeSafe -or
            $_.databaseWritesPerformed -or
            ($null -ne $_.effectiveAsOf -and
                ([datetime]$_.effectiveAsOf).Date -gt $AsOf.Date) -or
            ($_.status -eq 'ELIGIBLE' -and
                ([datetime]$_.effectiveAsOf).Date -ne $AsOf.Date) -or
            ($_.status -eq 'STALE' -and
                ([datetime]$_.effectiveAsOf).Date -ge $AsOf.Date) -or
            (($_.status -eq 'ELIGIBLE' -or $_.status -eq 'STALE') -and
                $null -eq $_.features) -or
            (($_.status -eq 'INSUFFICIENT_HISTORY' -or
                $_.status -eq 'NO_ELIGIBLE_DATA') -and $null -ne $_.features)
        }
    )

    if ($analysis.status -ne 'REVIEW_REQUIRED' -or
        $analysis.featureSetVersion -ne 'TECHNICAL_V1' -or
        $analysis.instrumentCount -ne 500 -or
        $analysis.instruments.Count -ne 500 -or
        $classifiedCount -ne 500 -or
        $itemsWithVectors -ne $analysis.featureVectorCount -or
        $itemCheckpointFailures.Count -ne 0 -or
        -not $manifestValid -or
        -not $analysis.pointInTimeSafe -or
        $analysis.databaseWritesPerformed) {
        throw 'The all-500 point-in-time analysis did not reach every expected checkpoint.'
    }

    Write-Host ''
    Write-Host 'STEP 55 COMPLETE: all 500 instruments were classified under one immutable TECHNICAL_V1 manifest.'
    Write-Host 'No feature, signal, order, finding, resolution, candle, or other database row was written.'
    Write-Host 'Share this summary and the JSON artifact before any feature persistence is prepared.'
    Write-Host "Result: $resultPath"
    Write-Host "Log: $logPath"
}
finally {
    if ($transcriptStarted) {
        Stop-Transcript | Out-Null
    }
}
