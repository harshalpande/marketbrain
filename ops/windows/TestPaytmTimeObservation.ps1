#Requires -Version 5.1
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'PaytmTimeObservation.ps1')
function New-Fixture {
 [pscustomobject]@{version=1;bootId='boot';sequence=1;frequency=10000000L;startTicks=10000000000L;endTicks=10001000000L;status=@{exitCode=0;output="Time since Last Good Sync Time: 10.0s`n"};source=@{exitCode=0;output='time.windows.com'};service=@{state='Running';startType=2}}
}
$v=New-Fixture;$r=ConvertFrom-TimeObservation $v 'boot' 10020000000L 10000000L
if($r.ageSeconds -ne 2 -or $r.status.output -notmatch '12.000000s'){throw 'Snapshot age not included'}
$count=1
foreach($case in @('boot','frequency','old','future','reversed','badstatus','stopped','oversized','noage')){
 $v=New-Fixture
 switch($case){'boot'{$v.bootId='other'} 'frequency'{$v.frequency=1} 'old'{$v.startTicks=9000000000L} 'future'{$v.endTicks=11000000000L} 'reversed'{$v.startTicks=10015000000L} 'badstatus'{$v.status.exitCode=5} 'stopped'{$v.service.state='Stopped'} 'oversized'{$v.source.output='x'*1025} 'noage'{$v.status.output='unknown'}}
 $failed=$false;try{$null=ConvertFrom-TimeObservation $v 'boot' 10020000000L 10000000L}catch{$failed=$_.Exception.Message -like 'TIME_OBSERVER_*'}
 if(-not $failed){throw "Invalid observation accepted: $case"};$count++
}
Write-Host "TIME_OBSERVATION_PASSED: $count protocol cases; no system changes."
# Validate the trust boundary against real Windows ACL objects, without setting ACLs.
function Get-Item {return @{Attributes=[IO.FileAttributes]::Normal}}
function Get-Acl {return $script:fixtureAcl}
foreach($untrusted in @($false,$true)){
 $script:fixtureAcl=[Security.AccessControl.DirectorySecurity]::new()
 $script:fixtureAcl.SetOwner([Security.Principal.SecurityIdentifier]::new('S-1-5-32-544'))
 $rights=if($untrusted){'Modify'}else{'ReadAndExecute'}
 $script:fixtureAcl.AddAccessRule([Security.AccessControl.FileSystemAccessRule]::new([Security.Principal.SecurityIdentifier]::new('S-1-5-32-545'),$rights,'Allow'))
 $rejected=$false;try{Assert-TimeObservationAcl 'fixture'}catch{$rejected=$_.Exception.Message -eq 'TIME_OBSERVER_WRITABLE'}
 if($rejected -ne $untrusted){throw 'ACL write boundary failed'}
}
Write-Host 'TIME_OBSERVATION_ACL_PASSED: read allowed; non-admin write rejected.'

$v=New-Fixture;$v.bootId='2026-11-20T01:02:03.1234567Z'
$parsed=ConvertFrom-TimeObservationJson ($v|ConvertTo-Json -Depth 5)
if($parsed.bootId -isnot [string] -or $parsed.bootId -cne $v.bootId){throw 'ISO boot identity changed during JSON parsing'}
$null=ConvertFrom-TimeObservation $parsed $v.bootId 10020000000L 10000000L
Write-Host 'TIME_OBSERVATION_JSON_PASSED: ISO boot identity preserved.'
