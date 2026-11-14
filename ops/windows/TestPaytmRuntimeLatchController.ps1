#Requires -Version 7.0
$ErrorActionPreference='Stop'
$source=Get-Content -LiteralPath (Join-Path $PSScriptRoot 'TestPaytmRuntimeLatchBundle.ps1') -Raw
$start=$source.IndexOf('foreach($n in @(');$end=$source.IndexOf('$watch=', $start)
$source=$source.Remove($start,$end-$start).Replace('$PSScriptRoot',("'"+$PSScriptRoot.Replace("'","''")+"'"))
$fixture=Join-Path ([IO.Path]::GetTempPath()) ('latch-controller-'+[guid]::NewGuid().ToString('N'))
$null=New-Item -ItemType Directory -Path $fixture
function Assert-PaytmAccountPath($p){$p}
function Assert-PaytmCustodyController {}
function Import-Module {}
function Get-PaytmAccountContract {@{root=$fixture}}
function Get-FileHash {@{Hash='078A34DB0A46951EB98C5A08063F9FC76DB6EC75C175A3572CEE3D65DA4FAB4B'}}
function Read-PaytmHostJson {@{}}
function Assert-PaytmTransportAcceptance {}
function Assert-PaytmInstalledTransport {@{installationId='fixture'}}
function Initialize-PaytmManagedApplication {
 if($script:mode -eq 'PREFLIGHT_FAIL'){throw 'FIXTURE_PREFLIGHT'}
 $application.Ready=$true;$application.BootId='boot';$application.Id='container';$application.Before=@{Image='image';State=@{StartedAt='start'}};$application.BeforeAccount='same'
}
function Invoke-PaytmRuntimeLatch {
 param($Receipt,$Manifest,$Checkpoint)
 $report.mutationAttempted=$true
 & $Checkpoint
 if($script:mode -in @('LATCH_FAIL','STOP_FAIL')){throw 'FIXTURE_LATCH_FAILURE'}
 $report.runtimeLatchPassed=$true;$report.latchPersistencePassed=$true;$report.applicationNoFallbackPassed=$true;$report.recoveryStartAttempts=1
}
function Invoke-PaytmApplicationHttp {
 if($script:mode -eq 'LOCK_FAIL'){throw 'FIXTURE_LOCK_FAILURE'}
 @{state='LOCKED';bootId='boot'}
}
function Assert-PaytmWriterLocked {}
function Get-PaytmApplicationContainer {@{Id='container';Image='image';State=@{StartedAt='start'}}}
function Read-PaytmPaperAccount {if($script:mode -eq 'ACCOUNT_CHANGED'){'changed'}else{'same'}}
function Stop-PaytmFailedManagedHost {
 $script:stops++
 if($script:mode -eq 'STOP_FAIL'){throw 'FIXTURE_STOP_FAILURE'}
}
function Write-PaytmSessionReport($p,$v){[IO.File]::WriteAllText($p,($v|ConvertTo-Json -Depth 16))}
$count=0
foreach($mode in @('PASS','PREFLIGHT_FAIL','LATCH_FAIL','LOCK_FAIL','ACCOUNT_CHANGED','STOP_FAIL')){
 $script:mode=$mode;$script:stops=0;$dir=Join-Path $fixture $mode;$failed=$false
 try{& ([scriptblock]::Create($source)) -OutputDirectory $dir}catch{$failed=$true}
 $f=@(Get-ChildItem -LiteralPath $dir -Filter '*.json');if($f.Count -ne 1){throw 'CONTROLLER_REPORT_COUNT'}
 $r=Get-Content -LiteralPath $f[0].FullName -Raw|ConvertFrom-Json
 if($mode -eq 'PASS'){
  if($failed -or $r.status -ne 'RUNTIME_LISTENER_LATCH_AND_RECOVERY_PASSED_CLOCK_PENDING' -or $stops -ne 0){throw 'CONTROLLER_SUCCESS'}
 }else{
  if(-not $failed -or $r.status -ne 'REVIEW_REQUIRED'){throw 'CONTROLLER_FAIL_CLOSED'}
  if($mode -eq 'PREFLIGHT_FAIL'){if($stops -ne 0){throw 'CONTROLLER_PREFLIGHT_MUTATED'}}elseif($stops -ne 1){throw 'CONTROLLER_FAILURE_NOT_STOPPED'}
 }
 if($mode -eq 'STOP_FAIL' -and ($r.failure -ne 'FIXTURE_LATCH_FAILURE' -or $r.stopFailure -ne 'FIXTURE_STOP_FAILURE')){throw 'CONTROLLER_FIRST_CAUSE_LOST'}
 if($r.ordersEnabled -or $r.credentialsUsed){throw 'CONTROLLER_SCOPE'}
 Remove-Item -LiteralPath $f[0].FullName;[IO.Directory]::Delete($dir,$false);$count++
}
Remove-Item -LiteralPath (Join-Path $fixture 'supervisor-install.lock');[IO.Directory]::Delete($fixture,$false)
@{status='RUNTIME_LATCH_CONTROLLER_PASSED';workflows=$count;runtimeApisMocked=$true}|ConvertTo-Json
