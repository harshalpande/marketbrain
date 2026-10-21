#Requires -Version 5.1
[CmdletBinding()]
param()
$ErrorActionPreference='Stop'
$source=Join-Path $PSScriptRoot '..\linux\InstallVpsAdminKey.sh'
$body=[IO.File]::ReadAllText((Resolve-Path -LiteralPath $source).Path).Replace("`r`n","`n")
$delimiter='MARKETBRAIN_ADMIN_INSTALL'
if($body.Contains($delimiter) -or $body.Contains([char]0) -or $body.Length -gt 20000){throw 'Unexpected installer content; clipboard unchanged.'}
# stdin/heredoc execution needs the explicit entry point, unlike execution from a file.
$entry='if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then mb_main "$@"; fi'
if(-not $body.Contains($entry)){throw 'Installer entry point changed; clipboard unchanged.'}
$body=$body.Replace($entry,'mb_main')
Set-Clipboard -Value ("bash <<'$delimiter'`n"+$body.TrimEnd("`r","`n")+"`n$delimiter`n")
Write-Host '[100%] Installer copied. Nothing has executed on the VPS.'
Write-Host 'Paste into the verified root PuTTY session. Type INSTALL only after reviewing the prompt.'
Write-Host 'Creates one sudo-capable administrator and installs sudo if absent; no root/SSH/firewall changes.'
Write-Host 'Account password is set afterward using passwd; never share it or the private PPK.'
