#requires -Version 7.5
param([Parameter(Mandatory)][string]$ResultPath,[ValidateSet('Observe','FailureFixture')][string]$Mode='Observe')
$ErrorActionPreference='Stop'
$report=@{version=4;test='PAYTM_TRANSPORT_OBSERVATION';passed=$false;ordersEnabled=$false;brokerCredentialsUsed=$false;gatewayChanged=$false;scope='OPERATOR_TRANSPORT_NOT_BROKER_READINESS';samples=@();failure=$null}
$watch=[Diagnostics.Stopwatch]::StartNew()
function Read-BoundedJson([string]$Path) {
    # Match the supervisor's atomic replacement protocol. Delete sharing keeps
    # a complete old snapshot readable while a new heartbeat replaces its path.
    for($attempt=0;$attempt -lt 5;$attempt++){
        $stream=$null;$reader=$null
        try{
            $stream=[IO.File]::Open($Path,'Open','Read',([IO.FileShare]::ReadWrite -bor [IO.FileShare]::Delete))
            if($stream.Length -gt 65536){throw 'STATE_TOO_LARGE'}
            $reader=[IO.StreamReader]::new($stream)
            $buffer=[char[]]::new(65537);$length=$reader.ReadBlock($buffer,0,$buffer.Length)
            if($length -gt 65536){throw 'STATE_TOO_LARGE'}
            return ([string]::new($buffer,0,$length)|ConvertFrom-Json -DateKind String)
        }catch{
            $e=$_.Exception.GetBaseException();$code=$e.HResult -band 65535
            if($e -isnot [IO.IOException] -or $code -notin @(2,32,33) -or $attempt -eq 4){throw}
        }finally{if($reader){$reader.Dispose()};if($stream){$stream.Dispose()}}
        Start-Sleep -Milliseconds 50
    }
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
function Get-DenialRecoveryPreflight($State) {
    $root='C:\ProgramData\MarketBrainPaytmGateway\supervisor-v1'
    $work='C:\ProgramData\MarketBrainPaytmGateway\supervisor-work-v1'
    $id='ea8b91471cf048aa97a0f6b939b355c7'
    $r=@{readOnly=$true;readyForReviewedRecovery=$false;hashes=@{};checks=@{};failure=$null}
    $lease=$null
    try {
        foreach($dir in @('C:\ProgramData\MarketBrainPaytmGateway',$root,$work)){
            if((Get-Item -LiteralPath $dir).Attributes -band [IO.FileAttributes]::ReparsePoint){throw 'RECOVERY_REPARSE_POINT'}
        }
        $manifest=Read-BoundedJson (Join-Path $root 'manifest.json')
        if($manifest.installationId -cne $id -or $manifest.version -ne 1 -or $manifest.transportVersion -ne 1){throw 'RECOVERY_MANIFEST_IDENTITY'}
        foreach($name in @('host.ps1','runner.ps1','native.dll','transport.ps1','gateway.ps1','transport.dll','manifest.json','control.json','transport-control.json','session-checkpoint.json','status.json','blocked.json','startup-failure.json')){
            $dir=if($name -in @('status.json','blocked.json','startup-failure.json')){$work}else{$root}
            $path=Join-Path $dir $name
            if($name -eq 'session-checkpoint.json' -and -not (Test-Path -LiteralPath $path)){$r.hashes[$name]='ABSENT';continue}
            if((Get-Item -LiteralPath $path).Attributes -band [IO.FileAttributes]::ReparsePoint){throw 'RECOVERY_REPARSE_FILE'}
            $r.hashes[$name]=(Get-FileHash -LiteralPath $path).Hash
            if($name -in @('host.ps1','runner.ps1','native.dll','transport.ps1','gateway.ps1','transport.dll') -and $r.hashes[$name] -cne $manifest.hashes.$name){throw 'RECOVERY_INSTALLED_SOURCE_DRIFT'}
        }
        $r.checks.installedSourcesVerified=$true
        if($r.hashes['manifest.json'] -cne '343A080C09E468F73FAC844ABC5CAA02B2A429CCD4B66308D2B6366102B12A98'){throw 'RECOVERY_REVIEWED_MANIFEST_CHANGED'}
        foreach($name in @('status.json','blocked.json','startup-failure.json')){
            $v=Read-BoundedJson (Join-Path $work $name)
            if($v.instanceId -cne '1f2c636c108042898f3c58143e00d9c7' -or $v.failure -cne 'TRANSPORT_DENIAL_FAILED'){throw 'RECOVERY_INCIDENT_CHANGED'}
        }
        if($State.sequence -ne 3860 -or $State.phase -cne 'BLOCKED' -or $State.ordersEnabled -ne $false -or $State.brokerReady -ne $false){throw 'RECOVERY_STATUS_CHANGED'}
        if((Read-BoundedJson (Join-Path $root 'control.json')).mode -cne 'LOCKED' -or (Read-BoundedJson (Join-Path $root 'transport-control.json')).mode -cne 'ENABLED'){throw 'RECOVERY_CONTROLS_CHANGED'}
        $r.checks.incidentAndControlVerified=$true
        $task=Get-ScheduledTask -TaskName 'MarketBrain-Gateway-Supervisor-v1' -TaskPath '\' -ErrorAction Stop
        $info=Get-ScheduledTaskInfo -TaskName $task.TaskName -TaskPath '\' -ErrorAction Stop
        $r.task=@{state=[string]$task.State;enabled=[bool]$task.Settings.Enabled;lastTaskResult=$info.LastTaskResult;lastRunUtc=$info.LastRunTime.ToUniversalTime().ToString('o')}
        $sid=$task.Principal.UserId
        if($sid -notmatch '^S-1-'){$sid=([Security.Principal.NTAccount]::new($sid)).Translate([Security.Principal.SecurityIdentifier]).Value}
        $command="&([scriptblock]::Create([IO.File]::ReadAllText('"+$root+"\runner.ps1')))"
        $expected='-NoLogo -NoProfile -NonInteractive -EncodedCommand '+[Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($command))
        $actions=@($task.Actions)
        if($sid -cne 'S-1-5-21-3041730714-102984520-3202743044-1010' -or [string]$task.Principal.RunLevel -cne 'Limited' -or [string]$task.Principal.LogonType -cne 'Password' -or $task.Description -cne ('MarketBrain locked supervisor '+$id) -or $actions.Count -ne 1 -or $actions[0].Execute -cne 'C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe' -or $actions[0].Arguments -cne $expected -or $actions[0].WorkingDirectory -cne $root){throw 'RECOVERY_TASK_IDENTITY_CHANGED'}
        if([string]$task.State -cne 'Ready' -or -not $task.Settings.Enabled -or $info.LastTaskResult -ne 1){throw 'RECOVERY_TASK_NOT_IDLE'}
        $r.checks.taskIdentityAndIdleVerified=$true
        $lease=[IO.File]::Open((Join-Path $work 'instance.lock'),'Open','ReadWrite','None')
        $r.checks.exclusiveLeaseAvailable=$true
        $listeners=@([Net.NetworkInformation.IPGlobalProperties]::GetIPGlobalProperties().GetActiveTcpListeners() | Where-Object Port -EQ 18889)
        if($listeners.Count){throw 'RECOVERY_LISTENER_PRESENT'}
        foreach($name in $r.hashes.Keys){
            $dir=if($name -in @('status.json','blocked.json','startup-failure.json')){$work}else{$root}
            $path=Join-Path $dir $name
            if($r.hashes[$name] -eq 'ABSENT'){if(Test-Path -LiteralPath $path){throw 'RECOVERY_STATE_DRIFT'}}
            elseif((Get-FileHash -LiteralPath $path).Hash -cne $r.hashes[$name]){throw 'RECOVERY_STATE_DRIFT'}
        }
        $r.checks.noListenerAndStableFiles=$true
        $r.readyForReviewedRecovery=$true
    } catch {
        $r.failure=if($_.Exception.Message -cmatch '^RECOVERY_[A-Z_]+$'){$_.Exception.Message}else{'RECOVERY_PREFLIGHT_'+$_.Exception.GetType().Name}
    } finally {if($lease){$lease.Dispose()}}
    return $r
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
            if($report.preflight.failure -ceq 'TRANSPORT_DENIAL_FAILED'){$report.recoveryPreflight=Get-DenialRecoveryPreflight $initial}
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
