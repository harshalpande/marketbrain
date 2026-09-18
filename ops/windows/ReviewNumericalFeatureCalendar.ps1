#Requires -Version 5.1
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$EvidencePath,
    [string]$OutputDirectory='C:\MarketBrainData\Review'
)
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'NumericalFeatureCalendar.ps1')
. (Join-Path $PSScriptRoot 'NumericalHistoryEvidence.ps1')
if(-not(Test-Path -LiteralPath $OutputDirectory)){[void](New-Item -ItemType Directory -Path $OutputDirectory)}
$path=Join-Path (Resolve-Path -LiteralPath $OutputDirectory).Path ('numerical-calendar-'+(Get-Date -Format 'yyyyMMdd-HHmmss')+'-'+[guid]::NewGuid().ToString('N').Substring(0,12)+'.json')
if(Test-Path -LiteralPath $path){throw 'Refusing to overwrite existing report.'}
$timer=[Diagnostics.Stopwatch]::StartNew()
$report=[pscustomobject]@{
    version='NUMERICAL_CALENDAR_EVIDENCE_V1';status='RUNNING';createdAtUtc=[DateTime]::UtcNow.ToString('o');updatedAtUtc=$null;elapsedSeconds=0
    inputFileName=$null;inputSha256=$null;calendarSha256=$null;calendar=$null
    scriptSha256=(Get-FileHash -LiteralPath $PSCommandPath).Hash
    reviewerSha256=(Get-FileHash -LiteralPath (Join-Path $PSScriptRoot 'NumericalFeatureCalendar.ps1')).Hash
    result=$null;failureStage=$null;failureMessage=$null;errorType=$null;events=[Collections.Generic.List[object]]::new()
}
function Save-CalendarProgress([int]$Percent,[string]$Message){
    $report.elapsedSeconds=[math]::Round($timer.Elapsed.TotalSeconds,3)
    $report.events.Add([pscustomobject]@{atUtc=[DateTime]::UtcNow.ToString('o');percent=$Percent;message=$Message})
    Save-NumericalHistoryReport $report $path
    Write-Host "[$Percent%] $Message"
    Write-Progress -Id 102 -Activity 'Offline numerical calendar review' -Status $Message -PercentComplete $Percent
}
try{
    $stage='READ_INPUT';Save-CalendarProgress 0 'Reading existing JSON only; no service, provider or model calls.'
    $inputFile=Get-Item -LiteralPath $EvidencePath
    if($inputFile.PSIsContainer -or ($inputFile.Attributes -band [IO.FileAttributes]::ReparsePoint) -or $inputFile.Length -gt 16MB){throw 'Input must be a regular file no larger than 16 MiB.'}
    # One byte read for both hash and parsing: no hash/read race against a changing checkpoint.
    $bytes=[IO.File]::ReadAllBytes($inputFile.FullName)
    if($bytes.Length -gt 16MB){throw 'Input grew beyond 16 MiB.'}
    $hash=[Security.Cryptography.SHA256]::Create()
    try{$report.inputSha256=([BitConverter]::ToString($hash.ComputeHash($bytes))).Replace('-','')}finally{$hash.Dispose()}
    $report.inputFileName=$inputFile.Name
    $evidence=[Text.Encoding]::UTF8.GetString($bytes).TrimStart([char]0xFEFF) | ConvertFrom-Json
    $stage='READ_CALENDAR';Save-CalendarProgress 20 'Loading versioned NSE circular-backed calendar.'
    $calendarPath=Join-Path $PSScriptRoot '..\data\nse-cm-calendar-20250401-20260605-v1.json'
    $report.calendarSha256=(Get-FileHash -LiteralPath $calendarPath).Hash
    $report.calendar=Get-Content -LiteralPath $calendarPath -Raw | ConvertFrom-Json
    $stage='REVIEW';Save-CalendarProgress 40 'Checking all feature-window dates and referenced candle IDs.'
    $report.result=Get-NumericalFeatureCalendarReview $evidence $report.calendar
    $report.status=$report.result.status
    Save-CalendarProgress 100 'Review complete. Training remains disabled; share this one JSON.'
    $report.result | Select-Object status,instrumentCount,rowCount,matchedRowCount,blockedRowCount,trainingAuthorized | Format-List
}catch{
    $report.status='FAILED_PARTIAL_REPORT';$report.failureStage=$stage;$report.errorType=$_.Exception.GetType().Name
    $report.failureMessage=if($stage -eq 'REVIEW'){$_.Exception.Message}else{'Unable to read or save bounded evidence. Check file path/size/JSON and errorType.'}
    try{Save-CalendarProgress 100 'Stopped; preserve the partial report. Original evidence unchanged.'}catch{Write-Warning 'Save failed; retain previous JSON/pending file.'}
    throw
}finally{Write-Progress -Id 102 -Activity 'Offline numerical calendar review' -Completed;Write-Host "Share: $path"}
