[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [datetime]$AsOf,

    [Parameter(Mandatory = $true)]
    [ValidatePattern('^[0-9a-f]{64}$')]
    [string]$ExpectedManifestHash,

    [Parameter(Mandatory = $true)]
    [ValidateLength(1, 120)]
    [string]$ReviewedBy,

    [Parameter()]
    [string]$BaseUrl = 'http://127.0.0.1:8080',

    [Parameter()]
    [string]$OutputDirectory = 'C:\MarketBrainData\Review'
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$approvedAsOf = '2026-09-08'
$approvedManifestHash = '6ad27dded487d8991672438044c4f5c610fabc03cf04bab81ff3fdee95ae47ba'
$asOfText = $AsOf.ToString('yyyy-MM-dd')
if ($asOfText -ne $approvedAsOf -or $ExpectedManifestHash -ne $approvedManifestHash) {
    throw 'The requested date or manifest does not match the explicitly reviewed Step 55 result.'
}
if ([string]::IsNullOrWhiteSpace($ReviewedBy)) {
    throw 'ReviewedBy cannot be blank.'
}

New-Item -ItemType Directory -Path $OutputDirectory -Force | Out-Null
$logPath = Join-Path $OutputDirectory "feature-snapshot-step56-$asOfText.log"
$transcriptStarted = $false

try {
    Start-Transcript -Path $logPath -Force | Out-Null
    $transcriptStarted = $true

    $health = Invoke-RestMethod "$BaseUrl/actuator/health" -TimeoutSec 60
    if ($health.status -ne 'UP') {
        throw "MarketBrain health is $($health.status), not UP."
    }

    $reviewer = [uri]::EscapeDataString($ReviewedBy.Trim())
    $uri = "$BaseUrl/api/v1/features/snapshots?asOf=$asOfText" +
        "&expectedManifestHash=$ExpectedManifestHash&reviewedBy=$reviewer"
    Write-Host 'Recomputing and atomically persisting the explicitly reviewed TECHNICAL_V1 snapshot...'
    Write-Host 'This database-only operation creates no signal, order, or broker action.'
    $result = Invoke-RestMethod -Method Post -Uri $uri -TimeoutSec 1800

    $resultPath = Join-Path $OutputDirectory "feature-snapshot-step56-$($result.runId).json"
    $result | ConvertTo-Json -Depth 8 |
        Set-Content -LiteralPath $resultPath -Encoding utf8

    $result | Select-Object status, runId, universeSnapshotId, requestedAsOf,
        featureSetVersion, sourceManifestHash, reviewedBy, instrumentCount,
        persistedFeatureCount, withheldCount, insufficientHistoryCount, staleCount,
        noEligibleDataCount, persistedItemCount, signalsCreated, ordersCreated,
        databaseWritesPerformed | Format-List

    if ($result.status -ne 'COMPLETED' -or
        ([datetime]$result.requestedAsOf).ToString('yyyy-MM-dd') -ne $approvedAsOf -or
        $result.featureSetVersion -ne 'TECHNICAL_V1' -or
        $result.sourceManifestHash -ne $approvedManifestHash -or
        $result.instrumentCount -ne 500 -or
        $result.persistedFeatureCount -ne 485 -or
        $result.withheldCount -ne 15 -or
        $result.insufficientHistoryCount -ne 15 -or
        $result.staleCount -ne 0 -or
        $result.noEligibleDataCount -ne 0 -or
        $result.persistedItemCount -ne 500 -or
        $result.signalsCreated -ne 0 -or
        $result.ordersCreated -ne 0) {
        throw 'The persisted snapshot did not reach every approved Step 56 checkpoint.'
    }

    Write-Host ''
    Write-Host 'STEP 56 COMPLETE: the reviewed snapshot contains 485 complete vectors and 15 explicit withheld classifications.'
    if (-not $result.databaseWritesPerformed) {
        Write-Host 'This was a safe idempotent replay; the exact completed snapshot already existed.'
    }
    Write-Host 'No signal or order was created. Keep model training and signal generation disabled.'
    Write-Host "Result: $resultPath"
    Write-Host "Log: $logPath"
}
finally {
    if ($transcriptStarted) {
        Stop-Transcript | Out-Null
    }
}
