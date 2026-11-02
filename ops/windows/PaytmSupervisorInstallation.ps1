#Requires -Version 7.0
function Get-PaytmHostContract {
    [pscustomobject]@{root='C:\ProgramData\MarketBrainPaytmGateway\supervisor-v1';
        work='C:\ProgramData\MarketBrainPaytmGateway\supervisor-work-v1';name='MarketBrain-Gateway-Supervisor-v1';
        executable='C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe'}
}
function Get-PaytmHostArguments {
    $c=Get-PaytmHostContract
    $text="&([scriptblock]::Create([IO.File]::ReadAllText('"+$c.root+"\runner.ps1')))"
    '-NoLogo -NoProfile -NonInteractive -EncodedCommand '+[Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($text))
}
function New-PaytmHostTask([string]$InstallationId) {
    $c=Get-PaytmHostContract
    $action=New-ScheduledTaskAction -Execute $c.executable -Argument (Get-PaytmHostArguments) -WorkingDirectory $c.root
    $principal=New-ScheduledTaskPrincipal -UserId (Get-PaytmKeyContract).accountSid -LogonType Password -RunLevel Limited
    $settings=New-ScheduledTaskSettingsSet -Disable -MultipleInstances IgnoreNew -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries
    # Set serialized duration explicitly: avoid zero TimeSpan being treated as omitted by module versions.
    $settings.ExecutionTimeLimit='PT0S'
    $trigger=New-ScheduledTaskTrigger -AtStartup;$trigger.Delay='PT30S'
    New-ScheduledTask -Action $action -Principal $principal -Settings $settings -Trigger $trigger -Description ('MarketBrain locked supervisor '+$InstallationId)
}
function Assert-PaytmHostTask($Task,[string]$InstallationId,[bool]$Enabled) {
    $c=Get-PaytmHostContract;$sid=(Get-PaytmKeyContract).accountSid
    if($Task.TaskName -cne $c.name -or $Task.TaskPath -cne '\' -or $Task.Description -cne ('MarketBrain locked supervisor '+$InstallationId)){throw 'HOST_TASK_OWNERSHIP'}
    $actual=$Task.Principal.UserId
    if($actual -cne $sid){$actual=([Security.Principal.NTAccount]::new($actual)).Translate([Security.Principal.SecurityIdentifier]).Value}
    if($actual -cne $sid -or [string]$Task.Principal.LogonType -cne 'Password' -or [string]$Task.Principal.RunLevel -cne 'Limited'){throw 'HOST_TASK_PRINCIPAL'}
    $actions=@($Task.Actions);$triggers=@($Task.Triggers)
    if($actions.Count -ne 1 -or $actions[0].Execute -cne $c.executable -or $actions[0].Arguments -cne (Get-PaytmHostArguments) -or $actions[0].WorkingDirectory -cne $c.root){throw 'HOST_TASK_ACTION'}
    if($triggers.Count -ne 1 -or $triggers[0].CimClass.CimClassName -cne 'MSFT_TaskBootTrigger' -or $triggers[0].Delay -cne 'PT30S' -or -not $triggers[0].Enabled){throw 'HOST_TASK_TRIGGER'}
    $s=$Task.Settings
    if($s.Enabled -ne $Enabled -or [string]$s.MultipleInstances -cne 'IgnoreNew' -or $s.RestartCount -ne 0 -or
       -not $s.AllowDemandStart -or -not $s.AllowHardTerminate -or $s.WakeToRun -or $s.StartWhenAvailable -or $s.RunOnlyIfNetworkAvailable -or $s.RunOnlyIfIdle -or
       $s.DisallowStartIfOnBatteries -or $s.StopIfGoingOnBatteries -or [Xml.XmlConvert]::ToTimeSpan($s.ExecutionTimeLimit).Ticks -ne 0){throw 'HOST_TASK_SETTINGS'}
}
function Get-PaytmOwnedHostTask([string]$InstallationId,[bool]$Enabled=$true) {
    $tasks=@(Get-PaytmProbeTask (Get-PaytmHostContract).name)
    if($tasks.Count -ne 1){throw 'HOST_TASK_MISSING'}
    Assert-PaytmHostTask $tasks[0] $InstallationId $Enabled
    $tasks[0]
}
function Set-PaytmHostControl([string]$InstallationId,[ValidateSet('LOCKED','STOP')][string]$Mode) {
    Write-PaytmHostJson (Join-Path (Get-PaytmHostContract).root 'control.json') @{version=1;installationId=$InstallationId;mode=$Mode}
}
function Wait-PaytmHost([string]$InstallationId,[ValidateSet('LOCKED','STOPPED')][string]$Phase,[string]$PreviousInstance='') {
    $c=Get-PaytmHostContract;$watch=[Diagnostics.Stopwatch]::StartNew();$first=$null
    do {
        $task=Get-PaytmOwnedHostTask $InstallationId
        $path=Join-Path $c.work 'status.json'
        if(Test-Path -LiteralPath $path){
            $value=Read-PaytmHostJson $path
            if($value.installationId -cne $InstallationId){throw 'HOST_STATUS_WRONG_INSTALLATION'}
            if($value.phase -ceq 'BLOCKED'){throw 'HOST_WORKER_BLOCKED'}
            if($value.instanceId -cne $PreviousInstance -and $value.phase -ceq $Phase){
                if($Phase -ceq 'STOPPED'){
                    if([string]$task.State -cnotin @('Running','Queued')){
                        $info=Get-ScheduledTaskInfo -TaskName $c.name -TaskPath '\' -ErrorAction Stop
                        if($info.LastTaskResult -ne 0){throw 'HOST_STOP_EXIT_NONZERO'}
                        Assert-PaytmHostStatus $value $InstallationId STOPPED
                        return $value
                    }
                }else{
                    Assert-PaytmHostStatus $value $InstallationId
                    if([string]$task.State -cne 'Running'){throw 'HOST_TASK_NOT_RUNNING'}
                    if($first -and $value.sequence -gt $first.sequence){Assert-PaytmHostAdvance $first $value;return $value}
                    if(-not $first){$first=$value}
                }
            }
        }
        $info=Get-ScheduledTaskInfo -TaskName $c.name -TaskPath '\' -ErrorAction Stop
        if([string]$task.State -cnotin @('Running','Queued') -and $info.LastTaskResult -notin @(0,267011)){throw 'HOST_TASK_LAUNCH_FAILED'}
        Write-Progress -Activity 'Gateway supervisor installation' -Status ('Waiting for {0}: {1:n0}s / 60s' -f $Phase,$watch.Elapsed.TotalSeconds) -PercentComplete 75
        Start-Sleep -Milliseconds 500
    }while($watch.Elapsed.TotalSeconds -lt 60)
    throw 'HOST_HEARTBEAT_TIMEOUT'
}
function Invoke-PaytmHostLifecycle([string]$InstallationId,$Report,[scriptblock]$Checkpoint) {
    $c=Get-PaytmHostContract
    $null=Get-PaytmOwnedHostTask $InstallationId $false
    $null=Enable-ScheduledTask -TaskName $c.name -TaskPath '\' -ErrorAction Stop
    Start-ScheduledTask -TaskName $c.name -TaskPath '\' -ErrorAction Stop
    $Report.first=Wait-PaytmHost $InstallationId LOCKED; &$Checkpoint
    # Task Scheduler IgnoreNew plus file lease prevents competing owners.
    Start-ScheduledTask -TaskName $c.name -TaskPath '\' -ErrorAction Stop
    $Report.duplicate=Wait-PaytmHost $InstallationId LOCKED
    Assert-PaytmHostAdvance $Report.first $Report.duplicate;$Report.duplicateStartPassed=$true; &$Checkpoint
    Set-PaytmHostControl $InstallationId STOP
    $Report.stopped=Wait-PaytmHost $InstallationId STOPPED; &$Checkpoint
    # STOP is durable across a fresh process: verify it does not run signing or activate anything.
    Start-ScheduledTask -TaskName $c.name -TaskPath '\' -ErrorAction Stop
    $Report.stoppedRestart=Wait-PaytmHost $InstallationId STOPPED $Report.stopped.instanceId
    if($Report.stoppedRestart.signingVerified -ne $false){throw 'HOST_STOP_NOT_PERSISTENT'}
    $Report.persistentStopPassed=$true; &$Checkpoint
    # Explicit owner-controlled return to locked monitoring, never an enable operation.
    Set-PaytmHostControl $InstallationId LOCKED
    Start-ScheduledTask -TaskName $c.name -TaskPath '\' -ErrorAction Stop
    $Report.final=Wait-PaytmHost $InstallationId LOCKED $Report.stoppedRestart.instanceId
    $Report.restartPassed=$true; &$Checkpoint
}
