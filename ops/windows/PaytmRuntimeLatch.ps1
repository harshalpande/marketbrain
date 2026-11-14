function Assert-PaytmExpectedListenerLatch($Status,$Blocked,$Startup,$Before) {
 foreach($v in @($Status,$Blocked,$Startup)){
  if($v.instanceId -cne $Before.instanceId -or $v.failure -cne 'TRANSPORT_LISTENER_CONFLICT'){throw 'LATCH_UNRELATED_FAILURE'}
 }
 if($Status.installationId -cne $Before.installationId -or $Startup.installationId -cne $Before.installationId -or
    $Status.processId -ne $Before.processId -or $Startup.processId -ne $Before.processId -or $Status.phase -cne 'BLOCKED' -or
    $Status.brokerReady -or $Status.ordersEnabled -or $Status.childProcessId -ne 0){throw 'LATCH_IDENTITY_OR_SCOPE'}
}
function Read-PaytmExpectedListenerLatch($Before) {
 $c=Get-PaytmHostContract
 $values=@{}
 foreach($n in @('status.json','blocked.json','startup-failure.json')){
  $p=Assert-PaytmAccountPath (Join-Path $c.work $n)
  $values[$n]=Read-PaytmHostJson $p
 }
 Assert-PaytmExpectedListenerLatch $values['status.json'] $values['blocked.json'] $values['startup-failure.json'] $Before
 return $values
}
function Wait-PaytmExpectedListenerLatch($Before) {
 $c=Get-PaytmHostContract;$watch=[Diagnostics.Stopwatch]::StartNew()
 do{
  $task=Get-PaytmOwnedHostTask $Before.installationId
  if([string]$task.State -cnotin @('Running','Queued')){
   if((Get-ScheduledTaskInfo -TaskName $c.name -TaskPath '\').LastTaskResult -ne 1){throw 'LATCH_TASK_EXIT_UNEXPECTED'}
   return Read-PaytmExpectedListenerLatch $Before
  }
  if($watch.Elapsed.TotalSeconds -ge 30){throw 'LATCH_BLOCK_TIMEOUT'}
  Start-Sleep -Milliseconds 250
 }while($true)
}
function Restore-PaytmOwnedListenerLatch($Before,$Receipt,[string]$RunId,[scriptblock]$Checkpoint) {
 $c=Get-PaytmHostContract;$held=$null
 $archive=Join-Path $c.root ('listener-latch-'+$RunId)
 $null=Assert-PaytmAccountPath $archive
 if(Test-Path -LiteralPath $archive){throw 'LATCH_ARCHIVE_EXISTS'}
 $null=New-Item -ItemType Directory -Path $archive
 Set-PaytmAccountDirectoryAcl $archive (Get-PaytmKeyContract).accountSid
 $report.archive=@{path=$archive;hashes=@{};verified=$false}
 try{
  $task=Get-PaytmOwnedHostTask $Before.installationId
  if([string]$task.State -cin @('Running','Queued')){throw 'LATCH_TASK_NOT_IDLE'}
  $null=Disable-ScheduledTask -TaskName $c.name -TaskPath '\' -ErrorAction Stop
  $held=[IO.File]::Open((Assert-PaytmAccountPath (Join-Path $c.work 'instance.lock')),'Open','ReadWrite','None')
  $null=Read-PaytmExpectedListenerLatch $Before
  $null=Assert-PaytmTransportInstallationSources $Receipt
  foreach($n in @('status.json','blocked.json','startup-failure.json')){
   $from=Assert-PaytmAccountPath (Join-Path $c.work $n);$to=Join-Path $archive $n
   $h=(Get-FileHash -LiteralPath $from).Hash
   Copy-Item -LiteralPath $from -Destination $to -ErrorAction Stop
   if((Get-FileHash -LiteralPath $to).Hash -cne $h){throw 'LATCH_ARCHIVE_HASH'}
   $report.archive.hashes[$n]=$h
  }
  $report.archive.verified=$true;& $Checkpoint
  # Revalidate all inputs before removing any expected marker; no unrelated marker is cleared.
  $null=Read-PaytmExpectedListenerLatch $Before
  foreach($n in $report.archive.hashes.Keys){if((Get-FileHash -LiteralPath (Join-Path $c.work $n)).Hash -cne $report.archive.hashes[$n]){throw 'LATCH_STATE_CHANGED'}}
  foreach($n in @('blocked.json','startup-failure.json','status.json')){Remove-Item -LiteralPath (Assert-PaytmAccountPath (Join-Path $c.work $n)) -ErrorAction Stop}
  Set-PaytmHostControl $Before.installationId LOCKED
  Set-PaytmTransportControl $Before.installationId DISABLED
  $null=Enable-ScheduledTask -TaskName $c.name -TaskPath '\' -ErrorAction Stop
 }finally{if($held){$held.Dispose()}}
 $report.recoveryStartAttempts=1;& $Checkpoint
 Start-ScheduledTask -TaskName $c.name -TaskPath '\' -ErrorAction Stop
 $report.recoveredLocked=Wait-PaytmManagedHost $Before.installationId LOCKED $Before.instanceId -TimeoutSeconds 30 -AwaitScheduledStart
 Set-PaytmTransportControl $Before.installationId ENABLED
 $report.recovered=Wait-PaytmManagedHost $Before.installationId TRANSPORT_READY $Before.instanceId -TimeoutSeconds 60
 if((Invoke-PaytmApplicationHttp 'head').status -cne 'LOCKED'){throw 'LATCH_APPLICATION_AUTHORITY_REPLAY'}
 Invoke-PaytmApplicationHead 'After owned listener recovery' $true
 & $Checkpoint
}
function New-PaytmConflictSocket {
 $s=[Net.Sockets.Socket]::new([Net.Sockets.AddressFamily]::InterNetwork,[Net.Sockets.SocketType]::Stream,[Net.Sockets.ProtocolType]::Tcp)
 try{$s.ExclusiveAddressUse=$true;$s.Bind([Net.IPEndPoint]::new([Net.IPAddress]::Loopback,18889));$s.Listen(1);return $s}catch{$s.Dispose();throw}
}
function Invoke-PaytmRuntimeLatch($Receipt,$Manifest,[scriptblock]$Checkpoint) {
 $id=$Manifest.installationId;$c=Get-PaytmHostContract;$socket=$null
 $report.before=Wait-PaytmManagedHost $id TRANSPORT_READY -TimeoutSeconds 30
 Invoke-PaytmApplicationHead 'Before listener conflict' $true
 $report.mutationAttempted=$true;& $Checkpoint
 Set-PaytmTransportControl $id DISABLED
 $report.disabled=Wait-PaytmManagedHost $id LOCKED -TimeoutSeconds 30
 Invoke-PaytmApplicationHead 'Absent tunnel fails closed' $false
 $report.applicationNoFallbackPassed=$true;& $Checkpoint
 try{
  Write-Host '[45%] Inject owned loopback listener conflict; await supervisor failure latch'
  $socket=New-PaytmConflictSocket
  # No requests are sent to the test listener and no connection is accepted.
  $report.latched=Wait-PaytmExpectedListenerLatch $report.disabled
  $report.runtimeLatchPassed=$true;& $Checkpoint
 }finally{if($socket){$socket.Dispose()}}
 Assert-PaytmTransportListener (Get-PaytmTransportListeners)
 Write-Host '[60%] Verify latch persists after removing the conflict (10 seconds)'
 $quiet=[Diagnostics.Stopwatch]::StartNew();$samples=0
 do{
  $task=Get-PaytmOwnedHostTask $id
  if([string]$task.State -cin @('Running','Queued')){throw 'LATCH_UNEXPECTED_RESTART'}
  $null=Read-PaytmExpectedListenerLatch $report.disabled
  Assert-PaytmTransportListener (Get-PaytmTransportListeners)
  $samples++;Start-Sleep -Milliseconds 500
 }while($quiet.Elapsed.TotalSeconds -lt 10)
 $report.quiet=@{seconds=$quiet.Elapsed.TotalSeconds;samples=$samples};$report.latchPersistencePassed=$true;& $Checkpoint
 Write-Host '[75%] Archive only this induced failure and perform one controlled recovery'
 Restore-PaytmOwnedListenerLatch $report.disabled $Receipt $report.runId $Checkpoint
}
