# Pure reviewer for the pinned, previously accepted E52 saved cohort.
Set-StrictMode -Version Latest
. (Join-Path $PSScriptRoot 'NumericalReadinessBundle.ps1')
$script:MappingEvidenceSha='E983F6EE5B0B6DDA2DE40DC27D37451B2DD58C5D360CBBE092672B9EFD419CA8'
function ConvertTo-NumericalMappingUtc($Value) {
    # PS 5.1 generally retains JSON timestamp strings; PS 7 also supplies typed dates.
    # Never stringify a DateTime: that loses Kind/offset and introduces culture/local-zone parsing.
    if($Value -is [DateTimeOffset]){return $Value.UtcDateTime}
    if($Value -is [datetime]){
        if($Value.Kind -eq [DateTimeKind]::Unspecified){throw 'Cutoff timestamp has no timezone.'}
        return $Value.ToUniversalTime()
    }
    if($Value -isnot [string] -or $Value -cnotmatch '^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(\.\d{1,7})?(Z|[+-]\d{2}:\d{2})$'){
        throw 'Explicit ISO-8601 timezone required for cutoff.'
    }
    $instant=[DateTimeOffset]::Parse($Value,[Globalization.CultureInfo]::InvariantCulture,[Globalization.DateTimeStyles]::None)
    return $instant.UtcDateTime
}
function Get-NumericalMappingReplayResult($Source,$Replay) {
    Assert-NumericalMappingSource $Source
    $data=$Replay.data
    if($data.version -eq 'NUMERICAL_RESEARCH_MAPPING_V1'){return $data}
    if($data.version -ne 'NUMERICAL_RESEARCH_MAPPING_COLLECTION_V1' -or $data.sourceSha256 -cne $Source.sha256 -or
       $data.trainingAuthorized -isnot [bool] -or $data.trainingAuthorized -or $null -eq $data.result){throw 'Saved mapping report is incomplete or bound to a different source.'}
    # Compare both requests after the SAME runtime's JSON decoding, not cross-version serialized bytes.
    if(($data.request|ConvertTo-Json -Depth 16 -Compress) -cne ($Source.data.request|ConvertTo-Json -Depth 16 -Compress)){
        throw 'Saved mapping report request differs from accepted evidence.'
    }
    # FAILED_PARTIAL_REPORT is reusable only because the entire response is independently revalidated.
    return $data.result
}
function Assert-NumericalMappingSource($Source) {
    if($Source.sha256 -ne $script:MappingEvidenceSha -or $Source.data.version -ne 'NUMERICAL_EXPANDED_RESEARCH_COLLECTION_V1' -or
       $Source.data.result.candidateRowCount -ne 600 -or $Source.data.trainingAuthorized -isnot [bool] -or $Source.data.trainingAuthorized){throw 'Expected accepted E52 saved export; do not recollect or substitute another cohort.'}
}
function Assert-NumericalResearchMapping($Source,$Result) {
    Assert-NumericalMappingSource $Source
    $saved=$Source.data
    if($Result.version -ne 'NUMERICAL_RESEARCH_MAPPING_V1' -or $Result.status -ne 'MAPPED_RESEARCH_TRAINING_BLOCKED' -or
       $Result.datasetRunId -ne $saved.request.datasetRunId -or $Result.datasetManifestHash -ne $saved.request.datasetManifestHash -or
       $Result.calendarSessionSha256 -ne $saved.result.calendarSessionSha256){throw 'Mapping response identity mismatch.'}
    foreach($name in @('trainingAuthorized','databaseWritesPerformed')){if($Result.$name -isnot [bool] -or $Result.$name){throw 'Unsafe mapping response.'}}
    foreach($name in @('trainingEligibleCount','certifiedLabelCount','databaseQueryCount','providerCallCount','modelCallCount','ordersCreated')){
        if(($Result.$name -isnot [int] -and $Result.$name -isnot [long]) -or $Result.$name -ne 0){throw 'Unexpected safety count.'}
    }
    if($Result.rowCount -ne 600 -or $Result.mappingReadyCount -ne 600 -or @($Result.rows).Count -ne 600 -or @($Result.dateCoverage).Count -ne 150){throw 'Mapping coverage mismatch.'}
    $expected=@{};$closes=@{};$seen=@{};$dates=@{};$blockers=@{}
    foreach($instrument in $saved.request.instruments){foreach($bar in $instrument.bars){$closes["$($instrument.instrumentId)|$($bar.date)"]=[decimal]$bar.close}}
    foreach($row in $saved.result.rows){$expected["$($row.instrumentId)|$($row.decisionDate)"]=$row}
    $names=@('dailyReturnPercent','closeToSma20Percent','closeToSma50Percent','closeToSma200Percent','ema12ToEma26Percent','rsi14','atr14ToClosePercent','annualizedVolatility20Percent','volumeRatio20','rangePosition252Percent')
    if(($Result.featureNames -join '|') -cne ($names -join '|')){throw 'Feature order mismatch.'}
    foreach($row in $Result.rows){
        $key="$($row.instrumentId)|$($row.decisionDate)"
        if(-not $expected.ContainsKey($key) -or $seen.ContainsKey($key)){throw 'Unknown or repeated row.'};$seen[$key]=$true
        $old=$expected[$key];$f=$old.featureSnapshot.features;$close=$closes[$key]
        if($row.symbol -cne $old.symbol -or $row.featureStatus -cne $old.featureStatus -or $row.mappingReady -isnot [bool] -or -not $row.mappingReady -or
           $row.trainingEligible -isnot [bool] -or $row.trainingEligible){throw 'Invalid row identity or eligibility.'}
        $cutoff=ConvertTo-NumericalMappingUtc ($old.decisionDate+'T16:00:00+05:30')
        $actualCutoff=ConvertTo-NumericalMappingUtc $row.proposedCutoff
        if($actualCutoff.Ticks -ne $cutoff.Ticks){throw "Decision cutoff mismatch for ${key}: expected UTC $($cutoff.ToString('o')); received UTC $($actualCutoff.ToString('o'))."}
        foreach($field in @('receivedAfterCutoffCount','missingReceivedAtCount')){if($row.$field -ne $old.featureSnapshot.$field){throw 'Receipt diagnostics changed.'}}
        if(($row.sourceCandleIds -join ',') -ne ($old.featureSnapshot.sourceCandleIds -join ',')){throw 'Source window changed.'}
        $values=@(([decimal]$f.dailyReturnPercent),(100*($close/[decimal]$f.sma20-1)),(100*($close/[decimal]$f.sma50-1)),(100*($close/[decimal]$f.sma200-1)),
            (100*([decimal]$f.ema12/[decimal]$f.ema26-1)),([decimal]$f.rsi14),(100*[decimal]$f.atr14/$close),([decimal]$f.annualizedVolatility20Percent),([decimal]$f.volumeRatio20),([decimal]$f.rangePosition252Percent))
        if(@($row.features.PSObject.Properties).Count -ne 10){throw 'Unexpected feature fields.'}
        for($i=0;$i -lt 10;$i++){
            $actual=$row.features.($names[$i]);$wanted=[math]::Round($values[$i],8,[MidpointRounding]::AwayFromZero)
            if(-not(Test-NumericalBundleNumber $actual) -or [math]::Abs([decimal]$actual-$wanted) -gt [decimal]'0.00000001'){throw "Feature arithmetic mismatch: $($names[$i])"}
        }
        $required=@('PRICE_ACTION_PROVENANCE_UNVERIFIED','HISTORICAL_AVAILABILITY_UNVERIFIED','SOURCE_RIGHTS_SCOPE_REVIEW_PENDING','EVALUATION_POLICY_AND_FIT_APPROVAL_PENDING')
        if($old.featureSnapshot.receivedAfterCutoffCount -gt 0){$required+='STORED_RECEIPT_AFTER_CUTOFF'}
        if($old.featureSnapshot.missingReceivedAtCount -gt 0){$required+='STORED_RECEIPT_MISSING'}
        if(($row.blockers -join '|') -cne ($required -join '|')){throw 'Blocker ledger mismatch.'}
        foreach($reason in $required){if(-not $blockers.ContainsKey($reason)){$blockers[$reason]=0};$blockers[$reason]++}
        if(-not $dates.ContainsKey([string]$row.decisionDate)){$dates[[string]$row.decisionDate]=0};$dates[[string]$row.decisionDate]++
    }
    foreach($d in $Result.dateCoverage){
        if(-not $dates.ContainsKey([string]$d.decisionDate) -or $d.rowCount -ne 4 -or $d.mappingReadyCount -ne 4 -or $d.trainingEligibleCount -ne 0){throw 'Invalid date group.'}
        $dates.Remove([string]$d.decisionDate)
    }
    if($dates.Count -ne 0 -or @($Result.blockerCounts.PSObject.Properties).Count -ne $blockers.Count){throw 'Incomplete coverage or blocker summary.'}
    foreach($reason in $blockers.Keys){if($Result.blockerCounts.$reason -ne $blockers[$reason]){throw 'Invalid blocker count.'}}
}
