#Requires -Version 5.1
$ErrorActionPreference='Stop'
$capture=[pscustomobject]@{Value=$null}
function Set-Clipboard { param([string]$Value) $capture.Value=$Value }
& (Join-Path $PSScriptRoot 'PrepareVpsAdminInstallation.ps1')
if(-not $capture.Value.StartsWith("bash <<'MARKETBRAIN_ADMIN_INSTALL'`n")){throw 'Wrong heredoc'}
if(-not $capture.Value.EndsWith("`nmb_main`nMARKETBRAIN_ADMIN_INSTALL`n")){throw 'Missing entry point or delimiter'}
if($capture.Value.Contains("`r")){throw 'Unexpected carriage return'}
if(-not $capture.Value.Contains('${SSH_CONNECTION:-}')){throw 'Bash variable expanded'}
if(-not $capture.Value.Contains('read -r answer </dev/tty')){throw 'Confirmation lost'}
if(-not $capture.Value.Contains('AAAAC3NzaC1lZDI1NTE5AAAAIPOVSxqHLjDm2skmoTLWNmCnjAA7Vh6SNf8lHqc0GSOu')){throw 'Public key changed'}
Write-Host 'PASS: six clipboard assertions. No actual clipboard update or VPS execution.'
