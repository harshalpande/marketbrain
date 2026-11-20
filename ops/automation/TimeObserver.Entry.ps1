# Embedded by Build-TimeObserverJob.ps1. Fixed installation; no supplied commands.
$ErrorActionPreference='Stop'
$r=@{version=1;passed=$false;mode=$Mode;failure=$null;ordersEnabled=$false;credentialsUsed=$false;taskCreated=$false;healthAccountAcceptance=$false}
$root='C:\ProgramData\MarketBrainPaytmHealth\time-observer-v1';$task='MarketBrain-Time-Observer-v1';$watch=[Diagnostics.Stopwatch]::StartNew()
try{
 if($Mode -ceq 'FailureFixture'){throw 'TIME_OBSERVER_DELIBERATE_FIXTURE'}
 $id=[Security.Principal.WindowsIdentity]::GetCurrent()
 try{if(-not ([Security.Principal.WindowsPrincipal]::new($id)).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)){throw 'TIME_OBSERVER_ADMIN_REQUIRED'}}finally{$id.Dispose()}
 Assert-TimeObservationAcl 'C:\ProgramData\MarketBrainPaytmHealth'
 $account=Get-LocalUser -Name 'marketbrain-health'
 if($account.SID.Value -cne 'S-1-5-21-3041730714-102984520-3202743044-1011' -or -not $account.Enabled){throw 'TIME_OBSERVER_ACCOUNT_DRIFT'}
 $existing=@(Get-ScheduledTask|Where-Object {$_.TaskPath -ceq '\' -and $_.TaskName -ceq $task})
 if($Mode -ceq 'Observe'){
  $r.directoryPresent=Test-Path -LiteralPath $root;$r.taskPresent=($existing.Count -gt 0)
  if($r.directoryPresent){$snapshot=Join-Path $root 'snapshot.json';if(Test-Path -LiteralPath $snapshot){$v=Read-TimeObservationFile $snapshot;$r.snapshotIdentity=@{bootId=$v.bootId;expectedBootId=(Get-TimeObservationBootId);frequency=$v.frequency;expectedFrequency=[Diagnostics.Stopwatch]::Frequency;sequence=$v.sequence;version=$v.version}};$r.workerSha256=(Get-FileHash -LiteralPath (Join-Path $root 'worker.ps1')).Hash};if($existing.Count -eq 1){$r.taskState=[string]$existing[0].State}
  $localResult=Join-Path $root 'account-probe-result.json'
  if(Test-Path -LiteralPath $localResult){$r.localAccountProbe=Read-TimeObservationFile $localResult}
  $collectorResult=Join-Path $root 'collector-batch-result.json'
  if(Test-Path -LiteralPath $collectorResult){$r.collectorBatch=Read-TimeObservationFile $collectorResult}
  $installResult=Join-Path $root 'collector-install-result.json'
  if(Test-Path -LiteralPath $installResult){$r.collectorInstallation=Read-TimeObservationFile $installResult;$r.collectorStaging=Get-DurableCollectorStagingPreflight $r.collectorInstallation}
  $r.accountIdentity=Get-TimeAccountIdentityEvidence $account $r.localAccountProbe
  $r.accountExecution=Get-TimeAccountExecutionEvidence $r.localAccountProbe
  $r.status='TIME_OBSERVER_INVENTORY_ONLY';$r.passed=$true;return
 }
 if($existing.Count -eq 1 -and [string]$existing[0].State -ceq 'Running'){throw 'TIME_ACCOUNT_LOCAL_PASSWORD_REQUIRED'}
 $recover=(Test-Path -LiteralPath $root) -or $existing.Count
 if($recover){
  if(-not (Test-Path -LiteralPath $root) -or $existing.Count -ne 1 -or [string]$existing[0].State -cne 'Disabled'){throw 'TIME_OBSERVER_EXISTING_INSTALL_REVIEW_REQUIRED'}
  Assert-TimeObservationAcl $root
  $path=Join-Path $root 'worker.ps1';Assert-TimeObservationAcl $path
  if((Get-FileHash -LiteralPath $path).Hash -cne '7129B3D3844D8E60F039ACE5F9701B100B2A849BB25AB3E5E653B18486BCFBE0'){throw 'TIME_OBSERVER_RECOVERY_WORKER_DRIFT'}
  $r.recovery=$true
 }else{
 $null=New-Item -ItemType Directory -Path $root
 $acl=[Security.AccessControl.DirectorySecurity]::new();$acl.SetAccessRuleProtection($true,$false)
 $acl.SetOwner([Security.Principal.SecurityIdentifier]::new('S-1-5-32-544'))
 foreach($sid in @('S-1-5-18','S-1-5-32-544',$account.SID.Value)){
  $rights=if($sid -ceq $account.SID.Value){[Security.AccessControl.FileSystemRights]::ReadAndExecute}else{[Security.AccessControl.FileSystemRights]::FullControl}
  $acl.AddAccessRule([Security.AccessControl.FileSystemAccessRule]::new([Security.Principal.SecurityIdentifier]::new($sid),$rights,'ContainerInherit,ObjectInherit','None','Allow'))
 }
 Set-Acl -LiteralPath $root -AclObject $acl;Assert-TimeObservationAcl $root
 $path=Join-Path $root 'worker.ps1';$bytes=[Convert]::FromBase64String($timeObserverWorker)
 [IO.File]::WriteAllBytes($path,$bytes);Assert-TimeObservationAcl $path
 }
 $hash=(Get-FileHash -LiteralPath $path).Hash
 $command="if((Get-FileHash -LiteralPath '$path').Hash -cne '$hash'){exit 9};&([scriptblock]::Create([IO.File]::ReadAllText('$path')))"
 $arguments='-NoLogo -NoProfile -NonInteractive -EncodedCommand '+[Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($command))
 $exe=Join-Path $env:WINDIR 'System32\WindowsPowerShell\v1.0\powershell.exe'
 $action=New-ScheduledTaskAction -Execute $exe -Argument $arguments
 $trigger=New-ScheduledTaskTrigger -AtStartup
 $principal=New-ScheduledTaskPrincipal -UserId 'S-1-5-18' -LogonType ServiceAccount -RunLevel Highest
 $settings=New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable -MultipleInstances IgnoreNew -ExecutionTimeLimit ([TimeSpan]::Zero)
 if(-not $recover){
 $null=Register-ScheduledTask -TaskName $task -TaskPath '\' -Description 'MarketBrain fixed read-only Windows time observer v1' -Action $action -Trigger $trigger -Principal $principal -Settings $settings
 $r.taskCreated=$true
 }
 $t=Get-ScheduledTask -TaskName $task -TaskPath '\'
 if($t.Actions.Count -ne 1 -or $t.Actions[0].Arguments -cne $arguments -or $t.Actions[0].Execute -ine $exe -or $t.Principal.UserId -notin @('SYSTEM','S-1-5-18') -or [string]$t.Principal.LogonType -ne 'ServiceAccount' -or $t.Triggers.Count -ne 1 -or $t.Triggers[0].CimClass.CimClassName -cne 'MSFT_TaskBootTrigger'){throw 'TIME_OBSERVER_TASK_VERIFY'}
 $r.workerSha256=$hash
 if($recover){$r.recoveryStartAttempted=$true;$null=Enable-ScheduledTask -TaskName $task -TaskPath '\'}
 Start-ScheduledTask -TaskName $task -TaskPath '\'
 $first=$null;$last=$null;$startedTicks=[Diagnostics.Stopwatch]::GetTimestamp()
 for($i=0;$i -lt 15;$i++){
  Start-Sleep -Seconds 1
  if(Test-Path -LiteralPath (Join-Path $root 'snapshot.json')){
   $snapshotPath=Join-Path $root 'snapshot.json';Assert-TimeObservationAcl $snapshotPath
   $snapshot=ConvertFrom-TimeObservationJson ([IO.File]::ReadAllText($snapshotPath))
   if($snapshot.endTicks -lt $startedTicks){continue}
   $last=Read-TimeObservation
   if($first -and $last.sequence -gt $first.sequence){break}
   $first=$last
  }
 }
 if(-not $last -or -not $first -or $last.sequence -le $first.sequence){throw 'TIME_OBSERVER_NO_FRESH_SEQUENCE'}
 $r.firstSequence=$first.sequence;$r.lastSequence=$last.sequence;$r.ageSeconds=$last.ageSeconds
 $r.status='TIME_OBSERVER_SYSTEM_PASSED_HEALTH_ACCOUNT_PENDING';$r.passed=$true
}catch{
 $r.failure=if($_.Exception.Message -cmatch '^(TIME_OBSERVER|TIME_ACCOUNT|COLLECTOR)_[A-Z_]+$'){$_.Exception.Message}else{'TIME_OBSERVER_'+$_.Exception.GetBaseException().GetType().Name}
 $r.failureLine=$_.InvocationInfo.ScriptLineNumber
 if($r.taskCreated -or $r.recoveryStartAttempted){try{$null=Disable-ScheduledTask -TaskName $task -TaskPath '\';Stop-ScheduledTask -TaskName $task -TaskPath '\';$r.failureStopRequested=$true}catch{$r.cleanupFailure='TIME_OBSERVER_STOP_REVIEW_REQUIRED'}}
}finally{
 $r.elapsedSeconds=$watch.Elapsed.TotalSeconds
 [IO.File]::WriteAllText($ResultPath,($r|ConvertTo-Json -Depth 6),[Text.UTF8Encoding]::new($false))
}
if(-not $r.passed){exit 1}
