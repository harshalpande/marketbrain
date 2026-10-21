#Requires -Version 5.1
[CmdletBinding()]
param(
    [ValidateSet('Admin','Gateway')]
    [string]$Purpose='Admin'
)
$ErrorActionPreference='Stop'
$candidates=@()
$onPath=Get-Command puttygen.exe -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
if ($onPath) { $candidates += $onPath.Source }
foreach ($root in @($env:ProgramFiles,${env:ProgramFiles(x86)})) {
    if ($root) { $candidates += (Join-Path $root 'PuTTY\puttygen.exe') }
}
$executable=$null
foreach ($candidate in $candidates) {
    if (Test-Path -LiteralPath $candidate -PathType Leaf) { $executable=$candidate; break }
}
if (-not $executable) { throw 'PuTTYgen was not found. Stop and share this message; no tool was downloaded or installed.' }
Write-Host '[100%] Opening the interactive PuTTYgen window with Ed25519 and SHA256 selected.'
Write-Host 'No key has been generated or installed by this script. Click Generate, set a strong passphrase, and save the private .ppk locally outside the repository.'
if ($Purpose -eq 'Gateway') {
    Write-Host 'Create a NEW key. Comment: marketbrain-paytm-gateway. Save as marketbrain-paytm-gateway.ppk.'
    Write-Host 'Do not load, overwrite or reuse the administrator key. This separate key is for the planned restricted tunnel only.'
    Write-Host 'Initial verification will be interactive; this does not enable unattended startup or install server restrictions.'
} else {
    Write-Host 'Comment: marketbrain-vps-admin. Save as marketbrain-vps-admin.ppk without overwriting an existing key.'
}
Write-Host 'Keep the existing PuTTY session open. Do not change VPS SSH settings yet.'
Write-Host 'Share only the one-line public key beginning ssh-ed25519, never the .ppk file or passphrase.'
# Deliberately visible: the owner must generate and protect their private key interactively.
Start-Process -FilePath $executable -ArgumentList @('-t','ed25519','-E','sha256') -WindowStyle Normal | Out-Null
