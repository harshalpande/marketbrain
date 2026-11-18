#requires -Version 7.2
param([switch]$ResumeAfterHealthBlock)
$ErrorActionPreference='Stop'
$directory=Join-Path 'C:\MarketBrainData\Review' ('automation-recovery-'+[guid]::NewGuid().ToString('N'))
$latest='C:\MarketBrainData\Review\automation-gateway-recovery-latest.json'
$script=Join-Path $PSScriptRoot '..\windows\RepairPaytmNativeProcess.ps1'
Write-Host 'Starting one reviewed recovery and 30-minute stability observation. Leave this window open.'
try {
 $mode=if($ResumeAfterHealthBlock){'-HealthBlockedTransportResume'}else{'-CurrentSigningRecovery'}
 & (Join-Path $PSHOME 'pwsh.exe') -NoProfile -File $script $mode -OutputDirectory $directory
 $exit=$LASTEXITCODE
} finally {
 $files=@(Get-ChildItem -LiteralPath $directory -Filter 'paytm-native-recovery-*.json' -ErrorAction SilentlyContinue)
 if($files.Count -eq 1 -and $files[0].Length -le 65536){
  $bytes=[IO.File]::ReadAllBytes($files[0].FullName)
  $r=[Text.Encoding]::UTF8.GetString($bytes).TrimStart([char]0xfeff)|ConvertFrom-Json
  if($r.runId -notmatch '^[a-f0-9]{32}$' -or $r.ordersEnabled -ne $false){throw 'Recovery report contract invalid; original retained.'}
  $tmp=$latest+'.'+[guid]::NewGuid().ToString('N')+'.tmp'
  [IO.File]::WriteAllBytes($tmp,$bytes);[IO.File]::Move($tmp,$latest,$true)
  Write-Host "RESULT_READY_FOR_AUTOMATIC_COLLECTION: $($r.runId) / $($r.status)"
 }else{Write-Host 'No single bounded result available; preserve console and evidence. Do not rerun.'}
}
if($exit -ne 0){throw 'Recovery needs review; automatic report collection prepared. Do not rerun.'}
