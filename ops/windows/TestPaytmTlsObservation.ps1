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
Check (($report|ConvertTo-Json -Depth 8 -Compress).Length -lt 2500) 'BOUNDED_EVIDENCE'
Write-Host "PASS: $checks TLS observation assertions; no network or native process."
