#Requires -Version 5.1
[CmdletBinding()]param(
    [Parameter(Mandatory=$true)][string]$OperationsEvidencePath,
    [string]$OutputDirectory='C:\MarketBrainData\Review'
)
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'PaytmOperationsElevation.ps1')
Start-PaytmOperationsElevatedReview -Runner (Join-Path $PSScriptRoot 'ReviewPaytmOperationsFollowUp.ps1') -Evidence $OperationsEvidencePath -OutputDirectory $OutputDirectory
