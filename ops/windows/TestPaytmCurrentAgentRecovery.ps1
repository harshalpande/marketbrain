#Requires -Version 7.0
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'PaytmCurrentAgentRecovery.ps1')
$tmp=Join-Path ([IO.Path]::GetTempPath()) ('mb-current-recovery-'+[guid]::NewGuid().ToString('N'))
$checks=0
function Check($v,$n){if(-not $v){throw "AGENT_RECOVERY_TEST_$n"};$script:checks++}
function Assert-PaytmAccountPath($p){$p}
function Get-PaytmHostContract {@{root=$root;work=$work;name='fixture'}}
function Get-PaytmKeyContract {@{accountSid='fixture'}}
function Assert-PaytmNativeReceipt($p){$review}
function Assert-PaytmTransportInstallationSources($r){@{installationId='fixture'}}
function Add-Type {param($Path)}
function Assert-PaytmTransportListener($v){}
function Get-PaytmTransportListeners {@()}
function Set-PaytmAccountDirectoryAcl($p,$s){}
function Save-NativeRecoveryReport {}
function Set-PaytmHostControl($id,$mode){$script:lastMode=$mode}
function Assert-PaytmInstalledTransport($r){}
function Start-ScheduledTask {param($TaskName,$TaskPath,$ErrorAction) $script:starts++;if($case -eq 'startFailure'){throw 'START_FAILED'}}
function Wait-PaytmManagedHost {param($Id,$Phase,$PreviousInstance,[switch]$AwaitScheduledStart) Check ($PreviousInstance -eq '1eef65f6e872480ebd5acfa4d361261d' -and $AwaitScheduledStart) 'FRESH_WORKER_REQUIRED';@{instanceId='new'}}
function Get-PaytmCurrentRecoverySnapshot {
 $script:snapshotCalls++
 $hashes=[ordered]@{}
 foreach($name in $names){$dir=if($name -in @('startup-failure.json','blocked.json','status.json')){$work}else{$root};$hashes[$name]=if(Test-Path (Join-Path $dir $name)){(Get-FileHash (Join-Path $dir $name)).Hash}else{'ABSENT'}}
 if($case -eq 'drift' -and $script:snapshotCalls -ge 2){$hashes['status.json']='changed'}
 @{hashes=$hashes;taskLastRunUtc='2026-11-05T15:47:47.0000000Z'}
}
try{
 foreach($case in @('pass','drift','startFailure','noCheckpoint')){
  $root=Join-Path $tmp $case;$work=Join-Path $root work;$null=New-Item -ItemType Directory -Path $work -Force
  $names=@('manifest.json','control.json','transport-control.json','session-checkpoint.json','startup-failure.json','blocked.json','status.json')
  foreach($name in $names){$dir=if($name -in @('startup-failure.json','blocked.json','status.json')){$work}else{$root};[IO.File]::WriteAllText((Join-Path $dir $name),'fixture')}
  $snap=Get-PaytmCurrentRecoverySnapshot;$review=(@{productionAfter=$snap}|ConvertTo-Json -Depth 5|ConvertFrom-Json)
  $snapshotCalls=0
  if($case -eq 'noCheckpoint'){Remove-Item -LiteralPath (Join-Path $root 'session-checkpoint.json');$snap=Get-PaytmCurrentRecoverySnapshot}
  $report=[ordered]@{runId=[guid]::NewGuid().ToString('N');nativeRecoveryAttempted=$false};$starts=0;$lastMode=$null;$failed=$false
  try{Invoke-PaytmNativeRecovery @{} 'fixture' 'fixture'}catch{$failed=$true}
  Check ($failed -eq ($case -in @('drift','startFailure'))) 'EXPECTED_OUTCOME'
  if($case -eq 'drift'){Check ($starts -eq 0 -and -not $report.nativeRecoveryAttempted -and (Test-Path (Join-Path $root 'session-checkpoint.json'))) 'DRIFT_NO_MUTATION';continue}
  Check ($starts -eq 1 -and $report.nativeRecovery.backupVerified -and $lastMode -eq 'LOCKED') 'ONE_START_VERIFIED_ARCHIVE'
  foreach($name in $names){if($snap.hashes[$name] -eq 'ABSENT'){continue};Check ((Get-FileHash (Join-Path $report.nativeRecovery.backupPath $name)).Hash -ceq $snap.hashes[$name]) 'COMPLETE_RECOVERABLE_COPY'}
  Check ((Test-Path (Join-Path $root 'session-checkpoint.json')) -eq ($case -ne 'noCheckpoint')) 'CHECKPOINT_PRESERVED'
  foreach($name in @('startup-failure.json','blocked.json','status.json')){$dir=if($name -eq 'session-checkpoint.json'){$root}else{$work};Check (-not (Test-Path (Join-Path $dir $name))) 'OLD_STATE_ARCHIVED'}
 }
 "PASS: $checks agent recovery assertions"
}finally{
 $full=[IO.Path]::GetFullPath($tmp);$parent=[IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\')+'\'
 if(-not $full.StartsWith($parent,[StringComparison]::OrdinalIgnoreCase) -or [IO.Path]::GetFileName($full) -notmatch '^mb-current-recovery-[a-f0-9]{32}$'){throw 'UNSAFE_FIXTURE_CLEANUP'}
 if(Test-Path -LiteralPath $full){Remove-Item -LiteralPath $full -Recurse -Force}
}
