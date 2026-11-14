#Requires -Version 7.0
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'PaytmTlsDiagnosticCapture.ps1')
. (Join-Path $PSScriptRoot 'PaytmGatewayFailureEvidence.ps1')
function Get-PaytmHostContract {@{work='fixture'}}
function Get-PaytmTlsDiagnosticClock {$script:clock=@{Elapsed=@{TotalSeconds=0.0}};$clock}
function Start-Sleep {param($Seconds) $clock.Elapsed.TotalSeconds+=$Seconds}
function Native-Step {}
function Test-Path {param($LiteralPath) $case -eq 'blocked'}
function Read-PaytmHostJson {
 $script:sequence++
 @{installationId=$(if($case -eq 'identity'){'wrong'}else{'fixture'});instanceId=$(if($case -eq 'replaced' -and $sequence -gt 1){'b'*32}else{'a'*32});processId=100;sequence=$(if($case -eq 'stale'){1}elseif($case -eq 'reverse'){100-$sequence}else{$sequence});phase=$(if($case -eq 'outage'){'BACKOFF'}else{'TRANSPORT_READY'});failure=$null;brokerReady=$false;ordersEnabled=$false}
}
$checks=0
foreach($case in @('ready','outage','identity','replaced','blocked','stale','reverse','oldWorker')){
 $report=[ordered]@{};$sequence=0;$failed=$false
 if($case -eq 'oldWorker'){$report.capturePreviousInstance='a'*32}
 try{Invoke-PaytmTlsDiagnosticCapture fixture}catch{$failed=$true}
 if($failed -ne ($case -notin @('ready','outage'))){throw "OUTCOME_$case"};$checks++
 if(-not $failed){if(-not $report.diagnostic.captureCompleted -or $report.diagnostic.elapsedSeconds -lt 300 -or $report.diagnostic.samples.Count -ne 61){throw "CAPTURE_$case"};$checks++}
 if($case -eq 'outage' -and $report.diagnostic.healthySamples -ne 0){throw 'OUTAGE_COUNTED_HEALTHY'}
}
Write-Host "PASS: $checks capture assertions across eight fake-clock workflows; no runtime actions."
