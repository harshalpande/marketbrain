#Requires -Version 5.1
[CmdletBinding()]
param(
    [string]$EvidencePath='C:\MarketBrainData\Review\daily-quality-follow-up-2026-10-08-fb41949416494625817181ede0b86c55.json',
    [Parameter(Mandatory)][string]$ReviewedBy,
    [switch]$Apply,
    [string]$BaseUrl='http://127.0.0.1:8080',
    [string]$OutputDirectory='C:\MarketBrainData\Review'
)
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'LlmCleanupInventory.ps1')
. (Join-Path $PSScriptRoot 'NumericalHistoryEvidence.ps1')
. (Join-Path $PSScriptRoot 'ReviewedPolicyBzrResolution.ps1')
$base=Assert-LlmInventoryLoopback $BaseUrl
$body=New-PolicyBzrResolutionBody $ReviewedBy
$job=$body.jobId;$endpoint='/api/v1/market-data/backfills/quality-resolutions'
[void](New-Item -ItemType Directory -Path $OutputDirectory -Force)
$path=Join-Path (Resolve-Path -LiteralPath $OutputDirectory).Path ('policybzr-reviewed-resolution-'+[guid]::NewGuid().ToString('N')+'.json')
if($path.Length+41 -ge 260 -or (Test-Path -LiteralPath $path)){throw 'Unsafe report path.'}
$timer=[Diagnostics.Stopwatch]::StartNew();$mutex=$null;$locked=$false
$report=[ordered]@{version='POLICYBZR_REVIEWED_RESOLUTION_V1';status='RUNNING';createdAtUtc=[DateTime]::UtcNow.ToString('o');updatedAtUtc=$null;elapsedSeconds=0
    applyRequested=[bool]$Apply;writeState='NOT_ATTEMPTED';events=@();requests=@();requestBody=$body;evidenceSha256=$null;evidence=$null
    dailyRun=$null;automation=$null;qualityBefore=$null;currentBefore=$null;postResponse=$null;currentAfter=$null;featurePreview=$null
    failureStage=$null;failureMessage=$null;featurePersistenceRequested=$false;priceChangeRequested=$false;exclusionRequested=$false;modelOrTradeRequested=$false}
function Save-Step([int]$Percent,[string]$Message){
    $report.elapsedSeconds=$timer.Elapsed.TotalSeconds;$report.events+=@{percent=$Percent;atUtc=[DateTime]::UtcNow.ToString('o');message=$Message}
    Save-NumericalHistoryReport $report $path -Compact
    Write-Host "[$Percent%] $Message";Write-Progress -Activity 'Reviewed POLICYBZR resolution' -Status $Message -PercentComplete $Percent
}
function Request([string]$Route,[int]$Seconds,[switch]$Write){
    $method=if($Write){'Post'}else{'Get'}
    $record=[ordered]@{route=$Route;method=$method;timeoutSeconds=$Seconds;status='STARTED';elapsedSeconds=0}
    $report.requests+=@($record);Save-NumericalHistoryReport $report $path -Compact;$watch=[Diagnostics.Stopwatch]::StartNew()
    try{
        $requestArgs=@{Uri=($base+$Route);Method=$method;TimeoutSec=$Seconds;MaximumRedirection=0;ErrorAction='Stop'}
        if($Write){$requestArgs.ContentType='application/json';$requestArgs.Body=($body|ConvertTo-Json -Compress)}
        $value=Invoke-RestMethod @requestArgs;$record.status='RETURNED';return $value
    }catch{$record.status='FAILED';throw}
    finally{$record.elapsedSeconds=$watch.Elapsed.TotalSeconds;Save-NumericalHistoryReport $report $path -Compact}
}
try{
    $stage='EVIDENCE';Save-Step 0 'Validating the exact accepted evidence. Default is preview; Apply requires explicit confirmation.'
    $mutex=[Threading.Mutex]::new($false,'Local\MarketBrainPolicyBzrReview20260924')
    try{$locked=$mutex.WaitOne(0)}catch [Threading.AbandonedMutexException]{$locked=$true}
    if(-not $locked){throw 'Another copy is running in this Windows session.'}
    if(-not(Test-Path -LiteralPath $EvidencePath -PathType Leaf) -or (Get-Item -LiteralPath $EvidencePath).Length -gt 5MB){throw 'Accepted evidence file missing or too large.'}
    $report.evidenceSha256=(Get-FileHash -LiteralPath $EvidencePath).Hash
    if($report.evidenceSha256 -cne '190CE4143E39B84AADC14B34570E2278D7AB60F78448BEB2D81A0FB9910B4349'){throw 'Evidence hash differs. Do not substitute or rerun diagnostics; share the file for review.'}
    $report.evidence=Get-Content -LiteralPath $EvidencePath -Raw|ConvertFrom-Json
    Assert-PolicyBzrEvidence $report.evidence
    $stage='PREFLIGHT';Save-Step 10 'Checking health, exact daily run and current resolution. No provider/model call.'
    if((Request '/actuator/health' 15).status -cne 'UP'){throw 'Service is not UP.'}
    $report.dailyRun=Request ("/api/v1/market-data/daily-enrichment/runs/status?runId=$job") 30
    Assert-DailyReviewScope $report.dailyRun
    if($report.dailyRun.manifestHash -cne $report.evidence.dailyRun.manifestHash){throw 'Daily manifest changed.'}
    $report.currentBefore=@(Request ($endpoint+"?jobId=$job") 30)
    $existing=Get-PolicyBzrCurrentResolution $report.currentBefore $body
    if($null -eq $existing){
        $report.automation=Request '/api/v1/features/daily-automation/status?targetDate=2026-10-08' 30
        if($report.automation.status -cne 'REVIEW_REQUIRED' -or [string]$report.automation.dailyRunId -cne $job -or
            [string]$report.automation.targetDate -cne '2026-10-08' -or $null -ne $report.automation.featureSnapshotRunId){throw 'Automation state changed; do not resolve during active processing.'}
        $stage='QUALITY';Save-Step 30 'Rechecking stored prices and the single open finding; provider spot checks disabled (180-second limit).'
        $report.qualityBefore=Request ("/api/v1/market-data/backfills/quality?jobId=$job&providerSpotCheck=false") 180
        Assert-PolicyBzrOpenFinding $report.qualityBefore
        if(-not $Apply){$report.status='PREVIEW_READY_NO_WRITE';Save-Step 100 'Preview passed. Apply would append one review record only.';return}
        Write-Host 'This appends one VERIFIED_EXCHANGE_MOVE audit event. It preserves candles and creates no exclusion or feature snapshot.'
        Write-Host 'The legacy finding allowsTraining flag will become true for this finding only; broader training/source gates remain. Run no other review or data repair concurrently.'
        if((Read-Host 'Type RESOLVE POLICYBZR 2026-09-24 to confirm this scope and no concurrent reviewer') -cne 'RESOLVE POLICYBZR 2026-09-24'){$report.status='CANCELLED_NO_WRITE';Save-Step 100 'Cancelled; no write attempted.';return}
        # Recheck after user confirmation. The existing API is not a server-side compare-and-set.
        $report.currentBefore=@(Request ($endpoint+"?jobId=$job") 30)
        $existing=Get-PolicyBzrCurrentResolution $report.currentBefore $body
        if($null -eq $existing){
            $stage='RESOLUTION_POST';$report.writeState='UNKNOWN_PENDING_RECONCILIATION'
            Save-Step 60 'Write intent saved. Sending exactly one POST; never automatically retry an uncertain response.'
            $report.postResponse=Request $endpoint 30 -Write
            if($null -eq (Get-PolicyBzrCurrentResolution @($report.postResponse) $body)){throw 'POST response does not identify the reviewed resolution.'}
        }
    }
    $stage='RECONCILIATION';Save-Step 75 'Reading current resolution to confirm persistence; an existing exact match is not written again.'
    $report.currentAfter=@(Request ($endpoint+"?jobId=$job") 30)
    $confirmed=Get-PolicyBzrCurrentResolution $report.currentAfter $body
    if($null -eq $confirmed){throw 'Resolution not confirmed. Do not retry POST; review saved evidence.'}
    $report.writeState='RESOLUTION_VERIFIED'
    $stage='FEATURE_PREVIEW';Save-Step 85 'Resolution verified. Checking feature readiness only (660-second limit); no feature persistence or scheduler reset.'
    $report.featurePreview=Request '/api/v1/features/daily-automation-preview?targetDate=2026-10-08' 660
    $ready=Test-PolicyBzrFeatureReadiness $report.featurePreview
    $report.status=if($ready){'RESOLUTION_VERIFIED_FEATURE_READY_NOT_PERSISTED'}else{'RESOLUTION_VERIFIED_FEATURE_REVIEW_REQUIRED'}
    Save-Step 100 'Review and readiness captured. Share one report; no further write was performed.'
}catch{
    $report.status='STOPPED_REVIEW_REQUIRED';$report.failureStage=$stage
    $report.failureMessage='Stopped; inspect captured stage and writeState. If writeState is UNKNOWN_PENDING_RECONCILIATION, do not retry with Apply. Run without Apply to reconcile first.'
    Save-Step 100 'Stopped; partial report preserved. No automatic retry or rollback.'
    throw
}finally{
    if($locked){$mutex.ReleaseMutex()};if($null -ne $mutex){$mutex.Dispose()}
    Write-Progress -Activity 'Reviewed POLICYBZR resolution' -Completed;Write-Host "Share this ONE file: $path"
}
