#requires -Version 7.5
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


# PS5 compatible. Local readiness is not authority to publish healthy state.
function Test-CollectorApplicationReady {
 Add-Type -AssemblyName System.Net.Http
 $h=[Net.Http.HttpClientHandler]::new();$h.UseProxy=$false;$h.AllowAutoRedirect=$false
 $c=[Net.Http.HttpClient]::new($h);$c.Timeout=[TimeSpan]::FromSeconds(3);$c.MaxResponseContentBufferSize=4096;$response=$null
 try{$response=$c.GetAsync('http://127.0.0.1:8080/actuator/health').GetAwaiter().GetResult();if([int]$response.StatusCode -ne 200){return $false};$v=$response.Content.ReadAsStringAsync().GetAwaiter().GetResult()|ConvertFrom-Json;return ($v.status -ceq 'UP')}catch{return $false}finally{if($response){$response.Dispose()};$c.Dispose()}
}
function Get-CollectorRecoveryElapsed($Watch){return $Watch.Elapsed.TotalSeconds}
function Wait-CollectorApplication([scriptblock]$Enabled) {
 $watch=[Diagnostics.Stopwatch]::StartNew()
 while((& $Enabled)){
  if(Test-CollectorApplicationReady){return}
  if((Get-CollectorRecoveryElapsed $watch) -ge 300){throw 'COLLECTOR_APPLICATION_WAIT_EXHAUSTED'}
  Start-Sleep -Seconds 5
 }
 throw 'COLLECTOR_START_CANCELLED'
}
function Get-CollectorRecoveryBoot([string]$Token) {
 $v=Invoke-CollectorHttp $Token 'clock' $null
 if($v.clockContractVersion -cne 'HEALTH_CLOCK_V1' -or $v.bootId -cnotmatch '^[a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12}$' -or $v.accepted -isnot [bool] -or $v.accepted -or $v.ordersEnabled -isnot [bool] -or $v.ordersEnabled){throw 'COLLECTOR_RECOVERY_CLOCK_CONTRACT'}
 return [string]$v.bootId
}
function Invoke-CollectorRecoveryLoop([string]$Token,[string[]]$SshArguments,[string]$Boot,[scriptblock]$Enabled,[scriptblock]$Save) {
 $r=@{version=2;instanceId=[guid]::NewGuid().ToString('N');processId=$PID;sequence=0;acceptedCount=0;consecutiveFailures=0;phase='STARTING';failure=$null;finalHealthRevoked=$false;ordersEnabled=$false;applicationBootId=$Boot;recoveryCount=0;lastFailure=$null}
 $outage=$null;$recover=$false
 try{
  while((& $Enabled)){
   $r.sequence++;$r.observedUtc=[DateTimeOffset]::UtcNow.ToString('o')
   if(-not (Test-CollectorApplicationReady)){
    if(-not $outage){$outage=[Diagnostics.Stopwatch]::StartNew();try{$null=Invoke-CollectorCycle $Token $SshArguments $Boot -Revoke}catch{}}
    $recover=$true;$r.phase='WAITING_FOR_APPLICATION';$r.failure='COLLECTOR_APPLICATION_NOT_READY';$r.lastFailure=@{code=$r.failure;sequence=$r.sequence}
    & $Save $r
    if((Get-CollectorRecoveryElapsed $outage) -ge 300){throw 'COLLECTOR_APPLICATION_WAIT_EXHAUSTED'}
    Start-Sleep -Seconds 5;continue
   }
   $v=$null
   try{
    $currentBoot=Get-CollectorRecoveryBoot $Token
    if($recover -or $currentBoot -cne $Boot){
     $newBoot=Test-HealthTokenAuthority $Token
     if($newBoot -cne $currentBoot){throw 'COLLECTOR_RECOVERY_BOOT_CHANGED'}
     $Boot=$newBoot;$r.applicationBootId=$Boot;$recover=$false;$r.recoveryCount++
    }
    $v=Invoke-CollectorCycle $Token $SshArguments $Boot
    if(-not $v.accepted -or -not $v.healthySubmitted){throw 'COLLECTOR_SAMPLE_REJECTED'}
    $r.acceptedCount++;$r.consecutiveFailures=0;$r.phase='HEALTH_RECORDED';$r.failure=$null;$outage=$null
   }catch{
    $r.consecutiveFailures++;$r.phase='BACKOFF';$r.failure='COLLECTOR_SAMPLE_FAILED'
    $code=if($_.Exception.Message -cmatch '^(COLLECTOR|HEALTH_TOKEN)_[A-Z_]+$'){$_.Exception.Message}else{'COLLECTOR_SAMPLE_EXCEPTION'}
    $r.lastFailure=@{code=$code;sequence=$r.sequence;phase=$null;findings=@();windowExceeded=$false}
    if($v){$r.lastFailure.phase=if([string]$v.failedPhase -cmatch '^[A-Z_]{1,64}$'){$v.failedPhase}else{$null};$r.lastFailure.findings=@($v.findings|Where-Object {$_ -cmatch '^[A-Z_]{1,100}$'}|Select-Object -First 10);$r.lastFailure.windowExceeded=($v.windowExceeded -eq $true)}
    try{$null=Invoke-CollectorCycle $Token $SshArguments $Boot -Revoke}catch{}
   }
   & $Save $r
   if($r.consecutiveFailures -ge 3){throw 'COLLECTOR_FAILURE_LIMIT'}
   if($outage -and (Get-CollectorRecoveryElapsed $outage) -ge 300){throw 'COLLECTOR_APPLICATION_WAIT_EXHAUSTED'}
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


function Invoke-CollectorDockerRead([string]$Executable,[string[]]$Arguments) {
 $p=[Diagnostics.Process]::new();$p.StartInfo.FileName=$Executable;$p.StartInfo.UseShellExecute=$false;$p.StartInfo.CreateNoWindow=$true;$p.StartInfo.RedirectStandardOutput=$true;$p.StartInfo.RedirectStandardError=$true
 foreach($arg in $Arguments){$p.StartInfo.ArgumentList.Add($arg)}
 try{if(-not $p.Start()){throw 'DOCKER_READ_START'};$o=$p.StandardOutput.ReadToEndAsync();$e=$p.StandardError.ReadToEndAsync();if(-not $p.WaitForExit(8000)){$p.Kill();throw 'DOCKER_READ_TIMEOUT'};if($p.ExitCode -ne 0 -or -not $o.Wait(1000) -or $o.Result.Length -gt 4096){throw 'DOCKER_READ_FAILED'};return $o.Result.Trim()}finally{$p.Dispose()}
}

function Get-CollectorDockerState {
 $exe=@(Get-Command docker.exe -CommandType Application -ErrorAction Stop)[0].Source
 $ids=Invoke-CollectorDockerRead $exe @('ps','-a','--filter','label=com.docker.compose.service=marketbrain-service','--format','{{.ID}}')
 $rows=@($ids -split '\r?\n'|Where-Object {$_})
 if($rows.Count -ne 1 -or $rows[0] -cnotmatch '^[a-f0-9]{12,64}$'){throw 'DOCKER_SERVICE_SELECTION_AMBIGUOUS'}
 $format='{{.Id}}|{{.State.Status}}|{{.State.StartedAt}}|{{.State.FinishedAt}}|{{.HostConfig.RestartPolicy.Name}}|{{.RestartCount}}'
 $v=(Invoke-CollectorDockerRead $exe @('inspect','--format',$format,$rows[0])) -split '\|'
 if($v.Count -ne 6 -or $v[0] -cnotmatch '^[a-f0-9]{64}$' -or $v[5] -cnotmatch '^\d+$'){throw 'DOCKER_SERVICE_STATE_FORMAT'}
 return @{containerId=$v[0];state=$v[1];startedAt=$v[2];finishedAt=$v[3];restartPolicy=$v[4];restartCount=[int]$v[5];readOnly=$true}
}

$upgradeWorkerHash='F4C496DBBBB1CF55A1A3FA8E2BAD29AE832166E97A5A633F10A3C2C313CCFF4B'
$upgradePayload='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'

# Upgrade the stopped diagnostic worker only. No task start, application restart or credentials.
function Get-CollectorUpgradeHash([byte[]]$Bytes){[Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($Bytes))}
function Assert-CollectorUpgradeTaskPreserved([string]$Before,[string]$After){
 [xml]$a=$Before;[xml]$b=$After
 $a.Task.Actions.InnerXml='';$b.Task.Actions.InnerXml=''
 if($a.OuterXml -cne $b.OuterXml){throw 'UPGRADE_TASK_NON_ACTION_DRIFT'}
}
function Write-CollectorUpgradeNew([string]$Path,[byte[]]$Bytes){
 $f=[IO.File]::Open($Path,'CreateNew','Write','None');try{$f.Write($Bytes,0,$Bytes.Length);$f.Flush($true)}finally{$f.Dispose()}
 Assert-TimeObservationAcl $Path
}
function Set-CollectorUpgradeAction($Definition){
 $action=New-ScheduledTaskAction -Execute $Definition.exe -Argument $Definition.arguments -WorkingDirectory $Definition.root
 # Action-only update preserves the existing stored task credential; no password registration.
 $null=Set-ScheduledTask -TaskName $Definition.name -TaskPath '\' -Action $action -ErrorAction Stop
}
function Invoke-CollectorRecoveryUpgrade([string]$RequestedMode){
 $r=@{version=1;runId=[guid]::NewGuid().ToString('N');status='REVIEW_REQUIRED';mode=$RequestedMode;failure=$null;rollbackFailure=$null;ordersEnabled=$false;workerStarted=$false;applicationRestarted=$false;credentialsUsed=$false;workerSha256=$upgradeWorkerHash}
 $lease=$null;$workerChanged=$false;$actionChanged=$false;$dockerChanged=$false;$backup=$null;$oldXml=$null;$before=$null;$exe=$null;$d=$null
 try{
  if($RequestedMode -notin @('Observe','Apply')){throw 'UPGRADE_MODE'}
  $identity=[Security.Principal.WindowsIdentity]::GetCurrent()
  if(-not ([Security.Principal.WindowsPrincipal]::new($identity)).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)){throw 'UPGRADE_ADMIN_REQUIRED'}
  $receipt=Read-TimeObservationFile 'C:\ProgramData\MarketBrainPaytmHealth\time-observer-v1\collector-install-result.json'
  $r.preflight=Get-DurableCollectorStagingPreflight $receipt
  $d=Get-DurableCollectorDefinition $receipt.workerSha256
  $destination=Join-Path $d.root 'recovery-upgrade.json'
  if(Test-Path -LiteralPath $destination){throw 'UPGRADE_ALREADY_RECORDED'}
  $checkpointPath=Join-Path $d.root 'signout-checkpoint.json'
  Assert-TimeObservationAcl $checkpointPath
  $cp=Read-TimeObservationFile $checkpointPath
  if($cp.runId -cne '73fc2f10891346768bdc0f88e978da75' -or $cp.phase -cne 'REVIEW_REQUIRED' -or $cp.installationId -cne $receipt.runId){throw 'UPGRADE_INCIDENT_CHANGED'}
  $gateway=Get-ScheduledTask -TaskName 'MarketBrain-Gateway-Supervisor-v1' -TaskPath '\' -ErrorAction Stop
  if($gateway.Settings.Enabled -or [string]$gateway.State -cne 'Disabled'){throw 'UPGRADE_GATEWAY_NOT_STOPPED'}
  $lock=Join-Path $d.work 'instance.lock'
  if((Get-Item -LiteralPath $lock).Attributes -band [IO.FileAttributes]::ReparsePoint){throw 'UPGRADE_LEASE_REPARSE'}
  $lease=[IO.File]::Open($lock,'Open','ReadWrite','None')
  $oldXml=Export-ScheduledTask -TaskName $d.name -TaskPath '\'
  $before=Get-CollectorDockerState
  if($before.containerId -cne '1644e08701f13e4cf8df734d516e2e04a098c7a88cb0cb55597996f71204c6ad' -or $before.state -cne 'running' -or $before.restartPolicy -cne 'no'){throw 'UPGRADE_CONTAINER_CHANGED'}
  if(-not (Test-CollectorApplicationReady)){throw 'UPGRADE_APPLICATION_NOT_READY'}
  $exe=@(Get-Command docker.exe -CommandType Application -ErrorAction Stop)[0].Source
  $r.containerBefore=$before
  $compressed=[IO.MemoryStream]::new([Convert]::FromBase64String($upgradePayload));$gz=[IO.Compression.GZipStream]::new($compressed,[IO.Compression.CompressionMode]::Decompress);$out=[IO.MemoryStream]::new()
  try{$gz.CopyTo($out);$bytes=$out.ToArray()}finally{$gz.Dispose();$compressed.Dispose();$out.Dispose()}
  if($bytes.Length -gt 262144 -or (Get-CollectorUpgradeHash $bytes) -cne $upgradeWorkerHash){throw 'UPGRADE_PAYLOAD'}
  $t=$null;$e=$null;$null=[Management.Automation.Language.Parser]::ParseInput([Text.Encoding]::UTF8.GetString($bytes),[ref]$t,[ref]$e);if($e.Count){throw 'UPGRADE_PARSE'}
  if($RequestedMode -ceq 'Observe'){$r.status='COLLECTOR_RECOVERY_UPGRADE_PREFLIGHT_PASSED';return $r}
  $backup=Join-Path $d.root ('recovery-backup-'+$r.runId)
  $null=New-Item -ItemType Directory -Path $backup -ErrorAction Stop;Assert-TimeObservationAcl $backup
  foreach($name in @('worker.ps1','known_hosts','control.json','signout-checkpoint.json')){
   $src=Join-Path $d.root $name;Assert-TimeObservationAcl $src
   Write-CollectorUpgradeNew (Join-Path $backup $name) ([IO.File]::ReadAllBytes($src))
   if((Get-FileHash -LiteralPath $src).Hash -cne (Get-FileHash -LiteralPath (Join-Path $backup $name)).Hash){throw 'UPGRADE_BACKUP_HASH'}
  }
  Write-CollectorUpgradeNew (Join-Path $backup 'task.xml') ([Text.Encoding]::UTF8.GetBytes($oldXml))
  Write-CollectorUpgradeNew (Join-Path $backup 'install-receipt.json') ([IO.File]::ReadAllBytes('C:\ProgramData\MarketBrainPaytmHealth\time-observer-v1\collector-install-result.json'))
  # Original status/final files and failed checkpoint remain untouched in their original locations.
  $r.backup=$backup
  $candidate=Join-Path $d.root ('worker-'+$r.runId+'.new')
  Write-CollectorUpgradeNew $candidate $bytes
  $workerChanged=$true
  [IO.File]::Replace($candidate,(Join-Path $d.root 'worker.ps1'),[Management.Automation.Language.NullString]::Value)
  $next=Get-DurableCollectorDefinition $upgradeWorkerHash
  $actionChanged=$true;Set-CollectorUpgradeAction $next
  Assert-DurableCollectorTask (Get-ScheduledTask -TaskName $d.name -TaskPath '\') $next
  $newXml=Export-ScheduledTask -TaskName $d.name -TaskPath '\'
  Assert-CollectorUpgradeTaskPreserved $oldXml $newXml
  if((Get-FileHash -LiteralPath (Join-Path $d.root 'worker.ps1')).Hash -cne $upgradeWorkerHash){throw 'UPGRADE_WORKER_HASH'}
  Assert-TimeObservationAcl (Join-Path $d.root 'worker.ps1')
  $dockerChanged=$true;$null=Invoke-CollectorDockerRead $exe @('update','--restart','unless-stopped',$before.containerId)
  $after=Get-CollectorDockerState
  if($after.containerId -cne $before.containerId -or $after.state -cne 'running' -or $after.startedAt -cne $before.startedAt -or $after.restartPolicy -cne 'unless-stopped'){throw 'UPGRADE_CONTAINER_VERIFY'}
  if((Read-TimeObservationFile (Join-Path $d.root 'control.json')).enabled -ne $false){throw 'UPGRADE_CONTROL_CHANGED'}
  $r.containerAfter=$after;$r.taskXmlSha256=Get-CollectorUpgradeHash ([Text.Encoding]::UTF8.GetBytes($newXml))
  $r.installationId=$receipt.runId;$r.taskDisabled=$true;$r.controlDisabled=$true;$r.status='COLLECTOR_RECOVERY_UPGRADED_DISABLED_RUNTIME_PENDING'
  Write-CollectorUpgradeNew $destination ([Text.Encoding]::UTF8.GetBytes(($r|ConvertTo-Json -Depth 10)))
 }catch{
  $r.status='REVIEW_REQUIRED';$r.failure=if($_.Exception.Message -cmatch '^[A-Z][A-Z0-9_]+$'){$_.Exception.Message}else{'UPGRADE_OPERATION_FAILED'}
  $r.failureType=$_.Exception.GetType().Name
  $rollbackErrors=@()
  try{if($actionChanged){Set-CollectorUpgradeAction $d}}catch{$rollbackErrors+='ACTION'}
  try{
   if($workerChanged){
    $restore=Join-Path $d.root ('restore-'+$r.runId+'.new');Write-CollectorUpgradeNew $restore ([IO.File]::ReadAllBytes((Join-Path $backup 'worker.ps1')))
    [IO.File]::Replace($restore,(Join-Path $d.root 'worker.ps1'),[Management.Automation.Language.NullString]::Value)
   }
  }catch{$rollbackErrors+='WORKER'}
  try{if($dockerChanged){$null=Invoke-CollectorDockerRead $exe @('update','--restart','no',$before.containerId);if((Get-CollectorDockerState).restartPolicy -cne 'no'){throw 'ROLLBACK_DOCKER'}}}catch{$rollbackErrors+='DOCKER'}
  try{
   if($actionChanged -or $workerChanged){
    Assert-DurableCollectorTask (Get-ScheduledTask -TaskName $d.name -TaskPath '\') $d
    if((Export-ScheduledTask -TaskName $d.name -TaskPath '\') -cne $oldXml -or (Get-FileHash -LiteralPath (Join-Path $d.root 'worker.ps1')).Hash -cne $receipt.workerSha256){throw 'ROLLBACK_VERIFY'}
    $r.rollbackVerified=$true
   }
  }catch{$rollbackErrors+='VERIFY'}
  if($rollbackErrors.Count){$r.rollbackFailure='UPGRADE_ROLLBACK_REVIEW_REQUIRED';$r.rollbackSteps=$rollbackErrors;$r.rollbackVerified=$false}
 }finally{if($lease){$lease.Dispose()}}
 return $r
}
$result=Invoke-CollectorRecoveryUpgrade $Mode
[IO.File]::WriteAllText($ResultPath,($result|ConvertTo-Json -Depth 12),[Text.UTF8Encoding]::new($false))
if($result.failure){throw ('COLLECTOR_UPGRADE_REVIEW_REQUIRED: '+$result.failure)}
