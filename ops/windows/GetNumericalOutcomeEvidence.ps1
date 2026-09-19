#Requires -Version 5.1
[CmdletBinding()]
param([Parameter(Mandatory)][string]$FeatureEvidencePath,[string]$BaseUrl='http://127.0.0.1:8080',[string]$OutputDirectory='C:\MarketBrainData\Review',[string]$ExistingOutcomeReportPath)
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'NumericalOutcomeEvidence.ps1')
. (Join-Path $PSScriptRoot 'NumericalHistoryEvidence.ps1')
. (Join-Path $PSScriptRoot 'LlmCleanupInventory.ps1')
$base=Assert-LlmInventoryLoopback $BaseUrl
if(-not(Test-Path -LiteralPath $OutputDirectory)){[void](New-Item -ItemType Directory -Path $OutputDirectory)}
$path=Join-Path (Resolve-Path -LiteralPath $OutputDirectory).Path ('numerical-outcomes-'+(Get-Date -Format 'yyyyMMdd-HHmmss')+'-'+[guid]::NewGuid().ToString('N').Substring(0,12)+'.json')
if(Test-Path -LiteralPath $path){throw 'Refusing report overwrite.'}
$timer=[Diagnostics.Stopwatch]::StartNew()
$report=[pscustomobject]@{
    version='NUMERICAL_OUTCOME_COLLECTION_V1';status='RUNNING';createdAtUtc=[DateTime]::UtcNow.ToString('o');updatedAtUtc=$null;elapsedSeconds=0
    inputFileName=$null;inputSha256=$null;reusedReportSha256=$null;calendar=$null;extension=$null;calendarSha256=$null;extensionSha256=$null
    scriptSha256=(Get-FileHash -LiteralPath $PSCommandPath).Hash;reviewerSha256=(Get-FileHash -LiteralPath (Join-Path $PSScriptRoot 'NumericalOutcomeEvidence.ps1')).Hash
    labelReviewerSha256=(Get-FileHash -LiteralPath (Join-Path $PSScriptRoot 'NumericalReadinessBundle.ps1')).Hash
    calendarReviewerSha256=(Get-FileHash -LiteralPath (Join-Path $PSScriptRoot 'NumericalFeatureCalendar.ps1')).Hash
    outcome=$null;review=$null;failureStage=$null;errorType=$null;httpStatus=$null;events=[Collections.Generic.List[object]]::new()
}
function Save-OutcomeProgress([int]$Percent,[string]$Message){
    $report.elapsedSeconds=[math]::Round($timer.Elapsed.TotalSeconds,3);$report.events.Add([pscustomobject]@{atUtc=[DateTime]::UtcNow.ToString('o');percent=$Percent;message=$Message})
    Save-NumericalHistoryReport $report $path;Write-Host "[$Percent%] $Message"
    Write-Progress -Id 105 -Activity 'Bounded stored outcome evidence' -Status $Message -PercentComplete $Percent
}
try{
    $stage='INPUT';Save-OutcomeProgress 0 'Reading saved features; no feature recalculation or history download.'
    $f=Read-NumericalBundleInput $FeatureEvidencePath;$report.inputFileName=$f.name;$report.inputSha256=$f.sha256
    $c=Read-NumericalBundleInput (Join-Path $PSScriptRoot '..\data\nse-cm-calendar-20250401-20260605-v1.json')
    $x=Read-NumericalBundleInput (Join-Path $PSScriptRoot '..\data\nse-cm-outcome-calendar-20260606-20260717-v1.json')
    $report.calendar=$c.data;$report.calendarSha256=$c.sha256;$report.extension=$x.data;$report.extensionSha256=$x.sha256
    $initial=Get-NumericalFeatureCalendarReview $f.data $c.data
    if($initial.blockedRowCount -ne 0){throw 'Saved feature windows must pass before outcome collection.'}
    [void](Get-NumericalOutcomeSessions $c.data $x.data)
    $p=$f.data.snapshot.payload
    if($p.asOf -ne '2026-06-05' -or ($p.offset -isnot [int] -and $p.offset -isnot [long]) -or $p.offset -lt 0 -or $p.offset -gt 499 -or
       ($p.limit -isnot [int] -and $p.limit -isnot [long]) -or $p.limit -lt 1 -or $p.limit -gt 4){throw 'Unsupported saved scope; no automatic query.'}
    $from=($p.instruments.rows.featureFrom | Sort-Object | Select-Object -First 1)
    if($ExistingOutcomeReportPath){
        $stage='REUSE';Save-OutcomeProgress 25 'Reusing previously captured outcome report; no service calls.'
        $saved=Read-NumericalBundleInput $ExistingOutcomeReportPath
        if($saved.data.version -ne 'NUMERICAL_OUTCOME_COLLECTION_V1' -or $saved.data.inputSha256 -ne $f.sha256 -or $null -eq $saved.data.outcome){throw 'Reuse input does not match saved feature hash.'}
        $report.reusedReportSha256=$saved.sha256;$report.outcome=$saved.data.outcome
    }else{
        $stage='HEALTH';Save-OutcomeProgress 25 'Checking service health.'
        $health=Invoke-RestMethod -Uri ($base+'/actuator/health') -TimeoutSec 10 -MaximumRedirection 0 -ErrorAction Stop
        if($health.status -ne 'UP'){throw 'Service not UP.'}
        $stage='QUERY';Save-OutcomeProgress 40 'Reading only June 6-July 17 stored bars and extended quality/action evidence; no provider/model calls.'
        $uri=$base+"/api/v1/training/numerical-outcome-evidence?datasetRunId=$($p.datasetRunId)&featureFrom=$from&throughDate=$($x.data.coverageThrough)&offset=$($p.offset)&limit=$($p.limit)"
        $report.outcome=Invoke-RestMethod -Uri $uri -TimeoutSec 90 -MaximumRedirection 0 -ErrorAction Stop
    }
    $stage='REVIEW';Save-OutcomeProgress 80 'Response persisted; validating outcome paths without modifying feature inputs.'
    $report.review=Get-NumericalOutcomeReview $f.data $report.outcome $c.data $x.data
    $report.status=$report.review.status
    Save-OutcomeProgress 100 'Outcome evidence captured. Price policy and training authorization remain blocked.'
    $report.review.summary | Format-List
}catch{
    $report.status='FAILED_PARTIAL_REPORT';$report.failureStage=$stage;$report.errorType=$_.Exception.GetType().Name
    if($_.Exception.PSObject.Properties['Response'] -and $_.Exception.Response -and $_.Exception.Response.PSObject.Properties['StatusCode']){$report.httpStatus=[int]$_.Exception.Response.StatusCode}
    try{Save-OutcomeProgress 100 'Stopped; share the partial report. No automatic database retry.'}catch{Write-Warning 'Save failed; retain previous JSON/pending file.'}
    throw
}finally{Write-Progress -Id 105 -Activity 'Bounded stored outcome evidence' -Completed;Write-Host "Share: $path"}
