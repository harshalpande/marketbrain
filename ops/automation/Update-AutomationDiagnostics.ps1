#requires -Version 7.2
$ErrorActionPreference='Stop'
$root=Join-Path $env:LOCALAPPDATA 'MarketBrainAutomation'
$installed=Join-Path $root 'runner\Start-AutomationWorker.ps1'
$source=Join-Path $PSScriptRoot 'Start-AutomationWorker.ps1'
if (-not (Test-Path -LiteralPath $installed)) { throw 'Existing runner not found. Do not initialize another account.' }
if (Test-Path -LiteralPath (Join-Path $root 'pending.json')) { throw 'Runner has pending work. Preserve it and finish that job before updating.' }
$oldHash=(Get-FileHash -LiteralPath $installed).Hash
$newHash=(Get-FileHash -LiteralPath $source).Hash
if ($oldHash -ne 'C6FFB38A54DFC1A8BC7A0ED685F3F2C7EF68F24900CA4AEA027C2FF2D7A55783' -and $oldHash -ne $newHash) { throw 'Installed runner differs from reviewed baseline. Stop for review.' }
$identity=[Security.Principal.WindowsIdentity]::GetCurrent().Name
$targets=@(Get-CimInstance Win32_Process -Filter "Name='pwsh.exe'" | Where-Object { $_.CommandLine -and $_.CommandLine.Contains('"'+$installed+'"') })
foreach($target in $targets) {
    $owner=Invoke-CimMethod -InputObject $target -MethodName GetOwner
    if ($owner.ReturnValue -ne 0 -or ($owner.Domain+'\'+$owner.User) -ine $identity) { throw 'Runner process owner mismatch' }
}
if ($targets.Count -gt 1) { throw 'Multiple matching runner processes found; inspect before updating.' }
foreach($target in $targets) {
    Stop-Process -Id $target.ProcessId -ErrorAction Stop
    Wait-Process -Id $target.ProcessId -Timeout 10 -ErrorAction SilentlyContinue
}
# Preserve pending state if a claim raced with the stop. New worker marks it
# interrupted, rather than repeating the job. No credentials or state reset.
$backup=Join-Path $root ('runner-backup-'+[guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $backup | Out-Null
foreach($name in @('Start-AutomationWorker.ps1','Automation.Diagnostics.ps1')) {
    $previous=Join-Path (Split-Path $installed) $name
    if (Test-Path -LiteralPath $previous) { Copy-Item -LiteralPath $previous -Destination $backup }
}
foreach($name in @('Automation.Diagnostics.ps1','Start-AutomationWorker.ps1')) {
    $destination=Join-Path (Split-Path $installed) $name
    Copy-Item -LiteralPath (Join-Path $PSScriptRoot $name) -Destination ($destination+'.new')
    [IO.File]::Move(($destination+'.new'),$destination,$true)
}
$exe=(Get-Process -Id $PID).Path
Start-Process -FilePath $exe -ArgumentList @('-NoProfile','-WindowStyle','Hidden','-File',('"'+$installed+'"')) -WindowStyle Hidden
Write-Host 'Read-only Paytm diagnostics installed; runner restarted. Pairing and reports preserved.'
Write-Host "Runner SHA256: $newHash"
Write-Host 'Tell the development agent the update completed. No manual Paytm test or file transfer is needed.'
