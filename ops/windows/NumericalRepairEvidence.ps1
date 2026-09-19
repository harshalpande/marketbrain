Set-StrictMode -Version Latest
. (Join-Path $PSScriptRoot 'NumericalExpandedCalendar.ps1')
function Assert-NumericalRepairEvidence($ExportInput,$CalendarReview,$Evidence,[int]$Offset) {
    $request=$ExportInput.data.request;$plan=$CalendarReview.plan;$p=$Evidence.priceEvidence
    if($Evidence.version -ne 'NUMERICAL_REPAIR_EVIDENCE_V1' -or $Evidence.status -ne 'REPAIR_PROVENANCE_REVIEW_REQUIRED' -or
       $p.version -ne 'NUMERICAL_PRICE_EVIDENCE_V1' -or $p.datasetRunId -ne $request.datasetRunId -or $p.datasetManifestHash -ne $request.datasetManifestHash -or
       $p.fromDate -ne $plan.featureFrom -or $p.throughDate -ne $plan.outcomeThrough -or $p.offset -ne $Offset -or
       $p.limit -ne @($request.instruments).Count -or @($p.instruments).Count -ne @($request.instruments).Count){throw 'Repair evidence scope mismatch.'}
    foreach($object in @($Evidence,$p)){
        foreach($flag in @('trainingAuthorized','databaseWritesPerformed')){if($object.$flag -isnot [bool] -or $object.$flag){throw 'Unsafe repair evidence flag.'}}
        foreach($counter in @('providerCallCount','modelCallCount','ordersCreated')){if(($object.$counter -isnot [int] -and $object.$counter -isnot [long]) -or $object.$counter -ne 0){throw 'Unsafe repair evidence counter.'}}
        if($object.partial -isnot [bool]){throw 'Unknown partial state.'}
    }
    $resolutionIds=[Collections.Generic.HashSet[string]]::new();$actionIds=[Collections.Generic.HashSet[string]]::new()
    for($i=0;$i -lt @($request.instruments).Count;$i++){
        $item=$p.instruments[$i];$expected=$request.instruments[$i]
        if($item.instrumentId -ne $expected.instrumentId -or $item.symbol -ne $expected.symbol){throw 'Repair instrument mismatch.'}
        foreach($e in $item.latestRelevantResolutions){[void]$resolutionIds.Add([string]$e.id)}
        foreach($a in $item.corporateActions){[void]$actionIds.Add([string]$a.id)}
    }
    if($Evidence.scopedResolutionCount -ne $resolutionIds.Count -or $Evidence.scopedActionCount -ne $actionIds.Count -or @($Evidence.references).Count -gt 400){throw 'Repair reference counts mismatch.'}
    $seen=[Collections.Generic.HashSet[string]]::new();$res=0;$actions=0
    foreach($ref in $Evidence.references){
        if(-not $seen.Add("$($ref.kind)|$($ref.recordId)")){throw 'Duplicate repair reference.'}
        if($ref.kind -eq 'RESOLUTION' -and $resolutionIds.Contains([string]$ref.recordId)){$res++}
        elseif($ref.kind -eq 'CORPORATE_ACTION' -and $actionIds.Contains([string]$ref.recordId)){$actions++}
        else{throw 'Unscoped repair reference.'}
        if($ref.publicReference){
            if($ref.publicReference -notmatch '^https://nsearchives\.nseindia\.com/(content/circulars|corporate|content/historical)/[A-Za-z0-9_./-]+\.(pdf|csv|zip)$' -or $ref.publicReference.Contains('..')){throw 'Unapproved shared reference URL.'}
        }
        foreach($field in @('notesSha256','originalReferenceSha256','evidenceSourceSha256')){if($ref.$field -and $ref.$field -notmatch '^[a-fA-F0-9]{64}$'){throw 'Invalid evidence hash.'}}
        foreach($forbidden in @('notes','reviewedBy','reviewed_by','evidence_url','rawUrl','evidence_source')){if($ref.PSObject.Properties[$forbidden]){throw 'Unexpected private evidence field.'}}
    }
    $partialExpected=$p.partial -or $resolutionIds.Count -gt 200 -or $actionIds.Count -gt 200 -or
        $res -ne [math]::Min(200,$resolutionIds.Count) -or $actions -ne [math]::Min(200,$actionIds.Count)
    if($Evidence.partial -ne $partialExpected){throw 'Repair partial state mismatch.'}
}
