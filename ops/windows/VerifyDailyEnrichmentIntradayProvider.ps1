[CmdletBinding()]
param(
    [Parameter()]
    [datetime]$TargetDate,

    [Parameter()]
    [string]$BaseUrl = 'http://127.0.0.1:8080',

    [Parameter()]
    [string]$OutputDirectory = 'C:\MarketBrainData\Review'
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$indiaNow = [TimeZoneInfo]::ConvertTimeBySystemTimeZoneId(
    [DateTimeOffset]::UtcNow,
    'India Standard Time'
)
if (-not $PSBoundParameters.ContainsKey('TargetDate')) {
    $TargetDate = $indiaNow.Date
}
if ($TargetDate.Date -ne $indiaNow.Date) {
    throw "The intraday provider check must target today's India date, $($indiaNow.ToString('yyyy-MM-dd'))."
}

$dateText = $TargetDate.ToString('yyyy-MM-dd')
New-Item -ItemType Directory -Path $OutputDirectory -Force | Out-Null
$resultPath = Join-Path $OutputDirectory "daily-enrichment-intraday-provider-$dateText.json"
$logPath = Join-Path $OutputDirectory "daily-enrichment-intraday-provider-$dateText.log"
$transcriptStarted = $false

try {
    Start-Transcript -Path $logPath -Force | Out-Null
    $transcriptStarted = $true

    $health = Invoke-RestMethod "$BaseUrl/actuator/health" -TimeoutSec 60
    if ($health.status -ne 'UP') {
        throw "MarketBrain health is $($health.status), not UP."
    }

    Write-Host "Checking five Upstox current-day intraday daily candles without writing data..."
    $readiness = Invoke-RestMethod `
        "$BaseUrl/api/v1/market-data/daily-enrichment/provider-readiness?targetDate=$dateText" `
        -TimeoutSec 180
    $readiness | ConvertTo-Json -Depth 8 |
        Set-Content -LiteralPath $resultPath -Encoding utf8
    $readiness | Select-Object targetDate, status, requestedChecks, availableChecks,
        missingChecks, failedChecks, databaseWritesPerformed | Format-List
    $readiness.checks | Format-Table symbol, status -AutoSize

    if ($readiness.status -ne 'READY' -or
        $readiness.requestedChecks -ne 5 -or
        $readiness.availableChecks -ne 5 -or
        $readiness.missingChecks -ne 0 -or
        $readiness.failedChecks -ne 0 -or
        $readiness.databaseWritesPerformed) {
        throw 'The current-day intraday provider verification did not reach every expected checkpoint.'
    }

    Write-Host ''
    Write-Host 'INTRADAY PROVIDER VERIFIED: all five target-date probes are ready and no database row was written.'
    Write-Host "Result: $resultPath"
    Write-Host "Log: $logPath"
}
finally {
    if ($transcriptStarted) {
        Stop-Transcript | Out-Null
    }
}
