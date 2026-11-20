#requires -Version 7.2
param([Parameter(Mandatory)][string]$FixtureDirectory)
. (Join-Path $PSScriptRoot 'Automation.Common.ps1')
$fixture=Get-Content (Join-Path $FixtureDirectory 'client.json') -Raw | ConvertFrom-Json
$env:LOCALAPPDATA=Join-Path $FixtureDirectory 'windows-user'
$root=Join-Path $env:LOCALAPPDATA 'MarketBrainAutomation'
New-Item -ItemType Directory -Path $root -Force | Out-Null
foreach($role in @('controller','worker')) {
    $config=@{role=$role;url='https://127.0.0.1:18443';pin=$fixture.pin;token=$fixture.$role}
    $cipher=ConvertTo-SecureString ($config | ConvertTo-Json) -AsPlainText -Force | ConvertFrom-SecureString
    [IO.File]::WriteAllText((Join-Path $root "$role.dpapi"),$cipher)
}
$controller=Get-AutomationConfig (Join-Path $root 'controller.dpapi')
$id=[guid]::NewGuid().ToString()
$null=Invoke-AutomationApi $controller '/submit' @{id=$id;kind='diagnostic'}
& (Join-Path $PSScriptRoot 'Start-AutomationWorker.ps1') -Once
if ((Get-Content (Join-Path $root 'connection-status.json') -Raw | ConvertFrom-Json).status -ne 'CONNECTED') { throw 'Recovered connection not recorded' }
$job=(Invoke-AutomationApi $controller '/result' @{id=$id}).job
if ($job.state -ne 'SUCCEEDED' -or $job.result.ordersEnabled -ne $false) { throw 'Real Windows worker failed' }
if (-not (Test-Path (Join-Path $root "reports\$id.json"))) { throw 'Local report missing' }
$id2=[guid]::NewGuid().ToString()
$null=Invoke-AutomationApi $controller '/submit' @{id=$id2;kind='diagnostic'}
$worker=Get-AutomationConfig (Join-Path $root 'worker.dpapi')
$null=Invoke-AutomationApi $worker '/claim' @{}
Write-AutomationState (Join-Path $root 'pending.json') @{id=$id2;state='RUNNING';result=$null}
& (Join-Path $PSScriptRoot 'Start-AutomationWorker.ps1') -Once
if ((Invoke-AutomationApi $controller '/result' @{id=$id2}).job.state -ne 'INTERRUPTED') { throw 'Interrupted work was not preserved' }
$id3=[guid]::NewGuid().ToString()
$null=Invoke-AutomationApi $controller '/submit' @{id=$id3;kind='diagnostic'}
$null=Invoke-AutomationApi $worker '/claim' @{}
$terminal=@{id=$id3;state='SUCCEEDED';result=@{observedUtc='2026-11-19T06:59:50.1234567+00:00';nested=@{observedUtc='2026-11-19T12:29:50.1234567+05:30'};ordersEnabled=$false}}
# Simulate accepted result with lost response: identical saved result must replay
# without PowerShell converting ISO strings into local DateTime formatting.
$null=Invoke-AutomationApi $worker '/update' $terminal
Write-AutomationState (Join-Path $root 'pending.json') $terminal
& (Join-Path $PSScriptRoot 'Start-AutomationWorker.ps1') -Once
if(Test-Path (Join-Path $root 'pending.json')){throw 'Timestamp-bearing result did not drain'}
$replayed=(Invoke-AutomationApi $controller '/result' @{id=$id3}).job
if($replayed.result.observedUtc -cne $terminal.result.observedUtc -or $replayed.result.nested.observedUtc -cne $terminal.result.nested.observedUtc){throw 'Timestamp strings changed during replay'}
$controller.pin='0'*64
$rejected=$false
try { $null=Invoke-AutomationApi $controller '/result' @{id=$id} } catch { $rejected=$true }
if (-not $rejected) { throw 'Wrong TLS pin accepted' }
$controller.pin=$fixture.pin
$controller.token='0'*64
$rejected=$false
try { $null=Invoke-AutomationApi $controller '/result' @{id=$id} } catch { $rejected=$true }
if (-not $rejected) { throw 'Wrong token accepted' }
$rejected=$false
try { $null=Invoke-AutomationApi $worker '/submit' @{id=[guid]::NewGuid().ToString();kind='diagnostic'} } catch { $rejected=$true }
if (-not $rejected) { throw 'Worker could submit jobs' }
if (Test-Path -LiteralPath (Join-Path $root 'pending.json')) { throw 'Unexpected pending fixture work' }
$installedDirectory=Join-Path $root 'runner'
New-Item -ItemType Directory -Path $installedDirectory -Force | Out-Null
foreach($name in @('Automation.Common.ps1','Automation.Diagnostics.ps1','Automation.TestExecution.ps1','Start-AutomationWorker.ps1')) { Copy-Item -LiteralPath (Join-Path $PSScriptRoot $name) -Destination $installedDirectory }
$installedWorker=Join-Path $installedDirectory 'Start-AutomationWorker.ps1'
$exe=(Get-Process -Id $PID).Path
$oldProcess=$null
try {
    # Unquoted -File path when no spaces: the old substring matcher missed it.
    $oldProcess=Start-Process -FilePath $exe -ArgumentList @('-NoProfile','-File',$installedWorker) -WindowStyle Hidden -PassThru
    $ready=$false
    for($attempt=0;$attempt -lt 40;$attempt++) {
        $statusPath=Join-Path $root 'worker-status.json'
        if(Test-Path $statusPath) { $s=Get-Content $statusPath -Raw|ConvertFrom-Json; if($s.processId -eq $oldProcess.Id){$ready=$true;break} }
        Start-Sleep -Milliseconds 250
    }
    if(-not $ready){throw 'Fixture worker did not start'}
    $identity=[Security.Principal.WindowsIdentity]::GetCurrent()
    try{$expectedElevated=([Security.Principal.WindowsPrincipal]::new($identity)).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)}finally{$identity.Dispose()}
    if(-not $expectedElevated){
        $blocked=$false
        try{& (Join-Path $PSScriptRoot 'Update-AutomationDiagnostics.ps1') -RequireElevation}catch{$blocked=$_.Exception.Message -like 'RUNNER_ADMIN_REQUIRED:*'}
        $oldProcess.Refresh()
        if(-not $blocked -or $oldProcess.HasExited){throw 'Elevation precheck did not preserve active runner'}
    }
    & (Join-Path $PSScriptRoot 'Update-AutomationDiagnostics.ps1')
    $s=Get-Content $statusPath -Raw|ConvertFrom-Json
    if($s.elevated -ne $expectedElevated){throw 'Worker startup elevation receipt incorrect'}
    if($s.processId -eq $oldProcess.Id -or $s.startupNonce -notmatch '^[a-f0-9]{32}$'){throw 'Updater did not confirm a replacement'}
    $oldProcess.Refresh()
    if(-not $oldProcess.HasExited){throw 'Old worker survived replacement'}
    if($s.diagnosticsSha256 -ne (Get-FileHash (Join-Path $PSScriptRoot 'Automation.Diagnostics.ps1')).Hash){throw 'Wrong helper loaded'}
    Stop-Process -Id $s.processId -ErrorAction Stop
    Wait-Process -Id $s.processId -Timeout 5 -ErrorAction SilentlyContinue
    Write-AutomationState (Join-Path $root 'pending.json') @{id=$id3;state='RUNNING';result=$null}
    $blocked=$false
    try { & (Join-Path $PSScriptRoot 'Update-AutomationDiagnostics.ps1') -PreserveCompletedPendingResult } catch { $blocked=$true }
    if(-not $blocked -or -not (Test-Path (Join-Path $root 'pending.json'))){throw 'Running result was not preserved/blocked'}
    Write-AutomationState (Join-Path $root 'pending.json') $terminal
    & (Join-Path $PSScriptRoot 'Update-AutomationDiagnostics.ps1') -PreserveCompletedPendingResult
    $drain=[Diagnostics.Stopwatch]::StartNew()
    while((Test-Path (Join-Path $root 'pending.json')) -and $drain.Elapsed.TotalSeconds -lt 15){Start-Sleep -Milliseconds 250}
    if(Test-Path (Join-Path $root 'pending.json')){throw 'Completed pending result failed to drain after updater'}
} finally {
    # Only processes whose exact fixture path is present; no broad process kill.
    Get-CimInstance Win32_Process -Filter "Name='pwsh.exe'" | Where-Object { $_.CommandLine -and $_.CommandLine.Contains($installedWorker) } | ForEach-Object { Stop-Process -Id $_.ProcessId -ErrorAction SilentlyContinue; Wait-Process -Id $_.ProcessId -Timeout 5 -ErrorAction SilentlyContinue }
}
Write-Host 'PASS: real runner replacement, unquoted command-line discovery, nonce/PID/hash startup acknowledgment and original process exit.'
Write-Host 'PASS: real TLS, DPAPI pairing, HTTP authentication, worker execution, report return, restart interruption, wrong certificate, wrong token and role isolation.'
Write-Host 'PASS: accepted-result replay preserves UTC/offset strings; pending-result updater blocks RUNNING and drains completed evidence without job rerun.'
