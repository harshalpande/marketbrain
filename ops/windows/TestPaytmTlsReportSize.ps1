#Requires -Version 7.0
[CmdletBinding()]param([Parameter(Mandatory)][string]$BaseReportPath)
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'PaytmGatewaySession.ps1')
. (Join-Path $PSScriptRoot 'PaytmGatewayFailureEvidence.ps1')
. (Join-Path $PSScriptRoot 'PaytmTlsDiagnosticCapture.ps1')
$tmp=Join-Path ([IO.Path]::GetTempPath()) ('mb-report-size-'+[guid]::NewGuid().ToString('N'))
$null=New-Item -ItemType Directory -Path $tmp
try{
 $report=Get-Content -LiteralPath $BaseReportPath -Raw|ConvertFrom-Json -AsHashtable
 $v=$report.nativeRecovery.first
 # Include all new phase metrics and retained first/last failures in a realistic base.
 foreach($name in @('lastTlsObservation','firstTlsFailure','lastTlsFailure')){
  $v[$name].phaseMetricsParsed=$true;$v[$name].lastCompletedStage='PROXY_CONNECT_ACCEPTED';$v[$name].nativeErrorCategory='CERTIFICATE_OR_REVOCATION'
  foreach($field in @('tcpConnectMilliseconds','tlsHandshakeCompletedMilliseconds','firstByteMilliseconds','curlTotalMilliseconds')){$v[$name][$field]=99999999L}
 }
 $rows=[Collections.Generic.List[object]]::new()
 1..61|ForEach-Object {$rows.Add((ConvertTo-PaytmWorkerEvidence ([pscustomobject]$v)))}
 $report.diagnostic=@{samples=$rows}
 $failed=$false;try{Write-PaytmSessionReport (Join-Path $tmp 'old.json') $report}catch{if($_.Exception.Message -cne 'SESSION_REPORT_TOO_LARGE'){throw};$failed=$true}
 if(-not $failed){throw 'OLD_FAILURE_NOT_REPRODUCED'}
 $report.diagnostic=[ordered]@{samples=[Collections.Generic.List[object]]::new();samplesDropped=0}
 for($i=1;$i -le 200;$i++){
  $v.sequence=$i
  Add-PaytmTlsDiagnosticSample $report.diagnostic ([pscustomobject]$v)
  # Exercise the real writer every time, including the final full report.
  Write-PaytmSessionReport (Join-Path $tmp 'fixed.json') $report
 }
 if($report.diagnostic.samples.Count -ne 64 -or $report.diagnostic.samplesDropped -ne 136 -or $report.diagnostic.firstObservation.sequence -ne 1 -or $report.diagnostic.lastObservation.sequence -ne 200){throw 'BOUNDED_RETENTION_FAILED'}
 $bytes=(Get-Item (Join-Path $tmp 'fixed.json')).Length
 if($bytes -ge 49152){throw 'REPORT_HEADROOM_TOO_SMALL'}
 Write-Host "PASS: old overflow reproduced; 200 real report writes; 64 sample cap, first/last preserved; final size $bytes bytes (limit 65536)."
}finally{
 $full=[IO.Path]::GetFullPath($tmp);$parent=[IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\')+'\'
 if(-not $full.StartsWith($parent,[StringComparison]::OrdinalIgnoreCase) -or [IO.Path]::GetFileName($full) -notmatch '^mb-report-size-[a-f0-9]{32}$'){throw 'UNSAFE_FIXTURE_CLEANUP'}
 if(Test-Path -LiteralPath $full){Remove-Item -LiteralPath $full -Recurse -Force}
}
