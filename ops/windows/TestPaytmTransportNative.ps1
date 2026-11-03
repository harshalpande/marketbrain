#Requires -Version 5.1
$ErrorActionPreference='Stop';$checks=0;$child=$null;$listener=$null
function Check($Value,$Name){if(-not $Value){throw "NATIVE_TRANSPORT_TEST_$Name"};$script:checks++}
Add-Type -Path (Join-Path $PSScriptRoot 'PaytmTransportNative.cs')
Add-Type -Path (Join-Path $PSScriptRoot 'PaytmSupervisorNative.cs')
Add-Type -TypeDefinition @'
using System;
using System.Net;
using System.Net.Sockets;
using System.Text;
using System.Threading.Tasks;
public sealed class DenyProxyFixture : IDisposable {
 readonly TcpListener listener = new TcpListener(IPAddress.Loopback,0);
 readonly Task worker;
 public int Port {get {return ((IPEndPoint)listener.LocalEndpoint).Port;}}
 public DenyProxyFixture() {
  listener.Start(); worker=Task.Run(async () => {
   for(int i=0;i<3;i++) using(var client=await listener.AcceptTcpClientAsync()) {
    client.ReceiveTimeout=5000;client.SendTimeout=5000;
    var stream=client.GetStream();var buffer=new byte[8192];int count=0;
    do { int n=stream.Read(buffer,count,buffer.Length-count);if(n==0)throw new Exception("EOF");count+=n; }
    while(!Encoding.ASCII.GetString(buffer,0,count).Contains("\r\n\r\n") && count<buffer.Length);
    byte[] response=Encoding.ASCII.GetBytes("HTTP/1.1 403 Forbidden\r\nContent-Length: 0\r\nConnection: close\r\n\r\n");
    stream.Write(response,0,response.Length);
   }
  });
 }
 public void Dispose(){listener.Stop();if(!worker.Wait(6000))throw new Exception("FIXTURE_TIMEOUT");}
}
'@
try{
 $listener=[Net.Sockets.TcpListener]::new([Net.IPAddress]::Loopback,0);$listener.Start();$port=$listener.LocalEndpoint.Port
 $rows=@([MarketBrain.Transport.Network]::Listeners($port))
 Check ($rows.Count -eq 1 -and $rows[0].ProcessId -eq $PID -and $rows[0].Address -eq '127.0.0.1') 'ACTUAL_IPV4_OWNER'
 $listener.Stop();$listener=$null
 Check (@([MarketBrain.Transport.Network]::Listeners($port)).Count -eq 0) 'CLOSED_LISTENER'
 $listener=[Net.Sockets.TcpListener]::new([Net.IPAddress]::IPv6Loopback,0);$listener.Start();$port=$listener.LocalEndpoint.Port
 $rows=@([MarketBrain.Transport.Network]::Listeners($port))
 Check ($rows.Count -eq 1 -and $rows[0].ProcessId -eq $PID -and $rows[0].Address -eq '::1') 'ACTUAL_IPV6_OWNER'
 $listener.Stop();$listener=$null
 $code='[Console]::Error.Write((''x''*80000));[Console]::Out.Write((''y''*80000));Start-Sleep -Seconds 30'
 $encoded=[Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($code))
 $child=[MarketBrain.Transport.Child]::new('C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe',[string[]]@('-NoProfile','-NonInteractive','-EncodedCommand',$encoded))
 $timer=[Diagnostics.Stopwatch]::StartNew()
 while($child.ErrorTail.Length -lt 16384 -and $timer.Elapsed.TotalSeconds -lt 10){Start-Sleep -Milliseconds 100}
 Check ($child.ErrorTail.Length -eq 16384 -and -not $child.Exited) 'BOUNDED_LIVE_DRAIN'
 $id=$child.Id;$ticks=$child.StartTicks;$p=Get-Process -Id $id
 Check ($ticks -eq $p.StartTime.ToUniversalTime().Ticks) 'PID_AND_BIRTH'
 $child.Dispose();$child=$null;Check ($p.WaitForExit(3000)) 'OWNED_CHILD_STOP';$p.Dispose()
 # Exercise actual Windows curl/argument quoting/response formatting against a loopback-only
 # denial fixture. No external connection or TLS endpoint is contacted.
 $proxy=[DenyProxyFixture]::new()
 $proxyFailure=$null
 try{
  $source=[IO.File]::ReadAllText((Join-Path $PSScriptRoot 'PaytmSupervisorTransport.ps1')).Replace('http://127.0.0.1:18889',('http://127.0.0.1:'+$proxy.Port))
  . ([scriptblock]::Create($source))
  Assert-PaytmTransportDenials;Check $true 'ACTUAL_CURL_THREE_DENIAL_FORMATS'
 }catch{$proxyFailure=$_}finally{try{$proxy.Dispose()}catch{if(-not $proxyFailure){$proxyFailure=$_}}}
 if($proxyFailure){throw $proxyFailure}
 [pscustomobject]@{status='NATIVE_TRANSPORT_PASSED';assertions=$checks;realLocalChildAndLoopback=$true;externalNetworkContacted=$false}|ConvertTo-Json
}finally{if($child){$child.Dispose()};if($listener){$listener.Stop()}}
