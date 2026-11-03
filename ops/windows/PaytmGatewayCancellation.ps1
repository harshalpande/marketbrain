#Requires -Version 7.0
# Definitions only. The controller cancels only the reviewed existing task.
function Assert-PaytmRestartAcceptance($Value){
 if($Value.runId -cne 'eb86108cc1e247d68d06e135eb580bf6' -or $Value.status -cne 'WINDOWS_RESTART_TRANSPORT_AND_APPLICATION_ROUTE_PASSED' -or $Value.stage -cne 'COMPLETE' -or $Value.phase -cne 'After' -or $Value.failure -or $Value.cleanupFailure){throw 'CANCEL_RESTART_RECEIPT'}
 foreach($n in @('windowsRestartObserved','accountPreserved','finalApplicationLockVerified','ownerConfirmsNoManualGatewayStart')){if($Value.$n -isnot [bool] -or -not $Value.$n){throw 'CANCEL_RESTART_PROOF'}}
 foreach($n in @('taskStartedByCollector','configurationChanged','rebootRequestedByCollector','credentialsUsed','ordersEnabled')){if($Value.$n -isnot [bool] -or $Value.$n){throw 'CANCEL_RESTART_SCOPE'}}
 if(@($Value.applicationRouteChecks).Count -ne 1 -or $Value.applicationRouteChecks[0].passed -ne $true){throw 'CANCEL_RESTART_ROUTE'}
 Assert-PaytmRestartBoundary $Value.before $Value.observation
 Assert-PaytmManagedStatus $Value.observation.worker 'ea8b91471cf048aa97a0f6b939b355c7' TRANSPORT_READY
}
function Open-PaytmCancellationProcesses($Snapshot){
 Assert-PaytmManagedStatus $Snapshot $Snapshot.installationId TRANSPORT_READY
 $owner=$null;$child=$null
 try{
  $owner=Get-Process -Id $Snapshot.processId -ErrorAction Stop
  $child=Get-Process -Id $Snapshot.childProcessId -ErrorAction Stop
  if($owner.Path -ine (Get-PaytmHostContract).executable -or $owner.SessionId -ne 0 -or $child.Path -ine 'C:\Windows\System32\OpenSSH\ssh.exe' -or $child.StartTime.ToUniversalTime().Ticks -ne $Snapshot.childStartTicks){throw 'CANCEL_PROCESS_IDENTITY'}
  # Retain handles across cancellation: PID reuse must not masquerade as survival.
  $null=$owner.Handle;$null=$child.Handle
  Assert-PaytmTransportListener (Get-PaytmTransportListeners) $Snapshot.childProcessId
  [pscustomobject]@{Owner=$owner;Child=$child}
 }catch{if($child){$child.Dispose()};if($owner){$owner.Dispose()};throw}
}
function Get-PaytmCancellationExit($Processes,[string]$Id){
 $task=Get-PaytmOwnedHostTask $Id
 $rows=@(Get-PaytmTransportListeners)
 [pscustomobject]@{taskIdle=([string]$task.State -cnotin @('Running','Queued'));ownerExited=$Processes.Owner.HasExited;childExited=$Processes.Child.HasExited;listenerCount=$rows.Count}
}
function Test-PaytmCancellationExit($State){
 ($State.taskIdle -is [bool] -and $State.taskIdle -and $State.ownerExited -is [bool] -and $State.ownerExited -and $State.childExited -is [bool] -and $State.childExited -and $State.listenerCount -eq 0)
}
function Wait-PaytmCancellationExit($Processes,[string]$Id,[ValidateRange(1,20)][int]$TimeoutSeconds=20){
 $watch=[Diagnostics.Stopwatch]::StartNew()
 do{
  $v=Get-PaytmCancellationExit $Processes $Id
  if(Test-PaytmCancellationExit $v){$v|Add-Member elapsedSeconds ([math]::Round($watch.Elapsed.TotalSeconds,3));return $v}
  Start-Sleep -Milliseconds 250
 }while($watch.Elapsed.TotalSeconds -lt $TimeoutSeconds)
 throw 'CANCEL_PROCESS_OR_LISTENER_SURVIVED'
}
function Invoke-PaytmCancellationBatch([string]$Id){
 $c=Get-PaytmHostContract;$processes=$null
 try{
  $report.before=Wait-PaytmManagedHost $Id TRANSPORT_READY
  Invoke-PaytmApplicationHead 'Before abrupt task cancellation' $true
  $processes=Open-PaytmCancellationProcesses $report.before
  $null=Get-PaytmOwnedHostTask $Id
  Cancellation-Step 'CANCEL_OWNED_TASK_AND_VERIFY_CHILD_EXIT' 40
  $report.cancellationAttempted=$true;Save-Report
  Stop-ScheduledTask -TaskName $c.name -TaskPath '\' -ErrorAction Stop
  $report.cancelled=Wait-PaytmCancellationExit $processes $Id
  $report.taskLastResult=(Get-ScheduledTaskInfo -TaskName $c.name -TaskPath '\' -ErrorAction Stop).LastTaskResult
  # An abruptly terminated process cannot publish STOPPED. Native handles, task
  # state and actual listeners are authoritative; old status.json is not health.
  $report.staleHeartbeatNotUsedAsHealth=$true
  Invoke-PaytmApplicationHead 'Cancelled gateway rejects application request' $false
  Cancellation-Step 'VERIFY_NO_ORPHAN_OR_UNREQUESTED_RESTART' 55
  $watch=[Diagnostics.Stopwatch]::StartNew()
  do{
   if(-not (Test-PaytmCancellationExit (Get-PaytmCancellationExit $processes $Id))){throw 'CANCEL_UNEXPECTED_RESTART_OR_LISTENER'}
   Start-Sleep -Milliseconds 500
  }while($watch.Elapsed.TotalSeconds -lt 10)
  $report.quietSeconds=[math]::Round($watch.Elapsed.TotalSeconds,3)
  $report.cancellationPassed=$true;Save-Report
  Cancellation-Step 'EXPLICIT_RESTART_AND_AUTHORITY_CHECK' 70
  $null=Get-PaytmOwnedHostTask $Id
  Start-ScheduledTask -TaskName $c.name -TaskPath '\' -ErrorAction Stop
  $report.recovered=Wait-PaytmManagedHost $Id TRANSPORT_READY $report.before.instanceId
  if($report.recovered.instanceId -ceq $report.before.instanceId -or ($report.recovered.childProcessId -eq $report.before.childProcessId -and $report.recovered.childStartTicks -eq $report.before.childStartTicks)){throw 'CANCEL_OLD_PROCESS_REUSED'}
  $v=Invoke-PaytmApplicationHttp 'head'
  if($v.status -cne 'LOCKED' -or $v.bootId -cne $application.BootId){throw 'CANCEL_APPLICATION_AUTHORITY_REPLAYED'}
  $report.noAutomaticRearmPassed=$true
  Invoke-PaytmApplicationHead 'Explicit rearm after new gateway worker' $true
  $report.recoveryPassed=$true
 }finally{if($processes){$processes.Child.Dispose();$processes.Owner.Dispose()}}
}
