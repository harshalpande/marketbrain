#Requires -Version 7.0
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'PaytmSupervisorHost.ps1')
. (Join-Path $PSScriptRoot 'PaytmTlsRecovery.ps1')
$idleBody=${function:Assert-PaytmTlsIdle}
$tmp=Join-Path ([IO.Path]::GetTempPath()) ('mb-tls-recovery-'+[guid]::NewGuid().ToString('N'))
$checks=0
function Check($Ok,$Name){if(-not $Ok){throw $Name};$script:checks++}
function Assert-PaytmAccountPath($p){$p}
function Get-PaytmHostContract {@{root=$root;work=$work;name='fixture'}}
function Get-PaytmKeyContract {@{accountSid='fixture'}}
function Assert-PaytmNativeReceipt($p){$review}
function Assert-PaytmTransportInstallationSources($r){Read-PaytmHostJson (Join-Path $root 'manifest.json')}
function Add-Type {param($Path)}
function Assert-PaytmTlsIdle($r,$id){if($case -eq 'drift'){throw 'HOST_TLS_STATUS_DRIFT'}}
function Set-PaytmAccountDirectoryAcl {}
function Save-NativeRecoveryReport {}
function Test-PaytmTlsObservedTransportHash($h){$h -ceq $patchHash}
function Set-PaytmHostControl($id,$mode){$script:mode=$mode}
function Enable-ScheduledTask {param($TaskName,$TaskPath,$ErrorAction) $script:enables++;if($case -eq 'enableFailure'){throw 'ENABLE_FAILED'}}
function Assert-PaytmInstalledTransport {}
function Start-ScheduledTask {param($TaskName,$TaskPath,$ErrorAction) $script:starts++;if($case -eq 'startFailure'){throw 'START_FAILED'}}
function Wait-PaytmManagedHost {param($Id,$Phase,$PreviousInstance,[switch]$AwaitScheduledStart)
 Check ($PreviousInstance -ceq '7d07b78014764b6497f70761d7348ff0' -and $AwaitScheduledStart) 'FRESH_WORKER_REQUIRED'
 @{instanceId='new'}
}
try{
 foreach($case in @('pass','drift','enableFailure','startFailure')){
  $root=Join-Path $tmp $case;$work=Join-Path $root work;$source=Join-Path $root source
  $null=New-Item -ItemType Directory -Path $work,$source -Force
  foreach($name in @('transport.ps1','control.json','transport-control.json')){[IO.File]::WriteAllText((Join-Path $root $name),'old')}
  [IO.File]::WriteAllText((Join-Path $work 'status.json'),'old-status')
  [IO.File]::WriteAllText((Join-Path $source 'PaytmSupervisorTransport.ps1'),'new-diagnostics')
  $patchHash=(Get-FileHash (Join-Path $source 'PaytmSupervisorTransport.ps1')).Hash
  $oldHash=(Get-FileHash (Join-Path $root 'transport.ps1')).Hash
  Write-PaytmHostJson (Join-Path $root 'manifest.json') @{installationId='fixture';hashes=@{'transport.ps1'=$oldHash}}
  $review=@{installedFiles=@(@{name='transport.ps1';actualSha256=$oldHash})}
  $report=[ordered]@{runId=[guid]::NewGuid().ToString('N');nativeRecoveryAttempted=$false};$starts=0;$enables=0;$mode=$null
  $failed=$false;try{Invoke-PaytmNativeRecovery @{} 'fixture' $source}catch{$failed=$true}
  Check ($failed -eq ($case -ne 'pass')) ($case+'_OUTCOME')
  if($case -eq 'drift'){
   Check ($starts -eq 0 -and $enables -eq 0 -and -not $report.nativeRecoveryAttempted -and (Test-Path (Join-Path $work 'status.json'))) 'DRIFT_PRESERVED'
   continue
  }
  Check ($report.nativeRecovery.backupVerified -and $report.nativeRecovery.transportUpdated -and $report.nativeRecovery.manifestUpdated) 'PATCH_AND_BACKUP'
  Check ((Get-FileHash (Join-Path $report.nativeRecovery.backupPath 'transport.ps1')).Hash -ceq $oldHash) 'OLD_TRANSPORT_PRESERVED'
  foreach($name in @('control.json','transport-control.json','manifest.json','status.json')){Check (Test-Path (Join-Path $report.nativeRecovery.backupPath $name)) 'STATE_ARCHIVED'}
  Check ((Get-FileHash (Join-Path $root 'transport.ps1')).Hash -ceq $patchHash) 'PATCH_INSTALLED'
  Check ((Read-PaytmHostJson (Join-Path $root 'manifest.json')).hashes.'transport.ps1' -ceq $patchHash) 'MANIFEST_MATCHES'
  Check (-not (Test-Path (Join-Path $work 'status.json'))) 'OLD_STATUS_ARCHIVED'
  Check ($enables -eq 1 -and $starts -eq [int]($case -ne 'enableFailure') -and $mode -eq 'LOCKED') 'START_BOUND'
 }
 # Exercise the real idle gate, including PS7 timestamp deserialization.
 function Get-PaytmOwnedHostTask($Id,$Enabled){Check (-not $Enabled) 'DISABLED_TASK_REQUIRED';@{State=$script:taskState}}
 function Get-ScheduledTaskInfo {param($TaskName,$TaskPath) @{LastTaskResult=267014}}
 function Get-Process {param($ErrorAction) @()}
 function Assert-PaytmHostControl {}
 function Read-PaytmTransportControl {'ENABLED'}
 function Get-PaytmWorkerEvidenceFile($Path){@{readSucceeded=$true;length=1169;value=$script:savedValue}}
 function Get-PaytmTransportListeners {@()}
 function Assert-PaytmTransportListener {}
 Write-PaytmHostJson (Join-Path $root 'control.json') @{mode='STOP'}
 $script:savedValue=@{phase='BACKOFF';observedUtc='2026-11-13T06:26:34.1054910Z';sequence=220}
 $review=@{workerDiagnostics=@{files=@{'status.json'=@{length=1169;value=($savedValue|ConvertTo-Json|ConvertFrom-Json)}}}}
 $script:taskState='Disabled'
 & $idleBody $review fixture
 Check $true 'REAL_IDLE_WITH_NORMALIZED_TIMESTAMP'
 $script:taskState='Ready';$failed=$false;try{& $idleBody $review fixture}catch{$failed=$true}
 Check $failed 'REAL_IDLE_REJECTS_ENABLED_TASK'
 $script:taskState='Disabled';$script:savedValue.sequence=221;$failed=$false;try{& $idleBody $review fixture}catch{$failed=$true}
 Check $failed 'REAL_IDLE_REJECTS_CHANGED_STATUS'
 Write-Host "PASS: $checks TLS recovery assertions; task/ACL APIs mocked, real archive and atomic replacement."
}finally{
 $full=[IO.Path]::GetFullPath($tmp);$parent=[IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\')+'\'
 if(-not $full.StartsWith($parent,[StringComparison]::OrdinalIgnoreCase) -or [IO.Path]::GetFileName($full) -notmatch '^mb-tls-recovery-[a-f0-9]{32}$'){throw 'UNSAFE_FIXTURE_CLEANUP'}
 if(Test-Path -LiteralPath $full){Remove-Item -LiteralPath $full -Recurse -Force}
}
