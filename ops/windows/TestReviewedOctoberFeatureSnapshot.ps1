# Offline only: mocked HTTP, confirmation and evidence digest; no runtime calls or writes.
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'NumericalHistoryEvidence.ps1')
. (Join-Path $PSScriptRoot 'ReviewedOctoberFeatureSnapshot.ps1')
$root=Join-Path ([IO.Path]::GetTempPath()) ('marketbrain-snapshot-test-'+[guid]::NewGuid().ToString('N'))
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

$resolution=New-PolicyBzrResolutionBody 'Fixture reviewer'|ConvertTo-Json|ConvertFrom-Json
$resolution|Add-Member id '19bc5ced-9ec0-497b-a2d2-ff86768249cd'
$resolution|Add-Member allowsTraining $true
# Preserve the real audit caveat; it must not be silently repaired or mistaken for a blocker-free identity.
$resolution.reviewedBy='RESOLVE POLICYBZR 2026-09-24'
$preview=[pscustomobject]@{databaseWritesPerformed=$false;targetDate='2026-10-08';dailyRunId=$run.runId;universeSnapshotId=$run.universeSnapshotId;status='READY';dailyQualityStatus='PASS';dailyRunStatus='COMPLETED';dailyManifestHash=$run.manifestHash;featureManifestHash=$features.manifestHash;featureSetVersion='TECHNICAL_V1';eligibleCount=487;insufficientHistoryCount=13;featureInstrumentCount=500;dailyInstrumentCount=500;targetDateCandleCount=500;persistenceAction='READY_TO_PERSIST';existingFeatureSnapshotRunId=$null;existingFeatureSnapshotStatus=$null;failedCheckpoints=@();failedChunks=0;rejectedRows=0;blockingInstrumentCount=0;missingProviderDataInstrumentCount=0;reviewInstrumentCount=0;duplicateRowCount=0;invalidRowCount=0;unresolvedFindingCount=0;truncatedFindingCount=0;staleCount=0;noEligibleDataCount=0;totalChunks=500;completedChunks=500;acceptedRows=6500;pointInTimeSafe=$true}
$accepted=[ordered]@{version='POLICYBZR_REVIEWED_RESOLUTION_V1';status='RESOLUTION_VERIFIED_FEATURE_READY_NOT_PERSISTED';writeState='RESOLUTION_VERIFIED';failureStage=$null;evidence=$evidence;currentAfter=@($resolution);featurePreview=$preview;featurePersistenceRequested=$false;priceChangeRequested=$false;exclusionRequested=$false;modelOrTradeRequested=$false}
Save-NumericalHistoryReport $accepted $fixturePath -Compact
$state=[pscustomobject]@{mode='preview';posts=0;calls=0;checks=0;stored=$false;resolutionReads=0}
function Check([bool]$Value,[string]$Name){if(-not $Value){throw "Failed: $Name"};$state.checks++}
function Clone($Value){return ($Value|ConvertTo-Json -Depth 16|ConvertFrom-Json)}
function Get-FileHash {param($LiteralPath)
    if($LiteralPath -ne $fixturePath){throw 'Unexpected hash target.'}
    [pscustomobject]@{Hash=if($state.mode -eq 'hash'){'BAD'}else{'91F75E59F91A17696687801CECBCA281EDBA6BD614173E8E982C645B0C6FC69F'}}
}
function Read-Host {param($Prompt);if($state.mode -eq 'cancel'){'NO'}else{'PERSIST FEATURES 2026-10-08'}}
$storedId='32315e04-16b1-4bbd-bae7-8d9b6dcb3fae'
function SnapshotFixture {
    [pscustomobject]@{status='COMPLETED';runId=$storedId;universeSnapshotId=$run.universeSnapshotId;requestedAsOf='2026-10-08';featureSetVersion='TECHNICAL_V1';sourceManifestHash=$features.manifestHash;reviewedBy='Fixture A & B';instrumentCount=500;persistedFeatureCount=487;withheldCount=13;insufficientHistoryCount=13;staleCount=0;noEligibleDataCount=0;persistedItemCount=500;signalsCreated=0;ordersCreated=0;databaseWritesPerformed=$true}
}
function QualityFixture {
    [pscustomobject]@{status='ELIGIBLE';runId=$storedId;requestedAsOf='2026-10-08';featureSetVersion='TECHNICAL_V1';sourceManifestHash=$features.manifestHash;recomputedManifestHash=$features.manifestHash;instrumentCount=500;persistedFeatureCount=487;withheldCount=13;persistedItemCount=500;completeVectorCount=487;insufficientHistoryCount=13;staleCount=0;noEligibleDataCount=0;partialVectorViolationCount=0;withheldVectorViolationCount=0;manifestMatches=$true;databaseWritesPerformed=$false}
}
function Invoke-RestMethod {
    param($Uri,$Method,$TimeoutSec,$MaximumRedirection,$ErrorAction)
    $state.calls++
    if($MaximumRedirection -ne 0 -or $Uri -notlike 'http://127.0.0.1:8080/*'){throw 'Unexpected HTTP authority.'}
    if($Method -eq 'Post'){
        Check ($Uri -ceq ('http://127.0.0.1:8080/api/v1/features/snapshots?asOf=2026-10-08&expectedManifestHash='+$features.manifestHash+'&reviewedBy=Fixture%20A%20%26%20B') -and $TimeoutSec -eq 900) 'exact encoded write scope and timeout'
        $state.posts++;$state.stored=$true
        if($state.mode -eq 'uncertain'){throw [TimeoutException]::new('Simulated committed write with lost acknowledgement')}
        $r=SnapshotFixture
        if($state.mode -eq 'postMismatch'){$r.sourceManifestHash='bad'}
        if($state.mode -eq 'postOrders'){$r.ordersCreated=1}
        return $r
    }
    if($Method -ne 'Get'){throw 'Unexpected method.'}
    if($Uri -like '*/actuator/health'){return @{status=if($state.mode -eq 'health'){'DOWN'}else{'UP'}}}
    if($Uri -like '*/daily-automation/status?*'){return @{targetDate='2026-10-08';dailyRunId=$run.runId;status=if($state.mode -eq 'active'){'RUNNING'}else{'REVIEW_REQUIRED'};featureSnapshotRunId=$null}}
    if($Uri -like '*/quality-resolutions?*'){
        $state.resolutionReads++;$r=Clone $resolution
        if($state.mode -eq 'resolution' -or ($state.mode -eq 'race' -and $state.resolutionReads -gt 1)){$r.id='32315e04-16b1-4bbd-bae7-8d9b6dcb3fae'}
        return @($r)
    }
    if($Uri -like '*/daily-automation-preview?*'){
        Check ($TimeoutSec -eq 660) 'bounded fresh preview'
        if($state.mode -eq 'previewTimeout'){throw [TimeoutException]::new('Preview timeout')}
        $r=Clone $preview
        if($state.stored){$r.persistenceAction='ALREADY_PERSISTED';$r.existingFeatureSnapshotStatus='COMPLETED';$r.existingFeatureSnapshotRunId=$storedId}
        if($state.mode -eq 'manifest'){$r.featureManifestHash='bad'}
        if($state.mode -eq 'notReady'){$r.status='REVIEW_REQUIRED'}
        if($state.mode -eq 'existingBad'){$r.existingFeatureSnapshotStatus='WRITING'}
        return $r
    }
    if($Uri -like '*/snapshots/quality?*'){
        Check ($Uri -ceq ("http://127.0.0.1:8080/api/v1/features/snapshots/quality?runId=$storedId&expectedManifestHash="+$features.manifestHash) -and $TimeoutSec -eq 180) 'exact quality scope'
        if($state.mode -eq 'qualityTimeout'){throw [TimeoutException]::new('Quality timeout')}
        $r=QualityFixture
        if($state.mode -eq 'qualityBad'){$r.completeVectorCount=486}
        return $r
    }
    throw 'Unexpected endpoint; no provider/model/order/SQL endpoint permitted.'
}
foreach($mode in @('preview','apply','existing','existingBad','hash','cancel','active','health','resolution','race','manifest','notReady','previewTimeout','uncertain','postMismatch','postOrders','qualityBad','qualityTimeout','reviewer')){
    $state.mode=$mode;$state.posts=0;$state.calls=0;$state.resolutionReads=0;$state.stored=$mode -in @('existing','existingBad');$failed=$false
    $dir=Join-Path $root $mode;$reviewer=if($mode -eq 'reviewer'){'PERSIST FEATURES 2026-10-08'}else{'Fixture A & B'}
    try{& (Join-Path $PSScriptRoot 'SaveReviewedOctoberFeatureSnapshot.ps1') -EvidencePath $fixturePath -ReviewedBy $reviewer -Apply:($mode -notin @('preview','existing','existingBad')) -OutputDirectory $dir|Out-Null}catch{$failed=$true}
    $files=@(Get-ChildItem -LiteralPath $dir -Filter '*.json')
    Check ($files.Count -eq 1) "$mode one report"
    $r=Get-Content -LiteralPath $files[0].FullName -Raw|ConvertFrom-Json
    Check ($failed -eq ($mode -notin @('preview','apply','existing','cancel'))) "$mode expected failure"
    $writes=if($mode -in @('apply','uncertain','postMismatch','postOrders','qualityBad','qualityTimeout')){1}else{0}
    Check ($state.posts -eq $writes) "$mode bounded writes"
    Check (-not $r.priceChangeRequested -and -not $r.resolutionChangeRequested -and -not $r.exclusionRequested -and -not $r.schedulerResetRequested -and -not $r.modelOrTradeRequested) "$mode no expansion"
    if($mode -in @('hash','reviewer')){Check ($state.calls -eq 0) "$mode stopped before HTTP"}
    if($mode -in @('apply','existing')){Check ($r.status -ceq 'FEATURE_SNAPSHOT_VERIFIED_RELEASE_BLOCKED' -and $r.writeState -ceq 'SNAPSHOT_VERIFIED') "$mode complete"}
    if($mode -eq 'preview'){Check ($r.status -ceq 'PREVIEW_READY_NO_WRITE') 'preview no implicit apply'}
    if($mode -in @('qualityBad','qualityTimeout')){Check ($r.writeState -ceq 'POST_ACKNOWLEDGED_NOT_YET_VERIFIED') 'readback failure is not a rollback'}
    if($mode -in @('uncertain','postMismatch','postOrders')){Check ($r.writeState -ceq 'UNKNOWN_PENDING_RECONCILIATION') 'uncertain outcome retained'}
    if($mode -eq 'uncertain'){
        $state.mode='reconcile'
        & (Join-Path $PSScriptRoot 'SaveReviewedOctoberFeatureSnapshot.ps1') -EvidencePath $fixturePath -OutputDirectory (Join-Path $root 'reconcile')|Out-Null
        Check ($state.posts -eq 1) 'read-only reconciliation never repeats POST'
        $r=Get-Content (Get-ChildItem (Join-Path $root 'reconcile') -Filter '*.json').FullName -Raw|ConvertFrom-Json
        Check ($r.status -ceq 'FEATURE_SNAPSHOT_VERIFIED_RELEASE_BLOCKED') 'uncertain write reconciled'
    }
}
foreach($name in @('RESOLVE POLICYBZR 2026-09-24','PERSIST FEATURES 2026-10-08','YES','IDLE','')){
    $failed=$false;try{[void](New-PolicyBzrResolutionBody $name)}catch{$failed=$true};Check $failed 'confirmation is not reviewer name'
}
foreach($pair in @(@('dailyQualityStatus','REVIEW'),@('pointInTimeSafe','true'),@('completedChunks',499),@('acceptedRows',6499),@('unresolvedFindingCount',1),@('databaseWritesPerformed',$true),@('eligibleCount',488),@('existingFeatureSnapshotRunId',$storedId))){
    $r=Clone $preview;$r.($pair[0])=$pair[1];$failed=$false
    try{[void](Assert-OctoberSnapshotPreview $r)}catch{$failed=$true};Check $failed ("preview mutation "+$pair[0])
}
foreach($pair in @(@('runId',[guid]::Empty.ToString()),@('requestedAsOf','2026-10-09'),@('status','REVIEW_REQUIRED'),@('persistedItemCount',499),@('withheldCount',12),@('persistedFeatureCount','487'),@('partialVectorViolationCount',1),@('withheldVectorViolationCount',1),@('recomputedManifestHash','bad'),@('manifestMatches','true'),@('databaseWritesPerformed',$true))){
    $r=QualityFixture;$r.($pair[0])=$pair[1];$failed=$false
    try{Assert-OctoberSnapshot $r -RunId $storedId -Quality}catch{$failed=$true};Check $failed ("quality mutation "+$pair[0])
}
Write-Host "PASS: $($state.checks) offline snapshot assertions. Fixtures: $root"
