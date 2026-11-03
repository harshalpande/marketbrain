#Requires -Version 7.0
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'PaytmSupervisorHost.ps1')
. (Join-Path $PSScriptRoot 'PaytmManagedTransport.ps1')
. (Join-Path $PSScriptRoot 'PaytmGatewayRestart.ps1')
$checks=0
function Check($Ok,$Name){if(-not $Ok){throw "RESTART_TEST_$Name"};$script:checks++}
function Reject($Body,$Name){$failed=$false;try{&$Body}catch{$failed=$true};Check $failed $Name}
function Worker($Phase='TRANSPORT_READY',$Instance=('a'*32),$Seq=1,$Child=200){
 [pscustomobject]@{version=1;transportVersion=1;installationId='ea8b91471cf048aa97a0f6b939b355c7';phase=$Phase;instanceId=$Instance;sequence=$Seq;processId=100;sessionId=0;elapsedSeconds=$Seq;failure=$null;
 identityVerified=$true;jobContained=$true;agentIdentityVerified=$true;signingVerified=$true;privateCopyAbsent=$true;networkContacted=($Phase -eq 'TRANSPORT_READY');transportEnabled=($Phase -eq 'TRANSPORT_READY');brokerReady=$false;ordersEnabled=$false;denialsVerified=$true;childProcessId=$(if($Phase -eq 'TRANSPORT_READY'){$Child}else{0});childStartTicks=123;httpStatus=503;transportState=@{phase=$Phase;attempts=$Seq}}
}
function Receipt {
 $v=[pscustomobject]@{runId='8ac7cdda3ca7475eb001df485797cb70';status='MANAGED_WINDOWS_TRANSPORT_AND_APPLICATION_ROUTE_PASSED_BOOT_PENDING';stage='COMPLETE';failure=$null;cleanupFailure=$null;
 before=@{installationId='ea8b91471cf048aa97a0f6b939b355c7'};first=(Worker);duplicate=(Worker -Seq 2);reenabled=(Worker -Seq 3 -Child 201);recovered=(Worker -Seq 4 -Child 202);final=(Worker -Instance ('c'*32));
 disabled=(Worker LOCKED);stopped=(Worker STOPPED);stoppedRestart=(Worker STOPPED ('b'*32));applicationRouteChecks=@(1..4|ForEach-Object{@{passed=$true}})}
 $v.stoppedRestart.signingVerified=$false
 foreach($name in @('upgradeApplied','duplicateStartPassed','disabledRoutePassed','childRecoveryPassed','persistentStopPassed','restartPassed','finalApplicationLockVerified','accountPreserved')){$v|Add-Member $name $true}
 foreach($name in @('ordersEnabled','brokerCredentialsUsed','vpsChanged','taskReRegistered','keyImported','rebootTested')){$v|Add-Member $name $false}
 $v
}
$good=Receipt;Assert-PaytmTransportAcceptance $good;Check $true 'RECEIPT_VALID'
foreach($mutation in @({param($x)$x.failure='error'},{param($x)$x.accountPreserved=$false},{param($x)$x.ordersEnabled=$true},{param($x)$x.duplicate.childProcessId=333},{param($x)$x.recovered.childProcessId=$x.reenabled.childProcessId},{param($x)$x.stoppedRestart.networkContacted=$true},{param($x)$x.final.denialsVerified=$false},{param($x)$x.applicationRouteChecks=@()})){
 $v=Receipt;&$mutation $v;Reject {Assert-PaytmTransportAcceptance $v} 'RECEIPT_TAMPER'
}
function Observation($After=$false){[pscustomobject]@{machineHash=('A'*64);bootUtc=$(if($After){'2026-11-03T12:00:00Z'}else{'2026-11-02T12:00:00Z'});workerStartUtc='2026-11-03T12:00:32Z';collectorStartUtc='2026-11-03T12:02:00Z';taskLastRunUtc='2026-11-03T12:00:31Z';worker=(Worker -Instance $(if($After){'b'*32}else{'a'*32}))}}
$before=Observation;$after=Observation $true;Assert-PaytmRestartBoundary $before $after;Check $true 'RESTART_BOUNDARY'
foreach($mutation in @({param($x)$x.machineHash='B'*64},{param($x)$x.bootUtc='2026-11-02T12:00:00Z'},{param($x)$x.worker.instanceId='a'*32},{param($x)$x.workerStartUtc='2026-11-03T11:00:00Z'},{param($x)$x.workerStartUtc='2026-11-03T12:03:00Z'},{param($x)$x.taskLastRunUtc='2026-11-02T12:00:00Z'})){
 $v=Observation $true;&$mutation $v;Reject {Assert-PaytmRestartBoundary $before $v} 'RESTART_PROOF_REJECTION'
}
$state=[pscustomobject]@{version=1;runId=('a'*32);completed=$false;receiptHash='078A34DB0A46951EB98C5A08063F9FC76DB6EC75C175A3572CEE3D65DA4FAB4B';reportName=('paytm-gateway-restart-'+('a'*32)+'.json')}
Assert-PaytmRestartCheckpoint $state;Check $true 'CHECKPOINT'
$state.reportName='../elsewhere.json';Reject {Assert-PaytmRestartCheckpoint $state} 'REPORT_PATH'
$state.completed=$true;Reject {Assert-PaytmRestartCheckpoint $state} 'COMPLETE_NOT_REPLAYED'
$route=@{Root=$PSScriptRoot};$bootResult=@{exitCode=0;stdout='2026-11-03T12:00:00.0000000Z'}
function Invoke-PaperRuntimeProcess($Executable,$Arguments,$Directory,$LimitSeconds){
 if($Executable -cne 'C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe' -or $LimitSeconds -ne 25 -or $Arguments -notcontains '-NonInteractive'){throw 'TEST_BOOT_PROCESS_CONTRACT'}
 $bootResult
}
Check ((Get-PaytmWindowsBootUtc) -ceq $bootResult.stdout) 'BOOT_QUERY_OUTPUT'
$bootResult.exitCode=1;Reject {Get-PaytmWindowsBootUtc} 'BOOT_QUERY_EXIT'
$bootResult.exitCode=0;$bootResult.stdout='unparseable';Reject {Get-PaytmWindowsBootUtc} 'BOOT_QUERY_MALFORMED'
$bootResult.stdout="2026-11-03T12:00:00.0000000Z`nextra";Reject {Get-PaytmWindowsBootUtc} 'BOOT_QUERY_EXTRA_OUTPUT'
[pscustomobject]@{status='GATEWAY_RESTART_RULES_PASSED';assertions=$checks;runtimeAccessed=$false}|ConvertTo-Json
