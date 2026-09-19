#Requires -Version 5.1
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'NumericalResearchMapping.ps1')
$checks=0
function Check-Instant($Value,[long]$ExpectedTicks){
    $actual=ConvertTo-NumericalMappingUtc $Value
    if($actual.Kind -ne [DateTimeKind]::Utc -or $actual.Ticks -ne $ExpectedTicks){throw 'Instant changed.'}
    $script:checks++
}
function Reject-Instant($Value){
    $rejected=$false;try{[void](ConvertTo-NumericalMappingUtc $Value)}catch{$rejected=$true}
    if(-not $rejected){throw 'Ambiguous/invalid timestamp was accepted.'};$script:checks++
}
$utc=[datetime]::new(2025,10,27,10,30,0,[DateTimeKind]::Utc)
$savedCulture=[Threading.Thread]::CurrentThread.CurrentCulture
try{
    foreach($culture in @('en-US','en-IN','en-GB','de-DE','fr-FR')){
        [Threading.Thread]::CurrentThread.CurrentCulture=[Globalization.CultureInfo]::GetCultureInfo($culture)
        Check-Instant '2025-10-27T10:30:00Z' $utc.Ticks
        Check-Instant '2025-10-27T16:00:00+05:30' $utc.Ticks
        Check-Instant '2025-10-27T06:30:00-04:00' $utc.Ticks
        Check-Instant $utc $utc.Ticks
        Check-Instant ($utc.ToLocalTime()) $utc.Ticks
        Check-Instant ([DateTimeOffset]::new(2025,10,27,16,0,0,[TimeSpan]::FromMinutes(330))) $utc.Ticks
        Check-Instant '2025-10-27T10:30:00.0000001Z' ($utc.Ticks+1)
        Reject-Instant ([datetime]::SpecifyKind($utc,[DateTimeKind]::Unspecified))
        Reject-Instant '2025-10-27T10:30:00'
        Reject-Instant '10/27/2025 10:30:00'
        Reject-Instant '2025-02-30T10:30:00Z'
        Reject-Instant $null
        Reject-Instant 12345
    }
}finally{[Threading.Thread]::CurrentThread.CurrentCulture=$savedCulture}
$decoded='{"timestamp":"2025-10-27T10:30:00Z"}'|ConvertFrom-Json
Check-Instant $decoded.timestamp $utc.Ticks
if((Get-Command ConvertFrom-Json).Parameters.ContainsKey('DateKind')){
    foreach($mode in @('Default','Local','Utc','Offset','String')){
        $decoded='{"timestamp":"2025-10-27T16:00:00+05:30"}'|ConvertFrom-Json -DateKind $mode
        Check-Instant $decoded.timestamp $utc.Ticks
    }
}
Write-Host "PASS: $checks timestamp assertions on PowerShell $($PSVersionTable.PSVersion); local zone $([TimeZoneInfo]::Local.Id)."
