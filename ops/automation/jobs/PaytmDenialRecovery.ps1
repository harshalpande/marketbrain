#requires -Version 7.5
# Generated bounded activation. Historical recovery revisions remain immutable.
param([Parameter(Mandatory)][string]$ResultPath,[ValidateSet('Observe','Apply','FailureFixture')][string]$Mode='Observe')
$ErrorActionPreference='Stop'

function Resolve-TimeAccountTaskSid([string]$Identity) {
 if([string]::IsNullOrWhiteSpace($Identity)){throw 'TIME_ACCOUNT_PRINCIPAL_MISSING'}
 if($Identity.StartsWith('S-1-', [StringComparison]::OrdinalIgnoreCase)){
  return [Security.Principal.SecurityIdentifier]::new($Identity).Value
 }
 return ([Security.Principal.NTAccount]::new($Identity)).Translate([Security.Principal.SecurityIdentifier]).Value
}

function Get-DurableCollectorDefinition([string]$WorkerHash) {
 if($WorkerHash -cnotmatch '^[A-F0-9]{64}$'){throw 'COLLECTOR_WORKER_HASH'}
 $root='C:\ProgramData\MarketBrainPaytmHealth\collector-v1'
 $command="if((Get-FileHash -LiteralPath '$root\worker.ps1').Hash -cne '$WorkerHash'){exit 9};&([scriptblock]::Create([IO.File]::ReadAllText('$root\worker.ps1')))"
 @{name='MarketBrain-Health-Collector-v1';root=$root;work='C:\ProgramData\MarketBrainPaytmHealth\collector-work-v1';exe='C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe';arguments=('-NoLogo -NoProfile -NonInteractive -EncodedCommand '+[Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($command)))}
}

function Assert-DurableCollectorTask($Task,$Definition) {
 $sid=Resolve-TimeAccountTaskSid ([string]$Task.Principal.UserId)
 if($Task.TaskName -cne $Definition.name -or $Task.TaskPath -cne '\' -or $sid -cne 'S-1-5-21-3041730714-102984520-3202743044-1011' -or [string]$Task.Principal.LogonType -cne 'Password' -or [string]$Task.Principal.RunLevel -cne 'Limited'){throw 'COLLECTOR_TASK_IDENTITY'}
 if($Task.Actions.Count -ne 1 -or $Task.Actions[0].Execute -ine $Definition.exe -or $Task.Actions[0].Arguments -cne $Definition.arguments -or $Task.Actions[0].WorkingDirectory -cne $Definition.root){throw 'COLLECTOR_TASK_ACTION'}
 if($Task.Settings.Enabled -or [string]$Task.State -cne 'Disabled' -or $Task.Triggers.Count -ne 1 -or $Task.Triggers[0].CimClass.CimClassName -cne 'MSFT_TaskBootTrigger' -or -not $Task.Triggers[0].Enabled){throw 'COLLECTOR_TASK_STARTUP'}
 if([string]$Task.Settings.MultipleInstances -cne 'IgnoreNew' -or $Task.Settings.RestartCount -ne 0 -or [Xml.XmlConvert]::ToTimeSpan($Task.Settings.ExecutionTimeLimit).TotalSeconds -ne 0 -or $Task.Settings.DisallowStartIfOnBatteries -or $Task.Settings.StopIfGoingOnBatteries -or -not $Task.Settings.StartWhenAvailable){throw 'COLLECTOR_TASK_SETTINGS'}
}

# PS5-compatible read-only time observation contract. No actions on import.
function Get-TimeObservationBootId {
    # Stable across users/processes; changes after a Windows restart.
    (Get-CimInstance Win32_OperatingSystem -ErrorAction Stop).LastBootUpTime.ToUniversalTime().ToString('o')
}
function Assert-TimeObservationAcl([string]$Path) {
    if((Get-Item -LiteralPath $Path -Force).Attributes -band [IO.FileAttributes]::ReparsePoint){throw 'TIME_OBSERVER_REPARSE'}
    $acl=Get-Acl -LiteralPath $Path
    $trusted=@('S-1-5-18','S-1-5-32-544')
    if($acl.GetOwner([Security.Principal.SecurityIdentifier]).Value -notin $trusted){throw 'TIME_OBSERVER_OWNER'}
    $write=[Security.AccessControl.FileSystemRights]::Write -bor [Security.AccessControl.FileSystemRights]::Delete -bor [Security.AccessControl.FileSystemRights]::DeleteSubdirectoriesAndFiles -bor [Security.AccessControl.FileSystemRights]::ChangePermissions -bor [Security.AccessControl.FileSystemRights]::TakeOwnership
    foreach($ace in $acl.GetAccessRules($true,$true,[Security.Principal.SecurityIdentifier])){
        if($ace.AccessControlType -eq 'Allow' -and ($ace.FileSystemRights -band $write) -and $ace.IdentityReference.Value -notin $trusted){throw 'TIME_OBSERVER_WRITABLE'}
    }
}
function ConvertFrom-TimeObservation($Value,[string]$BootId,[long]$NowTicks,[long]$Frequency) {
    if($Value.version -ne 1 -or $Value.bootId -cne $BootId -or $Value.frequency -ne $Frequency -or $Value.sequence -lt 1){throw 'TIME_OBSERVER_IDENTITY'}
    if($Value.startTicks -isnot [long] -or $Value.endTicks -isnot [long] -or $Value.startTicks -gt $Value.endTicks -or $Value.endTicks -gt $NowTicks){throw 'TIME_OBSERVER_TIMING'}
    $age=($NowTicks-$Value.startTicks)/[double]$Frequency
    if($age -lt 0 -or $age -gt 8){throw 'TIME_OBSERVER_STALE'}
    if($Value.status.exitCode -ne 0 -or $Value.source.exitCode -ne 0 -or $Value.service.state -cne 'Running' -or $Value.service.startType -ne 2){throw 'TIME_OBSERVER_UNHEALTHY'}
    if($Value.status.output -isnot [string] -or $Value.source.output -isnot [string] -or $Value.status.output.Length -gt 12000 -or $Value.source.output.Length -gt 1024){throw 'TIME_OBSERVER_FORMAT'}
    # Add snapshot age to the reported sync age; never make old evidence younger.
    $pattern='(?im)^(Time since Last Good Sync Time:\s*)([0-9]+(?:\.[0-9]+)?)(s\s*)$'
    $m=[regex]::Match($Value.status.output,$pattern)
    if(-not $m.Success){throw 'TIME_OBSERVER_SYNC_AGE'}
    $seconds=[double]::Parse($m.Groups[2].Value,[Globalization.CultureInfo]::InvariantCulture)+$age
    $output=$Value.status.output.Remove($m.Groups[2].Index,$m.Groups[2].Length).Insert($m.Groups[2].Index,$seconds.ToString('F6',[Globalization.CultureInfo]::InvariantCulture))
    [pscustomobject]@{status=@{exitCode=0;output=$output};source=$Value.source;service=$Value.service;ageSeconds=$age;sequence=$Value.sequence}
}
function ConvertFrom-TimeObservationJson([string]$Json) {
    # PS7 otherwise coerces ISO boot IDs into DateTime, unlike the PS5 producer.
    if($PSVersionTable.PSVersion -ge [version]'7.5'){ConvertFrom-Json -InputObject $Json -DateKind String}else{ConvertFrom-Json -InputObject $Json}
}
function Read-TimeObservationFileOnce([string]$Path) {
    Assert-TimeObservationAcl $Path
    $stream=[IO.File]::Open($Path,'Open','Read',([IO.FileShare]::ReadWrite -bor [IO.FileShare]::Delete))
    try{if($stream.Length -gt 16384){throw 'TIME_OBSERVER_SIZE'};$reader=[IO.StreamReader]::new($stream);try{$buffer=[char[]]::new(16385);$n=$reader.ReadBlock($buffer,0,16385);if($n -gt 16384){throw 'TIME_OBSERVER_SIZE'};return ConvertFrom-TimeObservationJson ([string]::new($buffer,0,$n))}finally{$reader.Dispose()}}finally{$stream.Dispose()}
}
function Read-TimeObservationFile([string]$Path) {
    for($attempt=0;$attempt -lt 3;$attempt++){
        try{return Read-TimeObservationFileOnce $Path}catch{
            $cause=$_.Exception.GetBaseException()
            if(($cause -isnot [IO.IOException] -and $cause -isnot [Management.Automation.ItemNotFoundException]) -or $attempt -eq 2){throw}
            Start-Sleep -Milliseconds 25
        }
    }
}
function Read-TimeObservationOnce {
    $root='C:\ProgramData\MarketBrainPaytmHealth\time-observer-v1';$path=Join-Path $root 'snapshot.json'
    foreach($p in @('C:\ProgramData\MarketBrainPaytmHealth',$root)){Assert-TimeObservationAcl $p}
    $v=Read-TimeObservationFileOnce $path
    ConvertFrom-TimeObservation $v (Get-TimeObservationBootId) ([Diagnostics.Stopwatch]::GetTimestamp()) ([Diagnostics.Stopwatch]::Frequency)
}

function Read-TimeObservation {
    # Snapshot replacement can briefly invalidate a path lookup. Retry only I/O
    # lookup failures, never ACL policy, identity, age or malformed-data failures.
    for($attempt=0;$attempt -lt 3;$attempt++){
        try{return Read-TimeObservationOnce}catch{
            $cause=$_.Exception.GetBaseException()
            $transient=$cause -is [IO.IOException] -or $cause -is [Management.Automation.ItemNotFoundException]
            if(-not $transient -or $attempt -eq 2){throw}
            Start-Sleep -Milliseconds 25
        }
    }
}


# PS5.1-compatible runtime. Diagnostic health only; never arms a route.
function Read-DurableCollectorControl([string]$Path,[string]$Installation) {
 $v=Read-TimeObservationFile $Path
 if($v.version -ne 1 -or $v.installationId -cne $Installation -or $v.enabled -isnot [bool]){throw 'COLLECTOR_CONTROL_INVALID'}
 return $v.enabled
}
function Write-DurableCollectorStatus([string]$Path,$Value) {
 $json=$Value|ConvertTo-Json -Depth 5 -Compress
 if([Text.Encoding]::UTF8.GetByteCount($json) -gt 8192){throw 'COLLECTOR_STATUS_SIZE'}
 $temp=$Path+'.'+[guid]::NewGuid().ToString('N')+'.new'
 [IO.File]::WriteAllText($temp,$json,[Text.UTF8Encoding]::new($false))
 if([IO.File]::Exists($Path)){[IO.File]::Replace($temp,$Path,[Management.Automation.Language.NullString]::Value)}else{[IO.File]::Move($temp,$Path)}
}
function Invoke-DurableCollectorLoop([string]$Token,[string[]]$SshArguments,[string]$Boot,[scriptblock]$Enabled,[scriptblock]$Save) {
 $r=@{version=1;instanceId=[guid]::NewGuid().ToString('N');processId=$PID;sequence=0;acceptedCount=0;consecutiveFailures=0;phase='STARTING';failure=$null;finalHealthRevoked=$false;ordersEnabled=$false}
 try{
  while((& $Enabled)){
   $r.sequence++;$r.observedUtc=[DateTimeOffset]::UtcNow.ToString('o')
   try{
    $v=Invoke-CollectorCycle $Token $SshArguments $Boot
    if(-not $v.accepted -or -not $v.healthySubmitted){throw 'COLLECTOR_SAMPLE_REJECTED'}
    $r.acceptedCount++;$r.consecutiveFailures=0;$r.phase='HEALTH_RECORDED';$r.failure=$null
   }catch{
    $r.consecutiveFailures++;$r.phase='BACKOFF';$r.failure='COLLECTOR_SAMPLE_FAILED'
    # Best-effort immediate revocation; TTL remains authoritative if Java is unavailable.
    try{$null=Invoke-CollectorCycle $Token $SshArguments $Boot -Revoke}catch{}
   }
   & $Save $r
   if($r.consecutiveFailures -ge 3){throw 'COLLECTOR_FAILURE_LIMIT'}
   Start-Sleep -Seconds ([int][math]::Min(8,2*[math]::Pow(2,$r.consecutiveFailures)))
  }
  $r.phase='STOPPED';$r.failure=$null
 }catch{$r.phase='FAILED';$r.failure=if($_.Exception.Message -cmatch '^COLLECTOR_[A-Z_]+$'){$_.Exception.Message}else{'COLLECTOR_RUNTIME_FAILED'}}
 finally{
  try{$v=Invoke-CollectorCycle $Token $SshArguments $Boot -Revoke;$r.finalHealthRevoked=($v.revoked -eq $true)}catch{$r.finalHealthRevoked=$false}
  if(-not $r.finalHealthRevoked){$r.phase='FAILED';$r.failure='COLLECTOR_REVOCATION_UNCONFIRMED'}
  $r.observedUtc=[DateTimeOffset]::UtcNow.ToString('o');& $Save $r
 }
 return $r
}


# Read-only verification of the accepted spare-machine installation.
function Assert-DurableCollectorReceipt($Receipt) {
 if($Receipt.version -ne 1 -or $Receipt.runId -cne 'ab47639ee8d74da69a9466c0f59e601e' -or $Receipt.status -cne 'DURABLE_COLLECTOR_STAGED_DISABLED_ACTIVATION_PENDING' -or $Receipt.failure -or $Receipt.taskRegistered -ne $true -or $Receipt.disabledVerified -ne $true -or $Receipt.workerStarted -ne $false -or $Receipt.ordersEnabled -ne $false){throw 'COLLECTOR_RECEIPT_STATE'}
 if($Receipt.workerSha256 -cne '25CFF7A9A54184DC0B5F43A094B331B14C4D288448C8BA8A01975A9F29053B99' -or $Receipt.knownHostsSha256 -cne 'C8D0896753936BC7AB4B47E755516BF253A973F8E65CC8B8CF249B9476CC924D' -or $Receipt.taskXmlSha256 -cne '4D5EFBB0271BF6EB937050E89B5118CBDCE89FF9AC30AF1FD7F8C10EC8E6B730'){throw 'COLLECTOR_RECEIPT_PINS'}
 if($Receipt.credentialCheck.accepted -ne $true -or $Receipt.credentialCheck.win32Code -ne 0 -or $Receipt.credentialCheck.logonType -cne 'BATCH' -or $Receipt.credentialCheck.resolvedSid -cne 'S-1-5-21-3041730714-102984520-3202743044-1011'){throw 'COLLECTOR_RECEIPT_IDENTITY'}
}
function Get-DurableCollectorStagingPreflight($Receipt) {
 Assert-DurableCollectorReceipt $Receipt
 $d=Get-DurableCollectorDefinition $Receipt.workerSha256
 foreach($path in @('C:\ProgramData\MarketBrainPaytmHealth',$d.root,(Join-Path $d.root 'worker.ps1'),(Join-Path $d.root 'known_hosts'),(Join-Path $d.root 'control.json'))){Assert-TimeObservationAcl $path}
 if((Get-FileHash -LiteralPath (Join-Path $d.root 'worker.ps1')).Hash -cne $Receipt.workerSha256 -or (Get-FileHash -LiteralPath (Join-Path $d.root 'known_hosts')).Hash -cne $Receipt.knownHostsSha256){throw 'COLLECTOR_INSTALLED_FILE_DRIFT'}
 $control=Read-TimeObservationFile (Join-Path $d.root 'control.json')
 if($control.version -ne 1 -or $control.installationId -cne $Receipt.runId -or $control.enabled -isnot [bool] -or $control.enabled){throw 'COLLECTOR_CONTROL_DRIFT'}
 $task=Get-ScheduledTask -TaskName $d.name -TaskPath '\' -ErrorAction Stop
 Assert-DurableCollectorTask $task $d
 if($task.Description -cne ('MarketBrain diagnostic collector '+$Receipt.runId)){throw 'COLLECTOR_TASK_OWNERSHIP'}
 $sha=[Security.Cryptography.SHA256]::Create()
 try{$xmlHash=([BitConverter]::ToString($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes((Export-ScheduledTask -TaskName $d.name -TaskPath '\'))))).Replace('-','')}finally{$sha.Dispose()}
 if($xmlHash -cne $Receipt.taskXmlSha256){throw 'COLLECTOR_TASK_XML_DRIFT'}
 $snapshot=Read-TimeObservation
 return @{status='DURABLE_COLLECTOR_STAGING_VERIFIED_ACTIVATION_PENDING';installationId=$Receipt.runId;taskDisabled=$true;controlDisabled=$true;workerHashVerified=$true;hostHashVerified=$true;taskXmlVerified=$true;timeSnapshotAgeSeconds=$snapshot.ageSeconds;observedUtc=[DateTime]::UtcNow.ToString('o');ordersEnabled=$false;runtimeStarted=$false}
}


function Stop-DenialRecoveryTask($Context) {
    $null=Disable-ScheduledTask -TaskName $Context.taskName -TaskPath '\' -ErrorAction Stop
    if([string](Get-ScheduledTask -TaskName $Context.taskName -TaskPath '\').State -in @('Running','Queued')){
        $null=Stop-ScheduledTask -TaskName $Context.taskName -TaskPath '\' -ErrorAction Stop
    }
    $watch=[Diagnostics.Stopwatch]::StartNew()
    do {
        $t=Get-ScheduledTask -TaskName $Context.taskName -TaskPath '\'
        $listeners=@([Net.NetworkInformation.IPGlobalProperties]::GetIPGlobalProperties().GetActiveTcpListeners()|Where-Object Port -EQ 18889)
        if([string]$t.State -notin @('Running','Queued') -and -not $t.Settings.Enabled -and -not $listeners.Count){
            $lease=$null
            try{$lease=[IO.File]::Open((Join-Path $Context.work 'instance.lock'),'Open','ReadWrite','None');return}
            catch{}finally{if($lease){$lease.Dispose()}}
        }
        Start-Sleep -Milliseconds 500
    }while($watch.Elapsed.TotalSeconds -lt 15)
    throw 'RECOVERY_STOP_NOT_VERIFIED'
}

function Register-DenialRecoveryGuard($Context,$ManifestHash) {
    # Independent stop survives termination of the controller/worker process.
    $guardPath=Join-Path $Context.archive 'guard.ps1'
    $collectorStop=''
    if($Context.collectorInstallation){
        if($Context.collectorInstallation -cne 'ab47639ee8d74da69a9466c0f59e601e'){throw 'COLLECTOR_GUARD_IDENTITY'}
        $collectorStop=@'
$ct=Get-ScheduledTask -TaskName 'MarketBrain-Health-Collector-v1' -TaskPath '\'
if($ct.Description -cne 'MarketBrain diagnostic collector ab47639ee8d74da69a9466c0f59e601e'){exit 6}
$cp='C:\ProgramData\MarketBrainPaytmHealth\collector-v1\control.json'
$cv=Get-Content -LiteralPath $cp -Raw|ConvertFrom-Json
if($cv.installationId -cne 'ab47639ee8d74da69a9466c0f59e601e'){exit 7}
$cv.enabled=$false
$tmp=$cp+'.guard.new'
[IO.File]::WriteAllText($tmp,($cv|ConvertTo-Json),[Text.UTF8Encoding]::new($false))
[IO.File]::Replace($tmp,$cp,[Management.Automation.Language.NullString]::Value)
Disable-ScheduledTask -TaskName 'MarketBrain-Health-Collector-v1' -TaskPath '\' | Out-Null
if([string](Get-ScheduledTask -TaskName 'MarketBrain-Health-Collector-v1' -TaskPath '\').State -in @('Running','Queued')){Stop-ScheduledTask -TaskName 'MarketBrain-Health-Collector-v1' -TaskPath '\'}
'@
    }
    $text=@"
`$ErrorActionPreference='Stop'
$collectorStop
if((Get-FileHash -LiteralPath '$($Context.root)\manifest.json').Hash -cne '$ManifestHash'){exit 2}
`$t=Get-ScheduledTask -TaskName '$($Context.taskName)' -TaskPath '\'
if(`$t.Description -cne 'MarketBrain locked supervisor ea8b91471cf048aa97a0f6b939b355c7'){exit 3}
Disable-ScheduledTask -TaskName '$($Context.taskName)' -TaskPath '\' | Out-Null
if([string](Get-ScheduledTask -TaskName '$($Context.taskName)' -TaskPath '\').State -in @('Running','Queued')){Stop-ScheduledTask -TaskName '$($Context.taskName)' -TaskPath '\'}
[IO.File]::WriteAllText('$($Context.archive)\guard-fired.json','{"stopRequested":true}')
"@
    [IO.File]::WriteAllText($guardPath,$text,[Text.UTF8Encoding]::new($false))
    $hash=(Get-FileHash -LiteralPath $guardPath).Hash
    $command="if((Get-FileHash -LiteralPath '$guardPath').Hash -cne '$hash'){exit 4};&([scriptblock]::Create([IO.File]::ReadAllText('$guardPath')))"
    $args='-NoLogo -NoProfile -NonInteractive -EncodedCommand '+[Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($command))
    $action=New-ScheduledTaskAction -Execute 'C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe' -Argument $args
    $minutes=3
    if($Context.lifecycleWindow -eq $true){
        if($Context.collectorInstallation -cne 'ab47639ee8d74da69a9466c0f59e601e'){throw 'COLLECTOR_GUARD_IDENTITY'}
        $minutes=10
    }
    $trigger=New-ScheduledTaskTrigger -Once -At ((Get-Date).AddMinutes($minutes))
    $principal=New-ScheduledTaskPrincipal -UserId 'S-1-5-18' -LogonType ServiceAccount -RunLevel Highest
    $settings=New-ScheduledTaskSettingsSet -StartWhenAvailable -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -ExecutionTimeLimit ([TimeSpan]::FromMinutes(1))
    if(Get-ScheduledTask -TaskName $Context.guardName -TaskPath '\' -ErrorAction SilentlyContinue){throw 'RECOVERY_GUARD_ALREADY_EXISTS'}
    $null=Register-ScheduledTask -TaskName $Context.guardName -TaskPath '\' -Action $action -Trigger $trigger -Principal $principal -Settings $settings -Description ('MarketBrain bounded denial capture '+$Context.runId) -ErrorAction Stop
    $guard=Get-ScheduledTask -TaskName $Context.guardName -TaskPath '\'
    $Context.guardVerification=@{expectedBoundary=$trigger.StartBoundary;actualBoundary=$guard.Triggers[0].StartBoundary;argumentMatch=($guard.Actions[0].Arguments -ceq $args);executeMatch=($guard.Actions[0].Execute -ieq $action.Execute);userId=$guard.Principal.UserId;logonType=[string]$guard.Principal.LogonType;runLevel=[string]$guard.Principal.RunLevel}
    if($guard.Actions.Count -ne 1 -or $guard.Actions[0].Arguments -cne $args -or
       $guard.Actions[0].Execute -ine $action.Execute -or -not $guard.Settings.Enabled -or
       $guard.Principal.UserId -notin @('S-1-5-18','SYSTEM','NT AUTHORITY\SYSTEM') -or
       [string]$guard.Principal.LogonType -ne 'ServiceAccount' -or
       [string]$guard.Principal.RunLevel -ne 'Highest' -or
       $guard.Triggers.Count -ne 1 -or [DateTimeOffset]::Parse($guard.Triggers[0].StartBoundary) -ne [DateTimeOffset]::Parse($trigger.StartBoundary) -or
       -not $guard.Settings.StartWhenAvailable -or $guard.Settings.DisallowStartIfOnBatteries -or
       $guard.Settings.StopIfGoingOnBatteries){throw 'RECOVERY_GUARD_NOT_VERIFIED'}
    $Context.guardXmlHash=[Convert]::ToHexString([Security.Cryptography.SHA256]::HashData([Text.Encoding]::UTF8.GetBytes((Export-ScheduledTask -TaskName $Context.guardName -TaskPath '\'))))
}

function Remove-DenialRecoveryGuard($Context) {
    $xml=Export-ScheduledTask -TaskName $Context.guardName -TaskPath '\'
    if([Convert]::ToHexString([Security.Cryptography.SHA256]::HashData([Text.Encoding]::UTF8.GetBytes($xml))) -cne $Context.guardXmlHash){throw 'RECOVERY_GUARD_DRIFT'}
    Unregister-ScheduledTask -TaskName $Context.guardName -TaskPath '\' -Confirm:$false -ErrorAction Stop
}

function Get-PostRecoveryPreflight($Context,$Receipt,[switch]$CollectorPreflight) {
    $r=@{passed=$false;hashes=@{};failure=$null};$lease=$null
    try{
        foreach($dir in @($Context.root,$Context.work)){if((Get-Item -LiteralPath $dir).Attributes -band [IO.FileAttributes]::ReparsePoint){throw 'RECOVERY_REPARSE_POINT'}}
        foreach($name in $Receipt.hashes.Keys){
            if($name -in @('status.json','blocked.json','startup-failure.json')){continue}
            $path=Join-Path $Context.root $name
            $expected=switch($name){'manifest.json'{'7DEBDC0E181DF0484E74F5FF4A2AD24D1034A8464A12DD72684A5D3EFFFAAD55'} 'transport.ps1'{'40343DDDBF1063ACE422922D5D4DAD98B126B04C53ECA40790B174ECA8C9CBCD'} default{$Receipt.hashes[$name]}}
            if((Get-Item -LiteralPath $path).Attributes -band [IO.FileAttributes]::ReparsePoint -or (Get-FileHash -LiteralPath $path).Hash -cne $expected){throw 'RECOVERY_POST_SOURCE_DRIFT'}
            $r.hashes[$name]=$expected
        }
        foreach($name in @('blocked.json','startup-failure.json')){if(Test-Path -LiteralPath (Join-Path $Context.work $name)){throw 'RECOVERY_NEW_INCIDENT'}}
        $v=Read-BoundedJson (Join-Path $Context.work 'status.json')
        $r.currentStatus=@{instanceId=$v.instanceId;sequence=$v.sequence;phase=$v.phase;failure=$v.failure;ordersEnabled=$v.ordersEnabled;brokerReady=$v.brokerReady}
        $taskInventory=Get-ScheduledTask -TaskName $Context.taskName -TaskPath '\'
        $r.currentTask=@{state=[string]$taskInventory.State;enabled=[bool]$taskInventory.Settings.Enabled}
        if($v.phase -cne 'TRANSPORT_READY' -or $v.failure -or $v.ordersEnabled -ne $false -or $v.brokerReady -ne $false){throw 'RECOVERY_POST_STATUS_DRIFT'}
        if(-not $CollectorPreflight -and ($v.instanceId -cne '8df248cef94f4b5baff3d672e0863e17' -or $v.sequence -ne 39)){throw 'RECOVERY_POST_STATUS_DRIFT'}
        if($CollectorPreflight -and ($v.instanceId -cnotmatch '^[a-f0-9]{32}$' -or $v.sequence -lt 1)){throw 'RECOVERY_POST_STATUS_DRIFT'}
        $r.hashes['status.json']=(Get-FileHash -LiteralPath (Join-Path $Context.work 'status.json')).Hash
        $t=Get-ScheduledTask -TaskName $Context.taskName -TaskPath '\';$i=Get-ScheduledTaskInfo -TaskName $Context.taskName -TaskPath '\'
        if([string]$t.State -cne 'Disabled' -or $t.Settings.Enabled -or $i.LastTaskResult -ne 267014){throw 'RECOVERY_POST_TASK_DRIFT'}
        if(-not $CollectorPreflight -and $i.LastRunTime.ToUniversalTime().ToString('o') -cne '2026-11-20T06:25:25.0000000Z'){throw 'RECOVERY_POST_TASK_DRIFT'}
        $saved=[xml][IO.File]::ReadAllText((Join-Path $Context.root 'denial-recovery-649710f6-e95b-4ebc-831b-60a99d22ac69\task.xml'))
        $current=[xml](Export-ScheduledTask -TaskName $Context.taskName -TaskPath '\')
        if($saved.Task.Actions.OuterXml -cne $current.Task.Actions.OuterXml -or $saved.Task.Principals.OuterXml -cne $current.Task.Principals.OuterXml){throw 'RECOVERY_TASK_IDENTITY_DRIFT'}
        if(@([Net.NetworkInformation.IPGlobalProperties]::GetIPGlobalProperties().GetActiveTcpListeners()|Where-Object Port -EQ 18889).Count){throw 'RECOVERY_LISTENER_PRESENT'}
        $lease=[IO.File]::Open((Join-Path $Context.work 'instance.lock'),'Open','ReadWrite','None')
        $r.passed=$true
    }catch{$r.failure=if($_.Exception.Message -cmatch '^RECOVERY_[A-Z_]+$'){$_.Exception.Message}else{'RECOVERY_POST_INSPECTION_FAILED'}}finally{if($lease){$lease.Dispose()}}
    return $r
}

function Get-ApplicationHealthInventory {
    $r=@{readOnly=$true;healthTasks=@();files=@{};applicationHttpStatus=$null;applicationUp=$false;credentialsRead=$false}
    $r.healthTasks=@(Get-ScheduledTask|Where-Object {$_.TaskName -like 'MarketBrain*Health*'}|ForEach-Object {@{name=$_.TaskName;state=[string]$_.State;enabled=$_.Settings.Enabled;logonType=[string]$_.Principal.LogonType}})
    foreach($relative in @('installation.json','key-custody\manifest.json','token-custody\health-token.dpapi')){
        $r.files[$relative]=Test-Path -LiteralPath (Join-Path 'C:\ProgramData\MarketBrainPaytmHealth' $relative)
    }
    $handler=[Net.Http.HttpClientHandler]::new();$handler.UseProxy=$false;$handler.AllowAutoRedirect=$false
    $client=[Net.Http.HttpClient]::new($handler);$client.Timeout=[TimeSpan]::FromSeconds(3);$client.MaxResponseContentBufferSize=4096
    try{$response=$client.GetAsync('http://127.0.0.1:8080/actuator/health').GetAwaiter().GetResult();try{$r.applicationHttpStatus=[int]$response.StatusCode;if($response.IsSuccessStatusCode){$body=$response.Content.ReadAsStringAsync().GetAwaiter().GetResult()|ConvertFrom-Json;$r.applicationUp=($body.status -ceq 'UP')}}finally{$response.Dispose()}}catch{$r.applicationProbeFailure=$_.Exception.GetBaseException().GetType().Name}finally{$client.Dispose()}
    return $r
}

function Read-BoundedJson([string]$Path) {
 $s=$null;$reader=$null
 try{
  $s=[IO.File]::Open($Path,'Open','Read',([IO.FileShare]::ReadWrite -bor [IO.FileShare]::Delete))
  if($s.Length -gt 65536){throw 'SCHEDULE_GATEWAY_STATE_SIZE'}
  $reader=[IO.StreamReader]::new($s);$buffer=[char[]]::new(65537);$n=$reader.ReadBlock($buffer,0,$buffer.Length)
  if($n -gt 65536){throw 'SCHEDULE_GATEWAY_STATE_SIZE'}
  ([string]::new($buffer,0,$n))|ConvertFrom-Json
 }finally{if($reader){$reader.Dispose()};if($s){$s.Dispose()}}
}

function New-CollectorGatewayContext([string]$RunId) {
 if($RunId -cnotmatch '^[a-f0-9]{32}$'){throw 'SCHEDULE_GATEWAY_RUN'}
 @{root='C:\ProgramData\MarketBrainPaytmGateway\supervisor-v1';work='C:\ProgramData\MarketBrainPaytmGateway\supervisor-work-v1';taskName='MarketBrain-Gateway-Supervisor-v1';runId=$RunId;guardName=('MarketBrain-Collector-Guard-'+$RunId);archive=('C:\ProgramData\MarketBrainPaytmGateway\supervisor-v1\collector-window-'+$RunId);guardXmlHash=$null;startAttempted=$false;stopped=$false;guardRemoved=$false}
}

function Get-CollectorGatewayPreflight($Context) {
 $receipt=$acceptedGatewayReceipt
 $r=Get-PostRecoveryPreflight $Context $receipt.result.evidence.recoveryPreflight -CollectorPreflight
 if(-not $r.passed){$r=Get-CollectorReviewedGatewayPreflight $Context $r}
 if((Read-BoundedJson (Join-Path $Context.root 'control.json')).mode -cne 'LOCKED'){throw 'SCHEDULE_GATEWAY_SCOPE'}
 $task=Get-ScheduledTask -TaskName $Context.taskName -TaskPath '\'
 if($task.Description -cne 'MarketBrain locked supervisor ea8b91471cf048aa97a0f6b939b355c7'){throw 'SCHEDULE_GATEWAY_IDENTITY'}
 if(-not (Get-ApplicationHealthInventory).applicationUp){throw 'SCHEDULE_APPLICATION_NOT_UP'}
 $null=Read-TimeObservation
 return $r
}

function Test-CollectorGatewaySample($Value,[string]$PreviousInstance) {
 if($Value.installationId -cne 'ea8b91471cf048aa97a0f6b939b355c7' -or $Value.ordersEnabled -ne $false -or $Value.brokerReady -ne $false){throw 'SCHEDULE_GATEWAY_SCOPE'}
 if($Value.instanceId -ceq $PreviousInstance){return $false}
 if($Value.instanceId -cnotmatch '^[a-f0-9]{32}$' -or $Value.failure -or $Value.phase -ceq 'BLOCKED'){throw 'SCHEDULE_GATEWAY_FAILED'}
 if($Value.phase -cne 'TRANSPORT_READY'){return $false}
 $tls=$Value.lastTlsObservation
 if($Value.denialsVerified -ne $true -or -not $tls -or $tls.exitCode -ne 0 -or $tls.timedOut -ne $false -or $tls.connectStatus -ne 200 -or $tls.tlsVerifyCode -ne 0){throw 'SCHEDULE_GATEWAY_TLS'}
 return $true
}

function Start-CollectorGatewayWindow($Context) {
 $before=Get-CollectorGatewayPreflight $Context
 if(Test-Path -LiteralPath $Context.archive){throw 'SCHEDULE_GATEWAY_COLLISION'}
 $null=New-Item -ItemType Directory -Path $Context.archive
 # Fixed independent three-minute stop survives terminal/process loss.
 $Context.guardAttempted=$true
 Register-DenialRecoveryGuard $Context $before.hashes['manifest.json']
 $again=Get-CollectorGatewayPreflight $Context
 if($again.hashes['status.json'] -cne $before.hashes['status.json']){throw 'SCHEDULE_GATEWAY_CHANGED'}
 Preserve-CollectorGatewayIncident $Context $again
 $Context.startAttempted=$true
 $null=Enable-ScheduledTask -TaskName $Context.taskName -TaskPath '\'
 Start-ScheduledTask -TaskName $Context.taskName -TaskPath '\'
 $watch=[Diagnostics.Stopwatch]::StartNew();$first=$null
 do{
  Start-Sleep -Seconds 1
  if((Read-BoundedJson (Join-Path $Context.root 'control.json')).mode -cne 'LOCKED'){throw 'SCHEDULE_GATEWAY_SCOPE'}
  $v=Read-BoundedJson (Join-Path $Context.work 'status.json')
  if(Test-CollectorGatewaySample $v $before.currentStatus.instanceId){
   $listeners=@([Net.NetworkInformation.IPGlobalProperties]::GetIPGlobalProperties().GetActiveTcpListeners()|Where-Object Port -EQ 18889)
   if(-not $listeners.Count -or @($listeners|Where-Object {$_.Address.ToString() -notin @('127.0.0.1','::1')}).Count){throw 'SCHEDULE_GATEWAY_LISTENER'}
   if($first -and $v.instanceId -ceq $first.instanceId -and $v.sequence -gt $first.sequence){$Context.readyInstance=$v.instanceId;return}
   if($first -and $v.instanceId -cne $first.instanceId){throw 'SCHEDULE_GATEWAY_CHANGED'}
   $first=$v
  }
  Write-Progress -Activity 'Collector gateway window' -Status ('Waiting for fresh transport: '+[int]$watch.Elapsed.TotalSeconds+' / 45 seconds') -PercentComplete 50
 }while($watch.Elapsed.TotalSeconds -lt 45)
 throw 'SCHEDULE_GATEWAY_TIMEOUT'
}

$acceptedGatewayReceipt = @'
{"id":"fac8bfd4-c743-4bd5-a65f-90b46ff6c91d","kind":"paytm-transport-test","state":"FAILED","created":1795152262.7403548,"updated":1795152268.4976327,"result":{"sourceSha256":"A4406D09EA13B766D61A7224688200FBB983C65EB8D8720DEC8CE075E01FA187","timedOut":false,"evidence":{"elapsedSeconds":2.9812462,"gatewayChanged":false,"passed":false,"version":4,"ordersEnabled":false,"preflight":{"applicationLocked":true,"phase":"BLOCKED","failure":"TRANSPORT_DENIAL_FAILED","sequence":3860,"instanceId":"1f2c636c108042898f3c58143e00d9c7"},"failure":"GATEWAY_BLOCKED:TRANSPORT_DENIAL_FAILED","brokerCredentialsUsed":false,"samples":[],"scope":"OPERATOR_TRANSPORT_NOT_BROKER_READINESS","recoveryPreflight":{"failure":null,"readyForReviewedRecovery":true,"readOnly":true,"task":{"enabled":true,"state":"Ready","lastRunUtc":"2026-11-19T14:40:40.0000000Z","lastTaskResult":1},"checks":{"incidentAndControlVerified":true,"noListenerAndStableFiles":true,"installedSourcesVerified":true,"exclusiveLeaseAvailable":true,"taskIdentityAndIdleVerified":true},"hashes":{"startup-failure.json":"CCFCCFCE7A1823FAE9C7904EC23C933C7B021B4604AE1CA552A18070D91751EB","transport.ps1":"AB861CA9E1556EC56F5EF149F63A49D407B3AAEB2771C2195B2A6A32A25754F1","gateway.ps1":"02984F2C16011A2916A06F4B66DE56AF5C88F1469E91F8A2DEC893C24D414453","transport-control.json":"771B4F00BBD8E703E0C53598ECF18FBF6F95374297CEF26699F3E4A3B6AD574B","status.json":"D39BD1F0E645DE8FBB0E1C4E84F43030638AE35DC8020F8E0032FE6BEB4BFBF6","manifest.json":"343A080C09E468F73FAC844ABC5CAA02B2A429CCD4B66308D2B6366102B12A98","host.ps1":"8345B8BF264B4A040A5076E8B94AA030F8F94847A151F8CF547D7D09C5FBDEE1","session-checkpoint.json":"353E2A30A6FA0085857DF3523FA5DAB858309936CE6C550C814D2BD80E2FFDB5","transport.dll":"8AB8A14B23C079AFF9ECEDDFB8897E2E93B3DB6C86B88595D63B3B4C811540B6","runner.ps1":"D143505DBC8565E1984C7A05100D1E565CF113D197E153804877D2FC4EE93CEC","control.json":"0E0055C44B349A9394BFBD7E97AC13C6F190B5B58BE9EA2CC24F0AECB4302B39","native.dll":"3EEF1F0E1251B770CB345248EE627AE897703D6799AB111F58177BC35A110F8C","blocked.json":"CE8ADFE890F9BD641B5AC010F97B9392F678F1D60E595233820B14841E4C090E"}},"test":"PAYTM_TRANSPORT_OBSERVATION","incident":{"firstTlsFailure":{"phaseMetricsParsed":true,"elapsedMilliseconds":4094,"curlTotalMilliseconds":4017,"exitCode":28,"tlsHandshakeCompletedMilliseconds":0,"metricsParsed":true,"tlsVerifyCode":0,"timedOut":false,"httpStatus":0,"connectStatus":0,"tcpConnectMilliseconds":0},"files":{"transport.ps1":"AB861CA9E1556EC56F5EF149F63A49D407B3AAEB2771C2195B2A6A32A25754F1","manifest.json":"343A080C09E468F73FAC844ABC5CAA02B2A429CCD4B66308D2B6366102B12A98"},"installedTransportMatchesManifest":true,"historicalDenialResponsePresent":false,"lastTlsFailure":{"phaseMetricsParsed":true,"elapsedMilliseconds":4123,"curlTotalMilliseconds":4011,"exitCode":28,"tlsHandshakeCompletedMilliseconds":0,"metricsParsed":true,"tlsVerifyCode":0,"timedOut":false,"httpStatus":0,"connectStatus":0,"tcpConnectMilliseconds":0},"lastTlsObservation":{"phaseMetricsParsed":true,"elapsedMilliseconds":1155,"curlTotalMilliseconds":1100,"exitCode":0,"tlsHandshakeCompletedMilliseconds":712,"metricsParsed":true,"tlsVerifyCode":0,"timedOut":false,"httpStatus":503,"connectStatus":200,"tcpConnectMilliseconds":2}}},"exitCode":1,"stdoutCharacters":0,"elapsedSeconds":4.5993754,"stderrCharacters":0,"revision":"42625d48fd8e6733fd3797fe8d133edd3c67186d","passed":false,"ordersEnabled":false},"spec":{"revision":"42625d48fd8e6733fd3797fe8d133edd3c67186d","sha256":"A4406D09EA13B766D61A7224688200FBB983C65EB8D8720DEC8CE075E01FA187","mode":"Observe"}}
'@ | ConvertFrom-Json -AsHashtable -DateKind String

# Fixed acceptance of the installed recovery worker; historical v1 receipts remain unchanged.
function Get-RecoveryCollectorReceipt {
 $v=Read-TimeObservationFile 'C:\ProgramData\MarketBrainPaytmHealth\collector-v1\recovery-upgrade.json'
 if($v.runId -cne '444dcaf7d25241c5a6e391d243f7eebe' -or $v.installationId -cne 'ab47639ee8d74da69a9466c0f59e601e' -or $v.status -cne 'COLLECTOR_RECOVERY_UPGRADED_DISABLED_RUNTIME_PENDING' -or $v.passed -ne $true -or $v.failure -or $v.ordersEnabled -ne $false -or $v.workerStarted -ne $false){throw 'RECOVERY_INSTALL_RECEIPT'}
 if($v.workerSha256 -cne 'F4C496DBBBB1CF55A1A3FA8E2BAD29AE832166E97A5A633F10A3C2C313CCFF4B' -or $v.taskXmlSha256 -cne '968E8E23E13263CC89A026084E0534A9692DB31FD0D60091870C817824674F11'){throw 'RECOVERY_INSTALL_PINS'}
 # Activation expects runId to identify the installation, not the upgrade attempt.
 @{runId=$v.installationId;workerSha256=$v.workerSha256;taskXmlSha256=$v.taskXmlSha256}
}
function Get-RecoveryCollectorPreflight($Receipt){
 $accepted=Get-RecoveryCollectorReceipt
 if($Receipt.runId -cne $accepted.runId -or $Receipt.workerSha256 -cne $accepted.workerSha256){throw 'RECOVERY_RECEIPT_CHANGED'}
 $d=Get-DurableCollectorDefinition $accepted.workerSha256
 foreach($name in @('worker.ps1','known_hosts','control.json')){Assert-TimeObservationAcl (Join-Path $d.root $name)}
 if((Get-FileHash -LiteralPath (Join-Path $d.root 'worker.ps1')).Hash -cne $accepted.workerSha256 -or (Get-FileHash -LiteralPath (Join-Path $d.root 'known_hosts')).Hash -cne 'C8D0896753936BC7AB4B47E755516BF253A973F8E65CC8B8CF249B9476CC924D'){throw 'RECOVERY_FILES_CHANGED'}
 Assert-DurableCollectorTask (Get-ScheduledTask -TaskName $d.name -TaskPath '\') $d
 $xml=Export-ScheduledTask -TaskName $d.name -TaskPath '\'
 $hash=[Convert]::ToHexString([Security.Cryptography.SHA256]::HashData([Text.Encoding]::UTF8.GetBytes($xml)))
 if($hash -cne $accepted.taskXmlSha256){throw 'RECOVERY_TASK_XML_CHANGED'}
 if(Read-DurableCollectorControl (Join-Path $d.root 'control.json') $accepted.runId){throw 'RECOVERY_CONTROL_ENABLED'}
 $time=Read-TimeObservation
 $syncAge=[regex]::Match($time.status.output,'(?im)^Time since Last Good Sync Time:\s*([0-9]+(?:\.[0-9]+)?)s\s*$')
 if(-not $syncAge.Success -or [double]::Parse($syncAge.Groups[1].Value,[Globalization.CultureInfo]::InvariantCulture) -gt 300){throw 'RECOVERY_FRESH_WINDOWS_SYNC_REQUIRED'}
 @{passed=$true;workerHashVerified=$true;taskXmlVerified=$true;disabledVerified=$true;timeSnapshotAgeSeconds=$time.ageSeconds;ordersEnabled=$false}
}
function Assert-RecoveryPriorReports($Status,$Final){
 if($Final.runId -cne 'ab47639ee8d74da69a9466c0f59e601e'){throw 'RECOVERY_PRIOR_INSTALLATION'}
 foreach($v in @($Status,$Final.collector)){
  if($v.version -ne 1 -or $v.instanceId -cne '9e0e85a010c2457887faa0fe8efdb6a1' -or $v.processId -ne 4400 -or $v.phase -cne 'FAILED' -or $v.failure -cne 'COLLECTOR_REVOCATION_UNCONFIRMED' -or $v.acceptedCount -ne 13 -or $v.sequence -ne 18 -or $v.ordersEnabled -ne $false){throw 'RECOVERY_PRIOR_REPORT_CHANGED'}
 }
}
function Preserve-RecoveryPriorReports($Definition){
 if(Test-Path -LiteralPath (Join-Path $Definition.root 'recovery-activation-attempt.json')){Preserve-RecoveryClockAttempt $Definition;return}
 $checkpoint=Read-TimeObservationFile (Join-Path $Definition.root 'signout-checkpoint.json')
 if($checkpoint.runId -cne '73fc2f10891346768bdc0f88e978da75' -or $checkpoint.phase -cne 'REVIEW_REQUIRED'){throw 'RECOVERY_CHECKPOINT_CHANGED'}
 $s=Read-BoundedJson (Join-Path $Definition.work 'status.json');$f=Read-BoundedJson (Join-Path $Definition.work 'final.json');Assert-RecoveryPriorReports $s $f
 $archive=Join-Path $Definition.root 'prior-signout-9e0e85a010c2457887faa0fe8efdb6a1'
 if(Test-Path -LiteralPath $archive){throw 'RECOVERY_ARCHIVE_EXISTS'}
 $null=New-Item -ItemType Directory -Path $archive;Assert-TimeObservationAcl $archive
 foreach($name in @('status.json','final.json')){
  $path=Join-Path $Definition.work $name
  if((Get-Item -LiteralPath $path).Attributes -band [IO.FileAttributes]::ReparsePoint){throw 'RECOVERY_PRIOR_REPARSE'}
  $hash=(Get-FileHash -LiteralPath $path).Hash;$target=Join-Path $archive $name
  Copy-Item -LiteralPath $path -Destination $target -ErrorAction Stop
  if((Get-FileHash -LiteralPath $target).Hash -cne $hash){throw 'RECOVERY_ARCHIVE_HASH'}
 }
 foreach($name in @('status.json','final.json')){
  $path=Join-Path $Definition.work $name
  if((Get-FileHash -LiteralPath $path).Hash -cne (Get-FileHash -LiteralPath (Join-Path $archive $name)).Hash){throw 'RECOVERY_PRIOR_RACE'}
  Remove-Item -LiteralPath $path -ErrorAction Stop
 }
}
function Assert-RecoveryClockAttempt($Claim,$Final,$Status){
 if($Claim.runId -cne 'bf234f1d51e34c95859a2332e27aebe8' -or $Final.runId -cne 'ab47639ee8d74da69a9466c0f59e601e' -or $Final.ordersEnabled -ne $false){throw 'RECOVERY_CLOCK_ATTEMPT_CHANGED'}
 foreach($s in @($Final.collector,$Status)){
  if($s.version -ne 2 -or $s.instanceId -cne '2ed645783c084210ac6d6062cb53235a' -or $s.processId -ne 9768 -or $s.phase -cne 'FAILED' -or $s.failure -cne 'COLLECTOR_FAILURE_LIMIT' -or $s.sequence -ne 3 -or $s.acceptedCount -ne 0 -or $s.finalHealthRevoked -ne $true -or $s.ordersEnabled -ne $false -or @($s.lastFailure.findings).Count -ne 1 -or $s.lastFailure.findings[0] -cne 'WINDOWS_LAST_SYNC_TOO_OLD'){throw 'RECOVERY_CLOCK_FINAL_CHANGED'}
 }
}
function Preserve-RecoveryClockAttempt($Definition){
 $claim=Join-Path $Definition.root 'recovery-activation-attempt.json'
 Assert-RecoveryClockAttempt (Read-TimeObservationFile $claim) (Read-BoundedJson (Join-Path $Definition.work 'final.json')) (Read-BoundedJson (Join-Path $Definition.work 'status.json'))
 $archive=Join-Path $Definition.root 'clock-retry-bf234f1d51e34c95859a2332e27aebe8'
 if(Test-Path -LiteralPath $archive){throw 'RECOVERY_CLOCK_RETRY_EXISTS'}
 $null=New-Item -ItemType Directory -Path $archive;Assert-TimeObservationAcl $archive
 $paths=@($claim,(Join-Path $Definition.work 'status.json'),(Join-Path $Definition.work 'final.json'))
 foreach($p in $paths){
  $item=Get-Item -LiteralPath $p;if($item.Attributes -band [IO.FileAttributes]::ReparsePoint){throw 'RECOVERY_CLOCK_REPARSE'}
  Copy-Item -LiteralPath $p -Destination (Join-Path $archive $item.Name) -ErrorAction Stop
  if((Get-FileHash -LiteralPath $p).Hash -cne (Get-FileHash -LiteralPath (Join-Path $archive $item.Name)).Hash){throw 'RECOVERY_CLOCK_ARCHIVE_HASH'}
 }
 foreach($p in $paths){
  if((Get-FileHash -LiteralPath $p).Hash -cne (Get-FileHash -LiteralPath (Join-Path $archive ([IO.Path]::GetFileName($p)))).Hash){throw 'RECOVERY_CLOCK_ARCHIVE_RACE'}
  Remove-Item -LiteralPath $p -ErrorAction Stop
 }
}
function ConvertTo-RecoveryActivationSource([string]$Source){
 $pairs=@{
  "`$receipt=Read-TimeObservationFile 'C:\ProgramData\MarketBrainPaytmHealth\time-observer-v1\collector-install-result.json'"=' $receipt=Get-RecoveryCollectorReceipt';
  'Get-DurableCollectorStagingPreflight $receipt'='Get-RecoveryCollectorPreflight $receipt';
  ' Preserve-CollectorRejectedAttempt $d'=' Preserve-RecoveryPriorReports $d';
  "`$claim=Join-Path `$d.root 'activation-attempt.json'"="`$claim=Join-Path `$d.root 'recovery-activation-attempt.json'";
  '$Value.version -ne 1'='$Value.version -ne 2';
  'DURABLE_COLLECTOR_ACTIVATION_PASSED_LIFECYCLE_PENDING'='RECOVERY_COLLECTOR_ACTIVATION_PASSED_LIFECYCLE_PENDING'
 }
 foreach($old in $pairs.Keys){if(-not $Source.Contains($old)){throw 'RECOVERY_ACTIVATION_TEMPLATE_DRIFT'};$Source=$Source.Replace($old,$pairs[$old])}
 return $Source
}


# One reviewed retry of the retained sign-out incident, never a general latch bypass.
function Assert-CollectorGatewayIncident($Status,$Blocked,$Startup){
 foreach($v in @($Status,$Blocked,$Startup)){if($v.instanceId -cne 'c592dec90f904b9da35d7f9dbf1b4226' -or $v.failure -cne 'TRANSPORT_CONFIG_UNAVAILABLE'){throw 'COLLECTOR_GATEWAY_INCIDENT_CHANGED'}}
 if($Status.installationId -cne 'ea8b91471cf048aa97a0f6b939b355c7' -or $Status.phase -cne 'BLOCKED' -or $Status.sequence -ne 157 -or $Status.processId -ne 8420 -or $Status.ordersEnabled -ne $false -or $Status.brokerReady -ne $false -or $Startup.stage -cne 'OBSERVATION_LOOP'){throw 'COLLECTOR_GATEWAY_INCIDENT_STATE'}
}
function Get-CollectorReviewedGatewayPreflight($Context,$Original){
 if($Original.failure -cne 'RECOVERY_NEW_INCIDENT'){throw $Original.failure}
 # Original preflight already verified all executable/configuration hashes before finding markers.
 $values=@{};$hashes=@{}
 foreach($name in @('status.json','blocked.json','startup-failure.json')){
  $p=Join-Path $Context.work $name
  if((Get-Item -LiteralPath $p).Attributes -band [IO.FileAttributes]::ReparsePoint){throw 'COLLECTOR_GATEWAY_REPARSE'}
  $values[$name]=Read-BoundedJson $p;$hashes[$name]=(Get-FileHash -LiteralPath $p).Hash
 }
 Assert-CollectorGatewayIncident $values['status.json'] $values['blocked.json'] $values['startup-failure.json']
 $task=Get-ScheduledTask -TaskName $Context.taskName -TaskPath '\';$info=Get-ScheduledTaskInfo -TaskName $Context.taskName -TaskPath '\'
 if([string]$task.State -cne 'Disabled' -or $task.Settings.Enabled -or $info.LastTaskResult -ne 1){throw 'COLLECTOR_GATEWAY_INCIDENT_TASK'}
 [xml]$saved=[IO.File]::ReadAllText((Join-Path $Context.root 'denial-recovery-649710f6-e95b-4ebc-831b-60a99d22ac69\task.xml'))
 [xml]$current=Export-ScheduledTask -TaskName $Context.taskName -TaskPath '\'
 if($saved.Task.Actions.OuterXml -cne $current.Task.Actions.OuterXml -or $saved.Task.Principals.OuterXml -cne $current.Task.Principals.OuterXml){throw 'COLLECTOR_GATEWAY_TASK_DRIFT'}
 if(@([Net.NetworkInformation.IPGlobalProperties]::GetIPGlobalProperties().GetActiveTcpListeners()|Where-Object Port -eq 18889).Count){throw 'COLLECTOR_GATEWAY_LISTENER_PRESENT'}
 $lease=[IO.File]::Open((Join-Path $Context.work 'instance.lock'),'Open','ReadWrite','None');$lease.Dispose()
 $Original.hashes['status.json']=$hashes['status.json'];$Original.incidentHashes=$hashes
 $Original.currentStatus=@{instanceId=$values['status.json'].instanceId;sequence=157;phase='BLOCKED';failure='TRANSPORT_CONFIG_UNAVAILABLE';ordersEnabled=$false;brokerReady=$false}
 $Original.passed=$true;$Original.failure=$null;$Original.reviewedIncident=$true
 return $Original
}
function Preserve-CollectorGatewayIncident($Context,$Before){
 if(-not $Before.reviewedIncident){return}
 if(-not $Context.guardXmlHash){throw 'COLLECTOR_GATEWAY_GUARD_REQUIRED'}
 foreach($name in @('status.json','blocked.json','startup-failure.json')){
  $src=Join-Path $Context.work $name;$dst=Join-Path $Context.archive $name
  if((Get-FileHash -LiteralPath $src).Hash -cne $Before.incidentHashes[$name] -or (Test-Path -LiteralPath $dst)){throw 'COLLECTOR_GATEWAY_INCIDENT_RACE'}
  Copy-Item -LiteralPath $src -Destination $dst -ErrorAction Stop
  if((Get-FileHash -LiteralPath $dst).Hash -cne $Before.incidentHashes[$name]){throw 'COLLECTOR_GATEWAY_BACKUP_HASH'}
 }
 foreach($name in @('blocked.json','startup-failure.json')){
  $p=Join-Path $Context.work $name
  if((Get-FileHash -LiteralPath $p).Hash -cne $Before.incidentHashes[$name]){throw 'COLLECTOR_GATEWAY_INCIDENT_RACE'}
  Remove-Item -LiteralPath $p -ErrorAction Stop
 }
 $Context.reviewedIncidentArchived=$true
}


# One bounded activation of the accepted disabled installation. No broker actions.
function Set-CollectorActivationControl($Definition,[bool]$Enabled) {
 $path=Join-Path $Definition.root 'control.json';$v=Read-TimeObservationFile $path
 if($v.version -ne 1 -or $v.installationId -cne 'ab47639ee8d74da69a9466c0f59e601e'){throw 'COLLECTOR_CONTROL_DRIFT'}
 $v.enabled=$Enabled;Write-DurableCollectorStatus $path $v;Assert-TimeObservationAcl $path
}
function Test-CollectorActivationSample($Value,$State) {
 if($Value.version -ne 2 -or $Value.instanceId -cnotmatch '^[a-f0-9]{32}$' -or $Value.processId -le 0 -or $Value.ordersEnabled -ne $false){throw 'COLLECTOR_SAMPLE_IDENTITY'}
 if($State.instance -and $Value.instanceId -cne $State.instance){throw 'COLLECTOR_INSTANCE_CHANGED'}
 if($State.processId -and $Value.processId -ne $State.processId){throw 'COLLECTOR_PROCESS_CHANGED'}
 if($Value.sequence -lt $State.sequence -or $Value.acceptedCount -gt $Value.sequence){throw 'COLLECTOR_SAMPLE_SEQUENCE'}
 if($Value.phase -ceq 'BACKOFF' -and $Value.failure -ceq 'COLLECTOR_SAMPLE_FAILED' -and $Value.consecutiveFailures -in @(1,2)){
  $State.instance=$Value.instanceId;$State.processId=$Value.processId;$State.sequence=$Value.sequence;return $false
 }
 if($Value.failure -or $Value.phase -ne 'HEALTH_RECORDED' -or $Value.consecutiveFailures -ne 0){throw 'COLLECTOR_SAMPLE_UNHEALTHY'}
 if($Value.sequence -gt $State.sequence){$State.advances++;$State.sequence=$Value.sequence}
 $State.instance=$Value.instanceId;$State.processId=$Value.processId
 return ($Value.acceptedCount -ge 3 -and $State.advances -ge 2)
}
function Preserve-CollectorRejectedAttempt($Definition) {
 $claim=Join-Path $Definition.root 'activation-attempt.json'
 if(-not (Test-Path -LiteralPath $claim)){return}
 $v=Read-TimeObservationFile $claim
 if($v.runId -cne 'a46e0f93692c401ab3d0e52f9aaac5a2'){throw 'COLLECTOR_ATTEMPT_REVIEW_REQUIRED'}
 $final=Read-BoundedJson (Join-Path $Definition.work 'final.json');$status=Read-BoundedJson (Join-Path $Definition.work 'status.json')
 if($final.runId -cne 'ab47639ee8d74da69a9466c0f59e601e' -or $final.failure -or $final.stage -cne 'COMPLETE' -or $final.ordersEnabled -ne $false){throw 'COLLECTOR_RETRY_FINAL_DRIFT'}
 foreach($sample in @($final.collector,$status)){
  if($sample.instanceId -cne '46f6741158754a6294298a5b23117de3' -or $sample.phase -cne 'STOPPED' -or $sample.finalHealthRevoked -ne $true -or $sample.acceptedCount -ne 0 -or $sample.sequence -ne 1 -or $sample.ordersEnabled -ne $false){throw 'COLLECTOR_RETRY_STATUS_DRIFT'}
 }
 $archive=Join-Path $Definition.root 'retry-after-a46e0f93692c401ab3d0e52f9aaac5a2'
 if(Test-Path -LiteralPath $archive){throw 'COLLECTOR_RETRY_ALREADY_PREPARED'}
 $null=New-Item -ItemType Directory -Path $archive
 foreach($path in @($claim,(Join-Path $Definition.work 'status.json'),(Join-Path $Definition.work 'final.json'))){
  $item=Get-Item -LiteralPath $path
  if($item.Attributes -band [IO.FileAttributes]::ReparsePoint){throw 'COLLECTOR_RETRY_REPARSE'}
  $hash=(Get-FileHash -LiteralPath $path).Hash;$target=Join-Path $archive $item.Name
  Move-Item -LiteralPath $path -Destination $target -ErrorAction Stop
  if((Get-FileHash -LiteralPath $target).Hash -cne $hash){throw 'COLLECTOR_RETRY_ARCHIVE_MISMATCH'}
 }
}
function Stop-CollectorActivation($Definition,$Report) {
 Set-CollectorActivationControl $Definition $false
 $w=[Diagnostics.Stopwatch]::StartNew()
 do{
  $t=Get-ScheduledTask -TaskName $Definition.name -TaskPath '\'
  if([string]$t.State -notin @('Running','Queued')){break}
  Start-Sleep -Milliseconds 500
 }while($w.Elapsed.TotalSeconds -lt 25)
 $null=Disable-ScheduledTask -TaskName $Definition.name -TaskPath '\'
 if([string](Get-ScheduledTask -TaskName $Definition.name -TaskPath '\').State -in @('Running','Queued')){
  Stop-ScheduledTask -TaskName $Definition.name -TaskPath '\';$Report.forcedStop=$true
 }
 $w.Restart()
 do{
  $t=Get-ScheduledTask -TaskName $Definition.name -TaskPath '\'
  if(-not $t.Settings.Enabled -and [string]$t.State -notin @('Running','Queued')){
   $lease=$null;try{$lease=[IO.File]::Open((Join-Path $Definition.work 'instance.lock'),'Open','ReadWrite','None');$Report.collectorStopped=$true;return}catch{}finally{if($lease){$lease.Dispose()}}
  }
  Start-Sleep -Milliseconds 500
 }while($w.Elapsed.TotalSeconds -lt 10)
 throw 'COLLECTOR_STOP_UNCONFIRMED'
}
$r=@{version=1;runId=[guid]::NewGuid().ToString('N');passed=$false;status='REVIEW_REQUIRED';mode=$Mode;ordersEnabled=$false;failure=$null;cleanupFailure=$null;collectorStarted=$false;collectorStopped=$false;forcedStop=$false;guardRemoved=$false}
$ctx=$null;$d=$null;$attempted=$false;$watch=[Diagnostics.Stopwatch]::StartNew()
try{
 if($Mode -eq 'FailureFixture'){throw 'COLLECTOR_DELIBERATE_FIXTURE'}
 $identity=[Security.Principal.WindowsIdentity]::GetCurrent()
 try{if(-not ([Security.Principal.WindowsPrincipal]::new($identity)).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)){throw 'COLLECTOR_ADMIN_REQUIRED'}}finally{$identity.Dispose()}
  $receipt=Get-RecoveryCollectorReceipt
 $r.preflight=Get-RecoveryCollectorPreflight $receipt
 $d=Get-DurableCollectorDefinition $receipt.workerSha256
 $ctx=New-CollectorGatewayContext $r.runId;$ctx.collectorInstallation=$receipt.runId
 $r.gatewayPreflight=Get-CollectorGatewayPreflight $ctx
 if($Mode -eq 'Observe'){$r.status='COLLECTOR_ACTIVATION_PREFLIGHT_PASSED';$r.passed=$true;return}
 foreach($path in @($d.work,(Join-Path $d.work 'instance.lock'))){if((Get-Item -LiteralPath $path).Attributes -band [IO.FileAttributes]::ReparsePoint){throw 'COLLECTOR_WORK_REPARSE'}}
 $lease=[IO.File]::Open((Join-Path $d.work 'instance.lock'),'Open','ReadWrite','None');$lease.Dispose()
 Preserve-RecoveryPriorReports $d
 foreach($name in @('status.json','final.json')){if(Test-Path -LiteralPath (Join-Path $d.work $name)){throw 'COLLECTOR_PRIOR_RUN_REVIEW_REQUIRED'}}
 # Durable one-shot receipt stops an automatic second activation after interruption.
 $claim=Join-Path $d.root 'recovery-activation-attempt.json'
 $f=[IO.File]::Open($claim,'CreateNew','Write','Read');try{$b=[Text.Encoding]::UTF8.GetBytes(($r|ConvertTo-Json -Depth 5));$f.Write($b,0,$b.Length);$f.Flush($true)}finally{$f.Dispose()}
 $r.stage='GATEWAY_START';Start-CollectorGatewayWindow $ctx
 $null=Get-RecoveryCollectorPreflight $receipt
 $r.stage='COLLECTOR_START';$attempted=$true
 Set-CollectorActivationControl $d $true
 $null=Enable-ScheduledTask -TaskName $d.name -TaskPath '\'
 Start-ScheduledTask -TaskName $d.name -TaskPath '\';$r.collectorStarted=$true
 $state=@{instance=$null;sequence=0;advances=0;processId=0};$w=[Diagnostics.Stopwatch]::StartNew()
 do{
  Start-Sleep -Seconds 1
  $path=Join-Path $d.work 'status.json'
  if(Test-Path -LiteralPath $path){$sample=Read-BoundedJson $path;if(Test-CollectorActivationSample $sample $state){$r.publicationsVerified=$true;$r.observation=$sample;break}}
  if([string](Get-ScheduledTask -TaskName $d.name -TaskPath '\').State -notin @('Running','Queued')){throw 'COLLECTOR_EXITED_BEFORE_PUBLICATION'}
 }while($w.Elapsed.TotalSeconds -lt 65)
 if(-not $r.publicationsVerified){throw 'COLLECTOR_PUBLICATION_TIMEOUT'}
 $r.stage='GRACEFUL_STOP';Stop-CollectorActivation $d $r
 $final=Read-BoundedJson (Join-Path $d.work 'final.json')
 $r.worker=@{stage=$final.stage;failure=$final.failure;nonAdmin=$final.nonAdmin;sessionId=$final.sessionId;tokenAuthenticated=$final.tokenAuthenticated;applicationLocked=$final.applicationLocked;collector=$final.collector}
 $r.lastTaskResult=(Get-ScheduledTaskInfo -TaskName $d.name -TaskPath '\').LastTaskResult
 if($r.forcedStop -or $r.lastTaskResult -ne 0 -or $final.runId -cne $receipt.runId -or $final.failure -or $final.ordersEnabled -ne $false -or $final.nonAdmin -ne $true -or $final.sessionId -ne 0 -or $final.tokenAuthenticated -ne $true -or $final.applicationLocked -ne $true -or $final.collector.instanceId -cne $state.instance -or $final.collector.processId -ne $state.processId -or $final.collector.phase -cne 'STOPPED' -or $final.collector.finalHealthRevoked -ne $true){throw 'COLLECTOR_FINAL_PROOF_FAILED'}
 $r.finalHealthRevoked=$true;$r.stage='COMPLETE';$r.passed=$true;$r.status='RECOVERY_COLLECTOR_ACTIVATION_PASSED_LIFECYCLE_PENDING'
}catch{$r.failure=if($_.Exception.Message -cmatch '^[A-Z][A-Z0-9_]+$'){$_.Exception.Message}else{'COLLECTOR_ACTIVATION_'+$_.Exception.GetBaseException().GetType().Name};$r.failureLine=$_.InvocationInfo.ScriptLineNumber}
finally{
 if($attempted -and -not $r.collectorStopped){try{Stop-CollectorActivation $d $r}catch{$r.cleanupFailure='COLLECTOR_STOP_REVIEW_REQUIRED'}}
 if($ctx -and $ctx.startAttempted){try{Stop-DenialRecoveryTask $ctx;$ctx.stopped=$true;$r.gatewayStopped=$true}catch{$r.cleanupFailure='GATEWAY_STOP_REVIEW_REQUIRED'}}
 if($ctx -and $ctx.guardXmlHash -and (-not $attempted -or $r.collectorStopped) -and (-not $ctx.startAttempted -or $ctx.stopped)){try{Remove-DenialRecoveryGuard $ctx;$r.guardRemoved=$true}catch{$r.cleanupFailure='COLLECTOR_GUARD_REVIEW_REQUIRED'}}
 if($ctx -and $ctx.guardAttempted -and -not $ctx.guardXmlHash){$r.cleanupFailure='COLLECTOR_GUARD_REVIEW_REQUIRED'}
 if($attempted -and $d -and -not $r.worker){
  try{
   $finalPath=Join-Path $d.work 'final.json'
   if(Test-Path -LiteralPath $finalPath){$v=Read-BoundedJson $finalPath;if($v.runId -ceq 'ab47639ee8d74da69a9466c0f59e601e'){$r.worker=@{stage=$v.stage;failure=$v.failure;sessionId=$v.sessionId;nonAdmin=$v.nonAdmin;tokenAuthenticated=$v.tokenAuthenticated;collector=$v.collector}}}
  }catch{$r.workerEvidenceFailure='COLLECTOR_FINAL_EVIDENCE_UNAVAILABLE'}
 }
 if($r.cleanupFailure -or $r.failure){$r.passed=$false;$r.status='REVIEW_REQUIRED'}
 $r.elapsedSeconds=$watch.Elapsed.TotalSeconds
 [IO.File]::WriteAllText($ResultPath,($r|ConvertTo-Json -Depth 8),[Text.UTF8Encoding]::new($false))
}
if(-not $r.passed){exit 1}
