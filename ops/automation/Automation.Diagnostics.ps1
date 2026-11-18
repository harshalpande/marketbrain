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
