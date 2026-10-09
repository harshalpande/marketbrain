#Requires -Version 5.1
[CmdletBinding()]
param(
    [string]$EvidencePath='C:\MarketBrainData\Review\reviewed-feature-snapshot-7b3af00824bc43e6b1b2e00cc84c0529.json',
    [string]$ReviewedBy,
    [switch]$Apply,
    [string]$BaseUrl='http://127.0.0.1:8080',
    [string]$OutputDirectory='C:\MarketBrainData\Review'
)
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'LlmCleanupInventory.ps1')
. (Join-Path $PSScriptRoot 'NumericalHistoryEvidence.ps1')
. (Join-Path $PSScriptRoot 'ReviewedFeatureReconciliation.ps1')
$base=Assert-LlmInventoryLoopback $BaseUrl
[void](New-Item -ItemType Directory -Path $OutputDirectory -Force)
$path=Join-Path (Resolve-Path -LiteralPath $OutputDirectory).Path ('feature-reconciliation-'+[guid]::NewGuid().ToString('N')+'.json')
if($path.Length+41 -ge 260 -or (Test-Path -LiteralPath $path)){throw 'Unsafe report path.'}
$timer=[Diagnostics.Stopwatch]::StartNew();$stage='EVIDENCE';$mutex=$null;$locked=$false
$route='/api/v1/features/daily-automation/reviewed-reconciliation'
$report=[ordered]@{version='REVIEWED_FEATURE_RECONCILIATION_REPORT_V1';status='RUNNING';createdAtUtc=[DateTime]::UtcNow.ToString('o');updatedAtUtc=$null;elapsedSeconds=0
    applyRequested=[bool]$Apply;writeState='NOT_ATTEMPTED';evidenceSha256=$null;evidence=$null;requestBody=$null
    preview=$null;postResponse=$null;readback=$null;automation=$null;requests=@();events=@();failureStage=$null;failureMessage=$null;recoveryGuidance=$null
    snapshotPersistenceRequested=$false;priceChangeRequested=$false;resolutionChangeRequested=$false;modelOrTradeRequested=$false}
function Save-Step([int]$Percent,[string]$Message){
    $report.elapsedSeconds=$timer.Elapsed.TotalSeconds;$report.events+=@{percent=$Percent;atUtc=[DateTime]::UtcNow.ToString('o');message=$Message}
    Save-NumericalHistoryReport $report $path -Compact;Write-Host "[$Percent%] $Message"
    Write-Progress -Activity 'Reviewed feature checkpoint reconciliation' -Status $Message -PercentComplete $Percent
}
function Request([string]$Route,[int]$Seconds,[switch]$Write){
    $entry=[ordered]@{route=$Route;method=if($Write){'Post'}else{'Get'};timeoutSeconds=$Seconds;status='STARTED';elapsedSeconds=0;responseError=$null}
    $report.requests+=@($entry);Save-NumericalHistoryReport $report $path -Compact;$watch=[Diagnostics.Stopwatch]::StartNew()
    try{
        $httpArgs=@{Uri=($base+$Route);Method=$entry.method;TimeoutSec=$Seconds;MaximumRedirection=0;ErrorAction='Stop'}
        if($Write){$httpArgs.ContentType='application/json';$httpArgs.Body=($report.requestBody|ConvertTo-Json -Compress)}
        $value=Invoke-RestMethod @httpArgs;$entry.status='RETURNED';return $value
    }catch{
        $entry.status='FAILED'
        if($null -ne $_.ErrorDetails){$details=[string]$_.ErrorDetails.Message;$entry.responseError=$details.Substring(0,[Math]::Min(4000,$details.Length))}
        throw
    }
    finally{$entry.elapsedSeconds=$watch.Elapsed.TotalSeconds;Save-NumericalHistoryReport $report $path -Compact}
}
try{
    Save-Step 0 'Verifying the accepted snapshot report. No feature regeneration or model/provider call.'
    $mutex=[Threading.Mutex]::new($false,'Local\MarketBrainPolicyBzrReview20260924')
    try{$locked=$mutex.WaitOne(0)}catch [Threading.AbandonedMutexException]{$locked=$true}
    if(-not $locked){throw 'Another related review tool is running.'}
    if(-not (Test-Path -LiteralPath $EvidencePath -PathType Leaf) -or (Get-Item -LiteralPath $EvidencePath).Length -gt 8MB){throw 'Accepted snapshot report missing or too large.'}
    $report.evidenceSha256=(Get-FileHash -LiteralPath $EvidencePath).Hash
    if($report.evidenceSha256 -cne '128C921E4C21734E9CC0801B39735ECDF9152A43C9906FB3695FEE44ACB62324'){throw 'Source evidence hash changed. Share it for review; do not regenerate it.'}
    $report.evidence=Get-Content -LiteralPath $EvidencePath -Raw|ConvertFrom-Json
    Assert-ReconciliationEvidence $report.evidence
    if($Apply){
        [void](New-PolicyBzrResolutionBody $ReviewedBy)
        if($ReviewedBy.Trim() -match '^RECONCILE(\s|$)'){throw 'Enter your name, not the confirmation phrase.'}
        $report.requestBody=@{evidenceSha256=$report.evidenceSha256;reviewedBy=$ReviewedBy.Trim()}
    }
    $stage='HEALTH';Save-Step 10 'Checking service health; deployment and migration must already be complete.'
    if((Request '/actuator/health' 15).status -cne 'UP'){throw 'Service is not UP.'}
    $stage='PREVIEW';Save-Step 25 'Server checks persisted snapshot and current daily quality (240-second HTTP limit).'
    $report.preview=Request $route 240;Assert-ReconciliationResponse $report.preview
    if($report.preview.status -ceq 'READY_TO_RECONCILE'){
        if(-not $Apply){$report.status='PREVIEW_READY_NO_WRITE';Save-Step 100 'Preview passed. No write requested.';return}
        Write-Host 'This links the existing snapshot and appends a reconciliation audit. The old warning is retained.'
        Write-Host 'The normal notifier may send a separate feature-completion message after commit. No trading action. Other data/review jobs must be idle.'
        if((Read-Host 'Type RECONCILE FEATURES 2026-10-08 to confirm') -cne 'RECONCILE FEATURES 2026-10-08'){$report.status='CANCELLED_NO_WRITE';Save-Step 100 'Cancelled; no write attempted.';return}
        $stage='APPLY';$report.writeState='UNKNOWN_PENDING_RECONCILIATION'
        Save-Step 55 'Intent saved. One POST only; server revalidates and commits audit plus checkpoint atomically.'
        $report.postResponse=Request $route 240 -Write;Assert-ReconciliationResponse $report.postResponse -Write
        if($report.postResponse.reviewedBy -cne $report.requestBody.reviewedBy){throw 'Applied reviewer mismatch.'}
        $report.writeState='ACKNOWLEDGED_NOT_YET_VERIFIED'
    }
    $stage='READBACK';Save-Step 80 'Read-only reconciliation check. No write retry or notification resend.'
    $report.readback=Request $route 240;Assert-ReconciliationResponse $report.readback
    if($report.readback.status -cne 'ALREADY_RECONCILED'){throw 'Reconciliation not confirmed.'}
    if($null -ne $report.postResponse -and [string]$report.readback.reconciliationId -cne [string]$report.postResponse.reconciliationId){throw 'Audit readback identity differs.'}
    $report.automation=Request '/api/v1/features/daily-automation/status?targetDate=2026-10-08' 30
    if($report.automation.status -cne 'COMPLETED' -or [string]$report.automation.targetDate -cne '2026-10-08' -or
        [string]$report.automation.dailyRunId -cne [string]$report.readback.dailyRunId -or
        [string]$report.automation.featureSnapshotRunId -cne [string]$report.readback.featureSnapshotRunId -or
        $report.automation.featureManifestHash -cne $report.readback.featureManifestHash -or $null -ne $report.automation.lastErrorCode -or
        $report.automation.eligibleCount -ne 487 -or $report.automation.withheldCount -ne 13 -or $report.automation.attempts -ne 1){throw 'Automation readback differs.'}
    $report.writeState='RECONCILIATION_VERIFIED';$report.status='AUTOMATION_RECONCILED_RELEASE_BLOCKED'
    Save-Step 100 'Checkpoint verified. Notification status captured, not assumed delivered. No training/trading release.'
}catch{
    $report.status='STOPPED_REVIEW_REQUIRED';$report.failureStage=$stage;$report.failureMessage=$_.Exception.Message
    $report.recoveryGuidance='A failed/timeout POST may have committed. Do not repeat Apply. After server is idle, rerun without Apply for read-only reconciliation and share the report.'
    Save-Step 100 'Stopped; partial evidence preserved. No automatic retry or rollback.';throw
}finally{
    if($locked){$mutex.ReleaseMutex()};if($null -ne $mutex){$mutex.Dispose()}
    Write-Progress -Activity 'Reviewed feature checkpoint reconciliation' -Completed;Write-Host "Share this ONE file: $path"
}
