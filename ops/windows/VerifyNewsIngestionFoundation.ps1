[CmdletBinding()]
param(
    [Parameter()]
    [string]$BaseUrl = 'http://127.0.0.1:8080',

    [Parameter()]
    [string]$OutputDirectory = 'C:\MarketBrainData\Review'
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$timestamp = Get-Date -Format 'yyyy-MM-dd-HHmmss'
$stem = "news-ingestion-foundation-$timestamp"
New-Item -ItemType Directory -Path $OutputDirectory -Force | Out-Null
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

    Write-Host 'Verifying the governed news-ingestion foundation...'
    Write-Host 'This check must not call providers, store articles, call Ollama, create signals, or create orders.'

    $status = Invoke-RestMethod "$BaseUrl/api/v1/news/ingestion/status" -TimeoutSec 120

    $run = Invoke-RestMethod `
        -Method Post `
        -Uri "$BaseUrl/api/v1/news/ingestion/run-once" `
        -TimeoutSec 120

    [ordered]@{
        status = $status
        runOnce = $run
    } | ConvertTo-Json -Depth 10 |
        Set-Content -LiteralPath $resultPath -Encoding utf8

    $status | Select-Object status, newsModuleEnabled, liveFetchEnabled, maximumArticlesPerDay,
        sourceCount, implementedConnectorCount, persistedSourceCount, enabledSourceCount,
        liveFetchEligibleCount, providerRequestCount, articlesStored, ollamaCallCount,
        newsFeaturesCreated, signalsCreated, ordersCreated |
        Format-List

    Write-Host ''
    Write-Host 'News source gates'
    $status.sources |
        Select-Object sourceKey, sourceType, integrationType, permissionStatus,
            connectorImplemented, integrationEnabled, liveFetchEligible, blockedReason |
        Format-Table -AutoSize

    Write-Host ''
    Write-Host 'Manual run-once result'
    $run | Select-Object status, runId, sourceCount, attemptedSourceCount,
        providerRequestCount, candidateArticleCount, storedArticleCount,
        ollamaCallCount, newsFeaturesCreated, signalsCreated, ordersCreated |
        Format-List

    $unexpectedFetch = @($status.sources | Where-Object { $_.liveFetchEligible })
    if ($status.status -ne 'BLOCKED_BY_GOVERNANCE' -or
        $status.sourceCount -ne 8 -or
        $status.implementedConnectorCount -ne 8 -or
        $status.persistedSourceCount -ne 8 -or
        $status.enabledSourceCount -ne 0 -or
        $status.liveFetchEligibleCount -ne 0 -or
        $status.providerRequestCount -ne 0 -or
        $status.articlesStored -ne 0 -or
        $status.ollamaCallCount -ne 0 -or
        $status.newsFeaturesCreated -ne 0 -or
        $status.signalsCreated -ne 0 -or
        $status.ordersCreated -ne 0 -or
        $run.status -ne 'BLOCKED_BY_GOVERNANCE' -or
        $run.attemptedSourceCount -ne 0 -or
        $run.providerRequestCount -ne 0 -or
        $run.candidateArticleCount -ne 0 -or
        $run.storedArticleCount -ne 0 -or
        $run.ollamaCallCount -ne 0 -or
        $run.newsFeaturesCreated -ne 0 -or
        $run.signalsCreated -ne 0 -or
        $run.ordersCreated -ne 0 -or
        $unexpectedFetch.Count -ne 0) {
        throw 'The news-ingestion foundation did not remain fully disabled and side-effect free.'
    }

    Write-Host ''
    Write-Host 'NEWS INGESTION FOUNDATION COMPLETE: all eight sources are implemented and permission-gated.'
    Write-Host 'No provider request, article, Ollama call, feature, signal, order, broker action, or live trading action was created.'
    Write-Host "Result: $resultPath"
    Write-Host "Log: $logPath"
}
finally {
    if ($transcriptStarted) {
        Stop-Transcript | Out-Null
    }
}
