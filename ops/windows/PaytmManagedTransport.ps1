#Requires -Version 7.0
function Set-PaytmTransportControl([string]$Id,[ValidateSet('ENABLED','DISABLED')][string]$Mode){
    Write-PaytmHostJson (Join-Path (Get-PaytmHostContract).root 'transport-control.json') @{version=1;installationId=$Id;mode=$Mode}
}
function Assert-PaytmManagedStatus($Value,[string]$Id,[ValidateSet('TRANSPORT_READY','LOCKED','STOPPED')][string]$Phase){
    if($Value.version -ne 1 -or $Value.transportVersion -ne 1 -or $Value.installationId -cne $Id -or $Value.phase -cne $Phase -or $null -ne $Value.failure){throw 'TRANSPORT_STATUS_INVALID'}
    if($Value.instanceId -cnotmatch '^[a-f0-9]{32}$' -or $Value.processId -le 0 -or $Value.sessionId -ne 0 -or $Value.sequence -lt 1 -or $Value.elapsedSeconds -lt 0){throw 'TRANSPORT_STATUS_IDENTITY'}
    foreach($field in @('identityVerified','jobContained')){if($Value.$field -isnot [bool] -or -not $Value.$field){throw 'TRANSPORT_STATUS_PROOF'}}
    foreach($field in @('networkContacted','transportEnabled','brokerReady','ordersEnabled')){if($Value.$field -isnot [bool]){throw 'TRANSPORT_STATUS_TYPE'}}
    if($Value.brokerReady -or $Value.ordersEnabled){throw 'TRANSPORT_STATUS_SCOPE'}
    if($Phase -ceq 'TRANSPORT_READY'){
        foreach($field in @('agentIdentityVerified','signingVerified','privateCopyAbsent','networkContacted','transportEnabled','denialsVerified')){if($Value.$field -isnot [bool] -or -not $Value.$field){throw 'TRANSPORT_READY_PROOF'}}
        if($Value.childProcessId -le 0 -or $Value.childStartTicks -le 0 -or $Value.httpStatus -lt 200 -or $Value.httpStatus -gt 599 -or $Value.transportState.phase -cne 'TRANSPORT_READY'){throw 'TRANSPORT_READY_STATE'}
    }elseif($Value.transportEnabled -or $Value.childProcessId -ne 0){throw 'TRANSPORT_STOP_NOT_CLOSED'}
}
function Wait-PaytmManagedHost([string]$Id,[string]$Phase,[string]$PreviousInstance='', [int]$PreviousChild=0){
    $c=Get-PaytmHostContract;$watch=[Diagnostics.Stopwatch]::StartNew();$first=$null
    do{
        $task=Get-PaytmOwnedHostTask $Id
        $v=Read-PaytmHostJson (Join-Path $c.work 'status.json')
        if($v.installationId -cne $Id){throw 'TRANSPORT_STATUS_IDENTITY'}
        if($v.phase -ceq 'BLOCKED'){throw 'TRANSPORT_WORKER_BLOCKED'}
        if($v.phase -ceq $Phase -and $v.instanceId -cne $PreviousInstance -and ($PreviousChild -eq 0 -or $v.childProcessId -ne $PreviousChild)){
            Assert-PaytmManagedStatus $v $Id $Phase
            if($Phase -ceq 'STOPPED'){
                if([string]$task.State -cnotin @('Running','Queued')){
                    if((Get-ScheduledTaskInfo -TaskName $c.name -TaskPath '\').LastTaskResult -ne 0){throw 'TRANSPORT_STOP_EXIT'}
                    Assert-PaytmTransportListener (Get-PaytmTransportListeners);return $v
                }
            }elseif([string]$task.State -ceq 'Running'){
                if($first -and $v.sequence -gt $first.sequence){
                    Assert-PaytmHostAdvance $first $v
                    Assert-PaytmTransportListener (Get-PaytmTransportListeners) $v.childProcessId
                    return $v
                }
                if(-not $first){$first=$v}
            }
        }
        if([string]$task.State -cnotin @('Running','Queued') -and (Get-ScheduledTaskInfo -TaskName $c.name -TaskPath '\').LastTaskResult -notin @(0,267011)){throw 'TRANSPORT_TASK_EXIT'}
        Write-Progress -Activity 'Managed Windows transport' -Status ("Waiting for $Phase ($([int]$watch.Elapsed.TotalSeconds)/120 seconds)") -PercentComplete 70
        Start-Sleep -Milliseconds 500
    }while($watch.Elapsed.TotalSeconds -lt 120)
    throw 'TRANSPORT_HEARTBEAT_TIMEOUT'
}
function Initialize-PaytmManagedApplication {
    # Reuse the deployed diagnostic route. No build, deploy or application restart.
    if($env:DOCKER_HOST){throw 'APP_ROUTE_REMOTE_DOCKER_OVERRIDE'}
    $application.Docker=(Get-Command docker.exe -CommandType Application -ErrorAction Stop|Select-Object -First 1).Source
    $context=Invoke-PaytmPrivateDocker @('context','show') 'CONTEXT'
    if((Invoke-PaytmPrivateDocker @('context','inspect',$context,'--format','{{.Endpoints.docker.Host}}') 'ENDPOINT') -notmatch '^npipe://'){throw 'APP_ROUTE_LOCAL_DOCKER_REQUIRED'}
    $before=Get-PaytmApplicationContainer;$application.Id=$before.Id;$application.Before=$before
    $envMap=ConvertTo-PaperRuntimeEnvironment $before.Config.Env
    if($envMap.MARKETBRAIN_PAYTM_ENABLED -cne 'false' -or $envMap.MARKETBRAIN_PAYTM_ACCESS_TOKEN){throw 'APP_ROUTE_BROKER_MUST_REMAIN_DISABLED'}
    foreach($key in @('JAVA_TOOL_OPTIONS','JDK_JAVA_OPTIONS','_JAVA_OPTIONS')){if($envMap[$key]){throw 'APP_ROUTE_JAVA_OVERRIDE_REVIEW'}}
    $application.Token=$envMap.MARKETBRAIN_PAPER_READ_TOKEN
    Assert-PaytmWriterLocked
    $application.BeforeAccount=Read-PaytmPaperAccount
    Invoke-PaytmApplicationHttp 'status' -WithoutToken
    $v=Invoke-PaytmApplicationHttp 'status'
    if($v.state -cne 'LOCKED'){throw 'APP_ROUTE_EXPECTED_LOCKED'}
    if((Invoke-PaytmApplicationHttp 'head').status -cne 'LOCKED'){throw 'APP_ROUTE_EXPECTED_LOCKED'}
    $application.BootId=$v.bootId;$application.Ready=$true
    $report.accountBefore=$application.BeforeAccount|ConvertFrom-Json
    $report.containerId=$before.Id;$report.imageId=$before.Image
}
function Assert-PaytmTransportUpgrade {
    $c=Get-PaytmHostContract;$sid=(Get-PaytmKeyContract).accountSid
    foreach($p in @($c.root,$c.work)){$null=Assert-PaytmAccountPath $p;Assert-PaytmAccountAcl (Get-Acl -LiteralPath $p) $sid -Writable:($p -ceq $c.work)}
    $m=Read-PaytmHostJson (Join-Path $c.root 'manifest.json')
    if($m.version -ne 1 -or $m.installationId -cne 'ea8b91471cf048aa97a0f6b939b355c7' -or $m.PSObject.Properties['transportVersion']){throw 'TRANSPORT_INSTALLATION_NOT_REVIEWED'}
    foreach($name in @('host.ps1','runner.ps1','native.dll')){if((Get-FileHash -LiteralPath (Assert-PaytmAccountPath (Join-Path $c.root $name))).Hash -cne $m.hashes.$name){throw 'TRANSPORT_EXISTING_SOURCE_DRIFT'}}
    if($m.hashes.'runner.ps1' -cne 'EE0EBF9CAA0A9309085CFDC21E753D090F97FFB0499C1DC96076C643B7BC078C'){throw 'TRANSPORT_RUNNER_NOT_ACCEPTED'}
    foreach($name in @('transport.ps1','gateway.ps1','transport.dll','transport-control.json')){if(Test-Path -LiteralPath (Assert-PaytmAccountPath (Join-Path $c.root $name))){throw 'TRANSPORT_EXISTING_EXTENSION_REVIEW'}}
    foreach($name in @('blocked.json','startup-failure.json')){if(Test-Path -LiteralPath (Join-Path $c.work $name)){throw 'TRANSPORT_EXISTING_FAILURE_REVIEW'}}
    $control=Read-PaytmHostJson (Join-Path $c.root 'control.json');Assert-PaytmHostControl $control $m.installationId
    if($control.mode -cne 'LOCKED'){throw 'TRANSPORT_EXPECTED_LOCKED'}
    $m
}
function Stop-PaytmReviewedChild($Snapshot){
    Assert-PaytmManagedStatus $Snapshot $Snapshot.installationId TRANSPORT_READY
    Assert-PaytmTransportListener (Get-PaytmTransportListeners) $Snapshot.childProcessId
    $p=Get-Process -Id $Snapshot.childProcessId -ErrorAction Stop
    try{
        if($p.StartTime.ToUniversalTime().Ticks -ne $Snapshot.childStartTicks -or $p.Path -ine 'C:\Windows\System32\OpenSSH\ssh.exe'){throw 'TRANSPORT_CHILD_IDENTITY_CHANGED'}
        $p.Kill();if(-not $p.WaitForExit(5000)){throw 'TRANSPORT_CHILD_KILL_TIMEOUT'}
    }finally{$p.Dispose()}
}
function Stop-PaytmFailedManagedHost([string]$Id){
    $c=Get-PaytmHostContract
    Set-PaytmHostControl $Id STOP
    $null=Get-PaytmOwnedHostTask $Id
    $null=Disable-ScheduledTask -TaskName $c.name -TaskPath '\'
    Stop-ScheduledTask -TaskName $c.name -TaskPath '\'
    $watch=[Diagnostics.Stopwatch]::StartNew()
    do {
        $task=Get-PaytmOwnedHostTask $Id $false
        if([string]$task.State -cnotin @('Running','Queued')){
            Assert-PaytmTransportListener (Get-PaytmTransportListeners)
            return
        }
        Start-Sleep -Milliseconds 250
    }while($watch.Elapsed.TotalSeconds -lt 20)
    throw 'TRANSPORT_FAILED_HOST_STOP_TIMEOUT'
}
function Invoke-PaytmManagedLifecycle([string]$Id,[scriptblock]$Checkpoint){
    $c=Get-PaytmHostContract
    Start-ScheduledTask -TaskName $c.name -TaskPath '\';$report.locked=Wait-PaytmManagedHost $Id LOCKED; &$Checkpoint
    Set-PaytmTransportControl $Id ENABLED
    $report.first=Wait-PaytmManagedHost $Id TRANSPORT_READY; &$Checkpoint
    Invoke-PaytmApplicationHead 'Managed application TLS' $true
    Start-ScheduledTask -TaskName $c.name -TaskPath '\'
    $report.duplicate=Wait-PaytmManagedHost $Id TRANSPORT_READY
    Assert-PaytmHostAdvance $report.first $report.duplicate
    if($report.first.childProcessId -ne $report.duplicate.childProcessId){throw 'TRANSPORT_DUPLICATE_CHILD'}
    $report.duplicateStartPassed=$true; &$Checkpoint
    Set-PaytmTransportControl $Id DISABLED
    $report.disabled=Wait-PaytmManagedHost $Id LOCKED
    Invoke-PaytmApplicationHead 'Managed application closed tunnel' $false
    $report.disabledRoutePassed=$true; &$Checkpoint
    Set-PaytmTransportControl $Id ENABLED
    $report.reenabled=Wait-PaytmManagedHost $Id TRANSPORT_READY
    if((Invoke-PaytmApplicationHttp 'head').status -cne 'LOCKED'){throw 'APP_ROUTE_RECONNECT_REARMED'}
    Invoke-PaytmApplicationHead 'Managed application explicit rearm' $true
    $null=Invoke-PaytmApplicationHttp 'lock'
    Stop-PaytmReviewedChild $report.reenabled
    $report.recovered=Wait-PaytmManagedHost $Id TRANSPORT_READY '' $report.reenabled.childProcessId
    Assert-PaytmHostAdvance $report.reenabled $report.recovered
    if($report.recovered.transportState.attempts -le $report.reenabled.transportState.attempts){throw 'TRANSPORT_RECONNECT_NOT_OBSERVED'}
    if((Invoke-PaytmApplicationHttp 'head').status -cne 'LOCKED'){throw 'APP_ROUTE_RECONNECT_REARMED'}
    $report.childRecoveryPassed=$true; &$Checkpoint
    Set-PaytmHostControl $Id STOP
    $report.stopped=Wait-PaytmManagedHost $Id STOPPED
    Start-ScheduledTask -TaskName $c.name -TaskPath '\'
    $report.stoppedRestart=Wait-PaytmManagedHost $Id STOPPED $report.stopped.instanceId
    if($report.stoppedRestart.networkContacted -or $report.stoppedRestart.signingVerified){throw 'TRANSPORT_STOP_NOT_PERSISTENT'}
    $report.persistentStopPassed=$true; &$Checkpoint
    Set-PaytmHostControl $Id LOCKED
    Start-ScheduledTask -TaskName $c.name -TaskPath '\'
    $report.final=Wait-PaytmManagedHost $Id TRANSPORT_READY $report.stoppedRestart.instanceId
    if((Invoke-PaytmApplicationHttp 'head').status -cne 'LOCKED'){throw 'APP_ROUTE_RESTART_REARMED'}
    Invoke-PaytmApplicationHead 'Managed application after supervisor restart' $true
    $report.restartPassed=$true; &$Checkpoint
}
