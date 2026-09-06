[CmdletBinding()]
param(
    [string]$BaseUrl = 'http://127.0.0.1:8080',
    [string]$EnvFile = '.env',
    [string]$OutputDirectory = 'C:\MarketBrainData\Review'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$health = Invoke-RestMethod "$BaseUrl/actuator/health"
if ($health.status -ne 'UP') {
    throw "MarketBrain health is $($health.status), not UP."
}

$latest = Invoke-RestMethod "$BaseUrl/api/v1/market-data/backfills/latest"
if ($latest.workerEnabled) {
    throw 'The backfill worker must remain disabled while the SUZLON runtime correction is verified.'
}

$containerIds = @(docker compose --env-file $EnvFile ps -q marketbrain-service)
if ($LASTEXITCODE -ne 0 -or $containerIds.Count -ne 1 -or
    [string]::IsNullOrWhiteSpace($containerIds[0])) {
    throw 'The running marketbrain-service container could not be identified.'
}
$containerId = $containerIds[0].Trim()

New-Item -ItemType Directory -Path $OutputDirectory -Force | Out-Null
$runtimeJar = Join-Path $OutputDirectory 'batch4-suzlon-reviewed-runtime.jar'
docker cp "${containerId}:/app/app.jar" $runtimeJar | Out-Host
if ($LASTEXITCODE -ne 0 -or -not (Test-Path -LiteralPath $runtimeJar -PathType Leaf)) {
    throw 'The running application JAR could not be copied for read-only verification.'
}

Add-Type -AssemblyName System.IO.Compression.FileSystem
$archive = [System.IO.Compression.ZipFile]::OpenRead($runtimeJar)
try {
    $entry = $archive.GetEntry(
        'BOOT-INF/classes/in/marketbrain/marketdata/upstox/UpstoxCandleBatchNormalizer$DailyCandleGroup.class'
    )
    if ($null -eq $entry) {
        throw 'The runtime JAR does not contain the candle-normalization implementation class.'
    }
    $stream = $entry.Open()
    $memory = [System.IO.MemoryStream]::new()
    try {
        $stream.CopyTo($memory)
        $classText = [System.Text.Encoding]::ASCII.GetString($memory.ToArray())
    } finally {
        $memory.Dispose()
        $stream.Dispose()
    }
} finally {
    $archive.Dispose()
}

$reasonPresent = $classText.Contains('REVIEWED_OFFICIAL_MISMATCH_LOW_VARIANCE')
$officialEvidencePresent = $classText.Contains('officialCloseDifference=1.70')
$decisionPresent = $classText.Contains('retain-provider-market-open-and-widest-range')
$runtimeCorrectionPresent = $reasonPresent -and $officialEvidencePresent -and $decisionPresent

[pscustomobject]@{
    Status = if ($runtimeCorrectionPresent) { 'VERIFIED' } else { 'STALE_RUNTIME' }
    ContainerId = $containerId
    RuntimeCorrectionPresent = $runtimeCorrectionPresent
    ReviewedReasonPresent = $reasonPresent
    OfficialEvidencePresent = $officialEvidencePresent
    ReviewedDecisionPresent = $decisionPresent
    VerifiedClassEntry = $entry.FullName
    WorkerEnabled = $latest.workerEnabled
    RuntimeJar = $runtimeJar
} | Format-List

if (-not $runtimeCorrectionPresent) {
    throw 'The running backend does not contain the reviewed SUZLON correction. Do not retry Batch 4.'
}

Write-Host 'RUNTIME VERIFIED: the exact reviewed SUZLON correction is running with the worker disabled.'
