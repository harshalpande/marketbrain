# Definitions only. No service, provider, model or database access.
Set-StrictMode -Version Latest
. (Join-Path $PSScriptRoot 'NumericalHistoryEvidence.ps1')

function ConvertTo-EvaluationProcessArgument([string]$Value) {
    # Windows CommandLineToArgvW quoting, including embedded quotes and trailing slashes.
    '"' + [regex]::Replace([regex]::Replace($Value, '(\\*)"', '$1$1\"'), '(\\+)$', '$1$1') + '"'
}

function Invoke-EvaluationProcess {
    param([string]$Executable,[string[]]$Arguments,[ValidateRange(1,300)][int]$TimeoutSeconds=120)
    $info = [Diagnostics.ProcessStartInfo]::new()
    $info.FileName=$Executable
    $info.Arguments=($Arguments | ForEach-Object { ConvertTo-EvaluationProcessArgument $_ }) -join ' '
    $info.UseShellExecute=$false; $info.CreateNoWindow=$true
    $info.RedirectStandardOutput=$true; $info.RedirectStandardError=$true
    # Do not allow machine-local JVM options/agents to change this fixed smoke test.
    foreach($key in @('JAVA_TOOL_OPTIONS','JDK_JAVA_OPTIONS','_JAVA_OPTIONS')) { $info.EnvironmentVariables.Remove($key) }
    $process=[Diagnostics.Process]::new(); $process.StartInfo=$info
    $started=$false; $timer=[Diagnostics.Stopwatch]::StartNew(); $lastHeartbeat=0
    try {
        $started=$process.Start()
        if(-not $started){throw 'Evaluation child could not start.'}
        $stdout=$process.StandardOutput.ReadToEndAsync(); $stderr=$process.StandardError.ReadToEndAsync()
        $complete=$false
        while($timer.Elapsed.TotalSeconds -lt $TimeoutSeconds){
            if($process.WaitForExit(250)){$complete=$true;break}
            if($timer.Elapsed.TotalSeconds-$lastHeartbeat -ge 5){
                $lastHeartbeat=$timer.Elapsed.TotalSeconds
                Write-Host ('[40%] Synthetic checks running; elapsed={0:N0}s; limit={1}s' -f $timer.Elapsed.TotalSeconds,$TimeoutSeconds)
                Write-Progress -Activity 'Numerical evaluation engineering' -Status 'Synthetic JVM checks (not model inference)' -PercentComplete 40
            }
        }
        if(-not $complete){$process.Kill(); if(-not $process.WaitForExit(5000)){throw 'Timed-out child did not stop.'}}
        if(-not $stdout.Wait(5000) -or -not $stderr.Wait(5000)){throw 'Timed out draining child evidence.'}
        [pscustomobject]@{exitCode=if($complete){$process.ExitCode}else{-999};timedOut=(-not $complete)
            stdout=$stdout.Result;stderr=$stderr.Result;elapsedSeconds=$timer.Elapsed.TotalSeconds}
    } finally {
        if($started){try{if(-not $process.HasExited){$process.Kill();[void]$process.WaitForExit(5000)}}catch{}}
        $process.Dispose();$timer.Stop()
    }
}

function Assert-EvaluationSmoke($Result) {
    if($Result.version -cne 'NUMERICAL_EVALUATION_ENGINEERING_V1' -or $Result.status -cne 'SYNTHETIC_CHECKS_PASSED') {throw 'Unexpected synthetic result contract/status.'}
    foreach($key in @('trainingAuthorized','databaseWritesPerformed')){if($Result.$key -isnot [bool] -or $Result.$key){throw "Unsafe flag: $key"}}
    if($Result.syntheticOnly -isnot [bool] -or -not $Result.syntheticOnly){throw 'Not synthetic-only evidence.'}
    foreach($key in @('providerCallCount','modelCallCount','ordersCreated','failedCheckCount')){
        if($Result.$key -isnot [int] -and $Result.$key -isnot [long]){throw "Invalid counter: $key"}
        if($Result.$key -ne 0){throw "Unexpected activity/failure: $key"}
    }
    $checks=@($Result.checks)
    if(($Result.checkCount -isnot [int] -and $Result.checkCount -isnot [long]) -or $checks.Count -ne 22 -or $Result.checkCount -ne $checks.Count){throw 'Incomplete synthetic suite.'}
    $names=@{}
    foreach($check in $checks){
        if($check.passed -isnot [bool] -or -not $check.passed -or $check.fixtureSha256 -cnotmatch '^[a-f0-9]{64}$' -or
            $check.failure -or [string]::IsNullOrWhiteSpace($check.name) -or $names.ContainsKey([string]$check.name)){throw 'Invalid/duplicate synthetic check.'}
        if($null -eq $check.elapsedMillis -or $check.elapsedMillis -is [string] -or $check.elapsedMillis -is [bool] -or
            [double]::IsNaN([double]$check.elapsedMillis) -or [double]::IsInfinity([double]$check.elapsedMillis) -or $check.elapsedMillis -lt 0){throw 'Invalid check timing.'}
        $names[[string]$check.name]=$true
    }
    foreach($name in @('hand_calculated_metrics','order_independence','empty_unavailable','duplicate_rejected',
        'invalid_number_NaN','invalid_number_Infinity','invalid_number_-Infinity','invalid_number_1.7976931348623157E308',
        'mixed_contract_rejected','flat_sign_including_negative_zero','valid_declared_metadata','overlap_TRAIN','overlap_VALIDATION',
        'same_date_split_rejected','inspected_period_rejected','unknown_availability_rejected','future_availability_rejected',
        'outcome_feature_rejected','insufficient_gap_rejected','duplicate_evaluation_rejected','empty_partitions_rejected','guard_order_independence')) {
        if(-not $names.ContainsKey($name)){throw "Missing synthetic check: $name"}
    }
    if($Result.metrics.rowCount -ne 3 -or $Result.metrics.dateCount -ne 2 -or $Result.metrics.status -cne 'METRICS_ONLY' -or
        $Result.guard.rowCount -ne 3 -or $Result.guard.dateCount -ne 3 -or
        $Result.guard.status -cne 'DECLARED_METADATA_CHECKS_PASS' -or @($Result.guard.issues).Count -ne 0){throw 'Unexpected fixture metrics/guard.'}
    foreach($contract in @($Result.fixtureContract,$Result.metrics.contract)){
        if($contract.horizonSessions -ne 2 -or $contract.unit -cne 'PERCENTAGE_POINTS' -or $contract.pricePolicy -cne 'SYNTHETIC_ONLY'){throw 'Synthetic contract mismatch.'}
    }
    $expected=@{mae=2.0;rmse=[math]::Sqrt(14.0/3);signedBias=2.0/3;directionAgreementPercent=100.0/3}
    $dateExpected=@{mae=2.25;rmse=[math]::Sqrt(5.75);signedBias=1.25;directionAgreementPercent=25.0}
    foreach($key in $expected.Keys){
        foreach($pair in @(@($Result.metrics.rowWeighted.$key,$expected[$key]),@($Result.metrics.equalDateWeighted.$key,$dateExpected[$key]))){
            if($null -eq $pair[0] -or $pair[0] -is [string] -or $pair[0] -is [bool]){throw "Invalid metric: $key"}
            $value=[double]$pair[0]
            if([double]::IsNaN($value) -or [double]::IsInfinity($value) -or [math]::Abs($value-$pair[1]) -gt 1e-10){throw "Metric mismatch: $key"}
        }
    }
}
