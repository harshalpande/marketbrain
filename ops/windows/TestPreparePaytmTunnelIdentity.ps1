#Requires -Version 5.1
$ErrorActionPreference='Stop'
$capture=[pscustomobject]@{Value=$null}
function Set-Clipboard { param([string]$Value) $capture.Value=$Value }
& (Join-Path $PSScriptRoot 'PreparePaytmTunnelIdentity.ps1')
$prefix='sudo -n env SSH_CONNECTION="$SSH_CONNECTION" bash'
if(-not $capture.Value.StartsWith($prefix+" <<'MARKETBRAIN_TUNNEL_IDENTITY'`n")){throw 'Remote connection metadata/privilege wrapper missing'}
if(-not $capture.Value.EndsWith("`ntg_main`nMARKETBRAIN_TUNNEL_IDENTITY`n")){throw 'Missing entry/delimiter'}
if($capture.Value.Contains("`r")){throw 'Unexpected CR'}
if(-not $capture.Value.Contains('read -r answer </dev/tty')){throw 'Confirmation missing'}
if(-not $capture.Value.Contains('${PIPESTATUS[@]}')){throw 'Variables expanded prematurely'}
if(-not $capture.Value.Contains('TUNNEL_IDENTITY_INSTALLED_FRESH_ADMIN_LOGIN_AND_TUNNEL_TESTS_PENDING')){throw 'Missing bounded status'}
if($capture.Value -match 'systemctl (start|restart|enable) '){throw 'Unexpected service activation/restart'}
if(-not $capture.Value.Contains('SHA256:fRekz3jjaYJxnK5dDXMzq9mDEB4Z3BEHhjfNJCx07UI')){throw 'Wrong public key fingerprint'}
Write-Host 'PASS: eight mocked clipboard assertions; no clipboard changes or remote execution.'
