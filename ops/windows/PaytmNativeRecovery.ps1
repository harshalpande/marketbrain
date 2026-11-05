#Requires -Version 7.0
# One reviewed stopped worker only. Never reset another failure or retry a partial install.
function Assert-PaytmNativeReceipt([string]$Path){
 $null=Assert-PaytmAccountPath $Path
 if((Get-FileHash -LiteralPath $Path).Hash -cne '857B0C3E835E252EC13DBA0FCFE927A1DF72CAB1DC043AE39F236013EC050024'){throw 'HOST_NATIVE_RECEIPT_NOT_REVIEWED'}
 $r=Read-PaytmHostJson $Path 65536
 if($r.runId -cne '1290fc4e5fc448ac98c749ff437f4a8d' -or $r.status -cne 'NATIVE_FAILURE_EVIDENCE_CAPTURED' -or -not $r.metadataComplete){throw 'HOST_NATIVE_RECEIPT_INVALID'}
 $r
}
function Assert-PaytmNativeIdle([string]$Id,[ValidateSet('LOCKED','STOP')][string]$Mode){
 $c=Get-PaytmHostContract;$t=Get-PaytmOwnedHostTask $Id
 if([string]$t.State -cin @('Running','Queued') -or (Get-ScheduledTaskInfo -TaskName $c.name -TaskPath '\').LastTaskResult -ne 1){throw 'HOST_NATIVE_TASK_CHANGED'}
 if(@(Get-Process -ErrorAction Stop|Where-Object Id -EQ 18156).Count){throw 'HOST_NATIVE_OLD_PROCESS_PRESENT'}
 $v=Read-PaytmHostJson (Join-Path $c.root 'control.json');Assert-PaytmHostControl $v $Id
 if($v.mode -cne $Mode -or (Read-PaytmTransportControl $c.root $Id) -cne 'ENABLED'){throw 'HOST_NATIVE_CONTROL_CHANGED'}
 Assert-PaytmTransportListener (Get-PaytmTransportListeners)
}
function Invoke-PaytmNativeBuild([string]$Source,[string]$Destination){
 # Both paths belong to the newly created, administrator-protected archive.
 $code="`$ErrorActionPreference='Stop'; Import-Module ([IO.Path]::Combine(`$PSHOME,'Modules','Microsoft.PowerShell.Utility','Microsoft.PowerShell.Utility.psd1')) -ErrorAction Stop; Add-Type -Path '"+$Source+"' -OutputAssembly '"+$Destination+"'; Add-Type -Path '"+$Destination+"'; `$r=[MarketBrain.Supervisor.NativeCommand]::Run('C:\Windows\System32\curl.exe',[string[]]@('--version'),5000); if(`$r.ExitCode -ne 0 -or `$r.TimedOut){throw 'HOST_NATIVE_BUILD_PROBE_FAILED'}"
 $encoded=[Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($code))
 $r=Invoke-PaperRuntimeProcess (Get-PaytmHostContract).executable @('-NoLogo','-NoProfile','-NonInteractive','-EncodedCommand',$encoded) (Get-PaytmHostContract).root 45
 $report.nativeRecovery.build=@{exitCode=$r.exitCode;elapsedSeconds=$r.elapsedSeconds;stderrCharacters=$r.stderr.Length}
 if($r.exitCode -ne 0 -or -not (Test-Path -LiteralPath $Destination)){throw 'HOST_NATIVE_BUILD_FAILED'}
}
function Invoke-PaytmNativeRecovery($Receipt,[string]$ReviewPath,[string]$SourceDirectory){
 $c=Get-PaytmHostContract;$held=$null;$review=Assert-PaytmNativeReceipt $ReviewPath
 $m=Assert-PaytmTransportInstallationSources $Receipt;$id=$m.installationId
 foreach($f in $review.installedFiles){if($m.hashes.($f.name) -cne $f.actualSha256){throw 'HOST_NATIVE_ALREADY_CHANGED'}}
 if(Test-Path -LiteralPath (Join-Path $c.root 'session-checkpoint.json')){throw 'HOST_NATIVE_SESSION_CHECKPOINT_PRESENT'}
 $source=Assert-PaytmAccountPath (Join-Path $SourceDirectory 'PaytmSupervisorNative.cs')
 $runner=Assert-PaytmAccountPath (Join-Path $SourceDirectory 'RunPaytmGatewaySupervisor.ps1')
 if(-not (Test-PaytmNativeRepairSourceHash (Get-FileHash -LiteralPath $source).Hash) -or -not (Test-PaytmNativeRunnerHash (Get-FileHash -LiteralPath $runner).Hash)){throw 'HOST_NATIVE_PATCH_NOT_REVIEWED'}
 Add-Type -Path (Join-Path $c.root 'transport.dll')
 Assert-PaytmNativeIdle $id LOCKED
 try{
  $held=[IO.File]::Open((Assert-PaytmAccountPath (Join-Path $c.work 'instance.lock')),'OpenOrCreate','ReadWrite','None')
  $hashes=@{}
  foreach($n in @('startup-failure.json','blocked.json','status.json')){
   $path=Assert-PaytmAccountPath (Join-Path $c.work $n);$v=Get-PaytmWorkerEvidenceFile $path;$e=$review.workerDiagnostics.files.$n
   if(-not $v.present -or -not $v.readSucceeded -or $v.length -ne $e.length -or ($v.value|ConvertTo-Json -Depth 8 -Compress) -cne ($e.value|ConvertTo-Json -Depth 8 -Compress)){throw 'HOST_NATIVE_FAILURE_CHANGED'}
   $hashes[$n]=(Get-FileHash -LiteralPath $path).Hash
  }
  $backup=Assert-PaytmAccountPath (Join-Path $c.root ('native-recovery-'+$report.runId))
  if(Test-Path -LiteralPath $backup){throw 'HOST_NATIVE_ARCHIVE_EXISTS'}
  $null=New-Item -ItemType Directory -Path $backup;Set-PaytmAccountDirectoryAcl $backup (Get-PaytmKeyContract).accountSid
  $report.nativeRecovery=[ordered]@{reviewedRunId=$review.runId;backupPath=$backup;backupHashes=@{};backupVerified=$false;nativeUpdated=$false;runnerUpdated=$false;manifestUpdated=$false;markersArchived=$false;startAttempts=0;healthy=$false}
  foreach($n in @('native.dll','runner.ps1','manifest.json','control.json','transport-control.json','startup-failure.json','blocked.json','status.json')){
   $from=Assert-PaytmAccountPath (Join-Path $(if($hashes.ContainsKey($n)){$c.work}else{$c.root}) $n)
   $h=(Get-FileHash -LiteralPath $from).Hash;Copy-Item -LiteralPath $from -Destination (Join-Path $backup $n)
   if((Get-FileHash -LiteralPath (Join-Path $backup $n)).Hash -cne $h){throw 'HOST_NATIVE_BACKUP_MISMATCH'}
   $report.nativeRecovery.backupHashes[$n]=$h
  }
  $report.nativeRecovery.backupVerified=$true;Save-NativeRecoveryReport
  Copy-Item -LiteralPath $source -Destination (Join-Path $backup 'new-native.cs')
  Copy-Item -LiteralPath $runner -Destination (Join-Path $backup 'new-runner.ps1')
  if(-not (Test-PaytmNativeRepairSourceHash (Get-FileHash -LiteralPath (Join-Path $backup 'new-native.cs')).Hash) -or -not (Test-PaytmNativeRunnerHash (Get-FileHash -LiteralPath (Join-Path $backup 'new-runner.ps1')).Hash)){throw 'HOST_NATIVE_STAGED_PATCH_DRIFT'}
  Invoke-PaytmNativeBuild (Join-Path $backup 'new-native.cs') (Join-Path $backup 'new-native.dll')
  $report.nativeRecovery.newNativeHash=(Get-FileHash -LiteralPath (Join-Path $backup 'new-native.dll')).Hash
  $report.nativeRecovery.newRunnerHash=(Get-FileHash -LiteralPath (Join-Path $backup 'new-runner.ps1')).Hash
  Assert-PaytmNativeIdle $id LOCKED;$null=Assert-PaytmTransportInstallationSources $Receipt
  $report.nativeRecoveryAttempted=$true;Save-NativeRecoveryReport
  Set-PaytmHostControl $id STOP
  foreach($pair in @(@('new-native.dll','native.dll','nativeUpdated'),@('new-runner.ps1','runner.ps1','runnerUpdated'))){
   $tmp=Assert-PaytmAccountPath (Join-Path $c.root ($pair[1]+'.'+$report.runId+'.tmp'))
   if(Test-Path -LiteralPath $tmp){throw 'HOST_NATIVE_TEMP_EXISTS'}
   Copy-Item -LiteralPath (Join-Path $backup $pair[0]) -Destination $tmp
   if((Get-FileHash -LiteralPath $tmp).Hash -cne (Get-FileHash -LiteralPath (Join-Path $backup $pair[0])).Hash){throw 'HOST_NATIVE_REPLACEMENT_DRIFT'}
   [IO.File]::Replace($tmp,(Join-Path $c.root $pair[1]),[Management.Automation.Language.NullString]::Value)
   $report.nativeRecovery[$pair[2]]=$true
  }
  $m.hashes.'native.dll'=$report.nativeRecovery.newNativeHash;$m.hashes.'runner.ps1'=$report.nativeRecovery.newRunnerHash
  Write-PaytmHostJson (Join-Path $c.root 'manifest.json') $m
  $null=Assert-PaytmTransportInstallationSources $Receipt;$report.nativeRecovery.manifestUpdated=$true;Save-NativeRecoveryReport
  Assert-PaytmNativeIdle $id STOP
  foreach($n in $hashes.Keys){if((Get-FileHash -LiteralPath (Join-Path $c.work $n)).Hash -cne $hashes[$n]){throw 'HOST_NATIVE_MARKER_DRIFT'}}
  foreach($n in $hashes.Keys){Remove-Item -LiteralPath (Join-Path $c.work $n) -ErrorAction Stop}
  $report.nativeRecovery.markersArchived=$true
  Set-PaytmHostControl $id LOCKED;$null=Assert-PaytmInstalledTransport $Receipt
 }finally{if($held){$held.Dispose()}}
 $report.nativeRecovery.startAttempts=1;Save-NativeRecoveryReport
 Start-ScheduledTask -TaskName $c.name -TaskPath '\' -ErrorAction Stop
 $report.nativeRecovery.first=Wait-PaytmManagedHost $id TRANSPORT_READY '6e74e3275a014678bb886b4574cfe45f' -AwaitScheduledStart
 $report.nativeRecovery.healthy=$true;Save-NativeRecoveryReport
}
function Assert-PaytmNativeSoakSample($First,$Current){
 Assert-PaytmManagedStatus $Current $First.installationId TRANSPORT_READY
 Assert-PaytmHostAdvance $First $Current
 if($Current.instanceId -cne $First.instanceId -or $Current.processId -ne $First.processId){throw 'HOST_NATIVE_WORKER_REPLACED'}
 if($Current.elapsedSeconds-$First.elapsedSeconds -gt 45){throw 'HOST_NATIVE_OBSERVATION_GAP'}
 $age=$Current.transportState.lastSeconds-$Current.transportState.lastHealthSeconds
 if($age -lt 0 -or $age -gt 30){throw 'HOST_NATIVE_HEALTH_STALE'}
}
