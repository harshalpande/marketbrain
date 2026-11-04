#Requires -Version 5.1
# Loaded only from the administrator-protected, hash-verified supervisor installation.
function Get-PaytmTransportListeners { @([MarketBrain.Transport.Network]::Listeners(18889)) }
function Assert-PaytmTransportListener($Rows,[int]$Owner=0) {
    $rows=@($Rows|Where-Object {$null -ne $_})
    if($Owner -eq 0){if($rows.Count){throw 'TRANSPORT_LISTENER_CONFLICT'};return}
    if($rows.Count -ne 1 -or $rows[0].Address -cne '127.0.0.1' -or $rows[0].Port -ne 18889 -or $rows[0].ProcessId -ne $Owner){throw 'TRANSPORT_LISTENER_CONFLICT'}
}
function Read-PaytmTransportControl([string]$Root,[string]$Id) {
    $v=Read-PaytmHostJson (Join-Path $Root 'transport-control.json')
    if($v.version -ne 1 -or $v.installationId -cne $Id -or $v.mode -cnotin @('ENABLED','DISABLED')){throw 'TRANSPORT_CONTROL_INVALID'}
    $v.mode
}
function Assert-PaytmTransportIdentity([string]$Custody) {
    $pub=[IO.File]::ReadAllText((Join-Path $Custody 'gateway.pub')).Trim()
    if($pub -cne 'ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIN0RPkYq7LMb/7fELzlnQIopM+xrLgxF1gBljdHiEdKJ'){throw 'TRANSPORT_KEY_DRIFT'}
    $hostLine=[IO.File]::ReadAllText((Join-Path $Custody 'known_hosts')).Trim()
    if($hostLine -cnotmatch '^130\.250\.191\.137 ssh-rsa ([A-Za-z0-9+/=]+)$'){throw 'TRANSPORT_HOST_DRIFT'}
    $sha=[Security.Cryptography.SHA256]::Create()
    try{$pin='SHA256:'+([Convert]::ToBase64String($sha.ComputeHash([Convert]::FromBase64String($Matches[1])))).TrimEnd('=')}finally{$sha.Dispose()}
    if($pin -cne 'SHA256:YTQ8GV8J4qOQkY4j3dGGyCTAzyR2iX/KSJoGK0p2dKI'){throw 'TRANSPORT_HOST_DRIFT'}
    Test-PaytmHostSigning $Custody
}
function Get-PaytmTransportFailure([string]$ErrorText) {
    if($ErrorText -match 'REMOTE HOST IDENTIFICATION HAS CHANGED|Host key verification failed'){return 'HOST_KEY_CHANGED'}
    # This exact local TCP-connect diagnostic precedes authentication. Do not
    # reinterpret arbitrary "Unknown error" output or authentication denials.
    $tcpUnknown='(?m)^ssh: connect to host 130\.250\.191\.137 port 22: Unknown error\r?$'
    $tcpDenied='(?m)^ssh: connect to host 130\.250\.191\.137 port 22: Permission denied\r?$'
    # A local connect() denial occurs before SSH authentication. Strip only that
    # exact pinned-endpoint line for the credential check; all other denials latch.
    $securityText=$ErrorText -replace $tcpDenied,''
    if($securityText -match 'Permission denied|sign_and_send_pubkey: signing failed|no mutual signature'){return 'KEY_DENIED'}
    if($ErrorText -match 'Address already in use|cannot listen to port|Could not request local forwarding'){return 'LISTENER_CONFLICT'}
    if($ErrorText -match 'administratively prohibited'){return 'DESTINATION_DRIFT'}
    if($ErrorText -match $tcpUnknown -or $ErrorText -match $tcpDenied -or $ErrorText -match 'Connection timed out|Connection refused|No route to host|Network is unreachable|Host is unreachable|Network unreachable|Connection reset|Broken pipe|Timeout, server|Connection to .* closed|kex_exchange_identification: Connection closed by remote host'){return 'NETWORK_UNAVAILABLE'}
    'UNKNOWN'
}
function Get-PaytmChildObservation($Child,[bool]$PreviouslyAuthenticated){
    $exited=$Child.Exited
    # HasExited does not imply redirected stderr has drained. Dispose performs
    # the native bounded drain before classification; ErrorTail survives disposal.
    if($exited){$Child.Dispose()}
    $text=$Child.ErrorTail
    $authenticated=$PreviouslyAuthenticated -or ($text -match 'Authenticated to .+ using "publickey"|Authentication succeeded \(publickey\)')
    $reason=Get-PaytmTransportFailure $text
    $tags=@()
    foreach($pair in @(
        @('TCP_CONNECT_UNKNOWN','(?m)^ssh: connect to host 130\.250\.191\.137 port 22: Unknown error\r?$'),
        @('TCP_CONNECT_DENIED','(?m)^ssh: connect to host 130\.250\.191\.137 port 22: Permission denied\r?$'),
        @('TCP_CONNECT_TIMEOUT','Connection timed out'),@('TCP_CONNECT_REFUSED','Connection refused'),
        @('NETWORK_UNREACHABLE','No route to host|Network is unreachable|Host is unreachable|Network unreachable'),
        @('CONNECTION_RESET','Connection reset'),@('BROKEN_PIPE','Broken pipe'),
        @('KEX_CLOSED','kex_exchange_identification: Connection closed by remote host'),
        @('SSH_TIMEOUT','Timeout, server'),@('HOST_KEY_FAILURE','REMOTE HOST IDENTIFICATION HAS CHANGED|Host key verification failed'),
        @('PERMISSION_DENIED','(?m)^(?!ssh: connect to host 130\.250\.191\.137 port 22: Permission denied\r?$).*Permission denied'),@('SIGNING_FAILURE','sign_and_send_pubkey: signing failed|no mutual signature'),
        @('LISTENER_FAILURE','Address already in use|cannot listen to port|Could not request local forwarding'),
        @('DESTINATION_DENIED','administratively prohibited'))){if($text -match $pair[1]){$tags+=$pair[0]}}
    $sha=[Security.Cryptography.SHA256]::Create()
    try{$hash=[BitConverter]::ToString($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($text))).Replace('-','')}finally{$sha.Dispose()}
    # Never persist raw debug output, identities, paths, server banners or secrets.
    [pscustomobject]@{version=1;exited=[bool]$exited;stderrDrained=[bool]$exited;authenticated=[bool]$authenticated;
        reason=$reason;stderrCharacters=$text.Length;stderrSha256=$hash;tags=@($tags)}
}
function Start-PaytmTransportChild([string]$Custody) {
    Assert-PaytmTransportIdentity $Custody
    Assert-PaytmTransportListener (Get-PaytmTransportListeners)
    $known=Join-Path $Custody 'known_hosts';$pub=Join-Path $Custody 'gateway.pub'
    $tool='C:\Windows\System32\OpenSSH\ssh.exe'
    $config=[MarketBrain.Supervisor.NativeCommand]::Run($tool,[string[]](Get-PaytmGatewaySshArguments $known $pub -InspectOnly),10000)
    if($config.TimedOut -or $config.ExitCode -ne 0){throw 'TRANSPORT_CONFIG_UNAVAILABLE'}
    $null=Assert-PaytmGatewayEffectiveConfig $config.Output $known $pub
    [MarketBrain.Transport.Child]::new($tool,[string[]](@('-v')+(Get-PaytmGatewaySshArguments $known $pub)))
}
function Invoke-PaytmTransportCurl([string]$Url='https://developer.paytmmoney.com/') {
    if($Url -cnotin @('https://developer.paytmmoney.com/','https://example.com/','https://developer.paytmmoney.com:444/','http://developer.paytmmoney.com/')){throw 'TRANSPORT_URL_INVALID'}
    [MarketBrain.Supervisor.NativeCommand]::Run('C:\Windows\System32\curl.exe',[string[]]@('-q','--silent','--show-error','--connect-timeout','4','--max-time','6','--max-redirs','0','--proxy','http://127.0.0.1:18889','--noproxy','','--head','--output','NUL','--write-out','%{http_connect}|%{ssl_verify_result}|%{http_code}',$Url),8000)
}
function Test-PaytmTransportTls {
    $r=Invoke-PaytmTransportCurl
    if($r.TimedOut -or $r.ExitCode -cin @(5,7,28,52,55,56)){return [pscustomobject]@{ok=$false;httpStatus=0}}
    if($r.ExitCode -ne 0 -or $r.Output -cnotmatch '^200\|0\|([2-5][0-9]{2})$'){throw 'TRANSPORT_TLS_FAILED'}
    [pscustomobject]@{ok=$true;httpStatus=[int]$Matches[1]}
}
function Assert-PaytmTransportDenials {
    foreach($url in @('https://example.com/','https://developer.paytmmoney.com:444/')){
        $r=Invoke-PaytmTransportCurl $url
        # Windows curl versions report refused CONNECT as 7 or 56. Require the
        # actual proxy 403 and no destination response; a connection error alone is not proof.
        if($r.TimedOut -or $r.ExitCode -cnotin @(7,56) -or $r.Output -cnotmatch '^403\|0\|000$'){throw 'TRANSPORT_DENIAL_FAILED'}
    }
    $r=Invoke-PaytmTransportCurl 'http://developer.paytmmoney.com/'
    if($r.TimedOut -or $r.ExitCode -ne 0 -or $r.Output -cne '000|0|403'){throw 'TRANSPORT_DENIAL_FAILED'}
}
function Invoke-PaytmTransportLoop([string]$Root,[string]$Work,[string]$Custody,$Report,$Clock) {
    $child=$null;$state=$null;$lastHealth=-100L;$denials=$false;$authenticated=$false
    $Report.transportVersion=1;$Report.childProcessId=0;$Report.childStartTicks=0L;$Report.httpStatus=0;$Report.denialsVerified=$false
    $initial=Read-PaytmHostJson (Join-Path $Root 'control.json');Assert-PaytmHostControl $initial $Report.installationId
    if($initial.mode -cne 'STOP'){
        if([IO.File]::Exists((Join-Path $Work 'blocked.json'))){throw 'TRANSPORT_PREVIOUS_FAILURE_REVIEW_REQUIRED'}
        Test-PaytmHostSigning $Custody
        $Report.agentIdentityVerified=$true;$Report.signingVerified=$true;$Report.privateCopyAbsent=$true
    }
    try{
        while($true){
            $control=Read-PaytmHostJson (Join-Path $Root 'control.json');Assert-PaytmHostControl $control $Report.installationId
            $mode=if($control.mode -ceq 'STOP'){'DISABLED'}else{Read-PaytmTransportControl $Root $Report.installationId}
            if($control.mode -ceq 'STOP' -or $mode -ceq 'DISABLED'){
                if($child){$child.Dispose();$child=$null}
                Assert-PaytmTransportListener (Get-PaytmTransportListeners)
                $state=$null;$Report.transportEnabled=$false;$Report.childProcessId=0;$Report.childStartTicks=0L;$Report.httpStatus=0
                $Report.phase=if($control.mode -ceq 'STOP'){'STOPPED'}else{'LOCKED'}
            }else{
                $Report.transportEnabled=$true
                if([IO.File]::Exists((Join-Path $Work 'blocked.json'))){throw 'TRANSPORT_PREVIOUS_FAILURE_REVIEW_REQUIRED'}
                $seconds=[long][math]::Floor($Clock.Elapsed.TotalSeconds)
                if(-not $state){$state=Step-PaytmGatewayState (New-PaytmGatewayState) START $seconds}
                elseif($state.phase -ceq 'BACKOFF'){$state=Step-PaytmGatewayState $state TICK $seconds}
                if($state.action -ceq 'START_CHILD'){
                    $Report.networkContacted=$true
                    $child=Start-PaytmTransportChild $Custody
                    $Report.agentIdentityVerified=$true;$Report.signingVerified=$true;$Report.privateCopyAbsent=$true
                    $Report.childProcessId=$child.Id;$Report.childStartTicks=$child.StartTicks;$denials=$false;$Report.denialsVerified=$false;$authenticated=$false;$lastHealth=-100L
                    $state.action='NONE'
                }
                if($child){
                    $observation=Get-PaytmChildObservation $child $authenticated
                    $reason=$observation.reason;$authenticated=$observation.authenticated
                    if($observation.exited -or $reason -cne 'UNKNOWN'){
                        $Report.lastSshObservation=$observation
                        $Report.lastSshAttempt=$state.attempts
                        $Report.lastSshElapsedSeconds=$seconds
                    }
                    if($reason -cnotin @('UNKNOWN','NETWORK_UNAVAILABLE')){
                        $state=Step-PaytmGatewayState $state SECURITY_FAILURE $seconds $reason
                    }elseif($observation.exited){
                        # Locally forced child exit and ordinary transport loss may reconnect; explicit authentication/configuration failures latch.
                        if($authenticated -or $reason -ceq 'NETWORK_UNAVAILABLE'){$state=Step-PaytmGatewayState $state TRANSIENT_FAILURE $seconds SSH_EXITED}
                        else{$state=Step-PaytmGatewayState $state SECURITY_FAILURE $seconds UNKNOWN}
                    }else{
                        $rows=@(Get-PaytmTransportListeners)
                        if(@($rows).Count){Assert-PaytmTransportListener $rows $child.Id}
                        if(@($rows).Count -eq 1 -and $authenticated -and ($seconds-$lastHealth) -ge 10){
                            $probe=Test-PaytmTransportTls
                            if($probe.ok -and -not $denials){Assert-PaytmTransportDenials;$denials=$true;$Report.denialsVerified=$true}
                            $seconds=[long][math]::Floor($Clock.Elapsed.TotalSeconds);$lastHealth=$seconds
                            if($probe.ok){$Report.httpStatus=$probe.httpStatus;$state=Step-PaytmGatewayState $state HEALTH_OK $seconds -OwnedLoopbackListener $true -PinnedSshAuthenticated $true -ProxyTlsVerified $true}
                            else{$state=Step-PaytmGatewayState $state TRANSIENT_FAILURE $seconds PROXY_UNAVAILABLE}
                        }else{$state=Step-PaytmGatewayState $state TICK $seconds}
                    }
                    if($state.action -ceq 'STOP_OWNED_CHILD'){$child.Dispose();$child=$null;$Report.childProcessId=0;$Report.childStartTicks=0L;$Report.httpStatus=0}
                    if($state.phase -ceq 'BLOCKED'){throw ('TRANSPORT_'+$state.reason)}
                }
                $Report.phase=$state.phase;$Report.transportState=$state
            }
            $Report.sequence++;$Report.elapsedSeconds=[math]::Round($Clock.Elapsed.TotalSeconds,3);$Report.observedUtc=[DateTime]::UtcNow.ToString('o')
            Write-PaytmHostJson (Join-Path $Work 'status.json') $Report
            if($control.mode -ceq 'STOP'){return}
            Start-Sleep -Seconds 1
        }
    }finally{if($child){$child.Dispose()}}
}
