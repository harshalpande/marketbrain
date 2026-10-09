# Offline only: synthetic fixture, mocked HTTP/digest/confirmation. Never contacts the application.
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'NumericalHistoryEvidence.ps1')
. (Join-Path $PSScriptRoot 'ReviewedFeatureReconciliation.ps1')
$root=Join-Path ([IO.Path]::GetTempPath()) ('marketbrain-reconciliation-test-'+[guid]::NewGuid().ToString('N'))
[void](New-Item -ItemType Directory -Path $root)
$fixturePath=Join-Path $root 'evidence.json'
$snapshotId='fc15cbe7-15c7-46ab-989e-f09ba7978858';$dailyId='eebff875-3621-4064-a2ea-9de0b269681e'
$manifest='50e0749dfdfbc3e370f4cd5d0f23069021154bf69baafcc815cffcb509cbbb62'
$digest='128C921E4C21734E9CC0801B39735ECDF9152A43C9906FB3695FEE44ACB62324'
$summary=[pscustomobject]@{status='COMPLETED';runId=$snapshotId;universeSnapshotId='68117add-3ebe-4681-82fc-ff5613ecd869';requestedAsOf='2026-10-08';featureSetVersion='TECHNICAL_V1';sourceManifestHash=$manifest;reviewedBy='Harshal Pande';instrumentCount=500;persistedFeatureCount=487;withheldCount=13;insufficientHistoryCount=13;staleCount=0;noEligibleDataCount=0;persistedItemCount=500;signalsCreated=0;ordersCreated=0;databaseWritesPerformed=$true}
$quality=[pscustomobject]@{status='ELIGIBLE';runId=$snapshotId;requestedAsOf='2026-10-08';featureSetVersion='TECHNICAL_V1';sourceManifestHash=$manifest;recomputedManifestHash=$manifest;instrumentCount=500;persistedFeatureCount=487;withheldCount=13;persistedItemCount=500;completeVectorCount=487;insufficientHistoryCount=13;staleCount=0;noEligibleDataCount=0;partialVectorViolationCount=0;withheldVectorViolationCount=0;manifestMatches=$true;databaseWritesPerformed=$false}
$evidence=[ordered]@{version='REVIEWED_OCTOBER_FEATURE_SNAPSHOT_V1';status='FEATURE_SNAPSHOT_VERIFIED_RELEASE_BLOCKED';writeState='SNAPSHOT_VERIFIED';runId=$snapshotId;failureStage=$null;reviewedBy='Harshal Pande';postResponse=$summary;persistedQuality=$quality;requests=@(@{method='Post';status='RETURNED'});priceChangeRequested=$false;resolutionChangeRequested=$false;exclusionRequested=$false;schedulerResetRequested=$false;modelOrTradeRequested=$false}
Save-NumericalHistoryReport $evidence $fixturePath -Compact
$state=[pscustomobject]@{mode='preview';checks=0;posts=0;calls=0;done=$false;gets=0}
function Check([bool]$Value,[string]$Name){if(-not $Value){throw "Failed: $Name"};$state.checks++}
function Get-FileHash {param($LiteralPath);if($LiteralPath -ne $fixturePath){throw 'Unexpected evidence'};[pscustomobject]@{Hash=if($state.mode -eq 'hash'){'bad'}else{$digest}}}
function Read-Host {param($Prompt);if($state.mode -eq 'cancel'){'NO'}else{'RECONCILE FEATURES 2026-10-08'}}
function Response([switch]$Write){
    [pscustomobject]@{version='REVIEWED_FEATURE_RECONCILIATION_V1';status=if($Write){'RECONCILED'}elseif($state.done){'ALREADY_RECONCILED'}else{'READY_TO_RECONCILE'};targetDate='2026-10-08';dailyRunId=$dailyId;featureSnapshotRunId=$snapshotId;featureManifestHash=$manifest;reconciliationId=if($state.done){'f98f70aa-8cb4-40dc-9758-ea4ef0606d56'}else{$null};reviewedBy=if($state.done){'Harshal Pande'}else{$null};evidenceSha256=$digest;automationStatus=if($state.done){'COMPLETED'}else{'REVIEW_REQUIRED'};eligibleCount=487;withheldCount=13;completionNotificationStatus=$null;databaseWritesPerformed=[bool]$Write;snapshotWrites=0;signalsCreated=0;ordersCreated=0}
}
function Invoke-RestMethod {
    param($Uri,$Method,$TimeoutSec,$MaximumRedirection,$ErrorAction,$ContentType,$Body)
    $state.calls++
    if($Uri -notlike 'http://127.0.0.1:8080/*' -or $MaximumRedirection -ne 0){throw 'Unexpected HTTP authority.'}
    if($Uri -like '*/actuator/health'){return @{status=if($state.mode -eq 'health'){'DOWN'}else{'UP'}}}
    if($Uri -like '*/reviewed-reconciliation'){
        if($Method -eq 'Post'){
            Check ($TimeoutSec -eq 240 -and $ContentType -ceq 'application/json') 'bounded JSON write'
            $sent=$Body|ConvertFrom-Json;Check ($sent.evidenceSha256 -ceq $digest -and $sent.reviewedBy -ceq 'Harshal Pande') 'exact request body'
            $state.posts++;$state.done=$true
            if($state.mode -eq 'unknown'){throw [TimeoutException]::new('Committed, acknowledgement lost')}
            $r=Response -Write
            if($state.mode -eq 'postMismatch'){$r.featureSnapshotRunId=[guid]::Empty.ToString()};return $r
        }
        if($Method -ne 'Get'){throw 'Forbidden method.'};$state.gets++
        if($state.mode -eq 'conflict' -or ($state.mode -eq 'readbackFailure' -and $state.gets -gt 1)){throw 'Simulated conflict/quality change'}
        $r=Response
        if($state.mode -eq 'mismatch'){$r.featureManifestHash='bad'}
        if($state.mode -eq 'writeFlag'){$r.databaseWritesPerformed=$true};return $r
    }
    if($Uri -like '*/daily-automation/status?targetDate=2026-10-08'){
        if($Method -ne 'Get'){throw 'Unexpected write'}
        return @{status='COMPLETED';targetDate='2026-10-08';dailyRunId=$dailyId;featureSnapshotRunId=$snapshotId;featureManifestHash=$manifest;lastErrorCode=$null;eligibleCount=487;withheldCount=13;attempts=if($state.mode -eq 'automationMismatch'){2}else{1};notificationStatus='PENDING'}
    }
    throw 'Unexpected route: snapshot generation, raw data, notification sending and trading routes are forbidden.'
}
foreach($mode in @('preview','apply','already','hash','cancel','reviewer','health','conflict','mismatch','writeFlag','unknown','postMismatch','readbackFailure','automationMismatch')){
    $state.mode=$mode;$state.posts=0;$state.calls=0;$state.gets=0;$state.done=$mode -eq 'already';$failed=$false
    $dir=Join-Path $root $mode;$reviewer=if($mode -eq 'reviewer'){'RECONCILE FEATURES 2026-10-08'}else{'Harshal Pande'}
    try{& (Join-Path $PSScriptRoot 'ReconcileReviewedOctoberFeatures.ps1') -EvidencePath $fixturePath -ReviewedBy $reviewer -Apply:($mode -notin @('preview','already')) -OutputDirectory $dir|Out-Null}catch{$failed=$true}
    $files=@(Get-ChildItem -LiteralPath $dir -Filter '*.json');Check ($files.Count -eq 1) "$mode one report"
    $r=Get-Content -LiteralPath $files[0].FullName -Raw|ConvertFrom-Json
    Check ($failed -eq ($mode -notin @('preview','apply','already','cancel'))) "$mode expected failure"
    $writes=if($mode -in @('apply','unknown','postMismatch','readbackFailure','automationMismatch')){1}else{0}
    Check ($state.posts -eq $writes) "$mode at most one write"
    Check (-not $r.snapshotPersistenceRequested -and -not $r.priceChangeRequested -and -not $r.resolutionChangeRequested -and -not $r.modelOrTradeRequested) "$mode no scope expansion"
    if($mode -in @('hash','reviewer')){Check ($state.calls -eq 0) "$mode early stop"}
    if($mode -in @('apply','already')){Check ($r.status -ceq 'AUTOMATION_RECONCILED_RELEASE_BLOCKED') "$mode verified";Check ($r.automation.notificationStatus -ceq 'PENDING') 'notification status not fabricated as sent'}
    if($mode -in @('unknown','postMismatch')){Check ($r.writeState -ceq 'UNKNOWN_PENDING_RECONCILIATION') 'uncertain outcome retained'}
    if($mode -eq 'readbackFailure'){Check ($r.writeState -ceq 'ACKNOWLEDGED_NOT_YET_VERIFIED') 'no rollback claim'}
    if($mode -eq 'unknown'){
        $state.mode='reconcile'
        & (Join-Path $PSScriptRoot 'ReconcileReviewedOctoberFeatures.ps1') -EvidencePath $fixturePath -OutputDirectory (Join-Path $root 'reconcile')|Out-Null
        Check ($state.posts -eq 1) 'read-only unknown acknowledgement recovery'
    }
}
$state.done=$true
foreach($pair in @(@('ordersCreated',1),@('snapshotWrites',1),@('signalsCreated','0'),@('databaseWritesPerformed','false'),@('reconciliationId',[guid]::Empty.ToString()),@('automationStatus','RUNNING'),@('targetDate','2026-10-09'),@('evidenceSha256','bad'))){
    $r=Response;$r.($pair[0])=$pair[1];$failed=$false;try{Assert-ReconciliationResponse $r}catch{$failed=$true};Check $failed ('response mutation '+$pair[0])
}
Write-Host "PASS: $($state.checks) offline reconciliation assertions. Fixtures: $root"
