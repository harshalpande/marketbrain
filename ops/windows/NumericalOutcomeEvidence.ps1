# Pure outcome-only review; feature inputs are never extended with future bars.
Set-StrictMode -Version Latest
. (Join-Path $PSScriptRoot 'NumericalReadinessBundle.ps1')
function Get-NumericalOutcomeSessions($Calendar,$Extension){
    $existing=@(Get-NumericalCalendarSessions $Calendar)
    if($Extension.version -ne 'NSE_CM_OUTCOME_CALENDAR_20260606_20260717_V1' -or $Extension.exchange -ne 'NSE' -or $Extension.segment -ne 'CM' -or
       $Extension.timezone -ne 'Asia/Kolkata' -or $Extension.coverageFrom -ne '2026-06-06' -or $Extension.coverageThrough -ne '2026-07-17' -or
       $Extension.rule -ne 'MONDAY_FRIDAY_EXCEPT_CLOSURES' -or (@($Extension.closures) -join ',') -ne '2026-06-26' -or
       $Extension.source -ne 'https://nsearchives.nseindia.com/content/circulars/CMTR71775.pdf'){throw 'Unreviewed outcome calendar.'}
    $existing
    $from=ConvertTo-NumericalCalendarDate $Extension.coverageFrom;$through=ConvertTo-NumericalCalendarDate $Extension.coverageThrough
    for($d=$from;$d -le $through;$d=$d.AddDays(1)){
        $key=$d.ToString('yyyy-MM-dd')
        if([int]$d.DayOfWeek -ge 1 -and [int]$d.DayOfWeek -le 5 -and $key -notin $Extension.closures){$key}
    }
}
function Get-NumericalOutcomeReview($Features,$Outcome,$Calendar,$Extension){
    $featureReview=Get-NumericalFeatureCalendarReview $Features $Calendar
    $p=$Features.snapshot.payload;$items=@($p.instruments);$incoming=@($Outcome.instruments)
    $from=($p.instruments.rows.featureFrom | Sort-Object | Select-Object -First 1)
    if($p.asOf -ne '2026-06-05' -or $Outcome.version -ne 'NUMERICAL_OUTCOME_EVIDENCE_V1' -or $Outcome.status -ne 'OUTCOME_EVIDENCE_REVIEW_REQUIRED' -or
       $Outcome.datasetRunId -ne $p.datasetRunId -or $Outcome.datasetManifestHash -ne $p.datasetManifestHash -or $Outcome.asOf -ne $p.asOf -or
       $Outcome.outcomeFrom -ne $Extension.coverageFrom -or $Outcome.outcomeThrough -ne $Extension.coverageThrough -or
       $Outcome.offset -ne $p.offset -or $Outcome.limit -ne $p.limit -or $items.Count -ne $incoming.Count){throw 'Outcome scope/manifest mismatch.'}
    $price=$Outcome.priceEvidence
    if($price.version -ne 'NUMERICAL_PRICE_EVIDENCE_V1' -or $price.status -ne 'PRICE_POLICY_REVIEW_REQUIRED' -or
       $price.datasetRunId -ne $p.datasetRunId -or $price.datasetManifestHash -ne $p.datasetManifestHash -or
       $price.fromDate -ne $from -or $price.throughDate -ne $Extension.coverageThrough -or $price.offset -ne $p.offset -or $price.limit -ne $p.limit -or
       @($price.instruments).Count -ne $items.Count){throw 'Extended price scope mismatch.'}
    foreach($object in @($Outcome,$price)){
        foreach($flag in @('trainingAuthorized','databaseWritesPerformed')){if($object.$flag -isnot [bool] -or $object.$flag){throw 'Unsafe outcome/price flag.'}}
        foreach($counter in @('modelCallCount','providerCallCount','ordersCreated')){if(($object.$counter -isnot [int] -and $object.$counter -isnot [long]) -or $object.$counter -ne 0){throw 'Unsafe outcome/price counter.'}}
        if($object.partial -isnot [bool]){throw 'Unknown partial state.'}
    }
    $sessions=@(Get-NumericalOutcomeSessions $Calendar $Extension)
    $rows=[Collections.Generic.List[object]]::new();$partial=$price.partial
    for($i=0;$i -lt $items.Count;$i++){
        $item=$items[$i];$new=$incoming[$i];$priceItem=$price.instruments[$i]
        if($new.instrumentId -ne $item.instrumentId -or $new.symbol -ne $item.symbol -or $priceItem.instrumentId -ne $item.instrumentId -or $priceItem.symbol -ne $item.symbol){throw 'Outcome instrument drift.'}
        $bars=@($new.canonicalBars)
        if(($new.rawRowCount -isnot [int] -and $new.rawRowCount -isnot [long]) -or $new.rawRowCount -lt $bars.Count -or $new.rawRowCount -gt 201 -or
           $new.truncated -isnot [bool] -or $new.truncated -ne ($new.rawRowCount -gt 200)){throw 'Invalid outcome row cap.'}
        $partial=$partial -or $new.truncated
        $ids=[Collections.Generic.HashSet[string]]::new();foreach($bar in $item.canonicalBars){[void]$ids.Add([string]$bar.candleId)}
        $prior=''
        foreach($bar in $bars){
            [void](ConvertTo-NumericalCalendarDate $bar.date)
            if([string]$bar.candleId -notmatch '^[1-9][0-9]*$' -or -not $ids.Add([string]$bar.candleId) -or $bar.date -le $prior -or
               $bar.date -lt $Extension.coverageFrom -or $bar.date -gt $Extension.coverageThrough -or $bar.source -notin @('UPSTOX','NSE_BHAVCOPY') -or $bar.excluded -isnot [bool]){throw 'Invalid/out-of-scope outcome bar.'}
            if($bar.date -notin $sessions){throw 'Outcome bar on an unreviewed trading session.'}
            $prior=[string]$bar.date
        }
        foreach($row in $item.rows){
            # Union is used ONLY for outcome paths, never to calculate any feature.
            $label=Get-NumericalLabelPreflight $row.decisionDate $sessions (@($item.canonicalBars)+$bars)
            $featureRow=@($featureReview.rows | Where-Object {$_.instrumentId -eq $item.instrumentId -and $_.decisionDate -eq $row.decisionDate})[0]
            if($new.truncated -or $Features.snapshot.partial -or $item.truncated -or $featureRow.calendarStatus -ne 'MATCHES_REVIEWED_CALENDAR'){
                $label.status='SOURCE_OR_FEATURE_EVIDENCE_BLOCKED';$label.indicativeGrossPercent=$null;$label.costSensitivity=@();$label.sourceCandleIds=@()
            }
            $rows.Add([pscustomobject]@{instrumentId=$item.instrumentId;symbol=$item.symbol;decisionDate=$row.decisionDate;labelPreflight=$label})
        }
    }
    if($Outcome.partial -ne $partial){throw 'Overall outcome partial mismatch.'}
    $splitRows=@(foreach($row in $rows){[pscustomobject]@{instrumentId=$row.instrumentId;decisionDate=$row.decisionDate;exitDate=$row.labelPreflight.exitDate}})
    [pscustomobject]@{
        status='OUTCOME_PREFLIGHT_COMPLETE_TRAINING_BLOCKED';featureCalendarReview=$featureReview;rows=$rows.ToArray()
        splitPreflight=(Get-NumericalSplitPreflight $splitRows $p.decisionDates[1] $p.decisionDates[2])
        summary=[pscustomobject]@{candidateRowCount=$rows.Count;arithmeticOnlyCount=@($rows | Where-Object {$_.labelPreflight.status -eq 'STORED_PRICE_ARITHMETIC_ONLY'}).Count;blockedOutcomeCount=@($rows | Where-Object {$_.labelPreflight.status -ne 'STORED_PRICE_ARITHMETIC_ONLY'}).Count;partial=$partial;certifiedLabelCount=0;trainingAuthorized=$false}
        trainingAuthorized=$false;remainingGates=@('PRICE_ACTION_COVERAGE_AND_ADJUSTMENT_PROVENANCE','EXECUTABLE_PRICE_COST_AND_RESEARCH_POLICY','MULTI_DATE_LABELLED_EXPORT_AND_FROZEN_SPLITS')
        limitations='Appended bars are for diagnostic outcomes only. Original feature report is unchanged. Complete arithmetic paths are not executable labels or verified corporate-action returns. Current source/exclusions and mixed snapshot vintages; no as-known replay or source-price stability guarantee. Price evidence remains unverified even if no events returned. Existing fixture split boundaries retained, not moved to manufacture a pass. No actual labels or model fitting.'
    }
}
