#Requires -Version 7.0
[CmdletBinding()]param([string]$CustodyReportPath='C:\MarketBrainData\Review\paytm-health-key-custody-d5e799ea1ba84d438008f64c13e41571.json',[string]$OutputDirectory='C:\MarketBrainData\Review',[string]$TokenReportPath='',[string]$CollectorDeploymentReport='')
$ErrorActionPreference='Stop'
foreach($n in @('PaytmGatewayAccount.ps1','PaytmGatewayAccountRepair.ps1','PaytmHealthAccount.ps1','PaytmGatewayKeyCustody.ps1','PaytmHealthKeyCustody.ps1','PaytmHealthScheduledProbe.ps1','PaytmHealthBatchLogon.ps1')){. (Join-Path $PSScriptRoot $n)}
. (Join-Path $PSScriptRoot 'PaytmHealthScheduledToken.ps1')
$run=[guid]::NewGuid().ToString('N');$c=Get-HealthScheduledProbeContract $run;$watch=[Diagnostics.Stopwatch]::StartNew();$password=$null;$mayExist=$false
$null=New-Item -ItemType Directory -Path $OutputDirectory -Force
$path=Join-Path $OutputDirectory "paytm-health-scheduled-$run.json"
$r=[ordered]@{version=1;runId=$run;status='REVIEW_REQUIRED';stage='PREFLIGHT';failure=$null;failureDetails=$null;cleanupFailure=$null;sourceHashes=@{};policyBefore=$null;policyAfter=$null;denyAssessment=@();batchGrantAttempted=$false;taskName=$c.name;taskRegistered=$false;taskStarted=$false;taskDisabled=$false;taskRemoved=$false;taskState=$null;lastTaskResult=$null;worker=$null;fresh=$null;elapsedSeconds=0;ordersEnabled=$false;keyImported=$false;productionTaskInstalled=$false}
function Save-HealthScheduled {$r.elapsedSeconds=$watch.Elapsed.TotalSeconds;[IO.File]::WriteAllText($path,($r|ConvertTo-Json -Depth 10))}
function Health-Step([string]$Name,[int]$Percent){$r.stage=$Name;Save-HealthScheduled;Write-Progress -Activity 'Scheduled clock access' -Status $Name -PercentComplete $Percent;Write-Host "[$Percent%] $Name"}
try{
 Save-HealthScheduled;Assert-PaytmCustodyController
 Import-Module ScheduledTasks -ErrorAction Stop
 Import-Module Microsoft.PowerShell.LocalAccounts -ErrorAction Stop
 $null=Assert-HealthScheduledPrerequisites $CustodyReportPath
 if($CollectorDeploymentReport){
  if(-not $TokenReportPath -or (Get-FileHash -LiteralPath $CollectorDeploymentReport).Hash -cne '97822DC022A95034613F3C0F3BFF06F6705B3054FEE7FC51CBE5CF79404B7F69'){throw 'SCHEDULE_COLLECTOR_DEPLOYMENT_RECEIPT'}
  $r['collectorMode']=$true
  foreach($n in @('PaytmTimeServiceRepair.ps1','PaytmLiveHealthCollector.ps1','PaytmHealthCollectorCore.ps1')){$r.sourceHashes[$n]=(Get-FileHash -LiteralPath "$PSScriptRoot/$n").Hash}
 }
 if($TokenReportPath){Assert-HealthScheduledTokenPrerequisites $TokenReportPath;$r['tokenMode']=$true}
 $preparedSource=New-HealthScheduledWorkerSource $run -WithToken:([bool]$TokenReportPath) -WithCollector:([bool]$CollectorDeploymentReport)
 $r.sourceHashes['PaytmHealthScheduledToken.ps1']=(Get-FileHash -LiteralPath "$PSScriptRoot/PaytmHealthScheduledToken.ps1").Hash
 foreach($n in @('TestPaytmHealthScheduledAccess.ps1','PaytmHealthScheduledProbe.ps1','PaytmHealthScheduledWorker.ps1','PaytmHealthBatchLogon.ps1','PaytmHealthKeyCustody.ps1','PaytmHealthAccount.ps1','PaytmGatewayAccount.ps1','PaytmGatewayAccountRepair.ps1','PaytmGatewayKeyCustody.ps1','paytm-vps-host-rsa.pub')){$r.sourceHashes[$n]=(Get-FileHash -LiteralPath "$PSScriptRoot/$n").Hash}
 $pins=ConvertFrom-PaytmHostPublicKey ([IO.File]::ReadAllText("$PSScriptRoot/paytm-vps-host-rsa.pub").Trim())
 $null=Assert-PaytmAccountPath $c.directory;$null=Assert-PaytmAccountPath $c.result
 if((Test-Path -LiteralPath $c.directory) -or (Test-Path -LiteralPath $c.result) -or @(Get-HealthProbeTask $c.name).Count){throw 'SCHEDULE_TARGET_COLLISION'}
 Health-Step 'REVIEW_BATCH_LOGON_POLICY' 10
 $r.policyBefore=Get-HealthBatchPolicy;Assert-HealthBatchPolicy $r.policyBefore $r;Save-HealthScheduled
 if($TokenReportPath -and (Get-HealthScheduledKeyContract).accountSid -cnotin @($r.policyBefore.allow)){throw 'SCHEDULE_TOKEN_BATCH_RIGHT_CHANGED'}
 Write-Host 'One temporary background task will sign twice and read the pinned VPS clock. If needed, only marketbrain-health receives Log on as a batch job. No deny policy is removed. The allow right remains for the future collector.'
 if($TokenReportPath -and -not $CollectorDeploymentReport){Write-Host 'Also decrypt the existing health token in session 0 and authenticate locally with an unhealthy/locked submission. No token import or healthy publication.'}
 if($CollectorDeploymentReport){Write-Host 'Collector mode: three LIVE Windows/VPS/Java/proxy checks; publish diagnostic health only when valid, then revoke health. No route arm or orders.'}
 $password=Read-Host 'Existing WINDOWS marketbrain-health account password (no SSH passphrase needed)' -AsSecureString
 Health-Step 'VALIDATE_EXACT_ACCOUNT_PASSWORD_AND_SIGNING' 20
 $i=New-PaytmAccountProbeStartInfo $password 'marketbrain-health';$diag=@{}
 try{$r.fresh=Invoke-PaytmAccountProbeProcess $i (New-HealthKeyFreshSource $run) $diag}finally{$i.Password=$null}
 Save-HealthScheduled
 if($r.fresh.runId -cne $run -or $r.fresh.failure -or $r.fresh.identityVerified -ne $true -or $r.fresh.signingVerified -ne $true){throw 'SCHEDULE_FRESH_ACCOUNT_FAILED'}
 Health-Step 'ENSURE_ONLY_HEALTH_BATCH_RIGHT' 30
 $before=Get-HealthBatchPolicy
 if(($before|ConvertTo-Json -Compress) -cne ($r.policyBefore|ConvertTo-Json -Compress)){throw 'SCHEDULE_POLICY_CHANGED'}
 if((Get-HealthScheduledKeyContract).accountSid -cnotin @($before.allow)){$r.batchGrantAttempted=$true;Save-HealthScheduled;Add-HealthBatchRight}
 $r.policyAfter=Get-HealthBatchPolicy;Save-HealthScheduled;Assert-HealthBatchPolicyDelta $before $r.policyAfter
 $null=Assert-HealthScheduledPrerequisites $CustodyReportPath
 if($TokenReportPath){Assert-HealthScheduledTokenPrerequisites $TokenReportPath}
 $null=New-Item -ItemType Directory -Path $c.directory -ErrorAction Stop
 Set-PaytmAccountDirectoryAcl $c.directory (Get-HealthScheduledKeyContract).accountSid
 foreach($item in @(@('worker.ps1',$preparedSource),@('known_hosts',$pins.knownHost))){
  $f=[IO.File]::Open((Join-Path $c.directory $item[0]),'CreateNew','Write','None');try{$b=[Text.Encoding]::UTF8.GetBytes($item[1]);$f.Write($b,0,$b.Length);$f.Flush($true)}finally{$f.Dispose()}
 }
 $workerHash=(Get-FileHash -LiteralPath (Join-Path $c.directory 'worker.ps1')).Hash
 Health-Step 'REGISTER_DISABLED_TEMPORARY_TASK' 40
 if(@(Get-HealthProbeTask $c.name).Count){throw 'SCHEDULE_TASK_COLLISION'}
 $mayExist=$true;Register-HealthProbeTask $run $password;$r.taskRegistered=$true
 $tasks=@(Get-HealthProbeTask $c.name);if($tasks.Count -ne 1){throw 'SCHEDULE_TASK_MISSING'}
 Assert-HealthProbeTask $tasks[0] $run $false
 if((Get-FileHash -LiteralPath (Join-Path $c.directory 'worker.ps1')).Hash -cne $workerHash){throw 'SCHEDULE_WORKER_CHANGED'}
 Health-Step 'RUN_BACKGROUND_SIGNING_AND_CLOCK' 60
 $null=Enable-ScheduledTask -TaskName $c.name -TaskPath $c.path -ErrorAction Stop
 $tasks=@(Get-HealthProbeTask $c.name);Assert-HealthProbeTask $tasks[0] $run $true
 Start-ScheduledTask -TaskName $c.name -TaskPath $c.path -ErrorAction Stop;$r.taskStarted=$true;Save-HealthScheduled
 Wait-HealthProbeTask $run $r {Save-HealthScheduled}
 Assert-HealthScheduledWorker $r.worker $run
 if($TokenReportPath){Assert-HealthScheduledTokenResult $r.worker}
 if($CollectorDeploymentReport){
  if($r.worker.finalHealthRevoked -ne $true -or @($r.worker.collectorRounds).Count -ne 3 -or @($r.worker.collectorRounds|Where-Object {$_.accepted -ne $true -or $_.healthySubmitted -ne $true}).Count){throw 'SCHEDULE_COLLECTOR_PROOF_MISSING'}
 }
 if($r.lastTaskResult -ne 0){throw 'SCHEDULE_TASK_NONZERO_RESULT'}
 $r.status='HEALTH_SCHEDULED_SIGNING_AND_CLOCK_PASSED_COLLECTOR_PENDING';$r.stage='COMPLETE'
 if($TokenReportPath){$r.status='HEALTH_SCHEDULED_CLOCK_AND_TOKEN_PASSED_COLLECTOR_PENDING'}
 if($CollectorDeploymentReport){$r.status='HEALTH_COLLECTOR_THREE_ROUNDS_PASSED_REVOKED_LIFECYCLE_PENDING'}
}catch{
 $r.failure=if($_.Exception.Message -cmatch '^(SCHEDULE|ACCOUNT|KEY|HEALTH_KEY|HEALTH_ACCOUNT)_[A-Z_]+$'){$_.Exception.Message}else{'SCHEDULE_SETUP_FAILED'}
 $e=$_.Exception.GetBaseException();$r.failureDetails=@{type=$e.GetType().Name;hresult=$e.HResult;line=$_.InvocationInfo.ScriptLineNumber}
}finally{
 if($mayExist){try{
  $tasks=@(Get-HealthProbeTask $c.name)
  if($tasks.Count -eq 1){
   Assert-HealthProbeTask $tasks[0] $run ([bool]$tasks[0].Settings.Enabled)
   $null=Disable-ScheduledTask -TaskName $c.name -TaskPath $c.path -ErrorAction Stop
   $tasks=@(Get-HealthProbeTask $c.name);Assert-HealthProbeTask $tasks[0] $run $false;$r.taskDisabled=$true
   if([string]$tasks[0].State -cin @('Running','Queued')){
    Stop-ScheduledTask -TaskName $c.name -TaskPath $c.path -ErrorAction Stop
    $stop=[Diagnostics.Stopwatch]::StartNew()
    do{$tasks=@(Get-HealthProbeTask $c.name);if([string]$tasks[0].State -cnotin @('Running','Queued')){break};Start-Sleep -Milliseconds 250}while($stop.Elapsed.TotalSeconds -lt 5)
    if([string]$tasks[0].State -cin @('Running','Queued')){throw 'SCHEDULE_STOP_NOT_CONFIRMED'}
   }
   if(-not $r.failure){Assert-HealthProbeTask $tasks[0] $run $false;Unregister-ScheduledTask -TaskName $c.name -TaskPath $c.path -Confirm:$false -ErrorAction Stop;if(@(Get-HealthProbeTask $c.name).Count){throw 'SCHEDULE_REMOVE_NOT_CONFIRMED'};$r.taskRemoved=$true}
  }elseif($r.taskRegistered){throw 'SCHEDULE_TASK_DISAPPEARED'}
 }catch{$r.cleanupFailure='SCHEDULE_CLEANUP_REVIEW_REQUIRED'}}
 if($r.taskStarted -and $null -eq $r.worker -and (Test-Path -LiteralPath $c.result)){try{$partial=Read-PaytmRepairJson $c.result 8192;if($partial.runId -ceq $run){$r.worker=$partial}}catch{}}
 if($null -ne $password){$password.Dispose()}
 if($r.failure -or $r.cleanupFailure){$r.status='REVIEW_REQUIRED'}
 Save-HealthScheduled;Write-Progress -Activity 'Scheduled clock access' -Completed
 Write-Host "[100%] $($r.status)";Write-Host "Share this ONE file: $path"
}
if($r.status -ceq 'REVIEW_REQUIRED'){throw 'Share the report. Do not rerun, delete tasks or reset account/key state.'}
