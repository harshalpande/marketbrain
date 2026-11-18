#requires -Version 7.2
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'Automation.Diagnostics.ps1')
$exe=(Get-Process -Id $PID).Path
$encoded=[Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes("[Console]::Out.Write('A' * 3000); [Console]::Error.Write('sample'); exit 7"))
$result=Invoke-AutomationNativeObservation $exe @('-NoProfile','-EncodedCommand',$encoded) 10
if ($result.exitCode -ne 7 -or $result.stdout.Length -ne 2048 -or $result.stderr -ne 'sample' -or $result.timedOut) { throw 'Native exit/output bounding failed' }
$encoded=[Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes('Start-Sleep -Seconds 30'))
$result=Invoke-AutomationNativeObservation $exe @('-NoProfile','-EncodedCommand',$encoded) 1
if (-not $result.timedOut -or $result.elapsedSeconds -gt 8) { throw 'Native timeout was not bounded' }
$script:calls=@()
function Get-AutomationGatewayObservation { return @{readOnly=$true} }
function Invoke-AutomationNativeObservation([string]$Executable,[string[]]$Arguments,[int]$TimeoutSeconds) {
    $script:calls+=,@{executable=$Executable;arguments=$Arguments;timeout=$TimeoutSeconds}
    return @{exitCode=28;timedOut=$false;stdout='000|';stderr='fixture timeout'}
}
$result=Get-AutomationPaytmObservation
if ($result.ordersEnabled -or $result.permissionChanges -or $script:calls.Count -ne 4) { throw 'Unexpected diagnostic scope' }
foreach($call in $script:calls[2..3]) {
    if ($call.arguments[-1] -ne 'https://developer.paytmmoney.com/' -or '--head' -notin $call.arguments -or 'http://127.0.0.1:18889' -notin $call.arguments -or '--insecure' -in $call.arguments) { throw 'Transport target/verification changed' }
}
if ($result.proxyObservations[0].connectTimeoutSeconds -ne 2 -or $result.proxyObservations[1].connectTimeoutSeconds -ne 8 -or $result.proxyObservations[0].observation.exitCode -ne 28) { throw 'Comparison lost failure evidence' }
Write-Host 'PASS: native exit/output bounds, forced timeout, fixed verified transport target, preserved failures and diagnostic-only scope.'
