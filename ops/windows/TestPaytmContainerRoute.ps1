#Requires -Version 5.1
[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)][string]$TunnelEvidencePath,
    [string]$ApplicationContainerId,
    [string]$JavaBinDirectory,
    [string]$OutputDirectory='C:\MarketBrainData\Review'
)
$ErrorActionPreference='Stop'
& (Join-Path $PSScriptRoot 'TestPaytmTunnelBundle.ps1') -ContainerRoute -TunnelEvidencePath $TunnelEvidencePath `
    -ApplicationContainerId $ApplicationContainerId -JavaBinDirectory $JavaBinDirectory -OutputDirectory $OutputDirectory
