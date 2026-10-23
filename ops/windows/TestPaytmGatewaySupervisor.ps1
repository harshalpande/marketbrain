#Requires -Version 7.0
[CmdletBinding()]param([switch]$AsObject)
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'PaytmGatewaySupervisor.ps1')
. (Join-Path $PSScriptRoot 'PaytmTunnelVerification.ps1')
$checks=[Collections.Generic.List[object]]::new();$watch=[Diagnostics.Stopwatch]::StartNew()
function Check([bool]$Value,[string]$Name){
    $checks.Add([pscustomobject]@{name=$Name;passed=$Value})
    if(-not $Value){throw "SUPERVISOR_TEST_FAILED: $Name"}
}
function Reject([scriptblock]$Action,[string]$Name){$rejected=$false;try{&$Action|Out-Null}catch{$rejected=$true};Check $rejected $Name}
function Ready($State,[long]$Seconds){Step-PaytmGatewayState $State HEALTH_OK $Seconds -OwnedLoopbackListener $true -PinnedSshAuthenticated $true -ProxyTlsVerified $true}
$state=New-PaytmGatewayState
Check ($state.phase -ceq 'IDLE' -and -not $state.ordersEnabled) 'initial no execution authority'
$badState=New-PaytmGatewayState;$badState.phase='OTHER'
Reject {Step-PaytmGatewayState $badState TICK 0} 'unknown state fails closed'
Reject {Step-PaytmGatewayState $state HEALTH_OK 0} 'cannot claim ready before start'
$state=Step-PaytmGatewayState $state START 0
Check ($state.phase -ceq 'CONNECTING' -and $state.attempts -eq 1 -and $state.action -ceq 'START_CHILD') 'one initial child request'
Reject {Step-PaytmGatewayState $state START 0} 'duplicate start rejected'
for($i=0;$i -lt 7;$i++){
    $now=$state.lastSeconds+1;$state=Step-PaytmGatewayState $state TRANSIENT_FAILURE $now NETWORK_UNAVAILABLE
    $expected=@(5,10,20,40,60,60,60)[$i]
    Check (($state.retryAtSeconds-$now) -eq $expected -and $state.action -ceq 'STOP_OWNED_CHILD') "backoff $i is $expected seconds"
    $state=Step-PaytmGatewayState $state TICK ($state.retryAtSeconds-1)
    Check ($state.phase -ceq 'BACKOFF' -and $state.action -ceq 'NONE') "no early reconnect $i"
    $state=Step-PaytmGatewayState $state TICK ($state.retryAtSeconds)
    Check ($state.phase -ceq 'CONNECTING' -and $state.attempts -eq ($i+2)) "reconnect once $i"
}
Reject {Step-PaytmGatewayState $state TICK 0} 'monotonic regression rejected'
$state=Ready $state ($state.lastSeconds+1)
Check ($state.phase -ceq 'TRANSPORT_READY' -and -not $state.brokerReady -and -not $state.ordersEnabled) 'transport never means broker or trade ready'
Check ($state.closedOutageSeconds -eq $state.firstReadySeconds) 'initial outage measured with monotonic seconds'
Check ($state.failures -eq 7) 'brief connection does not reset flapping penalty'
$state=Ready $state ($state.lastSeconds+20);$state=Ready $state ($state.lastSeconds+20);$state=Ready $state ($state.lastSeconds+20)
Check ($state.failures -eq 0) '60 seconds healthy observations reset penalty'
$state=Step-PaytmGatewayState $state TICK ($state.lastSeconds+30)
Check ($state.phase -ceq 'BACKOFF' -and $state.reason -ceq 'HEALTH_OR_CONNECT_TIMEOUT') 'stale health closes transport readiness'
$state=Step-PaytmGatewayState $state TICK $state.retryAtSeconds
$state=Ready $state ($state.lastSeconds+30)
Check ($state.phase -ceq 'BACKOFF') 'late healthy claim cannot erase connect deadline'
foreach($reason in @('SSH_EXITED','PROXY_UNAVAILABLE')){
    $s=Step-PaytmGatewayState (New-PaytmGatewayState) START 0
    $s=Step-PaytmGatewayState $s TRANSIENT_FAILURE 1 $reason
    Check ($s.phase -ceq 'BACKOFF' -and $s.retryAtSeconds -eq 6) "ordinary interruption retry $reason"
}
foreach($reason in @('HOST_KEY_CHANGED','KEY_DENIED','LISTENER_CONFLICT','DESTINATION_DRIFT','TLS_FAILED','CREDENTIAL_MISSING','CONFIG_DRIFT','UNKNOWN')){
    $s=Step-PaytmGatewayState (New-PaytmGatewayState) START 0
    $s=Step-PaytmGatewayState $s SECURITY_FAILURE 1 $reason
    Check ($s.phase -ceq 'BLOCKED' -and $s.action -ceq 'STOP_OWNED_CHILD') "security latches $reason"
    $s=Step-PaytmGatewayState $s START 60
    Check ($s.phase -ceq 'BLOCKED' -and $s.action -ceq 'NONE') "no automatic rearm $reason"
}
foreach($proof in @(@($false,$true,$true),@($true,$false,$true),@($true,$true,$false))){
    $s=Step-PaytmGatewayState (New-PaytmGatewayState) START 0
    $s=Step-PaytmGatewayState $s HEALTH_OK 1 -OwnedLoopbackListener $proof[0] -PinnedSshAuthenticated $proof[1] -ProxyTlsVerified $proof[2]
    Check ($s.phase -ceq 'BLOCKED') 'partial readiness proof blocked'
}
$s=Step-PaytmGatewayState (New-PaytmGatewayState) START 0
$s=Step-PaytmGatewayState $s TRANSIENT_FAILURE 1 'SECRET_SENTINEL_NOT_A_REASON'
Check ($s.phase -ceq 'BLOCKED' -and ($s|ConvertTo-Json -Compress) -cnotmatch 'SECRET_SENTINEL') 'unknown failures block and redact'
foreach($phase in @('IDLE','CONNECTING','BACKOFF','TRANSPORT_READY')){
    $s=New-PaytmGatewayState
    if($phase -cne 'IDLE'){$s=Step-PaytmGatewayState $s START 0}
    if($phase -ceq 'BACKOFF'){$s=Step-PaytmGatewayState $s TRANSIENT_FAILURE 1 SSH_EXITED}
    if($phase -ceq 'TRANSPORT_READY'){$s=Ready $s 1}
    $s=Step-PaytmGatewayState $s STOP 2
    Check ($s.phase -ceq 'STOPPED' -and $s.action -ceq 'STOP_OWNED_CHILD') "stop from $phase"
    $s=Step-PaytmGatewayState $s START 100
    Check ($s.phase -ceq 'STOPPED' -and $s.action -ceq 'NONE') "stop latch from $phase"
}
$known='C:/ProgramData/MarketBrain/Gateway/known_hosts';$pub='C:/ProgramData/MarketBrain/Gateway/gateway.pub'
$arguments=Get-PaytmGatewaySshArguments $known $pub -InspectOnly
Check ($arguments -ccontains '-G' -and $arguments -ccontains '127.0.0.1:18889:127.0.0.1:18888') 'config-only fixed local forward'
Check ($arguments -ccontains 'StrictHostKeyChecking=yes' -and $arguments -ccontains 'BatchMode=yes') 'no prompt no TOFU'
Check ($arguments -ccontains 'ForwardAgent=no' -and $arguments -ccontains '-N' -and $arguments -ccontains '-T') 'no agent forwarding or remote session'
Check (-not ((Get-PaytmGatewaySshArguments $known $pub) -ccontains '-G')) 'runtime argument template separated from inspection'
foreach($path in @('relative','C:/keys/%h','C:/keys/a"b','C:/../keys','C:/keys/$(bad)',"C:/keys/a`nb")){
    Reject {Get-PaytmGatewaySshArguments $path $pub} 'unsafe config path rejected'
}
Reject {Get-PaytmGatewaySshArguments $known 'C:/keys/private.ppk'} 'private identity file not accepted'
# Native config inspector is tested separately by the bundle on the installed Windows client.
$temp=Join-Path ([IO.Path]::GetTempPath()) ('marketbrain-supervisor-'+[guid]::NewGuid().ToString('N'))
$null=New-Item -ItemType Directory -Path $temp
$lock=$null;$child=$null;$other=$null
try{
    $lockPath=Join-Path $temp 'instance.lock';$lock=Open-PaytmGatewayLock $lockPath
    Reject {Open-PaytmGatewayLock $lockPath} 'second instance cannot take owned lock'
    $lock.Dispose();$lock=$null;$lock=Open-PaytmGatewayLock $lockPath
    Check ($lock.CanWrite) 'released lock can be reacquired'
    $executable=Join-Path $PSHOME 'pwsh.exe'
    # Known fixture only: no server, keys, network or external command. Hidden children.
    $child=Start-TunnelProcess $executable @('-NoLogo','-NoProfile','-NonInteractive','-Command','Start-Sleep -Seconds 30')
    $other=Start-TunnelProcess $executable @('-NoLogo','-NoProfile','-NonInteractive','-Command','Start-Sleep -Seconds 30')
    $result=Complete-TunnelProcess $child -StopNow
    Check ($result.StoppedByRunner) 'cancel terminates exact owned fixture'
    Check (-not $other.Process.HasExited) 'cancel does not terminate another fixture'
    $result=Complete-TunnelProcess $other -LimitSeconds 1
    Check ($result.StoppedByRunner) 'bounded timeout stops owned fixture'
}finally{
    foreach($handle in @($child,$other)){if($null -ne $handle -and $null -eq $handle.Result){$null=Complete-TunnelProcess $handle -StopNow}}
    if($null -ne $lock){$lock.Dispose()}
    # Exact files created above, no recursive cleanup or unrelated path deletion.
    if(Test-Path -LiteralPath (Join-Path $temp 'instance.lock')){Remove-Item -LiteralPath (Join-Path $temp 'instance.lock')}
    [IO.Directory]::Delete($temp,$false)
}
$watch.Stop()
$result=[pscustomobject]@{status='ENGINEERING_CHECKS_PASSED';assertions=$checks.Count;checks=$checks.ToArray();elapsedSeconds=[math]::Round($watch.Elapsed.TotalSeconds,3);realNetworkRecoveryTested=$false;scheduledTaskTested=$false;credentialCustodyTested=$false;gatewayActivated=$false;ordersEnabled=$false}
if($AsObject){return $result}
$result|ConvertTo-Json -Depth 5
