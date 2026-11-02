#Requires -Version 7.0
$ErrorActionPreference='Stop'
foreach($name in @('PaytmGatewayAccount.ps1','PaytmGatewayKeyCustody.ps1','PaytmGatewayScheduledProbe.ps1','PaytmSupervisorHost.ps1','PaytmSupervisorInstallation.ps1')){. (Join-Path $PSScriptRoot $name)}
Assert-PaytmCustodyController
$c=Get-PaytmHostContract
$null=Assert-PaytmAccountPath $c.root
Assert-PaytmAccountAcl (Get-Acl -LiteralPath $c.root) (Get-PaytmKeyContract).accountSid
$manifest=Read-PaytmHostJson (Join-Path $c.root 'manifest.json')
if($manifest.version -ne 1 -or $manifest.installationId -cnotmatch '^[a-f0-9]{32}$'){throw 'HOST_MANIFEST_INVALID'}
$tasks=@(Get-PaytmProbeTask $c.name)
if($tasks.Count -ne 1){throw 'HOST_TASK_MISSING'}
Assert-PaytmHostTask $tasks[0] $manifest.installationId ([bool]$tasks[0].Settings.Enabled)
Set-PaytmHostControl $manifest.installationId STOP
$null=Disable-ScheduledTask -TaskName $c.name -TaskPath '\' -ErrorAction Stop
Stop-ScheduledTask -TaskName $c.name -TaskPath '\' -ErrorAction Stop
$timer=[Diagnostics.Stopwatch]::StartNew()
do{
    $task=Get-PaytmOwnedHostTask $manifest.installationId $false
    if([string]$task.State -cnotin @('Running','Queued')){break}
    Start-Sleep -Milliseconds 250
}while($timer.Elapsed.TotalSeconds -lt 10)
if([string]$task.State -cin @('Running','Queued')){throw 'HOST_STOP_TIMEOUT'}
Write-Host 'Supervisor disabled and stopped. Persistent STOP retained. Account, agent key, installed files and evidence preserved.'
