#Requires -Version 5.1
[CmdletBinding()]
param([Parameter(Mandatory)][string]$FeatureEvidencePath,[Parameter(Mandatory)][string]$OutcomeEvidencePath,
      [string]$BaseUrl='http://127.0.0.1:8080',[string]$OutputDirectory='C:\MarketBrainData\Review')
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'NumericalResearchExport.ps1')
. (Join-Path $PSScriptRoot 'NumericalHistoryEvidence.ps1')
. (Join-Path $PSScriptRoot 'LlmCleanupInventory.ps1')
$base=Assert-LlmInventoryLoopback $BaseUrl
if(-not(Test-Path -LiteralPath $OutputDirectory)){[void](New-Item -ItemType Directory -Path $OutputDirectory)}
$path=Join-Path (Resolve-Path -LiteralPath $OutputDirectory).Path ('numerical-research-export-'+(Get-Date -Format 'yyyyMMdd-HHmmss')+'-'+[guid]::NewGuid().ToString('N').Substring(0,12)+'.json')
if(Test-Path -LiteralPath $path){throw 'Refusing report overwrite.'}
$timer=[Diagnostics.Stopwatch]::StartNew()
$report=[pscustomobject]@{version='NUMERICAL_RESEARCH_EXPORT_COLLECTION_V1';status='RUNNING';createdAtUtc=[DateTime]::UtcNow.ToString('o');updatedAtUtc=$null;elapsedSeconds=0
    featureFileName=$null;outcomeFileName=$null;request=$null;requestSha256=$null;result=$null
    scriptSha256=(Get-FileHash -LiteralPath $PSCommandPath).Hash;helperSha256=(Get-FileHash -LiteralPath (Join-Path $PSScriptRoot 'NumericalResearchExport.ps1')).Hash
    calendar=$null;extension=$null;priceEvidence=$null;failureStage=$null;errorType=$null;events=[Collections.Generic.List[object]]::new()}
function Save-ExportProgress([int]$Percent,[string]$Message){
    $report.elapsedSeconds=[math]::Round($timer.Elapsed.TotalSeconds,3)
    $report.events.Add([pscustomobject]@{atUtc=[DateTime]::UtcNow.ToString('o');percent=$Percent;message=$Message})
    Save-NumericalHistoryReport $report $path;Write-Host "[$Percent%] $Message"
    Write-Progress -Id 106 -Activity 'Saved-data multi-date research export' -Status $Message -PercentComplete $Percent
}
try{
    $stage='INPUT';Save-ExportProgress 0 'Verifying saved feature and outcome files. No history download.'
    $f=Read-NumericalBundleInput $FeatureEvidencePath;$o=Read-NumericalBundleInput $OutcomeEvidencePath
    $report.featureFileName=$f.name;$report.outcomeFileName=$o.name
    $report.calendar=(Read-NumericalBundleInput (Join-Path $PSScriptRoot '..\data\nse-cm-calendar-20250401-20260605-v1.json')).data
    $report.extension=(Read-NumericalBundleInput (Join-Path $PSScriptRoot '..\data\nse-cm-outcome-calendar-20260606-20260717-v1.json')).data
    $report.request=New-NumericalResearchExportRequest $f $o $report.calendar $report.extension
    $report.priceEvidence=$o.data.outcome.priceEvidence
    $body=$report.request | ConvertTo-Json -Depth 16 -Compress
    $bytes=[Text.Encoding]::UTF8.GetBytes($body)
    if($bytes.Length -gt 2MB){throw 'Export request exceeds bounded endpoint size.'}
    $sha=[Security.Cryptography.SHA256]::Create()
    try{$report.requestSha256=[BitConverter]::ToString($sha.ComputeHash($bytes)).Replace('-','')}finally{$sha.Dispose()}
    $stage='HEALTH';Save-ExportProgress 25 'Inputs checkpointed. Checking Java service health.'
    $health=Invoke-RestMethod -Uri ($base+'/actuator/health') -TimeoutSec 10 -MaximumRedirection 0 -ErrorAction Stop
    if($health.status -ne 'UP'){throw 'Service not UP.'}
    $stage='EXPORT';Save-ExportProgress 40 'Java is calculating the bounded multi-date pilot from saved bars; no DB/provider/model calls.'
    $report.result=Invoke-RestMethod -Uri ($base+'/api/v1/training/numerical-research-export') -Method Post -ContentType 'application/json; charset=utf-8' -Body $bytes -TimeoutSec 90 -MaximumRedirection 0 -ErrorAction Stop
    $stage='REVIEW';Save-ExportProgress 80 'Export persisted. Independently checking every outcome and safety counter.'
    Assert-NumericalResearchExportResult $report.request $report.result
    $report.status=$report.result.status
    Save-ExportProgress 100 'Research export complete. Price policy, broader dates, frozen splits and fitting remain pending.'
    $report.result | Select-Object status,decisionDateCount,candidateRowCount,completeArithmeticRowCount,blockedRowCount,certifiedLabelCount,trainingAuthorized | Format-List
}catch{
    $report.status='FAILED_PARTIAL_REPORT';$report.failureStage=$stage;$report.errorType=$_.Exception.GetType().Name
    try{Save-ExportProgress 100 'Stopped; evidence retained. No automatic POST retry.'}catch{Write-Warning 'Save failed; retain previous JSON/pending file.'}
    throw
}finally{Write-Progress -Id 106 -Activity 'Saved-data multi-date research export' -Completed;Write-Host "Share: $path"}
