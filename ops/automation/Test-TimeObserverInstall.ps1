#requires -Version 7.5
$ErrorActionPreference='Stop'
# Isolated controller workflow: OS/task/ACL calls mocked; files use a temp root.
function Assert-TimeObservationAcl {}
function Set-Acl {}
function Get-LocalUser {return @{SID=@{Value='S-1-5-21-3041730714-102984520-3202743044-1011'};Enabled=$true}}
function New-ScheduledTaskAction {param($Execute,$Argument) @{Execute=$Execute;Arguments=$Argument}}
function New-ScheduledTaskTrigger {return @{CimClass=@{CimClassName='MSFT_TaskBootTrigger'}}}
function New-ScheduledTaskPrincipal {return @{UserId='SYSTEM';LogonType='ServiceAccount'}}
function New-ScheduledTaskSettingsSet {}
function Register-ScheduledTask {param($TaskName,$TaskPath,$Description,$Action,$Trigger,$Principal,$Settings) $script:registered=$true;$script:taskValue=@{TaskName=$TaskName;TaskPath=$TaskPath;Actions=@($Action);Triggers=@($Trigger);Principal=$Principal}}
function Get-ScheduledTask {if($script:registered){return [pscustomobject]$script:taskValue}}
function Start-ScheduledTask {$script:starts++;if($script:scenario -eq 'startFailure'){throw 'TIME_OBSERVER_FIXTURE_START'};[IO.File]::WriteAllText((Join-Path $root 'snapshot.json'),'{}')}
function Stop-ScheduledTask {$script:stops++}
function Disable-ScheduledTask {$script:disabled++}
function Read-TimeObservation {$script:sequence++;return @{sequence=$script:sequence;ageSeconds=0.2}}
function Start-Sleep {}
$source=[IO.File]::ReadAllText((Join-Path $PSScriptRoot 'TimeObserver.Entry.ps1'))
$source=$source.Replace("if(-not ([Security.Principal.WindowsPrincipal]::new(`$id)).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator))",'if($false)')
$source=$source.Replace('if(-not $r.passed){exit 1}','')
foreach($script:scenario in @('success','collision','startFailure')){
 $dir=Join-Path ([IO.Path]::GetTempPath()) ('mb-time-install-'+[guid]::NewGuid().ToString('N'))
 $null=New-Item -ItemType Directory $dir
 $root=Join-Path $dir 'observer';$ResultPath=Join-Path $dir 'result.json';$Mode='Apply';$timeObserverWorker=[Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes('# fixture only'))
 $script:registered=$false;$script:starts=0;$script:stops=0;$script:disabled=0;$script:sequence=0
 if($scenario -eq 'collision'){$null=New-Item -ItemType Directory $root}
 & ([scriptblock]::Create($source.Replace('C:\ProgramData\MarketBrainPaytmHealth\time-observer-v1',$root)))
 $r=Get-Content -LiteralPath $ResultPath -Raw|ConvertFrom-Json
 if($scenario -eq 'success' -and (-not $r.passed -or $starts -ne 1 -or $stops -or $r.healthAccountAcceptance)){throw 'Install success fixture failed'}
 if($scenario -eq 'collision' -and ($r.passed -or $registered -or $starts)){throw 'Collision mutated state'}
 if($scenario -eq 'startFailure' -and ($r.passed -or $starts -ne 1 -or $stops -ne 1 -or $disabled -ne 1)){throw 'Start failure cleanup missing'}
}
Write-Host 'TIME_OBSERVER_INSTALL_FIXTURES_PASSED: success, collision, failed start; no real task or ACL changes.'
