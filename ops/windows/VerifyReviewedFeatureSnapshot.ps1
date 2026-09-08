[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [guid]$RunId,

    [Parameter(Mandatory = $true)]
    [ValidatePattern('^[0-9a-f]{64}$')]
    [string]$ExpectedManifestHash,

    [Parameter()]
    [string]$BaseUrl = 'http://127.0.0.1:8080',

    [Parameter()]
    [string]$OutputDirectory = 'C:\MarketBrainData\Review'
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$approvedManifestHash = '6ad27dded487d8991672438044c4f5c610fabc03cf04bab81ff3fdee95ae47ba'
if ($ExpectedManifestHash -ne $approvedManifestHash) {
    throw 'The expected manifest does not match the explicitly reviewed Step 55 result.'
}

New-Item -ItemType Directory -Path $OutputDirectory -Force | Out-Null
$resultPath = Join-Path $OutputDirectory "feature-snapshot-quality-$RunId.json"
$logPath = Join-Path $OutputDirectory "feature-snapshot-quality-$RunId.log"
$transcriptStarted = $false

try {
    Start-Transcript -Path $logPath -Force | Out-Null
    $transcriptStarted = $true

    $health = Invoke-RestMethod "$BaseUrl/actuator/health" -TimeoutSec 60
    if ($health.status -ne 'UP') {
        throw "MarketBrain health is $($health.status), not UP."
    }

    Write-Host 'Auditing the immutable feature snapshot and independently rebuilding its source manifest...'
    $quality = Invoke-RestMethod `
        "$BaseUrl/api/v1/features/snapshots/quality?runId=$RunId&expectedManifestHash=$ExpectedManifestHash" `
        -TimeoutSec 300
    $quality | ConvertTo-Json -Depth 8 |
        Set-Content -LiteralPath $resultPath -Encoding utf8

    $quality | Format-List

    if ($quality.status -ne 'ELIGIBLE' -or
        ([datetime]$quality.requestedAsOf).ToString('yyyy-MM-dd') -ne '2026-09-08' -or
        $quality.featureSetVersion -ne 'TECHNICAL_V1' -or
        $quality.sourceManifestHash -ne $approvedManifestHash -or
        $quality.recomputedManifestHash -ne $approvedManifestHash -or
        $quality.instrumentCount -ne 500 -or
        $quality.persistedFeatureCount -ne 485 -or
        $quality.withheldCount -ne 15 -or
        $quality.persistedItemCount -ne 500 -or
        $quality.completeVectorCount -ne 485 -or
        $quality.insufficientHistoryCount -ne 15 -or
        $quality.staleCount -ne 0 -or
        $quality.noEligibleDataCount -ne 0 -or
        $quality.partialVectorViolationCount -ne 0 -or
        $quality.withheldVectorViolationCount -ne 0 -or
        -not $quality.manifestMatches -or
        $quality.databaseWritesPerformed) {
        throw 'The persisted feature snapshot failed one or more read-only quality checkpoints.'
    }

    Write-Host ''
    Write-Host 'STEP 57 COMPLETE: all 500 immutable classifications match the reviewed manifest.'
    Write-Host 'The audit was read-only. No signal, order, or model-training row was created.'
    Write-Host "Result: $resultPath"
    Write-Host "Log: $logPath"
}
finally {
    if ($transcriptStarted) {
        Stop-Transcript | Out-Null
    }
}
