#Requires -Version 5.1
# Installed host. Transport is available only through an explicitly installed/verified extension.
$ErrorActionPreference='Stop'
$root='C:\ProgramData\MarketBrainPaytmGateway\supervisor-v1'
$work='C:\ProgramData\MarketBrainPaytmGateway\supervisor-work-v1'
$custody='C:\ProgramData\MarketBrainPaytmGateway\key-custody'
$lease=$null;$report=$null;$exitCode=1
$bootstrap=[ordered]@{version=1;instanceId=[guid]::NewGuid().ToString('N');installationId=$null;stage='IDENTITY';
    processId=$PID;failure=$null;details=$null;executionPolicies=@();networkContacted=$false;ordersEnabled=$false}
try {
    # Exact account and Session 0 are mandatory. No operator-mode bypass in deployed code.
    $identity=[Security.Principal.WindowsIdentity]::GetCurrent()
    if($identity.User.Value -cne 'S-1-5-21-3041730714-102984520-3202743044-1010' -or
       ([Security.Principal.WindowsPrincipal]::new($identity)).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator) -or
       (Get-Process -Id $PID).SessionId -ne 0){throw 'HOST_IDENTITY_INVALID'}
    # A loser never publishes status or kills another instance.
    try{$lease=[IO.File]::Open((Join-Path $work 'instance.lock'),'OpenOrCreate','ReadWrite','None')}catch{exit 73}
    $bootstrap.stage='EXECUTION_POLICY'
    $bootstrap.executionPolicies=@(Get-ExecutionPolicy -List|ForEach-Object {[pscustomobject]@{scope=[string]$_.Scope;policy=[string]$_.ExecutionPolicy}})
    if(@($bootstrap.executionPolicies|Where-Object {$_.scope -cin @('MachinePolicy','UserPolicy') -and $_.policy -cne 'Undefined'}).Count){throw 'HOST_MANAGED_POLICY_REVIEW_REQUIRED'}
    $bootstrap.stage='MANIFEST'
    $manifestPath=Join-Path $root 'manifest.json'
    if((Get-Item -LiteralPath $manifestPath).Length -gt 16384){throw 'HOST_MANIFEST_INVALID'}
    $manifest=[IO.File]::ReadAllText($manifestPath)|ConvertFrom-Json -ErrorAction Stop
    if($manifest.version -ne 1 -or $manifest.installationId -cnotmatch '^[a-f0-9]{32}$'){throw 'HOST_MANIFEST_INVALID'}
    $bootstrap.installationId=$manifest.installationId
    $bootstrap.stage='VERIFY_SOURCES'
    $files=@('host.ps1','runner.ps1','native.dll')
    if($manifest.PSObject.Properties['transportVersion']){
        if($manifest.transportVersion -ne 1){throw 'HOST_TRANSPORT_VERSION_INVALID'}
        $files+=@('transport.ps1','gateway.ps1','transport.dll')
    }
    foreach($name in $files){
        if((Get-FileHash -LiteralPath (Join-Path $root $name)).Hash -cne $manifest.hashes.$name){throw 'HOST_SOURCE_DRIFT'}
    }
    $bootstrap.stage='LOAD_HELPER'
    # Same administrator-protected inline loading mechanism as the accepted signing worker.
    # Hashes are checked before evaluation. Do not change execution policy or bypass managed policy.
    . ([scriptblock]::Create([IO.File]::ReadAllText((Join-Path $root 'host.ps1'))))
    $bootstrap.stage='LOAD_NATIVE'
    Add-Type -Path (Join-Path $root 'native.dll')
    if($manifest.PSObject.Properties['transportVersion']){
        $bootstrap.stage='LOAD_TRANSPORT'
        . ([scriptblock]::Create([IO.File]::ReadAllText((Join-Path $root 'gateway.ps1'))))
        . ([scriptblock]::Create([IO.File]::ReadAllText((Join-Path $root 'transport.ps1'))))
        Add-Type -Path (Join-Path $root 'transport.dll')
    }
    $bootstrap.stage='ATTACH_JOB'
    [MarketBrain.Supervisor.Lifetime]::AttachCurrentProcess()
    $clock=[Diagnostics.Stopwatch]::StartNew()
    $report=[ordered]@{version=1;installationId=$manifest.installationId;instanceId=$bootstrap.instanceId;
        processId=$PID;sessionId=0;sequence=0;elapsedSeconds=0;observedUtc=$null;phase='STARTING';failure=$null;
        identityVerified=$true;jobContained=$true;agentIdentityVerified=$false;signingVerified=$false;privateCopyAbsent=$false;executionPolicies=$bootstrap.executionPolicies;
        networkContacted=$false;transportEnabled=$false;brokerReady=$false;ordersEnabled=$false}
    $bootstrap.stage='OBSERVATION_LOOP'
    if($manifest.PSObject.Properties['transportVersion']){Invoke-PaytmTransportLoop $root $work $custody $report $clock}
    else{Invoke-PaytmHostObservationLoop $root $work $custody $report $clock}
    $exitCode=0
}catch{
    # Structured diagnostics only; never native stderr, keys, arbitrary exception messages or passwords.
    $base=$_.Exception.GetBaseException()
    $bootstrap.failure=if($_.Exception.Message -cmatch '^(HOST|TRANSPORT|GATEWAY)_[A-Z_]+$'){$_.Exception.Message}else{'HOST_STARTUP_FAILED'}
    $bootstrap.details=@{type=$base.GetType().Name;outerType=$_.Exception.GetType().Name;hresult=$base.HResult;line=$_.InvocationInfo.ScriptLineNumber;
        nativeErrorCode=if($base -is [ComponentModel.Win32Exception]){$base.NativeErrorCode}else{$null}}
    # This does not depend on the helper loading successfully. Exclusive lease prevents competing writers.
    # Preserve the first cause until reviewed recovery archives it. A later launch
    # may fail only because this latch exists; that is not the original cause.
    if($lease -and -not [IO.File]::Exists((Join-Path $work 'startup-failure.json'))){
        try{[IO.File]::WriteAllText((Join-Path $work 'startup-failure.json'),($bootstrap|ConvertTo-Json -Depth 5 -Compress),[Text.UTF8Encoding]::new($false))}catch{}
    }
    if($lease -and $report){
        $report.phase='BLOCKED';$report.sequence++
        $report.failure=if($_.Exception.Message -cmatch '^(HOST|TRANSPORT|GATEWAY)_[A-Z_]+$'){$_.Exception.Message}else{'HOST_RUNTIME_FAILED'}
        if(-not [IO.File]::Exists((Join-Path $work 'blocked.json'))){
            Write-PaytmHostJson (Join-Path $work 'blocked.json') @{failure=$report.failure;instanceId=$report.instanceId}
        }
        Write-PaytmHostJson (Join-Path $work 'status.json') $report
    }
}finally{if($lease){$lease.Dispose()}}
exit $exitCode
