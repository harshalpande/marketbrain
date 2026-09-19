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

function Assert-BaselineNumber($Value,[double]$Expected,[string]$Name) {
    if($null -eq $Value -or $Value -is [string] -or $Value -is [bool] -or
        [double]::IsNaN([double]$Value) -or [double]::IsInfinity([double]$Value) -or
        [math]::Abs([double]$Value-$Expected) -gt 1e-9){throw "Invalid baseline value: $Name"}
}

function Assert-NumericalBaselineBundle($Result) {
    if($Result.version -cne 'SYNTHETIC_NUMERICAL_BASELINES_V1' -or $Result.status -cne 'SYNTHETIC_CHECKS_PASSED'){throw 'Wrong baseline bundle contract/status.'}
    foreach($key in @('trainingAuthorized','realMarketTrainingAuthorized','automaticPromotionEnabled','databaseWritesPerformed')){
        if($Result.$key -isnot [bool] -or $Result.$key){throw "Unsafe baseline flag: $key"}
    }
    foreach($key in @('syntheticOnly','syntheticTrainingPerformed')){
        if($Result.$key -isnot [bool] -or -not $Result.$key){throw "Missing synthetic flag: $key"}
    }
    foreach($key in @('providerCallCount','modelCallCount','ordersCreated','failedCheckCount')){
        Assert-BaselineNumber $Result.$key 0 $key
    }
    Assert-EvaluationSmoke $Result.evaluationRegression
    $expectedNames=@('linear_signal_beats_references','constant_target_retains_tie','reversal_exposes_underperformance',
        'shuffle_training_same_artifact','heldout_targets_cannot_change_fit_or_predictions','heldout_rows_rejected_by_fit',
        'unmatured_target_rejected','duplicate_training_rejected','optional_missing_uses_training_mean',
        'critical_missing_rejected','ranking_average_ties_and_top_ties','constant_ranking_unavailable','parameter_artifact_copy_prediction_parity')
    Assert-BaselineNumber $Result.checkCount 13 'checkCount'
    if(@($Result.checks).Count -ne 13){throw 'Incomplete baseline checks.'}
    $seen=@{}
    foreach($check in $Result.checks){
        if($expectedNames -cnotcontains $check.name -or $seen.ContainsKey($check.name) -or
            $check.passed -isnot [bool] -or -not $check.passed -or $check.failure -or $check.fixtureSha256 -cnotmatch '^[a-f0-9]{64}$'){
            throw 'Invalid baseline check.'
        }
        Assert-BaselineNumber $check.elapsedMillis ([double]$check.elapsedMillis) 'check timing'
        if($check.elapsedMillis -lt 0){throw 'Negative timing.'}
        $seen[$check.name]=$true
    }
    Assert-BaselineNumber $Result.configuration.ridgePenalty 0.01 'ridge penalty'
    Assert-BaselineNumber $Result.configuration.horizonSessions 20 'horizon'
    Assert-BaselineNumber $Result.configuration.scenarioCount 3 'scenario count'
    Assert-BaselineNumber $Result.configuration.tieTolerance 1e-9 'tie tolerance'
    if($Result.configuration.primaryMetric -cne 'EQUAL_DATE_MAE' -or @($Result.scenarios).Count -ne 3){throw 'Wrong comparison contract.'}
    $seen=@{}
    foreach($scenario in $Result.scenarios){
        if(@('LINEAR_SIGNAL','CONSTANT_TARGET','REGIME_REVERSAL') -cnotcontains $scenario.name -or $seen.ContainsKey($scenario.name)) {throw 'Unexpected/duplicate scenario.'}
        $seen[$scenario.name]=$true
        if($scenario.fixtureSha256 -cnotmatch '^[a-f0-9]{64}$' -or $scenario.modelSha256 -cnotmatch '^[a-f0-9]{64}$' -or
            $scenario.model.trainingSha256 -cnotmatch '^[a-f0-9]{64}$'){throw 'Missing artifact fingerprint.'}
        if($scenario.guard.status -cne 'DECLARED_METADATA_CHECKS_PASS' -or @($scenario.guard.issues).Count -ne 0 -or
            $scenario.guard.rowCount -ne 210){throw 'Scenario guard failed.'}
        Assert-BaselineNumber $scenario.model.trainingRows 120 'training count'
        if($scenario.model.version -cne 'SYNTHETIC_RIDGE_V1' -or ($scenario.model.features -join ',') -cne 'return5,volumeRatio20'){throw 'Invalid fitted model.'}
        Assert-BaselineNumber $scenario.model.penalty 0.01 'model penalty'
        Assert-BaselineNumber $scenario.model.intercept ([double]$scenario.model.intercept) 'intercept'
        foreach($field in @('means','scales','weights')){
            if(@($scenario.model.$field).Count -ne 2){throw 'Model dimensions changed.'}
            foreach($v in $scenario.model.$field){Assert-BaselineNumber $v ([double]$v) $field}
        }
        if(@($scenario.model.scales | Where-Object {$_ -le 0}).Count){throw 'Invalid model scale.'}
        foreach($partition in @($scenario.validation,$scenario.test)){
            if(@($partition.comparisons).Count -ne 3){throw 'Incomplete comparison.'}
            $ids=@{};$errors=@{};$referenceKeys=$null
            foreach($comparison in $partition.comparisons){
                $id=[string]$comparison.predictor
                if(@('ZERO','TRAIN_MEAN','RIDGE') -cnotcontains $id -or $ids.ContainsKey($id)){throw 'Duplicate/unknown comparator.'}
                $ids[$id]=$true
                $rows=@($comparison.predictions)
                if($rows.Count -ne 45){throw 'Incomplete held-out predictions.'}
                $keys=@{};$dates=@{}
                $ae=0.0;$se=0.0;$bias=0.0;$direction=0.0
                foreach($row in $rows){
                    $key=([string]$row.decisionDate)+'|'+$row.instrument
                    if($keys.ContainsKey($key) -or $row.predictionId -cne $id -or $row.contract.horizonSessions -ne 20 -or
                        $row.contract.unit -cne 'PERCENTAGE_POINTS' -or $row.contract.pricePolicy -cne 'SYNTHETIC_ONLY'){throw 'Invalid held-out row identity/contract.'}
                    Assert-BaselineNumber $row.predicted ([double]$row.predicted) 'prediction'
                    Assert-BaselineNumber $row.observed ([double]$row.observed) 'target'
                    $keys[$key]=$row.observed
                    if($id -eq 'ZERO'){Assert-BaselineNumber $row.predicted 0 'zero baseline'}
                    if($id -eq 'TRAIN_MEAN'){Assert-BaselineNumber $row.predicted $scenario.model.intercept 'mean baseline'}
                    $e=[double]$row.predicted-[double]$row.observed
                    $ae+=[math]::Abs($e);$se+=$e*$e;$bias+=$e
                    if([math]::Sign([double]$row.predicted) -eq [math]::Sign([double]$row.observed)){$direction++}
                    $date=[string]$row.decisionDate
                    if(-not $dates.ContainsKey($date)){$dates[$date]=0};$dates[$date]++
                }
                # The fixed bundle has exactly three stocks each date, so equal-date and row weighting coincide.
                if($dates.Count -ne 15 -or @($dates.Values | Where-Object {$_ -ne 3}).Count){throw 'Unexpected date grouping.'}
                if($null -eq $referenceKeys){$referenceKeys=$keys}else{
                    foreach($key in $keys.Keys){if(-not $referenceKeys.ContainsKey($key) -or $referenceKeys[$key] -ne $keys[$key]){throw 'Comparators use different held-out targets.'}}
                }
                $expected=@{mae=$ae/45;rmse=[math]::Sqrt($se/45);signedBias=$bias/45;directionAgreementPercent=100*$direction/45}
                if($comparison.errors.rowCount -ne 45 -or $comparison.errors.dateCount -ne 15 -or $comparison.errors.status -cne 'METRICS_ONLY'){throw 'Wrong metric population.'}
                foreach($weight in @('rowWeighted','equalDateWeighted')){foreach($metric in $expected.Keys){Assert-BaselineNumber $comparison.errors.$weight.$metric $expected[$metric] $metric}}
                $errors[$id]=$expected.mae
                if($comparison.ranking.dateCount -ne 15 -or $comparison.ranking.correlationDateCount+$comparison.ranking.unavailableCorrelationDates -ne 15){throw 'Wrong ranking population.'}
            }
            $best=($errors.Values | Measure-Object -Minimum).Minimum
            $winners=@(@('ZERO','TRAIN_MEAN','RIDGE') | Where-Object {[math]::Abs($errors[$_]-$best) -le 1e-9})
            if(($winners -join ',') -cne ($partition.lowestMaePredictors -join ',')){throw 'Incorrect winner/tie reporting.'}
            switch($scenario.name){
                LINEAR_SIGNAL{if($errors.RIDGE -ge $errors.ZERO -or $errors.RIDGE -ge $errors.TRAIN_MEAN){throw 'Signal fixture not learned.'}}
                CONSTANT_TARGET{if(($winners -join ',') -cne 'TRAIN_MEAN,RIDGE'){throw 'Constant-target tie lost.'}}
                REGIME_REVERSAL{if($errors.RIDGE -le $errors.ZERO){throw 'Reversal underperformance hidden.'}}
            }
        }
    }
}
