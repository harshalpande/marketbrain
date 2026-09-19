# Definitions only. Independent report arithmetic; no service or data access.
Set-StrictMode -Version Latest
. (Join-Path $PSScriptRoot 'NumericalEvaluationEngineering.ps1')

function Get-TenFeatureTextHash([string]$Text) {
    $sha=[Security.Cryptography.SHA256]::Create()
    try { ([BitConverter]::ToString($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($Text)))).Replace('-','').ToLowerInvariant() }
    finally { $sha.Dispose() }
}

function ConvertTo-TenFeatureUtc($Value) {
    if($Value -is [DateTimeOffset]){return $Value.ToUniversalTime()}
    if($Value -is [DateTime]){
        if($Value.Kind -eq [DateTimeKind]::Unspecified){throw 'Timezone-free typed timestamp.'}
        return ([DateTimeOffset]$Value).ToUniversalTime()
    }
    if($Value -isnot [string] -or $Value -cnotmatch '^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(\.\d{1,7})?(Z|[+-]\d{2}:\d{2})$'){throw 'Explicit timestamp timezone required.'}
    [DateTimeOffset]::Parse($Value,[Globalization.CultureInfo]::InvariantCulture,[Globalization.DateTimeStyles]::None).ToUniversalTime()
}

function Assert-TenFeatureBundle($Result) {
    if($Result.version -cne 'NUMERICAL_TEN_FEATURE_ENGINEERING_V1' -or $Result.status -cne 'SYNTHETIC_CHECKS_PASSED'){throw 'Wrong ten-feature suite/status.'}
    foreach($key in @('realMarketTrainingAuthorized','automaticPromotionEnabled','actionExecutionEnabled','databaseWritesPerformed')) {
        if($Result.$key -isnot [bool] -or $Result.$key){throw "Unsafe flag: $key"}
    }
    if($Result.syntheticOnly -isnot [bool] -or -not $Result.syntheticOnly){throw 'Non-synthetic report.'}
    foreach($key in @('providerCallCount','llmCallCount','ordersCreated','signalsCreated','failedCheckCount')) { Assert-BaselineNumber $Result.$key 0 $key }
    if($Result.readiness.status -cne 'MARKET_FIT_BLOCKED' -or $Result.readiness.trainingEligibleMarketRows -ne 0 -or
       ($Result.readiness.blockers -join ',') -cne 'SOURCE_PRICE_ACTION_EVIDENCE,HISTORICAL_AVAILABILITY,SOURCE_RIGHTS,FINAL_EVALUATION_CRITERIA,SCOPED_MARKET_FIT_APPROVAL'){throw 'Missing market-fit gates.'}
    $names=@('fold_LINEAR','fold_FLAT','fold_REVERSAL','heldout_mutation_isolation','row_order_invariance','date_weights_sum_one',
        'constant_feature','artifact_roundtrip','artifact_corruption','artifact_identity','duplicate_rows',
        'UNKNOWN_AVAILABILITY','FUTURE_AVAILABILITY','FEATURE_SCHEMA_MISMATCH','MISSING_OR_NON_FINITE_FEATURE',
        'UNCERTIFIED_OR_MARKET_DATA_DISABLED','UNKNOWN_LABEL_AVAILABILITY','LABEL_POLICY_MISMATCH','label_purge_TRAIN',
        'label_purge_VALIDATION','inspected_final_test','insufficient_gap','missing_inference_target_not_required',
        'non_finite_solver','zero_baseline_unavailable','abstention_coverage','negative_result_retained',
        'independent_metric_arithmetic','collinear_hand_solution','paired_date_blocks_reproducible',
        'unpaired_uncertainty_rejected','constant_block_oracle')
    if($Result.checkCount -ne $names.Count -or @($Result.checks).Count -ne $names.Count){throw 'Incomplete check suite.'}
    $seen=@{}
    foreach($c in $Result.checks){
        if($names -cnotcontains $c.name -or $seen.ContainsKey($c.name) -or $c.passed -isnot [bool] -or -not $c.passed -or $c.failure){throw 'Failed/missing/duplicate check.'}
        $seen[$c.name]=$true
        Assert-BaselineNumber $c.elapsedMillis ([double]$c.elapsedMillis) 'check timing'
        if($c.elapsedMillis -lt 0){throw 'Negative check timing.'}
    }
    $features=@('dailyReturnPercent','closeToSma20Percent','closeToSma50Percent','closeToSma200Percent','ema12ToEma26Percent',
        'rsi14','atr14ToClosePercent','annualizedVolatility20Percent','volumeRatio20','rangePosition252Percent')
    if(($Result.configuration.featureOrder -join ',') -cne ($features -join ',') -or $Result.configuration.horizonSessions -ne 20 -or
        ($Result.configuration.costsBps -join ',') -cne '0,25,50,100'){throw 'Wrong engineering configuration.'}
    Assert-BaselineNumber $Result.configuration.alpha 0.01 'alpha'
    Assert-BaselineNumber $Result.configuration.parityTolerance 1e-9 'tolerance'
    if(@($Result.folds).Count -ne 3 -or ($Result.folds.name -join ',') -cne 'LINEAR,FLAT,REVERSAL'){throw 'Missing scenario/loss evidence.'}
    if(@($Result.syntheticUncertaintyChecks).Count -ne 3){throw 'Missing synthetic uncertainty checks.'}
    foreach($u in $Result.syntheticUncertaintyChecks){
        if($u.scope -cne 'SYNTHETIC_PARAMETERS_NOT_MARKET_ACCEPTANCE' -or $u.blockLength -ne 2 -or $u.resamples -ne 200 -or $u.seed -ne 42 -or
            $u.dates -ne 10 -or $u.lower -gt $u.upper -or $u.sampleMeansHash -cnotmatch '^[a-f0-9]{64}$'){throw 'Invalid uncertainty fixture.'}
        Assert-BaselineNumber $u.confidenceLevel 0.95 'synthetic confidence setting'
    }
    foreach($fold in $Result.folds) {
        $model=$fold.model
        if($model.version -cne $Result.version -or ($model.featureOrder -join ',') -cne ($features -join ',') -or
            ($model.featureUnits -join ',') -cne 'PERCENT,PERCENT,PERCENT,PERCENT,PERCENT,INDEX_0_100,PERCENT,PERCENT,RATIO,PERCENT_0_100' -or
            @($model.means).Count -ne 10 -or @($model.scales).Count -ne 10 -or @($model.coefficients).Count -ne 10 -or
            @($model.constants).Count -ne 10 -or $model.metadata.dataScope -cne 'SYNTHETIC_ONLY' -or
            $model.metadata.contractHash -cne '0ca5efab05b6fde03c16adb4181e31d63893e80fee8b71a63087eb35385a69d6'){throw 'Invalid model dimensions or contract.'}
        Assert-BaselineNumber $model.alpha 0.01 'model alpha'
        if((Get-TenFeatureTextHash $fold.artifact) -cne $fold.artifactHash -or $fold.artifact.Length -ge 20000 -or
            $fold.artifact.Substring(0,64) -cne (Get-TenFeatureTextHash $fold.artifact.Substring(65))){throw 'Artifact corruption.'}
        for($j=0;$j -lt 10;$j++) {
            foreach($value in @($model.means[$j],$model.scales[$j],$model.coefficients[$j])){Assert-BaselineNumber $value ([double]$value) 'model numeric'}
            if($model.scales[$j] -le 0){throw 'Invalid scale.'}
            if($model.constants[$j] -isnot [bool]){throw 'Invalid constant flag.'}
            if($model.constants[$j] -and ($model.scales[$j] -ne 1 -or $model.coefficients[$j] -ne 0)){throw 'Invalid constant-feature parameters.'}
        }
        foreach($part in @($fold.validation,$fold.test)) {
            if($part.inputRows -le 0 -or $part.evaluatedRows -ne $part.inputRows -or @($part.exclusions).Count -ne 0){throw 'Unexpected fixture coverage.'}
            Assert-BaselineNumber $part.coveragePercent 100 'coverage'
            if(($part.comparisons.predictor -join ',') -cne 'ZERO_RETURN,WEIGHTED_TRAIN_MEAN,TEN_FEATURE_WEIGHTED_RIDGE'){throw 'Missing comparators.'}
            $reference=@{};$zeroMae=$null
            foreach($comparison in $part.comparisons) {
                $groups=@{};$keys=@{}
                if(@($comparison.predictions).Count -ne $part.evaluatedRows){throw 'Missing prediction.'}
                foreach($r in $comparison.predictions) {
                    # Typed DateTime/string independent: normalize instant, not local display text.
                    $at=ConvertTo-TenFeatureUtc $r.decisionAt
                    if($at.TimeOfDay -ne [TimeSpan]::FromMinutes(630)){throw 'Wrong fixture decision cutoff.'}
                    $day=$at.ToString('yyyy-MM-dd');$key=$r.instrument+'@'+$at.ToString('o')
                    if($keys.ContainsKey($key)){throw 'Duplicate prediction.'};$keys[$key]=$true
                    Assert-BaselineNumber $r.observed ([double]$r.observed) 'observed'
                    Assert-BaselineNumber $r.predicted ([double]$r.predicted) 'predicted'
                    # Reconstruct the fixed input, independent of Java's fit/serialization path.
                    $dayIndex=($at.Date-([datetime]'2020-01-01')).Days
                    if($r.instrument -cnotmatch '^SYNTHETIC_([0-2])$'){throw 'Unexpected fixture instrument.'}
                    $stock=[int]$Matches[1];$x=@()
                    for($j=0;$j -lt 10;$j++) {
                        $v=switch($j){
                            9 {50.0} 5 {50+10*[math]::Sin($dayIndex+$stock)}
                            6 {2+[math]::Abs([math]::Sin($dayIndex*0.7+$stock))}
                            7 {10+[math]::Abs([math]::Cos($dayIndex+$stock))}
                            8 {1+0.2*[math]::Sin($dayIndex+$stock)}
                            default {[math]::Sin($dayIndex*($j+1)*0.37+$stock*1.1)*($j+1)}
                        };$x+=@([double]$v)
                    }
                    $target=1+2*$x[0]-0.5*$x[1]
                    if($fold.name -ceq 'FLAT'){$target=0.0}
                    # Windows are explicit fixture session indexes, not exchange-calendar guesses.
                    $first=$fold.manifest.windows.TEST.first
                    $testFirst=if($first -is [datetime]){$first.Date}else{[datetime]::ParseExact([string]$first,'yyyy-MM-dd',[Globalization.CultureInfo]::InvariantCulture)}
                    if($fold.name -ceq 'REVERSAL' -and $at.Date -ge $testFirst.Date){$target=-$target}
                    Assert-BaselineNumber $r.observed $target 'fixture target'
                    if($comparison.predictor -ceq 'TEN_FEATURE_WEIGHTED_RIDGE') {
                        $pred=[double]$model.intercept
                        for($j=0;$j -lt 10;$j++){$pred+=(($x[$j]-$model.means[$j])/$model.scales[$j])*$model.coefficients[$j]}
                        Assert-BaselineNumber $r.predicted $pred 'independent ridge prediction'
                    }
                    if($comparison.predictor -ceq 'ZERO_RETURN'){$reference[$key]=[double]$r.observed;Assert-BaselineNumber $r.predicted 0 'zero prediction'}else{
                        if(-not $reference.ContainsKey($key)){throw 'Mismatched comparison rows.'}
                        Assert-BaselineNumber $r.observed $reference[$key] 'same target'
                    }
                    if($comparison.predictor -ceq 'WEIGHTED_TRAIN_MEAN'){Assert-BaselineNumber $r.predicted $model.trainingMean 'mean prediction'}
                    if(-not $groups.ContainsKey($day)){$groups[$day]=@()};$groups[$day]+=@($r)
                }
                $ae=0.0;$sq=0.0;$bias=0.0;$direction=0.0
                foreach($group in $groups.Values){foreach($r in $group){
                    $w=1.0/($groups.Count*$group.Count);$e=[double]$r.predicted-[double]$r.observed
                    $ae+=$w*[math]::Abs($e);$sq+=$w*$e*$e;$bias+=$w*$e
                    if([math]::Sign([double]$r.predicted) -eq [math]::Sign([double]$r.observed)){$direction+=$w}
                }}
                $expected=@{mae=$ae;rmse=[math]::Sqrt($sq);signedBias=$bias;directionAgreementPercent=100*$direction}
                if($comparison.metrics.rows -ne $part.evaluatedRows -or $comparison.metrics.dates -ne $groups.Count){throw 'Wrong metric population.'}
                foreach($key in $expected.Keys){Assert-BaselineNumber $comparison.metrics.$key $expected[$key] $key}
                if($null -eq $zeroMae){$zeroMae=$ae}
                if($zeroMae -eq 0){if($null -ne $comparison.maeImprovementVsZeroPercent){throw 'Invented zero-denominator improvement.'}}
                else{Assert-BaselineNumber $comparison.maeImprovementVsZeroPercent (100*($zeroMae-$ae)/$zeroMae) 'improvement'}
                if(($comparison.hypotheticalCosts.roundTripBps -join ',') -cne '0,25,50,100'){throw 'Missing cost scenario.'}
                foreach($cost in $comparison.hypotheticalCosts){
                    $selected=@($comparison.predictions | Where-Object {$_.predicted -gt $cost.roundTripBps/100.0})
                    if($cost.selectedCount -ne $selected.Count){throw 'Cost selection mismatch.'}
                    if($selected.Count -eq 0){if($null -ne $cost.meanSelectedNetPercent){throw 'Invented net result.'}}
                    else{$net=0.0;foreach($r in $selected){$net+=$r.observed-$cost.roundTripBps/100.0};Assert-BaselineNumber $cost.meanSelectedNetPercent ($net/$selected.Count) 'net result'}
                }
            }
        }
        if($fold.name -ceq 'REVERSAL' -and $fold.test.comparisons[2].maeImprovementVsZeroPercent -ge 0){throw 'Reversal loss hidden.'}
    }
}
