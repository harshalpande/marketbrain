#requires -Version 7.5
$ErrorActionPreference='Stop'
$source=[IO.File]::ReadAllText((Join-Path $PSScriptRoot 'CollectorLifecycle.Entry.ps1'))
$t=$null;$e=$null;$ast=[Management.Automation.Language.Parser]::ParseInput($source,[ref]$t,[ref]$e)
if($e.Count){throw 'LIFECYCLE_PARSE'}
foreach($fn in $ast.FindAll({param($n)$n -is [Management.Automation.Language.FunctionDefinitionAst]},$false)){. ([scriptblock]::Create($fn.Extent.Text))}
function New-FixtureSnapshot {
 @{bootUtc='2026-11-20T00:00:00Z';interactive=@{userSidHash=('A'*64);authenticationId=('1'*16)};worker=@{instanceId=('a'*32);processId=42;sequence=3;acceptedCount=3};workerStartUtc='2026-11-20T00:01:00Z';ticks=100;frequency=10}
}
foreach($case in @('valid','sameLogin','boot','user','instance','pid','processStart','sequence','accepted','ticks','frequency')){
 $before=New-FixtureSnapshot;$after=New-FixtureSnapshot;$after.interactive.authenticationId='2'*16;$after.worker.sequence=4;$after.worker.acceptedCount=4;$after.ticks=110
 switch($case){sameLogin{$after.interactive.authenticationId='1'*16} boot{$after.bootUtc='2026-11-21T00:00:00Z'} user{$after.interactive.userSidHash='B'*64} instance{$after.worker.instanceId='b'*32} pid{$after.worker.processId=43} processStart{$after.workerStartUtc='2026-11-20T00:02:00Z'} sequence{$after.worker.sequence=3} accepted{$after.worker.acceptedCount=3} ticks{$after.ticks=100} frequency{$after.frequency=20}}
 $failed=$false;try{Assert-CollectorLogoffBoundary $before $after}catch{$failed=$true}
 if($failed -ne ($case -ne 'valid')){throw ('BOUNDARY_CASE_'+$case)}
}
# Execute resumed orchestration with isolated OS substitutes.
$body=$source.Substring($source.IndexOf('$r=@{version=1;passed=')).Replace('if(-not $r.passed){exit 1}','')
function Get-DurableCollectorDefinition {return @{root=$script:temp;work=$script:temp;name='FIXTURE'}}
function Read-TimeObservationFile {return @{runId='ab47639ee8d74da69a9466c0f59e601e'}}
function Assert-DurableCollectorReceipt {}
function Test-Path {param($LiteralPath) if($script:case -like 'prep*' -and $LiteralPath.EndsWith('signout-checkpoint.json')){return $false};return $true}
function Read-CollectorLifecycleCheckpoint {return $script:checkpoint}
function Get-CollectorLifecycleSnapshot {return $script:after}
function Stop-CollectorActivation($Definition,$Report){$script:stops++;if($script:case -eq 'stopFailure'){throw 'FIXTURE_STOP'};$Report.collectorStopped=$true}
function Stop-DenialRecoveryTask {$script:gatewayStops++}
function Remove-DenialRecoveryGuard {$script:guardRemoves++}
function Save-CollectorLifecycleCheckpoint {$script:saves++;if($script:case -eq 'prepSaveFail'){throw 'FIXTURE_SAVE'}}
function Read-BoundedJson {return @{runId='ab47639ee8d74da69a9466c0f59e601e';ordersEnabled=$false;nonAdmin=$true;sessionId=0;applicationLocked=$true;tokenAuthenticated=$true;collector=@{instanceId=('a'*32);processId=42;phase='STOPPED';finalHealthRevoked=($script:case -ne 'revocation')}}}
function Get-ScheduledTaskInfo {return @{LastTaskResult=0}}
function Get-DurableCollectorStagingPreflight {return @{passed=$true}}
function New-CollectorGatewayContext {return @{startAttempted=$false;guardAttempted=$false;guardXmlHash=$null}}
function Get-CollectorGatewayPreflight {}
function Get-CollectorLogonIdentity {return @{authenticationId=('1'*16)}}
function Preserve-CollectorAcceptedActivation {}
function Start-CollectorGatewayWindow($Context){$Context.startAttempted=$true;$Context.guardAttempted=$true;$Context.guardXmlHash='fixed'}
function Set-CollectorActivationControl {}
function Enable-ScheduledTask {}
function Start-ScheduledTask {if($script:case -eq 'prepStartFail'){throw 'FIXTURE_START'}}
function Test-CollectorActivationSample {return $true}
function Start-Sleep {}
foreach($script:case in @('valid','waiting','observe','expired','workerChanged','revocation','stopFailure','alreadyComplete','alreadyFailed','prepValid','prepSaveFail','prepStartFail')){
 $script:temp=Join-Path ([IO.Path]::GetTempPath()) ('mb-lifecycle-fixture-'+[guid]::NewGuid().ToString('N'));$null=[IO.Directory]::CreateDirectory($temp)
 [IO.File]::WriteAllText((Join-Path $temp 'instance.lock'),'')
 $before=New-FixtureSnapshot;$before.ticks=[Diagnostics.Stopwatch]::GetTimestamp();$before.frequency=[Diagnostics.Stopwatch]::Frequency
 $script:after=New-FixtureSnapshot;$after.ticks=$before.ticks+1;$after.frequency=$before.frequency;$after.interactive.authenticationId='2'*16;$after.worker.sequence=4;$after.worker.acceptedCount=4
 $script:checkpoint=@{phase='WAITING_FOR_SIGNOUT';runId=('a'*32);before=$before;context=@{startAttempted=$true;guardAttempted=$true;guardXmlHash='fixed'}}
 switch($case){waiting{$after.interactive.authenticationId='1'*16} expired{$before.ticks-=[long](600*$before.frequency)} workerChanged{$after.worker.instanceId='b'*32} alreadyComplete{$checkpoint.phase='COMPLETE'} alreadyFailed{$checkpoint.phase='REVIEW_REQUIRED'}}
 $script:stops=0;$script:gatewayStops=0;$script:guardRemoves=0;$script:saves=0
 $Mode=if($case -eq 'observe'){'Observe'}else{'Apply'};$ResultPath=Join-Path $temp 'report.json'
 & ([scriptblock]::Create($body))
 $r=Get-Content -LiteralPath $ResultPath -Raw|ConvertFrom-Json
 if($r.passed -ne ($case -in @('valid','waiting','observe','alreadyComplete','prepValid'))){throw ('LIFECYCLE_CASE_'+$case)}
 if($case -in @('waiting','observe','alreadyComplete','alreadyFailed') -and ($stops -or $gatewayStops -or $guardRemoves -or $saves)){throw ('UNEXPECTED_MUTATION_'+$case)}
 if($case -eq 'stopFailure' -and $guardRemoves){throw 'GUARD_REMOVED_WITH_STOP_FAILURE'}
 if($case -eq 'valid' -and ($stops -ne 1 -or $gatewayStops -ne 1 -or $guardRemoves -ne 1 -or $checkpoint.phase -ne 'COMPLETE')){throw 'LIFECYCLE_CLEANUP'}
 if($case -eq 'prepValid' -and ($stops -or $gatewayStops -or $guardRemoves -or $saves -ne 1)){throw 'PREPARATION_NOT_PRESERVED'}
 if($case -in @('prepSaveFail','prepStartFail') -and ($stops -ne 1 -or $gatewayStops -ne 1 -or $guardRemoves -ne 1)){throw 'PREPARATION_FAILURE_CLEANUP'}
}
Write-Host 'COLLECTOR_LIFECYCLE_FIXTURES_PASSED: 11 boundary cases and 12 preparation/resume/cleanup cases.'
