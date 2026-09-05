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

$batchNumber = 3
$expectedInstrumentCount = 200
$expectedTotalChunks = 2320
$expectedAcceptedBefore = 549804
$expectedAcceptedAfter = 550050
$expectedRejectedRows = 6
$reviewedSymbol = 'LALPATHLAB'
$normalizedHash = $ReviewedManifestHash.Trim().ToLowerInvariant()
$creationPath = Join-Path $OutputDirectory "expansion-batch-$batchNumber-created-$JobId.json"
$failedRunPath = Join-Path $OutputDirectory "expansion-batch-$batchNumber-run-$JobId.json"

if (-not (Test-Path -LiteralPath $creationPath -PathType Leaf) -or
    -not (Test-Path -LiteralPath $failedRunPath -PathType Leaf)) {
    throw 'The reviewed Batch 3 creation report or failed-run report is missing. Do not retry the job.'
}

$creationReport = Get-Content -LiteralPath $creationPath -Raw | ConvertFrom-Json
$failedRunReport = Get-Content -LiteralPath $failedRunPath -Raw | ConvertFrom-Json
$failedReportInstruments = @(
    $failedRunReport.instruments | Where-Object { $_.failedChunks -gt 0 }
)
$reviewedFailedInstrument = @(
    $failedReportInstruments | Where-Object { $_.symbol -eq $reviewedSymbol }
)

if ($creationReport.reviewedManifestHash -ne $normalizedHash -or
    $creationReport.creation.manifestHash -ne $normalizedHash -or
    $creationReport.creation.batchNumber -ne $batchNumber -or
    [guid]$creationReport.verifiedStatus.jobId -ne $JobId -or
    $creationReport.verifiedStatus.instruments -ne $expectedInstrumentCount -or
    $creationReport.verifiedStatus.totalChunks -ne $expectedTotalChunks -or
    $failedRunReport.reviewedManifestHash -ne $normalizedHash -or
    [guid]$failedRunReport.status.jobId -ne $JobId -or
    $failedRunReport.status.batchNumber -ne $batchNumber -or
    $failedRunReport.status.status -ne 'PARTIAL_FAILED' -or
    $failedRunReport.status.instruments -ne $expectedInstrumentCount -or
    $failedRunReport.status.totalChunks -ne $expectedTotalChunks -or
    $failedRunReport.status.completedChunks -ne ($expectedTotalChunks - 1) -or
    $failedRunReport.status.failedChunks -ne 1 -or
    $failedRunReport.status.acceptedRows -ne $expectedAcceptedBefore -or
    $failedRunReport.status.rejectedRows -ne $expectedRejectedRows -or
    $failedReportInstruments.Count -ne 1 -or
    $reviewedFailedInstrument.Count -ne 1 -or
    $reviewedFailedInstrument[0].totalChunks -ne 11 -or
    $reviewedFailedInstrument[0].completedChunks -ne 10 -or
    $reviewedFailedInstrument[0].failedChunks -ne 1) {
    throw 'The saved reports do not describe the exact reviewed LALPATHLAB Batch 3 failure.'
}

$health = Invoke-RestMethod "$BaseUrl/actuator/health"
if ($health.status -ne 'UP') {
    throw "MarketBrain health is $($health.status), not UP."
}

$status = Invoke-RestMethod "$BaseUrl/api/v1/market-data/backfills/status?jobId=$JobId"
$latest = Invoke-RestMethod "$BaseUrl/api/v1/market-data/backfills/latest"
if ([guid]$latest.jobId -ne $JobId -or
    $status.jobType -ne 'EXPANSION' -or
    $status.batchNumber -ne $batchNumber -or
    $status.instruments -ne $expectedInstrumentCount -or
    $status.totalChunks -ne $expectedTotalChunks) {
    throw 'The live job identity differs from the reviewed Batch 3 checkpoint.'
}
if (-not $status.workerEnabled) {
    throw 'The backfill worker is disabled. Enable it locally only after deploying the reviewed correction.'
}
if ($status.status -notin @('PARTIAL_FAILED', 'RUNNING', 'WAITING_FOR_CONNECTIVITY', 'COMPLETED')) {
    throw "The LALPATHLAB recovery cannot continue from status $($status.status)."
}

$instrumentPayload = Invoke-RestMethod `
    "$BaseUrl/api/v1/market-data/backfills/instruments?jobId=$JobId"
$instruments = @($instrumentPayload | ForEach-Object { $_ })
$failedInstruments = @($instruments | Where-Object { $_.failedChunks -gt 0 })
$lalPathLab = @($instruments | Where-Object { $_.symbol -eq $reviewedSymbol })

if ($instruments.Count -ne $expectedInstrumentCount -or $lalPathLab.Count -ne 1) {
    throw 'The live Batch 3 instrument checkpoint does not contain the reviewed 200 instruments and LALPATHLAB.'
}
if ($status.status -eq 'PARTIAL_FAILED' -and
    ($status.completedChunks -ne ($expectedTotalChunks - 1) -or
     $status.failedChunks -ne 1 -or
     $status.acceptedRows -ne $expectedAcceptedBefore -or
     $status.rejectedRows -ne $expectedRejectedRows -or
     $failedInstruments.Count -ne 1 -or
     $failedInstruments[0].symbol -ne $reviewedSymbol -or
     $lalPathLab[0].totalChunks -ne 11 -or
     $lalPathLab[0].completedChunks -ne 10 -or
     $lalPathLab[0].failedChunks -ne 1)) {
    throw 'The live failed checkpoint is not the single reviewed LALPATHLAB failure. Do not retry it.'
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
Write-Host 'LALPATHLAB recovery progress (Ctrl+C stops only this monitor; backend processing continues safely)'
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
$finalFailedInstruments = @($finalInstruments | Where-Object { $_.failedChunks -gt 0 })
$finalLalPathLab = @($finalInstruments | Where-Object { $_.symbol -eq $reviewedSymbol })
$recoveryPath = Join-Path $OutputDirectory "expansion-batch-3-lalpathlab-recovery-$JobId.json"

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
    Status                     = $status.status
    JobId                      = $JobId
    BatchNumber                = $status.batchNumber
    ManifestHash               = $normalizedHash
    RetryRequestSent           = $retryRequestSent
    RetriedChunks              = if ($retryRequestSent) { $retry.retriedChunks } else { 0 }
    TotalChunks                = $status.totalChunks
    CompletedChunks            = $status.completedChunks
    FailedChunks               = $status.failedChunks
    AcceptedRows               = $status.acceptedRows
    RejectedRows               = $status.rejectedRows
    LalPathLabCompletedChunks  = if ($finalLalPathLab.Count -eq 1) {
        $finalLalPathLab[0].completedChunks
    } else { -1 }
    LalPathLabFailedChunks     = if ($finalLalPathLab.Count -eq 1) {
        $finalLalPathLab[0].failedChunks
    } else { -1 }
    FailedInstrumentCount      = $finalFailedInstruments.Count
    ConnectivityFailureCount   = $status.connectivityFailureCount
    WorkerEnabled              = $status.workerEnabled
    FullRecoveryPath           = $recoveryPath
} | Format-List

if ($status.status -ne 'COMPLETED' -or
    $status.pendingChunks -ne 0 -or
    $status.runningChunks -ne 0 -or
    $status.retryChunks -ne 0 -or
    $status.completedChunks -ne $expectedTotalChunks -or
    $status.failedChunks -ne 0 -or
    $status.acceptedRows -ne $expectedAcceptedAfter -or
    $status.rejectedRows -ne $expectedRejectedRows -or
    $finalFailedInstruments.Count -ne 0 -or
    $finalLalPathLab.Count -ne 1 -or
    $finalLalPathLab[0].completedChunks -ne 11 -or
    $finalLalPathLab[0].failedChunks -ne 0) {
    throw 'The reviewed LALPATHLAB recovery did not reach every expected checkpoint. Do not retry or alter data manually.'
}

Write-Host ''
Write-Host 'LALPATHLAB RECOVERY COMPLETE: exactly one reviewed chunk was recovered and all 2320 Batch 3 chunks completed.'
Write-Host 'The six rejected provider rows remain preserved for the Batch 3 quality audit.'
Write-Host 'Disable MARKETBRAIN_BACKFILL_WORKER_ENABLED and recreate only the backend now.'
Write-Host 'Then verify the normalization evidence using Step 36 in the runbook.'
