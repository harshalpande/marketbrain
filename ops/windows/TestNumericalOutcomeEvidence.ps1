#Requires -Version 5.1
$ErrorActionPreference='Stop'
# Reuse and execute the 43 existing offline preflight assertions/fixtures first.
. (Join-Path $PSScriptRoot 'TestNumericalReadinessBundle.ps1')
. (Join-Path $PSScriptRoot 'NumericalOutcomeEvidence.ps1')
$extension=Get-Content (Join-Path $PSScriptRoot '..\data\nse-cm-outcome-calendar-20260606-20260717-v1.json') -Raw | ConvertFrom-Json
$allSessions=@(Get-NumericalOutcomeSessions $calendar $extension)
Assert-Bundle ('2026-06-26' -notin $allSessions -and '2026-06-25' -in $allSessions -and '2026-07-17' -in $allSessions) 'Outcome holiday/bounds wrong.'
function New-OutcomeFixture {
    $p=(New-PriceFixture).result;$p.throughDate='2026-07-17'
    $new=@(foreach($day in $allSessions | Where-Object {$_ -ge '2026-06-06'}){[pscustomobject]@{candleId=([datetime]$day).DayOfYear+1000;date=$day;source='UPSTOX';receivedAt='2026-09-01T00:00:00Z';excluded=$false;open=100;high=120;low=80;close=110;volume=1000}})
    [pscustomobject]@{version='NUMERICAL_OUTCOME_EVIDENCE_V1';status='OUTCOME_EVIDENCE_REVIEW_REQUIRED';datasetRunId='5bdbfcc1-d990-48d8-9e98-d4927596d917';datasetManifestHash=('b'*64);asOf='2026-06-05';outcomeFrom='2026-06-06';outcomeThrough='2026-07-17';offset=0;limit=1
        partial=$false;trainingAuthorized=$false;databaseWritesPerformed=$false;modelCallCount=0;providerCallCount=0;ordersCreated=0;priceEvidence=$p
        instruments=@([pscustomobject]@{instrumentId=1;symbol='FIXTURE';rawRowCount=$new.Count;truncated=$false;canonicalBars=$new})}
}
$f=New-BundleFixture;$before=$f | ConvertTo-Json -Depth 16 -Compress
$review=Get-NumericalOutcomeReview $f (New-OutcomeFixture) $calendar $extension
Assert-Bundle ($review.summary.arithmeticOnlyCount -eq 3 -and $review.summary.blockedOutcomeCount -eq 0) 'Complete stored paths not joined.'
Assert-Bundle ($review.rows[1].labelPreflight.exitDate -eq '2026-06-08' -and $review.rows[2].labelPreflight.exitDate -eq '2026-07-06') '20-session dates incorrect.'
Assert-Bundle ($review.splitPreflight.purgedCount -eq 2 -and $review.splitPreflight.unknownEndCount -eq 0) 'Later validation overlap not purged.'
Assert-Bundle (($f | ConvertTo-Json -Depth 16 -Compress) -eq $before) 'Future bars changed original feature evidence.'
Assert-Bundle (-not $review.trainingAuthorized -and $review.summary.certifiedLabelCount -eq 0) 'Arithmetic paths promoted to labels.'
foreach($case in @('identity','manifest','from','priceThrough','training','cap','duplicate','oldBar','holiday','partial')){
    $o=New-OutcomeFixture
    switch($case){identity{$o.instruments[0].symbol='OTHER'}manifest{$o.datasetManifestHash=('c'*64)}from{$o.outcomeFrom='2026-06-05'}priceThrough{$o.priceEvidence.throughDate='2026-06-05'}training{$o.trainingAuthorized=$true}cap{$o.instruments[0].rawRowCount=202}duplicate{$o.instruments[0].canonicalBars[1].candleId=$o.instruments[0].canonicalBars[0].candleId}oldBar{$o.instruments[0].canonicalBars[0].date='2026-06-05'}holiday{$o.instruments[0].canonicalBars=@([pscustomobject]@{candleId=99999;date='2026-06-26';source='UPSTOX';excluded=$false})}partial{$o.partial=$true}}
    Must-Reject {Get-NumericalOutcomeReview (New-BundleFixture) $o $calendar $extension} "Bad outcome accepted: $case"
}
$o=New-OutcomeFixture;$o.instruments[0].rawRowCount=201;$o.instruments[0].truncated=$true;$o.partial=$true
$r=Get-NumericalOutcomeReview (New-BundleFixture) $o $calendar $extension
Assert-Bundle ($r.summary.arithmeticOnlyCount -eq 0 -and $r.summary.partial) 'Capped source accepted as complete.'
$o=New-OutcomeFixture;$o.instruments[0].canonicalBars=@($o.instruments[0].canonicalBars | Where-Object date -ne '2026-06-08');$o.instruments[0].rawRowCount--
$r=Get-NumericalOutcomeReview (New-BundleFixture) $o $calendar $extension
Assert-Bundle ($r.rows[2].labelPreflight.status -eq 'MISSING_BAR' -and $r.rows[2].labelPreflight.entryDate -eq '2026-06-08') 'Missing entry silently shifted.'
$bad=Copy-Bundle $extension;$bad.closures=@()
Must-Reject {Get-NumericalOutcomeSessions $calendar $bad} 'Unreviewed calendar accepted.'
$httpState=@{calls=0}
function Invoke-RestMethod {
    param($Uri,$TimeoutSec,$MaximumRedirection,$ErrorAction)
    $httpState.calls++
    if($Uri -like '*/actuator/health'){return [pscustomobject]@{status='UP'}}
    if($Uri -notmatch 'throughDate=2026-07-17' -or $Uri -notmatch 'featureFrom=2025-04-03' -or $TimeoutSec -ne 90 -or $MaximumRedirection -ne 0){throw 'Unexpected request.'}
    New-OutcomeFixture
}
$out=Join-Path $temp 'outcomes'
& (Join-Path $PSScriptRoot 'GetNumericalOutcomeEvidence.ps1') -FeatureEvidencePath $fp -OutputDirectory $out | Out-Null
Assert-Bundle ($httpState.calls -eq 2) 'Collector retried/overqueried.'
$saved=@(Get-ChildItem -LiteralPath $out -Filter '*.json')[0]
$captured=Get-Content $saved.FullName -Raw | ConvertFrom-Json
Assert-Bundle ($captured.review.summary.arithmeticOnlyCount -eq 3 -and $captured.status -eq 'OUTCOME_PREFLIGHT_COMPLETE_TRAINING_BLOCKED') 'Collector serialization failed.'
$httpState.calls=0
& (Join-Path $PSScriptRoot 'GetNumericalOutcomeEvidence.ps1') -FeatureEvidencePath $fp -ExistingOutcomeReportPath $saved.FullName -OutputDirectory $out | Out-Null
Assert-Bundle ($httpState.calls -eq 0 -and @(Get-ChildItem $out -Filter '*.json').Count -eq 2) 'Offline reuse queried or overwrote.'
function Invoke-RestMethod {param($Uri,$TimeoutSec,$MaximumRedirection,$ErrorAction) $httpState.calls++;throw 'Synthetic network timeout.'}
Must-Reject {& (Join-Path $PSScriptRoot 'GetNumericalOutcomeEvidence.ps1') -FeatureEvidencePath $fp -OutputDirectory $out} 'Timeout did not fail closed.'
$failed=@(Get-ChildItem $out -Filter '*.json' | ForEach-Object {Get-Content $_.FullName -Raw | ConvertFrom-Json} | Where-Object status -eq 'FAILED_PARTIAL_REPORT')
Assert-Bundle ($failed.Count -eq 1 -and $httpState.calls -eq 1) 'Timeout report absent or retried.'
Write-Host "PASS: $script:checks total assertions (including readiness suite). Mocked HTTP only."
