#Requires -Version 5.1
# Installed host, deliberately locked. This version has NO SSH connection or enable operation.
$ErrorActionPreference='Stop'
$root='C:\ProgramData\MarketBrainPaytmGateway\supervisor-v1'
$work='C:\ProgramData\MarketBrainPaytmGateway\supervisor-work-v1'
$custody='C:\ProgramData\MarketBrainPaytmGateway\key-custody'
$lease=$null;$report=$null;$exitCode=1
try {
    . (Join-Path $root 'host.ps1')
    $manifest=Read-PaytmHostJson (Join-Path $root 'manifest.json')
    if($manifest.version -ne 1 -or $manifest.installationId -cnotmatch '^[a-f0-9]{32}$'){throw 'HOST_MANIFEST_INVALID'}
    foreach($name in @('host.ps1','runner.ps1','native.dll')){
        if((Get-FileHash -LiteralPath (Join-Path $root $name)).Hash -cne $manifest.hashes.$name){throw 'HOST_SOURCE_DRIFT'}
    }
    # Exact account and Session 0 are mandatory. No operator-mode bypass in deployed code.
    $identity=[Security.Principal.WindowsIdentity]::GetCurrent()
    if($identity.User.Value -cne 'S-1-5-21-3041730714-102984520-3202743044-1010' -or
       ([Security.Principal.WindowsPrincipal]::new($identity)).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator) -or
       (Get-Process -Id $PID).SessionId -ne 0){throw 'HOST_IDENTITY_INVALID'}
    # A loser never publishes status or kills another instance.
    try{$lease=[IO.File]::Open((Join-Path $work 'instance.lock'),'OpenOrCreate','ReadWrite','None')}catch{exit 73}
    Add-Type -Path (Join-Path $root 'native.dll')
    [MarketBrain.Supervisor.Lifetime]::AttachCurrentProcess()
    $clock=[Diagnostics.Stopwatch]::StartNew()
    $report=[ordered]@{version=1;installationId=$manifest.installationId;instanceId=[guid]::NewGuid().ToString('N');
        processId=$PID;sessionId=0;sequence=0;elapsedSeconds=0;observedUtc=$null;phase='STARTING';failure=$null;
        identityVerified=$true;jobContained=$true;agentIdentityVerified=$false;signingVerified=$false;privateCopyAbsent=$false;
        networkContacted=$false;transportEnabled=$false;brokerReady=$false;ordersEnabled=$false}
    Invoke-PaytmHostObservationLoop $root $work $custody $report $clock
    $exitCode=0
}catch{
    # Structured diagnostics only; never native stderr, keys, arbitrary exception messages or passwords.
    if($lease -and $report){
        $report.phase='BLOCKED';$report.sequence++
        $report.failure=if($_.Exception.Message -cmatch '^HOST_[A-Z_]+$'){$_.Exception.Message}else{'HOST_RUNTIME_FAILED'}
        Write-PaytmHostJson (Join-Path $work 'blocked.json') @{failure=$report.failure;instanceId=$report.instanceId}
        Write-PaytmHostJson (Join-Path $work 'status.json') $report
    }
}finally{if($lease){$lease.Dispose()}}
exit $exitCode
