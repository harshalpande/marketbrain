#Requires -Version 5.1
$ErrorActionPreference='Stop'
foreach($name in @('PaytmSupervisorHost.ps1','PaytmGatewaySupervisor.ps1','PaytmSupervisorTransport.ps1','PaytmManagedTransport.ps1')){. ([scriptblock]::Create([IO.File]::ReadAllText((Join-Path $PSScriptRoot $name))))}
$checks=0
function Check($Value,$Name){if(-not $Value){throw "TRANSPORT_TEST_$Name"};$script:checks++}
function Reject($Body,$Name){$failed=$false;try{&$Body}catch{$failed=$true};Check $failed $Name}
$temp=Join-Path ([IO.Path]::GetTempPath()) ('mb-transport-tests-'+[guid]::NewGuid().ToString('N'));$null=New-Item -ItemType Directory -Path $temp
try{
 Assert-PaytmTransportListener $null;Check $true 'EMPTY_OUTPUT_IS_FREE'
 $row=[pscustomobject]@{Address='127.0.0.1';Port=18889;ProcessId=123}
 Assert-PaytmTransportListener @($row) 123;Check $true 'OWNED_LISTENER'
 Reject {Assert-PaytmTransportListener @($row)} 'OCCUPIED'
 foreach($address in @('0.0.0.0','::','::1','192.0.2.1')){$copy=$row.PSObject.Copy();$copy.Address=$address;Reject {Assert-PaytmTransportListener @($copy) 123} 'WRONG_BIND'}
 Reject {Assert-PaytmTransportListener @($row,$row) 123} 'DUPLICATE_LISTENERS'
 Reject {Assert-PaytmTransportListener @($row) 124} 'FOREIGN_OWNER'
 foreach($pair in @(@('Host key verification failed','HOST_KEY_CHANGED'),@('Permission denied (publickey)','KEY_DENIED'),@('bind: Address already in use','LISTENER_CONFLICT'),@('administratively prohibited','DESTINATION_DRIFT'),@('Connection reset by peer','NETWORK_UNAVAILABLE'),@('other','UNKNOWN'))){Check ((Get-PaytmTransportFailure $pair[0]) -ceq $pair[1]) 'ERROR_CLASSIFICATION'}
 $id='a'*32
 Write-PaytmHostJson (Join-Path $temp 'transport-control.json') @{version=1;installationId=$id;mode='ENABLED'}
 Check ((Read-PaytmTransportControl $temp $id) -ceq 'ENABLED') 'CONTROL'
 Reject {Read-PaytmTransportControl $temp ('b'*32)} 'CONTROL_ID'
 Write-PaytmHostJson (Join-Path $temp 'transport-control.json') @{version=1;installationId=$id;mode='OTHER'}
 Reject {Read-PaytmTransportControl $temp $id} 'CONTROL_MODE'
 $curlResult=[pscustomobject]@{TimedOut=$false;ExitCode=7;Output='403|0|000'}
 function Invoke-PaytmTransportCurl($Url){
  if($Url -eq 'http://developer.paytmmoney.com/'){return [pscustomobject]@{TimedOut=$false;ExitCode=0;Output='000|0|403'}}
  $curlResult
 }
 foreach($code in @(7,56)){$curlResult.ExitCode=$code;Assert-PaytmTransportDenials;Check $true 'CONNECT_DENIED_CURL_VARIANT'}
 $curlResult.Output='000|0|000';Reject {Assert-PaytmTransportDenials} 'NO_PROXY_RESPONSE_NOT_DENIAL'
 $curlResult.Output='200|0|200';Reject {Assert-PaytmTransportDenials} 'PERMITTED_DESTINATION_NOT_DENIAL'
 $curlResult.Output='403|0|000';$curlResult.TimedOut=$true;Reject {Assert-PaytmTransportDenials} 'TIMEOUT_NOT_DENIAL'
 $fixture=@{scenario='';signs=0;starts=0;disposed=0;sleeps=0;stage=0;child=$null;clock=$null;report=$null;observed=[Collections.Generic.List[string]]::new()}
 function Test-PaytmHostSigning {$fixture.signs++}
 function Start-PaytmTransportChild {
  $fixture.starts++
  $v=[pscustomobject]@{Id=(100+$fixture.starts);StartTicks=12345L;Exited=$false;ErrorTail='Authenticated to 130.250.191.137 using "publickey"';Disposed=$false}
  if($fixture.scenario -eq 'host_change'){$v.ErrorTail='Host key verification failed'}
  if($fixture.scenario -eq 'unknown_exit'){$v.ErrorTail='unknown failure';$v.Exited=$true}
  $v|Add-Member ScriptMethod Dispose {$this.Disposed=$true;$fixture.disposed++}
  $fixture.child=$v;$v
 }
 function Get-PaytmTransportListeners {
  if($fixture.child -and -not $fixture.child.Disposed){[pscustomobject]@{Address='127.0.0.1';Port=18889;ProcessId=$fixture.child.Id}}
 }
 function Test-PaytmTransportTls {if($fixture.scenario -eq 'tls_fail'){throw 'TRANSPORT_TLS_FAILED'};[pscustomobject]@{ok=$true;httpStatus=503}}
 function Assert-PaytmTransportDenials {}
 function Start-Sleep {
  $fixture.sleeps++;if($fixture.sleeps -gt 80){throw 'TEST_LOOP_LIMIT'}
  $fixture.clock.Elapsed=$fixture.clock.Elapsed.Add([TimeSpan]::FromSeconds(1));$phase=$fixture.report.phase;$fixture.observed.Add($phase)
  if($phase -eq 'TRANSPORT_READY' -and $fixture.stage -eq 0){$fixture.child.Exited=$true;$fixture.stage=1}
  elseif($phase -eq 'BACKOFF'){$fixture.clock.Elapsed=$fixture.clock.Elapsed.Add([TimeSpan]::FromSeconds(6))}
  elseif($phase -eq 'TRANSPORT_READY' -and $fixture.stage -eq 1){Write-PaytmHostJson (Join-Path $temp 'transport-control.json') @{version=1;installationId=$id;mode='DISABLED'};$fixture.stage=2}
  elseif($phase -eq 'LOCKED' -and $fixture.stage -eq 2){Write-PaytmHostJson (Join-Path $temp 'transport-control.json') @{version=1;installationId=$id;mode='ENABLED'};$fixture.stage=3}
  elseif($phase -eq 'TRANSPORT_READY' -and $fixture.stage -eq 3){Write-PaytmHostJson (Join-Path $temp 'control.json') @{version=1;installationId=$id;mode='STOP'}}
 }
 foreach($scenario in @('lifecycle','host_change','unknown_exit','tls_fail','persistent_stop')){
  $fixture.scenario=$scenario;$fixture.signs=0;$fixture.starts=0;$fixture.disposed=0;$fixture.sleeps=0;$fixture.stage=0;$fixture.child=$null;$fixture.observed.Clear()
  $fixture.clock=[pscustomobject]@{Elapsed=[TimeSpan]::Zero}
  $fixture.report=[ordered]@{installationId=$id;sequence=0;networkContacted=$false;brokerReady=$false;ordersEnabled=$false;signingVerified=$false}
  Write-PaytmHostJson (Join-Path $temp 'control.json') @{version=1;installationId=$id;mode=$(if($scenario -eq 'persistent_stop'){'STOP'}else{'LOCKED'})}
  Write-PaytmHostJson (Join-Path $temp 'transport-control.json') @{version=1;installationId=$id;mode='ENABLED'}
  if($scenario -in @('lifecycle','persistent_stop')){
   Invoke-PaytmTransportLoop $temp $temp $temp $fixture.report $fixture.clock
   Check ($fixture.report.phase -eq 'STOPPED' -and $fixture.report.childProcessId -eq 0) 'STOPPED'
   if($scenario -eq 'lifecycle'){Check ($fixture.starts -eq 3 -and $fixture.disposed -eq 3) 'RECONNECT_DISABLE_STOP';Check ($fixture.observed.Contains('BACKOFF') -and $fixture.observed.Contains('LOCKED') -and $fixture.observed.Contains('TRANSPORT_READY')) 'PHASES'}
   else{Check ($fixture.signs -eq 0 -and $fixture.starts -eq 0 -and -not $fixture.report.networkContacted) 'STOP_STARTUP_NO_SIGN_OR_CONNECT'}
  }else{
   Reject {Invoke-PaytmTransportLoop $temp $temp $temp $fixture.report $fixture.clock} 'SECURITY_LATCH'
   Check ($fixture.starts -eq 1 -and $fixture.disposed -eq 1) 'NO_SECURITY_RETRY_CHILD_CLOSED'
  }
  Check (-not $fixture.report.brokerReady -and -not $fixture.report.ordersEnabled) 'NO_AUTHORITY'
 }
 Remove-Item Function:\Start-Sleep
 [pscustomobject]@{status='TRANSPORT_ADAPTER_PASSED';assertions=$checks;loopWorkflows=5;networkAndSigningMocked=$true;realAtomicHeartbeatFiles=$true}|ConvertTo-Json
}finally{
 $resolved=[IO.Path]::GetFullPath($temp);$base=[IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\')+'\'
 if(-not $resolved.StartsWith($base,[StringComparison]::OrdinalIgnoreCase) -or [IO.Path]::GetFileName($resolved) -notmatch '^mb-transport-tests-[a-f0-9]{32}$'){throw 'UNSAFE_TEST_CLEANUP'}
 Remove-Item -LiteralPath $resolved -Recurse -Force
}
