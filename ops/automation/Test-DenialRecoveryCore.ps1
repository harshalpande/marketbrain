#requires -Version 7.5
$ErrorActionPreference='Stop'
# Exercise the actual generated receipt expression; date coercion must not alter
# the exact accepted task timestamp on a host in a different timezone.
$tokens=$null;$parseErrors=$null
$artifact=[Management.Automation.Language.Parser]::ParseFile((Join-Path $PSScriptRoot 'jobs/PaytmDenialRecovery.ps1'),[ref]$tokens,[ref]$parseErrors)
if($parseErrors.Count){throw 'Generated artifact parse failed'}
$assignment=$artifact.Find({param($n)$n -is [Management.Automation.Language.AssignmentStatementAst] -and $n.Left.Extent.Text -ceq '$acceptedRecoveryReceipt'},$true)
if(-not $assignment){throw 'Generated receipt missing'}
$accepted=& ([scriptblock]::Create($assignment.Extent.Text+'; $acceptedRecoveryReceipt'))
$original=Get-Content (Join-Path $PSScriptRoot '../../docs/evidence/queued-recovery-preflight-20261120.json') -Raw|ConvertFrom-Json -AsHashtable -DateKind String
if($accepted.task.lastRunUtc -isnot [string] -or $accepted.task.lastRunUtc -cne $original.result.evidence.recoveryPreflight.task.lastRunUtc){throw 'Accepted timestamp changed during build/load'}
. (Join-Path $PSScriptRoot 'DenialRecovery.Core.ps1')
function Read-BoundedJson($Path){Get-Content -LiteralPath $Path -Raw|ConvertFrom-Json}
function Get-ScheduledTask {return [pscustomobject]@{State=$script:taskState;Settings=[pscustomobject]@{Enabled=$script:enabled}}}
function Get-ScheduledTaskInfo {return [pscustomobject]@{LastTaskResult=1;LastRunTime=[DateTime]::Parse('2026-11-19T14:40:40Z').ToUniversalTime()}}
function Export-ScheduledTask {return '<Task>fixture</Task>'}
function Disable-ScheduledTask {$script:enabled=$false;$script:disableCalls++}
function Enable-ScheduledTask {$script:enabled=$true}
function Start-ScheduledTask {$script:startCalls++;if($script:scenario -eq 'StartFailure'){throw 'RECOVERY_FIXTURE_START_FAILED'}}
function Stop-DenialRecoveryTask($Context){$script:enabled=$false;$script:stopCalls++;if($script:scenario -eq 'StopFailure'){throw 'RECOVERY_STOP_NOT_VERIFIED'}}
function Register-DenialRecoveryGuard($Context,$ManifestHash){$script:guardCalls++;if($script:scenario -eq 'GuardFailure'){throw 'RECOVERY_GUARD_NOT_VERIFIED'};$Context.guardXmlHash='FIXTURE'}
function Remove-DenialRecoveryGuard($Context){$script:removeGuardCalls++}
function Wait-DenialRecoveryObservation($Context,$Report){if($script:scenario -eq 'CaptureFailure'){throw 'RECOVERY_NEW_WORKER_BLOCKED'}}
$base=Join-Path ([IO.Path]::GetTempPath()) ('mb-denial-core-'+[guid]::NewGuid().ToString('N'))
$count=0
foreach($script:scenario in @('Success','SnapshotDrift','GuardFailure','StartFailure','CaptureFailure','StopFailure')){
    $case=Join-Path $base $script:scenario;$root=Join-Path $case 'root';$work=Join-Path $case 'work'
    New-Item -ItemType Directory -Path $root,$work -Force|Out-Null
    $ctx=@{root=$root;work=$work;archive=(Join-Path $root 'archive');resultPath=(Join-Path $case 'result.json');taskName='Fixture';runId='fixture';guardXmlHash=$null}
    $manifest=@{hashes=@{}}
    foreach($name in @('host.ps1','runner.ps1','native.dll','transport.ps1','gateway.ps1','transport.dll')){[IO.File]::WriteAllText((Join-Path $root $name),'fixture-'+$name);$manifest.hashes[$name]=(Get-FileHash (Join-Path $root $name)).Hash}
    [IO.File]::WriteAllText((Join-Path $root 'manifest.json'),($manifest|ConvertTo-Json -Depth 5))
    foreach($name in @('control.json','transport-control.json','session-checkpoint.json')){[IO.File]::WriteAllText((Join-Path $root $name),'fixture-'+$name)}
    foreach($name in @('status.json','blocked.json','startup-failure.json')){[IO.File]::WriteAllText((Join-Path $work $name),'fixture-'+$name)}
    [IO.File]::WriteAllText((Join-Path $work 'instance.lock'),'')
    $before=@{hashes=@{};task=@{lastRunUtc=[DateTime]::Parse('2026-11-19T14:40:40Z').ToUniversalTime().ToString('o')}}
    foreach($file in @(Get-ChildItem $root -File)+@(Get-ChildItem $work -File|Where-Object Name -NE 'instance.lock')){$before.hashes[$file.Name]=(Get-FileHash $file.FullName).Hash}
    $r=@{passed=$false;cleanupFailure=$null;finalStoppedAndDisabled=$false;startAttempts=0;backupVerified=$false;instrumentationInstalled=$false;archivedMarkersCleared=$false;guardRegistered=$false;guardRemoved=$false;transportObserved=$false}
    $script:taskState='Ready';$script:enabled=$true;$script:startCalls=0;$script:stopCalls=0;$script:disableCalls=0;$script:guardCalls=0;$script:removeGuardCalls=0
    if($script:scenario -eq 'SnapshotDrift'){[IO.File]::WriteAllText((Join-Path $work 'blocked.json'),'changed')}
    $failure=$null
    try{Invoke-DenialRecoveryApply $ctx $before ([Text.Encoding]::UTF8.GetBytes('new-reviewed-fixture')) $r}catch{$failure=$_.Exception.Message}
    if($script:scenario -eq 'SnapshotDrift'){
        if($failure -ne 'RECOVERY_SNAPSHOT_DRIFT' -or $script:disableCalls -ne 0 -or $script:startCalls -ne 0){throw 'Drift mutation guard failed'}
    } else {
        if(-not $r.backupVerified -or -not $r.instrumentationInstalled -or (Get-FileHash (Join-Path $ctx.archive 'blocked.json')).Hash -ne $before.hashes['blocked.json']){throw "Backup/install verification failed: $failure"}
        if((Get-FileHash (Join-Path $root 'session-checkpoint.json')).Hash -ne $before.hashes['session-checkpoint.json']){throw 'Checkpoint changed'}
        if($script:startCalls -gt 1 -or $script:stopCalls -ne 1 -or $script:enabled){throw 'Start/stop boundedness failed'}
        if($script:scenario -eq 'GuardFailure' -and ($script:startCalls -ne 0 -or -not $r.cleanupFailure)){throw 'Unguarded start allowed'}
        if($script:scenario -eq 'StopFailure' -and ($r.finalStoppedAndDisabled -or $script:removeGuardCalls -ne 0 -or -not $r.cleanupFailure)){throw 'Stop failure removed fallback'}
        if($script:scenario -eq 'Success' -and ($failure -or -not $r.transportObserved -or -not $r.guardRemoved -or -not $r.finalStoppedAndDisabled)){throw 'Success workflow failed'}
        if($script:scenario -in @('StartFailure','CaptureFailure') -and (-not $failure -or -not $r.finalStoppedAndDisabled)){throw 'Failure cleanup not preserved'}
    }
    $count++
}
Write-Host "DENIAL_RECOVERY_CORE_PASSED: $count isolated workflows; no real task or network access. Fixtures: $base"
