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
foreach($name in @('Automation.Common.ps1','Automation.Diagnostics.ps1','Start-AutomationWorker.ps1')) { Copy-Item -LiteralPath (Join-Path $PSScriptRoot $name) -Destination $installedDirectory }
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
    & (Join-Path $PSScriptRoot 'Update-AutomationDiagnostics.ps1')
    $s=Get-Content $statusPath -Raw|ConvertFrom-Json
    if($s.processId -eq $oldProcess.Id -or $s.startupNonce -notmatch '^[a-f0-9]{32}$'){throw 'Updater did not confirm a replacement'}
    $oldProcess.Refresh()
    if(-not $oldProcess.HasExited){throw 'Old worker survived replacement'}
    if($s.diagnosticsSha256 -ne (Get-FileHash (Join-Path $PSScriptRoot 'Automation.Diagnostics.ps1')).Hash){throw 'Wrong helper loaded'}
} finally {
    # Only processes whose exact fixture path is present; no broad process kill.
    Get-CimInstance Win32_Process -Filter "Name='pwsh.exe'" | Where-Object { $_.CommandLine -and $_.CommandLine.Contains($installedWorker) } | ForEach-Object { Stop-Process -Id $_.ProcessId -ErrorAction SilentlyContinue; Wait-Process -Id $_.ProcessId -Timeout 5 -ErrorAction SilentlyContinue }
}
Write-Host 'PASS: real runner replacement, unquoted command-line discovery, nonce/PID/hash startup acknowledgment and original process exit.'
Write-Host 'PASS: real TLS, DPAPI pairing, HTTP authentication, worker execution, report return, restart interruption, wrong certificate, wrong token and role isolation.'
