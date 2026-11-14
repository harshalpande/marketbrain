#Requires -Version 7.0
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'PaytmSupervisorTransport.ps1')
. (Join-Path $PSScriptRoot 'PaytmGatewayFailureEvidence.ps1')
Set-StrictMode -Version Latest
$checks=0
function Check($Ok,$Name){if(-not $Ok){throw $Name};$script:checks++}
function Invoke-PaytmTransportCurl {
 if($script:case -eq 'exception'){throw [InvalidOperationException]::new('SECRET_MESSAGE')}
 $script:result
}
$report=[ordered]@{}
foreach($case in @('success','timeout','receive','certificate','malformed','exception','successAgain')){
 $script:case=$case
 $script:result=@{TimedOut=$false;ExitCode=0;Output='200|0|503';Error='SECRET_STDERR'}
 switch($case){
  timeout {$result.TimedOut=$true;$result.ExitCode=-1;$result.Output=''}
  receive {$result.ExitCode=56;$result.Output='200|0|000'}
  certificate {$result.ExitCode=60;$result.Output='200|20|000'}
  malformed {$result.Output='SECRET_OUTPUT'}
 }
 $threw=$false;$response=$null
 try{$response=Test-PaytmTransportTls $report}catch{$threw=$true}
 Check ($threw -eq ($case -in @('certificate','malformed','exception'))) ($case+'_ORIGINAL_POLICY')
 if(-not $threw){Check ($response.ok -eq ($case -in @('success','successAgain'))) ($case+'_HEALTH')}
 Check (($report|ConvertTo-Json -Depth 8 -Compress) -notmatch 'SECRET') ($case+'_REDACTION')
 Check ($report.lastTlsObservation.elapsedMilliseconds -ge 0) ($case+'_TIMING')
 if($case -eq 'timeout'){$first=$report.firstTlsFailure;Check ($first.timedOut -and $first.exitCode -eq -1) 'TIMEOUT_EVIDENCE'}
}
Check ($report.tlsFailureCount -eq 5 -and $report.firstTlsFailure -eq $first) 'FIRST_FAILURE_RETAINED'
Check ($report.lastTlsFailure.exceptionType -eq 'InvalidOperationException') 'LAST_FAILURE_RETAINED_AFTER_SUCCESS'
$projected=ConvertTo-PaytmWorkerEvidence $report
Check ($projected.firstTlsFailure.timedOut -and $projected.lastTlsObservation.httpStatus -eq 503 -and $projected.tlsFailureCount -eq 5) 'FAILURE_REPORT_PROJECTION'
Check (($report|ConvertTo-Json -Depth 8 -Compress).Length -lt 5000) 'BOUNDED_EVIDENCE'
foreach($pair in @(@('200|0|000|0.001|0.000|0.000|4.001','PROXY_CONNECT_ACCEPTED'),@('200|0|000|0.001|0.250|0.000|6.001','TLS_HANDSHAKE_COMPLETED'),@('200|0|503|0.001|0.250|0.400|0.410','HTTP_RESPONSE_STARTED'))){
 $script:case='phase';$script:result=@{TimedOut=$false;ExitCode=$(if($pair[1] -eq 'HTTP_RESPONSE_STARTED'){0}else{28});Output=$pair[0];Error='timeout SECRET_URL'}
 $v=Test-PaytmTransportTls $report
 Check ($v.ok -eq ($pair[1] -eq 'HTTP_RESPONSE_STARTED')) 'PHASE_POLICY_UNCHANGED'
 Check ($report.lastTlsObservation.lastCompletedStage -ceq $pair[1]) 'PHASE_CAPTURED'
 $projection=ConvertTo-PaytmWorkerEvidence $report
 Check ($projection.lastTlsObservation.tcpConnectMilliseconds -eq 1 -and $projection.lastTlsObservation.phaseMetricsParsed) 'PHASE_PROJECTED'
 Check (($projection|ConvertTo-Json -Depth 8) -notmatch 'SECRET') 'PHASE_REDACTION'
}
Write-Host "PASS: $checks TLS observation assertions; no network or native process."
