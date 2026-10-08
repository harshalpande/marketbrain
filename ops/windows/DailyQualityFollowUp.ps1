# Definitions only. Fixed October 8 incident review; no network or database calls on import.
Set-StrictMode -Version Latest
function Assert-DailyReviewFalse($Value,[string]$Name){
    if($Value -isnot [bool] -or $Value){throw "Unsafe or missing flag: $Name"}
}
function Assert-DailyReviewScope($Run){
    if([string]$Run.runId -cne 'eebff875-3621-4064-a2ea-9de0b269681e' -or
        $Run.status -cne 'COMPLETED' -or [string]$Run.requestedFrom -cne '2026-09-19' -or
        [string]$Run.targetDate -cne '2026-10-08' -or $Run.instruments -ne 500 -or
        [string]$Run.universeSnapshotId -cne '68117add-3ebe-4681-82fc-ff5613ecd869'){
        throw 'Daily run scope changed; stop before quality/source queries.'
    }
}
function Assert-DailyReviewQuality($Quality){
    if([string]$Quality.jobId -cne 'eebff875-3621-4064-a2ea-9de0b269681e' -or
        [string]$Quality.requestedFrom -cne '2026-09-19' -or [string]$Quality.requestedTo -cne '2026-10-08' -or
        $Quality.instrumentCount -ne 500 -or $Quality.jobStatus -cne 'COMPLETED') {throw 'Quality scope changed.'}
    Assert-DailyReviewFalse $Quality.providerSpotCheckRequested 'providerSpotCheckRequested'
    $moves=@($Quality.largeMoves|Where-Object symbol -CEQ 'POLICYBZR')
    if($moves.Count -ne 1 -or [string]$moves[0].tradingDate -cne '2026-09-24' -or
        $moves[0].previousClose -ne 1886.3 -or $moves[0].close -ne 1207.2 -or $Quality.truncatedFindingCount -ne 0){
        throw 'Reviewed POLICYBZR finding changed or truncated; do not fetch an expanded scope.'
    }
}
function Get-DailyReviewFeatureSummary($Preview){
    if($Preview.status -cne 'REVIEW_REQUIRED' -or $Preview.featureSetVersion -cne 'TECHNICAL_V1' -or
        [string]$Preview.requestedAsOf -cne '2026-10-08' -or
        [string]$Preview.universeSnapshotId -cne '68117add-3ebe-4681-82fc-ff5613ecd869' -or
        $Preview.instrumentCount -ne 500 -or @($Preview.instruments).Count -ne 500 -or
        $Preview.manifestHash -cnotmatch '^[a-f0-9]{64}$') {throw 'Feature scope or manifest invalid.'}
    Assert-DailyReviewFalse $Preview.databaseWritesPerformed 'features.databaseWritesPerformed'
    $symbols=[Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    $counts=@{ELIGIBLE=0;STALE=0;INSUFFICIENT_HISTORY=0;NO_ELIGIBLE_DATA=0}
    $withheld=[Collections.Generic.List[object]]::new()
    foreach($item in $Preview.instruments){
        if([string]$item.symbol -notmatch '^[A-Z0-9&-]{1,64}$' -or -not $symbols.Add([string]$item.symbol) -or
            -not $counts.ContainsKey([string]$item.status) -or [string]$item.requestedAsOf -cne '2026-10-08' -or
            $item.featureSetVersion -cne 'TECHNICAL_V1'){throw 'Invalid/duplicate feature item.'}
        Assert-DailyReviewFalse $item.databaseWritesPerformed 'item.databaseWritesPerformed'
        foreach($field in @('canonicalObservationCount','eligibleObservationCount','excludedObservationCount')){
            if(($item.$field -isnot [int] -and $item.$field -isnot [long]) -or $item.$field -lt 0){throw 'Invalid observation count.'}
        }
        if($item.canonicalObservationCount -ne ($item.eligibleObservationCount+$item.excludedObservationCount)){throw 'Observation counts do not reconcile.'}
        $effective=if($null -eq $item.effectiveAsOf){$null}else{[datetime]::ParseExact([string]$item.effectiveAsOf,'yyyy-MM-dd',[Globalization.CultureInfo]::InvariantCulture)}
        $asOf=[datetime]'2026-10-08'
        if($null -ne $effective -and $effective -gt $asOf){throw 'Future effective date.'}
        if($item.status -eq 'ELIGIBLE' -and ($effective -ne $asOf -or $item.eligibleObservationCount -lt 252 -or $null -eq $item.features)){throw 'Invalid eligible feature.'}
        if($item.status -eq 'STALE' -and ($null -eq $effective -or $effective -ge $asOf -or $item.eligibleObservationCount -lt 252 -or $null -eq $item.features)){throw 'Invalid stale feature.'}
        if($item.status -eq 'INSUFFICIENT_HISTORY' -and ($item.eligibleObservationCount -lt 1 -or $item.eligibleObservationCount -ge 252 -or $null -eq $effective -or $null -ne $item.features)){throw 'Invalid short-history feature.'}
        if($item.status -eq 'NO_ELIGIBLE_DATA' -and ($item.eligibleObservationCount -ne 0 -or $null -ne $effective -or $null -ne $item.features)){throw 'Invalid empty feature.'}
        $counts[$item.status]++
        if($item.status -ne 'ELIGIBLE'){$withheld.Add($item)}
    }
    if($counts.ELIGIBLE -ne $Preview.eligibleCount -or $counts.STALE -ne $Preview.staleCount -or
        $counts.INSUFFICIENT_HISTORY -ne $Preview.insufficientHistoryCount -or $counts.NO_ELIGIBLE_DATA -ne $Preview.noEligibleDataCount -or
        ($counts.ELIGIBLE+$counts.STALE) -ne $Preview.featureVectorCount){throw 'Feature classification totals mismatch.'}
    [pscustomobject]@{eligible=$counts.ELIGIBLE;withheld=$withheld.Count;classifications=$counts;withheldInstruments=$withheld.ToArray()
        manifestMatchesOriginalAutomation=($Preview.manifestHash -ceq '50e0749dfdfbc3e370f4cd5d0f23069021154bf69baafcc815cffcb509cbbb62')
        originalEligible=487;originalWithheld=13
        limitation='TECHNICAL_V1 uses historical dates and the current universe; its pointInTimeSafe flag does not certify original data availability or prediction fitness.'}
}
function Assert-DailyReviewOfficialEvidence($Evidence){
    if([string]$Evidence.jobId -cne 'eebff875-3621-4064-a2ea-9de0b269681e' -or $Evidence.findingCount -ne 1 -or
        @($Evidence.findings).Count -ne 1 -or $Evidence.sourceRequestCount -ne 1){throw 'Official evidence scope changed.'}
    Assert-DailyReviewFalse $Evidence.resolutionsWritten 'resolutionsWritten'
    $item=$Evidence.findings[0]
    if($item.symbol -cne 'POLICYBZR' -or [string]$item.findingDate -cne '2026-09-24' -or
        $item.storedPreviousClose -ne 1886.3 -or $item.storedClose -ne 1207.2){throw 'Evidence finding changed.'}
    # A captured source failure/mismatch is valid diagnostic evidence, never a resolution.
}
