#Requires -Version 5.1
$ErrorActionPreference='Stop'
$capture=[pscustomobject]@{Value=$null}
function Set-Clipboard { param([string]$Value) $capture.Value=$Value }
& (Join-Path $PSScriptRoot 'PreparePaytmLoopbackProxy.ps1')
if(-not $capture.Value.StartsWith("sudo -n bash <<'MARKETBRAIN_PROXY_STAGE'`n")){throw 'Wrong privilege/heredoc wrapper'}
if(-not $capture.Value.EndsWith("`npg_main`nMARKETBRAIN_PROXY_STAGE`n")){throw 'Missing entry point/delimiter'}
if($capture.Value.Contains("`r")){throw 'Unexpected CR'}
if(-not $capture.Value.Contains('read -r answer </dev/tty')){throw 'Confirmation missing'}
if(-not $capture.Value.Contains('${PIPESTATUS[@]}')){throw 'Shell variables expanded'}
if(-not $capture.Value.Contains('pg_filter final > /etc/marketbrain-paytm-gateway/allowlist')){throw 'Final allowlist restoration missing'}
if(-not $capture.Value.Contains('VPS_PROXY_STAGED_TESTED_STOPPED_APPLICATION_NOT_CONNECTED')){throw 'Missing scoped success marker'}
Write-Host 'PASS: seven mocked clipboard assertions; no clipboard changes or remote execution.'
