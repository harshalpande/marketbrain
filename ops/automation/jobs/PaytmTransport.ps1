#requires -Version 7.5
param([Parameter(Mandatory)][string]$ResultPath,[ValidateSet('Observe','FailureFixture')][string]$Mode='Observe')
$ErrorActionPreference='Stop'
$report=@{version=3;test='PAYTM_TRANSPORT_OBSERVATION';passed=$false;ordersEnabled=$false;brokerCredentialsUsed=$false;gatewayChanged=$false;scope='OPERATOR_TRANSPORT_NOT_BROKER_READINESS';samples=@();failure=$null}
$watch=[Diagnostics.Stopwatch]::StartNew()
function Read-BoundedJson([string]$Path) {
    if ((Get-Item -LiteralPath $Path).Length -gt 65536) { throw 'STATE_TOO_LARGE' }
    Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json -DateKind String
}
function Get-TransportPreflightEvidence($State,$Control) {
    $e=@{applicationLocked=($Control.mode -ceq 'LOCKED' -and $State.ordersEnabled -eq $false -and $State.brokerReady -eq $false)}
    foreach($name in @('phase','failure')) {
        $value=$State.$name
        if($value -is [string] -and $value -cmatch '^[A-Z][A-Z0-9_]{0,119}$'){$e[$name]=$value}
    }
    if($State.instanceId -cmatch '^[a-f0-9]{32}$'){$e.instanceId=$State.instanceId}
    if($State.sequence -is [long] -or $State.sequence -is [int]){$e.sequence=$State.sequence}
    return $e
}
function Get-DenialIncidentEvidence($State) {
    $e=@{historicalDenialResponsePresent=($null -ne $State.PSObject.Properties['lastDenialObservation']);files=@{}}
    foreach($name in @('transport.ps1','manifest.json')) {
        $path=Join-Path 'C:\ProgramData\MarketBrainPaytmGateway\supervisor-v1' $name
        $e.files[$name]=(Get-FileHash -LiteralPath $path).Hash
    }
    $manifest=Read-BoundedJson 'C:\ProgramData\MarketBrainPaytmGateway\supervisor-v1\manifest.json'
    $e.installedTransportMatchesManifest=($e.files['transport.ps1'] -ceq $manifest.hashes.'transport.ps1')
    foreach($name in @('lastTlsObservation','lastTlsFailure','firstTlsFailure')) {
        if($State.PSObject.Properties[$name]){
            $selected=@{}
            foreach($field in @('exitCode','elapsedMilliseconds','connectStatus','tlsVerifyCode','httpStatus','tcpConnectMilliseconds','tlsHandshakeCompletedMilliseconds','curlTotalMilliseconds')) {
                $v=$State.$name.$field
                if($v -is [long] -or $v -is [int] -or $v -is [double]){$selected[$field]=$v}
            }
            foreach($field in @('timedOut','metricsParsed','phaseMetricsParsed')) {
                if($State.$name.$field -is [bool]){$selected[$field]=$State.$name.$field}
            }
            $e[$name]=$selected
        }
    }
    return $e
}
function Test-LocalDenialFormatting {
    # Ephemeral loopback server never forwards a request or contacts the broker/VPS.
    Add-Type -TypeDefinition @'
using System;
using System.Net;
using System.Net.Sockets;
using System.Text;
using System.Threading.Tasks;
public sealed class QueueDenialFixture : IDisposable {
 readonly TcpListener listener=new TcpListener(IPAddress.Loopback,0);
 readonly Task task;
 public int Port { get { return ((IPEndPoint)listener.LocalEndpoint).Port; } }
 public QueueDenialFixture() {
  listener.Start(); task=Task.Run(async () => {
   for(int i=0;i<3;i++) {
    var accept=listener.AcceptTcpClientAsync();
    if(await Task.WhenAny(accept,Task.Delay(10000))!=accept) throw new TimeoutException();
    using(var client=await accept) {
     client.ReceiveTimeout=5000;client.SendTimeout=5000;
     var stream=client.GetStream();var bytes=new byte[8192];int n=0;
     while(n<bytes.Length) { int k=stream.Read(bytes,n,bytes.Length-n);if(k==0)break;n+=k;
      if(Encoding.ASCII.GetString(bytes,0,n).Contains("\r\n\r\n"))break; }
     var response=Encoding.ASCII.GetBytes("HTTP/1.1 403 Forbidden\r\nContent-Length: 0\r\nConnection: close\r\n\r\n");
     stream.Write(response,0,response.Length);
    }
   }
  });
 }
 public void Dispose() { listener.Stop();try{task.Wait(6000);}catch{} }
}
'@
    $fixture=[QueueDenialFixture]::new()
    $results=@()
    try {
        foreach($url in @('https://example.com/','https://developer.paytmmoney.com:444/','http://developer.paytmmoney.com/')) {
            $p=[Diagnostics.Process]::new()
            try {
                $s=[Diagnostics.ProcessStartInfo]::new((Join-Path $env:WINDIR 'System32/curl.exe'))
                $s.UseShellExecute=$false;$s.CreateNoWindow=$true;$s.RedirectStandardOutput=$true;$s.RedirectStandardError=$true
                foreach($a in @('-q','--silent','--show-error','--connect-timeout','4','--max-time','6','--max-redirs','0','--proxy',('http://127.0.0.1:'+$fixture.Port),'--noproxy','','--head','--output','NUL','--write-out','%{http_connect}|%{ssl_verify_result}|%{http_code}',$url)){$s.ArgumentList.Add($a)}
                $p.StartInfo=$s;[void]$p.Start()
                $o=$p.StandardOutput.ReadToEndAsync();$err=$p.StandardError.ReadToEndAsync()
                $timeout=-not $p.WaitForExit(8000)
                if($timeout){$p.Kill($true);$p.WaitForExit()}
                $raw=$o.GetAwaiter().GetResult();$null=$err.GetAwaiter().GetResult()
                $http=$url.StartsWith('http:')
                $expected=if($http){$p.ExitCode -eq 0 -and $raw -ceq '000|0|403'}else{$p.ExitCode -in @(7,56) -and $raw -ceq '403|0|000'}
                $results+=@{case=if($http){'PLAIN_HTTP'}elseif($url.Contains(':444')){'WRONG_PORT'}else{'WRONG_HOST'};timedOut=$timeout;exitCode=$p.ExitCode;metrics=if($raw -cmatch '^\d{3}\|\d{1,9}\|\d{3}$'){$raw}else{'UNPARSEABLE'};matchesInstalledRule=($expected -and -not $timeout)}
            } finally {$p.Dispose()}
        }
    } finally {$fixture.Dispose()}
    return @{scope='LOCAL_SYNTHETIC_403_NOT_VPS_POLICY_PROOF';externalNetworkContacted=$false;checks=$results;passed=(@($results|Where-Object {-not $_.matchesInstalledRule}).Count -eq 0 -and $results.Count -eq 3)}
}
try {
    if ($Mode -eq 'FailureFixture') { throw 'DELIBERATE_FAILURE_FIXTURE_NO_GATEWAY_ACCESS' }
    $control='C:\ProgramData\MarketBrainPaytmGateway\supervisor-v1\control.json'
    $status='C:\ProgramData\MarketBrainPaytmGateway\supervisor-work-v1\status.json'
    $initial=Read-BoundedJson $status
    $report.preflight=Get-TransportPreflightEvidence $initial (Read-BoundedJson $control)
    if(-not $report.preflight.applicationLocked){throw 'APPLICATION_NOT_LOCKED'}
    if($initial.phase -cne 'TRANSPORT_READY'){
        if($report.preflight.phase -ceq 'BLOCKED' -and $report.preflight.failure){
            $report.incident=Get-DenialIncidentEvidence $initial
            if($report.preflight.failure -ceq 'TRANSPORT_DENIAL_FAILED'){$report.localDenialFormatting=Test-LocalDenialFormatting}
            throw ('GATEWAY_BLOCKED:'+$report.preflight.failure)
        }
        throw 'GATEWAY_NOT_READY'
    }
    for($i=0;$i -lt 6;$i++) {
        $state=Read-BoundedJson $status
        $lock=Read-BoundedJson $control
        if ($lock.mode -cne 'LOCKED' -or $state.ordersEnabled -ne $false -or $state.brokerReady -ne $false) { throw 'APPLICATION_NOT_LOCKED' }
        if ($state.instanceId -cne $initial.instanceId) { throw 'SUPERVISOR_CHANGED' }
        $listeners=@(Get-NetTCPConnection -State Listen -LocalPort 18889 -ErrorAction Stop)
        if (-not $listeners.Count -or @($listeners | Where-Object LocalAddress -NotIn @('127.0.0.1','::1')).Count) { throw 'LOOPBACK_LISTENER_REQUIRED' }
        $p=[Diagnostics.Process]::new()
        try {
            $s=[Diagnostics.ProcessStartInfo]::new((Join-Path $env:WINDIR 'System32/curl.exe'))
            $s.UseShellExecute=$false; $s.CreateNoWindow=$true; $s.RedirectStandardOutput=$true; $s.RedirectStandardError=$true
            foreach($a in @('-q','--proxy','http://127.0.0.1:18889','--noproxy','','--head','--proto','=https','--connect-timeout','4','--max-time','6','--silent','--output','NUL','--write-out','%{http_code}|%{http_connect}|%{time_appconnect}|%{time_total}','https://developer.paytmmoney.com/')) { $s.ArgumentList.Add($a) }
            $p.StartInfo=$s; [void]$p.Start()
            $o=$p.StandardOutput.ReadToEndAsync(); $e=$p.StandardError.ReadToEndAsync()
            if (-not $p.WaitForExit(8000)) { $p.Kill($true); $p.WaitForExit() }
            $raw=$o.GetAwaiter().GetResult(); $null=$e.GetAwaiter().GetResult()
            $valid=$raw -cmatch '^([0-9]{3})\|([0-9]{3})\|([0-9.]+)\|([0-9.]+)$'
            $sample=@{observedUtc=[DateTimeOffset]::UtcNow.ToString('o');sequence=$state.sequence;phase=$state.phase;exitCode=$p.ExitCode;tlsVerified=$false}
            if($valid) {
                $sample.httpStatus=[int]$Matches[1]; $sample.connectStatus=[int]$Matches[2]
                $sample.tlsVerified=$p.ExitCode -eq 0 -and $sample.connectStatus -eq 200 -and [double]::Parse($Matches[3],[Globalization.CultureInfo]::InvariantCulture) -gt 0
            }
            $report.samples+= $sample
        } finally { $p.Dispose() }
        # Every sample is checkpointed; final evidence remains available after interruption.
        [IO.File]::WriteAllText($ResultPath,($report | ConvertTo-Json -Depth 8))
        if ($i -lt 5) { Start-Sleep -Seconds 5 }
    }
    $final=Read-BoundedJson $status
    if ((Read-BoundedJson $control).mode -cne 'LOCKED' -or $final.ordersEnabled -ne $false -or $final.brokerReady -ne $false -or $final.instanceId -cne $initial.instanceId -or $final.sequence -le $initial.sequence) { throw 'FINAL_LOCK_OR_ADVANCEMENT_FAILED' }
    if (@($report.samples | Where-Object { -not $_.tlsVerified -or $_.phase -cne 'TRANSPORT_READY' }).Count) { throw 'TRANSPORT_SAMPLE_FAILED' }
    $report.passed=$true
} catch { $report.failure=$_.Exception.Message.Substring(0,[Math]::Min(200,$_.Exception.Message.Length)) }
finally {
    $report.elapsedSeconds=$watch.Elapsed.TotalSeconds
    [IO.File]::WriteAllText($ResultPath,($report | ConvertTo-Json -Depth 8))
}
if (-not $report.passed) { exit 1 }
