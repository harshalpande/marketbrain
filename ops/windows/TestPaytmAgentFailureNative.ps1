#Requires -Version 7.0
# Development-machine read-only integration check. No gateway account or key access.
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'PaperRuntimeReview.ps1')
$body=[IO.File]::ReadAllText((Join-Path $PSScriptRoot 'ReadPaytmAgentFailure.ps1'))
$from=[DateTimeOffset]::UtcNow.AddMinutes(-15).ToString('o');$to=[DateTimeOffset]::UtcNow.ToString('o')
$wrapper="& {`n"+$body+"`n} -StartUtc '"+$from+"' -EndUtc '"+$to+"'"
$encoded=[Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($wrapper))
$r=Invoke-PaperRuntimeProcess 'C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe' @('-NoLogo','-NoProfile','-NonInteractive','-EncodedCommand',$encoded) (Resolve-Path (Join-Path $PSScriptRoot '../..')).Path 90
if($r.exitCode -ne 0){throw "AGENT_NATIVE_READER_EXIT_$($r.exitCode)"}
$v=$r.stdout|ConvertFrom-Json -ErrorAction Stop
if(-not $v.readOnly -or $v.events.Count -ne 6 -or -not $v.serviceBefore.querySucceeded -or -not $v.serviceAfter.querySucceeded){
 $v|ConvertTo-Json -Depth 8
 throw 'AGENT_NATIVE_READER_INVALID'
}
if($v.historicalCauseEstablished -or $v.gatewayAccountSigningTested -or $r.stdout.Length -gt 40000){throw 'AGENT_NATIVE_SCOPE_INVALID'}
[pscustomobject]@{status='LOCAL_PS7_TO_PS5_AGENT_READER_PASSED';elapsedSeconds=$r.elapsedSeconds;servicePresent=$v.serviceBefore.present;serviceState=$v.serviceBefore.state;eventQueries=$v.events.Count;queryGaps=@($v.events|Where-Object {-not $_.querySucceeded}).Count;outputCharacters=$r.stdout.Length;stderrCharacters=$r.stderr.Length;spareRuntimeTested=$false}|ConvertTo-Json
