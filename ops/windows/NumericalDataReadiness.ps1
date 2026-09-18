# Pure audit assessment: no database/network/model calls.
Set-StrictMode -Version Latest
function Get-ReadinessField($Object,[string]$Name) {
    if ($null -eq $Object) {return $null}
    $p=$Object.PSObject.Properties[$Name];if ($null -ne $p) {return $p.Value};return $null
}
function Measure-NumericalDataReadiness($Audit,[guid]$ExpectedRunId) {
    $failures=[Collections.Generic.List[string]]::new()
    $counts=[ordered]@{}
    foreach ($name in @('instrumentCount','featureEligibleCount','fullyLabeledCount','rightCensoredCount','insufficientHistoryCount','staleCount','noEligibleDataCount','persistedItemCount','persistedLabelCount')) {
        $value=Get-ReadinessField $Audit $name
        if ($null -eq $value -or $value -is [bool] -or $value -is [string] -or [string]$value -notmatch '^\d+$') {$failures.Add('INVALID_COUNT_'+$name);$counts[$name]=$null}
        else {$counts[$name]=[long]$value}
    }
    $id=[guid]::Empty
    if (-not [guid]::TryParse([string](Get-ReadinessField $Audit 'datasetRunId'),[ref]$id) -or $id -ne $ExpectedRunId) {$failures.Add('DATASET_ID_MISMATCH')}
    if ((Get-ReadinessField $Audit 'datasetContractVersion') -ne 'PROTOTYPE_SWING_TRAINING_DATASET_V1') {$failures.Add('UNSUPPORTED_DATASET_CONTRACT')}
    if ((Get-ReadinessField $Audit 'sourceUniverseCode') -ne 'CURRENT_SNAPSHOT_PROTOTYPE') {$failures.Add('UNSUPPORTED_UNIVERSE_CONTRACT')}
    if ((Get-ReadinessField $Audit 'status') -ne 'REVIEW_REQUIRED') {$failures.Add('AUDIT_NOT_ACCEPTED')}
    if ([string](Get-ReadinessField $Audit 'datasetManifestHash') -notmatch '^[a-fA-F0-9]{64}$') {$failures.Add('INVALID_MANIFEST_HASH')}
    foreach ($field in @('pointInTimeSafe','futureLabelsSeparated','survivorshipRiskPresent','prototypeTrainingEligible')) {
        $value=Get-ReadinessField $Audit $field
        if ($value -isnot [bool] -or -not $value) {$failures.Add('EXPECTED_TRUE_'+$field)}
    }
    foreach ($field in @('databaseWritesPerformed','benchmarkTrainingEligible')) {
        $value=Get-ReadinessField $Audit $field
        if ($value -isnot [bool] -or $value) {$failures.Add('EXPECTED_FALSE_'+$field)}
    }
    foreach ($field in @('ollamaCallCount','signalsCreated','ordersCreated')) {
        $value=Get-ReadinessField $Audit $field
        if ($null -eq $value -or $value -is [string] -or $value -is [bool] -or $value -ne 0) {$failures.Add('EXPECTED_ZERO_'+$field)}
    }
    $serverFailures=Get-ReadinessField $Audit 'failedCheckpoints'
    if ($null -eq $Audit.PSObject.Properties['failedCheckpoints'] -or $null -eq $Audit.failedCheckpoints -or $Audit.failedCheckpoints -isnot [array]) {$failures.Add('MISSING_FAILURE_LIST')}
    if ($null -ne $serverFailures -and @($serverFailures).Count -gt 0) {$failures.Add('SERVER_CHECKPOINT_FAILURES')}
    $dates=[ordered]@{}
    foreach ($field in @('asOf','labelThrough')) {
        $value=[string](Get-ReadinessField $Audit $field);$date=[datetime]::MinValue
        if (-not [datetime]::TryParseExact($value,'yyyy-MM-dd',[Globalization.CultureInfo]::InvariantCulture,[Globalization.DateTimeStyles]::None,[ref]$date)) {$failures.Add('INVALID_DATE_'+$field)}
        $dates[$field]=$date
    }
    if ($dates.labelThrough -le $dates.asOf) {$failures.Add('INVALID_LABEL_WINDOW')}
    if (@($counts.Values | Where-Object {$null -eq $_}).Count -eq 0) {
        if ($counts.instrumentCount -le 0) {$failures.Add('EMPTY_UNIVERSE')}
        if ($counts.persistedItemCount -ne $counts.instrumentCount) {$failures.Add('ITEM_METADATA_MISMATCH')}
        if ($counts.fullyLabeledCount+$counts.rightCensoredCount -ne $counts.featureEligibleCount) {$failures.Add('ELIGIBILITY_COUNT_MISMATCH')}
        if ($counts.featureEligibleCount+$counts.insufficientHistoryCount+$counts.staleCount+$counts.noEligibleDataCount -ne $counts.instrumentCount) {$failures.Add('UNIVERSE_COUNT_MISMATCH')}
        if ($counts.persistedLabelCount -ne $counts.fullyLabeledCount*3) {$failures.Add('LABEL_METADATA_MISMATCH')}
    }
    $classifications=@(Get-ReadinessField $Audit 'classificationCounts')
    $expectedClasses=@{LABELED='fullyLabeledCount';RIGHT_CENSORED='rightCensoredCount';INSUFFICIENT_HISTORY='insufficientHistoryCount';STALE='staleCount';NO_ELIGIBLE_DATA='noEligibleDataCount'}
    foreach ($row in $classifications) {
        $class=[string](Get-ReadinessField $row 'classification')
        if (-not $expectedClasses.ContainsKey($class)) {$failures.Add('UNKNOWN_CLASSIFICATION')}
    }
    foreach ($key in $expectedClasses.Keys) {
        $rows=@($classifications | Where-Object {(Get-ReadinessField $_ 'classification') -eq $key})
        $actual=if($rows.Count -eq 1){Get-ReadinessField $rows[0] 'count'}else{0}
        if ($rows.Count -gt 1 -or $actual -is [string] -or $actual -is [bool] -or $null -eq $actual -or $actual -ne $counts[$expectedClasses[$key]]) {$failures.Add('CLASSIFICATION_COUNT_'+$key)}
    }
    $horizons=@(Get-ReadinessField $Audit 'horizonAudits')
    if ($horizons.Count -ne 3) {$failures.Add('HORIZON_COVERAGE')}
    foreach ($h in @(5,20,60)) {
        $rows=@($horizons | Where-Object {(Get-ReadinessField $_ 'horizonSessions') -eq $h})
        if ($rows.Count -ne 1) {$failures.Add('HORIZON_DUPLICATE_OR_MISSING_'+$h);continue}
        $count=Get-ReadinessField $rows[0] 'labelCount'
        if ($null -eq $count -or $count -is [string] -or $count -is [bool] -or $count -ne $counts.fullyLabeledCount) {$failures.Add('HORIZON_LABEL_COUNT_'+$h)}
    }
    $h20=@($horizons | Where-Object {(Get-ReadinessField $_ 'horizonSessions') -eq 20})
    $labelCount=if($h20.Count -eq 1){Get-ReadinessField $h20[0] 'labelCount'}else{$null}
    if ($null -eq $labelCount -or $labelCount -le 0) {$failures.Add('NO_20_SESSION_LABELS')}
    $featurePercent=$null;$labeledPercent=$null
    if ($null -ne $counts.instrumentCount -and $counts.instrumentCount -gt 0) {
        if ($null -ne $counts.featureEligibleCount) {$featurePercent=[math]::Round(100.0*$counts.featureEligibleCount/$counts.instrumentCount,2)}
        if ($null -ne $counts.fullyLabeledCount) {$labeledPercent=[math]::Round(100.0*$counts.fullyLabeledCount/$counts.instrumentCount,2)}
    }
    [pscustomobject]@{
        status=if($failures.Count){'AUDIT_BLOCKED'}else{'PROTOTYPE_AUDIT_CONSISTENT_NOT_TRAINING_READY'}
        failures=$failures.ToArray();counts=$counts;featureEligiblePercent=$featurePercent;fullyLabeledPercent=$labeledPercent
        reported20SessionLabelCount=$labelCount;observedDecisionDateCount=1;trainingAuthorized=$false
        blockers=@('SINGLE_DATE_AUDIT_NOT_MULTI_DATE_EXPORT','CURRENT_MEMBERSHIP_SURVIVORSHIP_BIAS','ROW_LEVEL_POINT_IN_TIME_AND_EXECUTABLE_ENTRY_UNVERIFIED','CHRONOLOGICAL_SPLITS_AND_LABEL_OVERLAP_PURGE_NOT_ESTABLISHED','HISTORY_GAPS_CORPORATE_ACTIONS_AND_SOURCE_RIGHTS_UNVERIFIED')
        unmeasured=@('15-year coverage','Per-symbol missing sessions','Historical membership completeness','Fundamental/news availability timestamps','Out-of-sample predictive accuracy','Fitted or calibrated numerical model')
        nextStep='Freeze point-in-time feature/label and temporal split contract; then build a separate immutable multi-date export. Do not feed this audit or its future-outcome examples to a predictor.'
        limitations='One explicit existing run only. Percentages describe this run, not the Nifty 500 or project completion. Java pointInTimeSafe is a stored flag, not independent leakage proof. Classification/horizon aggregates are checked; item count metadata, constraints and full raw history are not independently audited here.'
    }
}
