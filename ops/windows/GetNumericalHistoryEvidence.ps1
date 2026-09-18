#Requires -Version 5.1
[CmdletBinding()]
param(
    [Parameter(Mandatory)][guid]$DatasetRunId,
    [ValidateRange(252,730)][int]$LookbackDays=730,
    [string]$BaseUrl='http://127.0.0.1:8080',
    [string]$OutputDirectory='C:\MarketBrainData\Review'
)
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'LlmCleanupInventory.ps1')
. (Join-Path $PSScriptRoot 'NumericalHistoryEvidence.ps1')
$base=Assert-LlmInventoryLoopback $BaseUrl
if($DatasetRunId -eq [guid]::Empty){throw 'Explicit dataset ID required.'}
if(-not(Test-Path -LiteralPath $OutputDirectory)){[void](New-Item -ItemType Directory -Path $OutputDirectory)}
$path=Join-Path (Resolve-Path -LiteralPath $OutputDirectory).Path ('numerical-history-'+(Get-Date -Format 'yyyyMMdd-HHmmss')+'-'+[guid]::NewGuid().ToString('N').Substring(0,12)+'.json')
if(Test-Path -LiteralPath $path){throw 'Unique report path exists.'}
$timer=[Diagnostics.Stopwatch]::StartNew()
$report=[pscustomobject]@{
    version='NUMERICAL_HISTORY_EVIDENCE_V1';status='RUNNING';datasetRunId=$DatasetRunId.ToString();lookbackDays=$LookbackDays
    createdAtUtc=[DateTime]::UtcNow.ToString('o');updatedAtUtc=$null;elapsedSeconds=0;datasetManifestHash=$null;asOf=$null;windowFrom=$null
    scriptSha256=(Get-FileHash -LiteralPath $PSCommandPath).Hash;validatorSha256=(Get-FileHash -LiteralPath (Join-Path $PSScriptRoot 'NumericalHistoryEvidence.ps1')).Hash
    instrumentCount=0;completedInstrumentCount=0;partial=$false;contract=$null;instruments=[Collections.Generic.List[object]]::new()
    pages=[Collections.Generic.List[object]]::new();events=[Collections.Generic.List[object]]::new();summary=$null;errorType=$null;failureStage=$null;httpStatus=$null
    safety='GET only; no LLM/model/provider calls, training, writes, backfill or orders. No retries. Server JDBC timeouts 5/15 seconds and read-only transaction 30 seconds; client timeout 60 seconds is not cancellation proof.'
    limitations=$null
}
function Save-HistoryProgress([int]$Percent,[string]$Message){
    $report.elapsedSeconds=[math]::Round($timer.Elapsed.TotalSeconds,2)
    $report.events.Add([pscustomobject]@{atUtc=[DateTime]::UtcNow.ToString('o');percent=$Percent;message=$Message})
    Save-NumericalHistoryReport $report $path
    Write-Host "[$Percent%] $Message"
    Write-Progress -Id 100 -Activity 'Read-only numerical history coverage' -Status $Message -PercentComplete $Percent
}
try {
    $stage='HEALTH'
    Save-HistoryProgress 0 'Checking service; querying only the existing run and bounded historical window.'
    Write-Host "Single report: $path"
    $health=Invoke-RestMethod -Uri ($base+'/actuator/health') -Method Get -TimeoutSec 10 -MaximumRedirection 0 -ErrorAction Stop
    if($health.status -ne 'UP'){throw 'Service not UP.'}
    $seen=[Collections.Generic.HashSet[string]]::new();$offset=0
    for($pageNumber=1;$pageNumber -le 10;$pageNumber++) {
        $stage="HISTORY_PAGE_OFFSET_$offset"
        $percent=if($report.instrumentCount){[int](90*$offset/$report.instrumentCount)}else{5}
        Save-HistoryProgress $percent "Reading page $pageNumber, offset $offset; up to 50 instruments."
        $pageTimer=[Diagnostics.Stopwatch]::StartNew()
        $page=Invoke-RestMethod -Uri ($base+'/api/v1/training/numerical-history-coverage?datasetRunId='+$DatasetRunId.ToString()+"&offset=$offset&limit=50&lookbackDays=$LookbackDays") -Method Get -TimeoutSec 60 -MaximumRedirection 0 -ErrorAction Stop
        Assert-NumericalHistoryPage $page $DatasetRunId $offset $LookbackDays $report.datasetManifestHash $report.instrumentCount
        if($report.contract -and (($report.contract | ConvertTo-Json -Depth 6 -Compress) -ne ($page.contract | ConvertTo-Json -Depth 6 -Compress))){throw 'Contract changed between pages.'}
        if($pageNumber -gt 1 -and ($report.asOf -ne $page.asOf -or $report.windowFrom -ne $page.windowFrom)){throw 'Window changed between pages.'}
        $report.datasetManifestHash=$page.datasetManifestHash;$report.instrumentCount=$page.instrumentCount
        $report.asOf=$page.asOf;$report.windowFrom=$page.windowFrom;$report.contract=$page.contract;$report.limitations=$page.limitations
        $pageIds=[Collections.Generic.HashSet[string]]::new()
        foreach($item in $page.instruments){
            if($seen.Contains([string]$item.instrumentId) -or -not $pageIds.Add([string]$item.instrumentId)){throw 'Duplicate instrument within/across pages.'}
        }
        foreach($item in $page.instruments){[void]$seen.Add([string]$item.instrumentId);$report.instruments.Add($item)}
        $report.completedInstrumentCount=$report.instruments.Count;$report.partial=$report.partial -or $page.partial
        $report.pages.Add([pscustomobject]@{offset=$offset;count=@($page.instruments).Count;elapsedSeconds=[math]::Round($pageTimer.Elapsed.TotalSeconds,3);partial=$page.partial})
        Save-HistoryProgress ([int](90*$report.completedInstrumentCount/$report.instrumentCount)) "Captured $($report.completedInstrumentCount)/$($report.instrumentCount) instruments."
        if($null -eq $page.nextOffset){break};$offset=[int]$page.nextOffset
    }
    if($report.completedInstrumentCount -ne $report.instrumentCount){throw 'Page budget exhausted before completion.'}
    $all=$report.instruments.ToArray()
    $report.summary=[pscustomobject]@{
        persistedInsufficientHistoryCount=@($all | Where-Object persistedClassification -eq 'INSUFFICIENT_HISTORY').Count
        cappedInstrumentCount=@($all | Where-Object truncated).Count
        uncappedWithAtLeast252NonexcludedDates=@($all | Where-Object {-not $_.truncated -and $_.nonexcludedDates -ge 252}).Count
        uncappedWithNoObservedDates=@($all | Where-Object {-not $_.truncated -and $_.observedDates -eq 0}).Count
        instrumentsWithReceivedAfterCutoffRows=@($all | Where-Object {$_.receivedAfterDecisionCutoffRows -gt 0}).Count
        trainingAuthorized=$false
    }
    $stage='FINAL_CHECKPOINT'
    $report.status=if($report.partial){'PARTIAL_WINDOW_COVERAGE_REVIEW_REQUIRED'}else{'WINDOW_COVERAGE_REVIEW_REQUIRED'}
    Save-HistoryProgress 100 'Collection complete; draft contract and historical availability still require review.'
    $report.summary | Format-List
} catch {
    $report.status='FAILED_PARTIAL_REPORT';$report.partial=$true;$report.errorType=$_.Exception.GetType().Name
    $report.failureStage=$stage
    if($_.Exception.PSObject.Properties['Response'] -and $_.Exception.Response -and $_.Exception.Response.PSObject.Properties['StatusCode']){
        $report.httpStatus=[int]$_.Exception.Response.StatusCode
    }
    try{Save-HistoryProgress 100 'Stopped; share partial report. Do not automatically retry.'}catch{Write-Warning 'Save failed; retain previous JSON/pending file.'}
    throw
} finally {Write-Progress -Id 100 -Activity 'Read-only numerical history coverage' -Completed;Write-Host "Share: $path"}
