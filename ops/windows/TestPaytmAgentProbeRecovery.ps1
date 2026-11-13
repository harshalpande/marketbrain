#Requires -Version 7.0
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'PaytmSupervisorHost.ps1')
. (Join-Path $PSScriptRoot 'PaytmAgentProbeRecovery.ps1')
$idleBody=${function:Assert-PaytmAgentProbeIdle}
$tmp=Join-Path ([IO.Path]::GetTempPath()) ('mb-probe-recovery-'+[guid]::NewGuid().ToString('N'))
$checks=0
function Check($Ok,$Name){if(-not $Ok){throw $Name};$script:checks++}
function Assert-PaytmAccountPath($p){$p}
function Get-PaytmHostContract {@{root=$root;work=$work;name='fixture'}}
function Get-PaytmKeyContract {@{accountSid='fixture'}}
function Assert-PaytmNativeReceipt {}
function Assert-PaytmTransportInstallationSources {Read-PaytmHostJson (Join-Path $root 'manifest.json')}
function Add-Type {param($Path)}
function Assert-PaytmAgentProbeIdle {if($case -eq 'drift'){throw 'HOST_PROBE_FAILURE_CHANGED'}}
function Test-PaytmAgentProbeSourceHash { $true }
function Set-PaytmAccountDirectoryAcl {}
function Save-NativeRecoveryReport {}
function Invoke-PaytmNativeBuild($source,$dest){if($case -eq 'buildFail'){throw 'HOST_NATIVE_BUILD_FAILED'};[IO.File]::WriteAllText($dest,'new-native')}
function Set-PaytmHostControl($id,$mode){$script:mode=$mode}
function Assert-PaytmInstalledTransport {}
function Start-ScheduledTask {param($TaskName,$TaskPath,$ErrorAction) $script:starts++;if($case -eq 'startFail'){throw 'START_FAILED'}}
function Wait-PaytmManagedHost {param($Id,$Phase,$PreviousInstance,[switch]$AwaitScheduledStart)
 Check ($PreviousInstance -ceq 'e2398de523db4fbd8e7e8f8c0eb246de' -and $AwaitScheduledStart) 'NEW_WORKER_REQUIRED'
 @{instanceId='new'}
}
try{
 foreach($case in @('pass','drift','buildFail','startFail')){
  $root=Join-Path $tmp $case;$work=Join-Path $root work;$source=Join-Path $root source
  $null=New-Item -ItemType Directory -Path $work,$source -Force
  $names=@('native.dll','host.ps1','runner.ps1','transport.ps1','control.json','transport-control.json','session-checkpoint.json')
  foreach($n in $names){[IO.File]::WriteAllText((Join-Path $root $n),'old-'+$n)}
  foreach($n in @('startup-failure.json','status.json','blocked.json')){[IO.File]::WriteAllText((Join-Path $work $n),'old-'+$n)}
  foreach($n in @('PaytmSupervisorNative.cs','PaytmSupervisorHost.ps1','RunPaytmGatewaySupervisor.ps1','PaytmSupervisorTransport.ps1')){[IO.File]::WriteAllText((Join-Path $source $n),'new-'+$n)}
  $hashes=@{};foreach($n in @('native.dll','host.ps1','runner.ps1','transport.ps1')){$hashes[$n]=(Get-FileHash (Join-Path $root $n)).Hash}
  Write-PaytmHostJson (Join-Path $root 'manifest.json') @{installationId='fixture';hashes=$hashes}
  $report=[ordered]@{runId=[guid]::NewGuid().ToString('N');nativeRecoveryAttempted=$false};$starts=0;$mode=$null
  $failed=$false;try{Invoke-PaytmNativeRecovery @{} 'fixture' $source}catch{$failed=$true}
  Check ($failed -eq ($case -ne 'pass')) ($case+'_OUTCOME')
  if($case -in @('drift','buildFail')){
   Check ($starts -eq 0 -and -not $report.nativeRecoveryAttempted -and (Test-Path (Join-Path $root 'session-checkpoint.json'))) 'PREFLIGHT_NO_MUTATION'
   foreach($n in $hashes.Keys){Check ((Get-FileHash (Join-Path $root $n)).Hash -ceq $hashes[$n]) 'ORIGINAL_CODE_UNCHANGED'}
   continue
  }
  Check ($starts -eq 1 -and $mode -eq 'LOCKED' -and $report.nativeRecovery.manifestUpdated) 'SINGLE_START'
  foreach($n in $report.nativeRecovery.backupHashes.Keys){Check ((Get-FileHash (Join-Path $report.nativeRecovery.backupPath $n)).Hash -ceq $report.nativeRecovery.backupHashes[$n]) 'VERIFIED_ARCHIVE'}
  $m=Read-PaytmHostJson (Join-Path $root 'manifest.json')
  foreach($n in $hashes.Keys){Check ((Get-FileHash (Join-Path $root $n)).Hash -ceq $m.hashes.$n -and $m.hashes.$n -cne $hashes[$n]) 'PATCH_MATCHES_MANIFEST'}
  Check (-not (Test-Path (Join-Path $root 'session-checkpoint.json')) -and -not(Test-Path (Join-Path $work 'startup-failure.json'))) 'OLD_STATE_ARCHIVED'
 }
 # Verify real idle gate against a completed failure, not the earlier racing snapshot.
 function Get-PaytmOwnedHostTask {@{State=$script:taskState}}
 function Get-ScheduledTaskInfo {param($TaskName,$TaskPath) @{LastTaskResult=1}}
 function Get-Process {param($ErrorAction) @()}
 function Assert-PaytmHostControl {}
 function Read-PaytmTransportControl {'ENABLED'}
 function Assert-PaytmSessionCheckpoint {}
 function Assert-PaytmTransportListener {}
 function Get-PaytmTransportListeners {@()}
 Write-PaytmHostJson (Join-Path $root 'control.json') @{mode='LOCKED'}
 foreach($n in @('startup-failure.json','status.json','blocked.json')){Write-PaytmHostJson (Join-Path $work $n) @{installationId='fixture';instanceId='e2398de523db4fbd8e7e8f8c0eb246de';processId=14544;phase='BLOCKED';failure='HOST_AGENT_UNAVAILABLE'}}
 Write-PaytmHostJson (Join-Path $root 'session-checkpoint.json') @{runId='3bec334f1adf423c986286eedd6697f2';nextPhase='AfterLogoff';before=@{worker=@{instanceId='e2398de523db4fbd8e7e8f8c0eb246de'}}}
 $script:taskState='Ready';& $idleBody fixture;Check $true 'COMPLETED_FAILURE_ACCEPTED'
 $script:taskState='Running';$failed=$false;try{& $idleBody fixture}catch{$failed=$true};Check $failed 'RUNNING_WORKER_REFUSED'
 Write-Host "PASS: $checks agent diagnostic recovery assertions; real archives and replacements, task/build APIs mocked."
}finally{
 $full=[IO.Path]::GetFullPath($tmp);$parent=[IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\')+'\'
 if(-not $full.StartsWith($parent,[StringComparison]::OrdinalIgnoreCase) -or [IO.Path]::GetFileName($full) -notmatch '^mb-probe-recovery-[a-f0-9]{32}$'){throw 'UNSAFE_FIXTURE_CLEANUP'}
 if(Test-Path -LiteralPath $full){Remove-Item -LiteralPath $full -Recurse -Force}
}
