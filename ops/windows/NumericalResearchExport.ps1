# Saved-evidence request construction. No network, database, or model work here.
Set-StrictMode -Version Latest
. (Join-Path $PSScriptRoot 'NumericalOutcomeEvidence.ps1')
function New-NumericalResearchExportRequest($FeatureInput,$OutcomeInput,$Calendar,$Extension) {
    $f=$FeatureInput.data;$o=$OutcomeInput.data
    if($o.version -ne 'NUMERICAL_OUTCOME_COLLECTION_V1' -or $o.inputSha256 -ne $FeatureInput.sha256){throw 'Outcome report is not bound to this feature file.'}
    $review=Get-NumericalOutcomeReview $f $o.outcome $Calendar $Extension
    if($review.summary.partial -or $review.summary.blockedOutcomeCount -ne 0 -or $review.featureCalendarReview.blockedRowCount -ne 0){throw 'Saved pilot evidence incomplete; do not export.'}
    $p=$f.snapshot.payload
    $items=@(for($i=0;$i -lt @($p.instruments).Count;$i++){
        $old=$p.instruments[$i];$future=$o.outcome.instruments[$i]
        [pscustomobject]@{instrumentId=$old.instrumentId;symbol=$old.symbol;bars=@($old.canonicalBars)+@($future.canonicalBars)}
    })
    [pscustomobject]@{datasetRunId=$p.datasetRunId;datasetManifestHash=$p.datasetManifestHash;featureEvidenceSha256=$FeatureInput.sha256
        outcomeEvidenceSha256=$OutcomeInput.sha256;sessions=@(Get-NumericalOutcomeSessions $Calendar $Extension);instruments=$items}
}
function Assert-NumericalResearchExportResult($Request,$Result,[switch]$Expanded) {
    $first=if($Expanded){'2025-10-27'}else{'2026-04-10'}
    $version=if($Expanded){'NUMERICAL_EXPANDED_RESEARCH_V1'}else{'NUMERICAL_MULTI_DATE_RESEARCH_V1'}
    $calendarHash=if($Expanded){'edc44a9eeee945a4362756c71d5d07c83e0c50a207706f9fb32f267733a60748'}else{'ea8cd016a1b03fab1d97b0cdecbdae4ff181b1b22f4a10a21f6ff6f11ca9c086'}
    $dates=@($Request.sessions | Where-Object {$_ -ge $first -and $_ -le '2026-06-05'})
    $expected=$dates.Count*@($Request.instruments).Count
    if($Result.version -ne $version -or $Result.status -ne 'RESEARCH_EXPORT_TRAINING_BLOCKED' -or
       $Result.datasetRunId -ne $Request.datasetRunId -or $Result.datasetManifestHash -ne $Request.datasetManifestHash -or
       $Result.featureEvidenceSha256 -ne $Request.featureEvidenceSha256 -or $Result.outcomeEvidenceSha256 -ne $Request.outcomeEvidenceSha256 -or
       $Result.calendarSessionSha256 -ne $calendarHash -or
       $Result.decisionDateCount -ne $dates.Count -or $Result.candidateRowCount -ne $expected -or @($Result.rows).Count -ne $expected){throw 'Export response identity/count mismatch.'}
    foreach($flag in @('trainingAuthorized','databaseWritesPerformed')){if($Result.$flag -isnot [bool] -or $Result.$flag){throw 'Unsafe export flag.'}}
    foreach($field in @('certifiedLabelCount','databaseQueryCount','providerCallCount','modelCallCount','ordersCreated')){
        if(($Result.$field -isnot [int] -and $Result.$field -isnot [long]) -or $Result.$field -ne 0){throw 'Unsafe export counter.'}
    }
    $seen=[Collections.Generic.HashSet[string]]::new();$complete=0
    foreach($row in $Result.rows){
        $item=@($Request.instruments | Where-Object {$_.instrumentId -eq $row.instrumentId -and $_.symbol -eq $row.symbol})
        if($item.Count -ne 1 -or $row.decisionDate -notin $dates -or -not $seen.Add("$($row.instrumentId)|$($row.decisionDate)")){throw 'Duplicate or foreign export row.'}
        # Independently recompute every outcome from the exact captured request; no new acquisition.
        $label=Get-NumericalLabelPreflight $row.decisionDate $Request.sessions $item[0].bars
        if($row.outcome.status -ne $label.status -or $row.outcome.entryDate -ne $label.entryDate -or $row.outcome.exitDate -ne $label.exitDate -or
           $row.outcome.problemDate -ne $label.problemDate -or $row.outcome.indicativeGrossPercent -ne $label.indicativeGrossPercent -or
           (@($row.outcome.sourceCandleIds) -join ',') -ne (@($label.sourceCandleIds) -join ',')){throw 'Java/outcome arithmetic mismatch.'}
        if(@($row.outcome.costSensitivity).Count -ne @($label.costSensitivity).Count){throw 'Cost sensitivity count mismatch.'}
        for($j=0;$j -lt @($label.costSensitivity).Count;$j++){
            if($row.outcome.costSensitivity[$j].roundTripBps -ne $label.costSensitivity[$j].assumedRoundTripCostBps -or
               $row.outcome.costSensitivity[$j].indicativeNetPercent -ne $label.costSensitivity[$j].indicativeNetPercent){throw 'Cost sensitivity mismatch.'}
        }
        if($row.featureStatus -eq 'MATCHES_REVIEWED_CALENDAR'){
            $index=[array]::IndexOf($Request.sessions,$row.decisionDate)
            $expectedDates=@($Request.sessions[($index-251)..$index])
            $bars=@($item[0].bars | Where-Object {$_.date -in $expectedDates})
            if($bars.Count -ne 252 -or $row.featureSnapshot.observationCount -ne 252 -or $row.featureSnapshot.decisionDate -ne $row.decisionDate -or
               $row.featureSnapshot.featureFrom -ne $expectedDates[0] -or (@($bars.candleId) -join ',') -ne (@($row.featureSnapshot.sourceCandleIds) -join ',')){
                throw 'Feature source window mismatch.'
            }
        }
        if($row.featureStatus -eq 'MATCHES_REVIEWED_CALENDAR' -and $row.outcome.status -eq 'STORED_PRICE_ARITHMETIC_ONLY'){$complete++}
    }
    if($Result.completeArithmeticRowCount -ne $complete -or $Result.blockedRowCount -ne ($expected-$complete)){throw 'Export summary mismatch.'}
}
