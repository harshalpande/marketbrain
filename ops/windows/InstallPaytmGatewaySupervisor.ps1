#Requires -Version 7.0
[CmdletBinding()]param(
 [string]$CustodyReportPath='C:\MarketBrainData\Review\paytm-key-custody-20261102-112446-29cb6394513a47f687351825698006d5.json',
 [string]$SigningReportPath='C:\MarketBrainData\Review\paytm-batch-logon-repair-20261102-135027-c3dec69b2f7c462fb383112ae388a596.json',
 [string]$OutputDirectory='C:\MarketBrainData\Review')
$ErrorActionPreference='Stop'
foreach($name in @('PaytmGatewayAccount.ps1','PaytmGatewayAccountRepair.ps1','PaytmGatewayKeyCustody.ps1','PaytmGatewayScheduledProbe.ps1','PaytmGatewayBatchLogon.ps1','PaytmTunnelVerification.ps1','PaytmSupervisorHost.ps1','PaytmSupervisorInstallation.ps1')){. (Join-Path $PSScriptRoot $name)}
$c=Get-PaytmHostContract;$watch=[Diagnostics.Stopwatch]::StartNew();$password=$null;$staged=$false;$mayRegister=$false;$installLease=$null
$report=[ordered]@{version=1;runId=[guid]::NewGuid().ToString('N');status='REVIEW_REQUIRED';stage='PREFLIGHT';sourceHashes=@{};
 failure=$null;failureDetails=$null;cleanupFailure=$null;prerequisites=$null;policy=$null;denyAssessment=@();acceptedProgress=@();
 taskRegistered=$false;startupConfigured=$false;duplicateStartPassed=$false;persistentStopPassed=$false;restartPassed=$false;
 first=$null;duplicate=$null;stopped=$null;stoppedRestart=$null;final=$null;failureWorker=$null;taskInfo=$null;
 elapsedSeconds=0;networkContacted=$false;keyImported=$false;policyChanged=$false;passwordChanged=$false;ordersEnabled=$false;
 rebootTested=$false;transportImplemented=$false;productionTransportActivated=$false}
$null=Assert-PaytmAccountPath $OutputDirectory;$null=New-Item -ItemType Directory -Path $OutputDirectory -Force
$path=Join-Path $OutputDirectory ('paytm-supervisor-install-'+(Get-Date -Format 'yyyyMMdd-HHmmss')+'-'+$report.runId+'.json')
function Save-HostInstall {
    $report.elapsedSeconds=[math]::Round($watch.Elapsed.TotalSeconds,3)
    # The install report can include embedded snapshots larger than the bounded worker heartbeat.
    $json=$report|ConvertTo-Json -Depth 12
    [IO.File]::WriteAllText($path,$json,[Text.UTF8Encoding]::new($false))
}
function Host-InstallStep([string]$Stage,[int]$Percent){$report.stage=$Stage;Save-HostInstall;Write-Host "[$Percent%] $Stage";Write-Progress -Activity 'Gateway supervisor installation' -Status $Stage -PercentComplete $Percent}
try {
    $f=[IO.File]::Open($path,'CreateNew','Write','Read');$f.Dispose();Save-HostInstall
    Assert-PaytmCustodyController;Import-Module ScheduledTasks -ErrorAction Stop;Import-Module Microsoft.PowerShell.LocalAccounts -ErrorAction Stop
    foreach($name in @('InstallPaytmGatewaySupervisor.ps1','PaytmSupervisorInstallation.ps1','PaytmSupervisorHost.ps1','RunPaytmGatewaySupervisor.ps1','PaytmSupervisorNative.cs','PaytmGatewayAccount.ps1','PaytmGatewayAccountRepair.ps1','PaytmGatewayKeyCustody.ps1','PaytmGatewayScheduledProbe.ps1','PaytmGatewayBatchLogon.ps1','PaytmTunnelVerification.ps1')){
        $report.sourceHashes[$name]=(Get-FileHash -LiteralPath (Join-Path $PSScriptRoot $name)).Hash
    }
    $report.acceptedProgress=@(Get-PaytmReadinessProgress)
    Host-InstallStep 'CHECK_ACCEPTED_ACCOUNT_AND_SIGNING' 10
    $null=Assert-PaytmAccountPath $SigningReportPath
    if((Get-FileHash -LiteralPath $SigningReportPath).Hash -cne '29555DF556ED576F618E28BF7478911D3A002DC74C5A336636C80CD321BCBE27'){throw 'HOST_SIGNING_RECEIPT_NOT_ACCEPTED'}
    $report.prerequisites=Assert-PaytmScheduledPrerequisites $CustodyReportPath
    $leasePath=Assert-PaytmAccountPath (Join-Path (Get-PaytmAccountContract).root 'supervisor-install.lock')
    try{$installLease=[IO.File]::Open($leasePath,'OpenOrCreate','ReadWrite','None')}catch{throw 'HOST_INSTALL_ALREADY_RUNNING'}
    $report.policy=Get-PaytmBatchPolicy;Assert-PaytmBatchPolicy $report.policy $report
    if((Get-PaytmKeyContract).accountSid -cnotin @($report.policy.allow)){throw 'HOST_BATCH_RIGHT_MISSING'}
    if((Get-Service Schedule).Status -ne 'Running'){throw 'HOST_SCHEDULER_NOT_RUNNING'}
    if(@(Get-PaytmProbeTask $c.name).Count){throw 'HOST_ALREADY_INSTALLED_REVIEW_EXISTING'}
    foreach($p in @($c.root,$c.work)){$null=Assert-PaytmAccountPath $p;if(Test-Path -LiteralPath $p){throw 'HOST_EXISTING_FILES_REVIEW_REQUIRED'}}
    # Build and validate native task definition before creating protected files or asking for a password.
    $task=New-PaytmHostTask $report.runId
    Assert-PaytmHostTask ([pscustomobject]@{TaskName=$c.name;TaskPath='\';Description=$task.Description;
        Principal=$task.Principal;Settings=$task.Settings;Actions=$task.Actions;Triggers=$task.Triggers}) $report.runId $false
    $password=Read-Host 'Existing WINDOWS password for marketbrain-gateway (not the SSH key passphrase)' -AsSecureString
    if($password.Length -eq 0){throw 'HOST_PASSWORD_REQUIRED'}
    Host-InstallStep 'INSTALL_PROTECTED_LOCKED_HOST' 35
    $staged=$true
    foreach($p in @($c.root,$c.work)){$null=New-Item -ItemType Directory -Path $p;Set-PaytmAccountDirectoryAcl $p (Get-PaytmKeyContract).accountSid -Writable:($p -ceq $c.work)}
    Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'PaytmSupervisorHost.ps1') -Destination (Join-Path $c.root 'host.ps1')
    Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'RunPaytmGatewaySupervisor.ps1') -Destination (Join-Path $c.root 'runner.ps1')
    Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'PaytmSupervisorNative.cs') -Destination (Join-Path $c.root 'native.cs')
    $compile="`$ErrorActionPreference='Stop'; Add-Type -Path '"+$c.root+"\native.cs' -OutputAssembly '"+$c.root+"\native.dll'"
    $encoded=[Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($compile))
    $result=Complete-TunnelProcess (Start-TunnelProcess $c.executable @('-NoLogo','-NoProfile','-NonInteractive','-EncodedCommand',$encoded)) 30
    if($result.StoppedByRunner -or $result.ExitCode -ne 0){throw 'HOST_NATIVE_COMPILE_FAILED'}
    $hashes=@{};foreach($name in @('host.ps1','runner.ps1','native.dll')){$hashes[$name]=(Get-FileHash -LiteralPath (Join-Path $c.root $name)).Hash}
    Write-PaytmHostJson (Join-Path $c.root 'manifest.json') @{version=1;installationId=$report.runId;hashes=$hashes}
    Set-PaytmHostControl $report.runId LOCKED
    Host-InstallStep 'REGISTER_STARTUP_TASK_DISABLED' 55
    $plain=$null
    try{
        $plain=[Net.NetworkCredential]::new('', $password).Password;$mayRegister=$true
        $null=Register-ScheduledTask -TaskName $c.name -TaskPath '\' -InputObject $task -User ($env:COMPUTERNAME+'\marketbrain-gateway') -Password $plain -ErrorAction Stop
    }finally{$plain=$null;$password.Dispose();$password=$null}
    $report.taskRegistered=$true
    $null=Get-PaytmOwnedHostTask $report.runId $false;$report.startupConfigured=$true
    Host-InstallStep 'VERIFY_HEARTBEAT_DUPLICATE_STOP_RESTART' 70
    Invoke-PaytmHostLifecycle $report.runId $report {Save-HostInstall}
    $report.status='LOCKED_SUPERVISOR_INSTALLED_TRANSPORT_PENDING';Host-InstallStep 'COMPLETE' 100
}catch{
    $report.failure=if($_.Exception.Message -cmatch '^(HOST|SCHEDULE|ACCOUNT|KEY)_[A-Z_]+$'){$_.Exception.Message}else{'HOST_INSTALL_FAILED'}
    $base=$_.Exception.GetBaseException();$report.failureDetails=@{type=$base.GetType().Name;hresult=$base.HResult;line=$_.InvocationInfo.ScriptLineNumber}
    # STOP first, then disable only our matching task. Preserve files and evidence; no blind reinstallation.
    try{
        if($staged -and (Test-Path -LiteralPath (Join-Path $c.root 'manifest.json'))){
            $ownedManifest=Read-PaytmHostJson (Join-Path $c.root 'manifest.json')
            if($ownedManifest.installationId -cne $report.runId){throw 'HOST_INSTALL_OWNERSHIP_DRIFT'}
            Set-PaytmHostControl $report.runId STOP
        }
        if($mayRegister){
            $tasks=@(Get-PaytmProbeTask $c.name)
            if($tasks.Count -eq 1){
                Assert-PaytmHostTask $tasks[0] $report.runId ([bool]$tasks[0].Settings.Enabled)
                $null=Disable-ScheduledTask -TaskName $c.name -TaskPath '\' -ErrorAction Stop
                Stop-ScheduledTask -TaskName $c.name -TaskPath '\' -ErrorAction Stop
                $info=Get-ScheduledTaskInfo -TaskName $c.name -TaskPath '\'
                $report.taskInfo=@{lastTaskResult=[long]$info.LastTaskResult}
            }
        }
        if(Test-Path -LiteralPath (Join-Path $c.work 'status.json')){$report.failureWorker=Read-PaytmHostJson (Join-Path $c.work 'status.json')}
    }catch{$report.cleanupFailure='HOST_CLEANUP_REVIEW_REQUIRED'}
}finally{
    if($password){$password.Dispose()};if($installLease){$installLease.Dispose()};Save-HostInstall
    Write-Progress -Activity 'Gateway supervisor installation' -Completed
    Write-Host "[100%] $($report.status); elapsed=$($report.elapsedSeconds)s"
    Write-Host "Share this ONE file: $path"
}
if($report.failure){throw 'Supervisor installation needs review. Share the JSON; do not delete the account or rerun installation.'}
