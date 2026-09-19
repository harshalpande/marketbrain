#Requires -Version 5.1
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'TestNumericalOutcomeEvidence.ps1')
. (Join-Path $PSScriptRoot 'NumericalResearchExport.ps1')
$feature=Read-NumericalBundleInput $fp;$outcome=Read-NumericalBundleInput $saved.FullName
$request=New-NumericalResearchExportRequest $feature $outcome $calendar $extension
Assert-Bundle ($request.sessions.Count -eq 320 -and $request.instruments.Count -eq 1) 'Wrong saved export scope.'
$bad=Copy-Bundle $outcome;$bad.data.inputSha256=('f'*64)
Must-Reject {New-NumericalResearchExportRequest $feature $bad $calendar $extension} 'Cross-run evidence accepted.'
function New-ExportFixture($Request){
    $rows=@(foreach($item in $Request.instruments){foreach($day in $Request.sessions | Where-Object {$_ -ge '2026-04-10' -and $_ -le '2026-06-05'}){
        $label=Get-NumericalLabelPreflight $day $Request.sessions $item.bars
        $window=@($item.bars | Where-Object {$_.date -le $day} | Select-Object -Last 252)
        [pscustomobject]@{instrumentId=$item.instrumentId;symbol=$item.symbol;decisionDate=$day;featureStatus='MATCHES_REVIEWED_CALENDAR'
            featureSnapshot=[pscustomobject]@{decisionDate=$day;featureFrom=$window[0].date;observationCount=252;sourceCandleIds=@($window.candleId)}
            outcome=[pscustomobject]@{status=$label.status;entryDate=$label.entryDate;exitDate=$label.exitDate;problemDate=$label.problemDate;sourceCandleIds=$label.sourceCandleIds;indicativeGrossPercent=$label.indicativeGrossPercent
                costSensitivity=@($label.costSensitivity | ForEach-Object {[pscustomobject]@{roundTripBps=$_.assumedRoundTripCostBps;indicativeNetPercent=$_.indicativeNetPercent}})}}
    }})
    [pscustomobject]@{version='NUMERICAL_MULTI_DATE_RESEARCH_V1';status='RESEARCH_EXPORT_TRAINING_BLOCKED';datasetRunId=$Request.datasetRunId;datasetManifestHash=$Request.datasetManifestHash
        featureEvidenceSha256=$Request.featureEvidenceSha256;outcomeEvidenceSha256=$Request.outcomeEvidenceSha256;calendarSessionSha256='ea8cd016a1b03fab1d97b0cdecbdae4ff181b1b22f4a10a21f6ff6f11ca9c086'
        decisionDateCount=38;candidateRowCount=$rows.Count;completeArithmeticRowCount=$rows.Count;blockedRowCount=0;rows=$rows
        certifiedLabelCount=0;trainingAuthorized=$false;databaseWritesPerformed=$false;databaseQueryCount=0;providerCallCount=0;modelCallCount=0;ordersCreated=0}
}
$valid=New-ExportFixture $request
Assert-NumericalResearchExportResult $request $valid
Assert-Bundle ($valid.rows.Count -eq 38) 'Rows not expanded.'
foreach($case in @('unsafe','duplicate','cost','future','gross','count','manifest')){
    $bad=Copy-Bundle $valid
    switch($case){unsafe{$bad.trainingAuthorized=$true}duplicate{$bad.rows[1]=$bad.rows[0]}cost{$bad.rows[0].outcome.costSensitivity[1].indicativeNetPercent=999}future{$bad.rows[0].featureSnapshot.sourceCandleIds[0]=999999}gross{$bad.rows[0].outcome.indicativeGrossPercent=999}count{$bad.completeArithmeticRowCount=0}manifest{$bad.datasetManifestHash='bad'}}
    Must-Reject {Assert-NumericalResearchExportResult $request $bad} "Bad export accepted: $case"
}
$exportHttp=@{calls=0;fail=$false}
function Invoke-RestMethod {
    param($Uri,$TimeoutSec,$MaximumRedirection,$ErrorAction,$Method,$ContentType,$Body)
    $exportHttp.calls++
    if($Uri -like '*/actuator/health'){return [pscustomobject]@{status='UP'}}
    if($exportHttp.fail){throw 'Synthetic timeout.'}
    if($Method -ne 'Post' -or $TimeoutSec -ne 90 -or $MaximumRedirection -ne 0){throw 'Unexpected export request.'}
    New-ExportFixture ([Text.Encoding]::UTF8.GetString($Body)|ConvertFrom-Json)
}
$exportDirectory=Join-Path $temp 'exports'
& (Join-Path $PSScriptRoot 'ExportNumericalResearchDataset.ps1') -FeatureEvidencePath $fp -OutcomeEvidencePath $saved.FullName -OutputDirectory $exportDirectory | Out-Null
Assert-Bundle ($exportHttp.calls -eq 2) 'Export repeated API work.'
$artifact=Get-ChildItem $exportDirectory -Filter '*.json' | Select-Object -First 1
$persisted=Get-Content $artifact.FullName -Raw|ConvertFrom-Json
Assert-Bundle ($persisted.status -eq 'RESEARCH_EXPORT_TRAINING_BLOCKED' -and $persisted.request.instruments.Count -eq 1 -and $persisted.result.rows.Count -eq 38) 'Compact evidence incomplete.'
$exportHttp.fail=$true;$exportHttp.calls=0
Must-Reject {& (Join-Path $PSScriptRoot 'ExportNumericalResearchDataset.ps1') -FeatureEvidencePath $fp -OutcomeEvidencePath $saved.FullName -OutputDirectory $exportDirectory} 'Timeout swallowed.'
$reports=@(Get-ChildItem $exportDirectory -Filter '*.json'|ForEach-Object {Get-Content $_.FullName -Raw|ConvertFrom-Json})
Assert-Bundle ($reports.Count -eq 2 -and $exportHttp.calls -eq 2 -and @($reports|Where-Object status -eq 'FAILED_PARTIAL_REPORT').Count -eq 1) 'Failed evidence lost, overwritten or retried.'
Write-Host "PASS: $script:checks assertions including upstream suites. HTTP mocked; no runtime service calls."
