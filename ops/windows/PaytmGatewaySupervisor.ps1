#Requires -Version 7.0
# Engineering foundation only. No service/task installation, key loading or network calls.
# The production observation/credential adapters are intentionally not wired yet.
function New-PaytmGatewayState {
    [pscustomobject]@{
        phase='IDLE';lastSeconds=0L;attempts=0;failures=0;retryAtSeconds=0L
        connectingSinceSeconds=0L;readySinceSeconds=$null;lastHealthSeconds=$null
        firstReadySeconds=$null;outageSinceSeconds=0L;closedOutageSeconds=0L
        reason='NOT_STARTED';action='NONE';brokerReady=$false;ordersEnabled=$false
    }
}
function Step-PaytmGatewayState {
    param($State,[ValidateSet('START','TICK','HEALTH_OK','TRANSIENT_FAILURE','SECURITY_FAILURE','STOP')][string]$Event,
        [ValidateRange(0,2147483647)][long]$Seconds,[string]$Reason='UNKNOWN',
        [bool]$OwnedLoopbackListener=$false,[bool]$PinnedSshAuthenticated=$false,[bool]$ProxyTlsVerified=$false)
    # Seconds must come from Stopwatch, never DateTime/wall-clock in a runtime adapter.
    if($State.phase -cnotin @('IDLE','CONNECTING','BACKOFF','TRANSPORT_READY','BLOCKED','STOPPED') -or $State.failures -lt 0){throw 'GATEWAY_STATE_INVALID'}
    if($Seconds -lt $State.lastSeconds){throw 'GATEWAY_MONOTONIC_TIME_REGRESSED'}
    $next=$State.PSObject.Copy();$next.lastSeconds=$Seconds;$next.action='NONE'
    $next.brokerReady=$false;$next.ordersEnabled=$false
    if($next.phase -in @('BLOCKED','STOPPED')){return $next} # No implicit rearm.
    if($Event -ceq 'STOP'){
        $next.phase='STOPPED';$next.action='STOP_OWNED_CHILD';$next.reason='OWNER_STOP'
        $next.readySinceSeconds=$null;$next.lastHealthSeconds=$null
        return $next
    }
    if($Event -ceq 'SECURITY_FAILURE'){
        $allowed=@('HOST_KEY_CHANGED','KEY_DENIED','LISTENER_CONFLICT','DESTINATION_DRIFT','TLS_FAILED','CREDENTIAL_MISSING','CONFIG_DRIFT','UNKNOWN')
        $next.reason=if($Reason -cin $allowed){$Reason}else{'UNKNOWN'}
        $next.phase='BLOCKED';$next.action='STOP_OWNED_CHILD';$next.readySinceSeconds=$null;$next.lastHealthSeconds=$null
        return $next
    }
    if($next.phase -ceq 'IDLE'){
        if($Event -cne 'START'){throw 'GATEWAY_START_REQUIRED'}
        $next.phase='CONNECTING';$next.attempts++;$next.connectingSinceSeconds=$Seconds
        $next.outageSinceSeconds=$Seconds;$next.action='START_CHILD';$next.reason='CONNECTING'
        return $next
    }
    if($Event -ceq 'START'){throw 'GATEWAY_ALREADY_STARTED'}
    if($next.phase -ceq 'BACKOFF'){
        if($Event -cne 'TICK'){throw 'GATEWAY_BACKOFF_EVENT_INVALID'}
        if($Seconds -ge $next.retryAtSeconds){
            $next.phase='CONNECTING';$next.attempts++;$next.connectingSinceSeconds=$Seconds
            $next.action='START_CHILD';$next.reason='CONNECTING'
        }
        return $next
    }
    $timedOut=($next.phase -ceq 'CONNECTING' -and ($Seconds-$next.connectingSinceSeconds) -ge 30) -or
        ($next.phase -ceq 'TRANSPORT_READY' -and ($Seconds-$next.lastHealthSeconds) -ge 30)
    # A late success cannot silently erase a missed health/connect deadline.
    if($timedOut -or $Event -ceq 'TRANSIENT_FAILURE'){
        if(-not $timedOut -and $Reason -cnotin @('NETWORK_UNAVAILABLE','SSH_EXITED','PROXY_UNAVAILABLE')){
            return Step-PaytmGatewayState $next SECURITY_FAILURE $Seconds UNKNOWN
        }
        if($next.phase -ceq 'TRANSPORT_READY'){$next.outageSinceSeconds=$Seconds}
        $next.failures++;$delays=@(5,10,20,40,60);$next.retryAtSeconds=$Seconds+$delays[[math]::Min($next.failures-1,4)]
        $next.phase='BACKOFF';$next.action='STOP_OWNED_CHILD';$next.reason=if($timedOut){'HEALTH_OR_CONNECT_TIMEOUT'}else{$Reason}
        $next.readySinceSeconds=$null;$next.lastHealthSeconds=$null
        return $next
    }
    if($Event -ceq 'HEALTH_OK'){
        if(-not ($OwnedLoopbackListener -and $PinnedSshAuthenticated -and $ProxyTlsVerified)){
            return Step-PaytmGatewayState $next SECURITY_FAILURE $Seconds UNKNOWN
        }
        if($next.phase -cne 'TRANSPORT_READY'){
            $next.closedOutageSeconds+=($Seconds-$next.outageSinceSeconds);$next.outageSinceSeconds=$null
            $next.readySinceSeconds=$Seconds
            if($null -eq $next.firstReadySeconds){$next.firstReadySeconds=$Seconds}
        }
        $next.phase='TRANSPORT_READY';$next.reason='TRANSPORT_ONLY_NOT_BROKER_READY';$next.lastHealthSeconds=$Seconds
        if(($Seconds-$next.readySinceSeconds) -ge 60){$next.failures=0} # Do not reset on flapping.
    }
    return $next
}
function Get-PaytmGatewaySshArguments {
    param([string]$KnownHostsPath,[string]$PublicIdentityPath,[switch]$InspectOnly)
    foreach($path in @($KnownHostsPath,$PublicIdentityPath)){
        # -G also receives these exact arguments. Reject expansion/control characters in configuration values.
        if($path -cnotmatch '^[A-Za-z]:[\\/][A-Za-z0-9 _./\\-]+$' -or $path -match '(^|[\\/])\.\.([\\/]|$)'){throw 'GATEWAY_PATH_INVALID'}
    }
    if(-not $PublicIdentityPath.EndsWith('.pub',[StringComparison]::Ordinal)){throw 'GATEWAY_PUBLIC_IDENTITY_REQUIRED'}
    $result=@('-F','none','-N','-T','-4','-p','22','-l','marketbrain-gateway')
    $options=@('BatchMode=yes','StrictHostKeyChecking=yes','IdentitiesOnly=yes','PasswordAuthentication=no',
        'KbdInteractiveAuthentication=no','PreferredAuthentications=publickey','PubkeyAuthentication=yes',
        'ForwardAgent=no','ForwardX11=no','GatewayPorts=no','ExitOnForwardFailure=yes',
        'ConnectTimeout=15','ConnectionAttempts=1','ServerAliveInterval=15','ServerAliveCountMax=2',
        'UpdateHostKeys=no','VerifyHostKeyDNS=no','GlobalKnownHostsFile=none',
        'ProxyCommand=none','ProxyJump=none','ControlMaster=no','ControlPath=none',
        'PermitLocalCommand=no','RequestTTY=no','NumberOfPasswordPrompts=0',
        ('UserKnownHostsFile="'+$KnownHostsPath.Replace('\','/')+'"'),
        ('IdentityFile="'+$PublicIdentityPath.Replace('\','/')+'"'))
    foreach($option in $options){$result+=@('-o',$option)}
    $result+=@('-L','127.0.0.1:18889:127.0.0.1:18888')
    if($InspectOnly){$result+='-G'}
    $result+='130.250.191.137'
    return $result
}
function Assert-PaytmGatewayEffectiveConfig {
    param([string]$Text,[string]$KnownHostsPath,[string]$PublicIdentityPath)
    if($Text.Length -gt 65536){throw 'GATEWAY_EFFECTIVE_CONFIG_TOO_LARGE'}
    $fields=@{}
    foreach($line in $Text.Replace("`r",'').Split("`n")){
        if($line -cmatch '^([A-Za-z0-9]+) (.+)$'){
            $name=$Matches[1].ToLowerInvariant();$value=$Matches[2]
            if($fields.ContainsKey($name)){$fields[$name]+=@($value)}else{$fields[$name]=@($value)}
        }elseif($line.Trim()) {throw 'GATEWAY_EFFECTIVE_CONFIG_UNPARSEABLE'}
    }
    $required=[ordered]@{hostname='130.250.191.137';user='marketbrain-gateway';port='22';addressfamily='inet';
        batchmode='yes';stricthostkeychecking='true';identitiesonly='yes';passwordauthentication='no';
        kbdinteractiveauthentication='no';preferredauthentications='publickey';pubkeyauthentication='true';
        forwardagent='no';forwardx11='no';gatewayports='no';exitonforwardfailure='yes';
        connecttimeout='15';connectionattempts='1';serveraliveinterval='15';serveralivecountmax='2';
        updatehostkeys='false';verifyhostkeydns='false';globalknownhostsfile='none';
        controlmaster='false';permitlocalcommand='no';requesttty='false';numberofpasswordprompts='0';
        userknownhostsfile=$KnownHostsPath.Replace('\','/');identityfile=$PublicIdentityPath.Replace('\','/');
        localforward='[127.0.0.1]:18889 [127.0.0.1]:18888';sessiontype='none';addkeystoagent='false'}
    foreach($key in $required.Keys){
        if(-not $fields.ContainsKey($key) -or $fields[$key].Count -ne 1){throw 'GATEWAY_EFFECTIVE_CONFIG_MISSING_OR_DUPLICATE'}
        # OpenSSH versions print boolean options as yes/no or true/false.
        $actual=$fields[$key][0];$want=$required[$key]
        if($want -cin @('true','yes') -and $actual -cin @('true','yes')){continue}
        if($want -cin @('false','no') -and $actual -cin @('false','no')){continue}
        if($actual -cne $want){throw "GATEWAY_EFFECTIVE_CONFIG_MISMATCH_$($key.ToUpperInvariant())"}
    }
    foreach($key in @('remoteforward','dynamicforward','proxycommand','proxyjump','controlpath','localcommand')){
        if($fields.ContainsKey($key) -and ($fields[$key].Count -ne 1 -or $fields[$key][0] -cne 'none')){throw 'GATEWAY_UNEXPECTED_FORWARD_OR_COMMAND'}
    }
    [pscustomobject]@{checkedSettings=$required.Count;fixedDestination=$true;configurationOnly=$true;authenticationTested=$false}
}
function Open-PaytmGatewayLock([string]$Path) {
    # The provisioner must eventually supply an ACL-protected path under the exact task identity.
    # This engineering primitive never deletes an existing lock or kills a different process.
    [IO.File]::Open($Path,[IO.FileMode]::OpenOrCreate,[IO.FileAccess]::ReadWrite,[IO.FileShare]::None)
}
