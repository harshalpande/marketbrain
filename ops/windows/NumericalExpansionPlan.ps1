# Pure development-layout planning. Observed dates are NOT a verified exchange calendar.
Set-StrictMode -Version Latest
. (Join-Path $PSScriptRoot 'NumericalResearchExport.ps1')
function New-NumericalDevelopmentLayout([string[]]$ObservedDates) {
    if($ObservedDates.Count -ne 170){throw 'Layout requires 150 decision dates plus 20 observed outcome dates.'}
    $prior=''
    foreach($day in $ObservedDates){[void](ConvertTo-NumericalCalendarDate $day);if($day -le $prior){throw 'Dates must be unique and ascending.'};$prior=$day}
    # Fixed BEFORE fitting, and independent of returns: 60 retained train, 20 validation, 20 shadow-test dates.
    # 20-session purges before each boundary; five-date gaps at each later partition start.
    $rows=@(for($i=0;$i -lt 150;$i++){
        $partition=if($i -lt 80){'TRAIN'}elseif($i -lt 125){'VALIDATION'}else{'SHADOW_TEST'}
        $boundary=if($partition -eq 'TRAIN'){$ObservedDates[80]}elseif($partition -eq 'VALIDATION'){$ObservedDates[125]}else{$null}
        $state='RETAINED_PROVISIONAL'
        if($boundary -and $ObservedDates[$i+20] -ge $boundary){$state='PURGED_LABEL_OVERLAP'}
        elseif(($i -ge 80 -and $i -lt 85) -or ($i -ge 125 -and $i -lt 130)){$state='FIVE_DATE_BOUNDARY_GAP'}
        [pscustomobject]@{decisionDate=$ObservedDates[$i];entryDate=$ObservedDates[$i+1];exitDate=$ObservedDates[$i+20];partition=$partition;state=$state}
    })
    [pscustomobject]@{version='NUMERICAL_DEVELOPMENT_LAYOUT_V1';calendarBasis='OBSERVED_DATES_UNVERIFIED';horizonSessions=20;lookbackSessions=252
        decisionDateCount=150;validationFrom=$ObservedDates[80];shadowTestFrom=$ObservedDates[125];boundaryGapDates=5
        trainRetainedDateCount=60;validationRetainedDateCount=20;shadowTestRetainedDateCount=20;purgedDateCount=40;boundaryGapDateCount=10
        assignments=$rows;trainingAuthorized=$false;untouchedTest=$false
        limitation='Engineering size target only, not statistical sufficiency. Observed dates may contain gaps/extra sessions. Must regenerate against a reviewed exchange calendar before any split acceptance. SHADOW_TEST is development evaluation, never an untouched test.'}
}
function New-NumericalExpansionPlan($ExportInput) {
    $report=$ExportInput.data
    if($report.version -ne 'NUMERICAL_RESEARCH_EXPORT_COLLECTION_V1' -or $report.status -ne 'RESEARCH_EXPORT_TRAINING_BLOCKED'){throw 'Completed research export required.'}
    $items=@($report.request.instruments)
    if($items.Count -lt 1 -or $items.Count -gt 4){throw 'Unsupported instrument count.'}
    if(@($report.request.sessions).Count -ne 320 -or @($report.result.rows).Count -gt 152){throw 'Saved export exceeds pilot bounds.'}
    $ids=[Collections.Generic.HashSet[string]]::new()
    foreach($item in $items){
        if(@($item.bars).Count -gt 700){throw 'Source bar cap exceeded.'}
        $prior=''
        foreach($bar in $item.bars){
            [void](ConvertTo-NumericalCalendarDate $bar.date)
            if($bar.date -le $prior -or [string]$bar.candleId -notmatch '^[1-9][0-9]*$' -or -not $ids.Add([string]$bar.candleId) -or
               $bar.excluded -isnot [bool] -or $bar.source -notin @('UPSTOX','NSE_BHAVCOPY')){throw 'Invalid source identity/order/flags.'}
            $prior=$bar.date
        }
    }
    Assert-NumericalResearchExportResult $report.request $report.result
    # Anchor to the first saved instrument's full sequence; NEVER intersect away another instrument's missing dates.
    $anchor=@($items[0].bars.date);$decisionEnd=[array]::IndexOf($anchor,'2026-06-05');$first=$decisionEnd-149
    if($first -lt 251 -or $decisionEnd+20 -ge $anchor.Count){throw 'Insufficient saved history for fixed development layout; no automatic fetch.'}
    $layout=New-NumericalDevelopmentLayout $anchor[$first..($decisionEnd+20)]
    $requiredDates=@($anchor[($first-251)..($decisionEnd+20)])
    $known=@(Get-NumericalOutcomeSessions $report.calendar $report.extension)
    $outside=@($requiredDates|Where-Object {$_ -lt $report.calendar.coverageFrom -or $_ -gt $report.extension.coverageThrough})
    $knownMismatch=@($requiredDates|Where-Object {$_ -ge $report.calendar.coverageFrom -and $_ -le $report.extension.coverageThrough -and $_ -notin $known})
    $knownMissing=@($known|Where-Object {$_ -ge $requiredDates[0] -and $_ -le $requiredDates[-1] -and $_ -notin $requiredDates})
    $scope=@(foreach($item in $items){
        $byDate=@{};foreach($bar in $item.bars){$byDate[[string]$bar.date]=$bar}
        $missing=@($requiredDates|Where-Object {-not $byDate.ContainsKey($_)})
        $excluded=@($requiredDates|Where-Object {$byDate.ContainsKey($_) -and $byDate[$_].excluded})
        $invalid=@(foreach($day in $requiredDates){if($byDate.ContainsKey($day)){
            $b=$byDate[$day];$valid=$true
            foreach($field in @('open','high','low','close','volume')){if(-not(Test-NumericalBundleNumber $b.$field) -or [decimal]$b.$field -lt 0 -or ($field -ne 'volume' -and [decimal]$b.$field -eq 0)){$valid=$false}}
            if($valid){$valid=[decimal]$b.low -le [decimal]$b.open -and [decimal]$b.low -le [decimal]$b.close -and [decimal]$b.high -ge [decimal]$b.open -and [decimal]$b.high -ge [decimal]$b.close}
            if(-not $valid){$day}
        }})
        [pscustomobject]@{instrumentId=$item.instrumentId;symbol=$item.symbol;savedBarCount=@($item.bars).Count;requiredObservedDateCount=$requiredDates.Count
            missingDates=$missing;excludedDates=$excluded;invalidDates=$invalid;completeObservedPath=($missing.Count+$excluded.Count+$invalid.Count -eq 0)}
    })
    $seenDates=@($report.result.rows.decisionDate|Sort-Object -Unique)
    $exposed=@($layout.assignments|Where-Object {$_.partition -eq 'SHADOW_TEST' -and $_.state -eq 'RETAINED_PROVISIONAL' -and $_.decisionDate -in $seenDates})
    [pscustomobject]@{version='NUMERICAL_EXPANSION_PLAN_V1';status='DEVELOPMENT_PLAN_REQUIRES_CALENDAR_AND_PRICE_EVIDENCE';inputSha256=$ExportInput.sha256
        datasetRunId=$report.request.datasetRunId;datasetManifestHash=$report.request.datasetManifestHash
        featureEvidenceSha256=$report.request.featureEvidenceSha256;outcomeEvidenceSha256=$report.request.outcomeEvidenceSha256
        decisionFrom=$anchor[$first];decisionThrough='2026-06-05';featureFrom=$requiredDates[0];outcomeThrough=$requiredDates[-1]
        provisionalCandidateRowCount=(150*$items.Count);provisionalRetainedRowCount=(100*$items.Count)
        instruments=$scope;layout=$layout;calendarExtensionRequiredDates=$outside;knownCalendarExtraDates=$knownMismatch;knownCalendarMissingDates=$knownMissing
        previouslyReviewedShadowTestDateCount=$exposed.Count;untouchedTest=$false;trainingAuthorized=$false
        remainingGates=@('REVIEW_EARLIER_EXCHANGE_CALENDAR','EXTEND_PRICE_ACTION_EVIDENCE_TO_FULL_SCOPE','APPROVE_RESEARCH_PRICE_COST_AVAILABILITY_UNIVERSE_CONTRACT','IMPLEMENT_BROADER_EXPORT_AND_VERIFY_SPLITS','RESERVE_GENUINELY_UNTOUCHED_EVALUATION')
        databaseQueryCount=0;providerCallCount=0;modelCallCount=0;ordersCreated=0
        limitation='Plan only: no new features, labels, fitting or approved folds. Boundaries derived from saved dates, not returns. Date completeness is provisional until the independent calendar is extended. Existing source-price provenance remains unknown. The inspected pilot is not an untouched holdout; engineering minima do not establish generalization.'}
}
