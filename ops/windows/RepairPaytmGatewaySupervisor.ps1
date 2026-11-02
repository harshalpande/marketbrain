#Requires -Version 7.0
[CmdletBinding()]param(
 [string]$FailedReportPath='C:\MarketBrainData\Review\paytm-supervisor-install-20261102-153600-ea8b91471cf048aa97a0f6b939b355c7.json',
 [string]$CustodyReportPath='C:\MarketBrainData\Review\paytm-key-custody-20261102-112446-29cb6394513a47f687351825698006d5.json',
 [string]$OutputDirectory='C:\MarketBrainData\Review')
$ErrorActionPreference='Stop'
foreach($name in @('PaytmGatewayAccount.ps1','PaytmGatewayAccountRepair.ps1','PaytmGatewayKeyCustody.ps1','PaytmGatewayScheduledProbe.ps1','PaytmGatewayBatchLogon.ps1','PaytmSupervisorHost.ps1','PaytmSupervisorInstallation.ps1','PaytmSupervisorRecovery.ps1')){. (Join-Path $PSScriptRoot $name)}
$c=Get-PaytmHostContract;$clock=[Diagnostics.Stopwatch]::StartNew();$lease=$null;$workerLease=$null;$owned=$false
$report=[ordered]@{version=1;runId=[guid]::NewGuid().ToString('N');installationId='ea8b91471cf048aa97a0f6b939b355c7';
 status='REVIEW_REQUIRED';stage='PREFLIGHT';failure=$null;failureDetails=$null;cleanupFailure=$null;sourceHashes=@{};
 backupCreated=$false;runnerUpdated=$false;manifestUpdated=$false;oldRunnerHash=$null;newRunnerHash=$null;
 duplicateStartPassed=$false;persistentStopPassed=$false;restartPassed=$false;first=$null;duplicate=$null;stopped=$null;stoppedRestart=$null;final=$null;
 startupFailure=$null;failureWorker=$null;taskInfo=$null;acceptedProgress=@();denyAssessment=@();elapsedSeconds=0;
 taskReRegistered=$false;passwordChanged=$false;policyChanged=$false;keyImported=$false;networkContacted=$false;ordersEnabled=$false}
$null=Assert-PaytmAccountPath $OutputDirectory;$null=New-Item -ItemType Directory -Path $OutputDirectory -Force
$path=Join-Path $OutputDirectory ('paytm-supervisor-recovery-'+(Get-Date -Format 'yyyyMMdd-HHmmss')+'-'+$report.runId+'.json')
function Save-SupervisorRecovery {
    $report.elapsedSeconds=[math]::Round($clock.Elapsed.TotalSeconds,3)
    [IO.File]::WriteAllText($path,($report|ConvertTo-Json -Depth 12),[Text.UTF8Encoding]::new($false))
}
function Recovery-Step([string]$Stage,[int]$Percent){$report.stage=$Stage;Save-SupervisorRecovery;Write-Host "[$Percent%] $Stage";Write-Progress -Activity 'Supervisor startup recovery' -Status $Stage -PercentComplete $Percent}
try {
    $f=[IO.File]::Open($path,'CreateNew','Write','Read');$f.Dispose()
    Assert-PaytmCustodyController;Import-Module ScheduledTasks -ErrorAction Stop;Import-Module Microsoft.PowerShell.LocalAccounts -ErrorAction Stop
    foreach($name in @('RepairPaytmGatewaySupervisor.ps1','PaytmSupervisorRecovery.ps1','RunPaytmGatewaySupervisor.ps1','PaytmSupervisorHost.ps1','PaytmSupervisorInstallation.ps1','PaytmGatewayAccount.ps1','PaytmGatewayAccountRepair.ps1','PaytmGatewayKeyCustody.ps1','PaytmGatewayScheduledProbe.ps1','PaytmGatewayBatchLogon.ps1')){
        $report.sourceHashes[$name]=(Get-FileHash -LiteralPath (Join-Path $PSScriptRoot $name)).Hash
    }
    $report.acceptedProgress=@(Get-PaytmReadinessProgress)
    Recovery-Step 'REVALIDATE_RETAINED_INSTALLATION' 10
    $receipt=Assert-PaytmSupervisorFailureReceipt $FailedReportPath
    $null=Assert-PaytmScheduledPrerequisites $CustodyReportPath
    $leasePath=Assert-PaytmAccountPath (Join-Path (Get-PaytmAccountContract).root 'supervisor-install.lock')
    try{$lease=[IO.File]::Open($leasePath,'OpenOrCreate','ReadWrite','None')}catch{throw 'HOST_INSTALL_ALREADY_RUNNING'}
    $policy=Get-PaytmBatchPolicy;Assert-PaytmBatchPolicy $policy $report
    if((Get-PaytmKeyContract).accountSid -cnotin @($policy.allow)){throw 'HOST_BATCH_RIGHT_MISSING'}
    $manifest=Assert-PaytmRecoverableHost $receipt
    $workerLeasePath=Assert-PaytmAccountPath (Join-Path $c.work 'instance.lock')
    try{$workerLease=[IO.File]::Open($workerLeasePath,'OpenOrCreate','ReadWrite','None')}catch{throw 'HOST_RECOVERY_WORKER_STILL_RUNNING'}
    $owned=$true
    Recovery-Step 'BACK_UP_AND_UPDATE_RUNNER_ONLY' 35
    Update-PaytmReviewedRunner $manifest $report.runId $PSScriptRoot $report
    $null=Get-PaytmOwnedHostTask $report.installationId $false
    Set-PaytmHostControl $report.installationId LOCKED
    $workerLease.Dispose();$workerLease=$null
    Recovery-Step 'VERIFY_HEARTBEAT_DUPLICATE_STOP_RESTART' 65
    Invoke-PaytmHostLifecycle $report.installationId $report {Save-SupervisorRecovery}
    $report.status='LOCKED_SUPERVISOR_RECOVERY_PASSED_TRANSPORT_PENDING';Recovery-Step 'COMPLETE' 100
}catch{
    $report.failure=if($_.Exception.Message -cmatch '^(HOST|SCHEDULE|ACCOUNT|KEY)_[A-Z_]+$'){$_.Exception.Message}else{'HOST_RECOVERY_FAILED'}
    $base=$_.Exception.GetBaseException();$report.failureDetails=@{type=$base.GetType().Name;hresult=$base.HResult;line=$_.InvocationInfo.ScriptLineNumber}
    if($owned){
        try{
            Set-PaytmHostControl $report.installationId STOP
            $tasks=@(Get-PaytmProbeTask $c.name)
            if($tasks.Count -ne 1){throw 'HOST_TASK_MISSING'}
            Assert-PaytmHostTask $tasks[0] $report.installationId ([bool]$tasks[0].Settings.Enabled)
            $null=Disable-ScheduledTask -TaskName $c.name -TaskPath '\' -ErrorAction Stop
            Stop-ScheduledTask -TaskName $c.name -TaskPath '\' -ErrorAction Stop
            $info=Get-ScheduledTaskInfo -TaskName $c.name -TaskPath '\'
            $report.taskInfo=@{lastTaskResult=[long]$info.LastTaskResult}
        }catch{$report.cleanupFailure='HOST_RECOVERY_CLEANUP_REVIEW_REQUIRED'}
    }
}finally{
    if($workerLease){$workerLease.Dispose()};if($lease){$lease.Dispose()}
    foreach($pair in @(@('startupFailure','startup-failure.json'),@('failureWorker','status.json'))){
        try{if(Test-Path -LiteralPath (Join-Path $c.work $pair[1])){$report[$pair[0]]=Read-PaytmHostJson (Join-Path $c.work $pair[1])}}catch{$report.cleanupFailure='HOST_RECOVERY_EVIDENCE_READ_FAILED'}
    }
    Save-SupervisorRecovery;Write-Progress -Activity 'Supervisor startup recovery' -Completed
    Write-Host "[100%] $($report.status); elapsed=$($report.elapsedSeconds)s"
    Write-Host "Share this ONE file: $path"
}
if($report.failure){throw 'Supervisor recovery needs review; share the JSON. Do not delete the account or reinstall.'}
