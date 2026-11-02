#Requires -Version 5.1
[CmdletBinding()]param([switch]$AsObject)
$ErrorActionPreference='Stop'
foreach($name in @('PaytmSupervisorHost.ps1','PaytmSupervisorInstallation.ps1','PaytmGatewayKeyCustody.ps1','PaytmTunnelVerification.ps1')){
    . ([scriptblock]::Create([IO.File]::ReadAllText((Join-Path $PSScriptRoot $name))))
}
$count=0;$temp=Join-Path ([IO.Path]::GetTempPath()) ('mb-host-tests-'+[guid]::NewGuid().ToString('N'))
$null=New-Item -ItemType Directory -Path $temp
$handles=[Collections.Generic.List[object]]::new()
function Check([bool]$Condition,[string]$Label){if(-not $Condition){throw "TEST_FAILED_$Label"};$script:count++}
function Reject([scriptblock]$Body,[string]$Label){$failed=$false;try{&$Body}catch{$failed=$true};Check $failed $Label}
function NativeScript([string]$Code){
    $encoded=[Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($Code))
    $h=Start-TunnelProcess 'C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe' @('-NoLogo','-NoProfile','-NonInteractive','-EncodedCommand',$encoded)
    $handles.Add($h);$h
}
try {
    $dll=Join-Path $temp 'native.dll';Add-Type -Path (Join-Path $PSScriptRoot 'PaytmSupervisorNative.cs') -OutputAssembly $dll
    Add-Type -Path $dll
    $tool='C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe'
    function NativeResult([string]$Code,[int]$Limit=5000){
        $encoded=[Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($Code))
        [MarketBrain.Supervisor.NativeCommand]::Run($tool,[string[]]@('-NoProfile','-NonInteractive','-EncodedCommand',$encoded),$Limit)
    }
    $r=NativeResult "[Console]::Out.Write(('x'*80000));[Console]::Error.Write(('y'*80000))"
    Check ($r.ExitCode -eq 0 -and -not $r.TimedOut -and $r.Output.Length -eq 16384 -and $r.Error.Length -eq 16384) 'BOUNDED_STDOUT_STDERR'
    $r=NativeResult 'Start-Sleep -Seconds 30' 300
    Check $r.TimedOut 'BOUNDED_TIMEOUT'
    Reject {[MarketBrain.Supervisor.NativeCommand]::Run($tool,[string[]]@("bad`nargument"),100)} 'ARGUMENT_REJECTION'
    Reject {[MarketBrain.Supervisor.NativeCommand]::Run($tool,[string[]]@(),31000)} 'TIMEOUT_RANGE'
    $code='$value=$args[0];[Console]::Write($value)'
    $script=Join-Path $temp 'argument.ps1';[IO.File]::WriteAllText($script,$code)
    $sample='space "quote" trail\'
    $r=[MarketBrain.Supervisor.NativeCommand]::Run($tool,[string[]]@('-NoProfile','-File',$script,$sample),5000)
    Check ($r.Output -ceq $sample) 'NATIVE_QUOTING'
    # Real isolated process enters a job, creates a child, then is forcibly terminated.
    $childPath=Join-Path $temp 'child.json'
    $template=@'
$ErrorActionPreference='Stop'
Add-Type -Path '__DLL__'
[MarketBrain.Supervisor.Lifetime]::AttachCurrentProcess()
$i=[Diagnostics.ProcessStartInfo]::new('C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe')
$i.UseShellExecute=$false;$i.CreateNoWindow=$true;$i.Arguments='-NoProfile -NonInteractive -Command "Start-Sleep -Seconds 60"'
$p=[Diagnostics.Process]::Start($i)
@{id=$p.Id;start=$p.StartTime.ToUniversalTime().Ticks}|ConvertTo-Json|Set-Content -LiteralPath '__CHILD__'
Start-Sleep -Seconds 60
'@
    $other=NativeScript 'Start-Sleep -Seconds 60'
    $owner=NativeScript ($template.Replace('__DLL__',$dll).Replace('__CHILD__',$childPath))
    $wait=[Diagnostics.Stopwatch]::StartNew()
    while(-not (Test-Path -LiteralPath $childPath) -and $wait.Elapsed.TotalSeconds -lt 10){Start-Sleep -Milliseconds 100}
    Check (Test-Path -LiteralPath $childPath) 'JOB_CHILD_CREATED'
    $child=[IO.File]::ReadAllText($childPath)|ConvertFrom-Json
    $ownedChild=Get-Process -Id $child.id -ErrorAction Stop
    $result=Complete-TunnelProcess $owner -StopNow
    Check $result.StoppedByRunner 'JOB_OWNER_KILLED'
    Check ($ownedChild.WaitForExit(5000)) 'JOB_DESCENDANT_KILLED'
    $ownedChild.Dispose()
    # A second independent process must not be harmed by cleanup of the owned job.
    Check (-not $other.Process.HasExited) 'UNRELATED_PROCESS_LIVES'
    $null=Complete-TunnelProcess $other -StopNow
    $lockPath=Join-Path $temp 'instance.lock'
    $lease=[IO.File]::Open($lockPath,'OpenOrCreate','ReadWrite','None')
    try{Reject {$f=[IO.File]::Open($lockPath,'OpenOrCreate','ReadWrite','None');$f.Dispose()} 'EXCLUSIVE_LEASE'}finally{$lease.Dispose()}
    $lease=[IO.File]::Open($lockPath,'OpenOrCreate','ReadWrite','None');$lease.Dispose();Check $true 'LEASE_REACQUIRED'
    $id='a'*32;$control=[pscustomobject]@{version=1;installationId=$id;mode='LOCKED'}
    Assert-PaytmHostControl $control $id;Check $true 'LOCKED_CONTROL'
    $control.mode='STOP';Assert-PaytmHostControl $control $id;Check $true 'STOP_CONTROL'
    foreach($bad in @('RUN','ENABLED','locked','', 'STOP ')){$control.mode=$bad;Reject {Assert-PaytmHostControl $control $id} 'NO_ENABLE_PATH'}
    $control.mode='LOCKED';Reject {Assert-PaytmHostControl $control ('b'*32)} 'WRONG_INSTALLATION'
    $p=Join-Path $temp 'status.json'
    foreach($n in 1..20){Write-PaytmHostJson $p @{value=$n}}
    Check ((Read-PaytmHostJson $p).value -eq 20) 'ATOMIC_REPLACE'
    Check (@(Get-ChildItem -LiteralPath $temp -Filter '*.tmp').Count -eq 0) 'NO_TEMP_LEAK'
    Reject {Write-PaytmHostJson $p @{value=('x'*20000)}} 'STATUS_SIZE_BOUND'
    $status=[pscustomobject]@{version=1;installationId=$id;instanceId=('c'*32);phase='LOCKED';failure=$null;
        sequence=1;processId=100;sessionId=0;elapsedSeconds=1;observedUtc=$null;identityVerified=$true;jobContained=$true;
        agentIdentityVerified=$true;signingVerified=$true;privateCopyAbsent=$true;networkContacted=$false;
        transportEnabled=$false;brokerReady=$false;ordersEnabled=$false}
    Assert-PaytmHostStatus $status $id;Check $true 'STATUS_VALID'
    foreach($field in @('identityVerified','jobContained','signingVerified','privateCopyAbsent')){
        $v=$status.PSObject.Copy();$v.$field=$false;Reject {Assert-PaytmHostStatus $v $id} 'PROOF_REQUIRED'
    }
    foreach($field in @('networkContacted','transportEnabled','brokerReady','ordersEnabled')){
        $v=$status.PSObject.Copy();$v.$field=$true;Reject {Assert-PaytmHostStatus $v $id} 'SCOPE_REQUIRED'
    }
    Reject {Assert-PaytmHostAdvance $status $status} 'STALE_STATUS_REJECTED'
    $v=$status.PSObject.Copy();$v.sequence=2;Assert-PaytmHostAdvance $status $v;Check $true 'ADVANCING_HEARTBEAT'
    $v.instanceId='d'*32;Reject {Assert-PaytmHostAdvance $status $v} 'INSTANCE_REPLACEMENT_REJECTED'
    $v=$status.PSObject.Copy();$v.phase='STOPPED';$v.signingVerified=$false;$v.agentIdentityVerified=$false;$v.privateCopyAbsent=$false
    Assert-PaytmHostStatus $v $id STOPPED;Check $true 'UNSIGNED_STOP_ACCEPTED'
    $v.jobContained=$false;Reject {Assert-PaytmHostStatus $v $id STOPPED} 'STOP_IDENTITY_PROOF_REQUIRED'
    # Real native ScheduledTasks constructors only. No registration or policy changes.
    Import-Module ScheduledTasks -ErrorAction Stop
    $definition=New-PaytmHostTask $id
    $task=[pscustomobject]@{TaskName=(Get-PaytmHostContract).name;TaskPath='\';Description=$definition.Description;
        Principal=$definition.Principal;Settings=$definition.Settings;Actions=$definition.Actions;Triggers=$definition.Triggers}
    Assert-PaytmHostTask $task $id $false;Check $true 'NATIVE_TASK_DEFINITION'
    $task.Settings.ExecutionTimeLimit='PT72H';Reject {Assert-PaytmHostTask $task $id $false} 'DEFAULT_THREE_DAY_LIMIT_REJECTED';$task.Settings.ExecutionTimeLimit='PT0S'
    $task.Triggers[0].Delay='PT0S';Reject {Assert-PaytmHostTask $task $id $false} 'BOOT_TRIGGER_DRIFT';$task.Triggers[0].Delay='PT30S'
    $task.Settings.WakeToRun=$true;Reject {Assert-PaytmHostTask $task $id $false} 'WAKE_DRIFT';$task.Settings.WakeToRun=$false
    $task.Actions[0].Arguments='wrong';Reject {Assert-PaytmHostTask $task $id $false} 'ACTION_DRIFT'
    # Real host loop and atomic files with only signing/time waits mocked; no identity bypass in runner.
    $script:signs=0;$script:sleeps=0
    function Test-PaytmHostSigning {$script:signs++}
    function Start-Sleep {
        $script:sleeps++
        if($script:sleeps -ge 2){Write-PaytmHostJson (Join-Path $temp 'control.json') @{version=1;installationId=$id;mode='STOP'}}
    }
    Write-PaytmHostJson (Join-Path $temp 'control.json') @{version=1;installationId=$id;mode='LOCKED'}
    $observation=$status.PSObject.Copy();$clock=[Diagnostics.Stopwatch]::StartNew()
    Invoke-PaytmHostObservationLoop $temp $temp $temp $observation $clock
    Check ($script:signs -eq 1 -and $observation.phase -ceq 'STOPPED' -and $observation.sequence -eq 4) 'ACTUAL_LOOP_HEARTBEATS_AND_STOP'
    $script:signs=0;$observation=$status.PSObject.Copy();$observation.signingVerified=$false
    Invoke-PaytmHostObservationLoop $temp $temp $temp $observation $clock
    Check ($script:signs -eq 0 -and $observation.phase -ceq 'STOPPED' -and -not $observation.signingVerified) 'STOP_BOOT_SKIPS_SIGNING'
    Write-PaytmHostJson (Join-Path $temp 'control.json') @{version=1;installationId=$id;mode='RUN'}
    Reject {Invoke-PaytmHostObservationLoop $temp $temp $temp $observation $clock} 'LOOP_ENABLE_REJECTED'
    Write-PaytmHostJson (Join-Path $temp 'control.json') @{version=1;installationId=$id;mode='LOCKED'}
    Write-PaytmHostJson (Join-Path $temp 'blocked.json') @{failure='HOST_SIGNING_FAILED'}
    Reject {Invoke-PaytmHostObservationLoop $temp $temp $temp $observation $clock} 'BLOCK_SURVIVES_RESTART'
    Check ($script:signs -eq 0) 'BLOCK_DOES_NOT_SIGN'
    Remove-Item Function:\Start-Sleep
    # Controller orchestration with mocked Task Scheduler and deterministic status observations.
    $script:events=[Collections.Generic.List[string]]::new();$script:phase='LOCKED';$script:instance=1;$script:sequence=0
    function Get-PaytmOwnedHostTask {$null}
    function Enable-ScheduledTask {$script:events.Add('ENABLE')}
    function Start-ScheduledTask {$script:events.Add('START')}
    function Set-PaytmHostControl($InstallationId,$Mode){$script:phase=$Mode;if($Mode -ceq 'LOCKED'){$script:instance++};$script:events.Add($Mode)}
    function Wait-PaytmHost($InstallationId,$Phase,$PreviousInstance){
        $script:sequence++;$v=$status.PSObject.Copy();$v.instanceId=('{0:x32}' -f $script:instance);$v.sequence=$script:sequence;$v.phase=$Phase
        if($Phase -ceq 'STOPPED' -and $PreviousInstance){$script:instance++;$v.instanceId=('{0:x32}' -f $script:instance);$v.signingVerified=$false}
        $v
    }
    $report=@{};Invoke-PaytmHostLifecycle $id $report {}
    Check ($report.duplicateStartPassed -and $report.persistentStopPassed -and $report.restartPassed) 'LIFECYCLE_ACCEPTANCE'
    Check (($script:events -join ',') -ceq 'ENABLE,START,START,STOP,START,LOCKED,START') 'LIFECYCLE_ORDER'
    $result=[pscustomobject]@{status='ENGINEERING_PASSED_SPARE_INSTALL_PENDING';assertions=$count;
        nativeBoundedOutputTested=$true;nativeOwnerDeathKillsChild=$true;nativeTaskDefinitionTested=$true;
        actualTaskRegistered=$false;accountPolicyChanged=$false;spareRuntimeTested=$false;networkContacted=$false;ordersEnabled=$false}
    if($AsObject){$result}else{$result|ConvertTo-Json}
}finally{
    foreach($h in $handles){if($null -eq $h.Result){try{$null=Complete-TunnelProcess $h -StopNow}catch{}}}
    # Only this verified unique fixture directory; loaded DLL may remain until process exit.
    $resolved=[IO.Path]::GetFullPath($temp);$base=[IO.Path]::GetFullPath([IO.Path]::GetTempPath())
    if($resolved.StartsWith($base,[StringComparison]::OrdinalIgnoreCase) -and ([IO.Path]::GetFileName($resolved)) -like 'mb-host-tests-*'){
        Get-ChildItem -LiteralPath $resolved -File | Where-Object {$_.Extension -ne '.dll'} | Remove-Item -ErrorAction SilentlyContinue
    }
}
