#requires -Version 7.5
$ErrorActionPreference='Stop'
$base=Join-Path ([IO.Path]::GetTempPath()) ('mb-recovery-preflight-'+[guid]::NewGuid().ToString('N'))
$root=Join-Path $base 'supervisor-v1';$work=Join-Path $base 'supervisor-work-v1'
New-Item -ItemType Directory -Path $root,$work -Force|Out-Null
function Save($Path,$Value){[IO.File]::WriteAllText($Path,($Value|ConvertTo-Json -Depth 8))}
$id='ea8b91471cf048aa97a0f6b939b355c7';$instance='1f2c636c108042898f3c58143e00d9c7'
$manifest=@{installationId=$id;version=1;transportVersion=1;hashes=@{}}
foreach($name in @('host.ps1','runner.ps1','native.dll','transport.ps1','gateway.ps1','transport.dll')){
    [IO.File]::WriteAllText((Join-Path $root $name),'fixture-'+$name)
    $manifest.hashes[$name]=(Get-FileHash (Join-Path $root $name)).Hash
}
Save (Join-Path $root 'manifest.json') $manifest
$manifestHash=(Get-FileHash (Join-Path $root 'manifest.json')).Hash
Save (Join-Path $root 'control.json') @{mode='LOCKED'}
Save (Join-Path $root 'transport-control.json') @{mode='ENABLED'}
$state=[pscustomobject]@{instanceId=$instance;failure='TRANSPORT_DENIAL_FAILED';sequence=3860;phase='BLOCKED';ordersEnabled=$false;brokerReady=$false}
foreach($name in @('status.json','blocked.json','startup-failure.json')){Save (Join-Path $work $name) $state}
[IO.File]::WriteAllText((Join-Path $work 'instance.lock'),'')
$command="&([scriptblock]::Create([IO.File]::ReadAllText('"+$root+"\runner.ps1')))"
$expected='-NoLogo -NoProfile -NonInteractive -EncodedCommand '+[Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($command))
$task=[pscustomobject]@{TaskName='MarketBrain-Gateway-Supervisor-v1';State='Ready';Description=('MarketBrain locked supervisor '+$id);Settings=[pscustomobject]@{Enabled=$true};Principal=[pscustomobject]@{UserId='S-1-5-21-3041730714-102984520-3202743044-1010';RunLevel='Limited';LogonType='Password'};Actions=@([pscustomobject]@{Execute='C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe';Arguments=$expected;WorkingDirectory=$root})}
function Get-ScheduledTask {return $task}
function Get-ScheduledTaskInfo {return [pscustomobject]@{LastTaskResult=1;LastRunTime=[DateTime]::UtcNow}}
$t=$null;$e=$null;$ast=[Management.Automation.Language.Parser]::ParseFile((Join-Path $PSScriptRoot 'jobs/PaytmTransport.ps1'),[ref]$t,[ref]$e)
if($e.Count){throw 'Parse failure'}
foreach($name in @('Read-BoundedJson','Get-DenialRecoveryPreflight')){
    $fn=$ast.Find({param($n)$n -is [Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -eq $name},$true)
    $source=$fn.Extent.Text.Replace('C:\ProgramData\MarketBrainPaytmGateway\supervisor-v1',$root).Replace('C:\ProgramData\MarketBrainPaytmGateway\supervisor-work-v1',$work).Replace('C:\ProgramData\MarketBrainPaytmGateway',$base).Replace('343A080C09E468F73FAC844ABC5CAA02B2A429CCD4B66308D2B6366102B12A98',$manifestHash)
    . ([scriptblock]::Create($source))
}
$r=Get-DenialRecoveryPreflight $state
if(-not $r.readyForReviewedRecovery){throw ($r|ConvertTo-Json -Depth 8)}
$task.Actions[0].Arguments='unrelated command'
if((Get-DenialRecoveryPreflight $state).failure -ne 'RECOVERY_TASK_IDENTITY_CHANGED'){throw 'Task drift accepted'}
$task.Actions[0].Arguments=$expected
$lease=[IO.File]::Open((Join-Path $work 'instance.lock'),'Open','ReadWrite','None')
try {if((Get-DenialRecoveryPreflight $state).readyForReviewedRecovery){throw 'Active worker accepted'}}finally{$lease.Dispose()}
[IO.File]::WriteAllText((Join-Path $root 'transport.ps1'),'drift')
if((Get-DenialRecoveryPreflight $state).failure -ne 'RECOVERY_INSTALLED_SOURCE_DRIFT'){throw 'Source drift accepted'}
[IO.File]::WriteAllText((Join-Path $root 'transport.ps1'),'fixture-transport.ps1')
$state.sequence=9999
if((Get-DenialRecoveryPreflight $state).failure -ne 'RECOVERY_STATUS_CHANGED'){throw 'New incident accepted'}
Write-Host 'RECOVERY_PREFLIGHT_FIXTURES_PASSED: idle pinned installation, changed task, live lease, source drift, changed incident.'
Write-Host "Fixture evidence retained: $base"
