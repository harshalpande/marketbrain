# No installed state changes. Socket observation is real; state-machine inputs are isolated.
function Get-PaytmInstalledFunctionText([string]$Path,[string]$Hash,[string[]]$Names) {
 if((Get-FileHash -LiteralPath $Path).Hash -cne $Hash){throw 'LISTENER_POLICY_SOURCE_DRIFT'}
 $tokens=$null;$errors=$null
 $ast=[Management.Automation.Language.Parser]::ParseFile($Path,[ref]$tokens,[ref]$errors)
 if($errors.Count){throw 'LISTENER_POLICY_PARSE'}
 $text=@()
 foreach($n in $Names){
  $nodes=@($ast.FindAll({param($a)$a -is [Management.Automation.Language.FunctionDefinitionAst] -and $a.Name -ceq $n},$true))
  if($nodes.Count -ne 1){throw 'LISTENER_POLICY_FUNCTION_COUNT'}
  $text+=$nodes[0].Extent.Text
 }
 if((Get-FileHash -LiteralPath $Path).Hash -cne $Hash){throw 'LISTENER_POLICY_SOURCE_DRIFT'}
 $text -join "`n"
}
function Test-PaytmExclusiveBindDenied([int]$Port) {
 $socket=[Net.Sockets.Socket]::new([Net.Sockets.AddressFamily]::InterNetwork,[Net.Sockets.SocketType]::Stream,[Net.Sockets.ProtocolType]::Tcp)
 try{
  $socket.ExclusiveAddressUse=$true
  try{$socket.Bind([Net.IPEndPoint]::new([Net.IPAddress]::Loopback,$Port));return @{denied=$false;socketError='NONE'}}
  catch [Net.Sockets.SocketException]{
   $code=$_.Exception.SocketErrorCode.ToString()
   return @{denied=($code -cin @('AddressAlreadyInUse','AccessDenied'));socketError=$code}
  }
 }finally{$socket.Dispose()}
}
function Invoke-PaytmListenerPolicyBatch($Manifest,$Worker,[scriptblock]$Record) {
 $root=(Get-PaytmHostContract).root
 . ([scriptblock]::Create((Get-PaytmInstalledFunctionText (Join-Path $root 'transport.ps1') $Manifest.hashes.'transport.ps1' @('Assert-PaytmTransportListener'))))
 . ([scriptblock]::Create((Get-PaytmInstalledFunctionText (Join-Path $root 'gateway.ps1') $Manifest.hashes.'gateway.ps1' @('New-PaytmGatewayState','Step-PaytmGatewayState'))))
 function Emit($Name,$Ok,$Scope){
  & $Record ([ordered]@{name=$Name;passed=[bool]$Ok;scope=$Scope})
  if(-not $Ok){throw ('LISTENER_POLICY_FAILED_'+$Name)}
 }
 Write-Host '[25%] Verify real listener ownership and duplicate bind protection'
 $rows=@(Get-PaytmTransportListeners)
 Assert-PaytmTransportListener $rows $Worker.childProcessId
 Emit 'ACTUAL_OWNED_LOOPBACK_LISTENER' $true 'REAL_LISTENER'
 $wrongOwner=if($Worker.childProcessId -eq 1){2}else{1}
 $rejected=$false
 try{Assert-PaytmTransportListener $rows $wrongOwner}catch{$rejected=$_.Exception.Message -ceq 'TRANSPORT_LISTENER_CONFLICT'}
 Emit 'INSTALLED_GUARD_REJECTS_WRONG_OWNER' $rejected 'INSTALLED_FUNCTION_REAL_ROWS_SYNTHETIC_OWNER'
 $bind=Test-PaytmExclusiveBindDenied 18889
 & $Record ([ordered]@{name='DUPLICATE_BIND_DENIED';passed=$bind.denied;socketError=$bind.socketError;scope='REAL_SOCKET'})
 if(-not $bind.denied){throw 'LISTENER_POLICY_DUPLICATE_BIND_NOT_DENIED'}
 Assert-PaytmTransportListener @(Get-PaytmTransportListeners) $Worker.childProcessId
 Write-Host '[50%] Installed security-latch and health-deadline rules with isolated inputs'
 Write-Progress -Activity 'Listener and installed policy checks' -Status 'Isolated policy inputs' -PercentComplete 50
 foreach($reason in @('HOST_KEY_CHANGED','KEY_DENIED','LISTENER_CONFLICT','DESTINATION_DRIFT','TLS_FAILED','CREDENTIAL_MISSING','CONFIG_DRIFT','UNKNOWN')){
  $s=Step-PaytmGatewayState (New-PaytmGatewayState) START 0
  $blocked=Step-PaytmGatewayState $s SECURITY_FAILURE 1 $reason
  $later=Step-PaytmGatewayState $blocked TICK 100
  $rearm=Step-PaytmGatewayState $later START 101
  Emit ('LATCH_'+$reason) ($blocked.phase -ceq 'BLOCKED' -and $blocked.action -ceq 'STOP_OWNED_CHILD' -and $rearm.phase -ceq 'BLOCKED' -and $rearm.action -ceq 'NONE' -and $rearm.attempts -eq 1 -and -not $rearm.ordersEnabled -and -not $rearm.brokerReady) 'ISOLATED_INSTALLED_POLICY'
 }
 $s=Step-PaytmGatewayState (New-PaytmGatewayState) START 0
 $ready=Step-PaytmGatewayState $s HEALTH_OK 1 -OwnedLoopbackListener $true -PinnedSshAuthenticated $true -ProxyTlsVerified $true
 $expired=Step-PaytmGatewayState $ready TICK 31
 Emit 'EXPIRED_HEALTH_STOPS_CHILD' ($expired.phase -ceq 'BACKOFF' -and $expired.action -ceq 'STOP_OWNED_CHILD') 'ISOLATED_INSTALLED_POLICY'
 $late=Step-PaytmGatewayState $ready HEALTH_OK 31 -OwnedLoopbackListener $true -PinnedSshAuthenticated $true -ProxyTlsVerified $true
 Emit 'LATE_SUCCESS_CANNOT_ERASE_DEADLINE' ($late.phase -ceq 'BACKOFF') 'ISOLATED_INSTALLED_POLICY'
 $regressed=$false
 try{$null=Step-PaytmGatewayState $ready TICK 0}catch{$regressed=$_.Exception.Message -ceq 'GATEWAY_MONOTONIC_TIME_REGRESSED'}
 Emit 'REGRESSED_MONOTONIC_TIME_REJECTED' $regressed 'ISOLATED_INSTALLED_POLICY'
 $unverified=Step-PaytmGatewayState $s HEALTH_OK 1
 Emit 'UNVERIFIED_HEALTH_NEVER_READY' ($unverified.phase -ceq 'BLOCKED' -and -not $unverified.brokerReady -and -not $unverified.ordersEnabled) 'ISOLATED_INSTALLED_POLICY'
 Write-Progress -Activity 'Listener and installed policy checks' -Completed
}
