#requires -Version 7.2
[CmdletBinding()]
param()
$ErrorActionPreference='Stop'
$root=Join-Path $env:LOCALAPPDATA 'MarketBrainAutomation'
$worker=Join-Path $root 'runner\Start-AutomationWorker.ps1'
if (-not (Test-Path -LiteralPath $worker) -or -not (Test-Path -LiteralPath (Join-Path $root 'worker.dpapi'))) { throw 'Pair the worker first' }
$exe=(Get-Process -Id $PID).Path
$startup=[Environment]::GetFolderPath('Startup')
$link=Join-Path $startup 'MarketBrain Automation.lnk'
if (Test-Path -LiteralPath $link) { throw 'Startup shortcut already exists. Use the existing shortcut to start the runner.' }
$shell=New-Object -ComObject WScript.Shell
try {
    $shortcut=$shell.CreateShortcut($link)
    $shortcut.TargetPath=$exe
    $shortcut.Arguments='-NoProfile -WindowStyle Hidden -File "'+$worker+'"'
    $shortcut.WorkingDirectory=$root
    $shortcut.Save()
} finally { [void][Runtime.InteropServices.Marshal]::ReleaseComObject($shell) }
Start-Process -FilePath $exe -ArgumentList @('-NoProfile','-WindowStyle','Hidden','-File',('"'+$worker+'"')) -WindowStyle Hidden
Write-Host 'Runner started. It will start again at Windows sign-in. Leave this Windows user signed in; locking the screen is fine, but prompts require unlocking.'
Write-Host "Local evidence: $root\reports"
