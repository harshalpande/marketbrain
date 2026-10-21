#Requires -Version 5.1
[CmdletBinding()]
param()
$ErrorActionPreference='Stop'
$source=Join-Path $PSScriptRoot '..\linux\InstallPaytmTunnelIdentity.sh'
$body=[IO.File]::ReadAllText((Resolve-Path -LiteralPath $source).Path).Replace("`r`n","`n")
$delimiter='MARKETBRAIN_TUNNEL_IDENTITY'
$entry='if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then tg_main "$@"; fi'
if($body.Contains($delimiter) -or $body.Contains([char]0) -or $body.Length -gt 24000 -or -not $body.Contains($entry)){throw 'Unexpected installer source; clipboard unchanged.'}
$body=$body.Replace($entry,'tg_main')
# SSH_CONNECTION is expanded by the verified remote admin shell, never by Windows.
$prefix='sudo -n env SSH_CONNECTION="$SSH_CONNECTION" bash'
Set-Clipboard -Value ($prefix+" <<'$delimiter'`n"+$body.TrimEnd("`r","`n")+"`n$delimiter`n")
Write-Host '[100%] Restricted tunnel identity installer copied. No remote operation performed.'
Write-Host 'Keep root/admin PuTTY windows and provider console available. Run sudo -v FIRST in the verified admin window.'
Write-Host 'Paste, review preflight, then type INSTALL-TUNNEL. Changes only the new account/key and scoped SSH policy; reloads SSH.'
Write-Host 'Proxy remains stopped. Never share private keys/passphrases. Share the ONE /tmp log and verify a fresh ADMIN login.'
