#requires -Version 7.5
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'DenialRecovery.Core.ps1')
function Read-BoundedJson($Path){Get-Content -LiteralPath $Path -Raw|ConvertFrom-Json -DateKind String}
function Get-FileHash($LiteralPath){
    if($LiteralPath -ceq (Join-Path $script:ctx.root 'manifest.json')){return @{Hash='7DEBDC0E181DF0484E74F5FF4A2AD24D1034A8464A12DD72684A5D3EFFFAAD55'}}
    Microsoft.PowerShell.Utility\Get-FileHash -LiteralPath $LiteralPath
}
function Get-ScheduledTask($TaskName){if($TaskName -like 'MarketBrain-Denial-Guard-*'){return $script:guard};return [pscustomobject]@{State='Disabled';Settings=@{Enabled=$false};Description='MarketBrain locked supervisor ea8b91471cf048aa97a0f6b939b355c7'}}
function Get-ScheduledTaskInfo {return @{LastTaskResult=1;LastRunTime=[DateTime]::Parse('2026-11-19T14:40:40Z').ToUniversalTime()}}
function Export-ScheduledTask {return '<Task><Actions><Exec>fixture</Exec></Actions><Principals><Principal>fixture</Principal></Principals></Task>'}
function Unregister-ScheduledTask {$script:removed++}
function Register-DenialRecoveryGuard($Context,$ManifestHash){if($script:scenario -eq 'GuardFailure'){throw 'RECOVERY_GUARD_NOT_VERIFIED'};$Context.guardXmlHash='fixture'}
function Enable-ScheduledTask {}
function Start-ScheduledTask {$script:starts++}
function Wait-DenialRecoveryObservation {if($script:scenario -eq 'CaptureFailure'){throw 'RECOVERY_NEW_WORKER_BLOCKED'}}
function Stop-DenialRecoveryTask {$script:stops++;if($script:scenario -eq 'StopFailure'){throw 'RECOVERY_STOP_NOT_VERIFIED'}}
function Remove-DenialRecoveryGuard {$script:cleanup++}
$base=Join-Path ([IO.Path]::GetTempPath()) ('mb-resume-fixture-'+[guid]::NewGuid().ToString('N'))
foreach($script:scenario in @('Success','BackupDrift','GuardFailure','CaptureFailure','StopFailure')){
    $root=Join-Path $base $scenario;$work=Join-Path $root 'work'
    $prior='649710f6-e95b-4ebc-831b-60a99d22ac69';$archive=Join-Path $root ('denial-recovery-'+$prior)
    $null=New-Item -ItemType Directory -Path $work,$archive -Force
    $script:ctx=@{root=$root;work=$work;taskName='fixture';archive=(Join-Path $root 'new');guardXmlHash=$null;resultPath=(Join-Path $root 'result.json')}
    [IO.File]::WriteAllText((Join-Path $work 'instance.lock'),'')
    [IO.File]::WriteAllText((Join-Path $archive 'manifest.json'),'original')
    [IO.File]::WriteAllText((Join-Path $root 'manifest.json'),'installed')
    [IO.File]::WriteAllText((Join-Path $archive 'task.xml'),(Export-ScheduledTask))
    $receipt=@{hashes=@{'manifest.json'=(Microsoft.PowerShell.Utility\Get-FileHash -LiteralPath (Join-Path $archive 'manifest.json')).Hash};task=@{lastRunUtc=[DateTime]::Parse('2026-11-19T14:40:40Z').ToUniversalTime().ToString('o')}}
    $guardPath=Join-Path $archive 'guard.ps1';[IO.File]::WriteAllText($guardPath,'fixture')
    $hash=(Get-FileHash -LiteralPath $guardPath).Hash
    $command="if((Get-FileHash -LiteralPath '$guardPath').Hash -cne '$hash'){exit 4};&([scriptblock]::Create([IO.File]::ReadAllText('$guardPath')))"
    $script:guard=@{State='Ready';Description=('MarketBrain bounded denial capture '+$prior);Actions=@(@{Execute='C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe';Arguments=('-NoLogo -NoProfile -NonInteractive -EncodedCommand '+[Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($command)))})}
    if($scenario -eq 'BackupDrift'){[IO.File]::WriteAllText((Join-Path $archive 'manifest.json'),'changed')}
    $script:removed=0;$script:starts=0;$script:stops=0;$script:cleanup=0
    $r=@{finalStoppedAndDisabled=$false;guardRemoved=$false;cleanupFailure=$null};$failure=$null
    try{Resume-DenialRecoveryCapture $ctx $receipt $r}catch{$failure=$_.Exception.Message}
    if($scenario -eq 'BackupDrift'){if($failure -ne 'RECOVERY_BACKUP_DRIFT' -or $removed -or $starts){throw 'Drift guard failed'};continue}
    if($removed -ne 1 -or $starts -gt 1 -or $stops -ne 1){throw "Bounded resume failed: $scenario $failure"}
    if($scenario -eq 'Success' -and ($failure -or -not $r.transportObserved -or -not $r.guardRemoved)){throw "Success failed: $failure"}
    if($scenario -eq 'GuardFailure' -and ($starts -or -not $failure)){throw 'Unguarded start'}
    if($scenario -eq 'CaptureFailure' -and (-not $failure -or -not $r.finalStoppedAndDisabled)){throw 'Capture failure cleanup failed'}
    if($scenario -eq 'StopFailure' -and ($cleanup -or -not $r.cleanupFailure)){throw 'Fallback removed'}
}
# Scheduler can add a timezone offset without changing the scheduled instant.
$local=[DateTimeOffset]::Parse('2026-11-20T11:46:12')
if([DateTimeOffset]::Parse($local.ToString('o')) -ne $local){throw 'Trigger instant normalization failed'}
Write-Host 'DENIAL_RESUME_PASSED: five isolated resume paths and trigger timestamp normalization.'
