#Requires -Version 5.1
[CmdletBinding()]
param(
    [Parameter(Mandatory)][guid]$DatasetRunId,
    [ValidateRange(0,499)][int]$Offset=0,
    [ValidateRange(1,4)][int]$Limit=4,
    [string]$BaseUrl='http://127.0.0.1:8080',
    [string]$OutputDirectory='C:\MarketBrainData\Review'
)
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'LlmCleanupInventory.ps1')
. (Join-Path $PSScriptRoot 'NumericalHistoryEvidence.ps1')
$base=Assert-LlmInventoryLoopback $BaseUrl
if($DatasetRunId -eq [guid]::Empty){throw 'Explicit dataset ID required.'}
if(-not(Test-Path -LiteralPath $OutputDirectory)){[void](New-Item -ItemType Directory -Path $OutputDirectory)}
$path=Join-Path (Resolve-Path -LiteralPath $OutputDirectory).Path ('numerical-features-'+(Get-Date -Format 'yyyyMMdd-HHmmss')+'-'+[guid]::NewGuid().ToString('N').Substring(0,12)+'.json')
if(Test-Path -LiteralPath $path){throw 'Report already exists; refusing overwrite.'}
$timer=[Diagnostics.Stopwatch]::StartNew()
$report=[pscustomobject]@{
    version='NUMERICAL_FEATURE_EVIDENCE_V1';status='RUNNING';datasetRunId=$DatasetRunId.ToString();offset=$Offset;limit=$Limit
    createdAtUtc=[DateTime]::UtcNow.ToString('o');updatedAtUtc=$null;elapsedSeconds=0
    scriptSha256=(Get-FileHash -LiteralPath $PSCommandPath).Hash
    events=[Collections.Generic.List[object]]::new();snapshot=$null;summary=$null;failureStage=$null;failureMessage=$null;errorType=$null;httpStatus=$null
}
function Save-FeatureProgress([int]$Percent,[string]$Message){
    $report.elapsedSeconds=[math]::Round($timer.Elapsed.TotalSeconds,3)
    $report.events.Add([pscustomobject]@{atUtc=[DateTime]::UtcNow.ToString('o');percent=$Percent;message=$Message})
    Save-NumericalHistoryReport $report $path
    Write-Host "[$Percent%] $Message"
    Write-Progress -Id 101 -Activity 'Numerical feature snapshot (no training)' -Status $Message -PercentComplete $Percent
}
try {
    $stage='HEALTH';Save-FeatureProgress 0 'Checking health; no model/provider calls or database writes.'
    $health=Invoke-RestMethod -Uri ($base+'/actuator/health') -Method Get -TimeoutSec 10 -MaximumRedirection 0 -ErrorAction Stop
    if($health.status -ne 'UP'){throw 'Service not UP.'}
    $stage='SNAPSHOT';Save-FeatureProgress 15 'One bounded request: up to four stocks and three dates; waiting for response.'
    $snapshot=Invoke-RestMethod -Uri ($base+'/api/v1/training/numerical-feature-snapshot?datasetRunId='+$DatasetRunId.ToString()+"&offset=$Offset&limit=$Limit") -Method Get -TimeoutSec 60 -MaximumRedirection 0 -ErrorAction Stop
    $report.snapshot=$snapshot
    $stage='VALIDATION'
    if($snapshot.status -ne 'FEATURE_SNAPSHOT_REVIEW_REQUIRED' -or $snapshot.payload.version -ne 'OBSERVED_252_FEATURE_SNAPSHOT_V1' -or
       [string]$snapshot.payload.datasetRunId -ne $DatasetRunId.ToString() -or $snapshot.payload.offset -ne $Offset -or $snapshot.payload.limit -ne $Limit -or
       $snapshot.payloadSha256 -notmatch '^[a-f0-9]{64}$' -or $snapshot.payload.datasetManifestHash -notmatch '^[a-fA-F0-9]{64}$') {throw 'Unexpected snapshot scope/version/hash.'}
    foreach($flag in @('trainingAuthorized','databaseWritesPerformed')){if($snapshot.$flag -isnot [bool] -or $snapshot.$flag){throw 'Unsafe authorization flag.'}}
    foreach($counter in @('modelCallCount','providerCallCount','ordersCreated')){if($snapshot.$counter -is [bool] -or $snapshot.$counter -is [string] -or $null -eq $snapshot.$counter -or $snapshot.$counter -ne 0){throw 'Unexpected side effects.'}}
    $items=@($snapshot.payload.instruments);$dates=@($snapshot.payload.decisionDates)
    if($items.Count -lt 1 -or $items.Count -gt $Limit -or $dates.Count -ne 3 -or $snapshot.partial -isnot [bool]){throw 'Unexpected snapshot size/partial flag.'}
    $ids=[Collections.Generic.HashSet[string]]::new();$computed=0;$blocked=0
    foreach($item in $items){
        if(-not $ids.Add([string]$item.instrumentId) -or @($item.rows).Count -ne 3 -or @($item.canonicalBars).Count -gt 2001 -or
           $item.rawRowCount -gt 2001 -or $item.rawRowCount -lt 0 -or $item.truncated -isnot [bool] -or $item.truncated -ne ($item.rawRowCount -gt 2000)){throw 'Invalid instrument rows/cap.'}
        for($i=0;$i -lt 3;$i++){
            $row=$item.rows[$i]
            if($row.decisionDate -ne $dates[$i]){throw 'Decision date mismatch.'}
            if($null -ne $row.features){
                if($item.truncated -or $row.status -ne 'FEATURES_ONLY_CALENDAR_UNVERIFIED' -or $row.observationCount -ne 252 -or @($row.sourceCandleIds).Count -ne 252){throw 'Invalid feature row.'}
                $computed++
            }else{$blocked++}
        }
    }
    if($snapshot.partial -ne (@($items | Where-Object truncated).Count -gt 0)){throw 'Partial flag mismatch.'}
    $report.summary=[pscustomobject]@{instrumentCount=$items.Count;decisionDateCount=3;computedFeatureRows=$computed;blockedRows=$blocked;trainingAuthorized=$false;labelsGenerated=0}
    $report.status='FEATURE_SNAPSHOT_REVIEW_REQUIRED'
    Save-FeatureProgress 100 'Snapshot captured. Calendar, adjustment and label gates remain; share this one JSON.'
    $report.summary | Format-List
}catch{
    $report.status='FAILED_PARTIAL_REPORT';$report.failureStage=$stage;$report.errorType=$_.Exception.GetType().Name
    # Preserve local contract failure detail; do not copy arbitrary HTTP response bodies/configuration.
    $report.failureMessage=if($stage -eq 'VALIDATION'){$_.Exception.Message}else{'Collection/save failed; inspect failureStage, errorType and httpStatus. No automatic retry.'}
    if($_.Exception.PSObject.Properties['Response'] -and $_.Exception.Response -and $_.Exception.Response.PSObject.Properties['StatusCode']){$report.httpStatus=[int]$_.Exception.Response.StatusCode}
    try{Save-FeatureProgress 100 'Stopped; preserve and share the partial report. No automatic query retry.'}catch{Write-Warning 'Save failed; retain previous JSON/pending file.'}
    throw
}finally{Write-Progress -Id 101 -Activity 'Numerical feature snapshot (no training)' -Completed;Write-Host "Share: $path"}
