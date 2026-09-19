#Requires -Version 5.1
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$FeatureEvidencePath,
    [Parameter(Mandatory)][string]$PriceEvidencePath,
    [string]$OutputDirectory='C:\MarketBrainData\Review'
)
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'NumericalReadinessBundle.ps1')
. (Join-Path $PSScriptRoot 'NumericalHistoryEvidence.ps1')
if(-not(Test-Path -LiteralPath $OutputDirectory)){[void](New-Item -ItemType Directory -Path $OutputDirectory)}
$path=Join-Path (Resolve-Path -LiteralPath $OutputDirectory).Path ('numerical-readiness-bundle-'+(Get-Date -Format 'yyyyMMdd-HHmmss')+'-'+[guid]::NewGuid().ToString('N').Substring(0,12)+'.json')
if(Test-Path -LiteralPath $path){throw 'Refusing report overwrite.'}
$timer=[Diagnostics.Stopwatch]::StartNew()
$report=[pscustomobject]@{
    version='NUMERICAL_READINESS_BUNDLE_V1';status='RUNNING';createdAtUtc=[DateTime]::UtcNow.ToString('o');updatedAtUtc=$null;elapsedSeconds=0
    inputs=@();calendar=$null;calendarSha256=$null;result=$null;failureStage=$null;errorType=$null
    scriptSha256=(Get-FileHash -LiteralPath $PSCommandPath).Hash
    reviewerSha256=(Get-FileHash -LiteralPath (Join-Path $PSScriptRoot 'NumericalReadinessBundle.ps1')).Hash
    calendarReviewerSha256=(Get-FileHash -LiteralPath (Join-Path $PSScriptRoot 'NumericalFeatureCalendar.ps1')).Hash
    events=[Collections.Generic.List[object]]::new()
}
function Save-BundleProgress([int]$Percent,[string]$Message){
    $report.elapsedSeconds=[math]::Round($timer.Elapsed.TotalSeconds,3)
    $report.events.Add([pscustomobject]@{atUtc=[DateTime]::UtcNow.ToString('o');percent=$Percent;message=$Message})
    Save-NumericalHistoryReport $report $path
    Write-Host "[$Percent%] $Message"
    Write-Progress -Id 104 -Activity 'Coordinated numerical readiness preflight' -Status $Message -PercentComplete $Percent
}
try{
    $stage='INPUTS';Save-BundleProgress 0 'Reading two saved reports; no server, download or model required.'
    $features=Read-NumericalBundleInput $FeatureEvidencePath
    $report.inputs+=@([pscustomobject]@{role='FEATURE';name=$features.name;sha256=$features.sha256})
    Save-BundleProgress 20 'Feature input captured.'
    $price=Read-NumericalBundleInput $PriceEvidencePath
    $report.inputs+=@([pscustomobject]@{role='PRICE';name=$price.name;sha256=$price.sha256})
    $calendar=Read-NumericalBundleInput (Join-Path $PSScriptRoot '..\data\nse-cm-calendar-20250401-20260605-v1.json')
    $report.calendar=$calendar.data;$report.calendarSha256=$calendar.sha256
    $stage='REVIEW';Save-BundleProgress 40 'Checking price gates, outcome windows, feature inputs and split overlaps together.'
    $report.result=Get-NumericalReadinessBundle $features.data $price.data $features.sha256 $calendar.data
    $report.status=$report.result.status
    Save-BundleProgress 100 'Preflight complete. Unverified inputs remain blocked; no training performed.'
    $report.result.summary | Format-List
}catch{
    $report.status='FAILED_PARTIAL_REPORT';$report.failureStage=$stage;$report.errorType=$_.Exception.GetType().Name
    try{Save-BundleProgress 100 'Stopped; retain and share this partial report.'}catch{Write-Warning 'Save failed; retain previous JSON/pending file.'}
    throw
}finally{Write-Progress -Id 104 -Activity 'Coordinated numerical readiness preflight' -Completed;Write-Host "Share: $path"}
