[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [datetime]$TargetDate,

    [Parameter(Mandatory = $true)]
    [ValidatePattern('^[0-9a-f]{64}$')]
    [string]$ExpectedFeatureManifestHash,

    [Parameter()]
    [string]$BaseUrl = 'http://127.0.0.1:8080',

    [Parameter()]
    [string]$OutputDirectory = 'C:\MarketBrainData\Review'
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$approvedTargetDate = '2026-09-08'
$approvedDailyRunId = [guid]'059437aa-2dec-4b56-a6de-f63dc300b25f'
$approvedFeatureRunId = [guid]'a5638530-28e9-4fce-a44c-d5399469c03b'
$approvedFeatureManifestHash = '6ad27dded487d8991672438044c4f5c610fabc03cf04bab81ff3fdee95ae47ba'
$targetDateText = $TargetDate.ToString('yyyy-MM-dd')
if ($targetDateText -ne $approvedTargetDate -or
    $ExpectedFeatureManifestHash -ne $approvedFeatureManifestHash) {
    throw 'The target date or feature manifest does not match the reviewed Step 58 checkpoint.'
}

New-Item -ItemType Directory -Path $OutputDirectory -Force | Out-Null
$resultPath = Join-Path $OutputDirectory "daily-feature-automation-$targetDateText.json"
$logPath = Join-Path $OutputDirectory "daily-feature-automation-$targetDateText.log"
$transcriptStarted = $false

try {
    Start-Transcript -Path $logPath -Force | Out-Null
    $transcriptStarted = $true

    $health = Invoke-RestMethod "$BaseUrl/actuator/health" -TimeoutSec 60
    if ($health.status -ne 'UP') {
        throw "MarketBrain health is $($health.status), not UP."
    }

    Write-Host 'Waiting for the durable automatic feature-snapshot checkpoint and Telegram conclusion...'
    Write-Host 'The existing reviewed September 8 snapshot will be reused; signals and orders remain disabled.'
    $status = $null
    for ($attempt = 1; $attempt -le 180; $attempt++) {
        $status = Invoke-RestMethod `
            "$BaseUrl/api/v1/features/daily-automation/status?targetDate=$targetDateText" `
            -TimeoutSec 60
        if (-not $status.automationEnabled) {
            throw 'Daily feature snapshot automation is not enabled in the running container.'
        }
        if ([string]$status.activationDate -ne $approvedTargetDate) {
            throw 'The running activation date does not match the reviewed Step 59 boundary.'
        }
        $terminal = $status.status -in @('COMPLETED', 'REVIEW_REQUIRED', 'FAILED')
        $noticeFinished = $status.notificationStatus -in @('SENT', 'SUPPRESSED')
        if ($terminal -and $noticeFinished) {
            break
        }
        if ($attempt -eq 1 -or $attempt % 3 -eq 0) {
            Write-Host "Status=$($status.status); attempts=$($status.attempts); notification=$($status.notificationStatus)"
        }
        Start-Sleep -Seconds 10
    }

    $status | ConvertTo-Json -Depth 8 |
        Set-Content -LiteralPath $resultPath -Encoding utf8
    $status | Format-List

    if ($status.status -ne 'COMPLETED' -or
        [guid]$status.dailyRunId -ne $approvedDailyRunId -or
        [guid]$status.featureSnapshotRunId -ne $approvedFeatureRunId -or
        $status.featureManifestHash -ne $approvedFeatureManifestHash -or
        $status.eligibleCount -ne 485 -or
        $status.withheldCount -ne 15 -or
        $null -ne $status.lastErrorCode -or
        $status.notificationStatus -ne 'SENT') {
        throw 'The automatic daily feature snapshot did not reach every reviewed Step 59 checkpoint.'
    }

    Write-Host ''
    Write-Host 'STEP 59 COMPLETE: automatic quality-gated daily feature snapshots are enabled and checkpointed.'
    Write-Host 'The reviewed snapshot was reused idempotently and one Telegram feature conclusion was sent.'
    Write-Host 'No signal, order, broker action, or Ollama training was created.'
    Write-Host "Result: $resultPath"
    Write-Host "Log: $logPath"
}
finally {
    if ($transcriptStarted) {
        Stop-Transcript | Out-Null
    }
}
