#Requires -Version 7.0
[CmdletBinding()]param(
 [Parameter(Mandatory=$true)][string]$ContainerEvidencePath,
 [string]$OutputDirectory='C:\MarketBrainData\Review'
)
$ErrorActionPreference='Stop'
& (Join-Path $PSScriptRoot 'TestPaytmTunnelBundle.ps1') -ApplicationRoute -ContainerEvidencePath $ContainerEvidencePath -OutputDirectory $OutputDirectory
