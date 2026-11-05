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
 agentIdentityVerified=$false;signingChecks=0;failure=$null;elapsedSeconds=0;nativeObservations=@();
 keyImported=$false;networkContacted=$false;ordersEnabled=$false}
$timer=[Diagnostics.Stopwatch]::StartNew()
function Invoke-ObservedAgent([string]$Operation,[string[]]$Arguments){
 $clock=[Diagnostics.Stopwatch]::StartNew()
 $o=[ordered]@{operation=$Operation;limitSeconds=10;elapsedSeconds=0;exitCode=$null;timedOut=$null;stdoutCharacters=0;stderrCharacters=0;classification='NATIVE_EXCEPTION';errorType=$null;nativeErrorCode=$null}
 try{
  $result=Invoke-PaytmCustodyNative 'ssh-add.exe' $Arguments 10
  $o.exitCode=$result.ExitCode;$o.timedOut=[bool]$result.StoppedByRunner
  $o.stdoutCharacters=([string]$result.Stdout).Length;$o.stderrCharacters=([string]$result.Stderr).Length
  $text=([string]$result.Stdout+[string]$result.Stderr).Trim()
  $o.classification=if($o.timedOut){'TIMEOUT'}elseif($result.ExitCode -eq 1 -and $text -ceq 'The agent has no identities.'){'NO_IDENTITIES'}elseif($text -match 'Error connecting to agent|Could not open a connection to your authentication agent'){'AGENT_CONNECTION_ERROR'}elseif($result.ExitCode -ne 0){'NONZERO_EXIT'}else{'EXIT_ZERO'}
  $result
 }catch{
  $base=$_.Exception.GetBaseException();$o.errorType=$base.GetType().Name
  if($base -is [ComponentModel.Win32Exception]){$o.nativeErrorCode=$base.NativeErrorCode}
  throw
 }finally{
  $o.elapsedSeconds=[math]::Round($clock.Elapsed.TotalSeconds,3);$report.nativeObservations+=@([pscustomobject]$o)
 }
}
try {
 $id=Get-PaytmCustodyIdentity
 if($id.sid -cne (Get-PaytmKeyContract).accountSid -or -not $id.nonAdmin){throw 'SCHEDULE_WORKER_IDENTITY'}
 $report.identityVerified=$true;$report.nonAdmin=$true
 $report.sessionId=(Get-Process -Id $PID).SessionId
 if($report.sessionId -ne 0){throw 'SCHEDULE_INTERACTIVE_SESSION'};$report.nonInteractiveSession=$true
 if([IO.File]::Exists($root+'\gateway.openssh')){throw 'SCHEDULE_PRIVATE_STAGING_PRESENT'};$report.privateCopyAbsent=$true
 $report.stage='AGENT'
 Assert-PaytmAgentResult (Invoke-ObservedAgent 'LIST_IDENTITIES' @('-l')) Expected;$report.agentIdentityVerified=$true
 $report.stage='SIGNING'
 foreach($attempt in 1..2){
  Assert-PaytmSigningResult (Invoke-ObservedAgent ('SIGN_'+$attempt) @('-T',($root+'\gateway.pub'))) $true
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
function Get-PaytmSafeProbeSummary($Value) {
    # Whitelist known diagnostic fields; never copy a prior report's arbitrary strings/arguments.
    $result=[ordered]@{}
    foreach($name in @('runId','status','stage','failure','cleanupFailure','taskState')){
        $text=[string]$Value.$name
        $result[$name]=if($text -cmatch '^[A-Za-z0-9_]{1,120}$'){$text}elseif(-not $text){$null}else{'UNEXPECTED_VALUE'}
    }
    foreach($name in @('taskRegistered','taskStarted','taskDisabled','taskRemoved','identityVerified','nonAdmin','nonInteractiveSession','privateCopyAbsent','agentIdentityVerified','stagingCreated','keyImported','agentChanged','networkContacted','ordersEnabled')){
        if($null -ne $Value.$name){$result[$name]=if($Value.$name -is [bool]){$Value.$name}else{$null}}
    }
    foreach($name in @('elapsedSeconds','lastTaskResult','signingChecks','sessionId','processId')){
        $number=0D
        if($null -ne $Value.$name -and [decimal]::TryParse([string]$Value.$name,[ref]$number)){$result[$name]=$number}
    }
    if($null -ne $Value.failureDetails){
        $type=[string]$Value.failureDetails.type;$code=0L;$line=0
        $result.failureDetails=[pscustomobject]@{
            type=if($type -cmatch '^[A-Za-z0-9_.]{1,160}$'){$type}else{'UNEXPECTED_TYPE'};
            hresult=if([long]::TryParse([string]$Value.failureDetails.hresult,[ref]$code)){$code}else{$null};
            line=if([int]::TryParse([string]$Value.failureDetails.line,[ref]$line)){$line}else{$null}}
    }
    [pscustomobject]$result
}
function Get-PaytmExistingProbeEvidence([object[]]$Tasks,[string]$ReviewDirectory) {
    if($Tasks.Count -gt 20){throw 'SCHEDULE_TOO_MANY_EXISTING_PROBES'}
    $directory=Assert-PaytmAccountPath $ReviewDirectory
    foreach($task in $Tasks){
        $item=[ordered]@{taskName=$null;runId=$null;state=$null;definition=$null;definitionMatches=$false;
            definitionFailure=$null;lastTaskResult=$null;taskInfoFailure=$null;workerFilePresent=$false;
            workerHash=$null;workerMatchesCurrentSource=$false;workerSourceFailure=$null;
            workerResult=$null;workerResultFailure=$null;previousReport=$null;previousReportSha256=$null;
            previousWorker=$null;previousReportFailure=$null;launchEvidence=$null}
        if($task.TaskName -cnotmatch '^MarketBrain-Gateway-Key-Probe-([a-f0-9]{32})$' -or $task.TaskPath -cne '\'){
            $item.definitionFailure='SCHEDULE_UNRECOGNIZED_PROBE_NAME';[pscustomobject]$item;continue
        }
        $oldRun=$Matches[1];$c=Get-PaytmScheduledProbeContract $oldRun
        $item.taskName=$c.name;$item.runId=$oldRun
        $item.launchEvidence=Get-PaytmProbeLaunchEvidence $oldRun
        $item.state=if([string]$task.State -cmatch '^[A-Za-z0-9]{1,20}$'){[string]$task.State}else{'UNKNOWN'}
        $item.definition=Get-PaytmProbeTaskShape $task $oldRun
        try{Assert-PaytmProbeTask $task $oldRun ([bool]$task.Settings.Enabled);$item.definitionMatches=$true}
        catch{$item.definitionFailure=if($_.Exception.Message -cmatch '^SCHEDULE_[A-Z_]+$'){$_.Exception.Message}else{'SCHEDULE_DEFINITION_UNREADABLE'}}
        try{$info=Get-ScheduledTaskInfo -TaskName $c.name -TaskPath $c.path -ErrorAction Stop;$item.lastTaskResult=[long]$info.LastTaskResult}
        catch{$item.taskInfoFailure='SCHEDULE_TASK_INFO_UNAVAILABLE'}
        try{
            $worker=Assert-PaytmAccountPath (Join-Path $c.directory 'worker.ps1')
            if(Test-Path -LiteralPath $worker -PathType Leaf){
                $item.workerFilePresent=$true
                if((Get-Item -LiteralPath $worker).Length -gt 65536){throw 'SCHEDULE_WORKER_SIZE'}
                $item.workerHash=(Get-FileHash -LiteralPath $worker).Hash
                $item.workerMatchesCurrentSource=([IO.File]::ReadAllText($worker).Replace("`r`n","`n") -ceq (New-PaytmScheduledWorkerSource $oldRun).Replace("`r`n","`n"))
            }
        }catch{$item.workerSourceFailure='SCHEDULE_WORKER_SOURCE_UNAVAILABLE'}
        try{
            $null=Assert-PaytmAccountPath $c.result
            if(Test-Path -LiteralPath $c.result -PathType Leaf){
                $value=Read-PaytmRepairJson $c.result 8192
                if($value.runId -cne $oldRun){throw 'SCHEDULE_WORKER_BINDING'}
                $item.workerResult=Get-PaytmSafeProbeSummary $value
            }
        }catch{$item.workerResultFailure='SCHEDULE_WORKER_RESULT_UNAVAILABLE_OR_UNBOUND'}
        try{
            $files=@(Get-ChildItem -LiteralPath $directory -Filter ('paytm-scheduled-signing-*-'+$oldRun+'.json') -File -ErrorAction Stop)
            if($files.Count -gt 1){throw 'SCHEDULE_AMBIGUOUS_PRIOR_REPORT'}
            if($files.Count -eq 1){
                $value=Read-PaytmRepairJson $files[0].FullName 65536
                if($value.runId -cne $oldRun){throw 'SCHEDULE_PRIOR_REPORT_BINDING'}
                $item.previousReport=Get-PaytmSafeProbeSummary $value
                $item.previousReportSha256=(Get-FileHash -LiteralPath $files[0].FullName).Hash
                if($null -ne $value.worker){$item.previousWorker=Get-PaytmSafeProbeSummary $value.worker}
            }
        }catch{$item.previousReportFailure='SCHEDULE_PRIOR_REPORT_UNAVAILABLE_OR_UNBOUND'}
        [pscustomobject]$item
    }
}
function ConvertTo-PaytmProbeEvent($Event,[string]$TaskName,[ValidateSet('Task','Account')][string]$Scope) {
    $source=$Event.ToXml()
    if($source.Length -gt 65536 -or $source -match '<!DOCTYPE'){throw 'SCHEDULE_EVENT_XML_REJECTED'}
    [xml]$xml=$source;$data=@{}
    foreach($node in @($xml.Event.EventData.Data)){
        if($null -ne $node -and $node.HasAttribute('Name')){$data[$node.GetAttribute('Name')]=$node.InnerText}
    }
    # Recheck server-side filtering. Account events correlate by identity/time, not task ID.
    if($Scope -ceq 'Task'){
        if($data.TaskName -cne ('\'+$TaskName)){throw 'SCHEDULE_EVENT_TASK_BINDING'}
    }elseif($Event.Id -ne 4625 -or $data.TargetUserName -ine 'marketbrain-gateway' -or $data.LogonType -cne '4'){
        throw 'SCHEDULE_EVENT_ACCOUNT_BINDING'
    }
    $fields=[ordered]@{}
    foreach($key in @('ResultCode','ErrorCode','ErrorValue','Status','SubStatus','LogonType','ProcessId','EnginePID','TaskInstanceId','InstanceId')){
        if($data.ContainsKey($key)){
            $value=[string]$data[$key]
            $fields[$key]=if($value -cmatch '^(0x[0-9a-fA-F]{1,16}|-?[0-9]{1,20}|\{?[0-9a-fA-F]{8}(-[0-9a-fA-F]{4}){3}-[0-9a-fA-F]{12}\}?)$'){$value}else{'UNEXPECTED_VALUE'}
        }
    }
    [pscustomobject]@{id=[int]$Event.Id;recordId=[long]$Event.RecordId;
        utc=if($null -ne $Event.TimeCreated){$Event.TimeCreated.ToUniversalTime().ToString('o')}else{$null};fields=$fields}
}
function Get-PaytmProbeLaunchEvidence([string]$RunId) {
    $c=Get-PaytmScheduledProbeContract $RunId
    $result=[ordered]@{observedUtc=[datetime]::UtcNow.ToString('o');lookbackDays=7;taskInfo=$null;taskInfoFailure=$null;channels=@()}
    try{
        $info=Get-ScheduledTaskInfo -TaskName $c.name -TaskPath $c.path -ErrorAction Stop
        $result.taskInfo=[pscustomobject]@{lastTaskResult=[long]$info.LastTaskResult;
            lastRunTimeUtc=if($null -ne $info.LastRunTime){([datetime]$info.LastRunTime).ToUniversalTime().ToString('o')}else{$null};
            missedRuns=if($null -ne $info.NumberOfMissedRuns){[long]$info.NumberOfMissedRuns}else{$null}}
    }catch{$result.taskInfoFailure='SCHEDULE_TASK_INFO_UNAVAILABLE'}
    foreach($scope in @('Task','Account')){
        $channel=if($scope -ceq 'Task'){'Microsoft-Windows-TaskScheduler/Operational'}else{'Security'}
        $entry=[ordered]@{scope=$scope;channel=$channel;enabled=$null;status='UNAVAILABLE';events=@();limitReached=$false;failureType=$null;failureHresult=$null}
        try{
            $log=Get-WinEvent -ListLog $channel -ErrorAction Stop;$entry.enabled=[bool]$log.IsEnabled
            # Query retained events even if logging is currently disabled. Never enable/clear logs.
            $filter=if($scope -ceq 'Task'){
                "*[System[TimeCreated[timediff(@SystemTime) <= 604800000]] and EventData[Data[@Name='TaskName']='\"+$c.name+"']]"
            }else{
                "*[System[EventID=4625 and TimeCreated[timediff(@SystemTime) <= 604800000]] and EventData[Data[@Name='TargetUserName']='marketbrain-gateway' and Data[@Name='LogonType']='4']]"
            }
            $events=@();$queryErrors=@()
            $events=@(Get-WinEvent -LogName $channel -FilterXPath $filter -MaxEvents 32 -ErrorAction SilentlyContinue -ErrorVariable queryErrors)
            $unexpected=@($queryErrors|Where-Object {$_.FullyQualifiedErrorId -notlike 'NoMatchingEventsFound*'})
            if($unexpected.Count){throw $unexpected[0]}
            $entry.limitReached=($events.Count -ge 32)
            $entry.events=@(foreach($event in $events){ConvertTo-PaytmProbeEvent $event $c.name $scope})
            $entry.status=if($events.Count){'CAPTURED'}else{'NO_MATCHING_EVENTS'}
        }catch{
            $entry.status='UNAVAILABLE';$entry.events=@();$base=$_.Exception.GetBaseException()
            $entry.failureType=$base.GetType().Name;$entry.failureHresult=$base.HResult
        }
        $result.channels+=@([pscustomobject]$entry)
    }
    [pscustomobject]$result
}
