#Requires -Version 5.1
[CmdletBinding()]
param(
    [ValidateSet('Auto','Java','Docker')][string]$Runtime='Auto',
    [string]$OutputDirectory='C:\MarketBrainData\Review',
    [ValidateRange(5,300)][int]$TimeoutSeconds=120
)
$ErrorActionPreference='Stop'
& (Join-Path $PSScriptRoot 'TestNumericalEvaluationEngineering.ps1') -Suite Baselines @PSBoundParameters
