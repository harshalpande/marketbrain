# Sign-out verification only. Does not sign out, restart Windows, or enable trades.
function Get-CollectorLogonIdentity {
 $p=[Diagnostics.Process]::new();$p.StartInfo.FileName='C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe'
 $p.StartInfo.Arguments='-NoLogo -NoProfile -NonInteractive -EncodedCommand '+$interactiveSessionCode
 $p.StartInfo.UseShellExecute=$false;$p.StartInfo.CreateNoWindow=$true;$p.StartInfo.RedirectStandardOutput=$true;$p.StartInfo.RedirectStandardError=$true
 try{
  if(-not $p.Start()){throw 'COLLECTOR_LOGON_START'}
  $o=$p.StandardOutput.ReadToEndAsync();$e=$p.StandardError.ReadToEndAsync()
  if(-not $p.WaitForExit(25000)){$p.Kill();throw 'COLLECTOR_LOGON_TIMEOUT'}
  if($p.ExitCode -ne 0 -or -not $o.Wait(1000) -or $o.Result.Length -gt 2048){throw 'COLLECTOR_LOGON_QUERY'}
  $v=$o.Result|ConvertFrom-Json
  if($v.userSidHash -cnotmatch '^[A-F0-9]{64}$' -or $v.authenticationId -cnotmatch '^[A-F0-9]{16}$' -or $v.sessionId -le 0){throw 'COLLECTOR_LOGON_FORMAT'}
  return $v
 }finally{$p.Dispose()}
}
function Get-CollectorLifecycleSnapshot($Definition) {
 foreach($name in @('worker.ps1','known_hosts')){Assert-TimeObservationAcl (Join-Path $Definition.root $name)}
 if((Get-FileHash -LiteralPath (Join-Path $Definition.root 'worker.ps1')).Hash -cne '25CFF7A9A54184DC0B5F43A094B331B14C4D288448C8BA8A01975A9F29053B99' -or (Get-FileHash -LiteralPath (Join-Path $Definition.root 'known_hosts')).Hash -cne 'C8D0896753936BC7AB4B47E755516BF253A973F8E65CC8B8CF249B9476CC924D'){throw 'COLLECTOR_LIFECYCLE_FILE_DRIFT'}
 $s=Read-BoundedJson (Join-Path $Definition.work 'status.json')
 $state=@{instance=$null;sequence=0;advances=1;processId=0}
 if(-not (Test-CollectorActivationSample $s $state)){throw 'COLLECTOR_LIFECYCLE_NOT_HEALTHY'}
 $age=([DateTimeOffset]::UtcNow-([DateTimeOffset]$s.observedUtc)).TotalSeconds
 if($age -lt 0 -or $age -gt 15){throw 'COLLECTOR_LIFECYCLE_STALE'}
 $p=Get-Process -Id $s.processId -ErrorAction Stop
 if($p.SessionId -ne 0){throw 'COLLECTOR_LIFECYCLE_INTERACTIVE_WORKER'}
 if([string](Get-ScheduledTask -TaskName $Definition.name -TaskPath '\').State -cne 'Running'){throw 'COLLECTOR_LIFECYCLE_TASK_STOPPED'}
 return @{bootUtc=(Get-TimeObservationBootId);interactive=(Get-CollectorLogonIdentity);worker=$s;workerStartUtc=$p.StartTime.ToUniversalTime().ToString('o');ticks=[Diagnostics.Stopwatch]::GetTimestamp();frequency=[Diagnostics.Stopwatch]::Frequency}
}
function Assert-CollectorLogoffBoundary($Before,$After) {
 if([DateTimeOffset]$Before.bootUtc -ne [DateTimeOffset]$After.bootUtc){throw 'COLLECTOR_UNEXPECTED_RESTART'}
 if($Before.interactive.userSidHash -cne $After.interactive.userSidHash){throw 'COLLECTOR_LOGON_USER_CHANGED'}
 if($Before.interactive.authenticationId -ceq $After.interactive.authenticationId){throw 'COLLECTOR_SIGNOUT_NOT_OBSERVED'}
 if($Before.worker.instanceId -cne $After.worker.instanceId -or $Before.worker.processId -ne $After.worker.processId -or [DateTimeOffset]$Before.workerStartUtc -ne [DateTimeOffset]$After.workerStartUtc){throw 'COLLECTOR_LOGOFF_WORKER_RESTARTED'}
 if($After.worker.sequence -le $Before.worker.sequence -or $After.worker.acceptedCount -le $Before.worker.acceptedCount){throw 'COLLECTOR_LOGOFF_NO_ADVANCE'}
 if($After.frequency -ne $Before.frequency -or $After.ticks -le $Before.ticks){throw 'COLLECTOR_LOGOFF_TIMING'}
}
function Read-CollectorLifecycleCheckpoint([string]$Path) {
 Assert-TimeObservationAcl $Path
 if((Get-Item -LiteralPath $Path).Length -gt 16384){throw 'COLLECTOR_CHECKPOINT_SIZE'}
 $v=Get-Content -LiteralPath $Path -Raw|ConvertFrom-Json -AsHashtable -DateKind String
 if($v.version -ne 1 -or $v.installationId -cne 'ab47639ee8d74da69a9466c0f59e601e' -or $v.runId -cnotmatch '^[a-f0-9]{32}$' -or $v.phase -notin @('WAITING_FOR_SIGNOUT','COMPLETE','REVIEW_REQUIRED')){throw 'COLLECTOR_CHECKPOINT_IDENTITY'}
 $expected=New-CollectorGatewayContext $v.runId
 foreach($name in @('root','work','taskName','guardName','archive')){if($v.context[$name] -cne $expected[$name]){throw 'COLLECTOR_CHECKPOINT_CONTEXT'}}
 if($v.context.guardXmlHash -cnotmatch '^[A-F0-9]{64}$'){throw 'COLLECTOR_CHECKPOINT_GUARD'}
 return $v
}
function Save-CollectorLifecycleCheckpoint([string]$Path,$Value) {
 $json=$Value|ConvertTo-Json -Depth 10 -Compress
 if([Text.Encoding]::UTF8.GetByteCount($json) -gt 16384){throw 'COLLECTOR_CHECKPOINT_SIZE'}
 $temp=$Path+'.'+[guid]::NewGuid().ToString('N')+'.new';[IO.File]::WriteAllText($temp,$json,[Text.UTF8Encoding]::new($false));Assert-TimeObservationAcl $temp
 if(Test-Path -LiteralPath $Path){Assert-TimeObservationAcl $Path;[IO.File]::Replace($temp,$Path,[Management.Automation.Language.NullString]::Value)}else{[IO.File]::Move($temp,$Path)}
}
function Preserve-CollectorAcceptedActivation($Definition) {
 $claim=Read-TimeObservationFile (Join-Path $Definition.root 'activation-attempt.json')
 $v=Read-BoundedJson (Join-Path $Definition.work 'final.json')
 $s=Read-BoundedJson (Join-Path $Definition.work 'status.json')
 if($claim.runId -cne '0222ec7c4e024d4da5ce4753389674a2' -or $v.runId -cne 'ab47639ee8d74da69a9466c0f59e601e' -or $v.failure -or $v.stage -cne 'COMPLETE' -or $v.ordersEnabled -ne $false){throw 'COLLECTOR_ACCEPTED_STATE_DRIFT'}
 foreach($sample in @($v.collector,$s)){if($sample.instanceId -cne '753e0869ea71497eb220580af420108d' -or $sample.phase -cne 'STOPPED' -or $sample.finalHealthRevoked -ne $true -or $sample.acceptedCount -ne 4 -or $sample.sequence -ne 5 -or $sample.ordersEnabled -ne $false){throw 'COLLECTOR_ACCEPTED_STATE_DRIFT'}}
 $archive=Join-Path $Definition.root 'accepted-0222ec7c4e024d4da5ce4753389674a2'
 if(Test-Path -LiteralPath $archive){throw 'COLLECTOR_LIFECYCLE_ALREADY_PREPARED'}
 $null=New-Item -ItemType Directory -Path $archive
 foreach($path in @((Join-Path $Definition.root 'activation-attempt.json'),(Join-Path $Definition.work 'status.json'),(Join-Path $Definition.work 'final.json'))){
  $item=Get-Item -LiteralPath $path;if($item.Attributes -band [IO.FileAttributes]::ReparsePoint){throw 'COLLECTOR_WORK_REPARSE'}
  $hash=(Get-FileHash -LiteralPath $path).Hash;$target=Join-Path $archive $item.Name;Move-Item -LiteralPath $path -Destination $target
  if((Get-FileHash -LiteralPath $target).Hash -cne $hash){throw 'COLLECTOR_ARCHIVE_MISMATCH'}
 }
}
$r=@{version=1;passed=$false;status='REVIEW_REQUIRED';failure=$null;cleanupFailure=$null;ordersEnabled=$false;mode=$Mode;collectorStopped=$false;forcedStop=$false}
$d=Get-DurableCollectorDefinition '25CFF7A9A54184DC0B5F43A094B331B14C4D288448C8BA8A01975A9F29053B99'
$path=Join-Path $d.root 'signout-checkpoint.json';$cp=$null;$ctx=$null;$started=$false;$leaveRunning=$false;$cleanup=$false;$watch=[Diagnostics.Stopwatch]::StartNew()
try{
 if($Mode -eq 'FailureFixture'){throw 'COLLECTOR_LIFECYCLE_FIXTURE'}
 $receipt=Read-TimeObservationFile 'C:\ProgramData\MarketBrainPaytmHealth\time-observer-v1\collector-install-result.json';Assert-DurableCollectorReceipt $receipt
 if(Test-Path -LiteralPath $path){
  $cp=Read-CollectorLifecycleCheckpoint $path;$ctx=$cp.context;$r.runId=$cp.runId
  if($cp.phase -ne 'WAITING_FOR_SIGNOUT'){$r.checkpoint=$cp;$r.status=$cp.phase;$r.passed=($cp.phase -eq 'COMPLETE');$ctx=$null;return}
  $after=Get-CollectorLifecycleSnapshot $d;$r.after=$after
  if($after.bootUtc -cne $cp.before.bootUtc -or ([Diagnostics.Stopwatch]::GetTimestamp()-$cp.before.ticks)/[double]$cp.before.frequency -gt 480){throw 'COLLECTOR_SIGNOUT_WINDOW_EXPIRED'}
  if($after.interactive.authenticationId -ceq $cp.before.interactive.authenticationId){$r.status='COLLECTOR_WAITING_FOR_SIGNOUT';$r.passed=$true;$leaveRunning=$true;return}
  Assert-CollectorLogoffBoundary $cp.before $after;$r.boundaryVerified=$true
  if($Mode -eq 'Observe'){$r.status='COLLECTOR_SIGNOUT_VERIFIED_CLEANUP_PENDING';$r.passed=$true;$leaveRunning=$true;return}
  $cleanup=$true;Stop-CollectorActivation $d $r
  $v=Read-BoundedJson (Join-Path $d.work 'final.json');$r.final=$v.collector
  if($r.forcedStop -or $v.failure -or $v.runId -cne $receipt.runId -or $v.ordersEnabled -ne $false -or $v.nonAdmin -ne $true -or $v.sessionId -ne 0 -or $v.applicationLocked -ne $true -or $v.tokenAuthenticated -ne $true -or $v.collector.instanceId -cne $cp.before.worker.instanceId -or $v.collector.processId -ne $cp.before.worker.processId -or $v.collector.phase -cne 'STOPPED' -or $v.collector.finalHealthRevoked -ne $true -or (Get-ScheduledTaskInfo -TaskName $d.name -TaskPath '\').LastTaskResult -ne 0){throw 'COLLECTOR_SIGNOUT_FINAL_PROOF'}
  $cp.after=$after;$cp.final=$v.collector;$cp.phase='COMPLETE';$r.status='DURABLE_COLLECTOR_SIGNOUT_PASSED_RESTART_PENDING';$r.passed=$true
 }else{
  $r.preflight=Get-DurableCollectorStagingPreflight $receipt
  $r.runId=[guid]::NewGuid().ToString('N');$ctx=New-CollectorGatewayContext $r.runId;$ctx.collectorInstallation=$receipt.runId;$ctx.lifecycleWindow=$true
  $null=Get-CollectorGatewayPreflight $ctx;$null=Get-CollectorLogonIdentity
  if($Mode -eq 'Observe'){$r.status='COLLECTOR_SIGNOUT_PREFLIGHT_PASSED';$r.passed=$true;return}
  Preserve-CollectorAcceptedActivation $d
  Start-CollectorGatewayWindow $ctx
  $null=Get-DurableCollectorStagingPreflight $receipt
  $started=$true;$cleanup=$true;Set-CollectorActivationControl $d $true;$null=Enable-ScheduledTask -TaskName $d.name -TaskPath '\';Start-ScheduledTask -TaskName $d.name -TaskPath '\'
  $state=@{instance=$null;sequence=0;advances=0;processId=0};$w=[Diagnostics.Stopwatch]::StartNew();$ready=$false
  do{Start-Sleep -Seconds 1;$sp=Join-Path $d.work 'status.json';if(Test-Path -LiteralPath $sp){if(Test-CollectorActivationSample (Read-BoundedJson $sp) $state){$ready=$true;break}};if([string](Get-ScheduledTask -TaskName $d.name -TaskPath '\').State -notin @('Running','Queued')){throw 'COLLECTOR_LIFECYCLE_EARLY_EXIT'}}while($w.Elapsed.TotalSeconds -lt 65)
  if(-not $ready){throw 'COLLECTOR_LIFECYCLE_START_TIMEOUT'}
  $before=Get-CollectorLifecycleSnapshot $d
  $cp=@{version=1;installationId=$receipt.runId;runId=$r.runId;phase='WAITING_FOR_SIGNOUT';before=$before;context=$ctx}
  Save-CollectorLifecycleCheckpoint $path $cp
  $r.before=$before;$r.status='COLLECTOR_READY_FOR_OWNER_SIGNOUT';$r.passed=$true;$leaveRunning=$true;$cleanup=$false
 }
}catch{$r.failure=if($_.Exception.Message -cmatch '^[A-Z][A-Z0-9_]+$'){$_.Exception.Message}else{'COLLECTOR_LIFECYCLE_'+$_.Exception.GetBaseException().GetType().Name};$r.failureLine=$_.InvocationInfo.ScriptLineNumber;if($Mode -eq 'Apply' -and ($started -or ($cp -and $cp.phase -eq 'WAITING_FOR_SIGNOUT'))){$cleanup=$true}}
finally{
 if($Mode -eq 'Apply' -and -not $leaveRunning){
  if($cleanup -and -not $r.collectorStopped){try{Stop-CollectorActivation $d $r}catch{$r.cleanupFailure='COLLECTOR_STOP_REVIEW_REQUIRED'}}
  if($ctx -and $ctx.startAttempted){try{Stop-DenialRecoveryTask $ctx;$r.gatewayStopped=$true}catch{$r.cleanupFailure='GATEWAY_STOP_REVIEW_REQUIRED'}}
  if($ctx -and $ctx.guardXmlHash -and (-not $cleanup -or $r.collectorStopped) -and (-not $ctx.startAttempted -or $r.gatewayStopped)){try{Remove-DenialRecoveryGuard $ctx;$r.guardRemoved=$true}catch{$r.cleanupFailure='COLLECTOR_GUARD_REVIEW_REQUIRED'}}
  if($ctx -and $ctx.guardAttempted -and -not $ctx.guardXmlHash){$r.cleanupFailure='COLLECTOR_GUARD_REVIEW_REQUIRED'}
  if($ctx -and $cp -and ($cleanup -or $cp.phase -eq 'COMPLETE')){if($r.failure -or $r.cleanupFailure){$cp.phase='REVIEW_REQUIRED'};$cp.cleanup=@{collectorStopped=$r.collectorStopped;gatewayStopped=$r.gatewayStopped;guardRemoved=$r.guardRemoved;failure=$r.failure;cleanupFailure=$r.cleanupFailure};try{Save-CollectorLifecycleCheckpoint $path $cp}catch{$r.cleanupFailure='COLLECTOR_CHECKPOINT_SAVE_FAILED'}}
 }
 if($r.failure -or $r.cleanupFailure){$r.passed=$false;$r.status='REVIEW_REQUIRED'}
 $r.elapsedSeconds=$watch.Elapsed.TotalSeconds
 [IO.File]::WriteAllText($ResultPath,($r|ConvertTo-Json -Depth 10),[Text.UTF8Encoding]::new($false))
}
if(-not $r.passed){exit 1}
