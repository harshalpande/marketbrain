#Requires -Version 7.0
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'PaytmListenerPolicyProbes.ps1')
$checks=0
function Check($Ok,$Name){if(-not $Ok){throw "LISTENER_TEST_$Name"};$script:checks++}
# Real sockets, OS-selected ephemeral port; never use the gateway's port locally.
$listener=[Net.Sockets.TcpListener]::new([Net.IPAddress]::Loopback,0)
$listener.Server.ExclusiveAddressUse=$true
try{
 $listener.Start();$port=$listener.LocalEndpoint.Port
 $r=Test-PaytmExclusiveBindDenied $port
 Check $r.denied 'ACTUAL_DUPLICATE_BIND_DENIED'
 Check ($r.socketError -in @('AddressAlreadyInUse','AccessDenied')) 'EXPECTED_SOCKET_ERROR'
}finally{$listener.Stop()}
$r=Test-PaytmExclusiveBindDenied $port
Check (-not $r.denied) 'FREE_PORT_NOT_DENIAL'
$fixture=Join-Path ([IO.Path]::GetTempPath()) ('listener-policy-'+[guid]::NewGuid().ToString('N'))
$null=New-Item -ItemType Directory -Path $fixture
try{
 Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'PaytmSupervisorTransport.ps1') -Destination (Join-Path $fixture 'transport.ps1')
 Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'PaytmGatewaySupervisor.ps1') -Destination (Join-Path $fixture 'gateway.ps1')
 $m=@{hashes=@{}}
 foreach($n in @('transport.ps1','gateway.ps1')){$m.hashes[$n]=(Get-FileHash -LiteralPath (Join-Path $fixture $n)).Hash}
 function Get-PaytmHostContract {@{root=$fixture}}
 function Get-PaytmTransportListeners {@([pscustomobject]@{Address='127.0.0.1';Port=18889;ProcessId=1234})}
 function Test-PaytmExclusiveBindDenied {param($Port) if($Port -ne 18889){throw 'PORT_CHANGED'};@{denied=($script:mode -ne 'BIND_ALLOWED');socketError='AddressAlreadyInUse'}}
 $script:mode='PASS';$script:rows=@()
 Invoke-PaytmListenerPolicyBatch $m @{childProcessId=1234} {param($r)$script:rows+=,$r}
 Check ($rows.Count -eq 15 -and @($rows|Where-Object passed -NE $true).Count -eq 0) 'ALL_FIFTEEN_CHECKS'
 Check (@($rows|Where-Object scope -EQ 'ISOLATED_INSTALLED_POLICY').Count -eq 12) 'POLICY_SCOPE_EXPLICIT'
 $script:mode='BIND_ALLOWED';$script:rows=@();$rejected=$false
 try{Invoke-PaytmListenerPolicyBatch $m @{childProcessId=1234} {param($r)$script:rows+=,$r}}catch{$rejected=$_.Exception.Message -ceq 'LISTENER_POLICY_DUPLICATE_BIND_NOT_DENIED'}
 Check ($rejected -and -not $rows[-1].passed) 'UNEXPECTED_BIND_FAILURE_RECORDED'
 $rejected=$false
 try{Get-PaytmInstalledFunctionText (Join-Path $fixture 'transport.ps1') ('0'*64) @('Assert-PaytmTransportListener')}catch{$rejected=$_.Exception.Message -ceq 'LISTENER_POLICY_SOURCE_DRIFT'}
 Check $rejected 'HASH_DRIFT_REJECTED'
 $rejected=$false
 try{Get-PaytmInstalledFunctionText (Join-Path $fixture 'transport.ps1') $m.hashes.'transport.ps1' @('MissingFunction')}catch{$rejected=$_.Exception.Message -ceq 'LISTENER_POLICY_FUNCTION_COUNT'}
 Check $rejected 'MISSING_FUNCTION_REJECTED'
}finally{
 foreach($n in @('transport.ps1','gateway.ps1')){Remove-Item -LiteralPath (Join-Path $fixture $n)}
 [IO.Directory]::Delete($fixture,$false)
}
@{status='LISTENER_POLICY_LOCAL_PASSED';assertions=$checks;installedPolicyChecks=15;realLocalSockets=$true;productionGatewayAccessed=$false}|ConvertTo-Json
