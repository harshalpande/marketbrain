# Definitions only. Inspect saved evidence; never execute content from a report.
Set-StrictMode -Version Latest
. (Join-Path $PSScriptRoot 'ReviewedOctoberFeatureSnapshot.ps1')
function Assert-ReconciliationEvidence($Report){
    if($Report.version -cne 'REVIEWED_OCTOBER_FEATURE_SNAPSHOT_V1' -or $Report.status -cne 'FEATURE_SNAPSHOT_VERIFIED_RELEASE_BLOCKED' -or
        $Report.writeState -cne 'SNAPSHOT_VERIFIED' -or [string]$Report.runId -cne 'fc15cbe7-15c7-46ab-989e-f09ba7978858' -or
        $null -ne $Report.failureStage -or $Report.reviewedBy -cne 'Harshal Pande'){throw 'Wrong accepted snapshot report.'}
    Assert-OctoberSnapshot $Report.postResponse -RunId $Report.runId -Reviewer $Report.reviewedBy
    Assert-OctoberSnapshot $Report.persistedQuality -RunId $Report.runId -Quality
    foreach($flag in @('priceChangeRequested','resolutionChangeRequested','exclusionRequested','schedulerResetRequested','modelOrTradeRequested')){Assert-DailyReviewFalse $Report.$flag $flag}
    if(@($Report.requests|Where-Object method -eq 'Post').Count -ne 1 -or @($Report.requests|Where-Object status -ne 'RETURNED').Count -ne 0){throw 'Source request sequence differs.'}
}
function Assert-ReconciliationResponse($Value,[switch]$Write){
    if($Value.version -cne 'REVIEWED_FEATURE_RECONCILIATION_V1' -or [string]$Value.targetDate -cne '2026-10-08' -or
        [string]$Value.dailyRunId -cne 'eebff875-3621-4064-a2ea-9de0b269681e' -or
        [string]$Value.featureSnapshotRunId -cne 'fc15cbe7-15c7-46ab-989e-f09ba7978858' -or
        $Value.featureManifestHash -cne '50e0749dfdfbc3e370f4cd5d0f23069021154bf69baafcc815cffcb509cbbb62' -or
        $Value.evidenceSha256 -cne '128C921E4C21734E9CC0801B39735ECDF9152A43C9906FB3695FEE44ACB62324' -or
        $Value.eligibleCount -ne 487 -or $Value.withheldCount -ne 13){throw 'Reconciliation response scope differs.'}
    foreach($field in @('snapshotWrites','signalsCreated','ordersCreated')){
        if(($Value.$field -isnot [int] -and $Value.$field -isnot [long]) -or $Value.$field -ne 0){throw 'Unexpected side-effect counter.'}
    }
    if($Value.databaseWritesPerformed -isnot [bool]){throw 'Missing write flag.'}
    if(-not $Write){Assert-DailyReviewFalse $Value.databaseWritesPerformed 'GET.databaseWritesPerformed'}
    if($Value.status -ceq 'READY_TO_RECONCILE'){
        if($Write -or $Value.automationStatus -cne 'REVIEW_REQUIRED' -or $null -ne $Value.reconciliationId){throw 'Unexpected preview state.'}
    }elseif($Value.status -in @('RECONCILED','ALREADY_RECONCILED')){
        $id=[guid]::Empty
        if($Value.automationStatus -cne 'COMPLETED' -or -not [guid]::TryParse([string]$Value.reconciliationId,[ref]$id) -or
            $id -eq [guid]::Empty -or [string]::IsNullOrWhiteSpace($Value.reviewedBy)){throw 'Completed reconciliation is missing audit identity.'}
        if(-not $Write -and $Value.status -cne 'ALREADY_RECONCILED'){throw 'GET may not apply a reconciliation.'}
        if(($Value.status -ceq 'RECONCILED') -ne $Value.databaseWritesPerformed){throw 'Status/write flag mismatch.'}
    }else{throw 'Unknown reconciliation status.'}
}
