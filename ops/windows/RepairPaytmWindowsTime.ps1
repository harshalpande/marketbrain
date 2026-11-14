#Requires -Version 7.0
[CmdletBinding()]param(
 [ValidateSet('ServiceStartup','AdaptivePolling')][string]$Mode='ServiceStartup',
 [string]$EvidencePath='C:\MarketBrainData\Review\paytm-windows-time-access-20261115-005901-8ed634625bae4a1d912cb65d17e48648.json',
 [string]$OutputDirectory='C:\MarketBrainData\Review')
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'PaytmGatewayAccount.ps1')
. (Join-Path $PSScriptRoot 'PaytmGatewayKeyCustody.ps1')
. (Join-Path $PSScriptRoot 'PaytmTimeServiceRepair.ps1')
$deadline=if($Mode -eq 'AdaptivePolling'){420}else{240}
$taskMinutes=if($Mode -eq 'AdaptivePolling'){8}else{5}
$run=[guid]::NewGuid().ToString('N');$timer=[Diagnostics.Stopwatch]::StartNew();$registered=$false;$lease=$null
$name='MarketBrain-TimeRepair-'+$run;$work='C:\ProgramData\MarketBrainTimeRepair\'+$run
$exe=Join-Path $env:WINDIR 'System32\WindowsPowerShell\v1.0\powershell.exe'
$report=[ordered]@{version=1;runId=$run;mode=$Mode;status='REVIEW_REQUIRED';failure=$null;cleanupFailure=$null;elapsedSeconds=0;sourceHashes=@{};taskRemoved=$false;worker=$null;clockAlignmentVerified=$false;brokerCredentialsUsed=$false;ordersEnabled=$false}
$null=Assert-PaytmAccountPath $OutputDirectory;$null=New-Item -ItemType Directory -Path $OutputDirectory -Force
$path=Join-Path $OutputDirectory ('paytm-time-repair-'+$run+'.json')
function Save-TimeRepair {$report.elapsedSeconds=$timer.Elapsed.TotalSeconds;[IO.File]::WriteAllText($path,($report|ConvertTo-Json -Depth 16),[Text.UTF8Encoding]::new($false))}
function Protect-TimeDirectory([string]$p){
 $null=Assert-PaytmAccountPath $p
 if(-not (Test-Path -LiteralPath $p)){
  $null=New-Item -ItemType Directory -Path $p
  $acl=[Security.AccessControl.DirectorySecurity]::new();$acl.SetAccessRuleProtection($true,$false)
  $acl.SetOwner([Security.Principal.SecurityIdentifier]::new('S-1-5-32-544'))
  foreach($sid in @('S-1-5-18','S-1-5-32-544')){$acl.AddAccessRule([Security.AccessControl.FileSystemAccessRule]::new([Security.Principal.SecurityIdentifier]::new($sid),'FullControl','ContainerInherit,ObjectInherit','None','Allow'))}
  Set-Acl -LiteralPath $p -AclObject $acl
 }
 $a=Get-Acl -LiteralPath $p;$rules=@($a.GetAccessRules($true,$true,[Security.Principal.SecurityIdentifier]))
 if(-not $a.AreAccessRulesProtected -or $a.GetOwner([Security.Principal.SecurityIdentifier]).Value -cne 'S-1-5-32-544' -or $rules.Count -ne 2){throw 'TIME_REPAIR_DIRECTORY_ACL'}
 foreach($sid in @('S-1-5-18','S-1-5-32-544')){
  $r=@($rules|Where-Object {$_.IdentityReference.Value -ceq $sid})
  if($r.Count -ne 1 -or $r[0].AccessControlType -ne 'Allow' -or $r[0].IsInherited -or $r[0].FileSystemRights -ne 'FullControl' -or $r[0].InheritanceFlags -ne 'ContainerInherit, ObjectInherit' -or $r[0].PropagationFlags -ne 'None'){throw 'TIME_REPAIR_DIRECTORY_ACL'}
 }
}
function Get-OwnedTimeTask {
 $t=Get-ScheduledTask -TaskName $name -TaskPath '\' -ErrorAction Stop
 if(@($t.Actions).Count -ne 1 -or $t.Actions[0].Execute -ine $exe -or $t.Actions[0].Arguments -cne $arguments -or $t.Actions[0].WorkingDirectory -ine $work -or $t.Principal.UserId -notin @('SYSTEM','S-1-5-18') -or [string]$t.Principal.LogonType -ne 'ServiceAccount' -or [string]$t.Principal.RunLevel -ne 'Highest' -or @($t.Triggers | Where-Object {$null -ne $_}).Count -ne 0){throw 'TIME_REPAIR_TASK_IDENTITY'}
 $t
}
try{
 Save-TimeRepair;Assert-PaytmCustodyController;Import-Module ScheduledTasks
 $null=Assert-PaytmAccountPath $EvidencePath
 $expectedHash=if($Mode -eq 'AdaptivePolling'){'2D2EF859C6EAD50E44880FC1EEDA04E31EC6808CF6E997E0D80B4E56820518E3'}else{'68D4CCA6429665966142830CFEC6AE11819BA400A209927F01BEFA87769E6EC1'}
 if((Get-FileHash -LiteralPath $EvidencePath).Hash -cne $expectedHash){throw 'TIME_REPAIR_EVIDENCE_HASH'}
 foreach($n in @('RepairPaytmWindowsTime.ps1','PaytmTimeServiceRepair.ps1','InvokePaytmTimeRepairWorker.ps1')){$report.sourceHashes[$n]=(Get-FileHash -LiteralPath (Join-Path $PSScriptRoot $n)).Hash}
 Write-Host "[10%] Verify reviewed service baseline for $Mode"
 $report.before=Get-PaytmTimeRepairSnapshot;if($Mode -eq 'AdaptivePolling'){Assert-PaytmPollingBaseline $report.before}else{Assert-PaytmTimeRepairBaseline $report.before};Save-TimeRepair
 Protect-TimeDirectory 'C:\ProgramData\MarketBrainTimeRepair'
 $lease=[IO.File]::Open('C:\ProgramData\MarketBrainTimeRepair\repair.lock','OpenOrCreate','ReadWrite','None')
 Protect-TimeDirectory $work
 foreach($pair in @(@('PaytmTimeServiceRepair.ps1','helper.ps1'),@('InvokePaytmTimeRepairWorker.ps1','worker.ps1'))){
  Copy-Item -LiteralPath (Join-Path $PSScriptRoot $pair[0]) -Destination (Join-Path $work $pair[1]) -ErrorAction Stop
  if((Get-FileHash -LiteralPath (Join-Path $work $pair[1])).Hash -cne $report.sourceHashes[$pair[0]]){throw 'TIME_REPAIR_COPY_HASH'}
 }
 $arguments='-NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass -File "'+(Join-Path $work 'worker.ps1')+'" -RunId '+$run+' -HelperHash '+$report.sourceHashes['PaytmTimeServiceRepair.ps1']+' -Mode '+$Mode
 $action=New-ScheduledTaskAction -Execute $exe -Argument $arguments -WorkingDirectory $work
 $principal=New-ScheduledTaskPrincipal -UserId 'SYSTEM' -LogonType ServiceAccount -RunLevel Highest
 $settings=New-ScheduledTaskSettingsSet -MultipleInstances IgnoreNew -ExecutionTimeLimit ([TimeSpan]::FromMinutes($taskMinutes)) -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries
 $null=Register-ScheduledTask -TaskName $name -TaskPath '\' -Action $action -Principal $principal -Settings $settings -ErrorAction Stop
 $registered=$true;$null=Get-OwnedTimeTask
 $report.protectedWorkDirectory=$work;Save-TimeRepair
 Write-Host "[25%] One SYSTEM task: $Mode; progress and before-image checkpointed"
 Start-ScheduledTask -TaskName $name -TaskPath '\'
 $wait=[Diagnostics.Stopwatch]::StartNew();$resultPath=Join-Path $work 'worker.json'
 do{
  $task=Get-OwnedTimeTask
  if([string]$task.State -cnotin @('Running','Queued') -and (Test-Path -LiteralPath $resultPath)){break}
  if($wait.Elapsed.TotalSeconds -gt 10 -and [string]$task.State -cnotin @('Running','Queued') -and (Get-ScheduledTaskInfo -TaskName $name -TaskPath '\').LastTaskResult -notin @(0,267011)){throw 'TIME_REPAIR_WORKER_EXIT_WITHOUT_REPORT'}
  if($wait.Elapsed.TotalSeconds -gt $deadline){throw 'TIME_REPAIR_WORKER_TIMEOUT'}
  Write-Progress -Activity 'Windows Time repair' -Status ('Waiting for one-time task: {0:N0}/{1}s' -f $wait.Elapsed.TotalSeconds,$deadline) -PercentComplete ([math]::Min(85,25+[int]($wait.Elapsed.TotalSeconds/4)))
  if([int]$wait.Elapsed.TotalSeconds % 10 -eq 0){Write-Host ('[50%] Repair task running: {0:N0}s' -f $wait.Elapsed.TotalSeconds)}
  Start-Sleep -Seconds 1
 }while($true)
 if((Get-Item -LiteralPath $resultPath).Length -gt 100000){throw 'TIME_REPAIR_RESULT_SIZE'}
 $report.worker=Get-Content -LiteralPath $resultPath -Raw|ConvertFrom-Json
 if($report.worker.runId -cne $run -or -not $report.worker.completed){throw 'TIME_REPAIR_RESULT_IDENTITY'}
 $expectedWorkerStatus=if($Mode -eq 'AdaptivePolling'){'TIME_POLLING_CHANGED_SYNC_OBSERVED_RELEASE_PENDING'}else{'TIME_SERVICE_RUNNING_AUTOMATIC_RESYNC_ACCEPTED_ALIGNMENT_PENDING'}
 if((Get-ScheduledTaskInfo -TaskName $name -TaskPath '\').LastTaskResult -ne 0 -or $report.worker.status -cne $expectedWorkerStatus -or $report.worker.failure -or $report.worker.cleanupFailure){throw 'TIME_REPAIR_WORKER_REVIEW_REQUIRED'}
 $report.after=Get-PaytmTimeRepairSnapshot;if($Mode -eq 'AdaptivePolling'){Assert-PaytmPollingPreserved $report.before $report.after 'time.windows.com,0x8'}else{Assert-PaytmTimeRepairPreserved $report.before $report.after}
 if($report.after.state -cne 'Running' -or $report.after.startType -ne 2){throw 'TIME_REPAIR_PARENT_FINAL_STATE'}
 $report.status=if($Mode -eq 'AdaptivePolling'){'TIME_POLLING_CHANGED_SYNC_OBSERVED_RELEASE_PENDING'}else{'TIME_SERVICE_REPAIRED_ALIGNMENT_RECHECK_PENDING'}
}catch{$report.failure=$_.Exception.Message}
finally{
 if($registered){try{
  $t=Get-OwnedTimeTask
  if([string]$t.State -cin @('Running','Queued')){
   Stop-ScheduledTask -TaskName $name -TaskPath '\';$stop=[Diagnostics.Stopwatch]::StartNew()
   do{$t=Get-OwnedTimeTask;if([string]$t.State -cnotin @('Running','Queued')){break};Start-Sleep -Milliseconds 250}while($stop.Elapsed.TotalSeconds -lt 10)
   if([string]$t.State -cin @('Running','Queued')){throw 'TIME_REPAIR_TASK_STILL_RUNNING'}
  }
  Unregister-ScheduledTask -TaskName $name -TaskPath '\' -Confirm:$false
  if(Get-ScheduledTask -TaskName $name -TaskPath '\' -ErrorAction SilentlyContinue){throw 'TIME_REPAIR_TASK_REMAINS'}
  $report.taskRemoved=$true
 }catch{$report.cleanupFailure=$_.Exception.Message}}
 if($lease){$lease.Dispose()}
 if($report.failure -or $report.cleanupFailure){$report.status='REVIEW_REQUIRED'}
 Save-TimeRepair;Write-Progress -Activity 'Windows Time repair' -Completed
 Write-Host "[100%] $($report.status)"
 Write-Host "Share this ONE file: $path"
}
if($report.status -eq 'REVIEW_REQUIRED'){throw 'Share the JSON; do not reset service permissions or repeat the repair.'}
