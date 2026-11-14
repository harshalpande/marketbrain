#Requires -Version 7.0
[CmdletBinding()]param(
 [string]$EvidencePath='C:\MarketBrainData\Review\paytm-time-repair-75e26f6dd41842c1bfbfb1a9c1d96216.json',
 [string]$OutputDirectory='C:\MarketBrainData\Review')
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'PaytmGatewayAccount.ps1')
. (Join-Path $PSScriptRoot 'PaytmTimeServiceRepair.ps1')
$run=[guid]::NewGuid().ToString('N');$timer=[Diagnostics.Stopwatch]::StartNew()
$null=Assert-PaytmAccountPath $OutputDirectory
$null=New-Item -ItemType Directory -Path $OutputDirectory -Force
$path=Join-Path $OutputDirectory ('paytm-time-source-'+$run+'.json')
$r=[ordered]@{version=1;runId=$run;status='REVIEW_REQUIRED';failure=$null;commands=@();events=@();eventFailure=$null;elapsedSeconds=0;clockChangedByScript=$false;configurationChangedByScript=$false;alignmentVerified=$false;ordersEnabled=$false;sourceHashes=@{}}
function Save-SourceReport {$r.elapsedSeconds=$timer.Elapsed.TotalSeconds;[IO.File]::WriteAllText($path,($r|ConvertTo-Json -Depth 14),[Text.UTF8Encoding]::new($false))}
try{
 Save-SourceReport
 $null=Assert-PaytmAccountPath $EvidencePath
 if((Get-FileHash -LiteralPath $EvidencePath).Hash -cne '8BC1797E59257F2526950E5DC2CDD9A3BF9FA80A090D8AC457D8CB8801095757'){throw 'TIME_SOURCE_RECEIPT_MISMATCH'}
 foreach($n in @('ReviewPaytmTimeSource.ps1','PaytmTimeServiceRepair.ps1')){$r.sourceHashes[$n]=(Get-FileHash -LiteralPath (Join-Path $PSScriptRoot $n)).Hash}
 $r.before=Get-PaytmTimeRepairSnapshot
 if($r.before.state -cne 'Running' -or $r.before.startType -ne 2 -or $r.before.ntpServer -ine 'time.windows.com,0x9'){throw 'TIME_SOURCE_BASELINE_CHANGED'}
 $specs=@('/query /configuration /verbose','/query /peers /verbose','/query /status /verbose','/query /source','/stripchart /computer:time.windows.com /dataonly /samples:3 /period:2','/query /status /verbose','/query /source')
 for($i=0;$i -lt $specs.Count;$i++){
  $percent=10+[int](75*$i/$specs.Count)
  Write-Progress -Activity 'Read-only Windows time-source review' -PercentComplete $percent -Status $specs[$i]
  Write-Host "[$percent%] $($specs[$i])"
  try{$r.commands+=,(Invoke-PaytmTimeRepairNative 'w32tm.exe' $specs[$i] 20)}catch{$r.commands+=,@{arguments=$specs[$i];exitCode=$null;output='';failure=$_.Exception.Message}}
  Save-SourceReport
 }
 Write-Host '[90%] Latest 20 Windows Time events; no resync or configuration change'
 try{$r.events=@(Get-WinEvent -FilterHashtable @{LogName='System';ProviderName='Microsoft-Windows-Time-Service'} -MaxEvents 20 -ErrorAction Stop | ForEach-Object {@{recordId=$_.RecordId;timeCreated=$_.TimeCreated;id=$_.Id;level=$_.LevelDisplayName;message=([string]$_.Message).Substring(0,[math]::Min(4000,([string]$_.Message).Length))}})}catch{$r.eventFailure=$_.Exception.Message}
 $r.assessment=Get-PaytmTimeSyncAssessment $r.commands[5] $r.commands[6]
 $r.after=Get-PaytmTimeRepairSnapshot;Assert-PaytmTimeRepairPreserved $r.before $r.after
 if($r.after.state -cne 'Running' -or $r.after.startType -ne 2){throw 'TIME_SOURCE_FINAL_STATE_CHANGED'}
 $r.status=if($r.assessment.synchronizedReported){'TIME_SOURCE_REPORTS_SYNC_ALIGNMENT_PENDING'}else{'TIME_SOURCE_CAPTURED_SYNC_UNCONFIRMED'}
 if(@($r.commands|Where-Object {$_.failure -or $null -eq $_.exitCode -or $_.exitCode -ne 0}).Count -or $r.eventFailure){$r.status='TIME_SOURCE_PARTIAL_REVIEW_REQUIRED'}
}catch{$r.failure=$_.Exception.Message}
finally{Save-SourceReport;Write-Progress -Activity 'Read-only Windows time-source review' -Completed;Write-Host "[100%] $($r.status)";Write-Host "Share this ONE file: $path"}
if($r.failure){throw 'Collection stopped; share the JSON before retrying.'}
