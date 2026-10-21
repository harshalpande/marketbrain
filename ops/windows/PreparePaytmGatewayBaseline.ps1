#Requires -Version 5.1
[CmdletBinding()]
param()
$ErrorActionPreference = 'Stop'
$source = Join-Path $PSScriptRoot '..\linux\InspectPaytmGateway.sh'
if (-not (Test-Path -LiteralPath $source -PathType Leaf)) { throw 'Missing reviewed VPS baseline script.' }
$body = [IO.File]::ReadAllText((Resolve-Path -LiteralPath $source).Path).Replace("`r`n", "`n")
$delimiter = 'MARKETBRAIN_READ_ONLY_BASELINE'
if ($body.Contains($delimiter) -or $body.Contains([char]0) -or $body.Length -gt 20000) {
    throw 'Unexpected script content; clipboard was not changed.'
}
$payload = "bash <<'$delimiter'`n" + $body.TrimEnd("`r", "`n") + "`n$delimiter`n"
Set-Clipboard -Value $payload
Write-Host '[100%] Read-only VPS command copied to your clipboard. Nothing has run on the VPS yet.'
Write-Host 'Paste into the VERIFIED PuTTY root session, then press Enter if necessary. Do not use the VNC paste box.'
Write-Host 'Expected RSA host key: SHA256:YTQ8GV8J4qOQkY4j3dGGyCTAzyR2iX/KSJoGK0p2dKI'
Write-Host 'The script only inspects local state and writes one private /tmp report. No downloads, installs, restarts or settings changes.'
Write-Host 'Share the complete output or the ONE report path printed at completion. It contains network metadata, not passwords.'
