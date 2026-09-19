#Requires -Version 5.1
[CmdletBinding()]
param([Parameter(Mandatory)][string]$ExpandedResearchPath,[string]$BaseUrl='http://127.0.0.1:8080',
      [string]$OutputDirectory='C:\MarketBrainData\Review',[string]$SavedMappingResultPath)
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'NumericalResearchMapping.ps1')
. (Join-Path $PSScriptRoot 'NumericalHistoryEvidence.ps1')
. (Join-Path $PSScriptRoot 'LlmCleanupInventory.ps1')
$base=Assert-LlmInventoryLoopback $BaseUrl
if(-not(Test-Path -LiteralPath $OutputDirectory)){[void](New-Item -ItemType Directory -Path $OutputDirectory)}
$path=Join-Path (Resolve-Path -LiteralPath $OutputDirectory).Path ('numerical-research-mapping-'+(Get-Date -Format 'yyyyMMdd-HHmmss')+'-'+[guid]::NewGuid().ToString('N').Substring(0,12)+'.json')
if(Test-Path -LiteralPath $path){throw 'Refusing report overwrite.'}
$timer=[Diagnostics.Stopwatch]::StartNew()
$report=[pscustomobject]@{version='NUMERICAL_RESEARCH_MAPPING_COLLECTION_V1';status='RUNNING';createdAtUtc=[DateTime]::UtcNow.ToString('o');updatedAtUtc=$null
    elapsedSeconds=0;mappingRoundTripSeconds=$null;reviewSeconds=$null;sourceFileName=$null;sourceSha256=$null;request=$null;requestSha256=$null;result=$null;reusedResultSha256=$null
    trainingAuthorized=$false;failureStage=$null;errorType=$null;executionMode=$(if($SavedMappingResultPath){'OFFLINE_SAVED_RESPONSE_REVIEW'}else{'JAVA_SAVED_INPUT_MAPPING'})
    powerShellVersion=$PSVersionTable.PSVersion.ToString();culture=[Globalization.CultureInfo]::CurrentCulture.Name;localTimeZone=[TimeZoneInfo]::Local.Id
    cutoffValueType=$null;replayMetadata=$null;scriptSha256=(Get-FileHash -LiteralPath $PSCommandPath).Hash
    reviewerSha256=(Get-FileHash -LiteralPath (Join-Path $PSScriptRoot 'NumericalResearchMapping.ps1')).Hash;events=[Collections.Generic.List[object]]::new()}
function Save-MappingProgress([int]$Percent,[string]$Message){
    $report.elapsedSeconds=[math]::Round($timer.Elapsed.TotalSeconds,3)
    $report.events.Add([pscustomobject]@{atUtc=[DateTime]::UtcNow.ToString('o');percent=$Percent;message=$Message})
    Save-NumericalHistoryReport $report $path -Compact -MaxReplaceAttempts 12
    Write-Host "[$Percent%] $Message";Write-Progress -Id 113 -Activity 'Numerical research mapping' -Status $Message -PercentComplete $Percent
}
try{
    $stage='INPUT';Save-MappingProgress 0 'Reading accepted saved E52 export; no recollection, database, provider or model calls.'
    $source=Read-NumericalBundleInput $ExpandedResearchPath;Assert-NumericalMappingSource $source
    $report.sourceFileName=$source.name;$report.sourceSha256=$source.sha256;$report.request=$source.data.request
    $bytes=[Text.Encoding]::UTF8.GetBytes(($report.request|ConvertTo-Json -Depth 16 -Compress))
    if($bytes.Length -gt 2MB){throw 'Request exceeds bounded endpoint size.'}
    $sha=[Security.Cryptography.SHA256]::Create()
    try{$report.requestSha256=[BitConverter]::ToString($sha.ComputeHash($bytes)).Replace('-','')}finally{$sha.Dispose()}
    Save-MappingProgress 25 'Saved input checkpointed; mapping features and eligibility, NOT fitting a model.'
    if($SavedMappingResultPath){
        $stage='REUSE';$reused=Read-NumericalBundleInput $SavedMappingResultPath
        $report.reusedResultSha256=$reused.sha256;$report.result=Get-NumericalMappingReplayResult $source $reused
        if($reused.data.version -eq $report.version){
            $report.replayMetadata=[pscustomobject]@{previousStatus=$reused.data.status;previousElapsedSeconds=$reused.data.elapsedSeconds
                previousMappingRoundTripSeconds=$reused.data.mappingRoundTripSeconds;previousFailureStage=$reused.data.failureStage}
        }
    }else{
        $stage='HEALTH';$health=Invoke-RestMethod -Uri ($base+'/actuator/health') -TimeoutSec 10 -MaximumRedirection 0
        if($health.status -ne 'UP'){throw 'Service not UP; no request submitted.'}
        $stage='MAPPING';Save-MappingProgress 40 'One bounded Java mapping request; no automatic POST retry.'
        $requestTimer=[Diagnostics.Stopwatch]::StartNew()
        try{$report.result=Invoke-RestMethod -Uri ($base+'/api/v1/training/numerical-research-mapping') -Method Post -ContentType 'application/json; charset=utf-8' -Body $bytes -TimeoutSec 90 -MaximumRedirection 0}
        finally{$report.mappingRoundTripSeconds=[math]::Round($requestTimer.Elapsed.TotalSeconds,3)}
    }
    $stage='REVIEW'
    if($null -ne $report.result -and @($report.result.rows).Count -gt 0 -and $null -ne $report.result.rows[0].proposedCutoff){
        $report.cutoffValueType=$report.result.rows[0].proposedCutoff.GetType().FullName
    }
    Save-MappingProgress 80 'Response checkpointed; checking every vector, date group, blocker and safety counter.'
    $reviewTimer=[Diagnostics.Stopwatch]::StartNew()
    try{Assert-NumericalResearchMapping $source $report.result}finally{$report.reviewSeconds=[math]::Round($reviewTimer.Elapsed.TotalSeconds,3)}
    $report.status=$report.result.status
    Save-MappingProgress 100 'Mapping reviewed. Training remains blocked by source evidence and evaluation policy.'
    $report.result|Select-Object status,rowCount,mappingReadyCount,trainingEligibleCount,certifiedLabelCount,trainingAuthorized|Format-List
}catch{
    $report.status='FAILED_PARTIAL_REPORT';$report.failureStage=$stage;$report.errorType=$_.Exception.GetType().Name
    try{Save-MappingProgress 100 'Stopped; partial evidence preserved. Do not rerun collection.'}catch{Write-Warning 'Checkpoint save failed; preserve the previous/pending report.'}
    throw
}finally{Write-Progress -Id 113 -Activity 'Numerical research mapping' -Completed;Write-Host "Share this one file: $path"}
