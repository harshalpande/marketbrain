# Offline only: mocked HTTP, confirmation and evidence digest; no runtime calls or writes.
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'NumericalHistoryEvidence.ps1')
. (Join-Path $PSScriptRoot 'ReviewedPolicyBzrResolution.ps1')
$root=Join-Path ([IO.Path]::GetTempPath()) ('marketbrain-resolution-test-'+[guid]::NewGuid().ToString('N'))
[void](New-Item -ItemType Directory -Path $root)
$fixturePath=Join-Path $root 'evidence.json'
$run=[pscustomobject]@{runId='eebff875-3621-4064-a2ea-9de0b269681e';status='COMPLETED';requestedFrom='2026-09-19';targetDate='2026-10-08';instruments=500;universeSnapshotId='68117add-3ebe-4681-82fc-ff5613ecd869';manifestHash='655ea0fdf52cd86fc68d825d2fb2146e1e14da255c8257edd9b8e2bc941364ee'}
$quality=[pscustomobject]@{jobId=$run.runId;jobStatus='COMPLETED';requestedFrom='2026-09-19';requestedTo='2026-10-08';instrumentCount=500;providerSpotCheckRequested=$false;truncatedFindingCount=0;qualityStatus='REVIEW';unresolvedFindingCount=1;reviewInstrumentCount=1;blockingInstrumentCount=0;missingProviderDataInstrumentCount=0;duplicateRows=0;invalidRows=0
    largeMoves=@([pscustomobject]@{symbol='POLICYBZR';tradingDate='2026-09-24';previousClose=1886.3;close=1207.2})
    qualityFindings=@([pscustomobject]@{symbol='POLICYBZR';findingType='LARGE_MOVE';findingDate='2026-09-24';reviewStatus='OPEN';relatedDate=$null;corporateActionTypes=@()})}
$items=@(foreach($i in 1..500){$short=$i -gt 487;$n=if($short){200}else{300};[pscustomobject]@{symbol=('FIXTURE'+$i);status=if($short){'INSUFFICIENT_HISTORY'}else{'ELIGIBLE'};requestedAsOf='2026-10-08';effectiveAsOf='2026-10-08';featureSetVersion='TECHNICAL_V1';canonicalObservationCount=$n;eligibleObservationCount=$n;excludedObservationCount=0;databaseWritesPerformed=$false;features=if($short){$null}else{@{fixture=1}}}})
$features=[pscustomobject]@{status='REVIEW_REQUIRED';featureSetVersion='TECHNICAL_V1';requestedAsOf='2026-10-08';universeSnapshotId=$run.universeSnapshotId;instrumentCount=500;instruments=$items;manifestHash='50e0749dfdfbc3e370f4cd5d0f23069021154bf69baafcc815cffcb509cbbb62';databaseWritesPerformed=$false;eligibleCount=487;staleCount=0;insufficientHistoryCount=13;noEligibleDataCount=0;featureVectorCount=487}
$official=[pscustomobject]@{jobId=$run.runId;findingCount=1;sourceRequestCount=1;resolutionsWritten=$false;findings=@([pscustomobject]@{symbol='POLICYBZR';findingDate='2026-09-24';storedPreviousClose=1886.3;storedClose=1207.2;evidenceStatus='OFFICIAL_PRICES_MATCH';isin='INE417T01026';officialSymbol='POLICYBZR';matchBasis='ISIN';officialSeries='EQ';officialPreviousClose=1886.3;officialClose=1207.2;corporateActionTypes=@();sourceUrl='https://archives.nseindia.com/content/cm/BhavCopy_NSE_CM_0_0_0_20260924_F_0000.csv.zip'})}
$evidence=[ordered]@{version='DAILY_QUALITY_FOLLOW_UP_V1';status='CAPTURED_REVIEW_REQUIRED';dailyRun=$run;quality=$quality;features=$features;officialEvidence=$official;resolutionWriteRequested=$false;featurePersistenceRequested=$false;modelInvocationRequested=$false;orderActionRequested=$false}
Save-NumericalHistoryReport $evidence $fixturePath -Compact
$state=[pscustomobject]@{mode='preview';record=$null;posts=0;calls=0;checks=0}
function Check([bool]$Value,[string]$Name){if(-not $Value){throw "Failed: $Name"};$state.checks++}
function Get-FileHash {param($LiteralPath)
    if($LiteralPath -ne $fixturePath){throw 'Unexpected hash target.'}
    [pscustomobject]@{Hash=if($state.mode -eq 'hash'){'BAD'}else{'190CE4143E39B84AADC14B34570E2278D7AB60F78448BEB2D81A0FB9910B4349'}}
}
function Read-Host {param($Prompt);if($state.mode -eq 'cancel'){'NO'}else{'RESOLVE POLICYBZR 2026-09-24'}}
function ResolutionFixture($Body){
    $r=$Body|ConvertTo-Json|ConvertFrom-Json
    $r|Add-Member id '6b0b1e92-6d25-479a-8e2f-92e327c9c3ce'
    $r|Add-Member allowsTraining $true
    return $r
}
function Invoke-RestMethod {
    param($Uri,$Method,$TimeoutSec,$MaximumRedirection,$ErrorAction,$ContentType,$Body)
    $state.calls++
    if($MaximumRedirection -ne 0 -or $Uri -notlike 'http://127.0.0.1:8080/*'){throw 'Unexpected HTTP authority.'}
    if($Method -eq 'Post'){
        if($Uri -cne 'http://127.0.0.1:8080/api/v1/market-data/backfills/quality-resolutions' -or $TimeoutSec -ne 30){throw 'Unexpected write endpoint.'}
        $sent=$Body|ConvertFrom-Json
        Check ($sent.resolutionType -ceq 'VERIFIED_EXCHANGE_MOVE' -and $null -eq $sent.exclusionFrom -and $null -eq $sent.exclusionTo) 'one finding only, no exclusion'
        $state.posts++;$state.record=ResolutionFixture $sent
        if($state.mode -eq 'uncertain'){throw [TimeoutException]::new('Simulated lost acknowledgement after commit')}
        return $state.record
    }
    if($Method -ne 'Get'){throw 'Unexpected method.'}
    if($Uri -like '*/actuator/health'){return @{status='UP'}}
    if($Uri -like '*/runs/status?*'){return $run}
    if($Uri -like '*/quality-resolutions?*'){return @($state.record|Where-Object {$null -ne $_})}
    if($Uri -like '*/daily-automation/status?*'){return @{status=if($state.mode -eq 'active'){'RUNNING'}else{'REVIEW_REQUIRED'};dailyRunId=$run.runId;targetDate='2026-10-08';featureSnapshotRunId=$null}}
    if($Uri -like '*/quality?*'){
        if($Uri -notlike '*providerSpotCheck=false'){throw 'Provider fetch forbidden.'}
        $q=$quality|ConvertTo-Json -Depth 6|ConvertFrom-Json
        if($state.mode -eq 'price'){$q.largeMoves[0].close=1200}
        if($state.mode -eq 'action'){$q.qualityFindings[0].corporateActionTypes=@('SPLIT')};return $q
    }
    if($Uri -like '*/daily-automation-preview?*'){
        $r=[pscustomobject]@{databaseWritesPerformed=$false;targetDate='2026-10-08';dailyRunId=$run.runId;universeSnapshotId=$run.universeSnapshotId;status='READY';dailyQualityStatus='PASS';dailyRunStatus='COMPLETED';dailyManifestHash=$run.manifestHash;featureManifestHash=$features.manifestHash;featureSetVersion='TECHNICAL_V1';eligibleCount=487;insufficientHistoryCount=13;featureInstrumentCount=500;dailyInstrumentCount=500;targetDateCandleCount=500;persistenceAction='READY_TO_PERSIST';existingFeatureSnapshotRunId=$null;failedCheckpoints=@();failedChunks=0;rejectedRows=0;blockingInstrumentCount=0;missingProviderDataInstrumentCount=0;reviewInstrumentCount=0;duplicateRowCount=0;invalidRowCount=0;unresolvedFindingCount=0;truncatedFindingCount=0;staleCount=0;noEligibleDataCount=0}
        if($state.mode -eq 'notReady'){$r.status='REVIEW_REQUIRED';$r.failedCheckpoints=@('OTHER')}
        if($state.mode -eq 'previewFail'){throw [TimeoutException]::new('Preview timeout')};return $r
    }
    throw 'Unexpected endpoint.'
}
foreach($mode in @('preview','apply','existing','conflict','hash','cancel','active','price','action','uncertain','notReady','previewFail')){
    $state.mode=$mode;$state.record=$null;$state.posts=0;$state.calls=0;$failed=$false
    if($mode -in @('existing','conflict')){$state.record=ResolutionFixture (New-PolicyBzrResolutionBody 'Fixture reviewer');if($mode -eq 'conflict'){$state.record.notes='Conflicting prior evidence'}}
    $dir=Join-Path $root $mode
    try{& (Join-Path $PSScriptRoot 'ResolveReviewedPolicyBzrMove.ps1') -EvidencePath $fixturePath -ReviewedBy 'Fixture reviewer' -Apply:($mode -ne 'preview') -OutputDirectory $dir|Out-Null}catch{$failed=$true}
    $files=@(Get-ChildItem -LiteralPath $dir -Filter '*.json')
    Check ($files.Count -eq 1) "$mode one report"
    $r=Get-Content -LiteralPath $files[0].FullName -Raw|ConvertFrom-Json
    Check ($failed -eq ($mode -in @('conflict','hash','active','price','action','uncertain','previewFail'))) "$mode expected failure"
    $writes=if($mode -in @('apply','uncertain','notReady','previewFail')){1}else{0}
    Check ($state.posts -eq $writes) "$mode bounded write count"
    Check (-not $r.featurePersistenceRequested -and -not $r.priceChangeRequested -and -not $r.exclusionRequested -and -not $r.modelOrTradeRequested) "$mode no expanded action"
    if($mode -eq 'hash'){Check ($state.calls -eq 0) 'bad evidence stops before HTTP'}
    if($mode -in @('apply','existing')){Check ($r.status -ceq 'RESOLUTION_VERIFIED_FEATURE_READY_NOT_PERSISTED') "$mode ready but not published"}
    if($mode -eq 'notReady'){Check ($r.status -ceq 'RESOLUTION_VERIFIED_FEATURE_REVIEW_REQUIRED') 'valid resolution does not waive other blockers'}
    if($mode -eq 'previewFail'){Check ($r.writeState -ceq 'RESOLUTION_VERIFIED') 'preview failure does not imply rollback'}
    if($mode -eq 'uncertain'){
        Check ($r.writeState -ceq 'UNKNOWN_PENDING_RECONCILIATION') 'lost ack stays unknown'
        $state.mode='reconcile'
        & (Join-Path $PSScriptRoot 'ResolveReviewedPolicyBzrMove.ps1') -EvidencePath $fixturePath -ReviewedBy 'Fixture reviewer' -OutputDirectory (Join-Path $root 'reconcile')|Out-Null
        Check ($state.posts -eq 1) 'read-only reconciliation never repeats POST'
    }
}
Write-Host "PASS: $($state.checks) offline reviewed resolution assertions. Fixtures: $root"
