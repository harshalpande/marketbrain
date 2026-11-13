#Requires -Version 7.0
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'ReadPaytmConnectivityEvents.ps1') -LibraryOnly
$script:case='events';$script:queries=0;$checks=0
function Check($Ok,$Name){if(-not $Ok){throw $Name};$script:checks++}
function Get-WinEvent {
 [CmdletBinding()]param($ListLog,$FilterHashtable,$MaxEvents)
 if($ListLog){
  if($script:case -eq 'missing'){throw [InvalidOperationException]::new('SECRET')}
  return @{IsEnabled=($script:case -ne 'disabled')}
 }
 $script:queries++
 if($MaxEvents -ne 32 -or ($FilterHashtable.EndTime-$FilterHashtable.StartTime).TotalMinutes -ne 9){throw 'UNBOUNDED_QUERY'}
 if($script:case -eq 'empty'){Write-Error -Message 'No events' -ErrorId NoMatchingEventsFound;return}
 if($script:case -eq 'denied'){Write-Error -Message 'SECRET' -ErrorId AccessDenied;return}
 $count=if($script:case -eq 'limit'){32}else{1}
 for($i=0;$i -lt $count;$i++){
  [pscustomobject]@{Id=8003;RecordId=17;TimeCreated=[DateTime]::Parse('2026-11-13T06:25:00Z').ToUniversalTime();Message='SECRET SSID';Properties=@('SECRET PASSWORD')}
 }
}
foreach($case in @('events','empty','denied','disabled','missing','limit')){
 $script:case=$case;$script:queries=0;$rows=@(Get-PaytmConnectivityEvents)
 Check ($rows.Count -eq 4) ($case+'_CHANNELS')
 Check (($rows|ConvertTo-Json -Depth 8 -Compress) -notmatch 'SECRET|PASSWORD|SSID') ($case+'_REDACTION')
 if($case -in @('disabled','missing')){Check ($queries -eq 0) ($case+'_NO_QUERY')}
 elseif($case -in @('events','empty','limit')){Check (@($rows|Where-Object {-not $_.querySucceeded}).Count -eq 0) ($case+'_QUERY_SUCCESS')}
 else{Check (@($rows|Where-Object {$_.querySucceeded -or -not $_.errorType}).Count -eq 0) 'DENIAL_NOT_EMPTY'}
 if($case -eq 'limit'){Check (@($rows|Where-Object {-not $_.limitReached}).Count -eq 0) 'TRUNCATION_VISIBLE'}
}
Write-Host "PASS: $checks connectivity event assertions; no real event log or network access."
