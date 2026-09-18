#Requires -Version 5.1
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$FeatureEvidencePath,
    [string]$BaseUrl='http://127.0.0.1:8080',
    [string]$OutputDirectory='C:\MarketBrainData\Review'
)
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'LlmCleanupInventory.ps1')
. (Join-Path $PSScriptRoot 'NumericalHistoryEvidence.ps1')
. (Join-Path $PSScriptRoot 'NumericalFeatureCalendar.ps1')
$base=Assert-LlmInventoryLoopback $BaseUrl
if(-not(Test-Path -LiteralPath $OutputDirectory)){[void](New-Item -ItemType Directory -Path $OutputDirectory)}
$path=Join-Path (Resolve-Path -LiteralPath $OutputDirectory).Path ('numerical-price-evidence-'+(Get-Date -Format 'yyyyMMdd-HHmmss')+'-'+[guid]::NewGuid().ToString('N').Substring(0,12)+'.json')
if(Test-Path -LiteralPath $path){throw 'Refusing report overwrite.'}
$timer=[Diagnostics.Stopwatch]::StartNew()
$report=[pscustomobject]@{
    version='NUMERICAL_PRICE_COLLECTION_V1';status='RUNNING';createdAtUtc=[DateTime]::UtcNow.ToString('o');updatedAtUtc=$null;elapsedSeconds=0
    inputFileName=$null;inputSha256=$null;scriptSha256=(Get-FileHash -LiteralPath $PSCommandPath).Hash
    calendarReview=$null;featureWindows=$null;result=$null;summary=$null;failureStage=$null;failureMessage=$null;errorType=$null;httpStatus=$null
    events=[Collections.Generic.List[object]]::new()
}
function Save-PriceProgress([int]$Percent,[string]$Message){
    $report.elapsedSeconds=[math]::Round($timer.Elapsed.TotalSeconds,3)
    $report.events.Add([pscustomobject]@{atUtc=[DateTime]::UtcNow.ToString('o');percent=$Percent;message=$Message})
    Save-NumericalHistoryReport $report $path
    Write-Host "[$Percent%] $Message"
    Write-Progress -Id 103 -Activity 'Stored quality and price evidence (no training)' -Status $Message -PercentComplete $Percent
}
try{
    $stage='INPUT';Save-PriceProgress 0 'Reading saved feature evidence; no recalculation or market-data download.'
    $file=Get-Item -LiteralPath $FeatureEvidencePath
    if($file.PSIsContainer -or ($file.Attributes -band [IO.FileAttributes]::ReparsePoint) -or $file.Length -gt 16MB){throw 'Regular input file <=16 MiB required.'}
    $bytes=[IO.File]::ReadAllBytes($file.FullName);if($bytes.Length -gt 16MB){throw 'Input grew beyond limit.'}
    $sha=[Security.Cryptography.SHA256]::Create()
    try{$report.inputSha256=([BitConverter]::ToString($sha.ComputeHash($bytes))).Replace('-','')}finally{$sha.Dispose()}
    $report.inputFileName=$file.Name
    $inputEvidence=[Text.Encoding]::UTF8.GetString($bytes).TrimStart([char]0xFEFF) | ConvertFrom-Json
    $calendar=Get-Content -LiteralPath (Join-Path $PSScriptRoot '..\data\nse-cm-calendar-20250401-20260605-v1.json') -Raw | ConvertFrom-Json
    $report.calendarReview=Get-NumericalFeatureCalendarReview $inputEvidence $calendar
    if($report.calendarReview.blockedRowCount -ne 0){throw 'Resolve blocked calendar/feature rows before price linkage.'}
    $payload=$inputEvidence.snapshot.payload
    if(($payload.offset -isnot [int] -and $payload.offset -isnot [long]) -or $payload.offset -lt 0 -or $payload.offset -gt 499 -or
       ($payload.limit -isnot [int] -and $payload.limit -isnot [long]) -or $payload.limit -lt 1 -or $payload.limit -gt 4){throw 'Invalid saved pagination.'}
    $report.featureWindows=@(foreach($item in $payload.instruments){foreach($row in $item.rows){[pscustomobject]@{instrumentId=$item.instrumentId;symbol=$item.symbol;fromDate=$row.featureFrom;throughDate=$row.decisionDate}}})
    $from=($report.featureWindows.fromDate | Sort-Object | Select-Object -First 1)
    $runId=[guid]$payload.datasetRunId
    $stage='HEALTH';Save-PriceProgress 20 'Checking Java service health.'
    $health=Invoke-RestMethod -Uri ($base+'/actuator/health') -Method Get -TimeoutSec 10 -MaximumRedirection 0 -ErrorAction Stop
    if($health.status -ne 'UP'){throw 'Service not UP.'}
    $stage='QUERY';Save-PriceProgress 35 'Reading bounded stored jobs, chunks, action events and review ledger; no provider calls.'
    $uri=$base+'/api/v1/training/numerical-price-evidence?datasetRunId='+$runId.ToString()+"&fromDate=$from&offset=$($payload.offset)&limit=$($payload.limit)"
    $result=Invoke-RestMethod -Uri $uri -Method Get -TimeoutSec 60 -MaximumRedirection 0 -ErrorAction Stop
    $report.result=$result;$stage='VALIDATION'
    if($result.version -ne 'NUMERICAL_PRICE_EVIDENCE_V1' -or $result.status -ne 'PRICE_POLICY_REVIEW_REQUIRED' -or
       [string]$result.datasetRunId -ne $runId.ToString() -or $result.datasetManifestHash -ne $payload.datasetManifestHash -or
       $result.fromDate -ne $from -or $result.throughDate -ne $payload.asOf -or $result.offset -ne $payload.offset -or $result.limit -ne $payload.limit){throw 'Response scope/manifest mismatch.'}
    foreach($flag in @('trainingAuthorized','databaseWritesPerformed')){if($result.$flag -isnot [bool] -or $result.$flag){throw 'Unsafe response flag.'}}
    foreach($counter in @('modelCallCount','providerCallCount','ordersCreated')){if(($result.$counter -isnot [int] -and $result.$counter -isnot [long]) -or $result.$counter -ne 0){throw 'Unexpected side effect.'}}
    if($result.partial -isnot [bool] -or $result.jobCatalogTruncated -isnot [bool] -or $result.jobsObserved -lt 0 -or $result.jobsObserved -gt 21 -or $result.jobCatalogTruncated -ne ($result.jobsObserved -gt 20)){throw 'Invalid job/cap metadata.'}
    $items=@($result.instruments);$expected=@($payload.instruments)
    if($items.Count -ne $expected.Count){throw 'Instrument count mismatch.'}
    for($i=0;$i -lt $items.Count;$i++){
        $item=$items[$i]
        if($item.instrumentId -ne $expected[$i].instrumentId -or $item.symbol -ne $expected[$i].symbol){throw 'Instrument identity/order mismatch.'}
        if($item.partial -isnot [bool] -or @($item.jobLinks).Count -gt 20 -or @($item.chunks).Count -gt 201 -or @($item.corporateActions).Count -gt 501 -or
           $item.resolutionEventsInspected -lt 0 -or $item.resolutionEventsInspected -gt 1001 -or @($item.latestRelevantResolutions).Count -gt $item.resolutionEventsInspected){throw 'Invalid bounded evidence counts.'}
        $expectedPartial=$result.jobCatalogTruncated -or @($item.chunks).Count -gt 200 -or @($item.corporateActions).Count -gt 500 -or $item.resolutionEventsInspected -gt 1000
        if($item.partial -ne $expectedPartial){throw 'Instrument partial flag mismatch.'}
        if('NO_VERIFIED_ADJUSTMENT_FACTORS_OR_EXECUTABLE_PRICE_BINDING' -notin $item.remainingGates){throw 'Missing price-policy gate.'}
    }
    if($result.partial -ne (@($items | Where-Object partial).Count -gt 0)){throw 'Overall partial flag mismatch.'}
    $report.summary=[pscustomobject]@{
        instrumentCount=$items.Count;partial=$result.partial
        instrumentsWithJobLinks=@($items | Where-Object {@($_.jobLinks).Count -gt 0}).Count
        storedCorporateActionCount=($items | ForEach-Object {@($_.corporateActions).Count} | Measure-Object -Sum).Sum
        overlappingActiveExclusionCount=($items.overlappingActiveExclusionCount | Measure-Object -Sum).Sum
        revokedFindingCount=($items.revokedFindingCount | Measure-Object -Sum).Sum
        trainingAuthorized=$false;pricePolicyApproved=$false
    }
    $report.status=if($result.partial){'PARTIAL_PRICE_POLICY_REVIEW_REQUIRED'}else{'PRICE_POLICY_REVIEW_REQUIRED'}
    Save-PriceProgress 100 'Evidence captured; review unresolved gates before any labels or training.'
    $report.summary | Format-List
}catch{
    $report.status='FAILED_PARTIAL_REPORT';$report.failureStage=$stage;$report.errorType=$_.Exception.GetType().Name
    $report.failureMessage=if($stage -in @('INPUT','VALIDATION')){$_.Exception.Message}else{'Collection/save failed; inspect failureStage, errorType and httpStatus. No automatic retry.'}
    if($_.Exception.PSObject.Properties['Response'] -and $_.Exception.Response -and $_.Exception.Response.PSObject.Properties['StatusCode']){$report.httpStatus=[int]$_.Exception.Response.StatusCode}
    try{Save-PriceProgress 100 'Stopped; share partial report. Do not rerun acquisition.'}catch{Write-Warning 'Save failed; retain previous JSON/pending file.'}
    throw
}finally{Write-Progress -Id 103 -Activity 'Stored quality and price evidence (no training)' -Completed;Write-Host "Share: $path"}
