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
$approvedFeatureManifestHash = '6ad27dded487d8991672438044c4f5c610fabc03cf04bab81ff3fdee95ae47ba'
$approvedFeatureRunId = [guid]'a5638530-28e9-4fce-a44c-d5399469c03b'
$targetDateText = $TargetDate.ToString('yyyy-MM-dd')
if ($targetDateText -ne $approvedTargetDate -or
    $ExpectedFeatureManifestHash -ne $approvedFeatureManifestHash) {
    throw 'The target date or feature manifest does not match the reviewed Step 57 checkpoint.'
}

New-Item -ItemType Directory -Path $OutputDirectory -Force | Out-Null
$resultPath = Join-Path $OutputDirectory "daily-feature-automation-preview-$targetDateText.json"
$logPath = Join-Path $OutputDirectory "daily-feature-automation-preview-$targetDateText.log"
$transcriptStarted = $false

try {
    Start-Transcript -Path $logPath -Force | Out-Null
    $transcriptStarted = $true

    $health = Invoke-RestMethod "$BaseUrl/actuator/health" -TimeoutSec 60
    if ($health.status -ne 'UP') {
        throw "MarketBrain health is $($health.status), not UP."
    }

    Write-Host 'Previewing the governed handoff from completed daily collection to feature persistence...'
    Write-Host 'This request is database-only and cannot persist features, create signals, or change the scheduler.'
    $preview = Invoke-RestMethod `
        "$BaseUrl/api/v1/features/daily-automation-preview?targetDate=$targetDateText" `
        -TimeoutSec 1800
    $preview | ConvertTo-Json -Depth 8 |
        Set-Content -LiteralPath $resultPath -Encoding utf8

    $preview | Format-List

    if ($preview.status -ne 'READY' -or
        ([datetime]$preview.targetDate).ToString('yyyy-MM-dd') -ne $approvedTargetDate -or
        $preview.dailyRunStatus -ne 'COMPLETED' -or
        $preview.dailyInstrumentCount -ne 500 -or
        $preview.totalChunks -ne 500 -or
        $preview.completedChunks -ne 500 -or
        $preview.failedChunks -ne 0 -or
        $preview.acceptedRows -ne 1000 -or
        $preview.rejectedRows -ne 0 -or
        $preview.targetDateCandleCount -ne 500 -or
        $preview.dailyQualityStatus -ne 'PASS' -or
        $preview.blockingInstrumentCount -ne 0 -or
        $preview.missingProviderDataInstrumentCount -ne 0 -or
        $preview.reviewInstrumentCount -ne 0 -or
        $preview.duplicateRowCount -ne 0 -or
        $preview.invalidRowCount -ne 0 -or
        $preview.unresolvedFindingCount -ne 0 -or
        $preview.truncatedFindingCount -ne 0 -or
        $preview.featureSetVersion -ne 'TECHNICAL_V1' -or
        $preview.featureManifestHash -ne $approvedFeatureManifestHash -or
        $preview.featureInstrumentCount -ne 500 -or
        $preview.eligibleCount -ne 485 -or
        $preview.insufficientHistoryCount -ne 15 -or
        $preview.staleCount -ne 0 -or
        $preview.noEligibleDataCount -ne 0 -or
        $preview.persistenceAction -ne 'ALREADY_PERSISTED' -or
        [guid]$preview.existingFeatureSnapshotRunId -ne $approvedFeatureRunId -or
        $preview.existingFeatureSnapshotStatus -ne 'COMPLETED' -or
        @($preview.failedCheckpoints).Count -ne 0 -or
        -not $preview.pointInTimeSafe -or
        $preview.databaseWritesPerformed) {
        throw 'The daily-to-feature automation preview did not reach every reviewed Step 58 checkpoint.'
    }

    Write-Host ''
    Write-Host 'STEP 58 COMPLETE: the completed daily run safely maps to the exact audited feature snapshot.'
    Write-Host 'The preview was read-only. Automatic feature persistence remains disabled.'
    Write-Host "Result: $resultPath"
    Write-Host "Log: $logPath"
}
finally {
    if ($transcriptStarted) {
        Stop-Transcript | Out-Null
    }
}
