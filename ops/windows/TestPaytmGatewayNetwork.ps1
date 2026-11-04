#Requires -Version 7.0
$ErrorActionPreference='Stop'
foreach($n in @('PaytmSupervisorHost.ps1','PaytmGatewayFailureEvidence.ps1','PaytmGatewayNetwork.ps1')){. (Join-Path $PSScriptRoot $n)}
Set-StrictMode -Version Latest
$temp=Join-Path ([IO.Path]::GetTempPath()) ('mb-network-test-'+[guid]::NewGuid().ToString('N'));$null=New-Item -ItemType Directory -Path $temp
$f=@{};$report=@{};$checks=0;$application=@{BootId='boot'}
function Check($Ok,$Name){if(-not $Ok){throw "NETWORK_TEST_$Name"};$script:checks++}
function Get-PaytmHostContract {@{root=$f.root;work=$f.root;executable='C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe'}}
function Assert-PaytmAccountPath($Path){$Path}
function Set-PaytmAccountDirectoryAcl {}
function Get-PaytmKeyContract {@{accountSid='fixture'}}
function Save-Report {Write-PaytmHostJson (Join-Path $f.root 'report.json') $report}
function Cancellation-Step {Save-Report}
function Import-Module {}
function Get-NetFirewallProfile {@{Enabled=($f.case -ne 'profile')};@{Enabled=$true};@{Enabled=$true}}
function Get-ScheduledTask {@($f.tasks.Values)}
function Get-PaytmProbeTask($Name){if($f.tasks.ContainsKey($Name)){$f.tasks[$Name]}}
function Get-NetFirewallRule {param($PolicyStore);foreach($r in $f.rules.Values){if(-not ($f.case -eq 'ineffective' -and $PolicyStore -eq 'ActiveStore' -and $r.Enabled -eq 'True')){$r}}}
function New-NetFirewallRule {
 param($Name,$DisplayName,$Group,$Description,$Direction,$Action,$Enabled,$Profile,$Protocol,$RemotePort,$RemoteAddress,$Program,$PolicyStore)
 if($f.case -eq 'create_failure' -and $Enabled -eq 'True'){throw 'NETWORK_FIXTURE_CREATE_FAILED'}
 $f.rules[$Name]=[pscustomobject]@{Name=$Name;Group=$Group;Description=$Description;Direction=$Direction;Action=$Action;Enabled=$Enabled;Profile=$Profile;Protocol=$Protocol;RemotePort=$RemotePort;RemoteAddress=$(if($f.case -eq 'scope'){'0.0.0.0/0'}else{$RemoteAddress});Program=$Program}
 if($f.case -eq 'program'){$f.rules[$Name].Program='Any'}
 if($f.case -eq 'port'){$f.rules[$Name].RemotePort='Any'}
 if($f.case -eq 'direction'){$f.rules[$Name].Direction='Inbound'}
 if($Enabled -eq 'True'){$f.blocked=$true;$f.blocks++}
}
function Get-NetFirewallApplicationFilter {param([Parameter(ValueFromPipeline)]$InputObject);process{@{Program=$InputObject.Program}}}
function Get-NetFirewallPortFilter {param([Parameter(ValueFromPipeline)]$InputObject);process{@{Protocol=$InputObject.Protocol;RemotePort=$InputObject.RemotePort;LocalPort='Any'}}}
function Get-NetFirewallAddressFilter {param([Parameter(ValueFromPipeline)]$InputObject);process{@{RemoteAddress=$InputObject.RemoteAddress;LocalAddress='Any'}}}
function Remove-NetFirewallRule {param($InputObject);if($f.case -eq 'cleanup_failure' -and $InputObject.Enabled -eq 'True'){throw 'NETWORK_FIXTURE_REMOVE_FAILED'};$f.rules.Remove($InputObject.Name);if($InputObject.Enabled -eq 'True'){$f.blocked=$false}}
function New-ScheduledTaskAction {param($Execute,$Argument,$WorkingDirectory);@{Execute=$Execute;Arguments=$Argument;WorkingDirectory=$WorkingDirectory}}
function New-ScheduledTaskPrincipal {param($UserId,$LogonType,$RunLevel);@{UserId=$UserId;LogonType=$LogonType;RunLevel=$RunLevel}}
function New-ScheduledTaskSettingsSet {param($MultipleInstances,[switch]$AllowStartIfOnBatteries,[switch]$DontStopIfGoingOnBatteries);@{MultipleInstances=$MultipleInstances;Enabled=$true;ExecutionTimeLimit='PT5M'}}
function New-ScheduledTaskTrigger {param([switch]$AtStartup);@{Enabled=$true;CimClass=@{CimClassName='MSFT_TaskBootTrigger'}}}
function New-ScheduledTask {param($Action,$Principal,$Settings,$Trigger,$Description);@{Actions=@($Action);Principal=$Principal;Settings=$Settings;Triggers=@($Trigger);Description=$Description;State='Ready'}}
function Register-ScheduledTask {param($TaskName,$TaskPath,$InputObject);$f.tasks[$TaskName]=$InputObject}
function Unregister-ScheduledTask {param($TaskName,$TaskPath,[switch]$Confirm);$f.tasks.Remove($TaskName)}
function Get-ScheduledTaskInfo {@{LastTaskResult=0}}
function Publish-Guard($Task,$Phase){
 Write-PaytmHostJson (Join-Path $Task.Actions[0].WorkingDirectory 'cleanup.json') @{runId=$Task.Description;systemIdentity=$true;failure=$(if($f.case -eq 'rehearsal'){'fixture'}else{$null});phase=$Phase;elapsedSeconds=1;ruleRemoved=($Phase -eq 'REMOVED')}
}
function Start-ScheduledTask {param($TaskName,$TaskPath);
 $t=$f.tasks[$TaskName];$t.State='Running';Publish-Guard $t READY
 $r=@(Get-NetFirewallRule|Where-Object Name -CEQ $TaskName)
 if($r.Count -and $r[0].Enabled -eq 'False'){Remove-NetFirewallRule $r[0];$t.State='Ready';Publish-Guard $t REMOVED}
}
function Start-Sleep {
 param($Milliseconds)
 foreach($t in @($f.tasks.Values)){if(Test-Path -LiteralPath (Join-Path $t.Actions[0].WorkingDirectory 'release')){$t.State='Ready';Publish-Guard $t REMOVED}}
 if($f.backoff){$f.seq++;Write-Backoff}
}
function Snapshot($Recovered=$false){@{installationId='installation';instanceId=$(if($Recovered -and $f.case -eq 'new_worker'){'different'}else{'same'});processId=10;childProcessId=$(if($Recovered){12}else{11});transportState=@{attempts=$(if($Recovered){3}else{1});failures=0}}}
function Wait-PaytmManagedHost {Snapshot ($f.kills -gt 0)}
function Get-PaytmOwnedHostTask {@{State='Running'}}
function Get-PaytmTransportListeners {@()}
function Assert-PaytmTransportListener {}
function Assert-PaytmHostAdvance($A,$B){if($A.instanceId -ne $B.instanceId -or $A.sequence -ge $B.sequence){throw 'NETWORK_FIXTURE_HEARTBEAT'}}
function Write-Backoff {
 Write-PaytmHostJson (Join-Path $f.root 'status.json') @{instanceId='same';processId=10;sequence=$f.seq;phase=$(if($f.case -eq 'blocked_worker'){'BLOCKED'}elseif($f.case -eq 'ineffective_connection'){'TRANSPORT_READY'}else{'BACKOFF'});failure=$null;brokerReady=$false;ordersEnabled=$false;transportState=@{attempts=2;failures=2};lastSshAttempt=$(if($f.case -eq 'stale_attempt'){1}else{2});lastSshObservation=@{exited=$true;stderrDrained=($f.case -ne 'undrained');authenticated=($f.case -eq 'forced_kill_only');reason='NETWORK_UNAVAILABLE';tags=@('TCP_CONNECT_DENIED')}}
}
function Stop-PaytmReviewedChild {$f.kills++;$f.backoff=$true;Write-Backoff}
function Invoke-PaytmApplicationHead($Label,$Expected){
 if(-not $Expected -and $f.case -eq 'fallback'){throw 'NETWORK_DIRECT_FALLBACK'}
 if($Expected -and $f.blocked){throw 'NETWORK_BLOCK_NOT_REMOVED'}
 $report.applicationRouteChecks.Add(@{label=$Label;passed=$true});$f.locked=-not $Expected
}
function Invoke-PaytmApplicationHttp {@{status=$(if($f.case -eq 'rearm'){'ARMED'}else{'LOCKED'});bootId='boot'}}
try{
 $cases=@('pass','profile','rehearsal','scope','program','port','direction','create_failure','ineffective','ineffective_connection','blocked_worker','fallback','new_worker','rearm','cleanup_failure')
 foreach($case in $cases){
  $root=Join-Path $temp $case;$null=New-Item -ItemType Directory -Path $root
  $f=@{case=$case;root=$root;tasks=@{};rules=@{};blocked=$false;blocks=0;kills=0;backoff=$false;seq=10;locked=$true}
  $report=@{runId=[guid]::NewGuid().ToString('N');networkInterruptionAttempted=$false;networkCleanupRehearsalPassed=$false;networkLossObserved=$false;networkRecoveryPassed=$false;noAutomaticRearmPassed=$false;cleanupTasksRegistered=0;cleanupFailure=$null;applicationRouteChecks=[Collections.Generic.List[object]]::new()}
  $failed=$false;$reason='';try{Invoke-PaytmNetworkBatch 'installation' $PSScriptRoot}catch{$failed=$true;$reason=$_.Exception.Message;if($case -eq 'pass'){throw}}
  if($case -eq 'pass'){
   Check (-not $failed -and $report.networkCleanupRehearsalPassed -and $report.networkLossObserved -and $report.networkRecoveryPassed -and $report.noAutomaticRearmPassed) 'BATCH_PASS'
   Check ($f.blocks -eq 1 -and $f.kills -eq 1 -and $report.applicationRouteChecks.Count -eq 3) 'ONE_FAULT_THREE_APPLICATION_CHECKS'
   Check ($report.networkObservations.Count -eq 1 -and $report.networkLastObservation.ssh.reason -ceq 'NETWORK_UNAVAILABLE') 'NETWORK_OBSERVATIONS_SAVED'
  }else{Check ($failed -or $null -ne $report.cleanupFailure) ($case+'_FAIL_CLOSED')}
  if($case -eq 'ineffective_connection'){Check ($reason -ceq 'NETWORK_BLOCK_INEFFECTIVE' -and -not $report.networkLossObserved -and $report.networkLastObservation.waitSeconds -lt 5) 'INEFFECTIVE_FAULT_FAILS_EARLY'}
  if($case -eq 'cleanup_failure'){Check ($report.cleanupFailure -eq 'NETWORK_GUARD_CLEANUP_REVIEW_REQUIRED' -and $f.rules.Count -eq 1 -and $f.tasks.Count -eq 1) 'INDEPENDENT_GUARD_RETAINED'}
  else{Check ($f.rules.Count -eq 0 -and $f.tasks.Count -eq 0) ($case+'_OWNED_RESOURCES_REMOVED')}
  if($case -in @('profile','rehearsal','scope','program','port','direction')){Check ($f.blocks -eq 0 -and $f.kills -eq 0) 'FAILED_REHEARSAL_NO_OUTAGE'}
 }
 foreach($case in @('forced_kill_only','stale_attempt','undrained')){
  $f.case=$case;$f.backoff=$true;$f.seq=10;Write-Backoff
  $reason='';try{$null=Wait-PaytmNetworkBackoff (Snapshot) 1}catch{$reason=$_.Exception.Message}
  Check ($reason -ceq 'NETWORK_BACKOFF_NOT_OBSERVED') ($case+'_NOT_NETWORK_PROOF')
  Check ($report.networkObservations.Count -eq 1 -and $report.networkLastObservation.sequence -gt 10) ($case+'_OBSERVATIONS_RETAINED')
 }
 [pscustomobject]@{status='NETWORK_BATCH_ENGINEERING_PASSED';assertions=$checks;workflows=$cases.Count;realGuardTaskConstructionAndRuleValidation=$true;windowsRuntimeApisMocked=$true}|ConvertTo-Json
}finally{
 $full=[IO.Path]::GetFullPath($temp);$base=[IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\')+'\'
 if(-not $full.StartsWith($base,[StringComparison]::OrdinalIgnoreCase) -or [IO.Path]::GetFileName($full) -notmatch '^mb-network-test-[a-f0-9]{32}$'){throw 'UNSAFE_FIXTURE_CLEANUP'}
 Remove-Item -LiteralPath $full -Recurse -Force
}
