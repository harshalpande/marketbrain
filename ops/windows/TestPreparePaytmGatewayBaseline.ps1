#Requires -Version 5.1
[CmdletBinding()]
param()
$ErrorActionPreference='Stop'
$capture=[pscustomobject]@{Value=$null}
function Set-Clipboard { param([string]$Value) $capture.Value=$Value }
& (Join-Path $PSScriptRoot 'PreparePaytmGatewayBaseline.ps1')
if (-not $capture.Value.StartsWith("bash <<'MARKETBRAIN_READ_ONLY_BASELINE'`n")) { throw 'Wrong quoted heredoc.' }
if (-not $capture.Value.EndsWith("`nMARKETBRAIN_READ_ONLY_BASELINE`n")) { throw 'Missing delimiter.' }
if ($capture.Value.Contains("`r")) { throw 'Unexpected carriage returns.' }
if (-not $capture.Value.Contains('${BASH_SOURCE[0]:-}')) { throw 'Bash variable was expanded.' }
Write-Host 'PASS: four clipboard payload assertions. Clipboard was mocked; no VPS access.'
