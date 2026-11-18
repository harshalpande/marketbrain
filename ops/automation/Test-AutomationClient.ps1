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
Write-Host 'PASS: real TLS, DPAPI pairing, HTTP authentication, worker execution, report return, restart interruption, wrong certificate, wrong token and role isolation.'
