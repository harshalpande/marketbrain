#Requires -Version 7.0
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'ReadPaytmAgentFailure.ps1') -LibraryOnly
$checks=0;$mode='running'
function Check($Ok,$Name){if(-not $Ok){throw "AGENT_EVIDENCE_TEST_$Name"};$script:checks++}
function Get-CimInstance {
 [CmdletBinding()]param($ClassName,$Filter,$OperationTimeoutSec)
 Check ($ClassName -eq 'Win32_Service' -and $Filter -ceq "Name='ssh-agent'" -and $OperationTimeoutSec -eq 10) 'EXACT_BOUNDED_SERVICE_QUERY'
 if($mode -eq 'denied'){throw [UnauthorizedAccessException]::new('PRIVATE_ERROR')}
 if($mode -eq 'missing'){return}
 @{State=if($mode -eq 'stopped'){'Stopped'}else{'Running'};StartMode='Auto';ProcessId=123;ExitCode=0;ServiceSpecificExitCode=0;StartName='LocalSystem';PathName='"C:\Windows\System32\OpenSSH\ssh-agent.exe"';DisplayName='OpenSSH Authentication Agent'}
}
foreach($mode in @('running','stopped','missing','denied')){
 $r=Get-PaytmAgentService
 Check ($r.querySucceeded -eq ($mode -ne 'denied')) 'SERVICE_QUERY_RESULT'
 if($mode -eq 'running'){Check ($r.state -eq 'Running' -and $r.expectedExecutable -and $r.runsAsLocalSystem) 'RUNNING'}
 if($mode -eq 'stopped'){Check ($r.state -eq 'Stopped') 'STOPPED_NOT_RUNNING'}
 if($mode -eq 'missing'){Check (-not $r.present -and $null -eq $r.state) 'MISSING_NOT_HEALTHY'}
 if($mode -eq 'denied'){Check ($null -eq $r.present -and $r.errorType -eq 'UnauthorizedAccessException') 'DENIED_NOT_MISSING'}
 Check (-not ($r|ConvertTo-Json).Contains('PRIVATE_')) 'SERVICE_REDACTION'
}
function New-Event([string]$Service='OpenSSH Authentication Agent'){
 $e=[pscustomobject]@{Id=7036;RecordId=12;TimeCreated=[DateTime]::UtcNow;FixtureService=$Service}
 $e|Add-Member -MemberType ScriptMethod -Name ToXml -Value {return ('<Event><EventData><Data Name="param1">'+$this.FixtureService+'</Data><Data Name="param2">stopped</Data><Data Name="param3">%%1067</Data><Data Name="User">PRIVATE_USER</Data><Data Name="CommandLine">PRIVATE_SECRET</Data></EventData></Event>')}
 $e
}
$r=ConvertTo-PaytmAgentEvent (New-Event) $true
Check ($r.approvedValues.Count -eq 2 -and $r.approvedValues[0] -eq 'stopped') 'SERVICE_EVENT'
Check (-not ($r|ConvertTo-Json).Contains('PRIVATE_')) 'EVENT_REDACTION'
Check ($null -eq (ConvertTo-PaytmAgentEvent (New-Event 'Unrelated service') $true)) 'UNRELATED_SERVICE_OMITTED'
Check ((ConvertTo-PaytmAgentEvent (New-Event) $false).PSObject.Properties.Name.Count -eq 3) 'OTHER_EVENTS_ONLY_ID_TIME'
function Get-WinEvent {
 [CmdletBinding()]param($ListLog,$FilterHashtable,$MaxEvents)
 if($ListLog){
  if($mode -eq 'denied'){throw [UnauthorizedAccessException]::new('PRIVATE_ERROR')}
  return @{IsEnabled=($mode -ne 'disabled')}
 }
 Check ($MaxEvents -le 128 -and ($FilterHashtable.EndTime-$FilterHashtable.StartTime).TotalMinutes -eq 15) 'BOUNDED_EVENT_QUERY'
 if($mode -eq 'empty'){Write-Error -Message 'PRIVATE_NO_EVENTS' -ErrorId NoMatchingEventsFound -Category ObjectNotFound;return}
 if($mode -eq 'queryDenied'){Write-Error -Message 'PRIVATE_ERROR' -ErrorId AccessDenied -Category PermissionDenied;return}
 $count=if($mode -eq 'limit'){$MaxEvents}else{1}
 1..$count|ForEach-Object {New-Event}
}
foreach($mode in @('empty','denied','disabled','queryDenied','limit','events')){
 $r=@(Get-PaytmAgentEvents '2026-11-05T18:33:00Z' '2026-11-05T18:48:00Z')
 Check ($r.Count -eq 6) 'SIX_EVENT_SOURCES'
 Check (@($r|Where-Object querySucceeded).Count -eq $(if($mode -in @('empty','limit','events')){6}else{0})) 'QUERY_COMPLETENESS'
 Check (@($r|Where-Object limitReached).Count -eq $(if($mode -eq 'limit'){6}else{0})) 'LIMIT_REPORTED'
 Check (-not ($r|ConvertTo-Json -Depth 8).Contains('PRIVATE_')) 'LOG_REDACTION'
}
foreach($end in @('2026-11-05T18:30:00Z','2026-11-05T19:30:00Z')){
 $threw=$false;try{Get-PaytmAgentEvents '2026-11-05T18:33:00Z' $end}catch{$threw=$_.Exception.Message -eq 'AGENT_EVENT_WINDOW_INVALID'}
 Check $threw 'INVALID_WINDOW_REJECTED'
}
[pscustomobject]@{status='AGENT_SERVICE_AND_EVENT_TESTS_PASSED';assertions=$checks;runtimeApisMocked=$true}|ConvertTo-Json
