#requires -Version 7.2
function Invoke-AutomationNativeObservation([string]$Executable,[string[]]$Arguments,[int]$TimeoutSeconds=12) {
    $watch=[Diagnostics.Stopwatch]::StartNew()
    $process=[Diagnostics.Process]::new()
    try {
        $start=[Diagnostics.ProcessStartInfo]::new($Executable)
        $start.UseShellExecute=$false; $start.CreateNoWindow=$true
        $start.RedirectStandardOutput=$true; $start.RedirectStandardError=$true
        foreach($argument in $Arguments) { $start.ArgumentList.Add($argument) }
        $process.StartInfo=$start
        if (-not $process.Start()) { throw 'Process did not start' }
        $stdout=$process.StandardOutput.ReadToEndAsync()
        $stderr=$process.StandardError.ReadToEndAsync()
        $timedOut=-not $process.WaitForExit($TimeoutSeconds*1000)
        if ($timedOut) { $process.Kill($true); [void]$process.WaitForExit(2000) }
        $output=''; $errorOutput=''
        if ($stdout.Wait(1000)) { $output=$stdout.Result }
        if ($stderr.Wait(1000)) { $errorOutput=$stderr.Result }
        return @{exitCode=if($process.HasExited){$process.ExitCode}else{$null};timedOut=$timedOut;stdout=$output.Substring(0,[Math]::Min(2048,$output.Length));stderr=$errorOutput.Substring(0,[Math]::Min(512,$errorOutput.Length));elapsedSeconds=$watch.Elapsed.TotalSeconds}
    } catch {
        return @{errorType=$_.Exception.GetType().Name;elapsedSeconds=$watch.Elapsed.TotalSeconds}
    } finally { $process.Dispose() }
}
function Get-AutomationPaytmObservation {
    $report=@{scope='INTERACTIVE_OPERATOR_READ_ONLY_NOT_HEALTH_ACCOUNT_ACCEPTANCE';ordersEnabled=$false;permissionChanges=$false}
    $report.gatewaySupervisor=Get-AutomationGatewayObservation
    $identity=[Security.Principal.WindowsIdentity]::GetCurrent()
    try { $report.elevated=([Security.Principal.WindowsPrincipal]::new($identity)).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator) }
    finally { $identity.Dispose() }
    $w32=Join-Path $env:WINDIR 'System32\w32tm.exe'
    $report.windowsStatus=Invoke-AutomationNativeObservation $w32 @('/query','/status','/verbose') 5
    $report.windowsSource=Invoke-AutomationNativeObservation $w32 @('/query','/source') 5
    try {
        $report.listeners=@(Get-NetTCPConnection -LocalPort 18889 -State Listen -ErrorAction Stop | ForEach-Object { @{address=$_.LocalAddress;port=$_.LocalPort;processId=$_.OwningProcess} })
    } catch { $report.listenerInspectionError=$_.Exception.GetType().Name }
    $tcp=[Net.Sockets.TcpClient]::new()
    try { $connection=$tcp.ConnectAsync('127.0.0.1',18889); $report.loopbackTcpConnected=($connection.Wait(2000) -and $tcp.Connected) }
    catch { $report.loopbackTcpConnected=$false }
    finally { $tcp.Dispose() }
    $curl=Join-Path $env:WINDIR 'System32\curl.exe'
    # Diagnostic comparison only. Does not relax any production timeout or gate.
    $report.proxyObservations=@(foreach($seconds in @(2,8)) {
        $arguments=@('-q','--proxy','http://127.0.0.1:18889','--noproxy','','--head','--proto','=https','--connect-timeout',"$seconds",'--max-time',"$($seconds+2)",'--silent','--show-error','--output','NUL','--write-out','%{http_code}|%{http_connect}|%{remote_ip}|%{time_connect}|%{time_appconnect}|%{time_total}','https://developer.paytmmoney.com/')
        @{connectTimeoutSeconds=$seconds;observation=(Invoke-AutomationNativeObservation $curl $arguments ($seconds+4))}
    })
    return $report
}

function Select-AutomationGatewayFields($Value,[int]$Depth=0) {
    $selected=@{}
    # Never return raw logs, command lines, keys or unknown JSON fields.
    $numbers=@('version','transportVersion','processId','sessionId','sequence','elapsedSeconds','lastSeconds','attempts','failures','retryAtSeconds','hresult','line','nativeErrorCode','nativePhaseMilliseconds','nativeTotalMilliseconds','signingChecks','lastTaskResult','exitCode','limitSeconds','stdoutCharacters','stderrCharacters')
    $booleans=@('identityVerified','agentIdentityVerified','signingVerified','privateCopyAbsent','networkContacted','transportEnabled','brokerReady','ordersEnabled','nonAdmin','nonInteractiveSession','taskRegistered','taskStarted','taskDisabled','taskRemoved','keyImported','agentChanged','productionStateUnchanged','timedOut')
    $codes=@('phase','mode','stage','failure','reason','action','type','outerType','nativeOperation','cleanupOperation','cleanupType','status','cleanupFailure','taskState','operation','classification','errorType')
    foreach($property in $Value.PSObject.Properties) {
        $name=$property.Name; $item=$property.Value
        if ($name -in $numbers -and ($item -is [int] -or $item -is [long] -or $item -is [double])) { $selected[$name]=$item }
        elseif ($name -in $booleans -and $item -is [bool]) { $selected[$name]=$item }
        elseif ($name -in $codes -and ($null -eq $item -or ($item -is [string] -and $item -cmatch '^[A-Za-z][A-Za-z0-9_]{0,119}$'))) { $selected[$name]=$item }
        elseif ($name -in @('installationId','instanceId','runId') -and $item -is [string] -and $item -cmatch '^[a-f0-9]{32}$') { $selected[$name]=$item }
        elseif ($name -eq 'nativeObservations' -and $Depth -lt 2) { $selected[$name]=@( @($item) | Select-Object -First 8 | ForEach-Object { Select-AutomationGatewayFields $_ ($Depth+1) }) }
        elseif ($name -eq 'sourceHashes' -and $null -ne $item) {
            $hashes=@{}
            foreach($hash in $item.PSObject.Properties) { if($hash.Name -cmatch '^[A-Za-z0-9-]+\.ps1$' -and $hash.Value -is [string] -and $hash.Value -cmatch '^[A-Fa-f0-9]{64}$'){$hashes[$hash.Name]=$hash.Value} }
            $selected[$name]=$hashes
        }
        elseif ($name -eq 'observedUtc' -and $item -is [string] -and $item.Length -le 50) {
            $parsed=[DateTimeOffset]::MinValue
            if ([DateTimeOffset]::TryParse($item,[ref]$parsed)) { $selected[$name]=$parsed.ToString('o') }
        }
        elseif ($name -eq 'observedUtc' -and ($item -is [DateTime] -or $item -is [DateTimeOffset])) { $selected[$name]=$item.ToString('o') }
        elseif ($name -in @('transportState','details','worker','failureDetails') -and $Depth -lt 2 -and $null -ne $item) { $selected[$name]=Select-AutomationGatewayFields $item ($Depth+1) }
    }
    return $selected
}
function Read-AutomationGatewaySnapshot([string]$Path) {
    $stream=$null; $reader=$null
    try {
        $stream=[IO.File]::Open($Path,'Open','Read',([IO.FileShare]::ReadWrite -bor [IO.FileShare]::Delete))
        if ($stream.Length -gt 65536) { return @{state='TOO_LARGE'} }
        $reader=[IO.StreamReader]::new($stream)
        $buffer=[char[]]::new(65537)
        $length=$reader.ReadBlock($buffer,0,$buffer.Length)
        if ($length -gt 65536) { return @{state='TOO_LARGE'} }
        $value=([string]::new($buffer,0,$length)) | ConvertFrom-Json -ErrorAction Stop
        return @{state='READ';fields=(Select-AutomationGatewayFields $value)}
    } catch {
        $errorType=$_.Exception.GetBaseException().GetType().Name
        return @{state='UNAVAILABLE';errorType=$errorType}
    } finally { if($reader){$reader.Dispose()}; if($stream){$stream.Dispose()} }
}
function Get-AutomationGatewayObservation {
    $code='C:\ProgramData\MarketBrainPaytmGateway\supervisor-v1'
    $work='C:\ProgramData\MarketBrainPaytmGateway\supervisor-work-v1'
    $result=@{readOnly=$true;capturedUtc=[DateTimeOffset]::UtcNow.ToString('o');files=@{}}
    $result.localSigningProbe=Read-AutomationGatewaySnapshot 'C:\MarketBrainData\Review\automation-gateway-signing-latest.json'
    foreach($name in @('manifest.json','control.json','transport-control.json')) { $result.files[$name]=Read-AutomationGatewaySnapshot (Join-Path $code $name) }
    foreach($name in @('status.json','blocked.json','startup-failure.json')) { $result.files[$name]=Read-AutomationGatewaySnapshot (Join-Path $work $name) }
    $taskSource=@'
$ErrorActionPreference='Stop'
try {
 $t=Get-ScheduledTask -TaskName 'MarketBrain-Gateway-Supervisor-v1' -TaskPath '\' -ErrorAction Stop
 $i=Get-ScheduledTaskInfo -TaskName $t.TaskName -TaskPath '\' -ErrorAction Stop
 @{state=[string]$t.State;enabled=[bool]$t.Settings.Enabled;lastTaskResult=$i.LastTaskResult;lastRunTime=$i.LastRunTime.ToString('o');logonType=[string]$t.Principal.LogonType;runLevel=[string]$t.Principal.RunLevel;actionCount=@($t.Actions).Count}|ConvertTo-Json -Compress
} catch { @{errorType=$_.Exception.GetBaseException().GetType().Name}|ConvertTo-Json -Compress;exit 1 }
'@
    $encoded=[Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($taskSource))
    $result.task=Invoke-AutomationNativeObservation (Join-Path $env:WINDIR 'System32\WindowsPowerShell\v1.0\powershell.exe') @('-NoProfile','-NonInteractive','-EncodedCommand',$encoded) 12
    try { $s=Get-Service -Name ssh-agent -ErrorAction Stop; $result.sshAgentService=@{status=$s.Status.ToString();startType=$s.StartType.ToString()} }
    catch { $result.sshAgentService=@{errorType=$_.Exception.GetType().Name} }
    Start-Sleep -Seconds 2
    $result.secondStatus=Read-AutomationGatewaySnapshot (Join-Path $work 'status.json')
    return $result
}
