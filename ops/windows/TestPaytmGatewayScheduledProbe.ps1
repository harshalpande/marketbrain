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
function Read-Host {param($Prompt,[switch]$AsSecureString)
 if($AsSecureString){$global:fixture.password=ConvertTo-SecureString 'FixturePassword-NoRealCredential' -AsPlainText -Force;return $global:fixture.password}
 if($global:fixture.case -ceq 'cancel'){return 'CANCEL'};'TEST-SCHEDULED-KEY'
}
function Get-ScheduledTask {param($TaskPath,$ErrorAction)
 if($global:fixture.case -ceq 'existingTask'){return [pscustomobject]@{TaskName='MarketBrain-Gateway-Key-Probe-existing';TaskPath='\'}}
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
$cases=@('pass','cancel','prerequisiteFailure','existingTask','registrationFailure','registrationAfterCreate','workerIdentity','interactiveSession','agentMissing','signFailure','taskTimeout','definitionDrift','removalFailure','malformedReport')
foreach($case in $cases){
 $root=Join-Path $temp $case;$null=New-Item -ItemType Directory -Path (Join-Path $root 'work') -Force
 $keyRoot=Join-Path $root 'key-custody';$null=New-Item -ItemType Directory -Path $keyRoot
 [IO.File]::WriteAllText((Join-Path $keyRoot 'library.ps1'),([IO.File]::ReadAllText((Join-Path $PSScriptRoot 'PaytmGatewayKeyCustody.ps1'))+"`n"+$workerMock))
 [IO.File]::WriteAllText((Join-Path $keyRoot 'native.ps1'),'# Test fixture, no native tool invoked.')
 $global:fixture=@{root=$root;case=$case;task=$null;registers=0;starts=0;disables=0;stops=0;removes=0;password=$null;passwordSupplied=$false;nativeCalls=@();lastResult=267011}
 $failed=$false;$output=Join-Path $root 'output';$console=@()
 try{$console=@(& (Join-Path $scripts 'TestPaytmGatewayScheduledSigning.ps1') -CustodyReportPath 'fixture' -OutputDirectory $output 6>&1)}catch{$failed=$true}
 $files=@(Get-ChildItem -LiteralPath $output -Filter '*.json');Check ($files.Count -eq 1) ('one report '+$case)
 $raw=[IO.File]::ReadAllText($files[0].FullName);$r=$raw|ConvertFrom-Json
 Check ($failed -eq ($case -cne 'pass')) ('result '+$case+' '+$r.failure+' '+($r.failureDetails|ConvertTo-Json -Compress))
 Check ($raw -notmatch 'FixturePassword|PRIVATE KEY' -and ($console -join '') -notmatch 'FixturePassword') 'no secrets in report/console'
 Check (-not $r.networkContacted -and -not $r.agentChanged -and -not $r.keyImported -and -not $r.ordersEnabled -and -not $r.productionSupervisorInstalled) 'scope unchanged'
 if($null -ne $global:fixture.password){$disposed=$false;try{$p=$global:fixture.password.Copy();$p.Dispose()}catch{$disposed=$true};Check $disposed 'secure password disposed'}
 if($case -cin @('cancel','prerequisiteFailure','existingTask')){Check ($global:fixture.registers -eq 0 -and -not $r.stagingCreated) 'preflight no mutations'}
 if($case -ceq 'pass'){
  Check ($r.worker.signingChecks -eq 2 -and $r.worker.sessionId -eq 0 -and $r.taskRemoved -and $null -eq $global:fixture.task) 'actual generated worker and cleanup pass'
  Check ($global:fixture.passwordSupplied -and $global:fixture.nativeCalls.Count -eq 3 -and $global:fixture.starts -eq 1) 'password API and bounded signing only'
 }
 if($case -cin @('registrationAfterCreate','workerIdentity','interactiveSession','agentMissing','signFailure','taskTimeout','malformedReport','removalFailure')){
  Check ($null -ne $global:fixture.task -and -not $global:fixture.task.Settings.Enabled -and $r.taskDisabled) 'failed task retained disabled'
 }
 if($case -ceq 'definitionDrift'){Check ($r.cleanupFailure -ceq 'SCHEDULE_CLEANUP_REVIEW_REQUIRED' -and $global:fixture.disables -eq 0 -and $global:fixture.starts -eq 0 -and -not $r.taskDefinition.argumentsMatch) 'do not operate changed task; capture mismatch'}
 if($case -ceq 'registrationFailure'){Check ($null -eq $global:fixture.task -and $global:fixture.disables -eq 0) 'no cleanup of absent task'}
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
Write-Host "PASS: $checks assertions, $($cases.Count) mocked scheduled-task workflows; real generated worker with mocked identity/native tools. No real task, credential, key or network changes."
