# Bounded follow-up to accepted recovery ea723866. No imports have side effects.
function Get-PostRecoveryPreflight($Context,$Receipt) {
    $r=@{passed=$false;hashes=@{};failure=$null};$lease=$null
    try{
        foreach($dir in @($Context.root,$Context.work)){if((Get-Item -LiteralPath $dir).Attributes -band [IO.FileAttributes]::ReparsePoint){throw 'RECOVERY_REPARSE_POINT'}}
        foreach($name in $Receipt.hashes.Keys){
            if($name -in @('status.json','blocked.json','startup-failure.json')){continue}
            $path=Join-Path $Context.root $name
            $expected=switch($name){'manifest.json'{'7DEBDC0E181DF0484E74F5FF4A2AD24D1034A8464A12DD72684A5D3EFFFAAD55'} 'transport.ps1'{'40343DDDBF1063ACE422922D5D4DAD98B126B04C53ECA40790B174ECA8C9CBCD'} default{$Receipt.hashes[$name]}}
            if((Get-Item -LiteralPath $path).Attributes -band [IO.FileAttributes]::ReparsePoint -or (Get-FileHash -LiteralPath $path).Hash -cne $expected){throw 'RECOVERY_POST_SOURCE_DRIFT'}
            $r.hashes[$name]=$expected
        }
        foreach($name in @('blocked.json','startup-failure.json')){if(Test-Path -LiteralPath (Join-Path $Context.work $name)){throw 'RECOVERY_NEW_INCIDENT'}}
        $v=Read-BoundedJson (Join-Path $Context.work 'status.json')
        if($v.instanceId -cne 'dc2c6bb7250543a4af8ad6ad59865762' -or $v.sequence -ne 8 -or $v.phase -cne 'TRANSPORT_READY' -or $v.failure -or $v.ordersEnabled -ne $false -or $v.brokerReady -ne $false){throw 'RECOVERY_POST_STATUS_DRIFT'}
        $r.hashes['status.json']=(Get-FileHash -LiteralPath (Join-Path $Context.work 'status.json')).Hash
        $t=Get-ScheduledTask -TaskName $Context.taskName -TaskPath '\';$i=Get-ScheduledTaskInfo -TaskName $Context.taskName -TaskPath '\'
        if([string]$t.State -cne 'Disabled' -or $t.Settings.Enabled -or $i.LastTaskResult -ne 267014 -or $i.LastRunTime.ToUniversalTime().ToString('o') -cne '2026-11-20T06:17:17.0000000Z'){throw 'RECOVERY_POST_TASK_DRIFT'}
        $saved=[xml][IO.File]::ReadAllText((Join-Path $Context.root 'denial-recovery-649710f6-e95b-4ebc-831b-60a99d22ac69\task.xml'))
        $current=[xml](Export-ScheduledTask -TaskName $Context.taskName -TaskPath '\')
        if($saved.Task.Actions.OuterXml -cne $current.Task.Actions.OuterXml -or $saved.Task.Principals.OuterXml -cne $current.Task.Principals.OuterXml){throw 'RECOVERY_TASK_IDENTITY_DRIFT'}
        if(@([Net.NetworkInformation.IPGlobalProperties]::GetIPGlobalProperties().GetActiveTcpListeners()|Where-Object Port -EQ 18889).Count){throw 'RECOVERY_LISTENER_PRESENT'}
        $lease=[IO.File]::Open((Join-Path $Context.work 'instance.lock'),'Open','ReadWrite','None')
        $r.passed=$true
    }catch{$r.failure=if($_.Exception.Message -cmatch '^RECOVERY_[A-Z_]+$'){$_.Exception.Message}else{'RECOVERY_POST_INSPECTION_FAILED'}}finally{if($lease){$lease.Dispose()}}
    return $r
}
function Get-ApplicationHealthInventory {
    $r=@{readOnly=$true;healthTasks=@();files=@{};applicationHttpStatus=$null;applicationUp=$false;credentialsRead=$false}
    $r.healthTasks=@(Get-ScheduledTask|Where-Object {$_.TaskName -like 'MarketBrain*Health*'}|ForEach-Object {@{name=$_.TaskName;state=[string]$_.State;enabled=$_.Settings.Enabled;logonType=[string]$_.Principal.LogonType}})
    foreach($relative in @('installation.json','key-custody\manifest.json','token-custody\health-token.dpapi')){
        $r.files[$relative]=Test-Path -LiteralPath (Join-Path 'C:\ProgramData\MarketBrainPaytmHealth' $relative)
    }
    $handler=[Net.Http.HttpClientHandler]::new();$handler.UseProxy=$false;$handler.AllowAutoRedirect=$false
    $client=[Net.Http.HttpClient]::new($handler);$client.Timeout=[TimeSpan]::FromSeconds(3);$client.MaxResponseContentBufferSize=4096
    try{$response=$client.GetAsync('http://127.0.0.1:8080/actuator/health').GetAwaiter().GetResult();try{$r.applicationHttpStatus=[int]$response.StatusCode;if($response.IsSuccessStatusCode){$body=$response.Content.ReadAsStringAsync().GetAwaiter().GetResult()|ConvertFrom-Json;$r.applicationUp=($body.status -ceq 'UP')}}finally{$response.Dispose()}}catch{$r.applicationProbeFailure=$_.Exception.GetBaseException().GetType().Name}finally{$client.Dispose()}
    return $r
}
function Update-PostRecoverySample($State,$Value,[double]$Seconds) {
    if($Value.installationId -cne 'ea8b91471cf048aa97a0f6b939b355c7' -or $Value.ordersEnabled -ne $false -or $Value.brokerReady -ne $false){throw 'RECOVERY_SCOPE_DRIFT'}
    if($Value.instanceId -ceq 'dc2c6bb7250543a4af8ad6ad59865762'){if($Seconds -gt 45){throw 'RECOVERY_START_TIMEOUT'};return $false}
    if(-not $State.instance){$State.instance=$Value.instanceId;$State.sequence=$Value.sequence;$State.progressSeconds=$Seconds}
    if($State.instance -cne $Value.instanceId){throw 'RECOVERY_WORKER_CHANGED'}
    if($Value.failure -or $Value.phase -ceq 'BLOCKED'){throw 'RECOVERY_NEW_WORKER_BLOCKED'}
    if($Value.sequence -gt $State.sequence){$State.sequence=$Value.sequence;$State.progressSeconds=$Seconds}
    if($Seconds-$State.progressSeconds -gt 10){throw 'RECOVERY_STATUS_STALLED'}
    if($Value.phase -ceq 'TRANSPORT_READY' -and $Value.denialsVerified -eq $true){
        $tls=$Value.lastTlsObservation
        if(-not $tls -or $tls.exitCode -ne 0 -or $tls.timedOut -or $tls.connectStatus -ne 200 -or $tls.tlsVerifyCode -ne 0){throw 'RECOVERY_TLS_OBSERVATION_INVALID'}
        if($State.tlsStamp -cne $tls.observedUtc){$State.tlsStamp=$tls.observedUtc;$State.tlsSeconds=$Seconds;$State.tlsObservations++}
        if($Seconds-$State.tlsSeconds -gt 20){throw 'RECOVERY_TLS_OBSERVATION_STALLED'}
        if($null -eq $State.readySince){$State.readySince=$Seconds}
        $State.readySamples++
        return ($Seconds-$State.readySince -ge 90 -and $State.tlsObservations -ge 3)
    }
    if($null -ne $State.readySince){throw 'RECOVERY_CONTINUOUS_READINESS_LOST'}
    if($Seconds -gt 45){throw 'RECOVERY_START_TIMEOUT'}
    return $false
}
function Invoke-PostRecoveryObservation($Context,$Receipt,$Report) {
    $before=Get-PostRecoveryPreflight $Context $Receipt
    if(-not $before.passed){throw $before.failure}
    if(Test-Path -LiteralPath $Context.archive){throw 'RECOVERY_ARCHIVE_ALREADY_EXISTS'}
    $null=New-Item -ItemType Directory -Path $Context.archive
    Copy-Item -LiteralPath (Join-Path $Context.work 'status.json') -Destination (Join-Path $Context.archive 'status.json')
    if((Get-FileHash -LiteralPath (Join-Path $Context.archive 'status.json')).Hash -cne $before.hashes['status.json']){throw 'RECOVERY_BACKUP_MISMATCH'}
    $Report.backupVerified=$true;$attempted=$false
    try{
        $again=Get-PostRecoveryPreflight $Context $Receipt;if(-not $again.passed){throw $again.failure}
        $attempted=$true
        Register-DenialRecoveryGuard $Context $before.hashes['manifest.json'];$Report.guardRegistered=$true
        $null=Enable-ScheduledTask -TaskName $Context.taskName -TaskPath '\'
        $Report.startAttempts=1;Save-DenialRecoveryResult $Context $Report
        Start-ScheduledTask -TaskName $Context.taskName -TaskPath '\'
        $watch=[Diagnostics.Stopwatch]::StartNew();$state=@{instance=$null;sequence=0;progressSeconds=0;tlsStamp=$null;tlsSeconds=0;tlsObservations=0;readySince=$null;readySamples=0}
        do{
            if((Read-BoundedJson (Join-Path $Context.root 'control.json')).mode -cne 'LOCKED'){throw 'RECOVERY_SCOPE_DRIFT'}
            $value=Read-BoundedJson (Join-Path $Context.work 'status.json')
            $passed=Update-PostRecoverySample $state $value $watch.Elapsed.TotalSeconds
            $Report.observation=@{elapsedSeconds=$watch.Elapsed.TotalSeconds;readySamples=$state.readySamples;distinctTlsObservations=$state.tlsObservations;instanceId=$state.instance;phase=$value.phase;sequence=$value.sequence;httpStatus=$value.httpStatus}
            Save-DenialRecoveryResult $Context $Report
            if($passed){$Report.transportObserved=$true;break}
            Start-Sleep -Seconds 2
        }while($watch.Elapsed.TotalSeconds -lt 140)
        if(-not $Report.transportObserved){throw 'RECOVERY_OBSERVATION_TIMEOUT'}
        $Report.applicationInventory=Get-ApplicationHealthInventory
    }finally{
        if($attempted){
            try{Stop-DenialRecoveryTask $Context;$Report.finalStoppedAndDisabled=$true}catch{$Report.cleanupFailure='RECOVERY_STOP_NOT_VERIFIED'}
            if($Report.finalStoppedAndDisabled -and $Context.guardXmlHash){try{Remove-DenialRecoveryGuard $Context;$Report.guardRemoved=$true}catch{$Report.cleanupFailure='RECOVERY_GUARD_CLEANUP_REQUIRED'}}
            Save-DenialRecoveryResult $Context $Report
        }
    }
}
