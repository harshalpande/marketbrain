#Requires -Version 5.1
[CmdletBinding()]
param([string]$BaseUrl='http://127.0.0.1:8080',[string]$OutputDirectory='C:\MarketBrainData\Review')
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'LlmCleanupInventory.ps1')
. (Join-Path $PSScriptRoot 'NumericalHistoryEvidence.ps1')
. (Join-Path $PSScriptRoot 'DailyQualityFollowUp.ps1')
$base=Assert-LlmInventoryLoopback $BaseUrl
$job='eebff875-3621-4064-a2ea-9de0b269681e';$date='2026-10-08'
[void](New-Item -ItemType Directory -Path $OutputDirectory -Force)
$path=Join-Path (Resolve-Path -LiteralPath $OutputDirectory).Path ('daily-quality-follow-up-'+$date+'-'+[guid]::NewGuid().ToString('N')+'.json')
if($path.Length+41 -ge 260 -or (Test-Path -LiteralPath $path)){throw 'Unsafe or existing report path.'}
$timer=[Diagnostics.Stopwatch]::StartNew()
$report=[ordered]@{version='DAILY_QUALITY_FOLLOW_UP_V1';status='RUNNING';createdAtUtc=[DateTime]::UtcNow.ToString('o');updatedAtUtc=$null
    targetDate=$date;dailyRunId=$job;scriptSha256=(Get-FileHash -LiteralPath $PSCommandPath).Hash
    elapsedSeconds=0;events=@();requests=@();dailyRun=$null;quality=$null;features=$null;featureSummary=$null;officialEvidence=$null
    failureStage=$null;failureMessage=$null;errorType=$null;httpStatus=$null
    resolutionWriteRequested=$false;featurePersistenceRequested=$false;modelInvocationRequested=$false;orderActionRequested=$false
    externalReadScope='Existing Java endpoint fetches the NSE archive for the reviewed date; no Upstox spot check or imports. A concurrent data change can alter findings; response scope is rechecked.'}
function Checkpoint([int]$Percent,[string]$Message){
    $report.elapsedSeconds=$timer.Elapsed.TotalSeconds
    $report.events+=@{atUtc=[DateTime]::UtcNow.ToString('o');percent=$Percent;message=$Message}
    Save-NumericalHistoryReport $report $path -Compact
    Write-Host "[$Percent%] $Message"
    Write-Progress -Activity 'Daily quality follow up (read only)' -Status $Message -PercentComplete $Percent
}
function Read-Endpoint([string]$Endpoint,[int]$Seconds){
    $watch=[Diagnostics.Stopwatch]::StartNew();$request=[ordered]@{endpoint=$Endpoint;method='GET';timeoutSeconds=$Seconds;status='STARTED';elapsedSeconds=0}
    $report.requests+=@($request);Save-NumericalHistoryReport $report $path -Compact
    try{$value=Invoke-RestMethod -Uri ($base+$Endpoint) -Method Get -TimeoutSec $Seconds -MaximumRedirection 0 -ErrorAction Stop;$request.status='RETURNED';return $value}
    catch{$request.status='FAILED';throw}
    finally{$request.elapsedSeconds=$watch.Elapsed.TotalSeconds;Save-NumericalHistoryReport $report $path -Compact}
}
try{
    $stage='HEALTH';Checkpoint 0 'No imports, resolution writes, feature persistence, models or trades. Checking service health once.'
    $health=Read-Endpoint '/actuator/health' 15
    if($health.status -cne 'UP'){throw 'Service is not UP.'}
    $stage='RUN_SCOPE';Checkpoint 10 'Checking the exact saved daily run before database review.'
    $report.dailyRun=Read-Endpoint ("/api/v1/market-data/daily-enrichment/runs/status?runId=$job") 30
    Assert-DailyReviewScope $report.dailyRun
    $stage='QUALITY';Checkpoint 20 'Auditing only the reviewed 20-calendar-day run; provider spot checks disabled (180-second HTTP limit).'
    $report.quality=Read-Endpoint ("/api/v1/market-data/backfills/quality?jobId=$job&providerSpotCheck=false") 180
    Assert-DailyReviewQuality $report.quality
    $stage='FEATURES';Checkpoint 40 'One all-500 feature preview, not 500 separate calls. Existing query limit 600 seconds; HTTP limit 660 seconds. No automatic retry.'
    $report.features=Read-Endpoint ("/api/v1/features/universe-preview?asOf=$date") 660
    Checkpoint 70 'Feature response saved; validating all classifications and retaining withholding details.'
    $report.featureSummary=Get-DailyReviewFeatureSummary $report.features
    $stage='OFFICIAL_EVIDENCE';Checkpoint 80 'Reading POLICYBZR NSE archive comparison through the existing Java endpoint (180-second HTTP limit).'
    $report.officialEvidence=Read-Endpoint ("/api/v1/market-data/backfills/large-move-evidence?jobId=$job&symbol=POLICYBZR") 180
    Assert-DailyReviewOfficialEvidence $report.officialEvidence
    $report.status='CAPTURED_REVIEW_REQUIRED'
    Checkpoint 100 'Evidence captured, not approved. Share this report before any finding resolution or feature retry.'
    $report.featureSummary|Select-Object eligible,withheld,manifestMatchesOriginalAutomation|Format-List
    $report.officialEvidence.findings|Select-Object symbol,findingDate,evidenceStatus,reviewPath|Format-List
}catch{
    $report.status='FAILED_PARTIAL_REPORT';$report.failureStage=$stage;$report.errorType=$_.Exception.GetType().Name
    $report.failureMessage='Collection or validation failed; preserve embedded responses. No automatic retry or state change.'
    if($_.Exception.PSObject.Properties['Response'] -and $_.Exception.Response -and $_.Exception.Response.PSObject.Properties['StatusCode']){$report.httpStatus=[int]$_.Exception.Response.StatusCode}
    Checkpoint 100 'Stopped; partial evidence saved. Do not rerun automatically.'
    throw
}finally{Write-Progress -Activity 'Daily quality follow up (read only)' -Completed;Write-Host "Share this ONE file: $path"}
