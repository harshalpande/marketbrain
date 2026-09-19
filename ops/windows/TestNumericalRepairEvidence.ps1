#Requires -Version 5.1
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'TestNumericalExpansionPlan.ps1')
. (Join-Path $PSScriptRoot 'NumericalRepairEvidence.ps1')
$early=Get-Content (Join-Path $PSScriptRoot '..\data\nse-cm-early-calendar-20241022-20250331-v1.json') -Raw|ConvertFrom-Json
$earlyDays=@(Get-NumericalEarlySessions $early)
Assert-Bundle ($earlyDays.Count -eq 110 -and '2024-11-01' -in $earlyDays -and '2024-11-20' -notin $earlyDays -and '2025-02-01' -in $earlyDays -and '2025-03-31' -notin $earlyDays) 'Earlier exchange calendar wrong.'
function New-RepairExportFixture {
    $f=New-ExpansionFixture
    foreach($item in $f.data.request.instruments){
        $replacement=@(for($i=0;$i -lt $earlyDays.Count;$i++){[pscustomobject]@{candleId=($item.instrumentId*100000+$i);date=$earlyDays[$i];source='UPSTOX';receivedAt='2026-09-01T00:00:00Z';excluded=$false;open=100;high=120;low=80;close=110;volume=1000}})
        $item.bars=@(@($item.bars|Where-Object {$_.date -lt '2024-10-22'})+$replacement+@($item.bars|Where-Object {$_.date -gt '2025-03-31'}))
    }
    $f.data.result=New-ExportFixture $f.data.request
    $f.data|Add-Member -NotePropertyName updatedAtUtc -NotePropertyValue $null -Force
    $f
}
$f=New-RepairExportFixture;$review=Get-NumericalExpandedCalendarReview $f $early
Assert-Bundle ($review.status -eq 'EXPANDED_WINDOWS_MATCH_TRAINING_BLOCKED' -and $review.rowCount -eq 300 -and $review.featureWindowMatchCount -eq 300 -and $review.outcomeWindowMatchCount -eq 300) 'Expanded windows not matched.'
$bad=Copy-Bundle $early;$bad.specialSessions=@('2024-11-01')
Must-Reject {Get-NumericalEarlySessions $bad} 'Budget session removal accepted.'
$bad=Copy-Bundle $early;$bad.sources[0].url='https://evil.example/calendar'
Must-Reject {Get-NumericalEarlySessions $bad} 'Unreviewed source accepted.'
$gap=New-RepairExportFixture;$gap.data.request.instruments[1].bars=@($gap.data.request.instruments[1].bars|Where-Object date -ne '2025-02-03')
$gapReview=Get-NumericalExpandedCalendarReview $gap $early
Assert-Bundle ($gapReview.status -eq 'EXPANDED_WINDOWS_BLOCKED' -and $gapReview.blockedRowCount -gt 0) 'Missing prior feature date accepted.'
function New-RepairFixture {
    $p=[pscustomobject]@{version='NUMERICAL_PRICE_EVIDENCE_V1';datasetRunId=$f.data.request.datasetRunId;datasetManifestHash=$f.data.request.datasetManifestHash
        fromDate=$review.plan.featureFrom;throughDate=$review.plan.outcomeThrough;offset=0;limit=2;partial=$false;trainingAuthorized=$false;databaseWritesPerformed=$false;providerCallCount=0;modelCallCount=0;ordersCreated=0
        instruments=@($f.data.request.instruments|ForEach-Object {[pscustomobject]@{instrumentId=$_.instrumentId;symbol=$_.symbol;latestRelevantResolutions=@();corporateActions=@()}})}
    [pscustomobject]@{version='NUMERICAL_REPAIR_EVIDENCE_V1';status='REPAIR_PROVENANCE_REVIEW_REQUIRED';priceEvidence=$p;references=@();scopedResolutionCount=0;scopedActionCount=0
        partial=$false;trainingAuthorized=$false;databaseWritesPerformed=$false;providerCallCount=0;modelCallCount=0;ordersCreated=0}
}
Assert-NumericalRepairEvidence $f $review (New-RepairFixture) 0
foreach($case in @('scope','flag','partial','identity','count')){
    $bad=New-RepairFixture
    switch($case){scope{$bad.priceEvidence.fromDate='2025-04-03'}flag{$bad.trainingAuthorized=$true}partial{$bad.partial=$true}identity{$bad.priceEvidence.instruments[0].symbol='OTHER'}count{$bad.scopedResolutionCount=1}}
    Must-Reject {Assert-NumericalRepairEvidence $f $review $bad 0} "Bad repair evidence accepted: $case"
}
$withReference=New-RepairFixture
$withReference.priceEvidence.instruments[0].latestRelevantResolutions=@([pscustomobject]@{id='event1';eventAction='REVOKE'})
$withReference.scopedResolutionCount=1
$withReference.references=@([pscustomobject]@{kind='RESOLUTION';recordId='event1';publicReference='https://nsearchives.nseindia.com/content/circulars/CMTR64960.pdf';notesSha256=('a'*64);originalReferenceSha256=('b'*64);evidenceSourceSha256=('c'*64)})
Assert-NumericalRepairEvidence $f $review $withReference 0
$withReference.references[0].publicReference+='?token=secret'
Must-Reject {Assert-NumericalRepairEvidence $f $review $withReference 0} 'Private query leaked.'
$http=@{calls=0;fail=$false}
function Invoke-RestMethod {
    param($Uri,$TimeoutSec,$MaximumRedirection,$ErrorAction)
    $http.calls++
    if($Uri -like '*/actuator/health'){return [pscustomobject]@{status='UP'}}
    if($http.fail){throw 'Synthetic timeout.'}
    if($Uri -notmatch 'fromDate=2024-10-22' -or $Uri -notmatch 'throughDate=2026-07-06' -or $Uri -notmatch 'limit=2' -or $TimeoutSec -ne 90 -or $MaximumRedirection -ne 0){throw 'Unexpected repair query.'}
    New-RepairFixture
}
$repairInput=Join-Path $temp 'repair-export.json';Save-NumericalHistoryReport $f.data $repairInput
$out=Join-Path $temp 'repair-reports'
& (Join-Path $PSScriptRoot 'GetNumericalRepairEvidence.ps1') -ResearchExportPath $repairInput -OutputDirectory $out|Out-Null
Assert-Bundle ($http.calls -eq 2) 'Repair collector retried/overqueried.'
$capturedFile=Get-ChildItem $out -Filter '*.json'|Select-Object -First 1
$captured=Get-Content $capturedFile.FullName -Raw|ConvertFrom-Json
Assert-Bundle ($captured.status -eq 'REPAIR_EVIDENCE_CAPTURED_TRAINING_BLOCKED' -and $captured.calendarReview.rowCount -eq 300) 'Repair evidence incomplete.'
$http.calls=0
& (Join-Path $PSScriptRoot 'GetNumericalRepairEvidence.ps1') -ResearchExportPath $repairInput -ExistingRepairReportPath $capturedFile.FullName -OutputDirectory $out|Out-Null
Assert-Bundle ($http.calls -eq 0 -and @(Get-ChildItem $out -Filter '*.json').Count -eq 2) 'Reuse made HTTP calls or overwrote report.'
$http.fail=$true
Must-Reject {& (Join-Path $PSScriptRoot 'GetNumericalRepairEvidence.ps1') -ResearchExportPath $repairInput -OutputDirectory $out} 'Query timeout swallowed.'
$failed=@(Get-ChildItem $out -Filter '*.json'|ForEach-Object {Get-Content $_.FullName -Raw|ConvertFrom-Json}|Where-Object status -eq 'FAILED_PARTIAL_REPORT')
Assert-Bundle ($failed.Count -eq 1 -and $failed[0].failureStage -eq 'QUERY' -and $null -ne $failed[0].calendarReview -and $http.calls -eq 2) 'Calendar checkpoint lost or query retried.'
Write-Host "PASS: $script:checks assertions including upstream suites. Mocked HTTP only."
