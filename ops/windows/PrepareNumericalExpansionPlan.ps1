#Requires -Version 5.1
[CmdletBinding()]
param([Parameter(Mandatory)][string]$ResearchExportPath,[string]$OutputDirectory='C:\MarketBrainData\Review')
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'NumericalExpansionPlan.ps1')
. (Join-Path $PSScriptRoot 'NumericalHistoryEvidence.ps1')
if(-not(Test-Path -LiteralPath $OutputDirectory)){[void](New-Item -ItemType Directory -Path $OutputDirectory)}
$path=Join-Path (Resolve-Path -LiteralPath $OutputDirectory).Path ('numerical-expansion-plan-'+(Get-Date -Format 'yyyyMMdd-HHmmss')+'-'+[guid]::NewGuid().ToString('N').Substring(0,12)+'.json')
if(Test-Path -LiteralPath $path){throw 'Refusing report overwrite.'}
$timer=[Diagnostics.Stopwatch]::StartNew()
$report=[pscustomobject]@{version='NUMERICAL_EXPANSION_PLAN_COLLECTION_V1';status='RUNNING';createdAtUtc=[DateTime]::UtcNow.ToString('o');updatedAtUtc=$null;elapsedSeconds=0
    inputSha256=$null;inputFileName=$null;plan=$null;failureStage=$null;errorType=$null;events=[Collections.Generic.List[object]]::new()
    scriptSha256=(Get-FileHash -LiteralPath $PSCommandPath).Hash;plannerSha256=(Get-FileHash -LiteralPath (Join-Path $PSScriptRoot 'NumericalExpansionPlan.ps1')).Hash}
function Save-PlanProgress([int]$Percent,[string]$Message){
    $report.elapsedSeconds=[math]::Round($timer.Elapsed.TotalSeconds,3)
    $report.events.Add([pscustomobject]@{atUtc=[DateTime]::UtcNow.ToString('o');percent=$Percent;message=$Message})
    Save-NumericalHistoryReport $report $path;Write-Host "[$Percent%] $Message"
    Write-Progress -Id 107 -Activity 'Offline numerical expansion plan' -Status $Message -PercentComplete $Percent
}
try{
    $stage='INPUT';Save-PlanProgress 0 'Reading saved export only; no service, provider or model calls.'
    $inputFile=Read-NumericalBundleInput $ResearchExportPath;$report.inputSha256=$inputFile.sha256;$report.inputFileName=$inputFile.name
    $stage='PLAN';Save-PlanProgress 25 'Checking saved paths and preparing date-only development partitions.'
    $report.plan=New-NumericalExpansionPlan $inputFile
    $report.status=$report.plan.status
    Save-PlanProgress 100 'Plan saved. Calendar, price provenance and untouched evaluation remain gated.'
    $report.plan|Select-Object status,decisionFrom,decisionThrough,featureFrom,outcomeThrough,provisionalCandidateRowCount,provisionalRetainedRowCount,previouslyReviewedShadowTestDateCount,trainingAuthorized|Format-List
}catch{
    $report.status='FAILED_PARTIAL_REPORT';$report.failureStage=$stage;$report.errorType=$_.Exception.GetType().Name
    try{Save-PlanProgress 100 'Stopped; partial plan retained. No automatic retries.'}catch{Write-Warning 'Save failed; retain prior JSON/pending file.'}
    throw
}finally{Write-Progress -Id 107 -Activity 'Offline numerical expansion plan' -Completed;Write-Host "Share: $path"}
