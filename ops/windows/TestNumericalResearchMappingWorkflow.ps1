#Requires -Version 5.1
param([Parameter(Mandatory)][string]$ExpandedResearchPath,[Parameter(Mandatory)][string]$RawMappingResultPath)
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'NumericalResearchMapping.ps1')
$source=Read-NumericalBundleInput $ExpandedResearchPath
$replay=Read-NumericalBundleInput $RawMappingResultPath
$raw=Get-NumericalMappingReplayResult $source $replay
$script:checks=0
function Check([bool]$Condition,[string]$Message){if(-not $Condition){throw $Message};$script:checks++}
function Reject([scriptblock]$Action){$rejected=$false;try{& $Action}catch{$rejected=$true};Check $rejected 'Expected rejection.'}
Assert-NumericalResearchMapping $source $raw;Check $true 'Saved cohort reviewed.'
function Copy-Result { $raw|ConvertTo-Json -Depth 16 -Compress|ConvertFrom-Json }
$bad=Copy-Result;$bad.trainingAuthorized=$true;Reject {Assert-NumericalResearchMapping $source $bad}
$bad=Copy-Result;$bad.modelCallCount=1;Reject {Assert-NumericalResearchMapping $source $bad}
$bad=Copy-Result;$bad.datasetRunId=[guid]::NewGuid().ToString();Reject {Assert-NumericalResearchMapping $source $bad}
$bad=Copy-Result;$bad.rows[0].features.closeToSma20Percent=999;Reject {Assert-NumericalResearchMapping $source $bad}
$bad=Copy-Result;$bad.rows[0].features|Add-Member -NotePropertyName actualRank -NotePropertyValue 1;Reject {Assert-NumericalResearchMapping $source $bad}
$bad=Copy-Result;$bad.rows[0].trainingEligible=$true;Reject {Assert-NumericalResearchMapping $source $bad}
$bad=Copy-Result;$bad.rows[1]=$bad.rows[0];Reject {Assert-NumericalResearchMapping $source $bad}
$bad=Copy-Result;$bad.rows[0].sourceCandleIds[0]=999999;Reject {Assert-NumericalResearchMapping $source $bad}
$bad=Copy-Result;$bad.rows[0].proposedCutoff='2025-10-27T11:30:00Z';Reject {Assert-NumericalResearchMapping $source $bad}
$bad=Copy-Result;$bad.rows[0].blockers=@();Reject {Assert-NumericalResearchMapping $source $bad}
$wrong=[pscustomobject]@{sha256=('0'*64);data=$source.data};Reject {Assert-NumericalMappingSource $wrong}
$typed=Copy-Result
foreach($row in $typed.rows){$row.proposedCutoff=ConvertTo-NumericalMappingUtc $row.proposedCutoff}
Assert-NumericalResearchMapping $source $typed;Check $true 'Typed UTC timestamps reviewed.'
$typed.rows[0].proposedCutoff=$typed.rows[0].proposedCutoff.AddTicks(1)
Reject {Assert-NumericalResearchMapping $source $typed}
$typed.rows[0].proposedCutoff=[datetime]::SpecifyKind($typed.rows[0].proposedCutoff,[DateTimeKind]::Unspecified)
Reject {Assert-NumericalResearchMapping $source $typed}
$envelope=[pscustomobject]@{data=[pscustomobject]@{version='NUMERICAL_RESEARCH_MAPPING_COLLECTION_V1';sourceSha256=$source.sha256;trainingAuthorized=$false;request=$source.data.request;result=$raw}}
[void](Get-NumericalMappingReplayResult $source $envelope);Check $true 'Saved envelope source binding reviewed.'
$envelope.data.sourceSha256='0'*64;Reject {Get-NumericalMappingReplayResult $source $envelope}
$envelope.data.sourceSha256=$source.sha256;$envelope.data.request=@{};Reject {Get-NumericalMappingReplayResult $source $envelope}
$envelope.data.request=$source.data.request;$envelope.data.result=$null;Reject {Get-NumericalMappingReplayResult $source $envelope}

$folder=Join-Path ([IO.Path]::GetTempPath()) ('marketbrain-mapping-test-'+[guid]::NewGuid().ToString('N'))
[void](New-Item -ItemType Directory -Path $folder)
$mappingTestState=[pscustomobject]@{postCount=0;simulateFailure=$false;healthDown=$false}
function Invoke-RestMethod {
    param($Uri,$TimeoutSec,$MaximumRedirection,$Method,$ContentType,$Body)
    if($Uri -like '*/actuator/health'){if($mappingTestState.healthDown){return @{status='DOWN'}};return @{status='UP'}}
    $mappingTestState.postCount++
    if($mappingTestState.simulateFailure){throw [TimeoutException]::new('fixture timeout')}
    return $raw
}
$runner=Join-Path $PSScriptRoot 'PrepareNumericalResearchMapping.ps1'
& $runner -ExpandedResearchPath $ExpandedResearchPath -OutputDirectory $folder
Check ($mappingTestState.postCount -eq 1) 'Exactly one POST expected.'
$first=Get-ChildItem -LiteralPath $folder -Filter '*.json'|Select-Object -First 1
$firstHash=(Get-FileHash -LiteralPath $first.FullName).Hash
$mappingTestState.simulateFailure=$true
Reject {& $runner -ExpandedResearchPath $ExpandedResearchPath -OutputDirectory $folder}
Check ($mappingTestState.postCount -eq 2) 'Timeout must not retry POST.'
$partial=Get-ChildItem -LiteralPath $folder -Filter '*.json'|Sort-Object LastWriteTime -Descending|Select-Object -First 1
$failed=Get-Content -LiteralPath $partial.FullName -Raw|ConvertFrom-Json
Check ($failed.status -eq 'FAILED_PARTIAL_REPORT' -and $failed.failureStage -eq 'MAPPING') 'Partial checkpoint missing.'
Check ((Get-FileHash -LiteralPath $first.FullName).Hash -eq $firstHash) 'Previous report overwritten.'
$mappingTestState.healthDown=$true
Reject {& $runner -ExpandedResearchPath $ExpandedResearchPath -OutputDirectory $folder}
Check ($mappingTestState.postCount -eq 2) 'Unhealthy service must not receive POST.'
& $runner -ExpandedResearchPath $ExpandedResearchPath -SavedMappingResultPath $RawMappingResultPath -OutputDirectory $folder
Check ($mappingTestState.postCount -eq 2) 'Offline replay invoked service.'
Check (@(Get-ChildItem -LiteralPath $folder -Filter '*.json').Count -eq 4) 'One unique report per invocation expected.'
$latest=Get-ChildItem -LiteralPath $folder -Filter '*.json'|Sort-Object LastWriteTime -Descending|Select-Object -First 1
$recovered=Get-Content -LiteralPath $latest.FullName -Raw|ConvertFrom-Json
Check ($recovered.executionMode -eq 'OFFLINE_SAVED_RESPONSE_REVIEW' -and $null -eq $recovered.mappingRoundTripSeconds) 'Offline replay claimed a new Java call.'
Check ($recovered.reusedResultSha256 -eq $replay.sha256) 'Replay file hash missing.'
if($replay.data.version -eq 'NUMERICAL_RESEARCH_MAPPING_COLLECTION_V1'){
    Check ($recovered.replayMetadata.previousStatus -eq $replay.data.status) 'Prior status not retained.'
    Check ($recovered.replayMetadata.previousMappingRoundTripSeconds -eq $replay.data.mappingRoundTripSeconds) 'Prior call timing not retained.'
}
Write-Host "PASS: $script:checks mapping workflow assertions. Test evidence retained: $folder"
