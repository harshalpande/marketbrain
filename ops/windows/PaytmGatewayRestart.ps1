#Requires -Version 7.0
# Read-only runtime verification. No task start, service restart or credential operation.
function Assert-PaytmTransportAcceptance($Value){
 if($Value.runId -cne '8ac7cdda3ca7475eb001df485797cb70' -or $Value.status -cne 'MANAGED_WINDOWS_TRANSPORT_AND_APPLICATION_ROUTE_PASSED_BOOT_PENDING' -or $Value.stage -cne 'COMPLETE' -or $Value.failure -or $Value.cleanupFailure){throw 'STARTUP_RECEIPT_NOT_ACCEPTED'}
 foreach($name in @('upgradeApplied','duplicateStartPassed','disabledRoutePassed','childRecoveryPassed','persistentStopPassed','restartPassed','finalApplicationLockVerified','accountPreserved')){if($Value.$name -isnot [bool] -or -not $Value.$name){throw 'STARTUP_RECEIPT_PROOF_MISSING'}}
 foreach($name in @('ordersEnabled','brokerCredentialsUsed','vpsChanged','taskReRegistered','keyImported','rebootTested')){if($Value.$name -isnot [bool] -or $Value.$name){throw 'STARTUP_RECEIPT_SCOPE'}}
 if(@($Value.applicationRouteChecks).Count -ne 4 -or @($Value.applicationRouteChecks|Where-Object passed -NE $true).Count){throw 'STARTUP_RECEIPT_ROUTE_CHECKS'}
 foreach($name in @('first','duplicate','reenabled','recovered','final')){Assert-PaytmManagedStatus $Value.$name $Value.before.installationId TRANSPORT_READY}
 Assert-PaytmHostAdvance $Value.first $Value.duplicate
 Assert-PaytmHostAdvance $Value.reenabled $Value.recovered
 if($Value.first.childProcessId -ne $Value.duplicate.childProcessId -or $Value.reenabled.childProcessId -eq $Value.recovered.childProcessId -or $Value.recovered.transportState.attempts -le $Value.reenabled.transportState.attempts){throw 'STARTUP_RECEIPT_RECOVERY'}
 Assert-PaytmManagedStatus $Value.disabled $Value.before.installationId LOCKED
 foreach($name in @('stopped','stoppedRestart')){Assert-PaytmManagedStatus $Value.$name $Value.before.installationId STOPPED}
 if($Value.stopped.instanceId -ceq $Value.stoppedRestart.instanceId -or $Value.stoppedRestart.networkContacted -or $Value.stoppedRestart.signingVerified -or $Value.final.instanceId -ceq $Value.stoppedRestart.instanceId){throw 'STARTUP_RECEIPT_STOP'}
}
function Test-PaytmFirstFailureRunnerHash([string]$Hash){
 # E220 reviewed first-cause preservation patch, exact LF and CRLF bytes only.
 $Hash -cin @('991BCFF40E468E5C88DC905BED9E3CBA025A4C1D1BBF79F797F84F4A66557633','B05057A4A0409F76CC2F55B941FBA5EF46483F0B6697F7842E3AA4B3C5089C3F')
}
function Test-PaytmObservedTransportHash([string]$Hash){
 # E224: bounded stderr drain and structured SSH observations, exact LF/CRLF sources.
 $Hash -cin @('1D36CDBCBAB8BECF1D60355454CCCC7E5EFC370E9FDFF5D19AF3FE439C8E9A75','0A0686E1DED26378AAC7365AE0E426485FDB9FB7C0849D2C9F30BE349781DE81') -or (Test-PaytmOutboundTransportHash $Hash)
}
function Test-PaytmOutboundTransportHash([string]$Hash){
 # E225: exact TCP connect denial is network loss; SSH authentication denial stays blocked.
 $Hash -cin @('86249FB0CDF7A1D1316C3B3AD6C7F313FDC9E3B7ED2DDA192115759AC612D59F','0C9405BE49E04763C3FA757A79119A7E5B9D1EC6EC6657EF1B2E7AD0E6AA3656') -or (Test-PaytmVerboseTcpTransportHash $Hash)
}
function Test-PaytmVerboseTcpTransportHash([string]$Hash){
 # E226 exact verbose TCP-denial reproduction. Authentication denials still latch.
 $Hash -cin @('4AA20733D04ED17930790B8F494078754CD129F0836E0F251C7ADAA567688E63','0E9DC20860BD68C66EB5B89D54B54D761888FE8501B265A8B5CBC68931716A69')
}
function Assert-PaytmTransportInstallationSources($Receipt){
 $c=Get-PaytmHostContract;$sid=(Get-PaytmKeyContract).accountSid
 foreach($p in @($c.root,$c.work)){$null=Assert-PaytmAccountPath $p;Assert-PaytmAccountAcl (Get-Acl -LiteralPath $p) $sid -Writable:($p -ceq $c.work)}
 $m=Read-PaytmHostJson (Join-Path $c.root 'manifest.json')
 if($m.version -ne 1 -or $m.transportVersion -ne 1 -or $m.installationId -cne 'ea8b91471cf048aa97a0f6b939b355c7'){throw 'STARTUP_INSTALLATION_MISMATCH'}
 foreach($name in @('runner.ps1','host.ps1','native.dll','gateway.ps1','transport.ps1','transport.dll')){
  if((Get-FileHash -LiteralPath (Assert-PaytmAccountPath (Join-Path $c.root $name))).Hash -cne $m.hashes.$name){throw 'STARTUP_INSTALLED_HASH_DRIFT'}
 }
 foreach($pair in @(@('runner.ps1','RunPaytmGatewaySupervisor.ps1'),@('gateway.ps1','PaytmGatewaySupervisor.ps1'),@('transport.ps1','PaytmSupervisorTransport.ps1'))){
  $accepted=$m.hashes.($pair[0]) -ceq $Receipt.sourceHashes.($pair[1])
  if($pair[0] -ceq 'runner.ps1' -and (Test-PaytmFirstFailureRunnerHash $m.hashes.'runner.ps1')){$accepted=$true}
  if($pair[0] -ceq 'transport.ps1' -and (Test-PaytmObservedTransportHash $m.hashes.'transport.ps1')){$accepted=$true}
  if(-not $accepted){throw 'STARTUP_UNACCEPTED_SOURCE'}
 }
 $m
}
function Assert-PaytmInstalledTransport($Receipt){
 $c=Get-PaytmHostContract;$m=Assert-PaytmTransportInstallationSources $Receipt
 $control=Read-PaytmHostJson (Join-Path $c.root 'control.json');Assert-PaytmHostControl $control $m.installationId
 if($control.mode -cne 'LOCKED' -or (Read-PaytmTransportControl $c.root $m.installationId) -cne 'ENABLED'){throw 'STARTUP_TRANSPORT_NOT_ENABLED'}
 foreach($name in @('blocked.json','startup-failure.json')){if(Test-Path -LiteralPath (Join-Path $c.work $name)){throw 'STARTUP_WORKER_FAILURE_PRESENT'}}
 $null=Get-PaytmOwnedHostTask $m.installationId
 Add-Type -Path (Join-Path $c.root 'transport.dll')
 $m
}
function Get-PaytmWindowsBootUtc {
 # Use the Windows-provided PS5 CIM module; portable PS7 distributions may omit it.
 $code='$ErrorActionPreference="Stop";(Get-CimInstance Win32_OperatingSystem -OperationTimeoutSec 10 -ErrorAction Stop).LastBootUpTime.ToUniversalTime().ToString("o")'
 $encoded=[Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($code))
 $r=Invoke-PaperRuntimeProcess 'C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe' @('-NoLogo','-NoProfile','-NonInteractive','-EncodedCommand',$encoded) $route.Root 25
 if($r.exitCode -ne 0 -or $r.stdout.Trim() -cnotmatch '^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d{7}Z$'){throw 'STARTUP_BOOT_QUERY_FAILED'}
 $r.stdout.Trim()
}
function Get-PaytmRestartObservation([string]$Id){
 $worker=Wait-PaytmManagedHost $Id TRANSPORT_READY
 $c=Get-PaytmHostContract;$bootUtc=Get-PaytmWindowsBootUtc
 $machine=Get-ItemPropertyValue -LiteralPath 'HKLM:\SOFTWARE\Microsoft\Cryptography' -Name MachineGuid -ErrorAction Stop
 $sha=[Security.Cryptography.SHA256]::Create()
 try{$machineHash=[BitConverter]::ToString($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($machine))).Replace('-','')}finally{$sha.Dispose()}
 $owner=Get-Process -Id $worker.processId -ErrorAction Stop;$child=Get-Process -Id $worker.childProcessId -ErrorAction Stop
 try{
  if($owner.SessionId -ne 0 -or $owner.Path -ine $c.executable -or $child.Path -ine 'C:\Windows\System32\OpenSSH\ssh.exe' -or $child.StartTime.ToUniversalTime().Ticks -ne $worker.childStartTicks){throw 'STARTUP_PROCESS_IDENTITY'}
  $started=$owner.StartTime.ToUniversalTime().ToString('o')
 }finally{$owner.Dispose();$child.Dispose()}
 $task=Get-ScheduledTaskInfo -TaskName $c.name -TaskPath '\' -ErrorAction Stop
 [pscustomobject]@{machineHash=$machineHash;bootUtc=$bootUtc;workerStartUtc=$started;collectorStartUtc=$collectorStartedUtc;
  taskLastRunUtc=$task.LastRunTime.ToUniversalTime().ToString('o');worker=$worker}
}
function Assert-PaytmRestartBoundary($Before,$After){
 if($Before.machineHash -cnotmatch '^[A-F0-9]{64}$' -or $Before.machineHash -cne $After.machineHash){throw 'STARTUP_DIFFERENT_MACHINE'}
 $oldBoot=[DateTimeOffset]::Parse($Before.bootUtc);$newBoot=[DateTimeOffset]::Parse($After.bootUtc)
 if($newBoot -le $oldBoot){throw 'STARTUP_WINDOWS_RESTART_NOT_OBSERVED'}
 if($Before.worker.instanceId -ceq $After.worker.instanceId){throw 'STARTUP_OLD_WORKER_REUSED'}
 $started=[DateTimeOffset]::Parse($After.workerStartUtc);$collector=[DateTimeOffset]::Parse($After.collectorStartUtc)
 if($started -lt $newBoot -or $started -gt $collector){throw 'STARTUP_WORKER_NOT_RUNNING_BEFORE_CHECK'}
 # Task Scheduler metadata is not the native process creation timestamp. Validate
 # both against the boot/collector boundary; their difference is diagnostic only.
 $taskRun=[DateTimeOffset]::Parse($After.taskLastRunUtc)
 if($taskRun -lt $newBoot -or $taskRun -gt $collector){throw 'STARTUP_TASK_OUTSIDE_RESTART_WINDOW'}
 $After|Add-Member -NotePropertyName taskToWorkerStartSeconds -NotePropertyValue ([math]::Round(($started-$taskRun).TotalSeconds,7)) -Force
}
function Assert-PaytmRestartCheckpoint($State){
 if($State.version -ne 1 -or $State.runId -cnotmatch '^[a-f0-9]{32}$' -or $State.completed -isnot [bool] -or $State.completed -or $State.receiptHash -cne '078A34DB0A46951EB98C5A08063F9FC76DB6EC75C175A3572CEE3D65DA4FAB4B'){throw 'STARTUP_CHECKPOINT_INVALID_OR_COMPLETE'}
 if($State.reportName -cne ('paytm-gateway-restart-'+$State.runId+'.json')){throw 'STARTUP_CHECKPOINT_REPORT_PATH'}
}
