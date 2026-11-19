#requires -Version 7.2
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'PaytmConcurrentTlsRecovery.ps1')
. (Join-Path $PSScriptRoot 'PaytmManagedTransport.ps1')
$tmp=Join-Path $env:TEMP ('mb-health-resume-'+[guid]::NewGuid().ToString('N'))
$checks=0
function Check($ok,$name){if(-not $ok){throw "RESUME_FIXTURE_$name"};$script:checks++}
function Assert-PaytmAccountPath($p){$p}
function Get-PaytmHostContract {@{root=$root;work=$work;name='fixture'}}
function Get-PaytmOwnedHostTask($id,$enabled){Check (-not $enabled) 'DISABLED_REQUIRED';@{State=if($case -eq 'running'){'Running'}else{'Disabled'}}}
function Get-ScheduledTaskInfo {param($TaskName,$TaskPath) @{LastTaskResult=0}}
function Read-PaytmHostJson($p){Get-Content -LiteralPath $p -Raw|ConvertFrom-Json}
function Assert-PaytmHostControl {}
function Read-PaytmTransportControl {'ENABLED'}
function Get-PaytmTransportListeners {@()}
function Assert-PaytmTransportListener($rows){if($case -eq 'listener'){throw 'LISTENER_CONFLICT'}}
function Assert-PaytmNativeReceipt {}
function Assert-PaytmTransportInstallationSources {@{installationId='ea8b91471cf048aa97a0f6b939b355c7'}}
function Add-Type {param($Path)}
function Get-PaytmKeyContract {@{accountSid='fixture'}}
function Set-PaytmAccountDirectoryAcl {}
function Save-NativeRecoveryReport {}
function Set-PaytmHostControl($id,$mode){$script:mode=$mode}
function Enable-ScheduledTask {param($TaskName,$TaskPath,$ErrorAction) $script:enables++;if($case -eq 'enableFailure'){throw 'ENABLE_FAILED'}}
function Assert-PaytmInstalledTransport {}
function Start-ScheduledTask {param($TaskName,$TaskPath,$ErrorAction) $script:starts++}
function Wait-PaytmManagedHost {param($Id,$Phase,$PreviousInstance,[switch]$AwaitScheduledStart) Check ($PreviousInstance -ceq '7df0565758b84e3194d9d0f6fe302307' -and $AwaitScheduledStart) 'FRESH_START';@{instanceId='new'}}
try{
 foreach($case in @('pass','running','newFailure','otherInstance','listener','enableFailure')){
  $root=Join-Path $tmp $case;$work=Join-Path $root work;$null=New-Item -ItemType Directory -Path $work -Force
  $v=@{version=1;transportVersion=1;installationId='ea8b91471cf048aa97a0f6b939b355c7';instanceId='7df0565758b84e3194d9d0f6fe302307';phase='STOPPED';failure=$null;sequence=273;processId=9148;sessionId=0;elapsedSeconds=15;identityVerified=$true;jobContained=$true;networkContacted=$true;transportEnabled=$false;brokerReady=$false;ordersEnabled=$false;childProcessId=0}
  if($case -eq 'otherInstance'){$v.instanceId='a'*32}
  [IO.File]::WriteAllText((Join-Path $work 'status.json'),($v|ConvertTo-Json))
  [IO.File]::WriteAllText((Join-Path $root 'control.json'),' {"mode":"STOP"}')
  foreach($n in @('manifest.json','transport-control.json')){[IO.File]::WriteAllText((Join-Path $root $n),'{}')}
  if($case -eq 'newFailure'){[IO.File]::WriteAllText((Join-Path $work 'blocked.json'),'{}')}
  $before=(Get-FileHash (Join-Path $work 'status.json')).Hash
  $report=@{runId=[guid]::NewGuid().ToString('N');nativeRecoveryAttempted=$false};$starts=0;$enables=0;$mode=$null
  $failed=$false;try{Invoke-PaytmNativeRecovery @{} 'fixture' 'fixture'}catch{$failed=$true}
  Check ($failed -eq ($case -ne 'pass')) ($case+'_OUTCOME')
  Check ((Get-FileHash (Join-Path $work 'status.json')).Hash -ceq $before) 'NO_MARKER_DELETION'
  if($case -in @('pass','enableFailure')){
   Check ($report.nativeRecovery.backupVerified -and $mode -eq 'LOCKED' -and $enables -eq 1) 'ARCHIVE_BEFORE_ONE_ENABLE'
   Check ($starts -eq [int]($case -eq 'pass')) 'AT_MOST_ONE_START'
  }else{Check (-not $report.nativeRecoveryAttempted -and $enables -eq 0 -and $starts -eq 0) 'PREFLIGHT_NO_MUTATION'}
 }
 Write-Host "PASS: $checks resume archive, identity and start assertions"
}finally{
 $full=[IO.Path]::GetFullPath($tmp);$parent=[IO.Path]::GetFullPath($env:TEMP).TrimEnd('\')+'\'
 if(-not $full.StartsWith($parent,[StringComparison]::OrdinalIgnoreCase) -or [IO.Path]::GetFileName($full) -notmatch '^mb-health-resume-[a-f0-9]{32}$'){throw 'UNSAFE_FIXTURE_PATH'}
 if(Test-Path -LiteralPath $full){Remove-Item -LiteralPath $full -Recurse -Force}
}
