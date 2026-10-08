# Definitions only. One reviewed finding; never executable instructions from attached evidence.
Set-StrictMode -Version Latest
. (Join-Path $PSScriptRoot 'DailyQualityFollowUp.ps1')
function Assert-PolicyBzrEvidence($Evidence){
    if($Evidence.version -cne 'DAILY_QUALITY_FOLLOW_UP_V1' -or $Evidence.status -cne 'CAPTURED_REVIEW_REQUIRED'){throw 'Wrong evidence version/status.'}
    Assert-DailyReviewScope $Evidence.dailyRun
    Assert-DailyReviewQuality $Evidence.quality
    $summary=Get-DailyReviewFeatureSummary $Evidence.features
    if(-not $summary.manifestMatchesOriginalAutomation -or $summary.eligible -ne 487 -or $summary.withheld -ne 13){throw 'Reviewed feature checkpoint changed.'}
    Assert-DailyReviewOfficialEvidence $Evidence.officialEvidence
    foreach($flag in @('resolutionWriteRequested','featurePersistenceRequested','modelInvocationRequested','orderActionRequested')){Assert-DailyReviewFalse $Evidence.$flag $flag}
    $item=$Evidence.officialEvidence.findings[0]
    if($item.evidenceStatus -cne 'OFFICIAL_PRICES_MATCH' -or $item.isin -cne 'INE417T01026' -or
        $item.officialSymbol -cne 'POLICYBZR' -or $item.matchBasis -cne 'ISIN' -or $item.officialSeries -cne 'EQ' -or
        $item.officialPreviousClose -ne 1886.3 -or $item.officialClose -ne 1207.2 -or
        @($item.corporateActionTypes).Count -ne 0 -or $item.sourceUrl -cne 'https://archives.nseindia.com/content/cm/BhavCopy_NSE_CM_0_0_0_20260924_F_0000.csv.zip'){
        throw 'Exact reviewed official price/identity/source evidence is required.'
    }
}
function New-PolicyBzrResolutionBody([string]$Reviewer){
    if([string]::IsNullOrWhiteSpace($Reviewer) -or $Reviewer.Length -gt 120){throw 'A reviewer name of 1-120 characters is required.'}
    if($Reviewer.Trim() -match '^(RESOLVE|PERSIST|CONFIRM|YES|IDLE)(\s|$)'){throw 'Enter your actual reviewer name, not the confirmation phrase.'}
    [ordered]@{jobId='eebff875-3621-4064-a2ea-9de0b269681e';symbol='POLICYBZR';findingType='LARGE_MOVE';findingDate='2026-09-24';relatedDate=$null
        resolutionType='VERIFIED_EXCHANGE_MOVE';evidenceSource='NSE UDIFF bhavcopy; reviewed captured ISIN comparison'
        evidenceUrl='https://archives.nseindia.com/content/cm/BhavCopy_NSE_CM_0_0_0_20260924_F_0000.csv.zip'
        notes='Reviewed evidence SHA256 190CE4143E39B84AADC14B34570E2278D7AB60F78448BEB2D81A0FB9910B4349. ISIN INE417T01026, EQ; stored and NSE previous close 1886.30, close 1207.20, return -36.0017 percent. Preserve raw candles. No exclusion, feature persistence, model fitting or trading approval. No corporate action recorded in captured evidence; not proof that none exists.'
        reviewedBy=$Reviewer.Trim();exclusionFrom=$null;exclusionTo=$null}
}
function Get-PolicyBzrCurrentResolution($Rows,$Body){
    $targets=@($Rows|Where-Object {$_.symbol -ceq 'POLICYBZR' -and $_.findingType -ceq 'LARGE_MOVE' -and [string]$_.findingDate -ceq '2026-09-24'})
    if($targets.Count -eq 0){return $null}
    if($targets.Count -ne 1){throw 'Multiple current resolutions; manual reconciliation required.'}
    $r=$targets[0]
    foreach($field in @('jobId','symbol','findingType','findingDate','resolutionType','evidenceSource','evidenceUrl','notes')){
        if([string]$r.$field -cne [string]$Body[$field]){throw 'Existing resolution conflicts with this reviewed payload; no replacement or revocation allowed.'}
    }
    foreach($field in @('relatedDate','exclusionFrom','exclusionTo')){if($null -ne $r.$field){throw 'Existing resolution has unexpected date/exclusion.'}}
    $id=[guid]::Empty
    if(-not [guid]::TryParse([string]$r.id,[ref]$id) -or $id -eq [guid]::Empty -or [string]::IsNullOrWhiteSpace($r.reviewedBy)){throw 'Resolution identity/reviewer missing.'}
    if($r.allowsTraining -isnot [bool] -or -not $r.allowsTraining){throw 'Unexpected finding-level resolution flag; manual review required.'}
    return $r
}
function Assert-PolicyBzrOpenFinding($Quality){
    Assert-DailyReviewQuality $Quality
    if($Quality.qualityStatus -cne 'REVIEW' -or $Quality.unresolvedFindingCount -ne 1 -or $Quality.reviewInstrumentCount -ne 1){throw 'The single open quality finding changed.'}
    foreach($name in @('blockingInstrumentCount','missingProviderDataInstrumentCount','duplicateRows','invalidRows')){if($Quality.$name -ne 0){throw 'Additional data-quality blockers appeared.'}}
    $items=@($Quality.qualityFindings)
    if($items.Count -ne 1 -or $items[0].symbol -cne 'POLICYBZR' -or $items[0].findingType -cne 'LARGE_MOVE' -or
        [string]$items[0].findingDate -cne '2026-09-24' -or $items[0].reviewStatus -cne 'OPEN' -or
        $null -ne $items[0].relatedDate -or @($items[0].corporateActionTypes).Count -ne 0){throw 'Finding status/identity/action evidence changed.'}
}
function Test-PolicyBzrFeatureReadiness($Preview){
    Assert-DailyReviewFalse $Preview.databaseWritesPerformed 'preview.databaseWritesPerformed'
    if([string]$Preview.targetDate -cne '2026-10-08' -or [string]$Preview.dailyRunId -cne 'eebff875-3621-4064-a2ea-9de0b269681e' -or
        [string]$Preview.universeSnapshotId -cne '68117add-3ebe-4681-82fc-ff5613ecd869'){throw 'Post-review preview identity changed.'}
    if($Preview.status -cne 'READY'){return $false}
    if($Preview.dailyQualityStatus -cne 'PASS' -or $Preview.dailyRunStatus -cne 'COMPLETED' -or
        $Preview.dailyManifestHash -cne '655ea0fdf52cd86fc68d825d2fb2146e1e14da255c8257edd9b8e2bc941364ee' -or
        $Preview.featureManifestHash -cne '50e0749dfdfbc3e370f4cd5d0f23069021154bf69baafcc815cffcb509cbbb62' -or
        $Preview.featureSetVersion -cne 'TECHNICAL_V1' -or $Preview.eligibleCount -ne 487 -or $Preview.insufficientHistoryCount -ne 13 -or
        $Preview.featureInstrumentCount -ne 500 -or $Preview.dailyInstrumentCount -ne 500 -or $Preview.targetDateCandleCount -ne 500 -or
        $Preview.persistenceAction -cne 'READY_TO_PERSIST' -or $null -ne $Preview.existingFeatureSnapshotRunId -or
        @($Preview.failedCheckpoints).Count -ne 0){throw 'READY preview differs from reviewed checkpoint; no persistence allowed.'}
    foreach($field in @('failedChunks','rejectedRows','blockingInstrumentCount','missingProviderDataInstrumentCount','reviewInstrumentCount','duplicateRowCount','invalidRowCount','unresolvedFindingCount','truncatedFindingCount','staleCount','noEligibleDataCount')){if($Preview.$field -ne 0){throw "READY preview has blocker: $field"}}
    return $true
}
