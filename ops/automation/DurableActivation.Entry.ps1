# One bounded activation of the accepted disabled installation. No broker actions.
function Set-CollectorActivationControl($Definition,[bool]$Enabled) {
 $path=Join-Path $Definition.root 'control.json';$v=Read-TimeObservationFile $path
 if($v.version -ne 1 -or $v.installationId -cne 'ab47639ee8d74da69a9466c0f59e601e'){throw 'COLLECTOR_CONTROL_DRIFT'}
 $v.enabled=$Enabled;Write-DurableCollectorStatus $path $v;Assert-TimeObservationAcl $path
}
function Test-CollectorActivationSample($Value,$State) {
 if($Value.version -ne 1 -or $Value.instanceId -cnotmatch '^[a-f0-9]{32}$' -or $Value.processId -le 0 -or $Value.ordersEnabled -ne $false){throw 'COLLECTOR_SAMPLE_IDENTITY'}
 if($State.instance -and $Value.instanceId -cne $State.instance){throw 'COLLECTOR_INSTANCE_CHANGED'}
 if($State.processId -and $Value.processId -ne $State.processId){throw 'COLLECTOR_PROCESS_CHANGED'}
 if($Value.failure -or $Value.phase -ne 'HEALTH_RECORDED' -or $Value.consecutiveFailures -ne 0){throw 'COLLECTOR_SAMPLE_UNHEALTHY'}
 if($Value.sequence -lt $State.sequence -or $Value.acceptedCount -gt $Value.sequence){throw 'COLLECTOR_SAMPLE_SEQUENCE'}
 if($Value.sequence -gt $State.sequence){$State.advances++;$State.sequence=$Value.sequence}
 $State.instance=$Value.instanceId;$State.processId=$Value.processId
 return ($Value.acceptedCount -ge 3 -and $State.advances -ge 2)
}
function Stop-CollectorActivation($Definition,$Report) {
 Set-CollectorActivationControl $Definition $false
 $w=[Diagnostics.Stopwatch]::StartNew()
 do{
  $t=Get-ScheduledTask -TaskName $Definition.name -TaskPath '\'
  if([string]$t.State -notin @('Running','Queued')){break}
  Start-Sleep -Milliseconds 500
 }while($w.Elapsed.TotalSeconds -lt 25)
 $null=Disable-ScheduledTask -TaskName $Definition.name -TaskPath '\'
 if([string](Get-ScheduledTask -TaskName $Definition.name -TaskPath '\').State -in @('Running','Queued')){
  Stop-ScheduledTask -TaskName $Definition.name -TaskPath '\';$Report.forcedStop=$true
 }
 $w.Restart()
 do{
  $t=Get-ScheduledTask -TaskName $Definition.name -TaskPath '\'
  if(-not $t.Settings.Enabled -and [string]$t.State -notin @('Running','Queued')){
   $lease=$null;try{$lease=[IO.File]::Open((Join-Path $Definition.work 'instance.lock'),'Open','ReadWrite','None');$Report.collectorStopped=$true;return}catch{}finally{if($lease){$lease.Dispose()}}
  }
  Start-Sleep -Milliseconds 500
 }while($w.Elapsed.TotalSeconds -lt 10)
 throw 'COLLECTOR_STOP_UNCONFIRMED'
}
$r=@{version=1;runId=[guid]::NewGuid().ToString('N');passed=$false;status='REVIEW_REQUIRED';mode=$Mode;ordersEnabled=$false;failure=$null;cleanupFailure=$null;collectorStarted=$false;collectorStopped=$false;forcedStop=$false;guardRemoved=$false}
$ctx=$null;$d=$null;$attempted=$false;$watch=[Diagnostics.Stopwatch]::StartNew()
try{
 if($Mode -eq 'FailureFixture'){throw 'COLLECTOR_DELIBERATE_FIXTURE'}
 $identity=[Security.Principal.WindowsIdentity]::GetCurrent()
 try{if(-not ([Security.Principal.WindowsPrincipal]::new($identity)).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)){throw 'COLLECTOR_ADMIN_REQUIRED'}}finally{$identity.Dispose()}
 $receipt=Read-TimeObservationFile 'C:\ProgramData\MarketBrainPaytmHealth\time-observer-v1\collector-install-result.json'
 $r.preflight=Get-DurableCollectorStagingPreflight $receipt
 $d=Get-DurableCollectorDefinition $receipt.workerSha256
 $ctx=New-CollectorGatewayContext $r.runId;$ctx.collectorInstallation=$receipt.runId
 $r.gatewayPreflight=Get-CollectorGatewayPreflight $ctx
 if($Mode -eq 'Observe'){$r.status='COLLECTOR_ACTIVATION_PREFLIGHT_PASSED';$r.passed=$true;return}
 foreach($path in @($d.work,(Join-Path $d.work 'instance.lock'))){if((Get-Item -LiteralPath $path).Attributes -band [IO.FileAttributes]::ReparsePoint){throw 'COLLECTOR_WORK_REPARSE'}}
 foreach($name in @('status.json','final.json')){if(Test-Path -LiteralPath (Join-Path $d.work $name)){throw 'COLLECTOR_PRIOR_RUN_REVIEW_REQUIRED'}}
 $lease=[IO.File]::Open((Join-Path $d.work 'instance.lock'),'Open','ReadWrite','None');$lease.Dispose()
 # Durable one-shot receipt stops an automatic second activation after interruption.
 $claim=Join-Path $d.root 'activation-attempt.json'
 $f=[IO.File]::Open($claim,'CreateNew','Write','Read');try{$b=[Text.Encoding]::UTF8.GetBytes(($r|ConvertTo-Json -Depth 5));$f.Write($b,0,$b.Length);$f.Flush($true)}finally{$f.Dispose()}
 $r.stage='GATEWAY_START';Start-CollectorGatewayWindow $ctx
 $null=Get-DurableCollectorStagingPreflight $receipt
 $r.stage='COLLECTOR_START';$attempted=$true
 Set-CollectorActivationControl $d $true
 $null=Enable-ScheduledTask -TaskName $d.name -TaskPath '\'
 Start-ScheduledTask -TaskName $d.name -TaskPath '\';$r.collectorStarted=$true
 $state=@{instance=$null;sequence=0;advances=0;processId=0};$w=[Diagnostics.Stopwatch]::StartNew()
 do{
  Start-Sleep -Seconds 1
  $path=Join-Path $d.work 'status.json'
  if(Test-Path -LiteralPath $path){$sample=Read-BoundedJson $path;if(Test-CollectorActivationSample $sample $state){$r.publicationsVerified=$true;$r.observation=$sample;break}}
  if([string](Get-ScheduledTask -TaskName $d.name -TaskPath '\').State -notin @('Running','Queued')){throw 'COLLECTOR_EXITED_BEFORE_PUBLICATION'}
 }while($w.Elapsed.TotalSeconds -lt 65)
 if(-not $r.publicationsVerified){throw 'COLLECTOR_PUBLICATION_TIMEOUT'}
 $r.stage='GRACEFUL_STOP';Stop-CollectorActivation $d $r
 $final=Read-BoundedJson (Join-Path $d.work 'final.json')
 $r.worker=@{stage=$final.stage;failure=$final.failure;nonAdmin=$final.nonAdmin;sessionId=$final.sessionId;tokenAuthenticated=$final.tokenAuthenticated;applicationLocked=$final.applicationLocked;collector=$final.collector}
 $r.lastTaskResult=(Get-ScheduledTaskInfo -TaskName $d.name -TaskPath '\').LastTaskResult
 if($r.forcedStop -or $r.lastTaskResult -ne 0 -or $final.runId -cne $receipt.runId -or $final.failure -or $final.ordersEnabled -ne $false -or $final.nonAdmin -ne $true -or $final.sessionId -ne 0 -or $final.tokenAuthenticated -ne $true -or $final.applicationLocked -ne $true -or $final.collector.instanceId -cne $state.instance -or $final.collector.processId -ne $state.processId -or $final.collector.phase -cne 'STOPPED' -or $final.collector.finalHealthRevoked -ne $true){throw 'COLLECTOR_FINAL_PROOF_FAILED'}
 $r.finalHealthRevoked=$true;$r.stage='COMPLETE';$r.passed=$true;$r.status='DURABLE_COLLECTOR_ACTIVATION_PASSED_LIFECYCLE_PENDING'
}catch{$r.failure=if($_.Exception.Message -cmatch '^[A-Z][A-Z0-9_]+$'){$_.Exception.Message}else{'COLLECTOR_ACTIVATION_'+$_.Exception.GetBaseException().GetType().Name};$r.failureLine=$_.InvocationInfo.ScriptLineNumber}
finally{
 if($attempted -and -not $r.collectorStopped){try{Stop-CollectorActivation $d $r}catch{$r.cleanupFailure='COLLECTOR_STOP_REVIEW_REQUIRED'}}
 if($ctx -and $ctx.startAttempted){try{Stop-DenialRecoveryTask $ctx;$ctx.stopped=$true;$r.gatewayStopped=$true}catch{$r.cleanupFailure='GATEWAY_STOP_REVIEW_REQUIRED'}}
 if($ctx -and $ctx.guardXmlHash -and (-not $attempted -or $r.collectorStopped) -and (-not $ctx.startAttempted -or $ctx.stopped)){try{Remove-DenialRecoveryGuard $ctx;$r.guardRemoved=$true}catch{$r.cleanupFailure='COLLECTOR_GUARD_REVIEW_REQUIRED'}}
 if($ctx -and $ctx.guardAttempted -and -not $ctx.guardXmlHash){$r.cleanupFailure='COLLECTOR_GUARD_REVIEW_REQUIRED'}
 if($attempted -and $d -and -not $r.worker){
  try{
   $finalPath=Join-Path $d.work 'final.json'
   if(Test-Path -LiteralPath $finalPath){$v=Read-BoundedJson $finalPath;if($v.runId -ceq 'ab47639ee8d74da69a9466c0f59e601e'){$r.worker=@{stage=$v.stage;failure=$v.failure;sessionId=$v.sessionId;nonAdmin=$v.nonAdmin;tokenAuthenticated=$v.tokenAuthenticated;collector=$v.collector}}}
  }catch{$r.workerEvidenceFailure='COLLECTOR_FINAL_EVIDENCE_UNAVAILABLE'}
 }
 if($r.cleanupFailure -or $r.failure){$r.passed=$false;$r.status='REVIEW_REQUIRED'}
 $r.elapsedSeconds=$watch.Elapsed.TotalSeconds
 [IO.File]::WriteAllText($ResultPath,($r|ConvertTo-Json -Depth 8),[Text.UTF8Encoding]::new($false))
}
if(-not $r.passed){exit 1}
