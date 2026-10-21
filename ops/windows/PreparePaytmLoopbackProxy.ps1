#Requires -Version 5.1
[CmdletBinding()]
param()
$ErrorActionPreference='Stop'
$source=Join-Path $PSScriptRoot '..\linux\StagePaytmLoopbackProxy.sh'
$body=[IO.File]::ReadAllText((Resolve-Path -LiteralPath $source).Path).Replace("`r`n","`n")
$delimiter='MARKETBRAIN_PROXY_STAGE'
$entry='if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then pg_main "$@"; fi'
if($body.Contains($delimiter) -or $body.Contains([char]0) -or $body.Length -gt 24000 -or -not $body.Contains($entry)){throw 'Unexpected staging source; clipboard unchanged.'}
$body=$body.Replace($entry,'pg_main')
Set-Clipboard -Value ("sudo -n bash <<'$delimiter'`n"+$body.TrimEnd("`r","`n")+"`n$delimiter`n")
Write-Host '[100%] VPS proxy staging command copied. No remote operation performed.'
Write-Host 'In the verified marketbrain-admin PuTTY window: run sudo -v FIRST, then paste and confirm STAGE.'
Write-Host 'Installs a loopback-only proxy, tests restrictions/TLS/egress/restart, then stops it. No application or SSH changes.'
Write-Host 'Do not enter broker credentials. Share the ONE /tmp log printed by the script; stop on failure.'
