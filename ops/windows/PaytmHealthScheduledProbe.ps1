#Requires -Version 7.0
# Definitions only. Temporary demand-start task; never a gateway/tunnel launcher.
function Get-HealthScheduledProbeContract([string]$RunId) {
    if($RunId -cnotmatch '^[a-f0-9]{32}$'){throw 'SCHEDULE_RUN_INVALID'}
    $base=(Get-PaytmHealthAccountContract).root
    [pscustomobject]@{name=('MarketBrain-Health-Clock-Probe-'+$RunId);path='\';
        directory=(Join-Path $base ('scheduled-probe-'+$RunId));
        result=(Join-Path $base ('work\scheduled-probe-'+$RunId+'.json'));
        executable='C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe';
        receiptHash='87F19AAD6973C920748EB38C1CC076E9685F2679A9255230A665B113BA515BA6';
        receiptRun='d5e799ea1ba84d438008f64c13e41571'}
}
function Assert-HealthScheduledPrerequisites([string]$ReceiptPath) {
    $k=Get-HealthScheduledKeyContract;$c=Get-HealthScheduledProbeContract ('0'*32)
    $null=Assert-PaytmAccountPath $ReceiptPath
    if((Get-FileHash -LiteralPath $ReceiptPath).Hash -cne $c.receiptHash){throw 'SCHEDULE_CUSTODY_RECEIPT_NOT_ACCEPTED'}
    $receipt=Read-PaytmRepairJson $ReceiptPath 32768
    if($receipt.runId -cne $c.receiptRun -or $receipt.status -cne 'HEALTH_KEY_CUSTODY_PASSED_SCHEDULED_ACCESS_PENDING' -or $null -ne $receipt.failure){throw 'SCHEDULE_CUSTODY_RECEIPT_INVALID'}
    $saved=Read-PaytmHealthAccount
    if($saved.sid -cne $k.accountSid -or $saved.runId -cne $k.accountRun -or -not (Get-LocalUser -SID $saved.sid).Enabled){throw 'SCHEDULE_ACCOUNT_DRIFT'}
    Assert-HealthScheduleAgent
    $null=Assert-PaytmAccountPath $k.root;Assert-PaytmAccountAcl (Get-Acl -LiteralPath $k.root) $k.accountSid
    if(Test-Path -LiteralPath (Join-Path $k.root 'clock.openssh')){throw 'SCHEDULE_PRIVATE_STAGING_PRESENT'}
    $state=Read-PaytmRepairJson (Join-Path $k.root 'custody-state.json') 4096
    if($state.version -ne 1 -or $state.runId -cne $c.receiptRun -or $state.sid -cne $k.accountSid -or $state.fingerprint -cne $k.fingerprint -or $state.privateFileRetained -ne $false){throw 'SCHEDULE_CUSTODY_STATE_DRIFT'}
    foreach($pair in @(@('parser.ps1','PaytmGatewayKeyCustody.ps1'),@('native.ps1','PaytmTunnelVerification.ps1'),@('health.ps1','PaytmHealthKeyCustody.ps1'))){
        $p=Assert-PaytmAccountPath (Join-Path $k.root $pair[0])
        if((Get-FileHash -LiteralPath $p).Hash -cne $receipt.sourceHashes.($pair[1])){throw 'SCHEDULE_CUSTODY_SOURCE_DRIFT'}
    }
    $pub=Assert-PaytmAccountPath (Join-Path $k.root 'clock.pub')
    if((Get-Item -LiteralPath $pub).Length -gt 1024 -or [IO.File]::ReadAllText($pub).Trim() -cne ('ssh-ed25519 '+$k.publicBlob)){throw 'SCHEDULE_PUBLIC_IDENTITY_DRIFT'}
    [pscustomobject]@{sid=$saved.sid;custodyRun=$state.runId;fingerprint=$state.fingerprint}
}
function New-HealthScheduledWorkerSource([string]$RunId,[switch]$WithToken,[switch]$WithCollector) {
 $c=Get-HealthScheduledProbeContract $RunId
 $source=[IO.File]::ReadAllText((Join-Path $PSScriptRoot 'PaytmHealthScheduledWorker.ps1'))
 $tokenCode=if($WithToken){Get-HealthScheduledTokenSource}else{''}
 if($WithCollector){
  if(-not $WithToken){throw 'SCHEDULE_COLLECTOR_TOKEN_REQUIRED'}
  foreach($n in @('PaytmTimeServiceRepair.ps1','PaytmLiveHealthCollector.ps1','PaytmTimeObservation.ps1','PaytmHealthCollectorCore.ps1')){$tokenCode+="`r`n"+[IO.File]::ReadAllText((Join-Path $PSScriptRoot $n))}
  $tokenCode+=@'

 $r.stage='COLLECTOR';$r['collectorRounds']=@();$r['finalHealthRevoked']=$false;$r.applicationLocked=$false;$token=$null
 try{
  $token=Unprotect-HealthToken ([IO.File]::ReadAllBytes($tokenRoot+'\health-token.dpapi'))
  try{
   foreach($iteration in 1..3){$r.collectorRounds+=,(Invoke-CollectorCycle $token $a $r.applicationBootId);if($iteration -lt 3){Start-Sleep -Seconds 1}}
  }finally{
   $revocation=Invoke-CollectorCycle $token $a $r.applicationBootId -Revoke
   $r.finalHealthRevoked=$revocation.revoked;$r.applicationLocked=$revocation.revoked
  }
  if(-not $r.finalHealthRevoked -or $r.collectorRounds.Count -ne 3 -or @($r.collectorRounds|Where-Object {-not $_.accepted}).Count){throw 'SCHEDULE_COLLECTOR_NOT_ACCEPTED'}
 }finally{$token=$null}
'@
 }
 $source.Replace('__RUN__',$RunId).Replace('__RESULT__',$c.result).Replace('__KNOWN__',((Join-Path $c.directory 'known_hosts').Replace('\','/'))).Replace('__TOKEN_CHECK__',$tokenCode)
}
function Get-HealthScheduledArguments([string]$RunId) {
    $c=Get-HealthScheduledProbeContract $RunId
    $source="&([scriptblock]::Create([IO.File]::ReadAllText('"+(Join-Path $c.directory 'worker.ps1').Replace("'","''")+"')))"
    '-NoLogo -NoProfile -NonInteractive -EncodedCommand '+[Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($source))
}
function Get-HealthProbeTask([string]$Name) {
    # Enumeration errors must not be treated as absence. Never overwrite an existing task.
    @(Get-ScheduledTask -ErrorAction Stop | Where-Object {$_.TaskPath -ceq '\' -and $_.TaskName -ceq $Name})
}
function Assert-HealthProbeTask($Task,[string]$RunId,[bool]$Enabled) {
    $c=Get-HealthScheduledProbeContract $RunId;$k=Get-HealthScheduledKeyContract
    if($Task.TaskName -cne $c.name -or $Task.TaskPath -cne $c.path -or $Task.Description -cne ('MarketBrain temporary health clock probe '+$RunId)){throw 'SCHEDULE_TASK_OWNERSHIP_DRIFT'}
    $principal=$Task.Principal.UserId
    if($principal -cne $k.accountSid){
        try{$principal=([Security.Principal.NTAccount]::new($principal)).Translate([Security.Principal.SecurityIdentifier]).Value}catch{throw 'SCHEDULE_TASK_PRINCIPAL_DRIFT'}
    }
    if($principal -cne $k.accountSid -or [string]$Task.Principal.LogonType -cne 'Password' -or [string]$Task.Principal.RunLevel -cne 'Limited'){throw 'SCHEDULE_TASK_PRINCIPAL_DRIFT'}
    $actions=@($Task.Actions);$triggers=@($Task.Triggers|Where-Object {$null -ne $_})
    if($actions.Count -ne 1 -or $triggers.Count -ne 0 -or $actions[0].Execute -cne $c.executable -or
        $actions[0].Arguments -cne (Get-HealthScheduledArguments $RunId) -or $actions[0].WorkingDirectory -cne $c.directory){throw 'SCHEDULE_TASK_ACTION_DRIFT'}
    $s=$Task.Settings
    if($s.Enabled -ne $Enabled -or [string]$s.MultipleInstances -cne 'IgnoreNew' -or $s.RestartCount -ne 0 -or
        -not $s.AllowDemandStart -or -not $s.AllowHardTerminate -or $s.WakeToRun -or $s.StartWhenAvailable -or $s.RunOnlyIfNetworkAvailable -or $s.RunOnlyIfIdle -or
        $s.DisallowStartIfOnBatteries -or $s.StopIfGoingOnBatteries -or [Xml.XmlConvert]::ToTimeSpan($s.ExecutionTimeLimit).TotalSeconds -ne 120){throw 'SCHEDULE_TASK_SETTINGS_DRIFT'}
}
function Get-HealthProbeTaskShape($Task,[string]$RunId) {
    $c=Get-HealthScheduledProbeContract $RunId;$actions=@($Task.Actions)
    $settings=[ordered]@{}
    foreach($name in @('Enabled','MultipleInstances','RestartCount','AllowDemandStart','AllowHardTerminate','WakeToRun','StartWhenAvailable','RunOnlyIfNetworkAvailable','RunOnlyIfIdle','DisallowStartIfOnBatteries','StopIfGoingOnBatteries','ExecutionTimeLimit')){
        $text=[string]$Task.Settings.$name
        $settings[$name]=if($text -cmatch '^[A-Za-z0-9:.\-]{0,40}$'){$text}else{'UNEXPECTED_VALUE'}
    }
    [pscustomobject]@{actionCount=$actions.Count;triggerCount=@($Task.Triggers|Where-Object {$null -ne $_}).Count;
        logonType=[string]$Task.Principal.LogonType;runLevel=[string]$Task.Principal.RunLevel;
        executableMatches=($actions.Count -eq 1 -and $actions[0].Execute -ceq $c.executable);
        argumentsMatch=($actions.Count -eq 1 -and $actions[0].Arguments -ceq (Get-HealthScheduledArguments $RunId));
        workingDirectoryMatches=($actions.Count -eq 1 -and $actions[0].WorkingDirectory -ceq $c.directory);settings=$settings}
}
function Register-HealthProbeTask([string]$RunId,[Security.SecureString]$Password) {
    $c=Get-HealthScheduledProbeContract $RunId;$plain=$null
    $action=New-ScheduledTaskAction -Execute $c.executable -Argument (Get-HealthScheduledArguments $RunId) -WorkingDirectory $c.directory
    $principal=New-ScheduledTaskPrincipal -UserId (Get-HealthScheduledKeyContract).accountSid -LogonType Password -RunLevel Limited
    $settings=New-ScheduledTaskSettingsSet -Disable -MultipleInstances IgnoreNew -ExecutionTimeLimit ([TimeSpan]::FromSeconds(120)) -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries
    $task=New-ScheduledTask -Action $action -Principal $principal -Settings $settings -Description ('MarketBrain temporary health clock probe '+$RunId)
    try {
        # The Windows API requires a string here. Never put it in argv, files or reports.
        $plain=[Net.NetworkCredential]::new('', $Password).Password
        $null=Register-ScheduledTask -TaskName $c.name -TaskPath $c.path -InputObject $task -User ($env:COMPUTERNAME+'\marketbrain-health') -Password $plain -ErrorAction Stop
    }finally{$plain=$null}
}
function Wait-HealthProbeTask([string]$RunId,$Report,[scriptblock]$Checkpoint) {
    $c=Get-HealthScheduledProbeContract $RunId;$clock=[Diagnostics.Stopwatch]::StartNew()
    do {
        $tasks=@(Get-HealthProbeTask $c.name);if($tasks.Count -ne 1){throw 'SCHEDULE_TASK_MISSING'}
        Assert-HealthProbeTask $tasks[0] $RunId $true
        $info=Get-ScheduledTaskInfo -TaskName $c.name -TaskPath $c.path -ErrorAction Stop
        $Report.lastTaskResult=[long]$info.LastTaskResult;$Report.taskState=[string]$tasks[0].State
        if(Test-Path -LiteralPath $c.result){
            $limit=if($Report.Contains('collectorMode') -and $Report.collectorMode){49152}else{8192}
            $Report.worker=Read-PaytmRepairJson $c.result $limit
            if($Report.worker.runId -cne $RunId){throw 'SCHEDULE_WORKER_BINDING'}
            if($Report.taskState -cnotin @('Running','Queued')){return}
        }elseif($Report.taskState -cnotin @('Running','Queued') -and $Report.lastTaskResult -notin @(0,267011,267009)){
            throw 'SCHEDULE_TASK_EXECUTION_FAILED'
        }
        Write-Progress -Activity 'Scheduled gateway signing' -Status ('Waiting for background task: {0:n0}s / 90s' -f $clock.Elapsed.TotalSeconds) -PercentComplete 70
        &$Checkpoint;Start-Sleep -Milliseconds 500
    }while($clock.Elapsed.TotalSeconds -lt 90)
    throw 'SCHEDULE_TASK_TIMEOUT'
}
function Assert-HealthScheduledWorker($Worker,[string]$RunId) {
    if($Worker.version -ne 1 -or $Worker.runId -cne $RunId -or $Worker.stage -cne 'COMPLETE' -or $null -ne $Worker.failure -or $Worker.signingChecks -ne 2 -or $Worker.clockVerified -ne $true){throw 'SCHEDULE_WORKER_NOT_PASSED'}
    foreach($field in @('identityVerified','nonAdmin','nonInteractiveSession','privateCopyAbsent','agentIdentityVerified')){
        if($Worker.$field -isnot [bool] -or -not $Worker.$field){throw 'SCHEDULE_WORKER_PROOF_MISSING'}
    }
    if($Worker.sessionId -ne 0 -or $Worker.processId -le 0 -or $Worker.keyImported -ne $false -or $Worker.networkContacted -ne $true -or $Worker.ordersEnabled -ne $false){throw 'SCHEDULE_WORKER_SCOPE'}
}

function Get-HealthScheduledKeyContract {
 $k=Get-HealthKeyContract
 [pscustomobject]@{root=$k.root;accountSid=$k.sid;accountRun=$k.accountRun;publicBlob=$k.blob;fingerprint=$k.fingerprint}
}
function Assert-HealthScheduleAgent {
 $a=Get-Service ssh-agent -ErrorAction Stop
 if($a.Status -ne 'Running' -or $a.StartType -ne 'Automatic'){throw 'SCHEDULE_AGENT_NOT_READY'}
}
