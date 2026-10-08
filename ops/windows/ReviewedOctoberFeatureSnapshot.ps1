# Definitions only. Exact October 8 checkpoint, not a generic quality bypass.
Set-StrictMode -Version Latest
. (Join-Path $PSScriptRoot 'ReviewedPolicyBzrResolution.ps1')
function Assert-OctoberSnapshotPreview($Preview){
    # Validate the existing-snapshot branch separately, then reuse the exact readiness guards on a copy.
    $copy=$Preview|ConvertTo-Json -Depth 6|ConvertFrom-Json
    $id=$null
    if($Preview.persistenceAction -ceq 'ALREADY_PERSISTED'){
        $parsed=[guid]::Empty
        if($Preview.existingFeatureSnapshotStatus -cne 'COMPLETED' -or
            -not [guid]::TryParse([string]$Preview.existingFeatureSnapshotRunId,[ref]$parsed) -or $parsed -eq [guid]::Empty){throw 'Invalid existing snapshot identity/status.'}
        $id=$parsed.ToString();$copy.persistenceAction='READY_TO_PERSIST';$copy.existingFeatureSnapshotRunId=$null
    }elseif($null -ne $Preview.existingFeatureSnapshotStatus){throw 'Unexpected existing snapshot status.'}
    if(-not (Test-PolicyBzrFeatureReadiness $copy)){throw 'Fresh daily quality/feature readiness is not READY.'}
    if($Preview.totalChunks -ne 500 -or $Preview.completedChunks -ne 500 -or $Preview.acceptedRows -ne 6500 -or
        $Preview.pointInTimeSafe -isnot [bool] -or -not $Preview.pointInTimeSafe){throw 'Daily coverage or feature cutoff flag changed.'}
    return $id
}
function Assert-OctoberResolution($Rows){
    $r=Get-PolicyBzrCurrentResolution $Rows (New-PolicyBzrResolutionBody 'Payload comparison only')
    if($null -eq $r -or [string]$r.id -cne '19bc5ced-9ec0-497b-a2d2-ff86768249cd'){throw 'The accepted resolution is absent or has changed identity.'}
}
function Assert-OctoberResolutionEvidence($Evidence){
    if($Evidence.version -cne 'POLICYBZR_REVIEWED_RESOLUTION_V1' -or
        $Evidence.status -cne 'RESOLUTION_VERIFIED_FEATURE_READY_NOT_PERSISTED' -or
        $Evidence.writeState -cne 'RESOLUTION_VERIFIED' -or $null -ne $Evidence.failureStage){throw 'Wrong accepted resolution report.'}
    Assert-PolicyBzrEvidence $Evidence.evidence
    Assert-OctoberResolution @($Evidence.currentAfter)
    foreach($f in @('featurePersistenceRequested','priceChangeRequested','exclusionRequested','modelOrTradeRequested')){Assert-DailyReviewFalse $Evidence.$f $f}
    $id=Assert-OctoberSnapshotPreview $Evidence.featurePreview
    if($null -ne $id){throw 'Source evidence should precede snapshot persistence.'}
}
function Assert-OctoberSnapshot($Value,[string]$RunId,[switch]$Quality,[string]$Reviewer){
    $parsed=[guid]::Empty
    if(-not [guid]::TryParse([string]$Value.runId,[ref]$parsed) -or $parsed -eq [guid]::Empty -or
        ($RunId -and [string]$Value.runId -cne $RunId) -or [string]$Value.requestedAsOf -cne '2026-10-08' -or
        $Value.featureSetVersion -cne 'TECHNICAL_V1' -or
        $Value.sourceManifestHash -cne '50e0749dfdfbc3e370f4cd5d0f23069021154bf69baafcc815cffcb509cbbb62'){throw 'Persisted snapshot identity/manifest mismatch.'}
    foreach($pair in @(@('instrumentCount',500),@('persistedFeatureCount',487),@('withheldCount',13),@('insufficientHistoryCount',13),@('persistedItemCount',500),@('staleCount',0),@('noEligibleDataCount',0))){
        $v=$Value.($pair[0]);if(($v -isnot [int] -and $v -isnot [long]) -or $v -ne $pair[1]){throw "Unexpected persisted count: $($pair[0])"}
    }
    if($Quality){
        if($Value.status -cne 'ELIGIBLE' -or $Value.completeVectorCount -ne 487 -or
            $Value.partialVectorViolationCount -ne 0 -or $Value.withheldVectorViolationCount -ne 0 -or
            $Value.recomputedManifestHash -cne $Value.sourceManifestHash -or
            $Value.manifestMatches -isnot [bool] -or -not $Value.manifestMatches){throw 'Persisted quality/manifest verification failed.'}
        Assert-DailyReviewFalse $Value.databaseWritesPerformed 'quality.databaseWritesPerformed'
    }else{
        if($Value.status -cne 'COMPLETED' -or [string]$Value.universeSnapshotId -cne '68117add-3ebe-4681-82fc-ff5613ecd869' -or
            $Value.reviewedBy -cne $Reviewer -or $Value.databaseWritesPerformed -isnot [bool] -or
            $Value.signalsCreated -ne 0 -or $Value.ordersCreated -ne 0){throw 'Unexpected snapshot write response or side effects.'}
    }
}
