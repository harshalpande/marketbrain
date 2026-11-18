#requires -Version 7.2
$ErrorActionPreference='Stop'
$script=[IO.File]::ReadAllText((Join-Path $PSScriptRoot 'repair_relay_permissions.sh')).Replace("`r`n","`n")
Set-Clipboard -Value ("sudo -n bash <<'MB_RELAY_PERMISSION_REPAIR'`n"+$script+"`nMB_RELAY_PERMISSION_REPAIR`n")
Write-Host 'Repair copied. In verified administrator PuTTY run sudo -v, then paste.'
Write-Host 'Only public program permissions and the automation service are repaired; existing pairing, certificate, queue and Paytm gateway are preserved.'
