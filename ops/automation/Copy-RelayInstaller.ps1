#requires -Version 7.2
$ErrorActionPreference='Stop'
$relay=[Convert]::ToBase64String([IO.File]::ReadAllBytes((Join-Path $PSScriptRoot 'relay.py')))
$installer=[Convert]::ToBase64String([IO.File]::ReadAllBytes((Join-Path $PSScriptRoot 'install_relay.py')))
$command=@'
sudo -n bash <<'MB_AUTOMATION_INSTALL'
set -eu
umask 077
tmp=$(mktemp -d /tmp/marketbrain-automation.XXXXXXXX)
trap 'rm -f -- "$tmp/relay.py" "$tmp/install_relay.py"; rmdir -- "$tmp"' EXIT
printf '%s' '__RELAY__' | base64 -d > "$tmp/relay.py"
printf '%s' '__INSTALLER__' | base64 -d > "$tmp/install_relay.py"
python3 "$tmp/install_relay.py"
MB_AUTOMATION_INSTALL
'@
$command=$command.Replace('__RELAY__',$relay).Replace('__INSTALLER__',$installer)
Set-Clipboard -Value $command
Write-Host 'Installer copied. In verified administrator PuTTY: run sudo -v, then paste the clipboard command.'
Write-Host 'It installs only the maintenance relay on TCP 18443. Keep the two private pairing lines out of chat and Git.'
