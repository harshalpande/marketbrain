#requires -Version 7.5
function Assert-AutomationTestSpec($Spec,[string]$Kind='paytm-transport-test') {
    $modes=if($Kind -cin @('paytm-denial-recovery','paytm-time-observer')){@('Observe','Apply','FailureFixture')}else{@('Observe','FailureFixture')}
    if (@($Spec.PSObject.Properties.Name | Sort-Object) -join ',' -cne 'mode,revision,sha256' -or
        $Spec.revision -cnotmatch '^[a-f0-9]{40}$' -or $Spec.sha256 -cnotmatch '^[A-F0-9]{64}$' -or
        $Spec.mode -cnotin $modes) { throw 'INVALID_TEST_SPEC' }
}
function Get-AutomationReviewedSource([string]$Revision,[string]$Kind='paytm-transport-test') {
    $name=switch -CaseSensitive ($Kind){'paytm-transport-test'{'PaytmTransport.ps1'} 'paytm-denial-recovery'{'PaytmDenialRecovery.ps1'} 'paytm-time-observer'{'PaytmTimeObserver.ps1'} default{throw 'INVALID_TEST_IDENTITY'}}
    $client=[Net.Http.HttpClient]::new()
    $client.Timeout=[TimeSpan]::FromSeconds(30)
    $client.MaxResponseContentBufferSize=65536
    try {
        $uri='https://raw.githubusercontent.com/harshalpande/marketbrain/'+$Revision+'/ops/automation/jobs/'+$name
        return ,$client.GetByteArrayAsync($uri).GetAwaiter().GetResult()
    } finally { $client.Dispose() }
}
function Invoke-AutomationReviewedTest($Job,[string]$Root,[scriptblock]$ProgressCallback=$null) {
    Assert-AutomationTestSpec $Job.spec $Job.kind
    if ($Job.id -cnotmatch '^[a-f0-9-]{36}$' -or $Job.kind -cnotin @('paytm-transport-test','paytm-denial-recovery','paytm-time-observer')) { throw 'INVALID_TEST_IDENTITY' }
    $deadline=if($Job.kind -ceq 'paytm-denial-recovery'){240}else{120}
    $directory=Join-Path $Root ('executions/'+$Job.id)
    # A durable receipt means this identity is never executed a second time.
    if (Test-Path -LiteralPath $directory) { throw 'EXECUTION_ALREADY_RESERVED_REVIEW_REQUIRED' }
    New-Item -ItemType Directory -Path $directory -ErrorAction Stop | Out-Null
    Write-AutomationState (Join-Path $directory 'request.json') $Job
    $bytes=Get-AutomationReviewedSource $Job.spec.revision $Job.kind
    if ($bytes.Length -gt 65536) { throw 'TEST_SOURCE_TOO_LARGE' }
    $hash=[Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($bytes))
    if ($hash -cne $Job.spec.sha256) { throw 'TEST_SOURCE_HASH_MISMATCH' }
    $script=Join-Path $directory 'test.ps1'
    [IO.File]::WriteAllBytes($script,$bytes)
    $tokens=$null; $errors=$null
    $null=[Management.Automation.Language.Parser]::ParseFile($script,[ref]$tokens,[ref]$errors)
    if ($errors.Count) { throw 'TEST_SOURCE_PARSE_FAILED' }
    $resultPath=Join-Path $directory 'result.json'
    $process=[Diagnostics.Process]::new()
    try {
        $start=[Diagnostics.ProcessStartInfo]::new((Join-Path $PSHOME 'pwsh.exe'))
        $start.UseShellExecute=$false; $start.CreateNoWindow=$true
        $start.RedirectStandardOutput=$true; $start.RedirectStandardError=$true
        foreach($arg in @('-NoProfile','-NonInteractive','-File',$script,'-ResultPath',$resultPath,'-Mode',$Job.spec.mode)) { $start.ArgumentList.Add($arg) }
        $process.StartInfo=$start
        if (-not $process.Start()) { throw 'TEST_PROCESS_START_FAILED' }
        $stdout=$process.StandardOutput.ReadToEndAsync(); $stderr=$process.StandardError.ReadToEndAsync()
        $watch=[Diagnostics.Stopwatch]::StartNew()
        $lastProgress=-20
        while(-not $process.WaitForExit(1000) -and $watch.Elapsed.TotalSeconds -lt $deadline) {
            if($ProgressCallback -and $watch.Elapsed.TotalSeconds-$lastProgress -ge 15) {
                $lastProgress=$watch.Elapsed.TotalSeconds
                try { & $ProgressCallback @{phase='EXECUTING_REVIEWED_TEST';elapsedSeconds=[int]$watch.Elapsed.TotalSeconds;deadlineSeconds=$deadline;revision=$Job.spec.revision;ordersEnabled=$false} }
                catch { # Losing a progress ACK never restarts or fails the running test.
                }
            }
        }
        $timedOut=-not $process.HasExited
        if ($timedOut) { $process.Kill($true); $process.WaitForExit() }
        # Raw output stays off the relay. Tests emit their bounded structured evidence.
        $out=$stdout.GetAwaiter().GetResult(); $err=$stderr.GetAwaiter().GetResult()
        $result=@{passed=$false;revision=$Job.spec.revision;sourceSha256=$hash;timedOut=$timedOut;exitCode=$process.ExitCode;stdoutCharacters=$out.Length;stderrCharacters=$err.Length;ordersEnabled=$false}
        if (Test-Path -LiteralPath $resultPath) {
            if ((Get-Item -LiteralPath $resultPath).Length -gt 65536) { throw 'TEST_EVIDENCE_TOO_LARGE' }
            $result.evidence=Get-Content -LiteralPath $resultPath -Raw | ConvertFrom-Json -DateKind String
            $result.passed= -not $timedOut -and $process.ExitCode -eq 0 -and $result.evidence.passed -eq $true
        }
        Write-AutomationState (Join-Path $directory 'completion.json') $result
        return $result
    } finally { $process.Dispose() }
}
