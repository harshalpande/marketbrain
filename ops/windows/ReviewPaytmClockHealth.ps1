#Requires -Version 7.0
[CmdletBinding()]param(
 [string]$EvidencePath='C:\MarketBrainData\Review\paytm-clock-snapshot-20261115-012410-af351b5a10e64d6b8b72a14d5598667b.json',
 [string]$OutputDirectory='C:\MarketBrainData\Review')
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'PaytmGatewayAccount.ps1')
. (Join-Path $PSScriptRoot 'PaytmTimeServiceRepair.ps1')
. (Join-Path $PSScriptRoot 'PaytmClockHealth.ps1')
$timer=[Diagnostics.Stopwatch]::StartNew();$run=[guid]::NewGuid().ToString('N')
$null=Assert-PaytmAccountPath $OutputDirectory;$null=New-Item -ItemType Directory -Path $OutputDirectory -Force
$path=Join-Path $OutputDirectory ('paytm-clock-health-'+$run+'.json')
$r=@{version=1;runId=$run;status='REVIEW_REQUIRED';failure=$null;rounds=@();assessment=$null;elapsedSeconds=0;settingsChanged=$false;clockChangedByScript=$false;ordersEnabled=$false;sourceHashes=@{}}
function Save-Health {$r.elapsedSeconds=$timer.Elapsed.TotalSeconds;[IO.File]::WriteAllText($path,($r|ConvertTo-Json -Depth 16),[Text.UTF8Encoding]::new($false))}
try{
 Save-Health;$null=Assert-PaytmAccountPath $EvidencePath
 if((Get-FileHash -LiteralPath $EvidencePath).Hash -cne '75B582A215A014EB2D15EED94F1932358E59C607C20466D841A368BA85A84281'){throw 'CLOCK_HEALTH_EVIDENCE_MISMATCH'}
 foreach($n in @('ReviewPaytmClockHealth.ps1','PaytmClockHealth.ps1','PaytmTimeServiceRepair.ps1')){$r.sourceHashes[$n]=(Get-FileHash -LiteralPath (Join-Path $PSScriptRoot $n)).Hash}
 Invoke-PaytmClockHealthBatch $r {Save-Health} {
  $wait=[Diagnostics.Stopwatch]::StartNew()
  while($wait.Elapsed.TotalSeconds -lt 30){
   Write-Progress -Activity 'Read-only clock health' -Status ('Between samples: {0:N0}/30 seconds' -f $wait.Elapsed.TotalSeconds) -PercentComplete ([math]::Min(95,10+40*$r.rounds.Count))
   Start-Sleep -Seconds 1
  }
 } {$timer.Elapsed.TotalSeconds}
}catch{$r.failure=$_.Exception.Message}
finally{Save-Health;Write-Progress -Activity 'Read-only clock health' -Completed;Write-Host "[100%] $($r.status)";Write-Host "Share this ONE file: $path"}
if($r.failure){throw 'Share the JSON before retrying; no repair was performed.'}
