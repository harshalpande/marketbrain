#Requires -Version 5.1
[CmdletBinding()]
param([Parameter(Mandatory)][string]$ResearchExportPath,[Parameter(Mandatory)][string]$RepairEvidencePath,
      [string]$BaseUrl='http://127.0.0.1:8080',[string]$OutputDirectory='C:\MarketBrainData\Review',[string]$ExistingExpandedReportPath)
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'NumericalExpandedResearch.ps1')
. (Join-Path $PSScriptRoot 'NumericalHistoryEvidence.ps1')
. (Join-Path $PSScriptRoot 'LlmCleanupInventory.ps1')
$base=Assert-LlmInventoryLoopback $BaseUrl
if(-not(Test-Path -LiteralPath $OutputDirectory)){[void](New-Item -ItemType Directory -Path $OutputDirectory)}
$path=Join-Path (Resolve-Path -LiteralPath $OutputDirectory).Path ('numerical-expanded-research-'+(Get-Date -Format 'yyyyMMdd-HHmmss')+'-'+[guid]::NewGuid().ToString('N').Substring(0,12)+'.json')
if(Test-Path -LiteralPath $path){throw 'Refusing report overwrite.'}
$timer=[Diagnostics.Stopwatch]::StartNew()
$report=[pscustomobject]@{version='NUMERICAL_EXPANDED_RESEARCH_COLLECTION_V1';status='RUNNING';createdAtUtc=[DateTime]::UtcNow.ToString('o');updatedAtUtc=$null;elapsedSeconds=0
    sourceFileName=$null;sourceSha256=$null;repairFileName=$null;repairSha256=$null;researchMode='UNCERTIFIED_STORED_PRICE_RESEARCH_ONLY';trainingAuthorized=$false
    request=$null;requestSha256=$null;calendarReview=$null;repairEvidence=$null;result=$null;reusedReportSha256=$null;failureStage=$null;errorType=$null
    scriptSha256=(Get-FileHash -LiteralPath $PSCommandPath).Hash;helperSha256=(Get-FileHash -LiteralPath (Join-Path $PSScriptRoot 'NumericalExpandedResearch.ps1')).Hash
    resultReviewerSha256=(Get-FileHash -LiteralPath (Join-Path $PSScriptRoot 'NumericalResearchExport.ps1')).Hash;events=[Collections.Generic.List[object]]::new()}
function Save-ExpandedProgress([int]$Percent,[string]$Message){
    $report.elapsedSeconds=[math]::Round($timer.Elapsed.TotalSeconds,3);$report.events.Add([pscustomobject]@{atUtc=[DateTime]::UtcNow.ToString('o');percent=$Percent;message=$Message})
    Save-NumericalHistoryReport $report $path -Compact -MaxReplaceAttempts 12;Write-Host "[$Percent%] $Message"
    Write-Progress -Id 109 -Activity 'Uncertified expanded research export' -Status $Message -PercentComplete $Percent
}
try{
    $stage='INPUT';Save-ExpandedProgress 0 'Reading saved export and repair evidence. No DB/provider/model calls.'
    $source=Read-NumericalBundleInput $ResearchExportPath;$repair=Read-NumericalBundleInput $RepairEvidencePath
    $report.sourceFileName=$source.name;$report.sourceSha256=$source.sha256;$report.repairFileName=$repair.name;$report.repairSha256=$repair.sha256
    Save-ExpandedProgress 10 'Rechecking saved evidence binding and all expanded calendar windows.'
    $context=New-NumericalExpandedResearchContext $source $repair
    $report.request=$context.request;$report.calendarReview=$context.calendarReview;$report.repairEvidence=$context.priceEvidence
    $bytes=[Text.Encoding]::UTF8.GetBytes(($report.request|ConvertTo-Json -Depth 16 -Compress))
    if($bytes.Length -gt 2MB){throw 'Request exceeds bounded endpoint size.'}
    $sha=[Security.Cryptography.SHA256]::Create()
    try{$report.requestSha256=[BitConverter]::ToString($sha.ComputeHash($bytes)).Replace('-','')}finally{$sha.Dispose()}
    Save-ExpandedProgress 35 'Inputs checkpointed. Price policy unknown; no certified labels or fitting.'
    if($ExistingExpandedReportPath){
        $stage='REUSE';$saved=Read-NumericalBundleInput $ExistingExpandedReportPath
        if($saved.data.version -ne $report.version -or $saved.data.sourceSha256 -ne $source.sha256 -or $saved.data.repairSha256 -ne $repair.sha256 -or $null -eq $saved.data.result){throw 'Saved response binding mismatch.'}
        $report.reusedReportSha256=$saved.sha256;$report.result=$saved.data.result
    }else{
        $stage='HEALTH';$health=Invoke-RestMethod -Uri ($base+'/actuator/health') -TimeoutSec 10 -MaximumRedirection 0 -ErrorAction Stop
        if($health.status -ne 'UP'){throw 'Service not UP.'}
        $stage='EXPORT';Save-ExpandedProgress 45 'Java calculating 150 dates from saved bars only; one request, no queue or automatic retry.'
        $report.result=Invoke-RestMethod -Uri ($base+'/api/v1/training/numerical-expanded-research-export') -Method Post -ContentType 'application/json; charset=utf-8' -Body $bytes -TimeoutSec 90 -MaximumRedirection 0 -ErrorAction Stop
    }
    $stage='REVIEW';Save-ExpandedProgress 80 'Response persisted; independently checking every outcome, feature window and safety counter.'
    Assert-NumericalResearchExportResult $report.request $report.result -Expanded
    $report.status=$report.result.status
    Save-ExpandedProgress 100 'Expanded research arithmetic exported. Price policy, certified labels, frozen evaluation and fitting remain pending.'
    $report.result|Select-Object status,decisionDateCount,candidateRowCount,completeArithmeticRowCount,blockedRowCount,certifiedLabelCount,trainingAuthorized|Format-List
}catch{
    $report.status='FAILED_PARTIAL_REPORT';$report.failureStage=$stage;$report.errorType=$_.Exception.GetType().Name
    try{Save-ExpandedProgress 100 'Stopped; partial evidence retained. No automatic request retry.'}catch{Write-Warning 'Save failed; preserve previous report/pending checkpoint.'}
    throw
}finally{Write-Progress -Id 109 -Activity 'Uncertified expanded research export' -Completed;Write-Host "Share: $path"}
