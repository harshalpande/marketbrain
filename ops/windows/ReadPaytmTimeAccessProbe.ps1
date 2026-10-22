#Requires -Version 7.0
# Runs only as a bounded local child; never starts a service or changes privileges.
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'PaytmOperationsFollowUp.ps1')
Add-Type -TypeDefinition ([IO.File]::ReadAllText((Join-Path $PSScriptRoot 'PaytmTimeAccessProbe.cs')))
[ordered]@{
    schemaVersion=1
    target='LOCAL_W32Time'
    administratorEnabled=(Test-PaytmOperationsAdministrator)
    rights=@([MarketBrain.Diagnostics.TimeServiceAccess]::Inspect())
    serviceStartInvoked=$false
    securityChanged=$false
} | ConvertTo-Json -Depth 5 -Compress
