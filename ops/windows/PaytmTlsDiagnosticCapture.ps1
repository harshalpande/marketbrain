#Requires -Version 7.0
function Get-PaytmTlsDiagnosticClock {[Diagnostics.Stopwatch]::StartNew()}
function Invoke-PaytmTlsDiagnosticCapture([string]$Id){
 $c=Get-PaytmHostContract;$clock=Get-PaytmTlsDiagnosticClock
 $report.diagnostic=[ordered]@{requiredSeconds=300;elapsedSeconds=0;captureCompleted=$false;samples=[Collections.Generic.List[object]]::new();healthySamples=0;outageSamples=0}
 $instance=$null;$previous=$null;$lastAdvance=0.0
 do{
  foreach($name in @('startup-failure.json','blocked.json')){if(Test-Path -LiteralPath (Join-Path $c.work $name)){throw 'TRANSPORT_WORKER_BLOCKED'}}
  $v=$null
  try{$v=Read-PaytmHostJson (Join-Path $c.work 'status.json')}catch [IO.FileNotFoundException]{}
  if($v){
   if($v.installationId -cne $Id -or $v.instanceId -ceq 'd1516d1bbd85469a818133aeadb29d10' -or $v.instanceId -cnotmatch '^[a-f0-9]{32}$' -or $v.brokerReady -ne $false -or $v.ordersEnabled -ne $false -or $v.failure){throw 'HOST_TLS_CAPTURE_IDENTITY_OR_SCOPE'}
   if(-not $instance){$instance=$v.instanceId}
   if($v.instanceId -cne $instance){throw 'HOST_TLS_CAPTURE_WORKER_REPLACED'}
   if($v.phase -cnotin @('CONNECTING','BACKOFF','TRANSPORT_READY')){throw 'HOST_TLS_CAPTURE_UNEXPECTED_STATE'}
   if(-not $previous -or $v.sequence -gt $previous.sequence){$lastAdvance=$clock.Elapsed.TotalSeconds}
   if($previous -and $v.sequence -lt $previous.sequence){throw 'HOST_TLS_CAPTURE_SEQUENCE_REVERSED'}
   $previous=$v
   $report.diagnostic.samples.Add((ConvertTo-PaytmWorkerEvidence $v))
   if($v.phase -ceq 'TRANSPORT_READY'){$report.diagnostic.healthySamples++}else{$report.diagnostic.outageSamples++}
  }
  if($clock.Elapsed.TotalSeconds-$lastAdvance -gt 45){throw 'TRANSPORT_HEARTBEAT_TIMEOUT'}
  $report.diagnostic.elapsedSeconds=[math]::Round($clock.Elapsed.TotalSeconds,3)
  Native-Step ('DIAGNOSTIC_CAPTURE {0:n0}/300 seconds; ready samples {1}; outage samples {2}' -f $clock.Elapsed.TotalSeconds,$report.diagnostic.healthySamples,$report.diagnostic.outageSamples) ([math]::Min(90,30+[int]($clock.Elapsed.TotalSeconds/5)))
  if($clock.Elapsed.TotalSeconds -ge 300){break}
  Start-Sleep -Seconds 5
 }while($true)
 if(-not $previous){throw 'HOST_TLS_CAPTURE_NO_WORKER'}
 $report.diagnostic.captureCompleted=$true
}
