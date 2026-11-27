#Requires -Version 7.2
# Fixed read-only job: return only the compact supervised login report, never credentials.
param([Parameter(Mandatory)][string]$ResultPath,[ValidateSet('Observe','Apply','FailureFixture')][string]$Mode='Observe')
$ErrorActionPreference='Stop'
# Fixed local application negative checks. No valid credentials, browser cookies,
# session creation, broker requests, task changes or order endpoints.
function Invoke-SupervisedBoundaryProbe {
 $checks=@(
  @{name='STATUS_MISSING_TOKEN';method='Post';path='/api/v1/paytm/supervised/status';code=401},
  @{name='STATUS_WRONG_TOKEN';method='Post';path='/api/v1/paytm/supervised/status';code=401;wrongToken=$true},
  @{name='QUOTE_MISSING_TOKEN';method='Post';path='/api/v1/paytm/supervised/quote';code=401;body='{"securityId":2885}'},
  @{name='QUOTE_WRONG_TOKEN';method='Post';path='/api/v1/paytm/supervised/quote';code=401;wrongToken=$true;body='{"securityId":2885}'},
  @{name='REVIEW_QUOTE_MISSING_TOKEN';method='Post';path='/api/v1/paytm/supervised/review-quote';code=401;body='{"symbol":"RELIANCE"}'},
  @{name='REVIEW_QUOTE_WRONG_TOKEN';method='Post';path='/api/v1/paytm/supervised/review-quote';code=401;wrongToken=$true;body='{"symbol":"RELIANCE"}'},
  @{name='CALLBACK_WITHOUT_COOKIE';method='Get';path='/paytm/callback?state=fixture&requestToken=fixture';code=400},
  @{name='CALLBACK_REPEAT_WITHOUT_COOKIE';method='Get';path='/paytm/callback?state=fixture&requestToken=fixture';code=400},
  @{name='BROWSER_INVALID_CODE';method='Get';path='/paytm/supervised/browser?code=fixture';code=400}
 )
 $results=@();$watch=[Diagnostics.Stopwatch]::StartNew()
 foreach($check in $checks){
  $args=@{Uri=('http://127.0.0.1:8080'+$check.path);Method=$check.method;NoProxy=$true;TimeoutSec=8;MaximumRedirection=0;SkipHttpErrorCheck=$true;Headers=@{'X-MarketBrain-Paytm-Supervised'='supervised-paper'}}
  if($check.wrongToken){$args.Headers['X-MarketBrain-Paper-Read-Token']='invalid-fixture'}
  if($check.body){$args.ContentType='application/json';$args.Body=$check.body}
  try {
   $reply=Invoke-WebRequest @args
   $actual=[int]$reply.StatusCode
   $noStore=([string]($reply.Headers['Cache-Control'] -join ',') -match '(^|[, ])no-store($|[, ])')
   $results+=@{name=$check.name;expectedStatus=$check.code;actualStatus=$actual;noStore=$noStore;passed=($actual -eq $check.code -and $noStore)}
  }catch{$results+=@{name=$check.name;expectedStatus=$check.code;actualStatus=0;noStore=$false;passed=$false}}
 }
 $passed=(@($results|Where-Object passed -NE $true).Count -eq 0)
 return @{version=1;test='SUPERVISED_APPLICATION_BOUNDARY_PROBES';passed=$passed;checks=$results;elapsedSeconds=$watch.Elapsed.TotalSeconds;ordersEnabled=$false;brokerCredentialsUsed=$false;sessionCreated=$false;status=$(if($passed){'BOUNDARY_PROBES_PASSED_CALLBACK_LIFECYCLE_PENDING'}else{'BOUNDARY_PROBES_REVIEW_REQUIRED'})}
}

# Read-only checks with the existing local token; require a locked session first.
# Never start/login/unlock and never return the token or arbitrary response bodies.
function Invoke-SupervisedReviewBoundaryProbe {
 $r=@{test='DEPLOYED_REVIEW_QUOTE_BOUNDARY';passed=$false;checks=@();ordersEnabled=$false;sessionCreated=$false;failure=$null}
 $token=$null;$headers=$null
 try{
  $id=Invoke-UniverseDocker -Arguments @('ps','-q','--filter','label=com.docker.compose.service=marketbrain-service','--filter','status=running')
  if($id -cnotmatch '^[a-f0-9]{12,64}$'){throw 'REVIEW_APPLICATION_NOT_UNIQUE'}
  $token=Invoke-UniverseDocker -Arguments @('exec',$id,'printenv','MARKETBRAIN_PAPER_READ_TOKEN')
  if($token -cnotmatch '^[A-Za-z0-9_-]{32,128}$'){throw 'REVIEW_TOKEN_INVALID'}
  $headers=@{'X-MarketBrain-Paper-Read-Token'=$token;'X-MarketBrain-Paytm-Supervised'='supervised-paper'}
  $base='http://127.0.0.1:8080/api/v1/paytm/supervised/'
  $state=Invoke-RestMethod -Uri ($base+'status') -Method Post -NoProxy -TimeoutSec 8 -MaximumRedirection 0 -Headers $headers
  if($state.status -cne 'LOCKED' -or $state.ordersEnabled -ne $false){throw 'REVIEW_SESSION_MUST_BE_LOCKED'}
  foreach($h in @('NONE','Origin','Forwarded','X-Forwarded-For','X-Forwarded-Host','X-Forwarded-Proto')){
   $requestHeaders=$headers.Clone()
   if($h -ne 'NONE'){$requestHeaders[$h]='untrusted-fixture'}
   $reply=Invoke-WebRequest -Uri ($base+'review-quote') -Method Post -NoProxy -TimeoutSec 8 -MaximumRedirection 0 -SkipHttpErrorCheck -Headers $requestHeaders -ContentType 'application/json' -Body '{"symbol":"RELIANCE","securityId":1,"fresh":true,"lastPrice":999,"reviewEligible":true,"ordersEnabled":true}'
   if($reply.Content.Length -gt 4096){throw 'REVIEW_RESPONSE_TOO_LARGE'}
   $v=$reply.Content|ConvertFrom-Json
   $expected=if($h -eq 'NONE'){200}else{401}
   $expectedStatus=if($h -eq 'NONE'){'SUPERVISED_SESSION_LOCKED'}else{'UNAUTHORIZED'}
   $ok=([int]$reply.StatusCode -eq $expected -and $v.status -ceq $expectedStatus -and [string]($reply.Headers['Cache-Control'] -join ',') -match '(^|[, ])no-store($|[, ])')
   if($h -eq 'NONE'){$ok=$ok -and $v.reviewEligible -eq $false -and $v.ordersEnabled -eq $false}
   $r.checks+=@{name=('REVIEW_'+$h.Replace('-','_').ToUpperInvariant());passed=[bool]$ok;expectedStatus=$expected;actualStatus=[int]$reply.StatusCode}
  }
  $state=Invoke-RestMethod -Uri ($base+'status') -Method Post -NoProxy -TimeoutSec 8 -MaximumRedirection 0 -Headers $headers
  $r.finalLocked=($state.status -ceq 'LOCKED' -and $state.ordersEnabled -eq $false)
  $r.passed=($r.finalLocked -and @($r.checks|Where-Object passed -NE $true).Count -eq 0)
 }catch{$r.failure=if($_.Exception.Message -cmatch '^REVIEW_[A-Z_]+$'){$_.Exception.Message}else{'REVIEW_BOUNDARY_FAILED'}}
 finally{$token=$null;$headers=$null;$requestHeaders=$null}
 return $r
}

# Read-only projection of the newest delivery bundle; never return Docker output or credential material.
function Get-PaperDeliveryReport([string]$Directory='C:\MarketBrainData\Review') {
 $files=@(Get-ChildItem -LiteralPath $Directory -File | Where-Object {$_.Name -cmatch '^(paper-(delivery|publisher-preflight|publisher-rehearsal|publisher-install)-[0-9]{8}-[0-9]{6}-[a-f0-9]{12}|paytm-supervised-(login|deployment)-[a-f0-9]{32})\.json$'} | Sort-Object LastWriteTimeUtc -Descending | Select-Object -First 1)
 if($files.Count -ne 1 -or $files[0].Name -cnotmatch '^paper-(delivery|publisher-preflight|publisher-rehearsal|publisher-install)-'){return $null}
 $file=$files[0]
 if($file.Length -gt 2097152 -or $file.Attributes -band [IO.FileAttributes]::ReparsePoint){throw 'DELIVERY_REPORT_FILE_REJECTED'}
 $bytes=[IO.File]::ReadAllBytes($file.FullName)
 if($bytes.Length -gt 2097152){throw 'DELIVERY_REPORT_FILE_REJECTED'}
 $v=[Text.Encoding]::UTF8.GetString($bytes)|ConvertFrom-Json
 if($file.Name -cmatch '^paper-publisher-(preflight|rehearsal|install)-'){return Get-PublisherCatalogProjection $v $bytes $file.Name}
 if($v.version -cne 'PAPER_DELIVERY_BUNDLE_V1' -or $v.runId -cnotmatch '^[a-f0-9]{32}$'){throw 'DELIVERY_REPORT_SCOPE_REJECTED'}
 $safe=[ordered]@{version=$v.version;runId=$v.runId;failurePresent=([bool]$v.failure)}
 foreach($n in @('status')){if($v.$n -cnotmatch '^[A-Z_]{1,100}$'){throw 'DELIVERY_REPORT_FIELD_REJECTED'};$safe[$n]=$v.$n}
 foreach($n in @('syntheticDatabaseWritesPerformed','applicationDatabaseAccessed','actionExecutionEnabled')){if($v.$n -isnot [bool]){throw 'DELIVERY_REPORT_FIELD_REJECTED'};$safe[$n]=$v.$n}
 $safe.elapsedSeconds=[double]$v.elapsedSeconds
 foreach($phase in @('prepare','recover')) {
  $safe[$phase]=$null;$p=$v.$phase;if($null -eq $p){continue}
  $s=[ordered]@{}
  foreach($n in @('version','status','phase','schema','httpTransport')){if([string]$p.$n -cnotmatch '^[A-Za-z0-9_-]{1,100}$'){throw 'DELIVERY_REPORT_FIELD_REJECTED'};$s[$n]=$p.$n}
  foreach($n in @('applicationDatabaseAccessed','actionExecutionEnabled','syntheticDatabaseWritesPerformed')){if($p.$n -isnot [bool]){throw 'DELIVERY_REPORT_FIELD_REJECTED'};$s[$n]=$p.$n}
  foreach($n in @('checkCount','failedCount','elapsedSeconds','providerCalls','telegramCalls','modelCalls','cashPaise','reservedCashPaise','ledgerRevision','orderCount','fillCount','decisionCount','deliveryCount','pendingCount','uncertainCount')){
   if($p.PSObject.Properties[$n]){if($p.$n -is [string] -or $p.$n -is [bool] -or $null -eq $p.$n){throw 'DELIVERY_REPORT_FIELD_REJECTED'};$s[$n]=[decimal]$p.$n}
  }
  if(@($p.checks).Count -gt 64){throw 'DELIVERY_REPORT_FIELD_REJECTED'}
  $s.checks=@($p.checks|ForEach-Object {if($_.name -cnotmatch '^[a-z0-9_]{1,100}$' -or $_.passed -isnot [bool]){throw 'DELIVERY_REPORT_FIELD_REJECTED'};@{name=$_.name;passed=$_.passed;elapsedMillis=[double]$_.elapsedMillis}})
  $safe[$phase]=$s
 }
 $safe.cleanup=@($v.cleanup|ForEach-Object {if($_.action -cnotmatch '^[A-Z_]{1,100}$'){throw 'DELIVERY_REPORT_FIELD_REJECTED'};@{action=$_.action}})
 $safe.manifest=[ordered]@{}
 foreach($p in $v.manifest.PSObject.Properties){if($p.Name -eq 'codeRevision'){if($p.Value -cnotmatch '^[a-f0-9]{40}$'){throw 'DELIVERY_MANIFEST_REJECTED'};$safe.manifest.codeRevision=$p.Value;continue};if($p.Name -in @('dockerExecutable','verificationImage','databaseImage')){continue};if($p.Name -cnotmatch '^(ops/windows|marketbrain-service)/[A-Za-z0-9/_.-]{1,200}$' -or $p.Value -cnotmatch '^[A-Fa-f0-9]{64}$'){throw 'DELIVERY_MANIFEST_REJECTED'};$safe.manifest[$p.Name]=$p.Value}
 return @{test='PAPER_DELIVERY_REPORT_COLLECTION';passed=$true;status='REPORT_COLLECTED_NOT_AUTOMATICALLY_ACCEPTED';sourceFile=$file.Name;sha256=[Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($bytes));report=$safe;ordersEnabled=$false}
}

function Get-PublisherCatalogProjection($v,[byte[]]$bytes,[string]$name) {
 if($v.version -cnotin @('PAPER_PUBLISHER_PREFLIGHT_BUNDLE_V1','PAPER_PUBLISHER_REHEARSAL_BUNDLE_V1','PAPER_PUBLISHER_INSTALL_BUNDLE_V1') -or $v.runId -cnotmatch '^[a-f0-9]{32}$'){throw 'CATALOG_SCOPE_REJECTED'}
 function Project($value) {
  $out=[ordered]@{}
  foreach($key in @('commitOutcome','version','status','scope','stage','failureCode','schemaName','resolvedSchema','database','roleName','functionName','tableName','kind','failureType','sqlState')) {
   if($null -ne $value.$key){if([string]$value.$key -cnotmatch '^[A-Za-z0-9_:-]{1,150}$'){throw 'CATALOG_FIELD_REJECTED'};$out[$key]=$value.$key}
  }
  foreach($key in @('disabledStateVerified','verifyOnly','rollbackVerified','committed','loginEnabled','readOnly','repeatableRead','unchangedSessionIdentity','superuser','createRole','createDatabase','replication','bypassRls','login','publicDatabaseCreate','publicDatabaseTemp','currentRoleCreate','currentRoleOwnerMembership','publicCreate','present','rowSecurity','forceRowSecurity','currentRoleSelect','publicSelect','publicWrite','securityDefiner','publicExecute','catalogListBoundReached','publisherActivated','connectionAttempted','applicationDatabaseWritesPerformed','applicationWriterActivated','actionExecutionEnabled','applicationRestartRequested','databaseWritesRequested','timedOut')) {
   if($null -ne $value.$key){if($value.$key -isnot [bool]){throw 'CATALOG_FIELD_REJECTED'};$out[$key]=$value.$key}
  }
  foreach($key in @('databaseOid','serverVersionNumber','elapsedSeconds','providerCalls','telegramCalls','modelCalls','exitCode','stdoutCharacters','stderrCharacters')) {
   if($null -ne $value.$key){if($value.$key -is [string] -or $value.$key -is [bool]){throw 'CATALOG_FIELD_REJECTED'};$out[$key]=[decimal]$value.$key}
  };return $out
 }
 $safe=Project $v;$safe.runId=$v.runId;$safe.failurePresent=[bool]$v.failure;$safe.revision=$v.revision
 if($null -ne $v.runtimeConfigurationMatched){if($v.runtimeConfigurationMatched -isnot [bool]){throw 'CATALOG_FIELD_REJECTED'};$safe.runtimeConfigurationMatched=$v.runtimeConfigurationMatched}
 if($null -ne $v.revision -and $v.revision -cnotmatch '^[a-f0-9]{40}$'){throw 'CATALOG_REVISION_REJECTED'}
 $safe.catalog=Project $v.catalog
 if(@($v.steps).Count -gt 12){throw 'CATALOG_STEP_BOUND_REJECTED'}
 $safe.steps=@($v.steps|Where-Object {$null -ne $_}|ForEach-Object {Project $_})
 foreach($key in @('session','schema','target')){$safe.catalog[$key]=Project $v.catalog.$key}
 foreach($key in @('tables','proposedRoleCollisions','writerFunctionCollisions','publicCreateSchemas','publicCallableDefiners')) {
  if(@($v.catalog.$key).Count -gt 21){throw 'CATALOG_BOUND_REJECTED'};$safe.catalog[$key]=@($v.catalog.$key|Where-Object {$null -ne $_}|ForEach-Object {Project $_})
 }
 $safe.catalog.installationBlockers=@($v.catalog.installationBlockers|Where-Object {$null -ne $_}|ForEach-Object {if($_ -cnotmatch '^[A-Za-z0-9_:]{1,150}$'){throw 'CATALOG_BLOCKER_REJECTED'};$_})
 $safe.cleanup=Project $v.cleanup;$safe.manifest=[ordered]@{}
 foreach($p in $v.manifest.PSObject.Properties){if($p.Name -cnotmatch '^(compose\.paper-writer-preflight\.yaml|(?:ops/windows|marketbrain-service)/[A-Za-z0-9/_.-]{1,200})$' -or $p.Value -cnotmatch '^[A-Fa-f0-9]{64}$'){throw 'CATALOG_MANIFEST_REJECTED'};$safe.manifest[$p.Name]=$p.Value}
 if(@($safe.steps|Where-Object {$_.stage -eq 'configuration' -and $_.timedOut}).Count){$safe.dockerProbe=Get-PublisherDockerProbe}
 return @{test='PAPER_PUBLISHER_CATALOG_COLLECTION';passed=$true;status='REPORT_COLLECTED_NOT_AUTOMATICALLY_ACCEPTED';sourceFile=$name;sha256=[Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($bytes));report=$safe;ordersEnabled=$false}
}
function Get-PublisherDockerProbe {
 $rows=@();$d=@(Get-Command docker.exe -CommandType Application -ErrorAction SilentlyContinue)
 if(-not $d.Count){return @{available=$false;checks=@()}}
 foreach($a in @(@('compose','version','--short'),@('version','--format','{{.Server.Version}}'))) {
  $p=[Diagnostics.Process]::new();$p.StartInfo.FileName=$d[0].Source;$p.StartInfo.UseShellExecute=$false;$p.StartInfo.CreateNoWindow=$true
  $p.StartInfo.RedirectStandardOutput=$true;$p.StartInfo.RedirectStandardError=$true
  foreach($s in $a){[void]$p.StartInfo.ArgumentList.Add($s)}
  $w=[Diagnostics.Stopwatch]::StartNew()
  try{[void]$p.Start();$o=$p.StandardOutput.ReadToEndAsync();$e=$p.StandardError.ReadToEndAsync();$done=$p.WaitForExit(20000)
   if(-not $done){$p.Kill($true);[void]$p.WaitForExit(3000)}
   $drained=$o.Wait(3000) -and $e.Wait(3000)
   $rows+=@{stage=($a[0]+'-version');timedOut=(-not $done);exitCode=$(if($done){$p.ExitCode}else{-999});elapsedSeconds=$w.Elapsed.TotalSeconds;outputDrained=$drained}
  }catch{$rows+=@{stage=($a[0]+'-version');probeFailed=$true}}
  finally{try{if(-not $p.HasExited){$p.Kill($true)}}catch{};$p.Dispose()}
 };return @{available=$true;checks=$rows;configurationRead=$false;databaseAccessed=$false}
}

# Read-only, fixed-task diagnostics. Never return task arguments, event messages or credentials.
function Get-SupervisedGatewayTaskObservation {
 $r=@{readOnly=$true;ordersEnabled=$false;taskChanged=$false}
 try {
  $name='MarketBrain-Gateway-Supervisor-v1'
  $t=Get-ScheduledTask -TaskName $name -TaskPath '\' -ErrorAction Stop
  $i=Get-ScheduledTaskInfo -TaskName $name -TaskPath '\' -ErrorAction Stop
  $r.task=@{state=[string]$t.State;lastTaskResult=[long]$i.LastTaskResult;lastRunTime=$i.LastRunTime.ToString('o');missedRuns=[int]$i.NumberOfMissedRuns;settings=@{}}
  foreach($n in @('Enabled','AllowDemandStart','DisallowStartIfOnBatteries','StopIfGoingOnBatteries','RunOnlyIfIdle','RunOnlyIfNetworkAvailable','StartWhenAvailable')){$r.task.settings[$n]=[bool]$t.Settings.$n}
  $r.task.multipleInstances=[string]$t.Settings.MultipleInstances
  $r.task.executionTimeLimit=[string]$t.Settings.ExecutionTimeLimit
  $r.task.idle=@{stopOnIdleEnd=[bool]$t.Settings.IdleSettings.StopOnIdleEnd;restartOnIdle=[bool]$t.Settings.IdleSettings.RestartOnIdle}
 }catch{$r.taskError=$_.Exception.GetBaseException().GetType().Name}
 try {
  $r.batteries=@(Get-CimInstance Win32_Battery -ErrorAction Stop|Select-Object -First 4|ForEach-Object {@{batteryStatus=[int]$_.BatteryStatus;estimatedChargeRemaining=[int]$_.EstimatedChargeRemaining}})
 }catch{$r.batteryError=$_.Exception.GetBaseException().GetType().Name}
 try {
  $log=Get-WinEvent -ListLog 'Microsoft-Windows-TaskScheduler/Operational' -ErrorAction Stop
  $r.eventLogEnabled=[bool]$log.IsEnabled
  if($log.IsEnabled){
   # Filter by the fixed task on the event service; do not return arbitrary message text.
   $filter="*[System[TimeCreated[timediff(@SystemTime) <= 86400000]]] and *[EventData[Data[@Name='TaskName']='\MarketBrain-Gateway-Supervisor-v1']]"
   $r.events=@(Get-WinEvent -LogName $log.LogName -FilterXPath $filter -MaxEvents 24 -ErrorAction Stop|ForEach-Object {
    $e=@{id=$_.Id;recordId=$_.RecordId;timeCreated=$_.TimeCreated.ToString('o');codes=@{}}
    $xml=[xml]$_.ToXml()
    foreach($d in $xml.Event.EventData.Data){if($d.Name -in @('ResultCode','ErrorCode') -and [string]$d.'#text' -match '^(0x[0-9a-fA-F]+|[0-9]+)$'){$e.codes[$d.Name]=[string]$d.'#text'}}
    $e
   })
  }
 }catch{$r.eventError=$_.Exception.GetBaseException().GetType().Name}
 return $r
}

# Fixed supervised gateway reproduction. No task registration, password, key or policy changes.
function Invoke-SupervisedGatewayStartupProbe {
 $r=@{test='SUPERVISED_GATEWAY_STARTUP';passed=$false;ordersEnabled=$false;brokerCredentialsUsed=$false;started=$false;cleanupPassed=$false;samples=@();failure=$null}
 $root='C:\ProgramData\MarketBrainPaytmGateway\supervisor-v1'
 $work='C:\ProgramData\MarketBrainPaytmGateway\supervisor-work-v1'
 $name='MarketBrain-Gateway-Supervisor-v1';$installation='ea8b91471cf048aa97a0f6b939b355c7'
 function Read-StartupState([string]$Path){
  $s=$null;$reader=$null
  try{$s=[IO.File]::Open($Path,'Open','Read',([IO.FileShare]::ReadWrite -bor [IO.FileShare]::Delete));if($s.Length -gt 65536){throw 'STARTUP_STATE_TOO_LARGE'};$reader=[IO.StreamReader]::new($s);$reader.ReadToEnd()|ConvertFrom-Json}
  finally{if($reader){$reader.Dispose()};if($s){$s.Dispose()}}
 }
 function Get-StartupListeners {@([Net.NetworkInformation.IPGlobalProperties]::GetIPGlobalProperties().GetActiveTcpListeners()|Where-Object Port -EQ 18889)}
 try{
  $t=Get-ScheduledTask -TaskName $name -TaskPath '\' -ErrorAction Stop
  if($t.Description -cne "MarketBrain locked supervisor $installation" -or $t.State -ne 'Disabled'){throw 'STARTUP_TASK_NOT_DISABLED_OR_OWNED'}
  $text="&([scriptblock]::Create([IO.File]::ReadAllText('$root\runner.ps1')))"
  $expected='-NoLogo -NoProfile -NonInteractive -EncodedCommand '+[Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($text))
  $a=@($t.Actions)
  if($a.Count -ne 1 -or $a[0].Execute -cne 'C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe' -or $a[0].Arguments -cne $expected -or $a[0].WorkingDirectory -cne $root){throw 'STARTUP_TASK_ACTION_DRIFT'}
  $sid=$t.Principal.UserId
  if($sid -notmatch '^S-1-'){$sid=([Security.Principal.NTAccount]::new($sid)).Translate([Security.Principal.SecurityIdentifier]).Value}
  if($sid -cne 'S-1-5-21-3041730714-102984520-3202743044-1010' -or [string]$t.Principal.RunLevel -cne 'Limited' -or [string]$t.Principal.LogonType -cne 'Password'){throw 'STARTUP_PRINCIPAL_DRIFT'}
  $collector=Get-ScheduledTask -TaskName 'MarketBrain-Health-Collector-v1' -ErrorAction SilentlyContinue
  if($collector -and $collector.State -ne 'Disabled'){throw 'STARTUP_COLLECTOR_ACTIVE'}
  $m=Read-StartupState "$root/manifest.json"
  if($m.installationId -cne $installation -or $m.version -ne 1 -or $m.transportVersion -ne 1){throw 'STARTUP_MANIFEST_DRIFT'}
  foreach($file in @('host.ps1','runner.ps1','native.dll','transport.ps1','gateway.ps1','transport.dll')){if((Get-FileHash -LiteralPath "$root/$file").Hash -cne $m.hashes.$file){throw 'STARTUP_SOURCE_DRIFT'}}
  if((Read-StartupState "$root/control.json").mode -cne 'LOCKED' -or (Read-StartupState "$root/transport-control.json").mode -cne 'ENABLED'){throw 'STARTUP_CONTROL_DRIFT'}
  if((Test-Path "$work/blocked.json") -or (Test-Path "$work/startup-failure.json")){throw 'STARTUP_EXISTING_FAILURE'}
  if(@(Get-StartupListeners).Count){throw 'STARTUP_EXISTING_LISTENER'}
  $previous=(Read-StartupState "$work/status.json").instanceId
  $r.before=Get-SupervisedGatewayTaskObservation
  $r.started=$true
  $null=Enable-ScheduledTask -TaskName $name -TaskPath '\'
  Start-ScheduledTask -TaskName $name -TaskPath '\'
  $watch=[Diagnostics.Stopwatch]::StartNew();$lastSequence=$null
  do{
   Start-Sleep -Seconds 2
   $v=Read-StartupState "$work/status.json"
   $t=Get-ScheduledTask -TaskName $name -TaskPath '\';$i=Get-ScheduledTaskInfo -TaskName $name -TaskPath '\'
   $phase=if([string]$v.phase -cmatch '^[A-Z_]{1,60}$'){[string]$v.phase}else{'INVALID'}
   $fresh=($v.instanceId -cne $previous -and $v.instanceId -cmatch '^[a-f0-9]{32}$')
   $r.samples+=@{seconds=[math]::Round($watch.Elapsed.TotalSeconds,2);newInstance=$fresh;phase=$phase;sequence=[long]$v.sequence;taskState=[string]$t.State;taskResult=[long]$i.LastTaskResult}
   if($fresh -and $phase -eq 'BLOCKED'){throw 'STARTUP_WORKER_BLOCKED'}
   if($fresh -and $phase -eq 'TRANSPORT_READY' -and $v.ordersEnabled -eq $false -and $v.brokerReady -eq $false -and $t.State -eq 'Running' -and @(Get-StartupListeners).Count -gt 0){
    if($null -ne $lastSequence -and $v.sequence -gt $lastSequence){$r.passed=$true;break};$lastSequence=$v.sequence
   }
  }while($watch.Elapsed.TotalSeconds -lt 60)
  if(-not $r.passed){throw 'STARTUP_NO_FRESH_READY_HEARTBEAT'}
 }catch{$r.failure=if($_.Exception.Message -cmatch '^STARTUP_[A-Z_]+$'){$_.Exception.Message}else{'STARTUP_PROBE_FAILED'};$r.errorType=$_.Exception.GetBaseException().GetType().Name}
 finally{
  if($r.started){
   try{
    $r.beforeCleanup=Get-SupervisedGatewayTaskObservation
    Stop-ScheduledTask -TaskName $name -TaskPath '\'
    $null=Disable-ScheduledTask -TaskName $name -TaskPath '\'
    $stop=[Diagnostics.Stopwatch]::StartNew()
    do{if((Get-ScheduledTask -TaskName $name -TaskPath '\').State -eq 'Disabled' -and @(Get-StartupListeners).Count -eq 0){$r.cleanupPassed=$true;break};Start-Sleep -Seconds 1}while($stop.Elapsed.TotalSeconds -lt 30)
   }catch{$r.cleanupError=$_.Exception.GetBaseException().GetType().Name}
   if(-not $r.cleanupPassed){$r.passed=$false;$r.failure='STARTUP_CLEANUP_NOT_VERIFIED'}
  }
 }
 return $r
}

# Fixed saved-universe read. Only the existing local paper read token is read into
# process memory. No broker login, gateway changes, database writes or orders.
function Invoke-UniverseDocker([string[]]$Arguments) {
 $exe=(Get-Command docker.exe -CommandType Application -ErrorAction Stop|Select-Object -First 1).Source
 $info=[Diagnostics.ProcessStartInfo]::new();$info.FileName=$exe;$info.UseShellExecute=$false;$info.CreateNoWindow=$true
 $info.RedirectStandardOutput=$true;$info.RedirectStandardError=$true
 foreach($arg in (@('--host','npipe:////./pipe/docker_engine')+$Arguments)){$info.ArgumentList.Add($arg)}
 $p=[Diagnostics.Process]::new();$p.StartInfo=$info
 try{
  $null=$p.Start();$stdout=$p.StandardOutput.ReadToEndAsync();$stderr=$p.StandardError.ReadToEndAsync()
  if(-not $p.WaitForExit(10000)){try{$p.Kill($true)}catch{};throw 'UNIVERSE_DOCKER_TIMEOUT'}
  if($p.ExitCode -ne 0){throw 'UNIVERSE_DOCKER_FAILED'}
  $value=$stdout.GetAwaiter().GetResult()
  if($value.Length -gt 4096){throw 'UNIVERSE_DOCKER_OUTPUT_REJECTED'}
  return $value.Trim()
 }finally{$p.Dispose()}
}
function Invoke-SupervisedUniverseProbe {
 $r=[ordered]@{version=1;test='SUPERVISED_SAVED_UNIVERSE_PROBE';passed=$false;ordersEnabled=$false;brokerCredentialsUsed=$false;failure=$null}
 $token=$null;$headers=$null
 try{
  $id=Invoke-UniverseDocker -Arguments @('ps','-q','--filter','label=com.docker.compose.service=marketbrain-service','--filter','status=running')
  if($id -cnotmatch '^[a-f0-9]{12,64}$'){throw 'UNIVERSE_APPLICATION_NOT_UNIQUE'}
  $token=Invoke-UniverseDocker -Arguments @('exec',$id,'printenv','MARKETBRAIN_PAPER_READ_TOKEN')
  if($token -cnotmatch '^[A-Za-z0-9_-]{32,128}$'){throw 'UNIVERSE_LOCAL_TOKEN_INVALID'}
  $headers=@{'X-MarketBrain-Paper-Read-Token'=$token;'X-MarketBrain-Paytm-Supervised'='supervised-paper'}
  $v=Invoke-RestMethod -Uri 'http://127.0.0.1:8080/api/v1/paytm/supervised/universe-match' -Method Post -NoProxy -TimeoutSec 10 -MaximumRedirection 0 -Headers $headers -ContentType 'application/json' -Body '{"symbol":"RELIANCE"}'
  if($v.status -cnotmatch '^[A-Z_]{1,100}$' -or $v.ordersEnabled -ne $false -or $v.snapshotMatched -isnot [bool]){throw 'UNIVERSE_RESPONSE_INVALID'}
  $safe=[ordered]@{status=[string]$v.status;snapshotMatched=$v.snapshotMatched;ordersEnabled=$false}
  $patterns=@{symbol='^RELIANCE$';snapshotId='^[a-f0-9-]{36}$';observedOn='^[0-9]{4}-[0-9]{2}-[0-9]{2}$';isin='^[A-Z]{2}[A-Z0-9]{9}[0-9]$';instrumentId='^[1-9][0-9]{0,18}$'}
  foreach($name in $patterns.Keys){if($v.PSObject.Properties[$name]){if([string]$v.$name -cnotmatch $patterns[$name]){throw 'UNIVERSE_RESPONSE_INVALID'};$safe[$name]=$v.$name}}
  foreach($name in @('currentMembershipVerified','providerIsinVerified')){if($v.PSObject.Properties[$name]){if($v.$name -isnot [bool] -or $v.$name){throw 'UNIVERSE_RESPONSE_INVALID'};$safe[$name]=$false}}
  $r.universeMatch=$safe
  $r.passed=($v.status -ceq 'LOCAL_SNAPSHOT_SYMBOL_ISIN_MATCHED' -and $v.snapshotMatched -eq $true -and $v.symbol -ceq 'RELIANCE')
 }catch{$r.failure=if($_.Exception.Message -cmatch '^UNIVERSE_[A-Z_]+$'){$_.Exception.Message}else{'UNIVERSE_PROBE_FAILED'}}
 finally{$token=$null;$headers=$null}
 return $r
}

# Fixed local negative lifecycle. Never follow a broker redirect or send a successful callback.
function Invoke-LifecycleHttp($Client,[string]$Path,[string]$Token,[string]$Body,[string]$Cookie) {
 if($Path -cnotmatch '^(/api/v1/paytm/supervised/(status|start|lock)|/paytm/supervised/browser\?code=[A-Za-z0-9_-]{43}|/paytm/callback\?success=false&state=[A-Za-z0-9_-]{43})$'){throw 'LIFECYCLE_PATH_REJECTED'}
 $method=if($Path.StartsWith('/api/')){[Net.Http.HttpMethod]::Post}else{[Net.Http.HttpMethod]::Get}
 $req=[Net.Http.HttpRequestMessage]::new($method,('http://127.0.0.1:8080'+$Path));$reply=$null
 try{
  if($Path.StartsWith('/api/')){$req.Headers.Add('X-MarketBrain-Paper-Read-Token',$Token);$req.Headers.Add('X-MarketBrain-Paytm-Supervised','supervised-paper')}
  if($Cookie){$req.Headers.Add('Cookie',('marketbrain_paytm_supervised='+$Cookie))}
  if($Body){$req.Content=[Net.Http.StringContent]::new($Body,[Text.Encoding]::UTF8,'application/json')}
  $reply=$Client.SendAsync($req).GetAwaiter().GetResult()
  $content=$reply.Content.ReadAsStringAsync().GetAwaiter().GetResult()
  $cookies=if($reply.Headers.Contains('Set-Cookie')){@($reply.Headers.GetValues('Set-Cookie'))}else{@()}
  return @{code=[int]$reply.StatusCode;content=$content;cookies=$cookies;noStore=($reply.Headers.CacheControl.NoStore -eq $true)}
 }finally{if($reply){$reply.Dispose()};$req.Dispose()}
}
function Invoke-SupervisedLifecycleProbe {
 $r=[ordered]@{version=1;test='SUPERVISED_LOCAL_NEGATIVE_LIFECYCLE';passed=$false;checks=@();failure=$null;finalLocked=$false;ordersEnabled=$false;brokerCredentialsUsed=$false;brokerRedirectsFollowed=$false;clockSource='SYNTHETIC_ANCHOR_FOR_LOCAL_NEGATIVES_ONLY'}
 $client=$null;$token=$null;$owned=$false;$cookie=$null;$path=$null
 function Check-Lifecycle($reply,[int]$code,[string]$name){
  $ok=($reply.code -eq $code -and $reply.noStore)
  $r.checks+=@{name=$name;expectedStatus=$code;actualStatus=$reply.code;noStore=$reply.noStore;passed=$ok}
  if(-not $ok){throw 'LIFECYCLE_UNEXPECTED_RESPONSE'}
 }
 function Read-LifecycleState([string]$expected,[string]$name){
  $reply=Invoke-LifecycleHttp $client '/api/v1/paytm/supervised/status' $token $null $null
  Check-Lifecycle $reply 200 $name
  $v=$reply.content|ConvertFrom-Json
  if($v.status -cne $expected -or $v.ordersEnabled -ne $false -or $v.readAccessVerified -ne $false){throw 'LIFECYCLE_STATE_REJECTED'}
 }
 try{
  $id=Invoke-UniverseDocker -Arguments @('ps','-q','--filter','label=com.docker.compose.service=marketbrain-service','--filter','status=running')
  if($id -cnotmatch '^[a-f0-9]{12,64}$'){throw 'LIFECYCLE_APPLICATION_NOT_UNIQUE'}
  $token=Invoke-UniverseDocker -Arguments @('exec',$id,'printenv','MARKETBRAIN_PAPER_READ_TOKEN')
  if($token -cnotmatch '^[A-Za-z0-9_-]{32,128}$'){throw 'LIFECYCLE_TOKEN_INVALID'}
  $handler=[Net.Http.HttpClientHandler]::new();$handler.UseProxy=$false;$handler.AllowAutoRedirect=$false;$handler.UseCookies=$false
  $client=[Net.Http.HttpClient]::new($handler);$client.Timeout=[TimeSpan]::FromSeconds(8);$client.MaxResponseContentBufferSize=8192
  Read-LifecycleState 'LOCKED' 'INITIAL_LOCKED'
  # Test-only anchor; no freshness claim or exchange is possible with success=false callbacks.
  $body='{"apiKey":"local-negative-fixture","apiSecret":"not-a-broker-secret","vpsEpochMilliseconds":1795219200000}'
  $owned=$true
  $reply=Invoke-LifecycleHttp $client '/api/v1/paytm/supervised/start' $token $body $null
  Check-Lifecycle $reply 200 'LOCAL_ATTEMPT_CREATED'
  $v=$reply.content|ConvertFrom-Json
  if($v.ordersEnabled -ne $false -or $v.browserUrl -cnotmatch '^http://127\.0\.0\.1:8080(/paytm/supervised/browser\?code=[A-Za-z0-9_-]{43})$'){throw 'LIFECYCLE_START_REJECTED'}
  $path=$Matches[1];$state=$path.Split('=')[-1]
  $reply=Invoke-LifecycleHttp $client $path $token $null $null
  Check-Lifecycle $reply 303 'BROWSER_LINK_CONSUMED_LOCALLY'
  $bindings=@($reply.cookies|Where-Object {$_ -cmatch '^marketbrain_paytm_supervised=[A-Za-z0-9_-]{43};'})
  if($bindings.Count -ne 1){throw 'LIFECYCLE_COOKIE_REJECTED'}
  $cookie=$bindings[0].Split(';')[0].Split('=')[1]
  Check-Lifecycle (Invoke-LifecycleHttp $client $path $token $null $null) 400 'BROWSER_LINK_REPLAY_REJECTED'
  $callback='/paytm/callback?success=false&state='+$state
  $wrong=if($cookie -ceq ('A'*43)){'B'*43}else{'A'*43}
  Check-Lifecycle (Invoke-LifecycleHttp $client $callback $token $null $wrong) 400 'WRONG_COOKIE_REJECTED'
  Read-LifecycleState 'AWAITING_CALLBACK' 'WRONG_COOKIE_PRESERVES_OWNER'
  Check-Lifecycle (Invoke-LifecycleHttp $client $callback $token $null $cookie) 400 'OWNER_CANCELLATION_REJECTED'
  Read-LifecycleState 'LOCKED' 'CANCELLED_ATTEMPT_LOCKED'
  Check-Lifecycle (Invoke-LifecycleHttp $client $callback $token $null $cookie) 400 'CANCELLED_CALLBACK_REPLAY_REJECTED'
  $reply=Invoke-LifecycleHttp $client '/api/v1/paytm/supervised/start' $token $body $null
  Check-Lifecycle $reply 200 'NEW_ATTEMPT_AFTER_CANCELLATION'
  Check-Lifecycle (Invoke-LifecycleHttp $client $path $token $null $null) 400 'OLD_BROWSER_LINK_REJECTED'
  Read-LifecycleState 'AWAITING_BROWSER' 'NEW_ATTEMPT_PRESERVED'
  $r.passed=$true
 }catch{$r.failure=if($_.Exception.Message -cmatch '^LIFECYCLE_[A-Z_]+$'){$_.Exception.Message}else{'LIFECYCLE_PROBE_FAILED'}}
 finally{
  if($owned){try{
   $reply=Invoke-LifecycleHttp $client '/api/v1/paytm/supervised/lock' $token $null $null
   Check-Lifecycle $reply 200 'FINAL_LOCK'
   Read-LifecycleState 'LOCKED' 'FINAL_LOCK_VERIFIED';$r.finalLocked=$true
  }catch{$r.passed=$false;$r.failure='LIFECYCLE_CLEANUP_NOT_VERIFIED'}}
  if($client){$client.Dispose()};$token=$null;$cookie=$null;$path=$null
 }
 return $r
}

function Get-PaytmQuoteBatchAssessment {
 param([object[]]$Samples,[int]$SecurityId,[switch]$RequireFresh)
 if($Samples.Count -ne 3){throw 'SUPERVISED_QUOTE_BATCH_COUNT'}
 $fresh=0;$stale=0;$missing=0;$lastObserved=0
 foreach($q in $Samples){
  if($q.ordersEnabled -ne $false -or $q.fresh -isnot [bool]){throw 'SUPERVISED_QUOTE_BATCH_SCOPE'}
  if($q.status -eq 'NO_QUOTE'){if($q.fresh){throw 'SUPERVISED_QUOTE_BATCH_INVALID'};$missing++;continue}
  if($q.status -notin @('FRESH_QUOTE_OBSERVED','STALE_QUOTE') -or $q.securityId -ne $SecurityId -or $q.exchange -cne 'NSE' -or $q.scripType -cne 'EQUITY' -or $q.timestampEpoch -cne 'PAYTM_1980_SECONDS'){throw 'SUPERVISED_QUOTE_BATCH_IDENTITY'}
  foreach($n in @('observedEpochMilliseconds','tradeEpochMilliseconds','ageMilliseconds','lastPrice')){
   if($null -eq $q.$n -or $q.$n -is [string] -or $q.$n -is [bool]){throw 'SUPERVISED_QUOTE_BATCH_INVALID'}
  }
  if($q.lastPrice -le 0 -or $q.observedEpochMilliseconds -le $lastObserved -or $q.ageMilliseconds -lt 0 -or ($q.observedEpochMilliseconds-$q.tradeEpochMilliseconds) -ne $q.ageMilliseconds){throw 'SUPERVISED_QUOTE_BATCH_INVALID'}
  $lastObserved=$q.observedEpochMilliseconds
  if($q.status -eq 'FRESH_QUOTE_OBSERVED'){
   if(-not $q.fresh -or $q.ageMilliseconds -gt 15000){throw 'SUPERVISED_QUOTE_BATCH_FALSE_FRESH'};$fresh++
  }else{if($q.fresh -or $q.ageMilliseconds -le 15000){throw 'SUPERVISED_QUOTE_BATCH_FALSE_STALE'};$stale++}
 }
 return @{status=$(if($fresh -eq 3){'THREE_FRESH_MAPPED_QUOTES'}else{'FRESHNESS_PENDING'});passed=($fresh -eq 3);freshCount=$fresh;staleCount=$stale;missingCount=$missing;sampleCount=3;securityId=$SecurityId;strictFreshRequired=[bool]$RequireFresh;ordersEnabled=$false}
}


function Resolve-PaytmQuoteMappingFromCsv {
 param([Parameter(Mandatory)][string]$Csv,[Parameter(Mandatory)][string]$Symbol,[Parameter(Mandatory)][string]$Sha256)
 if($Symbol -cnotmatch '^[A-Z0-9][A-Z0-9&-]{0,29}$' -or $Sha256 -cnotmatch '^[A-F0-9]{64}$'){throw 'SUPERVISED_MAPPING_INPUT_INVALID'}
 if([Text.Encoding]::UTF8.GetByteCount($Csv) -gt 4194304){throw 'SUPERVISED_MAPPING_TOO_LARGE'}
 $rows=@(ConvertFrom-Csv -InputObject $Csv -ErrorAction Stop)
 if($rows.Count -eq 0 -or $rows.Count -gt 30000){throw 'SUPERVISED_MAPPING_ROWS_INVALID'}
 foreach($name in @('security_id','symbol','exchange','series','segment','instrument_type')){
  if(-not $rows[0].PSObject.Properties[$name]){throw 'SUPERVISED_MAPPING_SCHEMA_INVALID'}
 }
 $matchingRows=@($rows|Where-Object {$_.symbol -ceq $Symbol -and $_.exchange -ceq 'NSE' -and $_.series -ceq 'EQ' -and $_.segment -ceq 'E' -and $_.instrument_type -ceq 'ES'})
 if($matchingRows.Count -ne 1 -or $matchingRows[0].security_id -cnotmatch '^[1-9][0-9]{0,7}$'){throw 'SUPERVISED_MAPPING_NOT_UNIQUE'}
 $id=$matchingRows[0].security_id
 if(@($rows|Where-Object {$_.exchange -ceq 'NSE' -and $_.security_id -ceq $id}).Count -ne 1){throw 'SUPERVISED_MAPPING_ID_CONFLICT'}
 return [ordered]@{symbol=$Symbol;securityId=[int]$id;exchange='NSE';series='EQ';segment='E';instrumentType='ES';source='PAYTM_PUBLIC_EQUITY_MASTER';sha256=$Sha256;localUniverseVerified=$false}
}
function Get-PaytmQuoteMapping {
 param([Parameter(Mandatory)][string]$Symbol)
 # Public reference data only. No broker credentials; no fallback URL or redirects.
 $handler=[Net.Http.HttpClientHandler]::new();$handler.AllowAutoRedirect=$false
 $client=[Net.Http.HttpClient]::new($handler);$client.Timeout=[TimeSpan]::FromSeconds(25);$client.MaxResponseContentBufferSize=4194304
 $response=$null
 try {
  $response=$client.GetAsync('https://developer.paytmmoney.com/data/v1/scrips/equity_security_master.csv').GetAwaiter().GetResult()
  if([int]$response.StatusCode -ne 200){throw 'SUPERVISED_MAPPING_DOWNLOAD_FAILED'}
  $bytes=$response.Content.ReadAsByteArrayAsync().GetAwaiter().GetResult()
  $hash=[Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($bytes))
  $csv=[Text.UTF8Encoding]::new($false,$true).GetString($bytes).TrimStart([char]0xFEFF)
  Resolve-PaytmQuoteMappingFromCsv -Csv $csv -Symbol $Symbol -Sha256 $hash
 } catch {
  if($_.Exception.Message -cmatch '^SUPERVISED_MAPPING_[A-Z_]+$'){throw}
  throw 'SUPERVISED_MAPPING_DOWNLOAD_OR_PARSE_FAILED'
 } finally {if($response){$response.Dispose()};$client.Dispose();$handler.Dispose()}
}

# Public master plus existing saved-universe endpoint. No broker login or writes.
function Invoke-SupervisedIdentityProbe {
 $r=[ordered]@{test='PROVIDER_AND_SAVED_UNIVERSE_IDENTITY';passed=$false;ordersEnabled=$false;currentMembershipVerified=$false;providerIsinVerified=$false;failure=$null}
 try{
  $m=Get-PaytmQuoteMapping -Symbol RELIANCE
  $u=Invoke-SupervisedUniverseProbe
  if(-not $u.passed -or $u.universeMatch.symbol -cne $m.symbol -or $m.exchange -cne 'NSE' -or $m.series -cne 'EQ' -or $m.instrumentType -cne 'ES'){throw 'IDENTITY_CORROBORATION_FAILED'}
  # Explicit fields only: no raw CSV, local token, or unknown provider values.
  if($m.symbol -cne 'RELIANCE' -or [string]$m.securityId -cnotmatch '^[1-9][0-9]{0,7}$' -or $m.sha256 -cnotmatch '^[A-F0-9]{64}$'){throw 'IDENTITY_MAPPING_REJECTED'}
  $r.mapping=@{symbol=$m.symbol;securityId=[int]$m.securityId;exchange='NSE';series='EQ';sha256=$m.sha256;source='PAYTM_PUBLIC_EQUITY_MASTER'}
  $r.savedUniverse=$u.universeMatch
  $r.passed=$true;$r.status='SYMBOL_CORROBORATED_FULL_IDENTITY_PENDING'
 }catch{$r.status='REVIEW_REQUIRED';$r.failure='IDENTITY_PROBE_FAILED'}
 return $r
}

$script:deployedQualitySource=@'
import java.nio.file.*;
import java.net.*;
import java.time.*;
import java.util.*;
import java.util.jar.*;
import java.lang.reflect.*;
import java.security.*;
import java.net.http.*;
import java.nio.ByteBuffer;
import java.nio.charset.StandardCharsets;
import java.util.concurrent.*;
import javax.net.ssl.*;

/** Isolated synthetic inputs against the copied deployed assessor; no application boot or networking. */
public final class DeployedQuoteQualityProbe {
    static final class FixtureHttp extends HttpClient {
        String body;int calls;
        public Optional<java.net.CookieHandler> cookieHandler(){return Optional.empty();}
        public Optional<Duration> connectTimeout(){return Optional.empty();}
        public Redirect followRedirects(){return Redirect.NEVER;}
        public Optional<ProxySelector> proxy(){return Optional.empty();}
        public SSLContext sslContext(){try{return SSLContext.getDefault();}catch(Exception e){throw new IllegalStateException(e);}}
        public SSLParameters sslParameters(){return new SSLParameters();}
        public Optional<Authenticator> authenticator(){return Optional.empty();}
        public Version version(){return Version.HTTP_1_1;}
        public Optional<Executor> executor(){return Optional.empty();}
        public <T> HttpResponse<T> send(HttpRequest request,HttpResponse.BodyHandler<T> handler){
            calls++;
            if(!request.uri().toString().equals("https://developer.paytmmoney.com/data/v1/price/live?mode=LTP&pref=NSE:2885:EQUITY")||!request.method().equals("GET")||!request.headers().firstValue("x-jwt-token").orElse("").equals("fixture-read-only"))throw new IllegalStateException("REQUEST_SCOPE_FAILED");
            var headers=HttpHeaders.of(Map.of(),(a,b)->true);
            var info=new HttpResponse.ResponseInfo(){public int statusCode(){return 200;}public HttpHeaders headers(){return headers;}public Version version(){return Version.HTTP_1_1;}};
            var sub=handler.apply(info);
            sub.onSubscribe(new Flow.Subscription(){public void request(long n){}public void cancel(){}});
            sub.onNext(List.of(ByteBuffer.wrap(body.getBytes(StandardCharsets.UTF_8))));sub.onComplete();
            T value=sub.getBody().toCompletableFuture().join();
            return new HttpResponse<T>(){
                public int statusCode(){return 200;}public HttpRequest request(){return request;}public Optional<HttpResponse<T>> previousResponse(){return Optional.empty();}
                public HttpHeaders headers(){return headers;}public T body(){return value;}public Optional<SSLSession> sslSession(){return Optional.of(sslContext().createSSLEngine().getSession());}
                public URI uri(){return request.uri();}public Version version(){return Version.HTTP_1_1;}
            };
        }
        public <T> CompletableFuture<HttpResponse<T>> sendAsync(HttpRequest r,HttpResponse.BodyHandler<T> h){throw new UnsupportedOperationException();}
        public <T> CompletableFuture<HttpResponse<T>> sendAsync(HttpRequest r,HttpResponse.BodyHandler<T> h,HttpResponse.PushPromiseHandler<T> p){throw new UnsupportedOperationException();}
        public void shutdownNow(){}
    }
    record Case(String name, String body, String expected, boolean fresh) {}
    static final Instant NOW=Instant.parse("2026-11-25T04:00:00Z");
    static final long RAW=NOW.getEpochSecond()-315532800L;
    static String row(String id,String mode,String found,String price,String time) {
        return "{\"security_id\":"+id+",\"mode\":\""+mode+"\",\"found\":"+found+",\"last_price\":"+price+",\"last_trade_time\":"+time+"}";
    }
    static String body(String row){return "{\"data\":["+row+"]}";}
    static Case c(String name,String row,String status){return new Case(name,body(row),status,false);}
    static List<Case> cases(){
        String good=row("2885","LTP","true","100",Long.toString(RAW));
        return List.of(
            new Case("fresh",body(good),"FRESH_QUOTE_OBSERVED",true),
            new Case("exact15Seconds",body(row("2885","LTP","true","100",Long.toString(RAW-15))),"FRESH_QUOTE_OBSERVED",true),
            c("stale",row("2885","LTP","true","100",Long.toString(RAW-16)),"STALE_QUOTE"),
            c("future",row("2885","LTP","true","100",Long.toString(RAW+1)),"FUTURE_TIMESTAMP"),
            c("notFound",row("2885","LTP","false","100",Long.toString(RAW)),"NO_QUOTE"),
            c("wrongId",row("1","LTP","true","100",Long.toString(RAW)),"MALFORMED_QUOTE"),
            c("textId",row("\"2885\"","LTP","true","100",Long.toString(RAW)),"MALFORMED_QUOTE"),
            c("wrongMode",row("2885","FULL","true","100",Long.toString(RAW)),"MALFORMED_QUOTE"),
            c("textFound",row("2885","LTP","\"true\"","100",Long.toString(RAW)),"MALFORMED_QUOTE"),
            c("missingPrice",good.replace(",\"last_price\":100",""),"MALFORMED_QUOTE"),
            c("textPrice",row("2885","LTP","true","\"100\"",Long.toString(RAW)),"MALFORMED_QUOTE"),
            c("zeroPrice",row("2885","LTP","true","0",Long.toString(RAW)),"MALFORMED_QUOTE"),
            c("negativePrice",row("2885","LTP","true","-1",Long.toString(RAW)),"MALFORMED_QUOTE"),
            c("excessivePrice",row("2885","LTP","true","1000000001",Long.toString(RAW)),"MALFORMED_QUOTE"),
            c("missingTime",good.replace(",\"last_trade_time\":"+RAW,""),"MISSING_OR_INVALID_TIMESTAMP"),
            c("textTime",row("2885","LTP","true","100","\""+RAW+"\""),"MISSING_OR_INVALID_TIMESTAMP"),
            c("millisecondsTime",row("2885","LTP","true","100",Long.toString(NOW.toEpochMilli())),"MISSING_OR_INVALID_TIMESTAMP"),
            c("overflowTime",row("2885","LTP","true","100","99999999999999999999999"),"MISSING_OR_INVALID_TIMESTAMP"),
            new Case("duplicate",body(good+","+good),"MALFORMED_QUOTE",false),
            new Case("emptyData","{\"data\":[]}","MALFORMED_QUOTE",false),
            new Case("missingData","{}","MALFORMED_QUOTE",false),
            new Case("providerError","{\"error\":\"fixture\",\"data\":["+good+"]}","MALFORMED_QUOTE",false),
            new Case("nullReply","null","MALFORMED_QUOTE",false),
            new Case("arrayReply","[]","MALFORMED_QUOTE",false));
    }
    public static void main(String[] args)throws Exception{
        Path artifact=Path.of(args[0]), dir=Files.createTempDirectory(artifact.getParent(),"quality-classes-");
        String entry="BOOT-INF/classes/in/marketbrain/marketdata/paytm/PaytmQuoteProbe.class";
        String classHash=null;List<URL> urls=new ArrayList<>();urls.add(dir.toUri().toURL());int libraries=0;
        try{
            try(JarFile jar=new JarFile(artifact.toFile())){
                var all=jar.entries();
                while(all.hasMoreElements()){
                    var e=all.nextElement();String name=e.getName();
                    boolean assessor=name.equals(entry), client=name.matches("BOOT-INF/classes/in/marketbrain/marketdata/paytm/PaytmSupervisedClient(\\$[A-Za-z0-9]+)?\\.class"), lib=name.matches("BOOT-INF/lib/jackson-(core|databind|annotations)-[0-9][A-Za-z0-9._-]*\\.jar");
                    if(!assessor&&!client&&!lib)continue;
                    if(e.getSize()<1||e.getSize()>8_000_000)throw new IllegalStateException("ENTRY_SIZE_REJECTED");
                    byte[] bytes;try(var in=jar.getInputStream(e)){bytes=in.readNBytes(8_000_001);}
                    if(bytes.length!=e.getSize())throw new IllegalStateException("ENTRY_READ_REJECTED");
                    Path target=dir.resolve((assessor||client)?name.substring("BOOT-INF/classes/".length()):Path.of(name).getFileName().toString());
                    Files.createDirectories(target.getParent());Files.write(target,bytes,StandardOpenOption.CREATE_NEW);
                    if(assessor)classHash=HexFormat.of().formatHex(MessageDigest.getInstance("SHA-256").digest(bytes));
                    else if(lib){urls.add(target.toUri().toURL());libraries++;}
                }
            }
            if(classHash==null||libraries!=3)throw new IllegalStateException("ARTIFACT_COMPONENTS_MISSING");
            try(var loader=new URLClassLoader(urls.toArray(URL[]::new),ClassLoader.getPlatformClassLoader())){
                Class<?> mapperClass=loader.loadClass("com.fasterxml.jackson.databind.ObjectMapper");
                Object mapper=mapperClass.getConstructor().newInstance();Method parse=mapperClass.getMethod("readTree",String.class);
                var http=new FixtureHttp();var clientClass=loader.loadClass("in.marketbrain.marketdata.paytm.PaytmSupervisedClient");
                var ctor=clientClass.getDeclaredConstructor(HttpClient.class);ctor.setAccessible(true);Object client=ctor.newInstance(http);
                var quote=clientClass.getDeclaredMethod("quote",String.class,int.class);quote.setAccessible(true);
                Method assess=loader.loadClass("in.marketbrain.marketdata.paytm.PaytmQuoteProbe").getDeclaredMethod("assess",loader.loadClass("com.fasterxml.jackson.databind.JsonNode"),int.class,Instant.class);assess.setAccessible(true);
                List<Map<String,Object>> checks=new ArrayList<>();
                for(Case c:cases()){
                    http.body=c.body();
                    Map<?,?> result=(Map<?,?>)assess.invoke(null,quote.invoke(client,"fixture-read-only",2885),2885,NOW);
                    boolean ok=c.expected().equals(result.get("status"))&&Boolean.valueOf(c.fresh()).equals(result.get("fresh"))&&Boolean.FALSE.equals(result.get("ordersEnabled"))&&Boolean.FALSE.equals(result.get("mappingVerified"));
                    checks.add(Map.of("name",c.name(),"passed",ok,"expected",c.expected(),"actual",String.valueOf(result.get("status"))));
                }
                http.body="invalid-json";boolean rejected=false;
                try{quote.invoke(client,"fixture-read-only",2885);}catch(InvocationTargetException e){rejected="PAYTM_TRANSPORT_OR_JSON_FAILED".equals(e.getCause().getMessage());}
                checks.add(Map.of("name","invalidJson","passed",rejected,"expected","PAYTM_TRANSPORT_OR_JSON_FAILED","actual",rejected?"PAYTM_TRANSPORT_OR_JSON_FAILED":"UNEXPECTED"));
                boolean passed=checks.stream().allMatch(c->Boolean.TRUE.equals(c.get("passed")))&&http.calls==25;
                clientClass.getMethod("close").invoke(client);
                System.out.println(mapperClass.getMethod("writeValueAsString",Object.class).invoke(mapper,Map.of("passed",passed,"checks",checks,"assessorSha256",classHash,"scope","COPIED_DEPLOYED_CLIENT_ASSESSOR_SIMULATED_HTTP_NATIVE_JVM","ordersEnabled",false,"networkCalls",0,"simulatedHttpCalls",http.calls)));
                if(!passed)throw new IllegalStateException("QUALITY_ASSERTION_FAILED");
            }
        }finally{
            try(var files=Files.walk(dir)){for(Path p:files.sorted(Comparator.reverseOrder()).toList())Files.delete(p);}
        }
    }
}

'@
function Invoke-SupervisedDeployedQualityProbe {
 $r=@{test='COPIED_DEPLOYED_QUOTE_QUALITY';passed=$false;ordersEnabled=$false;brokerCredentialsUsed=$false;applicationChanged=$false;failure=$null;cleanupPassed=$false}
 $dir=$null;$watch=[Diagnostics.Stopwatch]::StartNew()
 function Invoke-QualityNative([string]$Exe,[string[]]$Arguments,[int]$Seconds=60){
  $p=[Diagnostics.Process]::new();$p.StartInfo=[Diagnostics.ProcessStartInfo]::new();$p.StartInfo.FileName=$Exe
  $p.StartInfo.UseShellExecute=$false;$p.StartInfo.CreateNoWindow=$true;$p.StartInfo.RedirectStandardOutput=$true;$p.StartInfo.RedirectStandardError=$true
  foreach($a in $Arguments){$p.StartInfo.ArgumentList.Add($a)}
  try{
   $null=$p.Start();$o=$p.StandardOutput.ReadToEndAsync();$e=$p.StandardError.ReadToEndAsync()
   if(-not $p.WaitForExit($Seconds*1000)){try{$p.Kill($true)}catch{};throw 'QUALITY_NATIVE_TIMEOUT'}
   if($p.ExitCode -ne 0){$r.nativeExitCode=$p.ExitCode;throw 'QUALITY_NATIVE_FAILED'}
   $text=$o.GetAwaiter().GetResult();$null=$e.GetAwaiter().GetResult()
   if($text.Length -gt 16384){throw 'QUALITY_OUTPUT_TOO_LARGE'}
   return $text.Trim()
  }finally{$p.Dispose()}
 }
 try{
  $r.stage='RESOLVE_TOOLS'
  $docker=(Get-Command docker.exe -CommandType Application -ErrorAction Stop|Select-Object -First 1).Source
  $javac=(Get-Command javac.exe -CommandType Application -ErrorAction Stop|Select-Object -First 1).Source
  $java=Join-Path (Split-Path $javac -Parent) 'java.exe'
  if(-not (Test-Path -LiteralPath $java)){throw 'QUALITY_JAVA_MISSING'}
  $id=Invoke-QualityNative $docker @('--host','npipe:////./pipe/docker_engine','ps','-q','--filter','label=com.docker.compose.service=marketbrain-service','--filter','status=running') 15
  if($id -cnotmatch '^[a-f0-9]{12,64}$'){throw 'QUALITY_APPLICATION_NOT_UNIQUE'}
  $r.stage='COPY_DEPLOYED_ARTIFACT'
  $hash=Invoke-QualityNative $docker @('--host','npipe:////./pipe/docker_engine','exec',$id,'sha256sum','/app/app.jar') 15
  if($hash -cnotmatch '^([a-f0-9]{64})\s+/app/app.jar$'){throw 'QUALITY_ARTIFACT_HASH_INVALID'}
  $r.artifactSha256=$Matches[1]
  $parent=Join-Path $env:LOCALAPPDATA 'MarketBrainAutomation'
  $dir=Join-Path $parent ('quote-quality-'+[guid]::NewGuid().ToString('N'))
  $null=New-Item -ItemType Directory -Path $dir -ErrorAction Stop
  $artifact=Join-Path $dir 'application.jar'
  $null=Invoke-QualityNative $docker @('--host','npipe:////./pipe/docker_engine','cp',($id+':/app/app.jar'),$artifact)
  if((Get-FileHash -LiteralPath $artifact).Hash.ToLowerInvariant() -cne $r.artifactSha256){throw 'QUALITY_COPY_HASH_MISMATCH'}
  $r.stage='COMPILE_ISOLATED_PROBE'
  $source=Join-Path $dir 'DeployedQuoteQualityProbe.java'
  [IO.File]::WriteAllText($source,$script:deployedQualitySource,[Text.UTF8Encoding]::new($false))
  $null=Invoke-QualityNative $javac @('-J-Xmx128m','--release','21','-encoding','UTF-8','-d',$dir,$source)
  $r.stage='EXECUTE_SYNTHETIC_CASES'
  $v=(Invoke-QualityNative $java @('-Xmx128m','-cp',$dir,'DeployedQuoteQualityProbe',$artifact) 30)|ConvertFrom-Json
  if($v.passed -ne $true -or $v.ordersEnabled -ne $false -or $v.networkCalls -ne 0 -or $v.simulatedHttpCalls -ne 25 -or @($v.checks).Count -ne 25 -or $v.assessorSha256 -cnotmatch '^[a-f0-9]{64}$'){throw 'QUALITY_RESULTS_REJECTED'}
  $r.scope='COPIED_DEPLOYED_CLIENT_ASSESSOR_SIMULATED_HTTP_NATIVE_JVM';$r.assessorSha256=$v.assessorSha256
  $r.checks=@($v.checks|ForEach-Object {
   if($_.name -cnotmatch '^[A-Za-z0-9]{1,40}$' -or $_.expected -cnotmatch '^[A-Z_]{1,60}$' -or $_.actual -cnotmatch '^[A-Z_]{1,60}$' -or $_.passed -ne $true){throw 'QUALITY_CASE_REJECTED'}
   @{name=$_.name;expected=$_.expected;actual=$_.actual;passed=$true}
  })
  $r.stage='VERIFY_UNCHANGED'
  $after=Invoke-QualityNative $docker @('--host','npipe:////./pipe/docker_engine','exec',$id,'sha256sum','/app/app.jar') 15
  if($after -cne $hash){throw 'QUALITY_ARTIFACT_CHANGED'}
  $r.passed=$true;$r.stage='COMPLETE'
 }catch{$r.failure=if($_.Exception.Message -cmatch '^QUALITY_[A-Z_]+$'){$_.Exception.Message}else{'QUALITY_PROBE_FAILED'};$r.errorType=$_.Exception.GetBaseException().GetType().Name}
 finally{
  if($dir){try{
   $full=[IO.Path]::GetFullPath($dir);$allowed=[IO.Path]::GetFullPath((Join-Path $env:LOCALAPPDATA 'MarketBrainAutomation'))+[IO.Path]::DirectorySeparatorChar
   if(-not $full.StartsWith($allowed,[StringComparison]::OrdinalIgnoreCase) -or (Split-Path $full -Leaf) -cnotmatch '^quote-quality-[a-f0-9]{32}$'){throw 'QUALITY_CLEANUP_PATH'}
   Remove-Item -LiteralPath $full -Recurse -Force -ErrorAction Stop;$r.cleanupPassed=$true
  }catch{$r.passed=$false;$r.cleanupFailure='QUALITY_TEMP_CLEANUP_FAILED'}}
  $r.elapsedSeconds=$watch.Elapsed.TotalSeconds
 }
 return $r
}

function Invoke-SupervisedQuoteFixtures {
try {
$ErrorActionPreference='Stop'
function Samples {
 @(1..3|ForEach-Object {@{status='FRESH_QUOTE_OBSERVED';fresh=$true;ordersEnabled=$false;securityId=2885;exchange='NSE';scripType='EQUITY';timestampEpoch='PAYTM_1980_SECONDS';observedEpochMilliseconds=(20000+$_*5000);tradeEpochMilliseconds=(20000+$_*5000-100);ageMilliseconds=100;lastPrice=1377.5}})
}
$s=Samples;$r=Get-PaytmQuoteBatchAssessment $s 2885 -RequireFresh
if(-not $r.passed -or $r.freshCount -ne 3){throw 'FRESH_FIXTURE_FAILED'}
$s=Samples;foreach($q in $s){$q.status='STALE_QUOTE';$q.fresh=$false;$q.tradeEpochMilliseconds=1;$q.ageMilliseconds=$q.observedEpochMilliseconds-1}
if((Get-PaytmQuoteBatchAssessment $s 2885 -RequireFresh).passed){throw 'STALE_ACCEPTED'}
$s=@(1..3|ForEach-Object {@{status='NO_QUOTE';fresh=$false;ordersEnabled=$false}})
if((Get-PaytmQuoteBatchAssessment $s 2885 -RequireFresh).missingCount -ne 3){throw 'MISSING_FIXTURE_FAILED'}
foreach($case in @('identity','age','price','duplicate','falseFresh')){
 $s=Samples
 switch($case){identity{$s[0].securityId=1};age{$s[0].ageMilliseconds=1};price{$s[0].lastPrice=0};duplicate{$s[1]=$s[0]};falseFresh{$s[0].ageMilliseconds=20000;$s[0].tradeEpochMilliseconds=$s[0].observedEpochMilliseconds-20000}}
 $failed=$false;try{$null=Get-PaytmQuoteBatchAssessment $s 2885 -RequireFresh}catch{$failed=$true}
 if(-not $failed){throw "NEGATIVE_NOT_CAUGHT_$case"}
}

 return @{test='POWERSHELL_QUOTE_VALIDATOR_SYNTHETIC_FIXTURES';passed=$true;fixtureCount=8;brokerCalls=0;ordersEnabled=$false}
}catch{return @{test='POWERSHELL_QUOTE_VALIDATOR_SYNTHETIC_FIXTURES';passed=$false;fixtureCount=8;failure='QUOTE_FIXTURE_FAILED';brokerCalls=0;ordersEnabled=$false}}
}
if($Mode -eq 'FailureFixture'){
 $boundary=Invoke-SupervisedBoundaryProbe
 $quality=Invoke-SupervisedQuoteFixtures
 $identity=Invoke-SupervisedIdentityProbe
 $review=Invoke-SupervisedReviewBoundaryProbe
 $deployed=Invoke-SupervisedDeployedQualityProbe
 $batch=@{test='BOUNDARY_QUOTE_VALIDATION_AND_IDENTITY';passed=($boundary.passed -and $quality.passed -and $identity.passed -and $review.passed -and $deployed.passed);boundary=$boundary;quoteFixtures=$quality;identity=$identity;reviewBoundary=$review;deployedQuality=$deployed;ordersEnabled=$false}
 [IO.File]::WriteAllText($ResultPath,($batch|ConvertTo-Json -Depth 8))
 if(-not $batch.passed){exit 1}
 exit 0
}
if($Mode -eq 'Apply'){
 $universe=Invoke-SupervisedUniverseProbe
 [IO.File]::WriteAllText($ResultPath,($universe|ConvertTo-Json -Depth 6))
 if(-not $universe.passed){exit 1}
 $lifecycle=Invoke-SupervisedLifecycleProbe
 $batch=@{test='SUPERVISED_UNIVERSE_AND_LIFECYCLE';passed=$lifecycle.passed;ordersEnabled=$false;universe=$universe;lifecycle=$lifecycle}
 if($lifecycle.passed -and $lifecycle.finalLocked){$batch.gatewayStartup=Invoke-SupervisedGatewayStartupProbe;$batch.passed=$batch.gatewayStartup.passed}
 [IO.File]::WriteAllText($ResultPath,($batch|ConvertTo-Json -Depth 8))
 if(-not $lifecycle.passed){exit 1}
 exit 0
}
if($Mode -eq 'Observe'){
 $delivery=Get-PaperDeliveryReport
 if($null -ne $delivery){[IO.File]::WriteAllText($ResultPath,($delivery|ConvertTo-Json -Depth 8));exit 0}
}

$result=[ordered]@{version=1;test='SUPERVISED_LOGIN_REPORT_COLLECTION';passed=$false;ordersEnabled=$false;failure=$null}
try{
 if($Mode -ne 'Observe'){throw 'REPORT_OBSERVE_ONLY'}
 $files=@(Get-ChildItem -LiteralPath 'C:\MarketBrainData\Review' -Filter 'paytm-supervised-*.json' -File|Where-Object {$_.Name -match '^paytm-supervised-(login|deployment)-[a-f0-9]{32}\.json$'}|Sort-Object LastWriteTimeUtc -Descending|Select-Object -First 1)
 if($files.Count -ne 1){throw 'SUPERVISED_REPORT_NOT_CREATED_YET'}
 $file=$files[0]
 if($file.Length -gt 16384 -or $file.Attributes -band [IO.FileAttributes]::ReparsePoint){throw 'REPORT_FILE_REJECTED'}
 $stream=$null;$reader=$null
 try{
  $stream=[IO.File]::Open($file.FullName,'Open','Read',([IO.FileShare]::ReadWrite -bor [IO.FileShare]::Delete))
  if($stream.Length -gt 16384){throw 'REPORT_FILE_REJECTED'}
  $reader=[IO.StreamReader]::new($stream)
  $v=$reader.ReadToEnd()|ConvertFrom-Json
 }finally{if($reader){$reader.Dispose()};if($stream){$stream.Dispose()}}
 if($v.version -ne 1 -or $v.runId -cnotmatch '^[a-f0-9]{32}$' -or $v.ordersEnabled -ne $false){throw 'REPORT_SCOPE_REJECTED'}
 $safe=[ordered]@{runId=$v.runId;ordersEnabled=$false}
 foreach($name in @('status','stage','failure','providerFailure','clockSource','applicationState')){
  $text=[string]$v.$name
  if($text -and $text -cnotmatch '^[A-Z0-9_]{1,100}$'){throw 'REPORT_FIELD_REJECTED'}
  $safe[$name]=$text
 }
 foreach($name in @('readAccessVerified','quotesTested','windowsClockGate','vpsAccuracyAssumed')){
  if($v.$name -isnot [bool]){throw 'REPORT_FIELD_REJECTED'};$safe[$name]=$v.$name
 }
 $safe.cleanup=@($v.cleanup|ForEach-Object {if($_ -cnotmatch '^[A-Z_]{1,80}$'){throw 'REPORT_FIELD_REJECTED'};$_})
 $safe.elapsedSeconds=[double]$v.elapsedSeconds
 if($v.PSObject.Properties['gatewayStartup']){
  $g=$v.gatewayStartup
  if($g.ready -isnot [bool] -or @($g.samples).Count -gt 20){throw 'REPORT_GATEWAY_REJECTED'}
  $safe.gatewayStartup=@{ready=$g.ready;samples=@($g.samples|ForEach-Object {
   if($_.phase -cnotmatch '^[A-Z_]{1,60}$' -or $_.taskState -cnotin @('Unknown','Disabled','Queued','Ready','Running') -or $_.newInstance -isnot [bool]){throw 'REPORT_GATEWAY_REJECTED'}
   @{seconds=[double]$_.seconds;newInstance=$_.newInstance;phase=[string]$_.phase;sequence=[long]$_.sequence;taskState=[string]$_.taskState;taskResult=[long]$_.taskResult}
  })}
 }
 if($v.PSObject.Properties['identityBinding']){
  $b=$v.identityBinding
  if($b.status -cnotmatch '^[A-Z0-9_]{1,100}$' -or $b.reviewEligible -isnot [bool] -or $b.ordersEnabled -ne $false){throw 'REPORT_IDENTITY_REJECTED'}
  $safe.identityBinding=@{status=$b.status;reviewEligible=$b.reviewEligible;ordersEnabled=$false}
  if($b.PSObject.Properties['identity']){
   $x=$b.identity;$safe.identityBinding.identity=@{}
   $patterns=@{symbol='^[A-Z0-9][A-Z0-9&-]{0,29}$';securityId='^[1-9][0-9]{0,7}$';instrumentId='^[1-9][0-9]{0,18}$';isin='^[A-Z]{2}[A-Z0-9]{9}[0-9]$';snapshotId='^[a-f0-9-]{36}$';snapshotDate='^[0-9]{4}-[0-9]{2}-[0-9]{2}$';providerSha256='^[A-F0-9]{64}$';constituentSha256='^[A-F0-9]{64}$';basis='^UNIQUE_NSE_EQ_SYMBOL_BRIDGE$';membershipScope='^LATEST_PUBLISHED_FILE$'}
   foreach($n in $patterns.Keys){if([string]$x.$n -cnotmatch $patterns[$n]){throw 'REPORT_IDENTITY_REJECTED'};$safe.identityBinding.identity[$n]=$x.$n}
   if($x.providerIsinVerified -ne $false){throw 'REPORT_IDENTITY_REJECTED'};$safe.identityBinding.identity.providerIsinVerified=$false
  }
 }
 if($v.PSObject.Properties['quoteBatch']){
  $x=$v.quoteBatch
  if($x.status -notin @('THREE_FRESH_MAPPED_QUOTES','FRESHNESS_PENDING') -or $x.passed -isnot [bool] -or $x.strictFreshRequired -isnot [bool] -or $x.ordersEnabled -ne $false -or $x.sampleCount -ne 3){throw 'REPORT_BATCH_REJECTED'}
  foreach($n in @('freshCount','staleCount','missingCount')){if([string]$x.$n -cnotmatch '^[0-3]$'){throw 'REPORT_BATCH_REJECTED'}}
  if(($x.freshCount+$x.staleCount+$x.missingCount) -ne 3 -or [string]$x.securityId -cnotmatch '^[1-9][0-9]{0,7}$'){throw 'REPORT_BATCH_REJECTED'}
  $safe.quoteBatch=@{status=$x.status;passed=$x.passed;strictFreshRequired=$x.strictFreshRequired;sampleCount=3;freshCount=[int]$x.freshCount;staleCount=[int]$x.staleCount;missingCount=[int]$x.missingCount;securityId=[int]$x.securityId;ordersEnabled=$false}
 }
 if($v.PSObject.Properties['transportFailure']){
  $x=$v.transportFailure
  if($x.status -cnotmatch '^[A-Z_]{1,100}$' -or ($x.failure -and $x.failure -cnotmatch '^SUPERVISED_[A-Z_]{1,100}$') -or $x.ordersEnabled -ne $false){throw 'REPORT_TRANSPORT_REJECTED'}
  $safe.transportFailure=[ordered]@{status=[string]$x.status;failure=[string]$x.failure;elapsedSeconds=[double]$x.elapsedSeconds;ordersEnabled=$false}
  foreach($n in @('passed','gatewayStopped','transportRejected','sessionLocked','subsequentQuoteRejected')){if($x.$n -isnot [bool]){throw 'REPORT_TRANSPORT_REJECTED'};$safe.transportFailure[$n]=$x.$n}
 }
 if($v.PSObject.Properties['callbackReplay']){
  $x=$v.callbackReplay
  if($x.requested -isnot [bool] -or $x.verified -isnot [bool] -or $x.exchangeAttempts -ne 1){throw 'REPORT_REPLAY_REJECTED'}
  $safe.callbackReplay=@{requested=$x.requested;verified=$x.verified;exchangeAttempts=1}
 }
 if($v.PSObject.Properties['sessionRestart']){
  $x=$v.sessionRestart
  if($x.status -cnotmatch '^[A-Z_]{1,100}$' -or ($x.failure -and $x.failure -cnotmatch '^SUPERVISED_[A-Z_]{1,100}$') -or $x.ordersEnabled -ne $false){throw 'REPORT_RESTART_REJECTED'}
  $safe.sessionRestart=[ordered]@{status=[string]$x.status;failure=[string]$x.failure;elapsedSeconds=[double]$x.elapsedSeconds;ordersEnabled=$false}
  foreach($n in @('passed','authenticatedBeforeRestart','restartAttempted','sameContainer','startChanged','lockedAfterRestart','quoteRejected')){if($x.$n -isnot [bool]){throw 'REPORT_RESTART_REJECTED'};$safe.sessionRestart[$n]=$x.$n}
 }
 if($v.PSObject.Properties['sessionExpiry']){
  $x=$v.sessionExpiry
  if($x.status -cnotmatch '^[A-Z_]{1,100}$' -or ($x.failure -and $x.failure -cnotmatch '^SUPERVISED_[A-Z_]{1,100}$') -or $x.ordersEnabled -ne $false){throw 'REPORT_EXPIRY_REJECTED'}
  $safe.sessionExpiry=[ordered]@{status=[string]$x.status;failure=[string]$x.failure;elapsedSeconds=[double]$x.elapsedSeconds;ordersEnabled=$false}
  foreach($n in @('passed','quoteLimitRejected','authenticatedBeforeWait','expiryObserved','postExpiryQuoteRejected')){if($x.$n -isnot [bool]){throw 'REPORT_EXPIRY_REJECTED'};$safe.sessionExpiry[$n]=$x.$n}
  if($safe.sessionExpiry.elapsedSeconds -lt 0 -or $safe.sessionExpiry.elapsedSeconds -gt 1800){throw 'REPORT_EXPIRY_REJECTED'}
 }
 if($v.PSObject.Properties['universeMatch']){
  $u=$v.universeMatch
  if($u.status -cnotmatch '^[A-Z_]{1,100}$' -or $u.ordersEnabled -ne $false -or $u.snapshotMatched -isnot [bool]){throw 'REPORT_UNIVERSE_REJECTED'}
  $safe.universeMatch=[ordered]@{status=[string]$u.status;snapshotMatched=$u.snapshotMatched;ordersEnabled=$false}
  $patterns=@{symbol='^[A-Z0-9][A-Z0-9&-]{0,29}$';snapshotId='^[a-f0-9-]{36}$';observedOn='^[0-9]{4}-[0-9]{2}-[0-9]{2}$';isin='^[A-Z]{2}[A-Z0-9]{9}[0-9]$';instrumentId='^[1-9][0-9]{0,18}$'}
  foreach($n in $patterns.Keys){if($u.PSObject.Properties[$n]){if([string]$u.$n -cnotmatch $patterns[$n]){throw 'REPORT_UNIVERSE_REJECTED'};$safe.universeMatch[$n]=$u.$n}}
  foreach($n in @('currentMembershipVerified','providerIsinVerified')){if($u.PSObject.Properties[$n]){if($u.$n -isnot [bool] -or $u.$n){throw 'REPORT_UNIVERSE_REJECTED'};$safe.universeMatch[$n]=$false}}
 }
 if($v.PSObject.Properties['quoteMapping']){
  $m=$v.quoteMapping
  if($m.symbol -cnotmatch '^[A-Z0-9][A-Z0-9&-]{0,29}$' -or [string]$m.securityId -cnotmatch '^[1-9][0-9]{0,7}$' -or $m.sha256 -cnotmatch '^[A-F0-9]{64}$' -or $m.exchange -cne 'NSE' -or $m.series -cne 'EQ' -or $m.segment -cne 'E' -or $m.instrumentType -cne 'ES' -or $m.source -cne 'PAYTM_PUBLIC_EQUITY_MASTER' -or $m.localUniverseVerified -ne $false){throw 'REPORT_MAPPING_REJECTED'}
  $safe.quoteMapping=@{symbol=[string]$m.symbol;securityId=[int]$m.securityId;exchange='NSE';series='EQ';segment='E';instrumentType='ES';source='PAYTM_PUBLIC_EQUITY_MASTER';sha256=[string]$m.sha256;localUniverseVerified=$false}
 }
 if($v.PSObject.Properties['quoteSamples']){
  if(@($v.quoteSamples).Count -gt 3){throw 'REPORT_FIELD_REJECTED'}
  $safe.quoteSamples=@($v.quoteSamples|ForEach-Object {
   $q=$_;$s=[ordered]@{}
   foreach($n in @('status','exchange','scripType','timestampEpoch')){
    if($q.PSObject.Properties[$n]){if([string]$q.$n -cnotmatch '^[A-Z0-9_]{1,100}$'){throw 'REPORT_FIELD_REJECTED'};$s[$n]=[string]$q.$n}
   }
   foreach($n in @('securityId','observedEpochMilliseconds','rawTradeTime','tradeEpochMilliseconds','ageMilliseconds','lastPrice')){
    if($q.PSObject.Properties[$n]){if($q.$n -is [string] -or $q.$n -is [bool] -or $null -eq $q.$n){throw 'REPORT_FIELD_REJECTED'};$s[$n]=[decimal]$q.$n}
   }
   foreach($n in @('fresh','mappingVerified','ordersEnabled')){if($q.$n -isnot [bool]){throw 'REPORT_FIELD_REJECTED'};$s[$n]=$q.$n}
   if($q.ordersEnabled -ne $false -or $q.mappingVerified -ne $false){throw 'REPORT_SCOPE_REJECTED'}
   $s
  })
 }
 if($v.PSObject.Properties['failureLine']){$safe.failureLine=[int]$v.failureLine}
 if($v.PSObject.Properties['deploymentAttempted']){$safe.deploymentAttempted=($v.deploymentAttempted -eq $true)}
 if($v.PSObject.Properties['commands']){
  $safe.commands=@($v.commands|ForEach-Object {
   if($_.stage -cnotmatch '^[A-Z_]{1,60}$'){throw 'REPORT_FIELD_REJECTED'}
   @{stage=$_.stage;exitCode=[int]$_.exitCode;elapsedSeconds=[double]$_.elapsedSeconds}
  })
 }
 $result.report=$safe;$result.sourceFile=$file.Name;$result.passed=$true
 if($safe.stage -eq 'GATEWAY'){
  if(-not (Get-Command Get-SupervisedGatewayTaskObservation -ErrorAction SilentlyContinue)){. "$PSScriptRoot/SupervisedGatewayObservation.ps1"}
  $result.gatewayTaskObservation=Get-SupervisedGatewayTaskObservation
 }
 $result.status='REPORT_COLLECTED_NOT_AUTOMATICALLY_ACCEPTED'
}catch{$result.failure=if($_.Exception.Message -cmatch '^[A-Z_]+$'){$_.Exception.Message}else{'REPORT_COLLECTION_FAILED'}}
[IO.File]::WriteAllText($ResultPath,($result|ConvertTo-Json -Depth 6))
if(-not $result.passed){exit 1}
