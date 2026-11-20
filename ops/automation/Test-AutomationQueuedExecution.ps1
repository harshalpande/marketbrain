#requires -Version 7.5
param([Parameter(Mandatory)][string]$FixtureDirectory)
. (Join-Path $PSScriptRoot 'Automation.Common.ps1')
$fixture=Get-Content (Join-Path $FixtureDirectory 'client.json') -Raw | ConvertFrom-Json
$env:LOCALAPPDATA=Join-Path $FixtureDirectory 'windows-user'
$root=Join-Path $env:LOCALAPPDATA 'MarketBrainAutomation'
$runner=Join-Path $root 'runner'
New-Item -ItemType Directory -Path $runner -Force | Out-Null
foreach($role in @('controller','worker')) {
    $config=@{role=$role;url='https://127.0.0.1:18443';pin=$fixture.pin;token=$fixture.$role}
    $cipher=ConvertTo-SecureString ($config|ConvertTo-Json) -AsPlainText -Force|ConvertFrom-SecureString
    [IO.File]::WriteAllText((Join-Path $root "$role.dpapi"),$cipher)
}
foreach($name in @('Automation.Common.ps1','Automation.TestExecution.ps1','Start-AutomationWorker.ps1')) { Copy-Item (Join-Path $PSScriptRoot $name) $runner }
# Fixture-only download substitution; production download has no configurable URL.
Add-Content (Join-Path $runner 'Automation.TestExecution.ps1') @'
function Get-AutomationReviewedSource([string]$Revision) { return ,[IO.File]::ReadAllBytes((Join-Path $PSScriptRoot 'fixture.ps1')) }
'@
[IO.File]::WriteAllText((Join-Path $runner 'Automation.Diagnostics.ps1'),'# No diagnostics or network probes in this fixture')
Copy-Item (Join-Path $PSScriptRoot 'jobs/PaytmTransport.ps1') (Join-Path $runner 'fixture.ps1')
$controller=Get-AutomationConfig (Join-Path $root 'controller.dpapi')
$worker=Get-AutomationConfig (Join-Path $root 'worker.dpapi')
function Invoke-FixtureJob([string]$Revision,[string]$Kind='paytm-transport-test') {
    $job=@{id=[guid]::NewGuid().ToString();kind=$Kind;spec=@{revision=$Revision;sha256=(Get-FileHash (Join-Path $runner 'fixture.ps1')).Hash;mode='FailureFixture'}}
    $null=Invoke-AutomationApi $controller '/submit' $job
    & (Join-Path $runner 'Start-AutomationWorker.ps1') -Once
    (Invoke-AutomationApi $controller '/result' @{id=$job.id}).job
}
$first=Invoke-FixtureJob ('a'*40)
if($first.state -ne 'FAILED' -or $first.result.evidence.failure -ne 'DELIBERATE_FAILURE_FIXTURE_NO_GATEWAY_ACCESS'){throw 'Real queued failure evidence missing'}
$completed=Get-Content (Join-Path $root ('reports/'+$first.id+'.json')) -Raw | ConvertFrom-Json -DateKind String
Write-AutomationState (Join-Path $root 'pending.json') $completed
& (Join-Path $runner 'Start-AutomationWorker.ps1') -Once
if(Test-Path (Join-Path $root 'pending.json')){throw 'Lost ACK retry not cleared'}
[IO.File]::WriteAllText((Join-Path $runner 'fixture.ps1'),"param([string]`$ResultPath,[string]`$Mode)`n[IO.File]::WriteAllText(`$ResultPath,'{`"passed`":true,`"fixture`":true}')")
$second=Invoke-FixtureJob ('b'*40)
if($second.state -ne 'SUCCEEDED' -or -not $second.result.evidence.fixture){throw 'Second reviewed version failed'}
if(@(Get-ChildItem (Join-Path $root 'executions') -Directory).Count -ne 2){throw 'Execution replay detected'}
Copy-Item (Join-Path $PSScriptRoot 'jobs/PaytmDenialRecovery.ps1') (Join-Path $runner 'fixture.ps1') -Force
$recovery=Invoke-FixtureJob ('c'*40) 'paytm-denial-recovery'
if($recovery.state -ne 'FAILED' -or $recovery.result.evidence.failure -ne 'RECOVERY_DELIBERATE_FAILURE_NO_GATEWAY_ACCESS' -or $recovery.result.evidence.startAttempts -ne 0){throw 'Recovery job boundary failed'}
Copy-Item (Join-Path $PSScriptRoot 'jobs/PaytmTimeObserver.ps1') (Join-Path $runner 'fixture.ps1') -Force
$observer=Invoke-FixtureJob ('d'*40) 'paytm-time-observer'
if($observer.state -ne 'FAILED' -or $observer.result.evidence.failure -ne 'TIME_OBSERVER_DELIBERATE_FIXTURE' -or $observer.result.evidence.taskCreated){throw 'Time observer fixture boundary failed'}
Write-Host 'QUEUED_EXECUTION_PASSED: real TLS relay, worker, returned failure, lost result ACK, second source version, no replay.'
