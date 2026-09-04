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
    [int]$PollSeconds = 15,
    [string]$OutputDirectory = 'C:\MarketBrainData\Review'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$normalizedHash = $ReviewedManifestHash.Trim().ToLowerInvariant()
$creationPath = Join-Path $OutputDirectory "expansion-batch-2-created-$JobId.json"
if (-not (Test-Path -LiteralPath $creationPath -PathType Leaf)) {
    throw "The reviewed Step 25 creation report was not found at $creationPath. Do not start the job."
}

$creationReport = Get-Content -LiteralPath $creationPath -Raw | ConvertFrom-Json
$expectedInstruments = @($creationReport.instruments | ForEach-Object { $_ })
if ($creationReport.reviewedManifestHash -ne $normalizedHash -or
    $creationReport.creation.manifestHash -ne $normalizedHash -or
    [guid]$creationReport.verifiedStatus.jobId -ne $JobId -or
    $creationReport.verifiedStatus.status -ne 'CREATED' -or
    $creationReport.verifiedStatus.workerEnabled -or
    $creationReport.verifiedStatus.totalChunks -ne $creationReport.verifiedStatus.pendingChunks -or
    $expectedInstruments.Count -ne $creationReport.verifiedStatus.instruments) {
    throw 'The saved Step 25 creation checkpoint does not match the reviewed inactive job.'
}

$health = Invoke-RestMethod "$BaseUrl/actuator/health"
if ($health.status -ne 'UP') {
    throw "MarketBrain health is $($health.status), not UP."
}

$current = Invoke-RestMethod "$BaseUrl/api/v1/market-data/backfills/status?jobId=$JobId"
$latest = Invoke-RestMethod "$BaseUrl/api/v1/market-data/backfills/latest"
if ([guid]$latest.jobId -ne $JobId -or
    $current.jobType -ne 'EXPANSION' -or
    $current.batchNumber -ne $creationReport.creation.batchNumber -or
    $current.fromDate -ne $creationReport.verifiedStatus.fromDate -or
    $current.toDate -ne $creationReport.verifiedStatus.toDate -or
    $current.instruments -ne $creationReport.verifiedStatus.instruments -or
    $current.totalChunks -ne $creationReport.verifiedStatus.totalChunks) {
    throw 'The live job identity or immutable boundaries differ from the reviewed Step 25 checkpoint.'
}
if (-not $current.workerEnabled) {
    throw 'The backfill worker is disabled. Set MARKETBRAIN_BACKFILL_WORKER_ENABLED=true and recreate only the backend.'
}
if ($current.status -notin @('CREATED', 'RUNNING', 'WAITING_FOR_CONNECTIVITY', 'COMPLETED', 'PARTIAL_FAILED')) {
    throw "Job $JobId cannot be started or monitored from status $($current.status)."
}

$persistedPayload = Invoke-RestMethod `
    "$BaseUrl/api/v1/market-data/backfills/instruments?jobId=$JobId"
$persistedInstruments = @($persistedPayload | ForEach-Object { $_ })
$expectedBySymbol = @{}
foreach ($instrument in $expectedInstruments) {
    if ($null -eq $instrument.PSObject.Properties['symbol']) {
        throw 'The Step 25 report contains an instrument without a symbol property.'
    }
    $expectedBySymbol[$instrument.symbol] = $instrument
}

$instrumentMismatchCount = 0
foreach ($instrument in $persistedInstruments) {
    if ($null -eq $instrument.PSObject.Properties['symbol']) {
        throw 'The live instrument response contains an item without a symbol property.'
    }
    $expected = $expectedBySymbol[$instrument.symbol]
    if ($null -eq $expected -or
        $instrument.providerInstrumentKey -ne $expected.providerInstrumentKey -or
        $instrument.totalChunks -ne $expected.totalChunks) {
        $instrumentMismatchCount++
    }
}
$uniqueSymbols = @(
    $persistedInstruments |
        ForEach-Object { $_.symbol } |
        Sort-Object -Unique
)
$persistedChunkTotal = ($persistedInstruments | Measure-Object -Property totalChunks -Sum).Sum
if ($persistedInstruments.Count -ne $expectedInstruments.Count -or
    $uniqueSymbols.Count -ne $persistedInstruments.Count -or
    $persistedChunkTotal -ne $current.totalChunks -or
    $instrumentMismatchCount -ne 0) {
    throw 'The live job instruments differ from the reviewed Step 25 creation report.'
}

$startRequestSent = $false
if ($current.status -eq 'CREATED') {
    if ($current.pendingChunks -ne $current.totalChunks -or
        $current.runningChunks -ne 0 -or
        $current.retryChunks -ne 0 -or
        $current.completedChunks -ne 0 -or
        $current.failedChunks -ne 0 -or
        $current.acceptedRows -ne 0 -or
        $current.rejectedRows -ne 0) {
        throw 'The CREATED job is not pristine. Do not start it.'
    }
    $started = Invoke-RestMethod -Method Post `
        "$BaseUrl/api/v1/market-data/backfills/start?jobId=$JobId"
    $startRequestSent = $true
    if ($started.status -notin @('RUNNING', 'WAITING_FOR_CONNECTIVITY', 'COMPLETED')) {
        throw "The start endpoint returned unexpected status $($started.status)."
    }
} elseif ($current.status -in @('RUNNING', 'WAITING_FOR_CONNECTIVITY')) {
    Write-Host "Job $JobId is already $($current.status); continuing read-only monitoring."
} else {
    Write-Host "Job $JobId is already $($current.status); validating its terminal checkpoint."
}

Write-Host ''
Write-Host 'Batch 2 progress (Ctrl+C stops only this monitor; backend processing continues safely)'
$status = $current
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
        Write-Warning 'The local status request failed. The persisted backend job was not changed; monitoring will retry.'
        Start-Sleep -Seconds $PollSeconds
        continue
    }

    if ($status.status -in @('COMPLETED', 'PARTIAL_FAILED')) {
        break
    }
    if ($status.status -notin @('RUNNING', 'WAITING_FOR_CONNECTIVITY')) {
        throw "Monitoring stopped because the job entered unexpected status $($status.status)."
    }
    Start-Sleep -Seconds $PollSeconds
}

$finalPayload = Invoke-RestMethod `
    "$BaseUrl/api/v1/market-data/backfills/instruments?jobId=$JobId"
$finalInstruments = @($finalPayload | ForEach-Object { $_ })
$failedInstruments = @($finalInstruments | Where-Object { $_.failedChunks -gt 0 })
$finalReportPath = Join-Path $OutputDirectory "expansion-batch-2-run-$JobId.json"
[pscustomobject]@{
    completedAt = (Get-Date).ToUniversalTime().ToString('o')
    creationPath = $creationPath
    reviewedManifestHash = $normalizedHash
    startRequestSent = $startRequestSent
    status = $status
    instruments = $finalInstruments
} | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $finalReportPath -Encoding utf8

[pscustomobject]@{
    Status                   = $status.status
    JobId                    = $JobId
    BatchNumber              = $status.batchNumber
    ManifestHash             = $normalizedHash
    StartRequestSent         = $startRequestSent
    Instruments              = $status.instruments
    TotalChunks              = $status.totalChunks
    PendingChunks            = $status.pendingChunks
    RunningChunks            = $status.runningChunks
    RetryChunks              = $status.retryChunks
    CompletedChunks          = $status.completedChunks
    FailedChunks             = $status.failedChunks
    AcceptedRows             = $status.acceptedRows
    RejectedRows             = $status.rejectedRows
    ConnectivityFailureCount = $status.connectivityFailureCount
    FailedInstrumentCount    = $failedInstruments.Count
    WorkerEnabled            = $status.workerEnabled
    FullRunPath              = $finalReportPath
} | Format-List

if ($failedInstruments.Count -gt 0) {
    Write-Host ''
    Write-Host 'Instruments requiring investigation'
    $failedInstruments |
        Sort-Object symbol |
        Format-Table symbol, totalChunks, pendingChunks, retryChunks, completedChunks, failedChunks -AutoSize
}

if ($status.status -ne 'COMPLETED' -or
    $status.pendingChunks -ne 0 -or
    $status.runningChunks -ne 0 -or
    $status.retryChunks -ne 0 -or
    $status.completedChunks -ne $status.totalChunks -or
    $status.failedChunks -ne 0 -or
    $status.rejectedRows -ne 0 -or
    $failedInstruments.Count -ne 0) {
    throw 'Batch 2 did not finish cleanly. Do not alter or retry data manually; share this complete output for review.'
}

Write-Host ''
Write-Host 'STEP 26 PROCESSING COMPLETE: all Batch 2 chunks completed without a failed or rejected row.'
Write-Host 'Disable MARKETBRAIN_BACKFILL_WORKER_ENABLED and recreate only the backend now.'
Write-Host 'Then share this complete output and the disabled-worker status for quality review.'
