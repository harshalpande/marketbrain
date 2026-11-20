# Embedded in the reviewed job artifact. No execution on import.
function Save-DenialRecoveryResult($Context,$Report) {
    $tmp=$Context.resultPath+'.new'
    [IO.File]::WriteAllText($tmp,($Report|ConvertTo-Json -Depth 10),[Text.UTF8Encoding]::new($false))
    [IO.File]::Move($tmp,$Context.resultPath,$true)
}
function Assert-DenialRecoverySnapshot($Context,$Before) {
    foreach($name in $Before.hashes.Keys){
        $dir=if($name -in @('status.json','blocked.json','startup-failure.json')){$Context.work}else{$Context.root}
        $path=Join-Path $dir $name
        if($Before.hashes[$name] -ceq 'ABSENT'){if(Test-Path -LiteralPath $path){throw 'RECOVERY_SNAPSHOT_DRIFT'}}
        elseif((Get-Item -LiteralPath $path).Attributes -band [IO.FileAttributes]::ReparsePoint -or (Get-FileHash -LiteralPath $path).Hash -cne $Before.hashes[$name]){throw 'RECOVERY_SNAPSHOT_DRIFT'}
    }
    $t=Get-ScheduledTask -TaskName $Context.taskName -TaskPath '\'
    $i=Get-ScheduledTaskInfo -TaskName $Context.taskName -TaskPath '\'
    if([string]$t.State -cne 'Ready' -or -not $t.Settings.Enabled -or $i.LastTaskResult -ne 1 -or $i.LastRunTime.ToUniversalTime().ToString('o') -cne $Before.task.lastRunUtc){throw 'RECOVERY_TASK_CHANGED'}
}
function Stop-DenialRecoveryTask($Context) {
    $null=Disable-ScheduledTask -TaskName $Context.taskName -TaskPath '\' -ErrorAction Stop
    if([string](Get-ScheduledTask -TaskName $Context.taskName -TaskPath '\').State -in @('Running','Queued')){
        $null=Stop-ScheduledTask -TaskName $Context.taskName -TaskPath '\' -ErrorAction Stop
    }
    $watch=[Diagnostics.Stopwatch]::StartNew()
    do {
        $t=Get-ScheduledTask -TaskName $Context.taskName -TaskPath '\'
        $listeners=@([Net.NetworkInformation.IPGlobalProperties]::GetIPGlobalProperties().GetActiveTcpListeners()|Where-Object Port -EQ 18889)
        if([string]$t.State -notin @('Running','Queued') -and -not $t.Settings.Enabled -and -not $listeners.Count){
            $lease=$null
            try{$lease=[IO.File]::Open((Join-Path $Context.work 'instance.lock'),'Open','ReadWrite','None');return}
            catch{}finally{if($lease){$lease.Dispose()}}
        }
        Start-Sleep -Milliseconds 500
    }while($watch.Elapsed.TotalSeconds -lt 15)
    throw 'RECOVERY_STOP_NOT_VERIFIED'
}
function Register-DenialRecoveryGuard($Context,$ManifestHash) {
    # Independent stop survives termination of the controller/worker process.
    $guardPath=Join-Path $Context.archive 'guard.ps1'
    $collectorStop=''
    if($Context.collectorInstallation){
        if($Context.collectorInstallation -cne 'ab47639ee8d74da69a9466c0f59e601e'){throw 'COLLECTOR_GUARD_IDENTITY'}
        $collectorStop=@'
$ct=Get-ScheduledTask -TaskName 'MarketBrain-Health-Collector-v1' -TaskPath '\'
if($ct.Description -cne 'MarketBrain diagnostic collector ab47639ee8d74da69a9466c0f59e601e'){exit 6}
$cp='C:\ProgramData\MarketBrainPaytmHealth\collector-v1\control.json'
$cv=Get-Content -LiteralPath $cp -Raw|ConvertFrom-Json
if($cv.installationId -cne 'ab47639ee8d74da69a9466c0f59e601e'){exit 7}
$cv.enabled=$false
$tmp=$cp+'.guard.new'
[IO.File]::WriteAllText($tmp,($cv|ConvertTo-Json),[Text.UTF8Encoding]::new($false))
[IO.File]::Replace($tmp,$cp,[Management.Automation.Language.NullString]::Value)
Disable-ScheduledTask -TaskName 'MarketBrain-Health-Collector-v1' -TaskPath '\' | Out-Null
if([string](Get-ScheduledTask -TaskName 'MarketBrain-Health-Collector-v1' -TaskPath '\').State -in @('Running','Queued')){Stop-ScheduledTask -TaskName 'MarketBrain-Health-Collector-v1' -TaskPath '\'}
'@
    }
    $text=@"
`$ErrorActionPreference='Stop'
$collectorStop
if((Get-FileHash -LiteralPath '$($Context.root)\manifest.json').Hash -cne '$ManifestHash'){exit 2}
`$t=Get-ScheduledTask -TaskName '$($Context.taskName)' -TaskPath '\'
if(`$t.Description -cne 'MarketBrain locked supervisor ea8b91471cf048aa97a0f6b939b355c7'){exit 3}
Disable-ScheduledTask -TaskName '$($Context.taskName)' -TaskPath '\' | Out-Null
if([string](Get-ScheduledTask -TaskName '$($Context.taskName)' -TaskPath '\').State -in @('Running','Queued')){Stop-ScheduledTask -TaskName '$($Context.taskName)' -TaskPath '\'}
[IO.File]::WriteAllText('$($Context.archive)\guard-fired.json','{"stopRequested":true}')
"@
    [IO.File]::WriteAllText($guardPath,$text,[Text.UTF8Encoding]::new($false))
    $hash=(Get-FileHash -LiteralPath $guardPath).Hash
    $command="if((Get-FileHash -LiteralPath '$guardPath').Hash -cne '$hash'){exit 4};&([scriptblock]::Create([IO.File]::ReadAllText('$guardPath')))"
    $args='-NoLogo -NoProfile -NonInteractive -EncodedCommand '+[Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($command))
    $action=New-ScheduledTaskAction -Execute 'C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe' -Argument $args
    $trigger=New-ScheduledTaskTrigger -Once -At ((Get-Date).AddMinutes(3))
    $principal=New-ScheduledTaskPrincipal -UserId 'S-1-5-18' -LogonType ServiceAccount -RunLevel Highest
    $settings=New-ScheduledTaskSettingsSet -StartWhenAvailable -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -ExecutionTimeLimit ([TimeSpan]::FromMinutes(1))
    if(Get-ScheduledTask -TaskName $Context.guardName -TaskPath '\' -ErrorAction SilentlyContinue){throw 'RECOVERY_GUARD_ALREADY_EXISTS'}
    $null=Register-ScheduledTask -TaskName $Context.guardName -TaskPath '\' -Action $action -Trigger $trigger -Principal $principal -Settings $settings -Description ('MarketBrain bounded denial capture '+$Context.runId) -ErrorAction Stop
    $guard=Get-ScheduledTask -TaskName $Context.guardName -TaskPath '\'
    $Context.guardVerification=@{expectedBoundary=$trigger.StartBoundary;actualBoundary=$guard.Triggers[0].StartBoundary;argumentMatch=($guard.Actions[0].Arguments -ceq $args);executeMatch=($guard.Actions[0].Execute -ieq $action.Execute);userId=$guard.Principal.UserId;logonType=[string]$guard.Principal.LogonType;runLevel=[string]$guard.Principal.RunLevel}
    if($guard.Actions.Count -ne 1 -or $guard.Actions[0].Arguments -cne $args -or
       $guard.Actions[0].Execute -ine $action.Execute -or -not $guard.Settings.Enabled -or
       $guard.Principal.UserId -notin @('S-1-5-18','SYSTEM','NT AUTHORITY\SYSTEM') -or
       [string]$guard.Principal.LogonType -ne 'ServiceAccount' -or
       [string]$guard.Principal.RunLevel -ne 'Highest' -or
       $guard.Triggers.Count -ne 1 -or [DateTimeOffset]::Parse($guard.Triggers[0].StartBoundary) -ne [DateTimeOffset]::Parse($trigger.StartBoundary) -or
       -not $guard.Settings.StartWhenAvailable -or $guard.Settings.DisallowStartIfOnBatteries -or
       $guard.Settings.StopIfGoingOnBatteries){throw 'RECOVERY_GUARD_NOT_VERIFIED'}
    $Context.guardXmlHash=[Convert]::ToHexString([Security.Cryptography.SHA256]::HashData([Text.Encoding]::UTF8.GetBytes((Export-ScheduledTask -TaskName $Context.guardName -TaskPath '\'))))
}
function Remove-DenialRecoveryGuard($Context) {
    $xml=Export-ScheduledTask -TaskName $Context.guardName -TaskPath '\'
    if([Convert]::ToHexString([Security.Cryptography.SHA256]::HashData([Text.Encoding]::UTF8.GetBytes($xml))) -cne $Context.guardXmlHash){throw 'RECOVERY_GUARD_DRIFT'}
    Unregister-ScheduledTask -TaskName $Context.guardName -TaskPath '\' -Confirm:$false -ErrorAction Stop
}
function Resume-DenialRecoveryCapture($Context,$Receipt,$Report) {
    $prior='649710f6-e95b-4ebc-831b-60a99d22ac69'
    $archive=Join-Path $Context.root ('denial-recovery-'+$prior)
    $manifestHash='7DEBDC0E181DF0484E74F5FF4A2AD24D1034A8464A12DD72684A5D3EFFFAAD55'
    $lease=$null;$guardAttempted=$false
    try {
        $lease=[IO.File]::Open((Join-Path $Context.work 'instance.lock'),'Open','ReadWrite','None')
        foreach($name in $Receipt.hashes.Keys){
            if((Get-FileHash -LiteralPath (Join-Path $archive $name)).Hash -cne $Receipt.hashes[$name]){throw 'RECOVERY_BACKUP_DRIFT'}
            $dir=if($name -in @('status.json','blocked.json','startup-failure.json')){$Context.work}else{$Context.root}
            $path=Join-Path $dir $name
            if($name -in @('blocked.json','startup-failure.json')){if(Test-Path -LiteralPath $path){throw 'RECOVERY_NEW_INCIDENT'};continue}
            $expected=switch($name){'manifest.json'{$manifestHash} 'transport.ps1'{'40343DDDBF1063ACE422922D5D4DAD98B126B04C53ECA40790B174ECA8C9CBCD'} default{$Receipt.hashes[$name]}}
            if((Get-Item -LiteralPath $path).Attributes -band [IO.FileAttributes]::ReparsePoint -or (Get-FileHash -LiteralPath $path).Hash -cne $expected){throw 'RECOVERY_RESUME_DRIFT'}
        }
        $t=Get-ScheduledTask -TaskName $Context.taskName -TaskPath '\'
        $i=Get-ScheduledTaskInfo -TaskName $Context.taskName -TaskPath '\'
        if([string]$t.State -cne 'Disabled' -or $t.Settings.Enabled -or $i.LastTaskResult -ne 1 -or $i.LastRunTime.ToUniversalTime().ToString('o') -cne $Receipt.task.lastRunUtc){throw 'RECOVERY_TASK_CHANGED'}
        $saved=[xml][IO.File]::ReadAllText((Join-Path $archive 'task.xml'))
        $current=[xml](Export-ScheduledTask -TaskName $Context.taskName -TaskPath '\')
        if($saved.Task.Actions.OuterXml -cne $current.Task.Actions.OuterXml -or $saved.Task.Principals.OuterXml -cne $current.Task.Principals.OuterXml -or $t.Description -cne 'MarketBrain locked supervisor ea8b91471cf048aa97a0f6b939b355c7'){throw 'RECOVERY_TASK_IDENTITY_DRIFT'}
        if(@([Net.NetworkInformation.IPGlobalProperties]::GetIPGlobalProperties().GetActiveTcpListeners()|Where-Object Port -EQ 18889).Count){throw 'RECOVERY_LISTENER_PRESENT'}
        $oldName='MarketBrain-Denial-Guard-'+$prior
        $g=Get-ScheduledTask -TaskName $oldName -TaskPath '\'
        $guardPath=Join-Path $archive 'guard.ps1';$hash=(Get-FileHash -LiteralPath $guardPath).Hash
        $command="if((Get-FileHash -LiteralPath '$guardPath').Hash -cne '$hash'){exit 4};&([scriptblock]::Create([IO.File]::ReadAllText('$guardPath')))"
        $expectedArgs='-NoLogo -NoProfile -NonInteractive -EncodedCommand '+[Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($command))
        if([string]$g.State -in @('Running','Queued') -or $g.Description -cne ('MarketBrain bounded denial capture '+$prior) -or $g.Actions.Count -ne 1 -or $g.Actions[0].Arguments -cne $expectedArgs -or $g.Actions[0].Execute -ine 'C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe'){throw 'RECOVERY_PRIOR_GUARD_DRIFT'}
        if(Test-Path -LiteralPath $Context.archive){throw 'RECOVERY_ARCHIVE_ALREADY_EXISTS'}
        $null=New-Item -ItemType Directory -Path $Context.archive
        [IO.File]::WriteAllText((Join-Path $Context.archive 'previous-guard.xml'),(Export-ScheduledTask -TaskName $oldName -TaskPath '\'))
        Unregister-ScheduledTask -TaskName $oldName -TaskPath '\' -Confirm:$false -ErrorAction Stop
        $Report.resumedFrom=$prior;$Report.backupVerified=$true;$Report.instrumentationInstalled=$true
        $guardAttempted=$true
        Register-DenialRecoveryGuard $Context $manifestHash
        $Report.guardRegistered=$true;Save-DenialRecoveryResult $Context $Report
        $lease.Dispose();$lease=$null
        $null=Enable-ScheduledTask -TaskName $Context.taskName -TaskPath '\'
        $Report.startAttempts=1;Save-DenialRecoveryResult $Context $Report
        Start-ScheduledTask -TaskName $Context.taskName -TaskPath '\'
        Wait-DenialRecoveryObservation $Context $Report
        $Report.transportObserved=$true
    } finally {
        if($lease){$lease.Dispose()}
        if($guardAttempted){
            try{Stop-DenialRecoveryTask $Context;$Report.finalStoppedAndDisabled=$true}catch{$Report.cleanupFailure='RECOVERY_STOP_NOT_VERIFIED'}
            if($Report.finalStoppedAndDisabled -and $Context.guardXmlHash){
                try{Remove-DenialRecoveryGuard $Context;$Report.guardRemoved=$true}catch{$Report.cleanupFailure='RECOVERY_GUARD_CLEANUP_REQUIRED'}
            }
            Save-DenialRecoveryResult $Context $Report
        }
    }
}
function Wait-DenialRecoveryObservation($Context,$Report) {
    $watch=[Diagnostics.Stopwatch]::StartNew();$first=$null
    do {
        $v=Read-BoundedJson (Join-Path $Context.work 'status.json')
        if($v.instanceId -cne '1f2c636c108042898f3c58143e00d9c7'){
            if($v.installationId -cne 'ea8b91471cf048aa97a0f6b939b355c7' -or $v.ordersEnabled -ne $false -or $v.brokerReady -ne $false -or (Read-BoundedJson (Join-Path $Context.root 'control.json')).mode -cne 'LOCKED'){throw 'RECOVERY_SCOPE_DRIFT'}
            $Report.lastObservation=@{phase=$v.phase;instanceId=$v.instanceId;sequence=$v.sequence;failure=$v.failure}
            foreach($name in @('lastDenialObservation','firstDenialFailure')){
                if($v.PSObject.Properties[$name]){$Report.lastObservation[$name]=$v.$name}
            }
            Save-DenialRecoveryResult $Context $Report
            if($v.phase -ceq 'BLOCKED'){throw 'RECOVERY_NEW_WORKER_BLOCKED'}
            if($v.phase -ceq 'TRANSPORT_READY' -and $v.denialsVerified -eq $true){
                if($first -and $v.sequence -gt $first.sequence -and $watch.Elapsed.TotalSeconds-$first.seconds -ge 5){return}
                if(-not $first){$first=@{sequence=$v.sequence;seconds=$watch.Elapsed.TotalSeconds}}
            }else{$first=$null}
        }
        Start-Sleep -Seconds 1
    }while($watch.Elapsed.TotalSeconds -lt 75)
    throw 'RECOVERY_OBSERVATION_TIMEOUT'
}
function Invoke-DenialRecoveryApply($Context,$Before,[byte[]]$Bytes,$Report) {
    $lease=$null;$mutated=$false;$guardAttempted=$false
    try {
        $lease=[IO.File]::Open((Join-Path $Context.work 'instance.lock'),'Open','ReadWrite','None')
        Assert-DenialRecoverySnapshot $Context $Before
        if(Test-Path -LiteralPath $Context.archive){throw 'RECOVERY_ARCHIVE_ALREADY_EXISTS'}
        $null=New-Item -ItemType Directory -Path $Context.archive -ErrorAction Stop
        # Archive inherits the existing protected installation ACL.
        foreach($name in $Before.hashes.Keys){
            if($Before.hashes[$name] -ceq 'ABSENT'){continue}
            $dir=if($name -in @('status.json','blocked.json','startup-failure.json')){$Context.work}else{$Context.root}
            Copy-Item -LiteralPath (Join-Path $dir $name) -Destination (Join-Path $Context.archive $name) -ErrorAction Stop
            if((Get-FileHash -LiteralPath (Join-Path $Context.archive $name)).Hash -cne $Before.hashes[$name]){throw 'RECOVERY_BACKUP_MISMATCH'}
        }
        [IO.File]::WriteAllText((Join-Path $Context.archive 'task.xml'),(Export-ScheduledTask -TaskName $Context.taskName -TaskPath '\'))
        $Report.backupVerified=$true;Save-DenialRecoveryResult $Context $Report
        Assert-DenialRecoverySnapshot $Context $Before
        $mutated=$true
        $null=Disable-ScheduledTask -TaskName $Context.taskName -TaskPath '\' -ErrorAction Stop
        $staged=Join-Path $Context.archive 'new-transport.ps1'
        [IO.File]::WriteAllBytes($staged,$Bytes)
        $hash=(Get-FileHash -LiteralPath $staged).Hash
        $Report.installedTransportSha256=$hash
        [IO.File]::Replace($staged,(Join-Path $Context.root 'transport.ps1'),[Management.Automation.Language.NullString]::Value)
        $m=Read-BoundedJson (Join-Path $Context.root 'manifest.json')
        $m.hashes.'transport.ps1'=$hash
        $stagedManifest=Join-Path $Context.archive 'new-manifest.json'
        [IO.File]::WriteAllText($stagedManifest,($m|ConvertTo-Json -Depth 8),[Text.UTF8Encoding]::new($false))
        [IO.File]::Replace($stagedManifest,(Join-Path $Context.root 'manifest.json'),[Management.Automation.Language.NullString]::Value)
        if((Get-FileHash -LiteralPath (Join-Path $Context.root 'transport.ps1')).Hash -cne $hash){throw 'RECOVERY_INSTALLED_HASH_MISMATCH'}
        $Report.instrumentationInstalled=$true;Save-DenialRecoveryResult $Context $Report
        foreach($name in @('blocked.json','startup-failure.json')){
            $path=Join-Path $Context.work $name
            if((Get-FileHash -LiteralPath $path).Hash -cne $Before.hashes[$name]){throw 'RECOVERY_MARKER_DRIFT'}
            Remove-Item -LiteralPath $path -ErrorAction Stop
        }
        $Report.archivedMarkersCleared=$true
        $guardAttempted=$true
        Register-DenialRecoveryGuard $Context (Get-FileHash -LiteralPath (Join-Path $Context.root 'manifest.json')).Hash
        $Report.guardRegistered=$true;Save-DenialRecoveryResult $Context $Report
        $lease.Dispose();$lease=$null
        $null=Enable-ScheduledTask -TaskName $Context.taskName -TaskPath '\' -ErrorAction Stop
        # Persist the attempt before dispatch; never retry an uncertain start.
        $Report.startAttempts=1;Save-DenialRecoveryResult $Context $Report
        Start-ScheduledTask -TaskName $Context.taskName -TaskPath '\' -ErrorAction Stop
        Wait-DenialRecoveryObservation $Context $Report
        $Report.transportObserved=$true
    } finally {
        if($lease){$lease.Dispose()}
        if($mutated){
            try {Stop-DenialRecoveryTask $Context;$Report.finalStoppedAndDisabled=$true}
            catch {$Report.cleanupFailure='RECOVERY_STOP_NOT_VERIFIED';$Report.passed=$false}
            if($guardAttempted -and $Report.finalStoppedAndDisabled -and $Context.guardXmlHash){
                try {Remove-DenialRecoveryGuard $Context;$Report.guardRemoved=$true}
                catch {$Report.cleanupFailure='RECOVERY_GUARD_CLEANUP_REQUIRED';$Report.passed=$false}
            }
            elseif($guardAttempted -and -not $Context.guardXmlHash){$Report.cleanupFailure='RECOVERY_GUARD_REGISTRATION_REVIEW_REQUIRED';$Report.passed=$false}
            Save-DenialRecoveryResult $Context $Report
        }
    }
}
