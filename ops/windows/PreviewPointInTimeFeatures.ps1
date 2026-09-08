[CmdletBinding()]
param(
    [Parameter()]
    [ValidatePattern('^[A-Za-z0-9&-]{1,64}$')]
    [string]$Symbol = 'RELIANCE',

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

$normalizedSymbol = $Symbol.Trim().ToUpperInvariant()
$asOfText = $AsOf.ToString('yyyy-MM-dd')
New-Item -ItemType Directory -Path $OutputDirectory -Force | Out-Null
$resultPath = Join-Path $OutputDirectory "feature-preview-$normalizedSymbol-$asOfText.json"
$logPath = Join-Path $OutputDirectory "feature-preview-$normalizedSymbol-$asOfText.log"
$transcriptStarted = $false

try {
    Start-Transcript -Path $logPath -Force | Out-Null
    $transcriptStarted = $true

    $health = Invoke-RestMethod "$BaseUrl/actuator/health" -TimeoutSec 60
    if ($health.status -ne 'UP') {
        throw "MarketBrain health is $($health.status), not UP."
    }

    Write-Host "Computing a governed point-in-time feature preview for $normalizedSymbol through $asOfText..."
    $encodedSymbol = [uri]::EscapeDataString($normalizedSymbol)
    $preview = Invoke-RestMethod `
        "$BaseUrl/api/v1/features/preview?symbol=$encodedSymbol&asOf=$asOfText" `
        -TimeoutSec 180

    $preview | ConvertTo-Json -Depth 10 |
        Set-Content -LiteralPath $resultPath -Encoding utf8

    $preview | Select-Object status, symbol, featureSetVersion, requestedAsOf, effectiveAsOf,
        canonicalObservationCount, eligibleObservationCount, excludedObservationCount,
        pointInTimeSafe, databaseWritesPerformed | Format-List
    $preview.latestCandle | Format-List
    $preview.features | Format-List

    if ($preview.status -ne 'ELIGIBLE' -or
        $preview.symbol -ne $normalizedSymbol -or
        $preview.featureSetVersion -ne 'TECHNICAL_V1' -or
        -not $preview.pointInTimeSafe -or
        $preview.databaseWritesPerformed -or
        $null -eq $preview.features -or
        ([datetime]$preview.effectiveAsOf).Date -gt $AsOf.Date) {
        throw 'The point-in-time feature preview did not reach every expected checkpoint.'
    }

    Write-Host ''
    Write-Host 'FEATURE PREVIEW COMPLETE: the full deterministic indicator vector passed without a database write.'
    Write-Host "Result: $resultPath"
    Write-Host "Log: $logPath"
}
finally {
    if ($transcriptStarted) {
        Stop-Transcript | Out-Null
    }
}
