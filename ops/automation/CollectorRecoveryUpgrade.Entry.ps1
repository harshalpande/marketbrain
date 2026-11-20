# Upgrade the stopped diagnostic worker only. No task start, application restart or credentials.
function Get-CollectorUpgradeHash([byte[]]$Bytes){[Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($Bytes))}
function Assert-CollectorUpgradeTaskPreserved([string]$Before,[string]$After){
 [xml]$a=$Before;[xml]$b=$After
 $a.Task.Actions.InnerXml='';$b.Task.Actions.InnerXml=''
 if($a.OuterXml -cne $b.OuterXml){throw 'UPGRADE_TASK_NON_ACTION_DRIFT'}
}
function Write-CollectorUpgradeNew([string]$Path,[byte[]]$Bytes){
 $f=[IO.File]::Open($Path,'CreateNew','Write','None');try{$f.Write($Bytes,0,$Bytes.Length);$f.Flush($true)}finally{$f.Dispose()}
 Assert-TimeObservationAcl $Path
}
function Set-CollectorUpgradeAction($Definition){
 if(-not $script:collectorUpgradePassword){throw 'UPGRADE_LOCAL_PASSWORD_REQUIRED'}
 $action=New-ScheduledTaskAction -Execute $Definition.exe -Argument $Definition.arguments -WorkingDirectory $Definition.root
 $user=(Get-ScheduledTask -TaskName $Definition.name -TaskPath '\').Principal.UserId
 $plain=$null
 try{$plain=[Net.NetworkCredential]::new('', $script:collectorUpgradePassword).Password;$null=Set-ScheduledTask -TaskName $Definition.name -TaskPath '\' -Action $action -User $user -Password $plain -ErrorAction Stop}finally{$plain=$null}
}
function Invoke-CollectorRecoveryUpgrade([string]$RequestedMode){
 $r=@{version=1;runId=[guid]::NewGuid().ToString('N');status='REVIEW_REQUIRED';passed=$false;stage='IDENTITY';mode=$RequestedMode;failure=$null;rollbackFailure=$null;ordersEnabled=$false;workerStarted=$false;applicationRestarted=$false;credentialsUsed=$false;workerSha256=$upgradeWorkerHash}
 $lease=$null;$workerChanged=$false;$actionChanged=$false;$dockerChanged=$false;$backup=$null;$oldXml=$null;$before=$null;$exe=$null;$d=$null
 try{
  if($RequestedMode -notin @('Observe','Apply')){throw 'UPGRADE_MODE'}
  $identity=[Security.Principal.WindowsIdentity]::GetCurrent()
  if(-not ([Security.Principal.WindowsPrincipal]::new($identity)).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)){throw 'UPGRADE_ADMIN_REQUIRED'}
  $localReport='C:\ProgramData\MarketBrainPaytmHealth\time-observer-v1\collector-upgrade-result.json'
  if($RequestedMode -ceq 'Observe' -and (Test-Path -LiteralPath $localReport)){
   $r.stage='LOCAL_UPGRADE_REVIEW';$r.localUpgrade=Read-TimeObservationFile $localReport
   if($r.localUpgrade.failure -or $r.localUpgrade.status -cne 'COLLECTOR_RECOVERY_UPGRADED_DISABLED_RUNTIME_PENDING'){throw 'UPGRADE_LOCAL_REPORT_REVIEW_REQUIRED'}
   $installed=Read-TimeObservationFile 'C:\ProgramData\MarketBrainPaytmHealth\collector-v1\recovery-upgrade.json'
   if($installed.workerSha256 -cne $upgradeWorkerHash -or $installed.passed -ne $true -or $installed.runId -cne $r.localUpgrade.runId){throw 'UPGRADE_RECEIPT_MISMATCH'}
   $d=Get-DurableCollectorDefinition $upgradeWorkerHash
   Assert-TimeObservationAcl (Join-Path $d.root 'worker.ps1')
   if((Get-FileHash -LiteralPath (Join-Path $d.root 'worker.ps1')).Hash -cne $upgradeWorkerHash){throw 'UPGRADE_WORKER_DRIFT'}
   Assert-DurableCollectorTask (Get-ScheduledTask -TaskName $d.name -TaskPath '\') $d
   $xml=Export-ScheduledTask -TaskName $d.name -TaskPath '\'
   if((Get-CollectorUpgradeHash ([Text.Encoding]::UTF8.GetBytes($xml))) -cne $installed.taskXmlSha256){throw 'UPGRADE_XML_DRIFT'}
   $control=Read-TimeObservationFile (Join-Path $d.root 'control.json')
   if($control.installationId -cne 'ab47639ee8d74da69a9466c0f59e601e' -or $control.enabled -ne $false){throw 'UPGRADE_CONTROL_DRIFT'}
   $r.containerAfter=Get-CollectorDockerState
   if($r.containerAfter.containerId -cne $installed.containerAfter.containerId -or $r.containerAfter.restartPolicy -cne 'unless-stopped'){throw 'UPGRADE_DOCKER_DRIFT'}
   $r.status='COLLECTOR_RECOVERY_UPGRADE_VERIFIED_RUNTIME_PENDING';$r.passed=$true;return $r
  }
  $r.stage='STAGING_PREFLIGHT'
  $r.files=@{}
  foreach($relative in @('time-observer-v1\collector-install-result.json','time-observer-v1\snapshot.json','collector-v1\worker.ps1','collector-v1\known_hosts','collector-v1\control.json')){$r.files[$relative]=Test-Path -LiteralPath ('C:\ProgramData\MarketBrainPaytmHealth\'+$relative)}
  $receipt=Read-TimeObservationFile 'C:\ProgramData\MarketBrainPaytmHealth\time-observer-v1\collector-install-result.json'
  $r.stage='TIME_OBSERVER';$r.timeObserver=Restore-CollectorTimeObserver -Start:($RequestedMode -ceq 'Apply')
  if(-not $r.timeObserver.verified){throw 'UPGRADE_OBSERVER_STOPPED_RESTART_PENDING'}
  $r.stage='STAGING_PREFLIGHT'
  $r.preflight=Get-DurableCollectorStagingPreflight $receipt
  $d=Get-DurableCollectorDefinition $receipt.workerSha256
  $destination=Join-Path $d.root 'recovery-upgrade.json'
  if(Test-Path -LiteralPath $destination){throw 'UPGRADE_ALREADY_RECORDED'}
  $r.stage='INCIDENT_PREFLIGHT'
  $checkpointPath=Join-Path $d.root 'signout-checkpoint.json'
  Assert-TimeObservationAcl $checkpointPath
  $cp=Read-TimeObservationFile $checkpointPath
  if($cp.runId -cne '73fc2f10891346768bdc0f88e978da75' -or $cp.phase -cne 'REVIEW_REQUIRED' -or $cp.installationId -cne $receipt.runId){throw 'UPGRADE_INCIDENT_CHANGED'}
  $gateway=Get-ScheduledTask -TaskName 'MarketBrain-Gateway-Supervisor-v1' -TaskPath '\' -ErrorAction Stop
  if($gateway.Settings.Enabled -or [string]$gateway.State -cne 'Disabled'){throw 'UPGRADE_GATEWAY_NOT_STOPPED'}
  $lock=Join-Path $d.work 'instance.lock'
  if((Get-Item -LiteralPath $lock).Attributes -band [IO.FileAttributes]::ReparsePoint){throw 'UPGRADE_LEASE_REPARSE'}
  $lease=[IO.File]::Open($lock,'Open','ReadWrite','None')
  $oldXml=Export-ScheduledTask -TaskName $d.name -TaskPath '\'
  $r.stage='APPLICATION_PREFLIGHT';$before=Get-CollectorDockerState
  if($before.containerId -cne '1644e08701f13e4cf8df734d516e2e04a098c7a88cb0cb55597996f71204c6ad' -or $before.state -cne 'running' -or $before.restartPolicy -cne 'no'){throw 'UPGRADE_CONTAINER_CHANGED'}
  if(-not (Test-CollectorApplicationReady)){throw 'UPGRADE_APPLICATION_NOT_READY'}
  $exe=@(Get-Command docker.exe -CommandType Application -ErrorAction Stop)[0].Source
  $r.containerBefore=$before
  $compressed=[IO.MemoryStream]::new([Convert]::FromBase64String($upgradePayload));$gz=[IO.Compression.GZipStream]::new($compressed,[IO.Compression.CompressionMode]::Decompress);$out=[IO.MemoryStream]::new()
  try{$gz.CopyTo($out);$bytes=$out.ToArray()}finally{$gz.Dispose();$compressed.Dispose();$out.Dispose()}
  if($bytes.Length -gt 262144 -or (Get-CollectorUpgradeHash $bytes) -cne $upgradeWorkerHash){throw 'UPGRADE_PAYLOAD'}
  $t=$null;$e=$null;$null=[Management.Automation.Language.Parser]::ParseInput([Text.Encoding]::UTF8.GetString($bytes),[ref]$t,[ref]$e);if($e.Count){throw 'UPGRADE_PARSE'}
  if($RequestedMode -ceq 'Observe'){$r.status='COLLECTOR_RECOVERY_UPGRADE_PREFLIGHT_PASSED';$r.passed=$true;return $r}
  if(-not $LocalPassword){throw 'UPGRADE_LOCAL_PASSWORD_REQUIRED'}
  Write-Host '[30%] Enter the existing WINDOWS marketbrain-health password locally. No password is sent to the queue.'
  $script:collectorUpgradePassword=Read-Host 'marketbrain-health password' -AsSecureString
  $r.credentialCheck=Test-TimeAccountCredential $script:collectorUpgradePassword
  if(-not $r.credentialCheck.accepted){throw 'UPGRADE_WINDOWS_CREDENTIAL_REJECTED'}
  $r.credentialsUsed=$true
  $r.stage='UPGRADE'
  Write-Host '[60%] Back up stopped collector, update disabled task and verify application restart policy.'
  $backup=Join-Path $d.root ('recovery-backup-'+$r.runId)
  $null=New-Item -ItemType Directory -Path $backup -ErrorAction Stop;Assert-TimeObservationAcl $backup
  foreach($name in @('worker.ps1','known_hosts','control.json','signout-checkpoint.json')){
   $src=Join-Path $d.root $name;Assert-TimeObservationAcl $src
   Write-CollectorUpgradeNew (Join-Path $backup $name) ([IO.File]::ReadAllBytes($src))
   if((Get-FileHash -LiteralPath $src).Hash -cne (Get-FileHash -LiteralPath (Join-Path $backup $name)).Hash){throw 'UPGRADE_BACKUP_HASH'}
  }
  Write-CollectorUpgradeNew (Join-Path $backup 'task.xml') ([Text.Encoding]::UTF8.GetBytes($oldXml))
  Write-CollectorUpgradeNew (Join-Path $backup 'install-receipt.json') ([IO.File]::ReadAllBytes('C:\ProgramData\MarketBrainPaytmHealth\time-observer-v1\collector-install-result.json'))
  # Original status/final files and failed checkpoint remain untouched in their original locations.
  $r.backup=$backup
  $candidate=Join-Path $d.root ('worker-'+$r.runId+'.new')
  Write-CollectorUpgradeNew $candidate $bytes
  $workerChanged=$true
  [IO.File]::Replace($candidate,(Join-Path $d.root 'worker.ps1'),[Management.Automation.Language.NullString]::Value)
  $next=Get-DurableCollectorDefinition $upgradeWorkerHash
  $actionChanged=$true;Set-CollectorUpgradeAction $next
  Assert-DurableCollectorTask (Get-ScheduledTask -TaskName $d.name -TaskPath '\') $next
  $newXml=Export-ScheduledTask -TaskName $d.name -TaskPath '\'
  Assert-CollectorUpgradeTaskPreserved $oldXml $newXml
  if((Get-FileHash -LiteralPath (Join-Path $d.root 'worker.ps1')).Hash -cne $upgradeWorkerHash){throw 'UPGRADE_WORKER_HASH'}
  Assert-TimeObservationAcl (Join-Path $d.root 'worker.ps1')
  $dockerChanged=$true;$null=Invoke-CollectorDockerRead $exe @('update','--restart','unless-stopped',$before.containerId)
  $after=Get-CollectorDockerState
  if($after.containerId -cne $before.containerId -or $after.state -cne 'running' -or $after.startedAt -cne $before.startedAt -or $after.restartPolicy -cne 'unless-stopped'){throw 'UPGRADE_CONTAINER_VERIFY'}
  if((Read-TimeObservationFile (Join-Path $d.root 'control.json')).enabled -ne $false){throw 'UPGRADE_CONTROL_CHANGED'}
  $r.containerAfter=$after;$r.taskXmlSha256=Get-CollectorUpgradeHash ([Text.Encoding]::UTF8.GetBytes($newXml))
  $r.installationId=$receipt.runId;$r.taskDisabled=$true;$r.controlDisabled=$true;$r.status='COLLECTOR_RECOVERY_UPGRADED_DISABLED_RUNTIME_PENDING';$r.passed=$true
  Write-CollectorUpgradeNew $destination ([Text.Encoding]::UTF8.GetBytes(($r|ConvertTo-Json -Depth 10)))
 }catch{
  $r.status='REVIEW_REQUIRED';$r.passed=$false;$r.failureLine=$_.InvocationInfo.ScriptLineNumber;$r.failure=if($_.Exception.Message -cmatch '^[A-Z][A-Z0-9_]+$'){$_.Exception.Message}else{'UPGRADE_OPERATION_FAILED'}
  $r.failureType=$_.Exception.GetType().Name
  $r.failureHResult=$_.Exception.HResult
  $rollbackErrors=@()
  try{if($actionChanged){Set-CollectorUpgradeAction $d}}catch{$rollbackErrors+='ACTION'}
  try{
   if($workerChanged){
    $restore=Join-Path $d.root ('restore-'+$r.runId+'.new');Write-CollectorUpgradeNew $restore ([IO.File]::ReadAllBytes((Join-Path $backup 'worker.ps1')))
    [IO.File]::Replace($restore,(Join-Path $d.root 'worker.ps1'),[Management.Automation.Language.NullString]::Value)
   }
  }catch{$rollbackErrors+='WORKER'}
  try{if($dockerChanged){$null=Invoke-CollectorDockerRead $exe @('update','--restart','no',$before.containerId);if((Get-CollectorDockerState).restartPolicy -cne 'no'){throw 'ROLLBACK_DOCKER'}}}catch{$rollbackErrors+='DOCKER'}
  try{
   if($actionChanged -or $workerChanged){
    Assert-DurableCollectorTask (Get-ScheduledTask -TaskName $d.name -TaskPath '\') $d
    if((Export-ScheduledTask -TaskName $d.name -TaskPath '\') -cne $oldXml -or (Get-FileHash -LiteralPath (Join-Path $d.root 'worker.ps1')).Hash -cne $receipt.workerSha256){throw 'ROLLBACK_VERIFY'}
    $r.rollbackVerified=$true
   }
  }catch{$rollbackErrors+='VERIFY'}
  if($rollbackErrors.Count){$r.rollbackFailure='UPGRADE_ROLLBACK_REVIEW_REQUIRED';$r.rollbackSteps=$rollbackErrors;$r.rollbackVerified=$false}
 }finally{if($lease){$lease.Dispose()};if($script:collectorUpgradePassword){$script:collectorUpgradePassword.Dispose();$script:collectorUpgradePassword=$null}}
 return $r
}
$result=Invoke-CollectorRecoveryUpgrade $Mode
[IO.File]::WriteAllText($ResultPath,($result|ConvertTo-Json -Depth 12),[Text.UTF8Encoding]::new($false))
Write-Host ('[100%] '+$result.status)
if($result.failure){throw ('COLLECTOR_UPGRADE_REVIEW_REQUIRED: '+$result.failure)}
