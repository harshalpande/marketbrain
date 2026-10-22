#Requires -Version 7.0
[CmdletBinding()]param(
    [Parameter(Mandatory=$true)][string]$OperationsEvidencePath,
    [string]$OutputDirectory='C:\MarketBrainData\Review'
)
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'PaytmWindowsTimeAccess.ps1')
$run=[guid]::NewGuid().ToString('N');$timer=[Diagnostics.Stopwatch]::StartNew()
$report=[ordered]@{schemaVersion=1;runId=$run;startedUtc=[DateTimeOffset]::UtcNow.ToString('o');status='REVIEW_REQUIRED';scope='LOCAL_WINDOWS_TIME_READ_ONLY_ACCESS_DIAGNOSIS';priorEvidence=$null;inspection=$null;failure=$null;elapsedSeconds=0;clockChanged=$false;serviceStartInvoked=$false;securityChanged=$false;vpsAccessed=$false;packagesInstalled=$false;brokerCredentialsUsed=$false;ordersEnabled=$false}
$null=New-Item -ItemType Directory -Path $OutputDirectory -Force
$path=Join-Path $OutputDirectory ("paytm-windows-time-access-{0}-{1}.json" -f (Get-Date -Format 'yyyyMMdd-HHmmss'),$run)
try{
    Write-Host '[5%] Windows-only diagnosis. No start/resync, permission changes, VPS commands or application restart.'
    $report.priorEvidence=Assert-PaytmTimeAccessEvidence $OperationsEvidencePath
    $report.inspection=Invoke-PaytmTimeAccessInspection
    $report.status=if($report.inspection.probeFailure){'TIME_ACCESS_PARTIAL_REVIEW_REQUIRED'}else{'TIME_ACCESS_CAPTURED_REPAIR_REVIEW_PENDING'}
}catch{
    $report.failure=if($_.Exception.Message -cmatch '^OPS_[A-Z_]+$'){$_.Exception.Message}else{'OPS_TIME_ACCESS_CAPTURE_FAILED'}
}finally{
    $timer.Stop();$report.elapsedSeconds=[math]::Round($timer.Elapsed.TotalSeconds,3)
    $stream=[IO.File]::Open($path,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::None)
    try{$bytes=[Text.Encoding]::UTF8.GetBytes(($report|ConvertTo-Json -Depth 12));$stream.Write($bytes,0,$bytes.Length)}finally{$stream.Dispose()}
    Write-Progress -Activity 'Windows Time access diagnosis' -Completed
    Write-Host "[100%] $($report.status); elapsed=$($report.elapsedSeconds)s"
    Write-Host "Share this ONE file: $path"
    Write-Host 'No repair or clock accuracy claimed. Do not repeat the VPS refresh or reset Windows service permissions.'
}
if($report.failure){throw $report.failure}
