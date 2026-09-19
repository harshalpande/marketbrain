Set-StrictMode -Version Latest
. (Join-Path $PSScriptRoot 'NumericalExpansionPlan.ps1')
function Get-NumericalEarlySessions($Early) {
    if($Early.version -ne 'NSE_CM_EARLY_CALENDAR_20241022_20250331_V1' -or $Early.exchange -ne 'NSE' -or $Early.segment -ne 'CM' -or
       $Early.timezone -ne 'Asia/Kolkata' -or $Early.coverageFrom -ne '2024-10-22' -or $Early.coverageThrough -ne '2025-03-31' -or
       $Early.rule -ne 'MONDAY_FRIDAY_EXCEPT_CLOSURES_PLUS_SPECIAL_SESSIONS' -or
       (@($Early.closures) -join ',') -ne '2024-11-01,2024-11-15,2024-11-20,2024-12-25,2025-02-26,2025-03-14,2025-03-31' -or
       (@($Early.specialSessions) -join ',') -ne '2024-11-01,2025-02-01'){throw 'Unreviewed early calendar.'}
    $expected=@('CMTR59722','CMTR64628','CMTR64960','CMTR65587','NIFTY20250124')
    if((@($Early.sources.id) -join ',') -ne ($expected -join ',')){throw 'Early calendar source identities changed.'}
    foreach($source in $Early.sources){
        $url=if($source.id -eq 'NIFTY20250124'){'https://www.niftyindices.com/Press_Release/ind_prs24012025_3.pdf'}else{'https://nsearchives.nseindia.com/content/circulars/'+$source.id+'.pdf'}
        if($source.url -ne $url){throw 'Early calendar source URL changed.'}
        [void](ConvertTo-NumericalCalendarDate $source.publishedOn)
    }
    for($day=[datetime]'2024-10-22';$day -le [datetime]'2025-03-31';$day=$day.AddDays(1)){
        $key=$day.ToString('yyyy-MM-dd')
        if($key -in $Early.specialSessions -or ([int]$day.DayOfWeek -ge 1 -and [int]$day.DayOfWeek -le 5 -and $key -notin $Early.closures)){$key}
    }
}
function Get-NumericalExpandedCalendarReview($ExportInput,$Early) {
    $plan=New-NumericalExpansionPlan $ExportInput
    $r=$ExportInput.data
    $sessions=@(Get-NumericalEarlySessions $Early)+@(Get-NumericalOutcomeSessions $r.calendar $r.extension)
    $decisions=@($sessions|Where-Object {$_ -ge $plan.decisionFrom -and $_ -le $plan.decisionThrough})
    $rows=@(foreach($item in $r.request.instruments){foreach($date in $decisions){
        $index=[array]::IndexOf($sessions,$date)
        if($index -lt 251 -or $index+20 -ge $sessions.Count){throw 'Expanded calendar cannot cover requested windows.'}
        $expectedFeatures=@($sessions[($index-251)..$index]);$expectedOutcomes=@($sessions[($index+1)..($index+20)])
        $features=@($item.bars|Where-Object {$_.date -le $date}|Select-Object -Last 252)
        $outcomes=@($item.bars|Where-Object {$_.date -gt $date -and $_.date -le $expectedOutcomes[-1]})
        $featureMatch=(@($features.date) -join ',') -eq ($expectedFeatures -join ',')
        $outcomeMatch=(@($outcomes.date) -join ',') -eq ($expectedOutcomes -join ',')
        [pscustomobject]@{instrumentId=$item.instrumentId;symbol=$item.symbol;decisionDate=$date;featureFrom=$expectedFeatures[0];entryDate=$expectedOutcomes[0];exitDate=$expectedOutcomes[-1]
            featureCalendarMatches=$featureMatch;outcomeCalendarMatches=$outcomeMatch}
    }})
    $blocked=@($rows|Where-Object {-not $_.featureCalendarMatches -or -not $_.outcomeCalendarMatches}).Count
    $qualityBlocked=@($plan.instruments|Where-Object {-not $_.completeObservedPath}).Count
    $layoutMatches=($decisions -join ',') -eq (@($plan.layout.assignments.decisionDate) -join ',')
    [pscustomobject]@{version='NUMERICAL_EXPANDED_CALENDAR_REVIEW_V1';status=$(if($blocked -eq 0 -and $qualityBlocked -eq 0 -and $layoutMatches){'EXPANDED_WINDOWS_MATCH_TRAINING_BLOCKED'}else{'EXPANDED_WINDOWS_BLOCKED'})
        plan=$plan;decisionDateCount=$decisions.Count;rowCount=$rows.Count;featureWindowMatchCount=@($rows|Where-Object featureCalendarMatches).Count
        outcomeWindowMatchCount=@($rows|Where-Object outcomeCalendarMatches).Count;blockedRowCount=$blocked;qualityBlockedInstrumentCount=$qualityBlocked
        provisionalLayoutMatchesReviewedDates=$layoutMatches;rows=$rows;trainingAuthorized=$false
        remainingGates=@('REPAIR_AND_PRICE_PROVENANCE','RESEARCH_POLICY_APPROVAL','BROADER_JAVA_EXPORT','FROZEN_FOLDS_AND_UNTOUCHED_EVALUATION')
        limitation='Date sequences and basic saved-bar quality only, not corporate-action/executable-price certification. Existing plan remains a development layout. No new features or labels, fitting or trading.'}
}
