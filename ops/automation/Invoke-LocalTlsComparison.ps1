#requires -Version 7.5
$ErrorActionPreference='Stop'
$identity=[Security.Principal.WindowsIdentity]::GetCurrent()
try {if(-not ([Security.Principal.WindowsPrincipal]::new($identity)).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)){throw 'Open elevated PowerShell 7 on the spare laptop.'}}finally{$identity.Dispose()}
$id=[guid]::NewGuid().ToString('N')
$source=Get-Content -LiteralPath (Join-Path $PSScriptRoot '../linux/TestPaytmUpstreamPath.sh') -Raw
$command="bash <<'MB_CONCURRENT_UPSTREAM'`n"+$source.Replace("`r`n","`n")+"`nmb_upstream_main '$id' 60`nMB_CONCURRENT_UPSTREAM`n"
Set-Clipboard -Value $command
Write-Host '[0%] VPS comparison command copied. Paste it into your verified admin PuTTY session.'
Write-Host "Leave PuTTY running. Copy its exact VPS_CAPTURE_STARTED=$id line back HERE within two minutes."
$watch=[Diagnostics.Stopwatch]::StartNew()
$answer=Read-Host 'Paste the VPS_CAPTURE_STARTED line'
if($answer.Trim() -cne "VPS_CAPTURE_STARTED=$id" -or $watch.Elapsed.TotalSeconds -gt 120){throw 'VPS start confirmation missing, mismatched or late. Windows gateway was not changed. Let the bounded VPS collection finish.'}
$directory=Join-Path 'C:\MarketBrainData\Review' ('automation-tls-comparison-'+$id)
$latest='C:\MarketBrainData\Review\automation-gateway-recovery-latest.json'
$script=Join-Path $PSScriptRoot '../windows/RepairPaytmNativeProcess.ps1'
Write-Host '[10%] Starting the reviewed Windows gateway once, then capturing five minutes. Application stays locked.'
$exit=1
try {
 & (Join-Path $PSHOME 'pwsh.exe') -NoProfile -File $script -ConcurrentTlsCapture -ComparisonId $id -OutputDirectory $directory
 $exit=$LASTEXITCODE
}finally{
 $files=@(Get-ChildItem -LiteralPath $directory -Filter 'paytm-native-recovery-*.json' -ErrorAction SilentlyContinue)
 if($files.Count -eq 1 -and $files[0].Length -le 65536){
  $bytes=[IO.File]::ReadAllBytes($files[0].FullName)
  $r=[Text.Encoding]::UTF8.GetString($bytes).TrimStart([char]0xfeff)|ConvertFrom-Json -DateKind String
  if($r.comparisonId -cne $id -or $r.runId -cnotmatch '^[a-f0-9]{32}$' -or $r.ordersEnabled -ne $false){throw 'Comparison report contract invalid; preserve original.'}
  $tmp=$latest+'.'+[guid]::NewGuid().ToString('N')+'.tmp'
  [IO.File]::WriteAllBytes($tmp,$bytes);[IO.File]::Move($tmp,$latest,$true)
  Write-Host "RESULT_READY_FOR_AUTOMATIC_COLLECTION: $($r.runId) / $($r.status)"
 }else{Write-Host 'No single bounded report available; preserve console and reports.'}
 Write-Host "Comparison ID: $id. Let PuTTY finish; share its one /tmp/paytm-upstream-*.json file."
}
if($exit -ne 0){throw 'Windows comparison needs review. Do not rerun or remove state; report is preserved.'}
