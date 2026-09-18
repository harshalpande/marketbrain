# Definitions only: no network, process, model or database access.
Set-StrictMode -Version Latest
function ConvertTo-NumericalCalendarDate([string]$Value) {
    [datetime]::ParseExact($Value,'yyyy-MM-dd',[Globalization.CultureInfo]::InvariantCulture)
}
function Get-NumericalCalendarSessions($Calendar) {
    if($Calendar.version -ne 'NSE_CM_RESEARCH_CALENDAR_20250401_20260605_V1' -or
       $Calendar.exchange -ne 'NSE' -or $Calendar.segment -ne 'CM' -or $Calendar.timezone -ne 'Asia/Kolkata' -or
       $Calendar.coverageFrom -ne '2025-04-01' -or $Calendar.coverageThrough -ne '2026-06-05' -or
       $Calendar.rule -ne 'MONDAY_FRIDAY_EXCEPT_CLOSURES_PLUS_SPECIAL_SESSIONS' -or
       $Calendar.specialSessionOverridesClosure -isnot [bool] -or -not $Calendar.specialSessionOverridesClosure){throw 'Unsupported calendar contract.'}
    $from=ConvertTo-NumericalCalendarDate $Calendar.coverageFrom
    $through=ConvertTo-NumericalCalendarDate $Calendar.coverageThrough
    if($through -lt $from -or ($through-$from).Days -gt 730){throw 'Calendar bounds invalid.'}
    $sources=[Collections.Generic.HashSet[string]]::new()
    foreach($s in $Calendar.sources){
        if(-not $sources.Add([string]$s.id) -or $s.url -notmatch '^https://nsearchives\.nseindia\.com/content/circulars/CMTR[0-9]+\.pdf$'){throw 'Calendar source invalid/duplicated.'}
        [void](ConvertTo-NumericalCalendarDate $s.publishedOn)
    }
    if($sources.Count -eq 0){throw 'Calendar requires source evidence.'}
    $closed=[Collections.Generic.HashSet[string]]::new();$special=[Collections.Generic.HashSet[string]]::new()
    foreach($group in @('closures','specialSessions')){
        foreach($item in $Calendar.$group){
            $date=ConvertTo-NumericalCalendarDate $item.date
            if($date -lt $from -or $date -gt $through -or -not $sources.Contains([string]$item.sourceId)){throw 'Calendar exception outside scope or without source.'}
            $added=if($group -eq 'closures'){$closed.Add([string]$item.date)}else{$special.Add([string]$item.date)}
            if(-not $added){throw 'Duplicate calendar exception.'}
        }
    }
    for($d=$from;$d -le $through;$d=$d.AddDays(1)){
        $key=$d.ToString('yyyy-MM-dd')
        if($special.Contains($key) -or ([int]$d.DayOfWeek -ge 1 -and [int]$d.DayOfWeek -le 5 -and -not $closed.Contains($key))){$key}
    }
}
function Get-NumericalFeatureCalendarReview($Evidence,$Calendar) {
    $sessions=@(Get-NumericalCalendarSessions $Calendar)
    if($Evidence.version -ne 'NUMERICAL_FEATURE_EVIDENCE_V1' -or $Evidence.status -ne 'FEATURE_SNAPSHOT_REVIEW_REQUIRED') {throw 'Completed feature evidence required.'}
    $snapshot=$Evidence.snapshot;$payload=$snapshot.payload
    if($snapshot.status -ne 'FEATURE_SNAPSHOT_REVIEW_REQUIRED' -or $payload.version -ne 'OBSERVED_252_FEATURE_SNAPSHOT_V1' -or
       [string]$payload.datasetRunId -ne [string]$Evidence.datasetRunId -or [guid]$payload.datasetRunId -eq [guid]::Empty -or
       $payload.datasetManifestHash -notmatch '^[a-fA-F0-9]{64}$' -or $snapshot.payloadSha256 -notmatch '^[a-fA-F0-9]{64}$'){throw 'Unexpected feature evidence contract.'}
    foreach($flag in @('trainingAuthorized','databaseWritesPerformed')){if($snapshot.$flag -isnot [bool] -or $snapshot.$flag){throw 'Unsafe snapshot flag.'}}
    foreach($count in @('modelCallCount','providerCallCount','ordersCreated')){if(($snapshot.$count -isnot [int] -and $snapshot.$count -isnot [long]) -or $snapshot.$count -ne 0){throw 'Unsafe snapshot counter.'}}
    if($snapshot.partial -isnot [bool]){throw 'Missing partial status.'}
    $items=@($payload.instruments);$dates=@($payload.decisionDates)
    if($items.Count -lt 1 -or $items.Count -gt 4 -or $dates.Count -ne 3){throw 'Evidence exceeds four instruments/three dates.'}
    $asOf=ConvertTo-NumericalCalendarDate $payload.asOf
    $windowFrom=ConvertTo-NumericalCalendarDate $payload.windowFrom
    if(($asOf-$windowFrom).Days -ne 729){throw 'Unexpected snapshot window.'}
    $prior=''
    foreach($date in $dates){
        [void](ConvertTo-NumericalCalendarDate $date)
        if([string]$date -le $prior -or [string]$date -gt [string]$payload.asOf){throw 'Decision dates unordered or after as-of.'}
        $prior=[string]$date
    }
    $results=[Collections.Generic.List[object]]::new();$instruments=[Collections.Generic.HashSet[string]]::new()
    foreach($item in $items){
        if([string]$item.instrumentId -notmatch '^[1-9][0-9]*$' -or -not $instruments.Add([string]$item.instrumentId) -or [string]::IsNullOrWhiteSpace($item.symbol)){throw 'Invalid/duplicate instrument identity.'}
        $bars=@($item.canonicalBars);$rows=@($item.rows)
        if($bars.Count -gt 2001 -or $rows.Count -ne 3 -or $item.rawRowCount -lt $bars.Count -or $item.rawRowCount -gt 2001 -or
           $item.truncated -isnot [bool] -or $item.truncated -ne ($item.rawRowCount -gt 2000)){throw 'Invalid source size or cap.'}
        $byId=@{};$byDate=@{};$prior=''
        foreach($bar in $bars){
            [void](ConvertTo-NumericalCalendarDate $bar.date)
            $key=[string]$bar.candleId;$date=[string]$bar.date
            if($key -notmatch '^[1-9][0-9]*$' -or $byId.ContainsKey($key) -or $date -le $prior -or $date -lt [string]$payload.windowFrom -or $date -gt [string]$payload.asOf){throw 'Invalid/duplicate/out-of-range source ID/date.'}
            if($bar.source -notin @('UPSTOX','NSE_BHAVCOPY') -or $bar.excluded -isnot [bool]){throw 'Unknown source/exclusion flag.'}
            $byId[$key]=$bar;$byDate[$date]=$bar;$prior=$date
        }
        for($i=0;$i -lt 3;$i++){
            $row=$rows[$i];$date=[string]$row.decisionDate
            if($date -ne [string]$dates[$i]){throw 'Row/decision-date mismatch.'}
            if(@($row.sourceCandleIds).Count -gt 252){throw 'Feature row exceeds input-ID budget.'}
            $issues=[Collections.Generic.List[string]]::new();$actual=[Collections.Generic.List[string]]::new();$seen=[Collections.Generic.HashSet[string]]::new()
            $missingIds=[Collections.Generic.List[string]]::new();$excluded=0
            foreach($id in $row.sourceCandleIds){
                $key=[string]$id
                if(-not $seen.Add($key)){$issues.Add('DUPLICATE_INPUT_ID')}
                if(-not $byId.ContainsKey($key)){$missingIds.Add($key);continue}
                $b=$byId[$key];$actual.Add([string]$b.date);if($b.excluded){$excluded++}
            }
            $expected=@($sessions | Where-Object {$_ -le $date} | Select-Object -Last 252)
            if($date -lt $Calendar.coverageFrom -or $date -gt $Calendar.coverageThrough){$issues.Add('CALENDAR_OUT_OF_SCOPE')}
            elseif($date -notin $sessions){$issues.Add('DECISION_NOT_TRADING_SESSION')}
            elseif($expected.Count -lt 252){$issues.Add('CALENDAR_WARMUP_UNAVAILABLE')}
            if($snapshot.partial -or $item.truncated){$issues.Add('PARTIAL_OR_CAPPED_SOURCE')}
            if($null -eq $row.features -or $row.status -ne 'FEATURES_ONLY_CALENDAR_UNVERIFIED'){$issues.Add('UPSTREAM_FEATURE_ROW_BLOCKED')}
            if($missingIds.Count){$issues.Add('UNRESOLVED_INPUT_ID')}
            if($excluded){$issues.Add('EXCLUDED_INPUT')}
            if($row.observationCount -ne 252 -or $actual.Count -ne 252){$issues.Add('INPUT_COUNT_MISMATCH')}
            if($actual.Count -and $row.featureFrom -ne $actual[0]){$issues.Add('FEATURE_FROM_MISMATCH')}
            $missing=@($expected | Where-Object {$_ -notin $actual})
            $unexpected=@($actual.ToArray() | Where-Object {$_ -notin $expected})
            if($missing.Count){$issues.Add('MISSING_EXPECTED_SESSION')}
            if($unexpected.Count){$issues.Add('UNEXPECTED_INPUT_DATE')}
            if(($actual.ToArray() -join ',') -ne ($expected -join ',')){$issues.Add('WINDOW_SEQUENCE_MISMATCH')}
            $results.Add([pscustomobject]@{
                instrumentId=$item.instrumentId;symbol=$item.symbol;decisionDate=$date
                calendarStatus=$(if($issues.Count){'BLOCKED'}else{'MATCHES_REVIEWED_CALENDAR'})
                upstreamFeatureStatus=$row.status;expectedCount=$expected.Count;actualCount=$actual.Count
                expectedFrom=$(if($expected.Count){$expected[0]}else{$null});actualFrom=$row.featureFrom
                missingExpectedDates=$missing;unexpectedInputDates=$unexpected;unresolvedInputIds=$missingIds.ToArray()
                excludedInputCount=$excluded;issues=@($issues.ToArray() | Select-Object -Unique)
            })
        }
    }
    $matched=@($results.ToArray() | Where-Object calendarStatus -eq 'MATCHES_REVIEWED_CALENDAR').Count
    [pscustomobject]@{
        status=$(if($matched -eq $results.Count){'CALENDAR_WINDOWS_MATCH_REVIEW_REQUIRED'}else{'CALENDAR_WINDOWS_BLOCKED'})
        datasetRunId=$payload.datasetRunId;datasetManifestHash=$payload.datasetManifestHash
        reportedPayloadSha256=$snapshot.payloadSha256
        calendarVersion=$Calendar.version;instrumentCount=$items.Count;rowCount=$results.Count
        matchedRowCount=$matched;blockedRowCount=($results.Count-$matched);rows=$results.ToArray()
        trainingAuthorized=$false;labelsGenerated=0;databaseWritesPerformed=$false;modelCallCount=0;providerCallCount=0;ordersCreated=0
        remainingGates=@('PRICE_ADJUSTMENT_AND_CORPORATE_ACTION_POLICY','QUALITY_JOB_MEMBERSHIP_AND_PILOT_EVIDENCE','LABELS_AND_COST_POLICY','CHRONOLOGICAL_SPLITS_AND_UNTOUCHED_EVALUATION')
        limitations='Checks only the embedded feature windows against the cited bounded calendar; does not recalculate values, certify source prices, confirm availability/tradability, validate every stored date or verify the server serialization hash. Input file hash is captured separately. No calendar inference outside coverage and no training promotion.'
    }
}
