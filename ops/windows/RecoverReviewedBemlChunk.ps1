[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [ValidateNotNull()]
    [guid]$JobId,
    [Parameter(Mandatory)]
    [ValidatePattern('^[0-9a-fA-F]{64}$')]
    [string]$ReviewedManifestHash,
    [string]$BaseUrl = 'http://127.0.0.1:8080',
    [ValidateRange(5, 300)]
    [int]$PollSeconds = 5,
    [string]$OutputDirectory = 'C:\MarketBrainData\Review'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$normalizedHash = $ReviewedManifestHash.Trim().ToLowerInvariant()
$creationPath = Join-Path $OutputDirectory "expansion-batch-2-created-$JobId.json"
$failedRunPath = Join-Path $OutputDirectory "expansion-batch-2-run-$JobId.json"
if (-not (Test-Path -LiteralPath $creationPath -PathType Leaf) -or
    -not (Test-Path -LiteralPath $failedRunPath -PathType Leaf)) {
    throw 'The reviewed Step 25 creation report or Step 26 failed-run report is missing. Do not retry the job.'
}

$creationReport = Get-Content -LiteralPath $creationPath -Raw | ConvertFrom-Json
$failedRunReport = Get-Content -LiteralPath $failedRunPath -Raw | ConvertFrom-Json
if ($creationReport.reviewedManifestHash -ne $normalizedHash -or
    $failedRunReport.reviewedManifestHash -ne $normalizedHash -or
    [guid]$creationReport.verifiedStatus.jobId -ne $JobId -or
    [guid]$failedRunReport.status.jobId -ne $JobId -or
    $failedRunReport.status.status -ne 'PARTIAL_FAILED' -or
    $failedRunReport.status.totalChunks -ne 623 -or
    $failedRunReport.status.completedChunks -ne 622 -or
    $failedRunReport.status.failedChunks -ne 1 -or
    $failedRunReport.status.rejectedRows -ne 0) {
    throw 'The saved reports do not describe the reviewed single-chunk Batch 2 failure.'
}

$health = Invoke-RestMethod "$BaseUrl/actuator/health"
if ($health.status -ne 'UP') {
    throw "MarketBrain health is $($health.status), not UP."
}

$status = Invoke-RestMethod "$BaseUrl/api/v1/market-data/backfills/status?jobId=$JobId"
$latest = Invoke-RestMethod "$BaseUrl/api/v1/market-data/backfills/latest"
if ([guid]$latest.jobId -ne $JobId -or
    $status.jobType -ne 'EXPANSION' -or
    $status.batchNumber -ne 2 -or
    $status.instruments -ne 50 -or
    $status.totalChunks -ne 623) {
    throw 'The live job identity differs from the reviewed Batch 2 checkpoint.'
}
if (-not $status.workerEnabled) {
    throw 'The backfill worker is disabled. Enable it locally only after deploying the reviewed correction.'
}
if ($status.status -notin @('PARTIAL_FAILED', 'RUNNING', 'WAITING_FOR_CONNECTIVITY', 'COMPLETED')) {
    throw "The BEML recovery cannot continue from status $($status.status)."
}

$instrumentPayload = Invoke-RestMethod `
    "$BaseUrl/api/v1/market-data/backfills/instruments?jobId=$JobId"
$instruments = @($instrumentPayload | ForEach-Object { $_ })
$failedInstruments = @($instruments | Where-Object { $_.failedChunks -gt 0 })
if ($status.status -eq 'PARTIAL_FAILED' -and
    ($failedInstruments.Count -ne 1 -or
     $failedInstruments[0].symbol -ne 'BEML' -or
     $failedInstruments[0].totalChunks -ne 15 -or
     $failedInstruments[0].completedChunks -ne 14 -or
     $failedInstruments[0].failedChunks -ne 1)) {
    throw 'The live failed-instrument checkpoint is not the single reviewed BEML failure.'
}

$retryRequestSent = $false
if ($status.status -eq 'PARTIAL_FAILED') {
    $retry = Invoke-RestMethod -Method Post `
        "$BaseUrl/api/v1/market-data/backfills/retry-invalid-data?jobId=$JobId"
    $retryRequestSent = $true
    if ($retry.retriedChunks -ne 1 -or $retry.status -ne 'RUNNING') {
        throw 'The controlled endpoint did not reset exactly one INVALID_DATA chunk.'
    }
} elseif ($status.status -in @('RUNNING', 'WAITING_FOR_CONNECTIVITY')) {
    Write-Host "The reviewed retry is already $($status.status); continuing read-only monitoring."
} else {
    Write-Host 'The reviewed retry is already complete; validating its terminal checkpoint.'
}

Write-Host ''
Write-Host 'BEML recovery progress (Ctrl+C stops only this monitor; backend processing continues safely)'
while ($true) {
    try {
        $status = Invoke-RestMethod "$BaseUrl/api/v1/market-data/backfills/status?jobId=$JobId"
        [pscustomobject]@{
            CheckedAt                = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss')
            Status                   = $status.status
            ProgressPercent          = $status.progressPercent
            PendingChunks            = $status.pendingChunks
            RunningChunks            = $status.runningChunks
            RetryChunks              = $status.retryChunks
            CompletedChunks          = $status.completedChunks
            FailedChunks             = $status.failedChunks
            AcceptedRows             = $status.acceptedRows
            RejectedRows             = $status.rejectedRows
            ConnectivityFailureCount = $status.connectivityFailureCount
            ConnectivityRetryAt      = $status.connectivityRetryAt
            LastConnectivityError    = $status.lastConnectivityErrorCode
        } | Format-List
    } catch {
        Write-Warning 'The local status request failed. The persisted retry was not changed; monitoring will continue.'
        Start-Sleep -Seconds $PollSeconds
        continue
    }

    if ($status.status -in @('COMPLETED', 'PARTIAL_FAILED')) {
        break
    }
    if ($status.status -notin @('RUNNING', 'WAITING_FOR_CONNECTIVITY')) {
        throw "Recovery monitoring stopped at unexpected status $($status.status)."
    }
    Start-Sleep -Seconds $PollSeconds
}

$finalInstrumentPayload = Invoke-RestMethod `
    "$BaseUrl/api/v1/market-data/backfills/instruments?jobId=$JobId"
$finalInstruments = @($finalInstrumentPayload | ForEach-Object { $_ })
$beml = @($finalInstruments | Where-Object { $_.symbol -eq 'BEML' })
$recoveryPath = Join-Path $OutputDirectory "expansion-batch-2-beml-recovery-$JobId.json"
[pscustomobject]@{
    completedAt = (Get-Date).ToUniversalTime().ToString('o')
    creationPath = $creationPath
    failedRunPath = $failedRunPath
    reviewedManifestHash = $normalizedHash
    retryRequestSent = $retryRequestSent
    status = $status
    instruments = $finalInstruments
} | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $recoveryPath -Encoding utf8

[pscustomobject]@{
    Status                   = $status.status
    JobId                    = $JobId
    BatchNumber              = $status.batchNumber
    ManifestHash             = $normalizedHash
    RetryRequestSent         = $retryRequestSent
    RetriedChunks            = if ($retryRequestSent) { $retry.retriedChunks } else { 0 }
    TotalChunks              = $status.totalChunks
    CompletedChunks          = $status.completedChunks
    FailedChunks             = $status.failedChunks
    AcceptedRows             = $status.acceptedRows
    RejectedRows             = $status.rejectedRows
    BemlCompletedChunks      = if ($beml.Count -eq 1) { $beml[0].completedChunks } else { -1 }
    BemlFailedChunks         = if ($beml.Count -eq 1) { $beml[0].failedChunks } else { -1 }
    ConnectivityFailureCount = $status.connectivityFailureCount
    WorkerEnabled            = $status.workerEnabled
    FullRecoveryPath         = $recoveryPath
} | Format-List

if ($status.status -ne 'COMPLETED' -or
    $status.pendingChunks -ne 0 -or
    $status.runningChunks -ne 0 -or
    $status.retryChunks -ne 0 -or
    $status.completedChunks -ne 623 -or
    $status.failedChunks -ne 0 -or
    $status.acceptedRows -ne 149636 -or
    $status.rejectedRows -ne 0 -or
    $beml.Count -ne 1 -or
    $beml[0].completedChunks -ne 15 -or
    $beml[0].failedChunks -ne 0) {
    throw 'The reviewed BEML recovery did not reach every expected checkpoint. Do not retry or alter data manually.'
}

Write-Host ''
Write-Host 'BEML RECOVERY COMPLETE: exactly one reviewed chunk was recovered and all 623 Batch 2 chunks completed.'
Write-Host 'Disable MARKETBRAIN_BACKFILL_WORKER_ENABLED and recreate only the backend now.'
Write-Host 'Then verify the normalization audit evidence using Step 27 in the runbook.'
