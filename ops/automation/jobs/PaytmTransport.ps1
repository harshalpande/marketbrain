#requires -Version 7.5
param([Parameter(Mandatory)][string]$ResultPath,[ValidateSet('Observe','FailureFixture')][string]$Mode='Observe')
$ErrorActionPreference='Stop'
$report=@{version=2;test='PAYTM_TRANSPORT_OBSERVATION';passed=$false;ordersEnabled=$false;brokerCredentialsUsed=$false;gatewayChanged=$false;scope='OPERATOR_TRANSPORT_NOT_BROKER_READINESS';samples=@();failure=$null}
$watch=[Diagnostics.Stopwatch]::StartNew()
function Read-BoundedJson([string]$Path) {
    if ((Get-Item -LiteralPath $Path).Length -gt 65536) { throw 'STATE_TOO_LARGE' }
    Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json -DateKind String
}
function Get-TransportPreflightEvidence($State,$Control) {
    $e=@{applicationLocked=($Control.mode -ceq 'LOCKED' -and $State.ordersEnabled -eq $false -and $State.brokerReady -eq $false)}
    foreach($name in @('phase','failure')) {
        $value=$State.$name
        if($value -is [string] -and $value -cmatch '^[A-Z][A-Z0-9_]{0,119}$'){$e[$name]=$value}
    }
    if($State.instanceId -cmatch '^[a-f0-9]{32}$'){$e.instanceId=$State.instanceId}
    if($State.sequence -is [long] -or $State.sequence -is [int]){$e.sequence=$State.sequence}
    return $e
}
try {
    if ($Mode -eq 'FailureFixture') { throw 'DELIBERATE_FAILURE_FIXTURE_NO_GATEWAY_ACCESS' }
    $control='C:\ProgramData\MarketBrainPaytmGateway\supervisor-v1\control.json'
    $status='C:\ProgramData\MarketBrainPaytmGateway\supervisor-work-v1\status.json'
    $initial=Read-BoundedJson $status
    $report.preflight=Get-TransportPreflightEvidence $initial (Read-BoundedJson $control)
    if(-not $report.preflight.applicationLocked){throw 'APPLICATION_NOT_LOCKED'}
    if($initial.phase -cne 'TRANSPORT_READY'){
        if($report.preflight.phase -ceq 'BLOCKED' -and $report.preflight.failure){throw ('GATEWAY_BLOCKED:'+$report.preflight.failure)}
        throw 'GATEWAY_NOT_READY'
    }
    for($i=0;$i -lt 6;$i++) {
        $state=Read-BoundedJson $status
        $lock=Read-BoundedJson $control
        if ($lock.mode -cne 'LOCKED' -or $state.ordersEnabled -ne $false -or $state.brokerReady -ne $false) { throw 'APPLICATION_NOT_LOCKED' }
        if ($state.instanceId -cne $initial.instanceId) { throw 'SUPERVISOR_CHANGED' }
        $listeners=@(Get-NetTCPConnection -State Listen -LocalPort 18889 -ErrorAction Stop)
        if (-not $listeners.Count -or @($listeners | Where-Object LocalAddress -NotIn @('127.0.0.1','::1')).Count) { throw 'LOOPBACK_LISTENER_REQUIRED' }
        $p=[Diagnostics.Process]::new()
        try {
            $s=[Diagnostics.ProcessStartInfo]::new((Join-Path $env:WINDIR 'System32/curl.exe'))
            $s.UseShellExecute=$false; $s.CreateNoWindow=$true; $s.RedirectStandardOutput=$true; $s.RedirectStandardError=$true
            foreach($a in @('-q','--proxy','http://127.0.0.1:18889','--noproxy','','--head','--proto','=https','--connect-timeout','4','--max-time','6','--silent','--output','NUL','--write-out','%{http_code}|%{http_connect}|%{time_appconnect}|%{time_total}','https://developer.paytmmoney.com/')) { $s.ArgumentList.Add($a) }
            $p.StartInfo=$s; [void]$p.Start()
            $o=$p.StandardOutput.ReadToEndAsync(); $e=$p.StandardError.ReadToEndAsync()
            if (-not $p.WaitForExit(8000)) { $p.Kill($true); $p.WaitForExit() }
            $raw=$o.GetAwaiter().GetResult(); $null=$e.GetAwaiter().GetResult()
            $valid=$raw -cmatch '^([0-9]{3})\|([0-9]{3})\|([0-9.]+)\|([0-9.]+)$'
            $sample=@{observedUtc=[DateTimeOffset]::UtcNow.ToString('o');sequence=$state.sequence;phase=$state.phase;exitCode=$p.ExitCode;tlsVerified=$false}
            if($valid) {
                $sample.httpStatus=[int]$Matches[1]; $sample.connectStatus=[int]$Matches[2]
                $sample.tlsVerified=$p.ExitCode -eq 0 -and $sample.connectStatus -eq 200 -and [double]::Parse($Matches[3],[Globalization.CultureInfo]::InvariantCulture) -gt 0
            }
            $report.samples+= $sample
        } finally { $p.Dispose() }
        # Every sample is checkpointed; final evidence remains available after interruption.
        [IO.File]::WriteAllText($ResultPath,($report | ConvertTo-Json -Depth 8))
        if ($i -lt 5) { Start-Sleep -Seconds 5 }
    }
    $final=Read-BoundedJson $status
    if ((Read-BoundedJson $control).mode -cne 'LOCKED' -or $final.ordersEnabled -ne $false -or $final.brokerReady -ne $false -or $final.instanceId -cne $initial.instanceId -or $final.sequence -le $initial.sequence) { throw 'FINAL_LOCK_OR_ADVANCEMENT_FAILED' }
    if (@($report.samples | Where-Object { -not $_.tlsVerified -or $_.phase -cne 'TRANSPORT_READY' }).Count) { throw 'TRANSPORT_SAMPLE_FAILED' }
    $report.passed=$true
} catch { $report.failure=$_.Exception.Message.Substring(0,[Math]::Min(200,$_.Exception.Message.Length)) }
finally {
    $report.elapsedSeconds=$watch.Elapsed.TotalSeconds
    [IO.File]::WriteAllText($ResultPath,($report | ConvertTo-Json -Depth 8))
}
if (-not $report.passed) { exit 1 }
