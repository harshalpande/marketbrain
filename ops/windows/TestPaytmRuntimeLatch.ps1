#Requires -Version 7.0
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'PaytmRuntimeLatch.ps1')
$checks=0
function Check($v,$n){if(-not $v){throw "LATCH_TEST_$n"};$script:checks++}
$before=@{instanceId='owned';installationId='install';processId=123}
$status=@{instanceId='owned';installationId='install';processId=123;phase='BLOCKED';failure='TRANSPORT_LISTENER_CONFLICT';brokerReady=$false;ordersEnabled=$false;childProcessId=0}
$blocked=@{instanceId='owned';failure='TRANSPORT_LISTENER_CONFLICT'}
$startup=@{instanceId='owned';installationId='install';processId=123;failure='TRANSPORT_LISTENER_CONFLICT'}
Assert-PaytmExpectedListenerLatch $status $blocked $startup $before;Check $true 'EXPECTED_LATCH'
foreach($field in @('instanceId','installationId','processId','phase','failure','ordersEnabled','childProcessId')){
 $bad=$status.Clone();$bad[$field]=switch($field){ordersEnabled {$true};processId {999};childProcessId {999};default {'UNRELATED'}}
 $failed=$false;try{Assert-PaytmExpectedListenerLatch $bad $blocked $startup $before}catch{$failed=$true};Check $failed ('REJECT_'+$field)
}
# Actual private fixture files exercise archive/recheck/removal; scheduled-task APIs substituted.
$fixture=Join-Path ([IO.Path]::GetTempPath()) ('latch-fixture-'+[guid]::NewGuid().ToString('N'))
$root=Join-Path $fixture 'root';$work=Join-Path $fixture 'work'
$null=New-Item -ItemType Directory -Path $root,$work
function Get-PaytmHostContract {@{root=$root;work=$work;name='fixture'}}
function Assert-PaytmAccountPath($p){$p}
function Set-PaytmAccountDirectoryAcl {}
function Get-PaytmKeyContract {@{accountSid='fixture'}}
function Get-PaytmOwnedHostTask {@{State='Ready'}}
function Disable-ScheduledTask {}
function Enable-ScheduledTask {}
function Assert-PaytmTransportInstallationSources {}
function Read-PaytmHostJson($p){Get-Content -LiteralPath $p -Raw|ConvertFrom-Json}
function Set-PaytmHostControl {}
function Set-PaytmTransportControl {}
function Start-ScheduledTask {$script:starts++}
function Wait-PaytmManagedHost {param($Id,$Phase,$PreviousInstance,$TimeoutSeconds,[switch]$AwaitScheduledStart) @{instanceId='new';phase=$Phase}}
function Invoke-PaytmApplicationHttp {@{status='LOCKED'}}
function Invoke-PaytmApplicationHead {}
[IO.File]::WriteAllText((Join-Path $work 'instance.lock'),'')
foreach($pair in @(@('status.json',$status),@('blocked.json',$blocked),@('startup-failure.json',$startup))){[IO.File]::WriteAllText((Join-Path $work $pair[0]),($pair[1]|ConvertTo-Json))}
$report=@{};$script:starts=0
Restore-PaytmOwnedListenerLatch $before @{} 'test' {}
Check ($report.archive.verified -and $report.archive.hashes.Count -eq 3) 'ARCHIVE_VERIFIED'
Check ($starts -eq 1 -and $report.recoveryStartAttempts -eq 1) 'EXACTLY_ONE_START'
foreach($n in @('status.json','blocked.json','startup-failure.json')){
 Check (-not (Test-Path -LiteralPath (Join-Path $work $n))) 'EXPECTED_MARKER_REMOVED'
 Check (Test-Path -LiteralPath (Join-Path $report.archive.path $n)) 'EVIDENCE_RETAINED'
 Remove-Item -LiteralPath (Join-Path $report.archive.path $n)
}
[IO.Directory]::Delete($report.archive.path,$false)
Remove-Item -LiteralPath (Join-Path $work 'instance.lock')
[IO.Directory]::Delete($root,$false);[IO.Directory]::Delete($work,$false);[IO.Directory]::Delete($fixture,$false)
# Execute the real orchestration; replace only external runtime adapters.
function New-PaytmConflictSocket {
 $script:ownedSocket=[pscustomobject]@{disposed=$false}
 $script:ownedSocket|Add-Member ScriptMethod Dispose {$this.disposed=$true}
 return $script:ownedSocket
}
function Wait-PaytmExpectedListenerLatch {
 if($script:mode -eq 'FAIL'){throw 'FIXTURE_UNRELATED_FAILURE'}
 @{expected=$true}
}
function Read-PaytmExpectedListenerLatch {@{expected=$true}}
function Get-PaytmTransportListeners {}
function Assert-PaytmTransportListener {}
function Restore-PaytmOwnedListenerLatch {$script:restores++}
foreach($mode in @('PASS','FAIL')){
 $script:mode=$mode;$script:restores=0;$report=@{runId='test'};$failed=$false
 try{Invoke-PaytmRuntimeLatch @{} @{installationId='fixture'} {}}catch{$failed=$true}
 Check ($failed -eq ($mode -eq 'FAIL')) 'ORCHESTRATION_RESULT'
 Check $ownedSocket.disposed 'SOCKET_ALWAYS_DISPOSED'
 Check ($restores -eq $(if($mode -eq 'PASS'){1}else{0})) 'NO_RESTORE_ON_UNRELATED_FAILURE'
 if($mode -eq 'PASS'){Check ($report.quiet.seconds -ge 10 -and $report.latchPersistencePassed) 'REAL_QUIET_INTERVAL'}
}
@{status='RUNTIME_LATCH_HELPER_PASSED';assertions=$checks;realArchiveFiles=$true;runtimeApisMocked=$true}|ConvertTo-Json
