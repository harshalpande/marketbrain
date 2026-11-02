#Requires -Version 7.0
# Definitions only. Temporary demand-start task; never a gateway/tunnel launcher.
function Get-PaytmScheduledProbeContract([string]$RunId) {
    if($RunId -cnotmatch '^[a-f0-9]{32}$'){throw 'SCHEDULE_RUN_INVALID'}
    $base=(Get-PaytmAccountContract).root
    [pscustomobject]@{name=('MarketBrain-Gateway-Key-Probe-'+$RunId);path='\';
        directory=(Join-Path $base ('scheduled-probe-'+$RunId));
        result=(Join-Path $base ('work\scheduled-probe-'+$RunId+'.json'));
        executable='C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe';
        receiptHash='612A424BC90C02B08714A782FEFA48D97C588759EC92C332D116DB4E4EED2B4C';
        receiptRun='29cb6394513a47f687351825698006d5'}
}
function Assert-PaytmScheduledPrerequisites([string]$ReceiptPath) {
    $k=Get-PaytmKeyContract;$c=Get-PaytmScheduledProbeContract ('0'*32)
    $null=Assert-PaytmAccountPath $ReceiptPath
    if((Get-FileHash -LiteralPath $ReceiptPath).Hash -cne $c.receiptHash){throw 'SCHEDULE_CUSTODY_RECEIPT_NOT_ACCEPTED'}
    $receipt=Read-PaytmRepairJson $ReceiptPath 32768
    if($receipt.runId -cne $c.receiptRun -or $receipt.status -cne 'GATEWAY_KEY_CUSTODY_AND_AUTH_PASSED_LIFECYCLE_PENDING' -or $null -ne $receipt.failure){throw 'SCHEDULE_CUSTODY_RECEIPT_INVALID'}
    $saved=Read-PaytmOwnedAccount
    if($saved.sid -cne $k.accountSid -or $saved.runId -cne $k.accountRun -or -not (Get-LocalUser -SID $saved.sid).Enabled){throw 'SCHEDULE_ACCOUNT_DRIFT'}
    Assert-PaytmRepairAgent
    $null=Assert-PaytmAccountPath $k.root;Assert-PaytmAccountAcl (Get-Acl -LiteralPath $k.root) $k.accountSid
    if(Test-Path -LiteralPath (Join-Path $k.root 'gateway.openssh')){throw 'SCHEDULE_PRIVATE_STAGING_PRESENT'}
    $state=Read-PaytmRepairJson (Join-Path $k.root 'custody-state.json') 4096
    if($state.version -ne 1 -or $state.runId -cne $c.receiptRun -or $state.sid -cne $k.accountSid -or $state.fingerprint -cne $k.fingerprint -or $state.hostPin -cne $k.hostPin -or $state.privateFileRetained -ne $false){throw 'SCHEDULE_CUSTODY_STATE_DRIFT'}
    foreach($pair in @(@('library.ps1','PaytmGatewayKeyCustody.ps1'),@('native.ps1','PaytmTunnelVerification.ps1'))){
        $p=Assert-PaytmAccountPath (Join-Path $k.root $pair[0])
        if((Get-FileHash -LiteralPath $p).Hash -cne $receipt.sourceHashes.($pair[1])){throw 'SCHEDULE_CUSTODY_SOURCE_DRIFT'}
    }
    $pub=Assert-PaytmAccountPath (Join-Path $k.root 'gateway.pub')
    if((Get-Item -LiteralPath $pub).Length -gt 1024 -or [IO.File]::ReadAllText($pub).Trim() -cne ('ssh-ed25519 '+$k.publicBlob)){throw 'SCHEDULE_PUBLIC_IDENTITY_DRIFT'}
    [pscustomobject]@{sid=$saved.sid;custodyRun=$state.runId;fingerprint=$state.fingerprint}
}
function New-PaytmScheduledWorkerSource([string]$RunId) {
    $c=Get-PaytmScheduledProbeContract $RunId
    $template=@'
$ErrorActionPreference='Stop'
$root='__ROOT__'
. ([scriptblock]::Create([IO.File]::ReadAllText($root+'\library.ps1')))
. ([scriptblock]::Create([IO.File]::ReadAllText($root+'\native.ps1')))
$report=[ordered]@{version=1;runId='__RUN__';stage='IDENTITY';processId=$PID;sessionId=$null;
 identityVerified=$false;nonAdmin=$false;nonInteractiveSession=$false;privateCopyAbsent=$false;
 agentIdentityVerified=$false;signingChecks=0;failure=$null;elapsedSeconds=0;
 keyImported=$false;networkContacted=$false;ordersEnabled=$false}
$timer=[Diagnostics.Stopwatch]::StartNew()
try {
 $id=Get-PaytmCustodyIdentity
 if($id.sid -cne (Get-PaytmKeyContract).accountSid -or -not $id.nonAdmin){throw 'SCHEDULE_WORKER_IDENTITY'}
 $report.identityVerified=$true;$report.nonAdmin=$true
 $report.sessionId=(Get-Process -Id $PID).SessionId
 if($report.sessionId -ne 0){throw 'SCHEDULE_INTERACTIVE_SESSION'};$report.nonInteractiveSession=$true
 if([IO.File]::Exists($root+'\gateway.openssh')){throw 'SCHEDULE_PRIVATE_STAGING_PRESENT'};$report.privateCopyAbsent=$true
 $report.stage='AGENT'
 Assert-PaytmAgentResult (Invoke-PaytmCustodyNative 'ssh-add.exe' @('-l')) Expected;$report.agentIdentityVerified=$true
 $report.stage='SIGNING'
 foreach($attempt in 1..2){
  Assert-PaytmSigningResult (Invoke-PaytmCustodyNative 'ssh-add.exe' @('-T',($root+'\gateway.pub'))) $true
  $report.signingChecks++
 }
 $report.stage='COMPLETE'
}catch{
 $report.failure=if($_.Exception.Message -cmatch '^(SCHEDULE|KEY)_[A-Z_]+$'){$_.Exception.Message}else{'SCHEDULE_WORKER_FAILED'}
}finally{
 $timer.Stop();$report.elapsedSeconds=[math]::Round($timer.Elapsed.TotalSeconds,3)
 $data=[Text.Encoding]::UTF8.GetBytes(($report|ConvertTo-Json -Compress))
 $stream=[IO.File]::Open('__RESULT__','CreateNew','Write','Read')
 try{$stream.Write($data,0,$data.Length);$stream.Flush($true)}finally{$stream.Dispose()}
}
if($report.failure){throw $report.failure}
'@
    $template.Replace('__ROOT__',(Get-PaytmKeyContract).root.Replace("'","''")).Replace('__RUN__',$RunId).Replace('__RESULT__',$c.result.Replace("'","''"))
}
function Get-PaytmScheduledArguments([string]$RunId) {
    $c=Get-PaytmScheduledProbeContract $RunId
    $source="&([scriptblock]::Create([IO.File]::ReadAllText('"+(Join-Path $c.directory 'worker.ps1').Replace("'","''")+"')))"
    '-NoLogo -NoProfile -NonInteractive -EncodedCommand '+[Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($source))
}
function Get-PaytmProbeTask([string]$Name) {
    # Enumeration errors must not be treated as absence. Never overwrite an existing task.
    @(Get-ScheduledTask -ErrorAction Stop | Where-Object {$_.TaskPath -ceq '\' -and $_.TaskName -ceq $Name})
}
function Assert-PaytmProbeTask($Task,[string]$RunId,[bool]$Enabled) {
    $c=Get-PaytmScheduledProbeContract $RunId;$k=Get-PaytmKeyContract
    if($Task.TaskName -cne $c.name -or $Task.TaskPath -cne $c.path -or $Task.Description -cne ('MarketBrain temporary signing probe '+$RunId)){throw 'SCHEDULE_TASK_OWNERSHIP_DRIFT'}
    $principal=$Task.Principal.UserId
    if($principal -cne $k.accountSid){
        try{$principal=([Security.Principal.NTAccount]::new($principal)).Translate([Security.Principal.SecurityIdentifier]).Value}catch{throw 'SCHEDULE_TASK_PRINCIPAL_DRIFT'}
    }
    if($principal -cne $k.accountSid -or [string]$Task.Principal.LogonType -cne 'Password' -or [string]$Task.Principal.RunLevel -cne 'Limited'){throw 'SCHEDULE_TASK_PRINCIPAL_DRIFT'}
    $actions=@($Task.Actions);$triggers=@($Task.Triggers|Where-Object {$null -ne $_})
    if($actions.Count -ne 1 -or $triggers.Count -ne 0 -or $actions[0].Execute -cne $c.executable -or
        $actions[0].Arguments -cne (Get-PaytmScheduledArguments $RunId) -or $actions[0].WorkingDirectory -cne $c.directory){throw 'SCHEDULE_TASK_ACTION_DRIFT'}
    $s=$Task.Settings
    if($s.Enabled -ne $Enabled -or [string]$s.MultipleInstances -cne 'IgnoreNew' -or $s.RestartCount -ne 0 -or
        -not $s.AllowDemandStart -or -not $s.AllowHardTerminate -or $s.WakeToRun -or $s.StartWhenAvailable -or $s.RunOnlyIfNetworkAvailable -or $s.RunOnlyIfIdle -or
        $s.DisallowStartIfOnBatteries -or $s.StopIfGoingOnBatteries -or [Xml.XmlConvert]::ToTimeSpan($s.ExecutionTimeLimit).TotalSeconds -ne 120){throw 'SCHEDULE_TASK_SETTINGS_DRIFT'}
}
function Get-PaytmProbeTaskShape($Task,[string]$RunId) {
    $c=Get-PaytmScheduledProbeContract $RunId;$actions=@($Task.Actions)
    $settings=[ordered]@{}
    foreach($name in @('Enabled','MultipleInstances','RestartCount','AllowDemandStart','AllowHardTerminate','WakeToRun','StartWhenAvailable','RunOnlyIfNetworkAvailable','RunOnlyIfIdle','DisallowStartIfOnBatteries','StopIfGoingOnBatteries','ExecutionTimeLimit')){
        $text=[string]$Task.Settings.$name
        $settings[$name]=if($text -cmatch '^[A-Za-z0-9:.\-]{0,40}$'){$text}else{'UNEXPECTED_VALUE'}
    }
    [pscustomobject]@{actionCount=$actions.Count;triggerCount=@($Task.Triggers|Where-Object {$null -ne $_}).Count;
        logonType=[string]$Task.Principal.LogonType;runLevel=[string]$Task.Principal.RunLevel;
        executableMatches=($actions.Count -eq 1 -and $actions[0].Execute -ceq $c.executable);
        argumentsMatch=($actions.Count -eq 1 -and $actions[0].Arguments -ceq (Get-PaytmScheduledArguments $RunId));
        workingDirectoryMatches=($actions.Count -eq 1 -and $actions[0].WorkingDirectory -ceq $c.directory);settings=$settings}
}
function Register-PaytmProbeTask([string]$RunId,[Security.SecureString]$Password) {
    $c=Get-PaytmScheduledProbeContract $RunId;$plain=$null
    $action=New-ScheduledTaskAction -Execute $c.executable -Argument (Get-PaytmScheduledArguments $RunId) -WorkingDirectory $c.directory
    $principal=New-ScheduledTaskPrincipal -UserId (Get-PaytmKeyContract).accountSid -LogonType Password -RunLevel Limited
    $settings=New-ScheduledTaskSettingsSet -Disable -MultipleInstances IgnoreNew -ExecutionTimeLimit ([TimeSpan]::FromSeconds(120)) -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries
    $task=New-ScheduledTask -Action $action -Principal $principal -Settings $settings -Description ('MarketBrain temporary signing probe '+$RunId)
    try {
        # The Windows API requires a string here. Never put it in argv, files or reports.
        $plain=[Net.NetworkCredential]::new('', $Password).Password
        $null=Register-ScheduledTask -TaskName $c.name -TaskPath $c.path -InputObject $task -User ($env:COMPUTERNAME+'\marketbrain-gateway') -Password $plain -ErrorAction Stop
    }finally{$plain=$null}
}
function Wait-PaytmProbeTask([string]$RunId,$Report,[scriptblock]$Checkpoint) {
    $c=Get-PaytmScheduledProbeContract $RunId;$clock=[Diagnostics.Stopwatch]::StartNew()
    do {
        $tasks=@(Get-PaytmProbeTask $c.name);if($tasks.Count -ne 1){throw 'SCHEDULE_TASK_MISSING'}
        Assert-PaytmProbeTask $tasks[0] $RunId $true
        $info=Get-ScheduledTaskInfo -TaskName $c.name -TaskPath $c.path -ErrorAction Stop
        $Report.lastTaskResult=[long]$info.LastTaskResult;$Report.taskState=[string]$tasks[0].State
        if(Test-Path -LiteralPath $c.result){
            $Report.worker=Read-PaytmRepairJson $c.result 8192
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
function Assert-PaytmScheduledWorker($Worker,[string]$RunId) {
    if($Worker.version -ne 1 -or $Worker.runId -cne $RunId -or $Worker.stage -cne 'COMPLETE' -or $null -ne $Worker.failure -or $Worker.signingChecks -ne 2){throw 'SCHEDULE_WORKER_NOT_PASSED'}
    foreach($field in @('identityVerified','nonAdmin','nonInteractiveSession','privateCopyAbsent','agentIdentityVerified')){
        if($Worker.$field -isnot [bool] -or -not $Worker.$field){throw 'SCHEDULE_WORKER_PROOF_MISSING'}
    }
    if($Worker.sessionId -ne 0 -or $Worker.processId -le 0 -or $Worker.keyImported -ne $false -or $Worker.networkContacted -ne $false -or $Worker.ordersEnabled -ne $false){throw 'SCHEDULE_WORKER_SCOPE'}
}
