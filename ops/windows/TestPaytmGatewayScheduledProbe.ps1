#Requires -Version 7.0
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'PaytmGatewayAccount.ps1')
. (Join-Path $PSScriptRoot 'PaytmGatewayAccountRepair.ps1')
. (Join-Path $PSScriptRoot 'PaytmGatewayKeyCustody.ps1')
. (Join-Path $PSScriptRoot 'PaytmGatewayScheduledProbe.ps1')
. (Join-Path $PSScriptRoot 'PaytmTunnelVerification.ps1')
$checks=0
function Check([bool]$Value,[string]$Name){if(-not $Value){throw "SCHEDULE_TEST_FAILED $Name"};$script:checks++}
function Reject([scriptblock]$Action,[string]$Name){$bad=$false;try{&$Action|Out-Null}catch{$bad=$true};Check $bad $Name}
# Native CIM construction only: no registration, credentials, task execution or persistence.
$nativeSource=''
foreach($fn in @('Get-PaytmAccountContract','Get-PaytmKeyContract','Get-PaytmScheduledProbeContract','Get-PaytmScheduledArguments','Assert-PaytmProbeTask')){
 $nativeSource+='function '+$fn+' {'+(Get-Item ('Function:'+ $fn)).ScriptBlock.ToString()+"}`n"
}
$nativeSource+=[string]@'
$ErrorActionPreference='Stop'
Import-Module ScheduledTasks -ErrorAction Stop
$nativeRun='b'*32;$nativeContract=Get-PaytmScheduledProbeContract $nativeRun
$nativeAction=New-ScheduledTaskAction -Execute $nativeContract.executable -Argument (Get-PaytmScheduledArguments $nativeRun) -WorkingDirectory $nativeContract.directory
$nativePrincipal=New-ScheduledTaskPrincipal -UserId (Get-PaytmKeyContract).accountSid -LogonType Password -RunLevel Limited
$nativeSettings=New-ScheduledTaskSettingsSet -Disable -MultipleInstances IgnoreNew -ExecutionTimeLimit ([TimeSpan]::FromSeconds(120)) -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries
$nativeTask=New-ScheduledTask -Action $nativeAction -Principal $nativePrincipal -Settings $nativeSettings -Description ('MarketBrain temporary signing probe '+$nativeRun)
$nativeShape=[pscustomobject]@{TaskName=$nativeContract.name;TaskPath='\';Description=$nativeTask.Description;Principal=$nativeTask.Principal;Actions=$nativeTask.Actions;Triggers=$nativeTask.Triggers;Settings=$nativeTask.Settings}
Assert-PaytmProbeTask $nativeShape $nativeRun $false
'NATIVE_TASK_DEFINITION_OK'
'@
$nativeHandle=Start-TunnelProcess 'C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe' @('-NoLogo','-NoProfile','-NonInteractive','-EncodedCommand',[Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($nativeSource)))
$nativeResult=Complete-TunnelProcess $nativeHandle -LimitSeconds 30
Check ($nativeResult.ExitCode -eq 0 -and -not $nativeResult.StoppedByRunner -and $nativeResult.Stdout.Trim() -ceq 'NATIVE_TASK_DEFINITION_OK') ('native PS5 task definition without registration: '+$nativeResult.Stderr)
$temp=Join-Path ([IO.Path]::GetTempPath()) ('marketbrain-scheduled-test-'+[guid]::NewGuid().ToString('N'))
$scripts=Join-Path $temp 'repo\ops\windows';$null=New-Item -ItemType Directory -Path $scripts -Force
$global:scheduledKeyContract=Get-PaytmKeyContract
$mock=@'
$script:originalWait=(Get-Item Function:Wait-PaytmProbeTask).ScriptBlock
function Assert-PaytmCustodyController {}
function Import-Module {param($Name,$ErrorAction)}
function Get-PaytmReadinessProgress {@([pscustomobject]@{id='G2';percent=60})}
function Get-PaytmAccountContract {[pscustomobject]@{root=$global:fixture.root}}
function Get-PaytmKeyContract {$v=$global:scheduledKeyContract.PSObject.Copy();$v.root=Join-Path $global:fixture.root 'key-custody';$v}
function Assert-PaytmScheduledPrerequisites($ReceiptPath){if($global:fixture.case -ceq 'prerequisiteFailure'){throw 'SCHEDULE_CUSTODY_RECEIPT_NOT_ACCEPTED'};[pscustomobject]@{sid=$global:scheduledKeyContract.accountSid}}
function Set-PaytmAccountDirectoryAcl($Path,$AccountSid) {}
function Get-Service {param($Name,$ErrorAction) [pscustomobject]@{Status='Running'}}
function Get-WinEvent {param($ListLog,$LogName,$FilterXPath,$MaxEvents,$ErrorAction,$ErrorVariable)
 if($ListLog){return [pscustomobject]@{IsEnabled=$false}}
}
function Read-Host {param($Prompt,[switch]$AsSecureString)
 if($AsSecureString){$global:fixture.password=ConvertTo-SecureString 'FixturePassword-NoRealCredential' -AsPlainText -Force;return $global:fixture.password}
 if($global:fixture.case -ceq 'cancel'){return 'CANCEL'};'TEST-SCHEDULED-KEY'
}
function Get-ScheduledTask {param($TaskPath,$ErrorAction)
 if($global:fixture.case -ceq 'existingTask'){return [pscustomobject]@{TaskName='MarketBrain-Gateway-Key-Probe-existing';TaskPath='\'}}
 if($global:fixture.case -cin @('inspectExisting','inspectDrift') -and -not $global:fixture.existingSeeded){
  $oldRun='c'*32;$old=Get-PaytmScheduledProbeContract $oldRun
  $action=New-ScheduledTaskAction -Execute $old.executable -Argument (Get-PaytmScheduledArguments $oldRun) -WorkingDirectory $old.directory
  $principal=New-ScheduledTaskPrincipal -UserId $global:scheduledKeyContract.accountSid -LogonType Password -RunLevel Limited
  $settings=New-ScheduledTaskSettingsSet -Disable -MultipleInstances IgnoreNew -ExecutionTimeLimit ([TimeSpan]::FromSeconds(120)) -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries
  $task=New-ScheduledTask -Action $action -Principal $principal -Settings $settings -Description ('MarketBrain temporary signing probe '+$oldRun)
  $task.TaskName=$old.name;$task.TaskPath='\';$global:fixture.task=$task;$global:fixture.lastResult=1
  $null=New-Item -ItemType Directory -Path $old.directory
  [IO.File]::WriteAllText((Join-Path $old.directory 'worker.ps1'),(New-PaytmScheduledWorkerSource $oldRun))
  $worker=[ordered]@{runId=$oldRun;stage='AGENT';failure='KEY_AGENT_IDENTITY_MISMATCH';signingChecks=0;sessionId=0;identityVerified=$true}
  [IO.File]::WriteAllText($old.result,($worker|ConvertTo-Json))
  $prior=[ordered]@{runId=$oldRun;status='REVIEW_REQUIRED';stage='RUN_BACKGROUND_SIGNING_CHECKS';failure='SCHEDULE_WORKER_NOT_PASSED';taskDisabled=$true;worker=$worker;arbitrarySecret='PRIVATE_SENTINEL_DO_NOT_COPY'}
  if($global:fixture.case -ceq 'inspectDrift'){$prior.runId='wrong';$task.Actions[0].Arguments='changed';[IO.File]::WriteAllText((Join-Path $old.directory 'worker.ps1'),'changed')}
  [IO.File]::WriteAllText((Join-Path $global:fixture.output ('paytm-scheduled-signing-20000101-'+$oldRun+'.json')),($prior|ConvertTo-Json -Depth 5))
  $global:fixture.existingSeeded=$true
 }
 if($null -ne $global:fixture.task){$global:fixture.task}
}
function New-ScheduledTaskAction {param($Execute,$Argument,$WorkingDirectory) [pscustomobject]@{Execute=$Execute;Arguments=$Argument;WorkingDirectory=$WorkingDirectory}}
function New-ScheduledTaskPrincipal {param($UserId,$LogonType,$RunLevel) [pscustomobject]@{UserId=$UserId;LogonType=$LogonType;RunLevel=$RunLevel}}
function New-ScheduledTaskSettingsSet {param([switch]$Disable,$MultipleInstances,$ExecutionTimeLimit,[switch]$AllowStartIfOnBatteries,[switch]$DontStopIfGoingOnBatteries)
 [pscustomobject]@{Enabled=(-not $Disable);MultipleInstances=$MultipleInstances;ExecutionTimeLimit=[Xml.XmlConvert]::ToString($ExecutionTimeLimit);
 RestartCount=0;AllowDemandStart=$true;AllowHardTerminate=$true;WakeToRun=$false;StartWhenAvailable=$false;RunOnlyIfNetworkAvailable=$false;RunOnlyIfIdle=$false;
 DisallowStartIfOnBatteries=(-not $AllowStartIfOnBatteries);StopIfGoingOnBatteries=(-not $DontStopIfGoingOnBatteries)}
}
function New-ScheduledTask {param($Action,$Principal,$Settings,$Description)
 [pscustomobject]@{Actions=@($Action);Triggers=@();Principal=$Principal;Settings=$Settings;Description=$Description;TaskName='';TaskPath='';State='Disabled'}
}
function Register-ScheduledTask {param($TaskName,$TaskPath,$InputObject,$User,$Password,$ErrorAction)
 $global:fixture.passwordSupplied=($Password -ceq 'FixturePassword-NoRealCredential');$global:fixture.registers++
 if($global:fixture.case -ceq 'registrationFailure'){throw 'SCHEDULE_REGISTRATION_FAILED'}
 $InputObject.TaskName=$TaskName;$InputObject.TaskPath=$TaskPath;$global:fixture.task=$InputObject
 if($global:fixture.case -ceq 'definitionDrift'){$global:fixture.task.Actions[0].Arguments='unreviewed'}
 if($global:fixture.case -ceq 'registrationAfterCreate'){throw 'SCHEDULE_REGISTRATION_FAILED'}
}
function Enable-ScheduledTask {param($TaskName,$TaskPath,$ErrorAction) $global:fixture.task.Settings.Enabled=$true;$global:fixture.task.State='Ready'}
function Disable-ScheduledTask {param($TaskName,$TaskPath,$ErrorAction) $global:fixture.task.Settings.Enabled=$false;$global:fixture.task.State='Disabled';$global:fixture.disables++}
function Stop-ScheduledTask {param($TaskName,$TaskPath,$ErrorAction) $global:fixture.task.State='Disabled';$global:fixture.stops++}
function Unregister-ScheduledTask {param($TaskName,$TaskPath,$Confirm,$ErrorAction)
 if($global:fixture.case -ceq 'removalFailure'){throw 'SCHEDULE_FIXTURE_REMOVE_FAILURE'};$global:fixture.task=$null;$global:fixture.removes++
}
function Start-ScheduledTask {param($TaskName,$TaskPath,$ErrorAction)
 $global:fixture.starts++;$global:fixture.task.State='Running'
 if($global:fixture.case -ceq 'taskTimeout'){return}
 $file=Join-Path $global:fixture.task.Actions[0].WorkingDirectory 'worker.ps1'
 try{&([scriptblock]::Create([IO.File]::ReadAllText($file)));$global:fixture.lastResult=0}catch{$global:fixture.lastResult=1}
 $global:fixture.task.State='Ready'
 if($global:fixture.case -ceq 'malformedReport'){
  $f=Get-ChildItem -LiteralPath (Join-Path $global:fixture.root 'work') -Filter '*.json'
  $r=Get-Content -Raw -LiteralPath $f.FullName|ConvertFrom-Json;$r.runId='wrong';[IO.File]::WriteAllText($f.FullName,($r|ConvertTo-Json))
 }
}
function Get-ScheduledTaskInfo {param($TaskName,$TaskPath,$ErrorAction) [pscustomobject]@{LastTaskResult=$global:fixture.lastResult}}
function Wait-PaytmProbeTask($RunId,$Report,$Checkpoint){if($global:fixture.case -ceq 'taskTimeout'){throw 'SCHEDULE_TASK_TIMEOUT'};&$script:originalWait $RunId $Report $Checkpoint}
'@
$workerMock=@'
function Get-PaytmKeyContract {$global:scheduledKeyContract}
function Get-PaytmCustodyIdentity {[pscustomobject]@{sid=if($global:fixture.case -ceq 'workerIdentity'){'wrong'}else{$global:scheduledKeyContract.accountSid};nonAdmin=$true}}
function Get-Process {param($Id) [pscustomobject]@{SessionId=if($global:fixture.case -ceq 'interactiveSession'){1}else{0}}}
function Invoke-PaytmCustodyNative($Tool,[string[]]$Arguments,$Seconds){
 $global:fixture.nativeCalls+=@($Tool+' '+($Arguments -join ' '))
 if($Tool -cne 'ssh-add.exe' -or $Arguments[0] -cnotin @('-l','-T')){throw 'UNEXPECTED_NATIVE_CALL'}
 if($Seconds -ne 10){throw 'UNBOUNDED_AGENT_PROBE'}
 if($global:fixture.case -ceq 'nativeException'){throw [ComponentModel.Win32Exception]::new(5)}
 if($global:fixture.case -ceq 'agentTimeout'){return @{ExitCode=-1;StoppedByRunner=$true;Stdout='PRIVATE_SENTINEL';Stderr='PRIVATE_SENTINEL'}}
 if($global:fixture.case -ceq 'agentEmpty'){return @{ExitCode=1;StoppedByRunner=$false;Stdout='The agent has no identities.';Stderr=''}}
 if($global:fixture.case -ceq 'agentConnection'){return @{ExitCode=2;StoppedByRunner=$false;Stdout='';Stderr='Error connecting to agent: PRIVATE_SENTINEL'}}
 if($Arguments[0] -ceq '-l'){
  return [pscustomobject]@{ExitCode=if($global:fixture.case -ceq 'agentMissing'){1}else{0};StoppedByRunner=$false;Stdout=('256 '+$global:scheduledKeyContract.fingerprint+' fixture (ED25519)');Stderr=''}
 }
 [pscustomobject]@{ExitCode=if($global:fixture.case -ceq 'signFailure'){2}else{0};StoppedByRunner=$false;Stdout='';Stderr=''}
}
'@
foreach($name in @('PaytmGatewayScheduledProbe.ps1','TestPaytmGatewayScheduledSigning.ps1','PaytmGatewayKeyCustody.ps1','PaytmGatewayAccount.ps1','PaytmGatewayAccountRepair.ps1')){
 $source=[IO.File]::ReadAllText((Join-Path $PSScriptRoot $name));if($name -ceq 'PaytmGatewayScheduledProbe.ps1'){$source+="`n"+$mock}
 [IO.File]::WriteAllText((Join-Path $scripts $name),$source)
}
$agentMock=@'
function Assert-PaytmAgentSigningReceipt($Path){
 if($global:fixture.case -ceq 'agentReceiptFailure'){throw 'SCHEDULE_AGENT_RECEIPT_NOT_REVIEWED'}
 @{runId=('d'*32);checkpointHash=if($global:fixture.case -ceq 'agentCheckpointMismatch'){'wrong'}else{'same'}}
}
function Get-PaytmAgentSigningSnapshot {
 @{hashes=@{'session-checkpoint.json'='same'};taskState=if($global:fixture.case -ceq 'agentStateDrift' -and $global:fixture.starts -gt 0){'Changed'}else{'Ready'}}
}
'@
[IO.File]::WriteAllText((Join-Path $scripts 'PaytmAgentSigning.ps1'),$agentMock)
foreach($name in @('PaytmSupervisorHost.ps1','PaytmSupervisorInstallation.ps1')){[IO.File]::WriteAllText((Join-Path $scripts $name),'# fixture')}
$cases=@('pass','cancel','prerequisiteFailure','existingTask','registrationFailure','registrationAfterCreate','workerIdentity','interactiveSession','agentMissing','signFailure','taskTimeout','definitionDrift','removalFailure','malformedReport','inspectEmpty','inspectExisting','inspectDrift','agentTimeout','agentEmpty','agentConnection','nativeException','agentEvidencePass','agentStateDrift','agentReceiptFailure','agentCheckpointMismatch')
foreach($case in $cases){
 $root=Join-Path $temp $case;$null=New-Item -ItemType Directory -Path (Join-Path $root 'work') -Force
 $keyRoot=Join-Path $root 'key-custody';$null=New-Item -ItemType Directory -Path $keyRoot
 [IO.File]::WriteAllText((Join-Path $keyRoot 'library.ps1'),([IO.File]::ReadAllText((Join-Path $PSScriptRoot 'PaytmGatewayKeyCustody.ps1'))+"`n"+$workerMock))
 [IO.File]::WriteAllText((Join-Path $keyRoot 'native.ps1'),'# Test fixture, no native tool invoked.')
 $global:fixture=@{root=$root;case=$case;task=$null;registers=0;starts=0;disables=0;stops=0;removes=0;password=$null;passwordSupplied=$false;nativeCalls=@();lastResult=267011}
 $failed=$false;$output=Join-Path $root 'output';$global:fixture.output=$output;$console=@();$inspect=$case.StartsWith('inspect')
 $params=@{CustodyReportPath='fixture';OutputDirectory=$output;InspectExisting=$inspect}
 if($case -in @('agentEvidencePass','agentStateDrift','agentReceiptFailure','agentCheckpointMismatch')){$params.AgentFailureReportPath='fixture'}
 try{$console=@(& (Join-Path $scripts 'TestPaytmGatewayScheduledSigning.ps1') @params 6>&1)}catch{$failed=$true}
 $files=@(Get-ChildItem -LiteralPath $output -Filter '*.json'|Where-Object {$_.Name -cne ('paytm-scheduled-signing-20000101-'+('c'*32)+'.json')});Check ($files.Count -eq 1) ('one report '+$case)
 $raw=[IO.File]::ReadAllText($files[0].FullName);$r=$raw|ConvertFrom-Json
 Check ($failed -eq ($case -cnotin @('pass','agentEvidencePass') -and -not $inspect)) ('result '+$case+' '+$r.failure+' '+($r.failureDetails|ConvertTo-Json -Compress))
 Check ($raw -notmatch 'FixturePassword|PRIVATE KEY|PRIVATE_SENTINEL' -and ($console -join '') -notmatch 'FixturePassword') 'no secrets in report/console'
 Check (-not $r.networkContacted -and -not $r.agentChanged -and -not $r.keyImported -and -not $r.ordersEnabled -and -not $r.productionSupervisorInstalled) 'scope unchanged'
 if($null -ne $global:fixture.password){$disposed=$false;try{$p=$global:fixture.password.Copy();$p.Dispose()}catch{$disposed=$true};Check $disposed 'secure password disposed'}
 if($case -cin @('cancel','prerequisiteFailure','existingTask')){Check ($global:fixture.registers -eq 0 -and -not $r.stagingCreated) 'preflight no mutations'}
 if($case -ceq 'pass'){
  Check ($r.worker.signingChecks -eq 2 -and $r.worker.sessionId -eq 0 -and $r.taskRemoved -and $null -eq $global:fixture.task) 'actual generated worker and cleanup pass'
  Check ($global:fixture.passwordSupplied -and $global:fixture.nativeCalls.Count -eq 3 -and $global:fixture.starts -eq 1) 'password API and bounded signing only'
  Check ($r.worker.nativeObservations.Count -eq 3 -and @($r.worker.nativeObservations|Where-Object {$_.exitCode -ne 0 -or $_.timedOut -or $_.classification -cne 'EXIT_ZERO'}).Count -eq 0) 'three native results recorded'
 }
 if($case -ceq 'agentEvidencePass'){Check ($r.status -ceq 'AGENT_SIGNING_PASSED_PRODUCTION_RECOVERY_PENDING' -and $r.productionStateUnchanged -and $r.taskRemoved) 'recovery-mode pass preserves production'}
 if($case -ceq 'agentStateDrift'){Check ($r.cleanupFailure -ceq 'SCHEDULE_AGENT_PRODUCTION_STATE_REVIEW_REQUIRED' -and -not $r.productionStateUnchanged) 'production drift fails closed'}
 if($case -in @('agentReceiptFailure','agentCheckpointMismatch')){Check ($global:fixture.starts -eq 0 -and $global:fixture.registers -eq 0 -and $null -eq $global:fixture.password) 'agent preflight precedes credentials and tasks'}
 if($case -in @('agentTimeout','agentEmpty','agentConnection','nativeException')){
  $wanted=@{agentTimeout='TIMEOUT';agentEmpty='NO_IDENTITIES';agentConnection='AGENT_CONNECTION_ERROR';nativeException='NATIVE_EXCEPTION'}[$case]
  Check ($r.worker.nativeObservations.Count -eq 1 -and $r.worker.nativeObservations[0].classification -ceq $wanted -and $r.worker.signingChecks -eq 0) 'specific agent failure retained'
  if($case -ceq 'nativeException'){Check ($r.worker.nativeObservations[0].nativeErrorCode -eq 5) 'native error number preserved'}
 }
 if($case -cin @('registrationAfterCreate','workerIdentity','interactiveSession','agentMissing','signFailure','taskTimeout','malformedReport','removalFailure','agentTimeout','agentEmpty','agentConnection','nativeException')){
  Check ($null -ne $global:fixture.task -and -not $global:fixture.task.Settings.Enabled -and $r.taskDisabled) 'failed task retained disabled'
 }
 if($case -ceq 'definitionDrift'){Check ($r.cleanupFailure -ceq 'SCHEDULE_CLEANUP_REVIEW_REQUIRED' -and $global:fixture.disables -eq 0 -and $global:fixture.starts -eq 0 -and -not $r.taskDefinition.argumentsMatch) 'do not operate changed task; capture mismatch'}
 if($case -ceq 'registrationFailure'){Check ($null -eq $global:fixture.task -and $global:fixture.disables -eq 0) 'no cleanup of absent task'}
 if($case -ceq 'existingTask'){Check ($r.existingProbes.Count -eq 1 -and $r.existingProbes[0].definitionFailure -ceq 'SCHEDULE_UNRECOGNIZED_PROBE_NAME') 'ordinary guard now preserves existing probe evidence'}
 if($inspect){Check ($r.status -ceq 'SCHEDULED_PROBE_INVENTORY_CAPTURED' -and $null -eq $global:fixture.password -and $global:fixture.registers -eq 0 -and $global:fixture.starts -eq 0 -and $global:fixture.disables -eq 0 -and $global:fixture.removes -eq 0 -and $global:fixture.nativeCalls.Count -eq 0) 'inspection never changes task or asks password'}
 if($case -ceq 'inspectEmpty'){Check ($r.existingProbes.Count -eq 0 -and ($console -join '') -notmatch 'Temporary task removed') 'empty inventory does not claim cleanup'}
 if($case -ceq 'inspectExisting'){Check ($r.existingProbes.Count -eq 1 -and $r.existingProbes[0].definitionMatches -and $r.existingProbes[0].workerMatchesCurrentSource -and $r.existingProbes[0].previousReport.failure -ceq 'SCHEDULE_WORKER_NOT_PASSED' -and $r.existingProbes[0].workerResult.failure -ceq 'KEY_AGENT_IDENTITY_MISMATCH') 'collect prior task worker and root failure in one report'}
 if($case -ceq 'inspectExisting'){Check ($r.existingProbes[0].launchEvidence.channels.Count -eq 2 -and $r.existingProbes[0].launchEvidence.channels[0].status -ceq 'NO_MATCHING_EVENTS' -and -not $r.existingProbes[0].launchEvidence.channels[0].enabled) 'inspection embeds disabled-log evidence without enabling it'}
 if($case -ceq 'inspectDrift'){Check (-not $r.existingProbes[0].definitionMatches -and -not $r.existingProbes[0].workerMatchesCurrentSource -and $r.existingProbes[0].previousReportFailure -ceq 'SCHEDULE_PRIOR_REPORT_UNAVAILABLE_OR_UNBOUND') 'drift and wrong-run evidence refused'}
}
# Test task-definition guards independently of the controller fixtures.
$run='a'*32;$global:fixture=@{root=(Join-Path $temp 'guards')};$c=Get-PaytmScheduledProbeContract $run
$task=[pscustomobject]@{TaskName=$c.name;TaskPath='\';Description=('MarketBrain temporary signing probe '+$run);
 Principal=[pscustomobject]@{UserId=$global:scheduledKeyContract.accountSid;LogonType='Password';RunLevel='Limited'};
 Actions=@([pscustomobject]@{Execute=$c.executable;Arguments=(Get-PaytmScheduledArguments $run);WorkingDirectory=$c.directory});Triggers=@();
 Settings=[pscustomobject]@{Enabled=$false;MultipleInstances='IgnoreNew';RestartCount=0;AllowDemandStart=$true;AllowHardTerminate=$true;WakeToRun=$false;StartWhenAvailable=$false;
 RunOnlyIfNetworkAvailable=$false;RunOnlyIfIdle=$false;DisallowStartIfOnBatteries=$false;StopIfGoingOnBatteries=$false;ExecutionTimeLimit='PT2M'}}
Assert-PaytmProbeTask $task $run $false;Check $true 'exact task accepted'
foreach($field in @('WakeToRun','StartWhenAvailable','RunOnlyIfNetworkAvailable','RunOnlyIfIdle','DisallowStartIfOnBatteries','StopIfGoingOnBatteries')){
 $task.Settings.$field=$true;Reject {Assert-PaytmProbeTask $task $run $false} ('reject '+$field);$task.Settings.$field=$false
}
$task.Principal.RunLevel='Highest';Reject {Assert-PaytmProbeTask $task $run $false} 'highest blocked';$task.Principal.RunLevel='Limited'
$task.Triggers=@([pscustomobject]@{Enabled=$true});Reject {Assert-PaytmProbeTask $task $run $false} 'automatic trigger blocked';$task.Triggers=@()
$task.Actions[0].Arguments='other';Reject {Assert-PaytmProbeTask $task $run $false} 'changed action blocked'
Reject {Get-PaytmScheduledProbeContract '../bad'} 'run path bound'
foreach($name in @('PaytmGatewayScheduledProbe.ps1','TestPaytmGatewayScheduledSigning.ps1')){
 $tokens=$null;$errors=$null;$null=[Management.Automation.Language.Parser]::ParseFile((Join-Path $PSScriptRoot $name),[ref]$tokens,[ref]$errors);Check ($errors.Count -eq 0) ('parse '+$name)
}
$tokens=$null;$errors=$null;$null=[Management.Automation.Language.Parser]::ParseInput((New-PaytmScheduledWorkerSource $run),[ref]$tokens,[ref]$errors);Check ($errors.Count -eq 0) 'generated worker parses'
# Actual prerequisite parser/hash logic against owned local files, with OS identity/ACL calls mocked.
$script:prereqRoot=Join-Path $temp 'prerequisites';$keyRoot=Join-Path $script:prereqRoot 'key-custody';$null=New-Item -ItemType Directory -Path $keyRoot -Force
$script:realContract=(Get-Item Function:Get-PaytmScheduledProbeContract).ScriptBlock
function Get-PaytmAccountContract {[pscustomobject]@{root=$script:prereqRoot}}
function Get-PaytmKeyContract {$v=$global:scheduledKeyContract.PSObject.Copy();$v.root=Join-Path $script:prereqRoot 'key-custody';$v}
function Get-PaytmScheduledProbeContract($RunId){$v=&$script:realContract $RunId;$v.receiptHash=$script:receiptHash;$v}
function Read-PaytmOwnedAccount {[pscustomobject]@{sid=if($script:prereqCase -ceq 'wrongSid'){'wrong'}else{$global:scheduledKeyContract.accountSid};runId=$global:scheduledKeyContract.accountRun}}
function Get-LocalUser {param($SID) [pscustomobject]@{Enabled=($script:prereqCase -cne 'disabled')}}
function Assert-PaytmRepairAgent {$script:agentChecks++}
function Get-Acl {param($LiteralPath) [pscustomobject]@{fixturePath=$LiteralPath}}
function Assert-PaytmAccountAcl($Acl,$Sid){$script:aclChecks++;if($script:prereqCase -ceq 'badAcl'){throw 'ACCOUNT_ACL_OWNER_OR_INHERITANCE'}}
foreach($file in @('library.ps1','native.ps1')){[IO.File]::WriteAllText((Join-Path $keyRoot $file),'fixture-source')}
[IO.File]::WriteAllText((Join-Path $keyRoot 'gateway.pub'),('ssh-ed25519 '+$global:scheduledKeyContract.publicBlob))
$c=Get-PaytmScheduledProbeContract ('a'*32)
$state=[ordered]@{version=1;runId=$c.receiptRun;sid=$global:scheduledKeyContract.accountSid;fingerprint=$global:scheduledKeyContract.fingerprint;hostPin=$global:scheduledKeyContract.hostPin;privateFileRetained=$false}
$statePath=Join-Path $keyRoot 'custody-state.json';[IO.File]::WriteAllText($statePath,($state|ConvertTo-Json))
$receipt=[ordered]@{runId=$c.receiptRun;status='GATEWAY_KEY_CUSTODY_AND_AUTH_PASSED_LIFECYCLE_PENDING';failure=$null;
 sourceHashes=@{'PaytmGatewayKeyCustody.ps1'=(Get-FileHash -LiteralPath (Join-Path $keyRoot 'library.ps1')).Hash;'PaytmTunnelVerification.ps1'=(Get-FileHash -LiteralPath (Join-Path $keyRoot 'native.ps1')).Hash}}
$receiptPath=Join-Path $script:prereqRoot 'receipt.json';$receiptText=$receipt|ConvertTo-Json -Depth 5;[IO.File]::WriteAllText($receiptPath,$receiptText)
$script:receiptHash=(Get-FileHash -LiteralPath $receiptPath).Hash;$script:prereqCase='pass';$script:aclChecks=0;$script:agentChecks=0
$p=Assert-PaytmScheduledPrerequisites $receiptPath;Check ($p.sid -ceq $global:scheduledKeyContract.accountSid -and $script:aclChecks -eq 1 -and $script:agentChecks -eq 1) 'real prerequisite parser calls identity ACL and agent checks'
foreach($case in @('wrongSid','disabled','badAcl')){$script:prereqCase=$case;Reject {Assert-PaytmScheduledPrerequisites $receiptPath} ('prerequisite '+$case)};$script:prereqCase='pass'
[IO.File]::AppendAllText($receiptPath,' ');Reject {Assert-PaytmScheduledPrerequisites $receiptPath} 'receipt hash drift';[IO.File]::WriteAllText($receiptPath,$receiptText)
[IO.File]::WriteAllText((Join-Path $keyRoot 'library.ps1'),'changed');Reject {Assert-PaytmScheduledPrerequisites $receiptPath} 'staged library drift';[IO.File]::WriteAllText((Join-Path $keyRoot 'library.ps1'),'fixture-source')
$state.privateFileRetained=$true;[IO.File]::WriteAllText($statePath,($state|ConvertTo-Json));Reject {Assert-PaytmScheduledPrerequisites $receiptPath} 'custody state drift';$state.privateFileRetained=$false;[IO.File]::WriteAllText($statePath,($state|ConvertTo-Json))
[IO.File]::WriteAllText((Join-Path $keyRoot 'gateway.pub'),'ssh-ed25519 wrong');Reject {Assert-PaytmScheduledPrerequisites $receiptPath} 'public key drift'
# Launch diagnostics: actual XML/parser/filter construction, mocked Windows event API.
$script:eventMode='captured';$script:eventQueries=@()
function New-FixtureEvent([string]$Xml,[int]$Id=101){
 $e=[pscustomobject]@{xml=$Xml;Id=$Id;RecordId=17;TimeCreated=[datetime]'2026-11-02T10:00:00Z'}
 $e|Add-Member ScriptMethod ToXml { $this.xml };$e
}
$eventTask='MarketBrain-Gateway-Key-Probe-'+('a'*32)
$script:taskEvent=New-FixtureEvent ('<Event><EventData><Data Name="TaskName">\'+$eventTask+'</Data><Data Name="ResultCode">2147943785</Data><Data Name="Arguments">PRIVATE_SENTINEL</Data></EventData></Event>')
$script:accountEvent=New-FixtureEvent '<Event><EventData><Data Name="TargetUserName">marketbrain-gateway</Data><Data Name="LogonType">4</Data><Data Name="Status">0xc000015b</Data><Data Name="SubStatus">0x0</Data><Data Name="Password">PRIVATE_SENTINEL</Data></EventData></Event>' 4625
function Get-WinEvent {
 [CmdletBinding()]param($ListLog,$LogName,$FilterXPath,$MaxEvents)
 if($ListLog){if($script:eventMode -ceq 'denied'){throw [UnauthorizedAccessException]::new('private error text')};return [pscustomobject]@{IsEnabled=($script:eventMode -cne 'disabled')}}
 $script:eventQueries+=@([pscustomobject]@{channel=$LogName;filter=$FilterXPath;limit=$MaxEvents})
 if($script:eventMode -ceq 'empty'){
  Write-Error -Message 'No matching events' -ErrorId NoMatchingEventsFound;return
 }
 if($script:eventMode -ceq 'queryDenied'){Write-Error -Message 'private query detail' -ErrorId QueryAccessDenied;return}
 if($LogName -ceq 'Security'){$script:accountEvent}else{
  if($script:eventMode -ceq 'capped'){1..32|ForEach-Object {$script:taskEvent}}else{$script:taskEvent}
 }
}
$e=Get-PaytmProbeLaunchEvidence ('a'*32)
Check ($e.channels.Count -eq 2 -and $e.channels[0].status -ceq 'CAPTURED' -and $e.channels[1].events[0].fields.Status -ceq '0xc000015b') 'task and batch logon code evidence captured'
Check (($e|ConvertTo-Json -Depth 10) -notmatch 'PRIVATE_SENTINEL') 'event arguments passwords and arbitrary messages excluded'
Check ($script:eventQueries[0].filter.Contains($eventTask) -and $script:eventQueries[0].filter.Contains('604800000') -and $script:eventQueries[0].limit -eq 32) 'task exact filtered bounded seven day query'
Check ($script:eventQueries[1].filter.Contains('EventID=4625') -and $script:eventQueries[1].filter.Contains("Data[@Name='LogonType']='4'")) 'security scoped to gateway batch logon failures'
foreach($mode in @('disabled','empty','denied','queryDenied','capped')){
 $script:eventMode=$mode;$e=Get-PaytmProbeLaunchEvidence ('a'*32)
 switch($mode){
  disabled {Check (-not $e.channels[0].enabled -and $e.channels[0].status -ceq 'CAPTURED') 'disabled log retains historical events'}
  empty {Check ($e.channels[0].status -ceq 'NO_MATCHING_EVENTS') 'no matching events is explicit unknown evidence'}
  denied {Check ($e.channels[0].status -ceq 'UNAVAILABLE' -and $e.channels[0].failureType -ceq 'UnauthorizedAccessException') 'log access denial recorded without private message'}
  queryDenied {Check ($e.channels[0].status -ceq 'UNAVAILABLE') 'query failure distinct from empty results'}
  capped {Check ($e.channels[0].limitReached -and $e.channels[0].events.Count -eq 32) 'bounded query cap explicit'}
 }
}
Reject {ConvertTo-PaytmProbeEvent $script:taskEvent 'wrong' Task} 'unrelated task event refused'
Reject {ConvertTo-PaytmProbeEvent $script:taskEvent $eventTask Account} 'unrelated account event refused'
$bad=New-FixtureEvent '<!DOCTYPE Event><Event/>';Reject {ConvertTo-PaytmProbeEvent $bad $eventTask Task} 'DTD event refused'
Write-Host "PASS: $checks assertions, $($cases.Count) mocked scheduled-task workflows; real generated worker with mocked identity/native tools. No real task, credential, key or network changes."
