#Requires -Version 7.0
$ErrorActionPreference='Stop'
foreach($n in @('PaytmSupervisorHost.ps1','PaytmManagedTransport.ps1','PaytmGatewayRestart.ps1','PaytmGatewayCancellation.ps1')){. (Join-Path $PSScriptRoot $n)}
$t=$null;$e=$null;$ast=[Management.Automation.Language.Parser]::ParseFile((Join-Path $PSScriptRoot 'TestPaytmGatewayRestartRules.ps1'),[ref]$t,[ref]$e)
foreach($f in $ast.FindAll({param($a)$a -is [Management.Automation.Language.FunctionDefinitionAst] -and $a.Name -in @('Worker','Observation')},$true)){. ([scriptblock]::Create($f.Extent.Text))}
$checks=0
function Check($Ok,$Name){if(-not $Ok){throw "CANCEL_RULE_$Name"};$script:checks++}
function Reject($Body,$Name){$failed=$false;try{&$Body}catch{$failed=$true};Check $failed $Name}
function Receipt {
 [pscustomobject]@{runId='eb86108cc1e247d68d06e135eb580bf6';status='WINDOWS_RESTART_TRANSPORT_AND_APPLICATION_ROUTE_PASSED';stage='COMPLETE';phase='After';failure=$null;cleanupFailure=$null;
 windowsRestartObserved=$true;accountPreserved=$true;finalApplicationLockVerified=$true;ownerConfirmsNoManualGatewayStart=$true;taskStartedByCollector=$false;configurationChanged=$false;rebootRequestedByCollector=$false;credentialsUsed=$false;ordersEnabled=$false;
 applicationRouteChecks=@(@{passed=$true});before=(Observation);observation=(Observation $true)}
}
Assert-PaytmRestartAcceptance (Receipt);Check $true 'ACCEPTED_RESTART'
foreach($mutation in @({param($v)$v.status='REVIEW_REQUIRED'},{param($v)$v.cleanupFailure='x'},{param($v)$v.ordersEnabled=$true},{param($v)$v.accountPreserved=$false},{param($v)$v.ownerConfirmsNoManualGatewayStart='true'},{param($v)$v.applicationRouteChecks=@()},{param($v)$v.observation.worker.denialsVerified=$false},{param($v)$v.observation.worker.instanceId=$v.before.worker.instanceId})){
 $v=Receipt;&$mutation $v;Reject {Assert-PaytmRestartAcceptance $v} 'RECEIPT_REJECT'
}
$good=@{taskIdle=$true;ownerExited=$true;childExited=$true;listenerCount=0}
Check (Test-PaytmCancellationExit $good) 'EXIT_PROOF'
foreach($n in @('taskIdle','ownerExited','childExited')){
 $v=$good.Clone();$v[$n]=$false;Check (-not (Test-PaytmCancellationExit $v)) 'STILL_ALIVE'
 $v[$n]='true';Check (-not (Test-PaytmCancellationExit $v)) 'PROOF_NOT_BOOLEAN'
}
$v=$good.Clone();$v.listenerCount=1;Check (-not (Test-PaytmCancellationExit $v)) 'ORPHAN_LISTENER'
function Get-PaytmHostContract {@{executable='fixture-owner'}}
function Assert-PaytmTransportListener($Rows,$Owner){if($fixture.listenerConflict){throw 'TRANSPORT_LISTENER_CONFLICT'}}
function Get-PaytmTransportListeners {@()}
function FakeProcess($Path,$Session=0){
 $p=[pscustomobject]@{Path=$Path;SessionId=$Session;StartTime=[DateTime]::new(123,[DateTimeKind]::Utc);Handle=1;HasExited=$false;disposed=$false}
 $p|Add-Member -MemberType ScriptMethod -Name Dispose -Value {$this.disposed=$true};$p
}
function Get-Process($Id){if($Id -eq 100){$fixture.owner}else{$fixture.child}}
foreach($scenario in @('pass','wrong_owner','wrong_session','wrong_child','wrong_birth','listener_conflict')){
 $fixture=@{owner=(FakeProcess fixture-owner);child=(FakeProcess 'C:\Windows\System32\OpenSSH\ssh.exe');listenerConflict=($scenario -eq 'listener_conflict')}
 switch($scenario){wrong_owner{$fixture.owner.Path='other'}wrong_session{$fixture.owner.SessionId=1}wrong_child{$fixture.child.Path='other'}wrong_birth{$fixture.child.StartTime=[DateTime]::new(124,[DateTimeKind]::Utc)}}
 if($scenario -eq 'pass'){$p=Open-PaytmCancellationProcesses (Worker);Check ($p.Owner -eq $fixture.owner -and $p.Child -eq $fixture.child) 'RETAIN_HANDLES';$p.Owner.Dispose();$p.Child.Dispose()}
 else{Reject {Open-PaytmCancellationProcesses (Worker)} 'IDENTITY_OR_LISTENER'}
 Check ($fixture.owner.disposed -and $fixture.child.disposed) 'DISPOSE_HANDLES'
}
$polls=0;$never=$false
function Get-PaytmCancellationExit {
 $script:polls++
 @{taskIdle=$true;ownerExited=$true;childExited=($polls -gt 1 -and -not $never);listenerCount=0}
}
$exited=Wait-PaytmCancellationExit @{} fixture 1
Check ($polls -ge 2 -and $exited.childExited) 'WAIT_FOR_NATIVE_CHILD_EXIT'
$never=$true;Reject {Wait-PaytmCancellationExit @{} fixture 1} 'BOUNDED_ORPHAN_TIMEOUT'
[pscustomobject]@{status='GATEWAY_CANCELLATION_RULES_PASSED';assertions=$checks;runtimeApisMocked=$true}|ConvertTo-Json
