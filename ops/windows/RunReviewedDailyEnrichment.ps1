[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [datetime]$TargetDate,

    [Parameter(Mandatory)]
    [ValidatePattern('^[0-9a-f]{64}$')]
    [string]$ReviewedManifestHash,

    [Parameter()]
    [ValidateRange(1, 500)]
    [int]$ExpectedInstrumentCount = 500,

    [Parameter()]
    [ValidateRange(5, 360)]
    [int]$MaximumWaitMinutes = 180,

    [Parameter()]
    [string]$BaseUrl = 'http://127.0.0.1:8080',

    [Parameter()]
    [string]$OutputDirectory = 'C:\MarketBrainData\Review'
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$dateText = $TargetDate.ToString('yyyy-MM-dd')
New-Item -ItemType Directory -Path $OutputDirectory -Force | Out-Null
$logPath = Join-Path $OutputDirectory "daily-enrichment-run-$dateText.log"
$transcriptStarted = $false

try {
    Start-Transcript -Path $logPath -Force | Out-Null
    $transcriptStarted = $true

    $health = Invoke-RestMethod "$BaseUrl/actuator/health"
    if ($health.status -ne 'UP') {
        throw "MarketBrain health is $($health.status); no run was created or started."
    }

    $previewUri = "$BaseUrl/api/v1/market-data/daily-enrichment/preview?targetDate=$dateText"
    $runtimePreview = Invoke-RestMethod $previewUri
    if ($runtimePreview.workerEnabled -ne $true) {
        throw 'The persisted collection worker must be enabled for Step 51.'
    }
    if ($runtimePreview.schedulerEnabled -ne $false) {
        throw 'The automatic daily scheduler must remain disabled for the first reviewed run.'
    }

    $run = $null
    try {
        $latest = Invoke-RestMethod "$BaseUrl/api/v1/market-data/daily-enrichment/runs/latest"
        if ([string]$latest.targetDate -eq $dateText) {
            if ([string]$latest.manifestHash -ne $ReviewedManifestHash) {
                throw 'An existing run for the target date has a different manifest hash.'
            }
            $run = $latest
            Write-Host "Reusing reviewed daily run $($run.runId) with status $($run.status)."
        }
    }
    catch {
        $response = $_.Exception.Response
        if ($null -eq $response -or [int]$response.StatusCode -ne 404) {
            throw
        }
    }

    if ($null -eq $run) {
        if ([string]$runtimePreview.manifestHash -ne $ReviewedManifestHash) {
            throw 'The live preview differs from the reviewed daily enrichment manifest.'
        }
        if ($runtimePreview.blockedInstruments -ne 0) {
            throw "The live preview contains $($runtimePreview.blockedInstruments) blocked instruments."
        }
        if ($runtimePreview.instrumentCount -ne $ExpectedInstrumentCount -or
                $runtimePreview.fetchInstruments -ne $ExpectedInstrumentCount) {
            throw 'The live preview instrument counts differ from the reviewed first-run checkpoint.'
        }

        $createUri = "$BaseUrl/api/v1/market-data/daily-enrichment/runs" +
            "?targetDate=$dateText" +
            "&expectedManifestHash=$([uri]::EscapeDataString($ReviewedManifestHash))"
        $run = Invoke-RestMethod -Method Post $createUri
        Write-Host "Created reviewed daily run $($run.runId)."
    }

    if ([string]$run.manifestHash -ne $ReviewedManifestHash) {
        throw 'The persisted run manifest differs from the reviewed manifest.'
    }
    if ($run.instruments -ne $ExpectedInstrumentCount -or $run.totalChunks -ne $ExpectedInstrumentCount) {
        throw 'The persisted run does not contain exactly one chunk for every reviewed instrument.'
    }
    if ($run.schedulerEnabled -ne $false -or $run.workerEnabled -ne $true) {
        throw 'The live scheduler/worker configuration differs from the reviewed Step 51 configuration.'
    }

    if ($run.status -eq 'CREATED') {
        $startUri = "$BaseUrl/api/v1/market-data/daily-enrichment/runs/start" +
            "?runId=$([uri]::EscapeDataString([string]$run.runId))"
        $run = Invoke-RestMethod -Method Post $startUri
    }
    elseif ($run.status -notin @('RUNNING', 'WAITING_FOR_CONNECTIVITY', 'COMPLETED')) {
        throw "Daily enrichment run cannot continue from status $($run.status)."
    }

    $deadline = [datetime]::UtcNow.AddMinutes($MaximumWaitMinutes)
    while ($run.status -notin @('COMPLETED', 'PARTIAL_FAILED')) {
        if ([datetime]::UtcNow -ge $deadline) {
            throw "Daily enrichment did not reach a terminal state within $MaximumWaitMinutes minutes."
        }
        Start-Sleep -Seconds 5
        $statusUri = "$BaseUrl/api/v1/market-data/daily-enrichment/runs/status" +
            "?runId=$([uri]::EscapeDataString([string]$run.runId))"
        $run = Invoke-RestMethod $statusUri
        [pscustomobject]@{
            CheckedAt       = Get-Date
            Status          = $run.status
            ProgressPercent = $run.progressPercent
            CompletedChunks = $run.completedChunks
            FailedChunks    = $run.failedChunks
            AcceptedRows    = $run.acceptedRows
            RejectedRows    = $run.rejectedRows
        } | Format-List
    }

    $resultPath = Join-Path $OutputDirectory "daily-enrichment-run-$($run.runId).json"
    $run | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $resultPath -Encoding utf8

    [pscustomobject]@{
        Status                   = $run.status
        RunId                    = $run.runId
        TargetDate               = $run.targetDate
        ManifestHash             = $run.manifestHash
        Instruments              = $run.instruments
        TotalChunks              = $run.totalChunks
        CompletedChunks          = $run.completedChunks
        FailedChunks             = $run.failedChunks
        AcceptedRows             = $run.acceptedRows
        RejectedRows             = $run.rejectedRows
        ConnectivityFailureCount = $run.connectivityFailureCount
        WorkerEnabled            = $run.workerEnabled
        SchedulerEnabled         = $run.schedulerEnabled
        FullResultPath           = $resultPath
        FullLogPath              = $logPath
    } | Format-List

    if ($run.status -ne 'COMPLETED' -or $run.failedChunks -ne 0 -or
            $run.completedChunks -ne $ExpectedInstrumentCount) {
        throw 'The reviewed daily enrichment did not finish cleanly. Do not retry or alter data manually.'
    }

    Write-Host ''
    Write-Host 'STEP 51 COMPLETE: all 500 reviewed incremental chunks completed and raw imports were preserved.'
    Write-Host 'Keep the scheduler disabled. Share this complete output before the worker is disabled and quality is audited.'
}
finally {
    if ($transcriptStarted) {
        Stop-Transcript | Out-Null
    }
}
