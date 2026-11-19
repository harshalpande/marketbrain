#requires -Version 7.5
$ErrorActionPreference='Stop'
# One attended relay code upgrade. No pairing reset, new account or gateway change.
$relay=[IO.File]::ReadAllBytes((Join-Path $PSScriptRoot 'relay.py'))
$updater=[IO.File]::ReadAllBytes((Join-Path $PSScriptRoot 'update_relay.py'))
$hash=[Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($relay)).ToLowerInvariant()
$command=@"
sudo python3 - <<'MB_AUTOMATION_UPGRADE'
import base64, pathlib, subprocess, tempfile
with tempfile.TemporaryDirectory(prefix='mb-relay-update-') as d:
    p=pathlib.Path(d)
    (p/'relay.py').write_bytes(base64.b64decode('$([Convert]::ToBase64String($relay))'))
    (p/'update.py').write_bytes(base64.b64decode('$([Convert]::ToBase64String($updater))'))
    subprocess.run(['python3',str(p/'update.py'),str(p/'relay.py'),'$hash'],check=True)
MB_AUTOMATION_UPGRADE
"@
Set-Clipboard -Value $command
Write-Host 'Relay upgrade command copied. In the verified admin PuTTY session run sudo -v, then paste the clipboard and press Enter.'
Write-Host 'Expected: RELAY_TEST_EXECUTION_UPDATED. Pairing and existing jobs are retained.'
Write-Host 'Then run Update-AutomationDiagnostics.ps1 -PreserveCompletedPendingResult in elevated PowerShell 7 on the spare laptop.'
