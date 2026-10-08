#Requires -Version 5.1
[CmdletBinding()]
param(
    [string]$EvidencePath='C:\MarketBrainData\Review\policybzr-reviewed-resolution-2798223d024e493b8dc060a828532a6c.json',
    [string]$ReviewedBy,
    [switch]$Apply,
    [string]$BaseUrl='http://127.0.0.1:8080',
    [string]$OutputDirectory='C:\MarketBrainData\Review'
)
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'LlmCleanupInventory.ps1')
. (Join-Path $PSScriptRoot 'NumericalHistoryEvidence.ps1')
. (Join-Path $PSScriptRoot 'ReviewedOctoberFeatureSnapshot.ps1')
$base=Assert-LlmInventoryLoopback $BaseUrl
[void](New-Item -ItemType Directory -Path $OutputDirectory -Force)
$path=Join-Path (Resolve-Path -LiteralPath $OutputDirectory).Path ('reviewed-feature-snapshot-'+[guid]::NewGuid().ToString('N')+'.json')
if($path.Length+41 -ge 260 -or (Test-Path -LiteralPath $path)){throw 'Unsafe report path.'}
$timer=[Diagnostics.Stopwatch]::StartNew();$mutex=$null;$locked=$false;$stage='EVIDENCE'
$job='eebff875-3621-4064-a2ea-9de0b269681e'
$manifest='50e0749dfdfbc3e370f4cd5d0f23069021154bf69baafcc815cffcb509cbbb62'
$report=[ordered]@{version='REVIEWED_OCTOBER_FEATURE_SNAPSHOT_V1';status='RUNNING';createdAtUtc=[DateTime]::UtcNow.ToString('o');updatedAtUtc=$null;elapsedSeconds=0
    applyRequested=[bool]$Apply;reviewedBy=$ReviewedBy;writeState='NOT_ATTEMPTED';events=@();requests=@();evidenceSha256=$null;evidence=$null
    currentResolution=$null;automation=$null;preview=$null;postResponse=$null;persistedQuality=$null;runId=$null;failureStage=$null
    failureMessage=$null;failureType=$null;recoveryGuidance=$null;priceChangeRequested=$false;resolutionChangeRequested=$false;exclusionRequested=$false;schedulerResetRequested=$false;modelOrTradeRequested=$false
    reviewerCaveat='Prior resolution reviewer contains a confirmation phrase. Retained unchanged; new reviewer is self-declared, not authenticated identity.'}
function Save-Step([int]$Percent,[string]$Message){
    $report.elapsedSeconds=$timer.Elapsed.TotalSeconds;$report.events+=@{percent=$Percent;atUtc=[DateTime]::UtcNow.ToString('o');message=$Message}
    Save-NumericalHistoryReport $report $path -Compact
    Write-Host "[$Percent%] $Message";Write-Progress -Activity 'Reviewed October feature snapshot' -Status $Message -PercentComplete $Percent
}
function Request([string]$Route,[int]$Seconds,[switch]$Write){
    $record=[ordered]@{route=$Route;method=if($Write){'Post'}else{'Get'};timeoutSeconds=$Seconds;status='STARTED';elapsedSeconds=0}
    $report.requests+=@($record);Save-NumericalHistoryReport $report $path -Compact;$watch=[Diagnostics.Stopwatch]::StartNew()
    try{$value=Invoke-RestMethod -Uri ($base+$Route) -Method $record.method -TimeoutSec $Seconds -MaximumRedirection 0 -ErrorAction Stop;$record.status='RETURNED';return $value}
    catch{$record.status='FAILED';throw}
    finally{$record.elapsedSeconds=$watch.Elapsed.TotalSeconds;Save-NumericalHistoryReport $report $path -Compact}
}
function Fresh-Gates {
    $report.automation=Request '/api/v1/features/daily-automation/status?targetDate=2026-10-08' 30
    if([string]$report.automation.targetDate -cne '2026-10-08' -or [string]$report.automation.dailyRunId -cne $job -or
        $report.automation.status -notin @('REVIEW_REQUIRED','COMPLETED')){throw 'Automation is active or has unexpected scope. Wait and review; do not race it.'}
    $report.currentResolution=@(Request ("/api/v1/market-data/backfills/quality-resolutions?jobId=$job") 30)
    Assert-OctoberResolution $report.currentResolution
}
try{
    Save-Step 0 'Validating accepted evidence; no provider/model calls. Preview is the default.'
    # Same mutex as the resolution tool prevents competing review writes within this Windows session.
    $mutex=[Threading.Mutex]::new($false,'Local\MarketBrainPolicyBzrReview20260924')
    try{$locked=$mutex.WaitOne(0)}catch [Threading.AbandonedMutexException]{$locked=$true}
    if(-not $locked){throw 'A related review tool is already running in this Windows session.'}
    if(-not (Test-Path -LiteralPath $EvidencePath -PathType Leaf) -or (Get-Item -LiteralPath $EvidencePath).Length -gt 8MB){throw 'Accepted evidence is missing or too large.'}
    $report.evidenceSha256=(Get-FileHash -LiteralPath $EvidencePath).Hash
    if($report.evidenceSha256 -cne '91F75E59F91A17696687801CECBCA281EDBA6BD614173E8E982C645B0C6FC69F'){throw 'Evidence hash changed; share it for review, do not substitute a different run.'}
    $report.evidence=Get-Content -LiteralPath $EvidencePath -Raw|ConvertFrom-Json
    Assert-OctoberResolutionEvidence $report.evidence
    if($Apply){[void](New-PolicyBzrResolutionBody $ReviewedBy);$ReviewedBy=$ReviewedBy.Trim();$report.reviewedBy=$ReviewedBy}
    $stage='PREFLIGHT';Save-Step 10 'Checking health and unchanged resolution/automation state.'
    if((Request '/actuator/health' 15).status -cne 'UP'){throw 'Service is not UP.'}
    Fresh-Gates
    if($Apply){
        Write-Host 'This may persist 500 reviewed feature items: 487 vectors and 13 withheld classifications. No orders, training or scheduler reset.'
        Write-Host 'Previous reviewer-label caveat remains. Keep other data collection/repair/review jobs idle; this is not a distributed lock.'
        if((Read-Host 'Type PERSIST FEATURES 2026-10-08 to confirm this scope and no concurrent jobs') -cne 'PERSIST FEATURES 2026-10-08'){$report.status='CANCELLED_NO_WRITE';Save-Step 100 'Cancelled; no write attempted.';return}
    }
    $stage='FRESH_PREVIEW';Save-Step 25 'Checking fresh database quality, coverage and manifest (660-second request limit).'
    $report.preview=Request '/api/v1/features/daily-automation-preview?targetDate=2026-10-08' 660
    $report.runId=Assert-OctoberSnapshotPreview $report.preview
    if($null -eq $report.runId){
        if(-not $Apply){$report.status='PREVIEW_READY_NO_WRITE';Save-Step 100 'Ready but not persisted. Explicit Apply and a real reviewer name are required.';return}
        Fresh-Gates
        if($report.automation.status -cne 'REVIEW_REQUIRED' -or $null -ne $report.automation.featureSnapshotRunId){throw 'Automation changed before persistence.'}
        $stage='SNAPSHOT_POST';$report.writeState='UNKNOWN_PENDING_RECONCILIATION'
        Save-Step 55 'Intent saved. Sending at most one snapshot POST (900-second limit); no automatic retries.'
        $route='/api/v1/features/snapshots?asOf=2026-10-08&expectedManifestHash='+$manifest+'&reviewedBy='+[uri]::EscapeDataString($ReviewedBy)
        $report.postResponse=Request $route 900 -Write
        Assert-OctoberSnapshot $report.postResponse -Reviewer $ReviewedBy
        $report.runId=[string]$report.postResponse.runId;$report.writeState='POST_ACKNOWLEDGED_NOT_YET_VERIFIED'
    }
    $stage='PERSISTED_QUALITY';Save-Step 85 'Verifying stored item counts, withheld classifications and recomputed manifest (180-second limit).'
    $report.persistedQuality=Request ("/api/v1/features/snapshots/quality?runId=$($report.runId)&expectedManifestHash=$manifest") 180
    Assert-OctoberSnapshot $report.persistedQuality -RunId $report.runId -Quality
    $report.writeState='SNAPSHOT_VERIFIED';$report.status='FEATURE_SNAPSHOT_VERIFIED_RELEASE_BLOCKED'
    Save-Step 100 'Snapshot verified. No scheduler reset, model fitting or trading release. Share this report.'
}catch{
    $report.status='STOPPED_REVIEW_REQUIRED';$report.failureStage=$stage
    $report.failureMessage=$_.Exception.Message;$report.failureType=$_.Exception.GetType().FullName
    $report.recoveryGuidance='Inspect stage, requests and writeState. An uncertain POST may have committed; never blindly retry Apply. Run without Apply to reconcile after the server is idle.'
    Save-Step 100 'Stopped; partial evidence retained. No automatic retry, rollback or cleanup.'
    throw
}finally{
    if($locked){$mutex.ReleaseMutex()};if($null -ne $mutex){$mutex.Dispose()}
    Write-Progress -Activity 'Reviewed October feature snapshot' -Completed;Write-Host "Share this ONE file: $path"
}
