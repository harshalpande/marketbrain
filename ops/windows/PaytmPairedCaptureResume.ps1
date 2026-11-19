#Requires -Version 7.0
# Thirty-minute observation after the accepted paired capture. No code, key or timeout replacement.
function Assert-PaytmNativeReceipt([string]$Path){
 $null=Assert-PaytmAccountPath $Path
 if((Get-FileHash -LiteralPath $Path).Hash -cne 'A4694E1AF2C9DA26EED3451EE3B771FD1635B34BC3F19911C5536BD7846C59A7'){throw 'HOST_HEALTH_RESUME_RECEIPT_CHANGED'}
 $r=Read-PaytmHostJson $Path 65536
 if($r.runId -cne '7553672c6c1a428983e9f096a087aa3f' -or $r.failure -or $r.status -cne 'TLS_DIAGNOSTICS_CAPTURED_GATEWAY_STOPPED_REVIEW_REQUIRED' -or $r.cleanupFailure -or -not $r.failureStopVerified -or -not $r.finalApplicationLockVerified -or -not $r.accountPreserved -or $r.ordersEnabled -ne $false){throw 'HOST_HEALTH_RESUME_RECEIPT_INVALID'}
 if($r.comparisonId -cne '652e9722d9644047a504068af0dcfce8' -or $r.diagnostic.captureCompleted -ne $true -or $r.diagnostic.elapsedSeconds -lt 300 -or $r.diagnostic.outageSamples -ne 0 -or $r.diagnostic.healthySamples -ne 61){throw 'HOST_PAIRED_CAPTURE_NOT_ACCEPTED'}
 Assert-PaytmManagedStatus $r.nativeRecovery.first 'ea8b91471cf048aa97a0f6b939b355c7' TRANSPORT_READY
 $r
}
function Assert-PaytmHealthResumeIdle {
 $c=Get-PaytmHostContract;$id='ea8b91471cf048aa97a0f6b939b355c7'
 $task=Get-PaytmOwnedHostTask $id $false
 if([string]$task.State -cne 'Disabled' -or (Get-ScheduledTaskInfo -TaskName $c.name -TaskPath '\').LastTaskResult -ne 0){throw 'HOST_HEALTH_RESUME_TASK_CHANGED'}
 $v=Read-PaytmHostJson (Join-Path $c.work 'status.json')
 Assert-PaytmManagedStatus $v $id STOPPED
 if($v.instanceId -cne '52b35c1b29c7491eace8cee72eed57d3' -or $v.sequence -ne 270 -or $v.processId -ne 18568){throw 'HOST_HEALTH_RESUME_INSTANCE_CHANGED'}
 $control=Read-PaytmHostJson (Join-Path $c.root 'control.json');Assert-PaytmHostControl $control $id
 if($control.mode -cne 'STOP' -or (Read-PaytmTransportControl $c.root $id) -cne 'ENABLED'){throw 'HOST_HEALTH_RESUME_CONTROL_CHANGED'}
 foreach($n in @('blocked.json','startup-failure.json')){if(Test-Path -LiteralPath (Join-Path $c.work $n)){throw 'HOST_HEALTH_RESUME_NEW_FAILURE'}}
 Assert-PaytmTransportListener (Get-PaytmTransportListeners)
}
function Assert-PaytmRecoveryApplicationLocked {
 $v=Invoke-PaytmApplicationHttp 'status'
 $h=Invoke-PaytmApplicationHttp 'head'
 foreach($r in @($v,$h)){
  if($r.bootId -cne $application.BootId -or $r.state -cne 'LOCKED' -or $r.ordersEnabled -ne $false -or $r.credentialsUsed -ne $false){throw 'APP_ROUTE_HEALTH_RESUME_NOT_LOCKED'}
 }
 if($h.status -cne 'LOCKED' -or $h.httpStatus -ne 0 -or $h.tlsVerified -ne $false){throw 'APP_ROUTE_HEALTH_RESUME_REQUEST_ESCAPED'}
 Assert-PaytmWriterLocked
 $report.applicationHealthPending=$true
 $report.applicationRouteChecks.Add(@{label='Application remains locked during transport verification';expectedTls=$false;passed=$true})
 Save-NativeRecoveryReport
}
function Invoke-PaytmNativeRecovery($Receipt,[string]$ReviewPath,[string]$SourceDirectory){
 $null=Assert-PaytmNativeReceipt $ReviewPath
 $c=Get-PaytmHostContract;$m=Assert-PaytmTransportInstallationSources $Receipt;$id=$m.installationId
 Add-Type -Path (Join-Path $c.root 'transport.dll')
 $held=$null
 try{
  $held=[IO.File]::Open((Assert-PaytmAccountPath (Join-Path $c.work 'instance.lock')),'OpenOrCreate','ReadWrite','None')
  Assert-PaytmHealthResumeIdle
  $backup=Assert-PaytmAccountPath (Join-Path $c.root ('health-resume-'+$report.runId))
  if(Test-Path -LiteralPath $backup){throw 'HOST_HEALTH_RESUME_ARCHIVE_EXISTS'}
  $null=New-Item -ItemType Directory -Path $backup;Set-PaytmAccountDirectoryAcl $backup (Get-PaytmKeyContract).accountSid
  $report.nativeRecovery=[ordered]@{backupVerified=$false;backupHashes=@{};backupPath=$backup;startAttempts=0;healthy=$false;installedCodeChanged=$false;keyImported=$false}
  foreach($n in @('manifest.json','control.json','transport-control.json','status.json')){
   $dir=if($n -eq 'status.json'){$c.work}else{$c.root};$path=Assert-PaytmAccountPath (Join-Path $dir $n)
   $hash=(Get-FileHash -LiteralPath $path).Hash
   Copy-Item -LiteralPath $path -Destination (Join-Path $backup $n) -ErrorAction Stop
   if((Get-FileHash -LiteralPath (Join-Path $backup $n)).Hash -cne $hash){throw 'HOST_HEALTH_RESUME_BACKUP_FAILED'}
   $report.nativeRecovery.backupHashes[$n]=$hash
  }
  Assert-PaytmHealthResumeIdle
  foreach($n in $report.nativeRecovery.backupHashes.Keys){
   $dir=if($n -eq 'status.json'){$c.work}else{$c.root}
   if((Get-FileHash -LiteralPath (Join-Path $dir $n)).Hash -cne $report.nativeRecovery.backupHashes[$n]){throw 'HOST_HEALTH_RESUME_DRIFT'}
  }
  $report.nativeRecovery.backupVerified=$true;Save-NativeRecoveryReport
  $report.nativeRecoveryAttempted=$true;Save-NativeRecoveryReport
  Set-PaytmHostControl $id LOCKED
  $null=Enable-ScheduledTask -TaskName $c.name -TaskPath '\' -ErrorAction Stop
  $null=Assert-PaytmInstalledTransport $Receipt
 }finally{if($held){$held.Dispose()}}
 $report.nativeRecovery.startAttempts=1;Save-NativeRecoveryReport
 Start-ScheduledTask -TaskName $c.name -TaskPath '\' -ErrorAction Stop
 $report.nativeRecovery.first=Wait-PaytmManagedHost $id TRANSPORT_READY '52b35c1b29c7491eace8cee72eed57d3' -AwaitScheduledStart
 $report.nativeRecovery.healthy=$true;Save-NativeRecoveryReport
}
