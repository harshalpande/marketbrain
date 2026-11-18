#requires -Version 7.2
[CmdletBinding()]
param([switch]$Once,[ValidatePattern('^$|^[a-f0-9]{32}$')][string]$StartupNonce='')
. (Join-Path $PSScriptRoot 'Automation.Common.ps1')
. (Join-Path $PSScriptRoot 'Automation.Diagnostics.ps1')
$loadedRunnerHash=(Get-FileHash -LiteralPath $PSCommandPath -Algorithm SHA256).Hash
$loadedDiagnosticsHash=(Get-FileHash -LiteralPath (Join-Path $PSScriptRoot 'Automation.Diagnostics.ps1')).Hash
$root = Join-Path $env:LOCALAPPDATA 'MarketBrainAutomation'
$config = Get-AutomationConfig (Join-Path $root 'worker.dpapi')
if ($config.role -ne 'worker') { throw 'Worker pairing required' }
$mutex = [Threading.Mutex]::new($false,'Global\MarketBrainAutomationWorker')
if (-not $mutex.WaitOne(0)) { $mutex.Dispose(); throw 'Worker is already running' }
$pending = Join-Path $root 'pending.json'
$history = Join-Path $root 'reports'
New-Item -ItemType Directory -Path $history -Force | Out-Null
try {
    Write-AutomationState (Join-Path $root 'worker-status.json') @{state='STARTED';processId=$PID;startupNonce=$StartupNonce;runnerSha256=$loadedRunnerHash;diagnosticsSha256=$loadedDiagnosticsHash;observedUtc=[DateTimeOffset]::UtcNow.ToString('o')}
    do {
        try {
            # Persist before execution; an interrupted job is reported, never replayed.
            if (Test-Path -LiteralPath $pending) {
                $update = Get-Content -LiteralPath $pending -Raw | ConvertFrom-Json
                if ($update.state -eq 'RUNNING') {
                    $update.state = 'INTERRUPTED'
                    $update.result = @{ reason='Worker exited before saving completion'; ordersEnabled=$false }
                    Write-AutomationState $pending $update
                }
                $null = Invoke-AutomationApi $config '/update' $update
                Write-AutomationState (Join-Path $history ($update.id + '.json')) $update
                Remove-Item -LiteralPath $pending
            }
            $job = (Invoke-AutomationApi $config '/claim' @{}).job
            Write-AutomationState (Join-Path $root 'connection-status.json') @{observedUtc=[DateTimeOffset]::UtcNow.ToString('o');status='CONNECTED'}
            if ($null -ne $job) {
                $update = @{ id=$job.id; state='RUNNING'; result=$null }
                Write-AutomationState $pending $update
                $timer = [Diagnostics.Stopwatch]::StartNew()
                Write-Host "Running $($job.kind): $($job.id)"
                try {
                    switch ($job.kind) {
                        'diagnostic' {
                            # Fixed, read-only, bounded catalogue. No credentials,
                            # arbitrary commands, application changes or order calls.
                            $time = Get-Service -Name W32Time
                            $report = @{
                                observedUtc=[DateTimeOffset]::UtcNow.ToString('o')
                                powershell=$PSVersionTable.PSVersion.ToString()
                                windowsTimeService=$time.Status.ToString()
                                interactive=[Environment]::UserInteractive
                                sessionId=(Get-Process -Id $PID).SessionId
                                runnerSha256=$loadedRunnerHash
                                diagnosticsSha256=$loadedDiagnosticsHash
                                ordersEnabled=$false
                                paytmObservation=(Get-AutomationPaytmObservation)
                            }
                        }
                        'intervention-test' {
                            if (-not [Environment]::UserInteractive -or (Get-Process -Id $PID).SessionId -eq 0) { throw 'User sign-in required for local prompt' }
                            $null = Invoke-AutomationApi $config '/update' @{id=$job.id;state='WAITING_FOR_USER';result=@{instruction='Respond to the MarketBrain prompt on the spare laptop. No password required.'}}
                            # Interactive desktop companion for first release. Timeout
                            # prevents an abandoned prompt blocking the queue forever.
                            $shell = New-Object -ComObject WScript.Shell
                            try { $answer = $shell.Popup('MarketBrain automation test: click OK to confirm that local intervention works. No password or trading action is requested.',300,'MarketBrain - action required',1) }
                            finally { [void][Runtime.InteropServices.Marshal]::ReleaseComObject($shell) }
                            if ($answer -ne 1) { throw 'Intervention cancelled or timed out after five minutes' }
                            $report = @{ acknowledged=$true;ordersEnabled=$false }
                        }
                        default { throw 'Unsupported job kind' }
                    }
                    $update.state='SUCCEEDED'; $update.result=$report
                } catch {
                    $update.state='FAILED'
                    $update.result=@{reason=$_.Exception.Message.Substring(0,[Math]::Min(300,$_.Exception.Message.Length));ordersEnabled=$false}
                }
                $update.result.elapsedSeconds=$timer.Elapsed.TotalSeconds
                Write-AutomationState $pending $update
                $null = Invoke-AutomationApi $config '/update' $update
                Write-AutomationState (Join-Path $history ($job.id + '.json')) $update
                Remove-Item -LiteralPath $pending
                Write-Host "Completed $($job.id): $($update.state)"
            }
        } catch {
            # Keep the transport cause locally without headers or pairing secrets.
            $detail=$_.Exception.GetBaseException().Message.Replace($config.token,'[REDACTED]')
            Write-AutomationState (Join-Path $root 'connection-status.json') @{observedUtc=[DateTimeOffset]::UtcNow.ToString('o');status='RETRYING';errorType=$_.Exception.GetType().Name;detail=$detail.Substring(0,[Math]::Min(500,$detail.Length))}
            Write-Warning 'Connection or delivery failed; pending evidence retained. Retrying in ten seconds.'
        }
        if (-not $Once) { Start-Sleep -Seconds 10 }
    } while (-not $Once)
} finally { $mutex.ReleaseMutex(); $mutex.Dispose() }
