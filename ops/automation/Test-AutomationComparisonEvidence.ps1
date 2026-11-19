#requires -Version 7.5
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'Automation.Diagnostics.ps1')
$v=[pscustomobject]@{comparisonId=('a'*32);diagnostic=[pscustomobject]@{captureCompleted=$true;requiredSeconds=300;healthySamples=30;outageSamples=31;samples=@(1..80|ForEach-Object{[pscustomobject]@{sequence=$_;observedUtc='2026-11-19T10:00:00Z';tls_observedUtc='2026-11-19T10:00:00Z';tls_connectStatus=200;tls_tlsHandshakeCompletedMilliseconds=0;tls_firstByteMilliseconds=0;tls_curlTotalMilliseconds=4012;tlsElapsedMs=4119;tlsExitCode=28;tlsStage='PROXY_CONNECT_ACCEPTED';secret='NEVER_COPY'}})}}
$r=Select-AutomationGatewayFields $v
$json=$r|ConvertTo-Json -Depth 12
if($r.comparisonId -cne ('a'*32) -or $r.diagnostic.samples.Count -ne 64 -or -not $r.diagnostic.captureCompleted -or $r.diagnostic.samples[0].tls_connectStatus -ne 200 -or -not $r.diagnostic.samples[0].ContainsKey('tls_observedUtc') -or $json.Contains('NEVER_COPY') -or [Text.Encoding]::UTF8.GetByteCount($json) -gt 60000){throw 'Comparison evidence bound or filtering failed'}
Write-Host 'PASS: comparison timestamp/metrics retained, 64-sample bound, secrets omitted'
