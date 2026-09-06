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

$batchNumber = 4
$expectedInstrumentCount = 190
$expectedTotalChunks = 2190
$expectedAcceptedBefore = 519772
$expectedAcceptedAfter = 520018
$expectedRejectedRows = 29
$reviewedSymbol = 'SUZLON'
$normalizedHash = $ReviewedManifestHash.Trim().ToLowerInvariant()
$creationPath = Join-Path $OutputDirectory "expansion-batch-$batchNumber-created-$JobId.json"
$failedRunPath = Join-Path $OutputDirectory "expansion-batch-$batchNumber-run-$JobId.json"
$evidencePath = Join-Path $OutputDirectory "expansion-batch-$batchNumber-suzlon-investigation-$JobId.json"

foreach ($path in @($creationPath, $failedRunPath, $evidencePath)) {
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        throw "A reviewed Batch 4 checkpoint is missing at $path. Do not retry the job."
    }
}

$creationReport = Get-Content -LiteralPath $creationPath -Raw | ConvertFrom-Json
$failedRunReport = Get-Content -LiteralPath $failedRunPath -Raw | ConvertFrom-Json
$evidenceReport = Get-Content -LiteralPath $evidencePath -Raw | ConvertFrom-Json
$failedReportInstruments = @($failedRunReport.instruments | Where-Object { $_.failedChunks -gt 0 })
$evidenceTargetRows = @($evidenceReport.targetRows | ForEach-Object { $_ })
$evidenceOfficialRows = @($evidenceReport.officialRows | ForEach-Object { $_ })
$evidenceLows = @($evidenceTargetRows | ForEach-Object { [decimal]$_.low } | Sort-Object)

if ($creationReport.reviewedManifestHash -ne $normalizedHash -or
    $creationReport.creation.manifestHash -ne $normalizedHash -or
    $creationReport.creation.batchNumber -ne $batchNumber -or
    [guid]$creationReport.verifiedStatus.jobId -ne $JobId -or
    $creationReport.verifiedStatus.instruments -ne $expectedInstrumentCount -or
    $creationReport.verifiedStatus.totalChunks -ne $expectedTotalChunks -or
    $failedRunReport.reviewedManifestHash -ne $normalizedHash -or
    [guid]$failedRunReport.status.jobId -ne $JobId -or
    $failedRunReport.status.status -ne 'PARTIAL_FAILED' -or
    $failedRunReport.status.completedChunks -ne ($expectedTotalChunks - 1) -or
    $failedRunReport.status.failedChunks -ne 1 -or
    $failedRunReport.status.acceptedRows -ne $expectedAcceptedBefore -or
    $failedRunReport.status.rejectedRows -ne $expectedRejectedRows -or
    $failedReportInstruments.Count -ne 1 -or
    $failedReportInstruments[0].symbol -ne $reviewedSymbol -or
    $failedReportInstruments[0].totalChunks -ne 15 -or
    $failedReportInstruments[0].completedChunks -ne 14 -or
    $failedReportInstruments[0].failedChunks -ne 1) {
    throw 'The saved creation and failed-run reports do not describe the exact reviewed SUZLON failure.'
}

if ($evidenceReport.status -ne 'EVIDENCE_CAPTURED' -or
    [guid]$evidenceReport.jobId -ne $JobId -or
    $evidenceReport.reviewedManifestHash -ne $normalizedHash -or
    $evidenceReport.symbol -ne $reviewedSymbol -or
    $evidenceReport.providerInstrumentKey -ne 'NSE_EQ|INE040H01021' -or
    $evidenceReport.providerRowCount -ne 247 -or
    $evidenceReport.duplicateTradingDateCount -ne 1 -or
    $evidenceTargetRows.Count -ne 2 -or
    $evidenceLows.Count -ne 2 -or
    $evidenceLows[0] -ne [decimal]'18.70' -or
    $evidenceLows[1] -ne [decimal]'18.75' -or
    @($evidenceTargetRows | Where-Object {
        [decimal]$_.open -ne [decimal]'19.00' -or
        [decimal]$_.high -ne [decimal]'19.30' -or
        [decimal]$_.close -ne [decimal]'19.15' -or
        [decimal]$_.volume -ne [decimal]'22529886'
    }).Count -ne 0 -or
    $evidenceOfficialRows.Count -ne 1 -or
    $evidenceOfficialRows[0].SYMBOL -ne $reviewedSymbol -or
    $evidenceOfficialRows[0].ISIN -ne 'INE040H01021' -or
    [decimal]$evidenceOfficialRows[0].OPEN -ne [decimal]'20.7' -or
    [decimal]$evidenceOfficialRows[0].HIGH -ne [decimal]'21' -or
    [decimal]$evidenceOfficialRows[0].LOW -ne [decimal]'20.4' -or
    [decimal]$evidenceOfficialRows[0].CLOSE -ne [decimal]'20.85' -or
    [decimal]$evidenceOfficialRows[0].TOTTRDQTY -ne [decimal]'20687256' -or
    $evidenceReport.databaseWritesPerformed -or
    $evidenceReport.workerEnabled -or
    $evidenceReport.providerResponseHash -notmatch '^[0-9a-f]{64}$' -or
    $evidenceReport.officialArchiveHash -notmatch '^[0-9a-f]{64}$') {
    throw 'The saved SUZLON evidence differs from the exact reviewed provider and NSE rows.'
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
    throw 'The live job identity differs from the reviewed Batch 4 checkpoint.'
}
if (-not $status.workerEnabled) {
    throw 'The backfill worker is disabled. Enable it only after verifying the reviewed SUZLON runtime.'
}
if ($status.status -notin @('PARTIAL_FAILED', 'RUNNING', 'WAITING_FOR_CONNECTIVITY', 'COMPLETED')) {
    throw "The SUZLON recovery cannot continue from status $($status.status)."
}

$instrumentPayload = Invoke-RestMethod "$BaseUrl/api/v1/market-data/backfills/instruments?jobId=$JobId"
$instruments = @($instrumentPayload | ForEach-Object { $_ })
$failedInstruments = @($instruments | Where-Object { $_.failedChunks -gt 0 })
$suzlon = @($instruments | Where-Object { $_.symbol -eq $reviewedSymbol })
if ($instruments.Count -ne $expectedInstrumentCount -or $suzlon.Count -ne 1) {
    throw 'The live Batch 4 instrument checkpoint does not contain the reviewed 190 instruments and SUZLON.'
}
if ($status.status -eq 'PARTIAL_FAILED' -and
    ($status.completedChunks -ne ($expectedTotalChunks - 1) -or
     $status.failedChunks -ne 1 -or
     $status.acceptedRows -ne $expectedAcceptedBefore -or
     $status.rejectedRows -ne $expectedRejectedRows -or
     $failedInstruments.Count -ne 1 -or
     $failedInstruments[0].symbol -ne $reviewedSymbol -or
     $suzlon[0].totalChunks -ne 15 -or
     $suzlon[0].completedChunks -ne 14 -or
     $suzlon[0].failedChunks -ne 1)) {
    throw 'The live failed checkpoint is not the single reviewed SUZLON failure. Do not retry it.'
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
Write-Host 'SUZLON recovery progress (Ctrl+C stops only this monitor; backend processing continues safely)'
while ($true) {
    try {
        $status = Invoke-RestMethod "$BaseUrl/api/v1/market-data/backfills/status?jobId=$JobId"
        [pscustomobject]@{
            CheckedAt = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss')
            Status = $status.status
            ProgressPercent = $status.progressPercent
            PendingChunks = $status.pendingChunks
            RunningChunks = $status.runningChunks
            RetryChunks = $status.retryChunks
            CompletedChunks = $status.completedChunks
            FailedChunks = $status.failedChunks
            AcceptedRows = $status.acceptedRows
            RejectedRows = $status.rejectedRows
            ConnectivityFailureCount = $status.connectivityFailureCount
            ConnectivityRetryAt = $status.connectivityRetryAt
            LastConnectivityError = $status.lastConnectivityErrorCode
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

$finalInstrumentPayload = Invoke-RestMethod "$BaseUrl/api/v1/market-data/backfills/instruments?jobId=$JobId"
$finalInstruments = @($finalInstrumentPayload | ForEach-Object { $_ })
$finalFailedInstruments = @($finalInstruments | Where-Object { $_.failedChunks -gt 0 })
$finalSuzlon = @($finalInstruments | Where-Object { $_.symbol -eq $reviewedSymbol })
$recoveryPath = Join-Path $OutputDirectory "expansion-batch-4-suzlon-recovery-$JobId.json"

[pscustomobject]@{
    completedAt = (Get-Date).ToUniversalTime().ToString('o')
    creationPath = $creationPath
    failedRunPath = $failedRunPath
    evidencePath = $evidencePath
    reviewedManifestHash = $normalizedHash
    retryRequestSent = $retryRequestSent
    status = $status
    instruments = $finalInstruments
} | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $recoveryPath -Encoding utf8

[pscustomobject]@{
    Status = $status.status
    JobId = $JobId
    BatchNumber = $status.batchNumber
    ManifestHash = $normalizedHash
    RetryRequestSent = $retryRequestSent
    RetriedChunks = if ($retryRequestSent) { $retry.retriedChunks } else { 0 }
    TotalChunks = $status.totalChunks
    CompletedChunks = $status.completedChunks
    FailedChunks = $status.failedChunks
    AcceptedRows = $status.acceptedRows
    RejectedRows = $status.rejectedRows
    SuzlonCompletedChunks = if ($finalSuzlon.Count -eq 1) { $finalSuzlon[0].completedChunks } else { -1 }
    SuzlonFailedChunks = if ($finalSuzlon.Count -eq 1) { $finalSuzlon[0].failedChunks } else { -1 }
    FailedInstrumentCount = $finalFailedInstruments.Count
    ConnectivityFailureCount = $status.connectivityFailureCount
    WorkerEnabled = $status.workerEnabled
    FullRecoveryPath = $recoveryPath
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
    $finalSuzlon.Count -ne 1 -or
    $finalSuzlon[0].completedChunks -ne 15 -or
    $finalSuzlon[0].failedChunks -ne 0) {
    throw 'The reviewed SUZLON recovery did not reach every expected checkpoint. Do not retry or alter data manually.'
}

Write-Host ''
Write-Host 'SUZLON RECOVERY COMPLETE: exactly one reviewed chunk was recovered and all 2190 Batch 4 chunks completed.'
Write-Host 'The 29 rejected provider rows remain preserved for the Batch 4 quality analysis.'
Write-Host 'Disable MARKETBRAIN_BACKFILL_WORKER_ENABLED and recreate only the backend now.'
Write-Host 'Then share this complete output and the disabled-worker status for final Batch 4 quality review.'
