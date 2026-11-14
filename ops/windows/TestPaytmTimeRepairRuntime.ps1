#Requires -Version 5.1
# Run in a fresh -NoProfile Windows PowerShell process. Read-only integration test.
$ErrorActionPreference='Stop'
$initiallyLoaded=$null -ne ('System.ServiceProcess.ServiceController' -as [type])
. (Join-Path $PSScriptRoot 'PaytmTimeServiceRepair.ps1')
# Calls the real snapshot path before any service cmdlet/module can preload its assembly.
$v=Get-PaytmTimeRepairSnapshot
if(-not $v.state -or $v.startType -notin @(2,3,4) -or $v.sddl -notmatch '^D:'){throw 'RUNTIME_SNAPSHOT_INVALID'}
Initialize-PaytmTimeRepairRuntime
if([System.ServiceProcess.ServiceControllerStatus]::Running -ne 4){throw 'RUNTIME_ENUM_INVALID'}
$c=[System.ServiceProcess.ServiceController]::new('W32Time')
try{if($c.ServiceName -ne 'W32Time'){throw 'RUNTIME_CONTROLLER_INVALID'}}finally{$c.Dispose()}
Write-Host "PASS: fresh-process real snapshot, enum and controller; initiallyLoaded=$initiallyLoaded; no service mutation."
