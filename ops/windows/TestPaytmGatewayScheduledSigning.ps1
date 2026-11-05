#Requires -Version 7.0
[CmdletBinding()]param(
    [switch]$InspectExisting,
    [string]$AgentFailureReportPath,
    [string]$CustodyReportPath='C:\MarketBrainData\Review\paytm-key-custody-20261102-112446-29cb6394513a47f687351825698006d5.json',
    [string]$OutputDirectory='C:\MarketBrainData\Review')
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'PaytmGatewayAccount.ps1')
. (Join-Path $PSScriptRoot 'PaytmGatewayAccountRepair.ps1')
. (Join-Path $PSScriptRoot 'PaytmGatewayKeyCustody.ps1')
. (Join-Path $PSScriptRoot 'PaytmGatewayScheduledProbe.ps1')
if($AgentFailureReportPath){
 foreach($n in @('PaytmSupervisorHost.ps1','PaytmSupervisorInstallation.ps1','PaytmAgentSigning.ps1')){. (Join-Path $PSScriptRoot $n)}
}
$run=[guid]::NewGuid().ToString('N');$c=Get-PaytmScheduledProbeContract $run
$timer=[Diagnostics.Stopwatch]::StartNew();$password=$null;$stream=$null;$registered=$false;$mayBeRegistered=$false;$enabled=$false
$report=[ordered]@{version=1;runId=$run;status='REVIEW_REQUIRED';stage='PREFLIGHT';failure=$null;failureDetails=$null;
 sourceHashes=[ordered]@{};acceptedProgress=@();prerequisites=$null;taskName=$c.name;taskRegistered=$false;
 inspectionOnly=[bool]$InspectExisting;existingProbes=@();
 taskDefinitionVerified=$false;taskDefinition=$null;taskStarted=$false;lastTaskResult=$null;taskState=$null;worker=$null;
 taskDisabled=$false;taskRemoved=$false;cleanupFailure=$null;stagingCreated=$false;elapsedSeconds=0;
 schedulerPasswordSupplied=$false;keyImported=$false;agentChanged=$false;networkContacted=$false;
 tunnelStarted=$false;proxyStarted=$false;ordersEnabled=$false;rebootTested=$false;productionSupervisorInstalled=$false}
function Save-ScheduledCheckpoint {
 $report.elapsedSeconds=[math]::Round($timer.Elapsed.TotalSeconds,3)
 $bytes=[Text.Encoding]::UTF8.GetBytes(($report|ConvertTo-Json -Depth 10))
 $stream.Position=0;$stream.SetLength(0);$stream.Write($bytes,0,$bytes.Length);$stream.Flush($true)
}
function Scheduled-Step([string]$Name,[int]$Percent) {
 $report.stage=$Name;Save-ScheduledCheckpoint;Write-Host "[$Percent%] $Name"
 Write-Progress -Activity 'Scheduled gateway signing' -Status $Name -PercentComplete $Percent
}
$null=New-Item -ItemType Directory -Path $OutputDirectory -Force
$path=Join-Path $OutputDirectory ('paytm-scheduled-signing-'+(Get-Date -Format 'yyyyMMdd-HHmmss')+'-'+$run+'.json')
try {
 $stream=[IO.File]::Open($path,'CreateNew','Write','Read');Save-ScheduledCheckpoint
 foreach($name in @('TestPaytmGatewayScheduledSigning.ps1','PaytmGatewayScheduledProbe.ps1','PaytmGatewayKeyCustody.ps1','PaytmGatewayAccount.ps1','PaytmGatewayAccountRepair.ps1')){
  $report.sourceHashes[$name]=(Get-FileHash -LiteralPath (Join-Path $PSScriptRoot $name)).Hash
 }
 $report.acceptedProgress=@(Get-PaytmReadinessProgress)
 Assert-PaytmCustodyController
 Import-Module Microsoft.PowerShell.LocalAccounts -ErrorAction Stop
 Import-Module ScheduledTasks -ErrorAction Stop
 if($AgentFailureReportPath){
  if($InspectExisting){throw 'SCHEDULE_AGENT_INSPECTION_CONFLICT'}
  $report.agentFailureReview=Assert-PaytmAgentSigningReceipt $AgentFailureReportPath
  $report.productionBefore=Get-PaytmAgentSigningSnapshot
  if($report.productionBefore.hashes.'session-checkpoint.json' -cne $report.agentFailureReview.checkpointHash){throw 'SCHEDULE_AGENT_CHECKPOINT_CHANGED'}
  foreach($n in @('PaytmAgentSigning.ps1','PaytmSupervisorHost.ps1','PaytmSupervisorInstallation.ps1')){$report.sourceHashes[$n]=(Get-FileHash -LiteralPath (Join-Path $PSScriptRoot $n)).Hash}
  Save-ScheduledCheckpoint
 }
 Scheduled-Step 'REVALIDATE_ACCEPTED_CUSTODY' 10
 $report.prerequisites=Assert-PaytmScheduledPrerequisites $CustodyReportPath
 if((Get-Service -Name Schedule -ErrorAction Stop).Status -ne 'Running'){throw 'SCHEDULE_SERVICE_NOT_RUNNING'}
 if(-not (Test-Path -LiteralPath $c.executable -PathType Leaf)){throw 'SCHEDULE_EXECUTABLE_MISSING'}
 $existing=@(Get-ScheduledTask -ErrorAction Stop|Where-Object {$_.TaskPath -ceq '\' -and $_.TaskName -clike 'MarketBrain-Gateway-Key-Probe-*'})
 $report.existingProbes=@(Get-PaytmExistingProbeEvidence $existing $OutputDirectory);Save-ScheduledCheckpoint
 if($InspectExisting){
  $report.stage='INSPECT_EXISTING';$report.status='SCHEDULED_PROBE_INVENTORY_CAPTURED'
  Write-Host 'Existing task definitions and prior result summaries captured. No task or credential changes.'
  return
 }
 if($existing.Count){throw 'SCHEDULE_PREVIOUS_PROBE_REVIEW_REQUIRED'}
 foreach($p in @($c.directory,$c.result)){$null=Assert-PaytmAccountPath $p;if(Test-Path -LiteralPath $p){throw 'SCHEDULE_PATH_COLLISION'}}
 Write-Host 'Creates one temporary, non-admin, demand-start task with a 2-minute execution limit and no triggers.'
 Write-Host 'Windows Task Scheduler needs the existing Windows gateway account password. No SSH passphrase is requested.'
 Write-Host 'The task only checks its identity and signs locally twice. Successful task is removed; failed task is disabled and retained for review.'
 if((Read-Host 'Type TEST-SCHEDULED-KEY to proceed') -cne 'TEST-SCHEDULED-KEY'){throw 'SCHEDULE_OWNER_CANCELLED'}
 $password=Read-Host 'Existing WINDOWS marketbrain-gateway account password' -AsSecureString
 Scheduled-Step 'STAGE_PROTECTED_WORKER' 25
 $null=Assert-PaytmScheduledPrerequisites $CustodyReportPath
 $null=New-Item -ItemType Directory -Path $c.directory;Set-PaytmAccountDirectoryAcl $c.directory (Get-PaytmKeyContract).accountSid
 $report.stagingCreated=$true
 $workerPath=Join-Path $c.directory 'worker.ps1';$data=[Text.Encoding]::UTF8.GetBytes((New-PaytmScheduledWorkerSource $run))
 $f=[IO.File]::Open($workerPath,'CreateNew','Write','None');try{$f.Write($data,0,$data.Length);$f.Flush($true)}finally{$f.Dispose()}
 $workerHash=(Get-FileHash -LiteralPath $workerPath).Hash
 Scheduled-Step 'REGISTER_DISABLED_TEMPORARY_TASK' 40
 if(@(Get-PaytmProbeTask $c.name).Count){throw 'SCHEDULE_TASK_COLLISION'}
 $mayBeRegistered=$true;$report.schedulerPasswordSupplied=$true;Save-ScheduledCheckpoint
 Register-PaytmProbeTask $run $password;$registered=$true;$report.taskRegistered=$true
 $tasks=@(Get-PaytmProbeTask $c.name);if($tasks.Count -ne 1){throw 'SCHEDULE_TASK_MISSING'}
 $report.taskDefinition=Get-PaytmProbeTaskShape $tasks[0] $run;Save-ScheduledCheckpoint
 Assert-PaytmProbeTask $tasks[0] $run $false;$report.taskDefinitionVerified=$true;Save-ScheduledCheckpoint
 Scheduled-Step 'RUN_BACKGROUND_SIGNING_CHECKS' 60
 if((Get-FileHash -LiteralPath $workerPath).Hash -cne $workerHash){throw 'SCHEDULE_WORKER_CHANGED'}
 $null=Enable-ScheduledTask -TaskName $c.name -TaskPath $c.path -ErrorAction Stop;$enabled=$true
 $tasks=@(Get-PaytmProbeTask $c.name);Assert-PaytmProbeTask $tasks[0] $run $true
 Start-ScheduledTask -TaskName $c.name -TaskPath $c.path -ErrorAction Stop;$report.taskStarted=$true;Save-ScheduledCheckpoint
 Wait-PaytmProbeTask $run $report {Save-ScheduledCheckpoint}
 Assert-PaytmScheduledWorker $report.worker $run
 if($report.lastTaskResult -ne 0){throw 'SCHEDULE_NONZERO_TASK_RESULT'}
 $report.status=if($AgentFailureReportPath){'AGENT_SIGNING_PASSED_PRODUCTION_RECOVERY_PENDING'}else{'SCHEDULED_SIGNING_PASSED_SUPERVISOR_INSTALLATION_PENDING'};$report.stage='COMPLETE'
}catch{
 $report.failure=if($_.Exception.Message -cmatch '^(SCHEDULE|ACCOUNT|KEY|HOST)_[A-Z_]+$'){$_.Exception.Message}else{'SCHEDULE_PROBE_FAILED'}
 $base=$_.Exception.GetBaseException()
 $report.failureDetails=[pscustomobject]@{type=$base.GetType().Name;hresult=$base.HResult;line=$_.InvocationInfo.ScriptLineNumber}
}finally{
 if($mayBeRegistered){
  try{
   $tasks=@(Get-PaytmProbeTask $c.name)
   if($tasks.Count -eq 1){
    $report.taskDefinition=Get-PaytmProbeTaskShape $tasks[0] $run
    # Registration/enable may have succeeded before throwing: inspect actual enabled state.
    Assert-PaytmProbeTask $tasks[0] $run ([bool]$tasks[0].Settings.Enabled)
    $report.taskRegistered=$true
    $null=Disable-ScheduledTask -TaskName $c.name -TaskPath $c.path -ErrorAction Stop
    $tasks=@(Get-PaytmProbeTask $c.name);Assert-PaytmProbeTask $tasks[0] $run $false;$report.taskDisabled=$true
    if([string]$tasks[0].State -cin @('Running','Queued')){
     Stop-ScheduledTask -TaskName $c.name -TaskPath $c.path -ErrorAction Stop
     $stop=[Diagnostics.Stopwatch]::StartNew()
     do{$tasks=@(Get-PaytmProbeTask $c.name);if([string]$tasks[0].State -cnotin @('Running','Queued')){break};Start-Sleep -Milliseconds 250}while($stop.Elapsed.TotalSeconds -lt 5)
     if([string]$tasks[0].State -cin @('Running','Queued')){throw 'SCHEDULE_STOP_NOT_CONFIRMED'}
    }
    if($null -eq $report.failure){
     Assert-PaytmProbeTask $tasks[0] $run $false
     Unregister-ScheduledTask -TaskName $c.name -TaskPath $c.path -Confirm:$false -ErrorAction Stop
     if(@(Get-PaytmProbeTask $c.name).Count){throw 'SCHEDULE_REMOVE_NOT_CONFIRMED'};$report.taskRemoved=$true
    }
   }elseif($registered){throw 'SCHEDULE_TASK_DISAPPEARED'}
  }catch{$report.cleanupFailure='SCHEDULE_CLEANUP_REVIEW_REQUIRED';$report.status='REVIEW_REQUIRED'}
 }
 if($report.taskStarted -and $null -eq $report.worker -and (Test-Path -LiteralPath $c.result)){
  try{$partial=Read-PaytmRepairJson $c.result 8192;if($partial.runId -ceq $run){$report.worker=$partial}}catch{}
 }
 if($null -ne $password){$password.Dispose()}
 if($AgentFailureReportPath -and $report.Contains('productionBefore')){
  try{
   $report.productionAfter=Get-PaytmAgentSigningSnapshot
   $report.productionStateUnchanged=($report.productionBefore|ConvertTo-Json -Depth 5 -Compress) -ceq ($report.productionAfter|ConvertTo-Json -Depth 5 -Compress)
   if(-not $report.productionStateUnchanged){throw 'SCHEDULE_AGENT_PRODUCTION_CHANGED'}
  }catch{$report.cleanupFailure='SCHEDULE_AGENT_PRODUCTION_STATE_REVIEW_REQUIRED';$report.status='REVIEW_REQUIRED'}
 }
 if($report.failure -or $report.cleanupFailure){$report.status='REVIEW_REQUIRED'}
 $timer.Stop();if($null -ne $stream){try{Save-ScheduledCheckpoint}finally{$stream.Dispose()}}
 Write-Progress -Activity 'Scheduled gateway signing' -Completed
 Write-Host "[100%] $($report.status); elapsed=$($report.elapsedSeconds)s"
 Write-Host "Share this ONE file: $path"
 if($report.status -ceq 'REVIEW_REQUIRED'){Write-Host 'Preserve the report and any retained task/files for review. Do not rerun or reset the account.'}
 elseif($InspectExisting){Write-Host 'Read-only inspection finished. Share the report before retrying; existing tasks and keys are unchanged.'}
 else{Write-Host 'Temporary task removed. Key retained in its existing agent; no tunnel/proxy or production supervisor was started.'}
}
if($report.status -ceq 'REVIEW_REQUIRED'){throw 'Scheduled signing requires review; share the printed JSON.'}
