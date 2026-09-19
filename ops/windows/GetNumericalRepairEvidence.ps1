#Requires -Version 5.1
[CmdletBinding()]
param([Parameter(Mandatory)][string]$ResearchExportPath,[ValidateRange(0,499)][int]$Offset=0,
      [string]$BaseUrl='http://127.0.0.1:8080',[string]$OutputDirectory='C:\MarketBrainData\Review',[string]$ExistingRepairReportPath)
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'NumericalRepairEvidence.ps1')
. (Join-Path $PSScriptRoot 'NumericalHistoryEvidence.ps1')
. (Join-Path $PSScriptRoot 'LlmCleanupInventory.ps1')
$base=Assert-LlmInventoryLoopback $BaseUrl
if(-not(Test-Path -LiteralPath $OutputDirectory)){[void](New-Item -ItemType Directory -Path $OutputDirectory)}
$path=Join-Path (Resolve-Path -LiteralPath $OutputDirectory).Path ('numerical-repair-evidence-'+(Get-Date -Format 'yyyyMMdd-HHmmss')+'-'+[guid]::NewGuid().ToString('N').Substring(0,12)+'.json')
if(Test-Path -LiteralPath $path){throw 'Refusing report overwrite.'}
$timer=[Diagnostics.Stopwatch]::StartNew()
$report=[pscustomobject]@{version='NUMERICAL_REPAIR_COLLECTION_V1';status='RUNNING';createdAtUtc=[DateTime]::UtcNow.ToString('o');updatedAtUtc=$null;elapsedSeconds=0
    inputFileName=$null;inputSha256=$null;earlyCalendar=$null;earlyCalendarSha256=$null;calendarReview=$null;repairEvidence=$null;reusedReportSha256=$null
    failureStage=$null;errorType=$null;events=[Collections.Generic.List[object]]::new();scriptSha256=(Get-FileHash -LiteralPath $PSCommandPath).Hash
    helperSha256=(Get-FileHash -LiteralPath (Join-Path $PSScriptRoot 'NumericalRepairEvidence.ps1')).Hash;calendarHelperSha256=(Get-FileHash -LiteralPath (Join-Path $PSScriptRoot 'NumericalExpandedCalendar.ps1')).Hash}
function Save-RepairProgress([int]$Percent,[string]$Message){
    $report.elapsedSeconds=[math]::Round($timer.Elapsed.TotalSeconds,3);$report.events.Add([pscustomobject]@{atUtc=[DateTime]::UtcNow.ToString('o');percent=$Percent;message=$Message})
    Save-NumericalHistoryReport $report $path;Write-Host "[$Percent%] $Message"
    Write-Progress -Id 108 -Activity 'Calendar and stored repair evidence' -Status $Message -PercentComplete $Percent
}
try{
    $stage='INPUT';Save-RepairProgress 0 'Reading saved export; no historical-data acquisition.'
    $inputFile=Read-NumericalBundleInput $ResearchExportPath;$report.inputFileName=$inputFile.name;$report.inputSha256=$inputFile.sha256
    $early=Read-NumericalBundleInput (Join-Path $PSScriptRoot '..\data\nse-cm-early-calendar-20241022-20250331-v1.json')
    $report.earlyCalendar=$early.data;$report.earlyCalendarSha256=$early.sha256
    $stage='CALENDAR';Save-RepairProgress 15 'Checking every proposed feature/outcome window against the extended calendar.'
    $report.calendarReview=Get-NumericalExpandedCalendarReview $inputFile $early.data
    Save-RepairProgress 40 'Calendar review persisted. Price provenance remains a separate gate.'
    if($report.calendarReview.status -ne 'EXPANDED_WINDOWS_MATCH_TRAINING_BLOCKED'){throw 'Expanded windows blocked; no database request made.'}
    if($ExistingRepairReportPath){
        $stage='REUSE';$saved=Read-NumericalBundleInput $ExistingRepairReportPath
        if($saved.data.version -ne 'NUMERICAL_REPAIR_COLLECTION_V1' -or $saved.data.inputSha256 -ne $inputFile.sha256 -or $null -eq $saved.data.repairEvidence){throw 'Repair reuse input mismatch.'}
        $report.reusedReportSha256=$saved.sha256;$report.repairEvidence=$saved.data.repairEvidence
    }else{
        $stage='HEALTH';$health=Invoke-RestMethod -Uri ($base+'/actuator/health') -TimeoutSec 10 -MaximumRedirection 0 -ErrorAction Stop
        if($health.status -ne 'UP'){throw 'Service not UP.'}
        $stage='QUERY';Save-RepairProgress 55 'Reading bounded existing quality/action records and sanitized references; no provider/model calls.'
        $plan=$report.calendarReview.plan;$run=[guid]$plan.datasetRunId;$count=@($inputFile.data.request.instruments).Count
        $uri=$base+"/api/v1/training/numerical-repair-evidence?datasetRunId=$run&fromDate=$($plan.featureFrom)&throughDate=$($plan.outcomeThrough)&offset=$Offset&limit=$count"
        $report.repairEvidence=Invoke-RestMethod -Uri $uri -TimeoutSec 90 -MaximumRedirection 0 -ErrorAction Stop
    }
    $stage='REVIEW';Save-RepairProgress 85 'Response checkpointed; checking exact scope, caps and no-side-effect flags.'
    Assert-NumericalRepairEvidence $inputFile $report.calendarReview $report.repairEvidence $Offset
    $report.status='REPAIR_EVIDENCE_CAPTURED_TRAINING_BLOCKED'
    Save-RepairProgress 100 'Evidence recovered for review; empty or partial records do not certify price adjustments.'
    $report.calendarReview|Select-Object status,decisionDateCount,rowCount,featureWindowMatchCount,outcomeWindowMatchCount,blockedRowCount|Format-List
    $report.repairEvidence|Select-Object status,scopedResolutionCount,scopedActionCount,partial,trainingAuthorized|Format-List
}catch{
    $report.status='FAILED_PARTIAL_REPORT';$report.failureStage=$stage;$report.errorType=$_.Exception.GetType().Name
    try{Save-RepairProgress 100 'Stopped; partial evidence retained. No automatic database retry.'}catch{Write-Warning 'Save failed; retain previous JSON/pending file.'}
    throw
}finally{Write-Progress -Id 108 -Activity 'Calendar and stored repair evidence' -Completed;Write-Host "Share: $path"}
