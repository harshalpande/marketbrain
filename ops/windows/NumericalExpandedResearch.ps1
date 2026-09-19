Set-StrictMode -Version Latest
. (Join-Path $PSScriptRoot 'NumericalRepairEvidence.ps1')
function New-NumericalExpandedResearchContext($Source,$Repair) {
    $r=$Repair.data
    if($r.version -ne 'NUMERICAL_REPAIR_COLLECTION_V1' -or $r.status -ne 'REPAIR_EVIDENCE_CAPTURED_TRAINING_BLOCKED' -or $r.inputSha256 -ne $Source.sha256){throw 'Repair/source binding mismatch.'}
    # Recompute from saved bars and reviewed calendar; never trust just the captured summary.
    $review=Get-NumericalExpandedCalendarReview $Source $r.earlyCalendar
    Assert-NumericalRepairEvidence $Source $review $r.repairEvidence $r.repairEvidence.priceEvidence.offset
    if($review.status -ne 'EXPANDED_WINDOWS_MATCH_TRAINING_BLOCKED' -or $r.repairEvidence.partial){throw 'Incomplete calendar/repair capture; no expanded request.'}
    $old=$Source.data.request
    $request=[pscustomobject]@{datasetRunId=$old.datasetRunId;datasetManifestHash=$old.datasetManifestHash
        featureEvidenceSha256=$old.featureEvidenceSha256;outcomeEvidenceSha256=$old.outcomeEvidenceSha256
        sessions=@(Get-NumericalEarlySessions $r.earlyCalendar)+@(Get-NumericalOutcomeSessions $Source.data.calendar $Source.data.extension)
        instruments=$old.instruments}
    [pscustomobject]@{request=$request;calendarReview=$review;priceEvidence=$r.repairEvidence;researchMode='UNCERTIFIED_STORED_PRICE_RESEARCH_ONLY';trainingAuthorized=$false}
}
