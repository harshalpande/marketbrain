#Requires -Version 7.0
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'PaytmTimeServiceRepair.ps1')
$source=Get-Content (Join-Path $PSScriptRoot 'ReviewPaytmTimeSource.ps1') -Raw
$source=$source.Replace(". (Join-Path `$PSScriptRoot 'PaytmGatewayAccount.ps1')",'').Replace(". (Join-Path `$PSScriptRoot 'PaytmTimeServiceRepair.ps1')",'')
$source=$source.Replace('$PSScriptRoot',("'"+$PSScriptRoot.Replace("'","''")+"'"))
$root=Join-Path ([IO.Path]::GetTempPath()) ('mb-source-fixture-'+[guid]::NewGuid().ToString('N'));$null=New-Item -ItemType Directory $root
$e=Join-Path $root 'evidence.json';'{}'|Set-Content $e
$source=$source.Replace('8BC1797E59257F2526950E5DC2CDD9A3BF9FA80A090D8AC457D8CB8801095757',(Get-FileHash $e).Hash)
function Assert-PaytmAccountPath($p){$p}
function Get-PaytmTimeRepairSnapshot {@{state='Running';startType=2;ntpServer='time.windows.com,0x9'}}
function Get-WinEvent {param($FilterHashtable,$MaxEvents,$ErrorAction) if($script:scenario -eq 'events'){throw 'fixture event access denied'};@()}
function Invoke-PaytmTimeRepairNative($Tool,$Arguments,$Seconds){
 if($Arguments -notmatch '^/(query|stripchart) '){throw 'Unexpected mutating command'}
 if($script:scenario -eq 'timeout' -and $Arguments -match 'stripchart'){throw 'fixture timeout'}
 $output=switch($Arguments){'/query /status /verbose'{if($script:scenario -eq 'unsync'){"Leap Indicator: 3`nStratum: 0`nLast Sync Error: 1"}else{"Leap Indicator: 0`nStratum: 3`nLast Sync Error: 0"}};'/query /source'{'time.windows.com,0x9'};default{'fixture'}}
 @{arguments=$Arguments;exitCode=0;output=$output}
}
$count=0
foreach($script:scenario in @('sync','unsync','timeout','events')){
 $out=Join-Path $root $script:scenario
 & ([scriptblock]::Create($source)) -EvidencePath $e -OutputDirectory $out
 $r=Get-Content (Get-ChildItem $out -Filter '*.json').FullName -Raw|ConvertFrom-Json
 $expected=switch($script:scenario){sync{'TIME_SOURCE_REPORTS_SYNC_ALIGNMENT_PENDING'};unsync{'TIME_SOURCE_CAPTURED_SYNC_UNCONFIRMED'};default{'TIME_SOURCE_PARTIAL_REVIEW_REQUIRED'}}
 if($r.status -ne $expected -or $r.commands.Count -ne 7 -or $r.alignmentVerified -or $r.clockChangedByScript){throw "Collector fixture failed: $script:scenario"};$count++
}
Write-Host "PASS: $count read-only collector workflows."
