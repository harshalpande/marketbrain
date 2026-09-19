#Requires -Version 5.1
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'TestNumericalRepairEvidence.ps1')
. (Join-Path $PSScriptRoot 'NumericalExpandedResearch.ps1')
$source=Read-NumericalBundleInput $repairInput
$repair=Read-NumericalBundleInput $capturedFile.FullName
$context=New-NumericalExpandedResearchContext $source $repair
Assert-Bundle ($context.request.sessions.Count -eq 430 -and $context.calendarReview.rowCount -eq 300 -and -not $context.trainingAuthorized) 'Wrong expanded context.'
foreach($case in @('binding','partial','calendar')){
    $bad=Copy-Bundle $repair
    switch($case){binding{$bad.data.inputSha256=('f'*64)}partial{$bad.data.repairEvidence.partial=$true}calendar{$bad.data.earlyCalendar.specialSessions=@()}}
    Must-Reject {New-NumericalExpandedResearchContext $source $bad} "Unsafe input accepted: $case"
}
function New-ExpandedFixture($Request){
    $rows=@(foreach($item in $Request.instruments){foreach($day in $Request.sessions|Where-Object {$_ -ge '2025-10-27' -and $_ -le '2026-06-05'}){
        $label=Get-NumericalLabelPreflight $day $Request.sessions $item.bars
        $window=@($item.bars|Where-Object {$_.date -le $day}|Select-Object -Last 252)
        [pscustomobject]@{instrumentId=$item.instrumentId;symbol=$item.symbol;decisionDate=$day;featureStatus='MATCHES_REVIEWED_CALENDAR'
            featureSnapshot=[pscustomobject]@{decisionDate=$day;featureFrom=$window[0].date;observationCount=252;sourceCandleIds=@($window.candleId)}
            outcome=[pscustomobject]@{status=$label.status;entryDate=$label.entryDate;exitDate=$label.exitDate;problemDate=$label.problemDate;sourceCandleIds=$label.sourceCandleIds;indicativeGrossPercent=$label.indicativeGrossPercent
                costSensitivity=@($label.costSensitivity|ForEach-Object {[pscustomobject]@{roundTripBps=$_.assumedRoundTripCostBps;indicativeNetPercent=$_.indicativeNetPercent}})}}
    }})
    [pscustomobject]@{version='NUMERICAL_EXPANDED_RESEARCH_V1';status='RESEARCH_EXPORT_TRAINING_BLOCKED';datasetRunId=$Request.datasetRunId;datasetManifestHash=$Request.datasetManifestHash
        featureEvidenceSha256=$Request.featureEvidenceSha256;outcomeEvidenceSha256=$Request.outcomeEvidenceSha256;calendarSessionSha256='edc44a9eeee945a4362756c71d5d07c83e0c50a207706f9fb32f267733a60748'
        decisionDateCount=150;candidateRowCount=$rows.Count;completeArithmeticRowCount=$rows.Count;blockedRowCount=0;rows=$rows
        certifiedLabelCount=0;trainingAuthorized=$false;databaseWritesPerformed=$false;databaseQueryCount=0;providerCallCount=0;modelCallCount=0;ordersCreated=0}
}
$result=New-ExpandedFixture $context.request
Assert-NumericalResearchExportResult $context.request $result -Expanded
foreach($case in @('version','missing','duplicate','unsafe','calendar','outcome','feature')){
    $bad=Copy-Bundle $result
    switch($case){version{$bad.version='NUMERICAL_MULTI_DATE_RESEARCH_V1'}missing{$bad.rows=@($bad.rows|Select-Object -Skip 1)}duplicate{$bad.rows[1]=$bad.rows[0]}unsafe{$bad.certifiedLabelCount=300}calendar{$bad.calendarSessionSha256=('f'*64)}outcome{$bad.rows[0].outcome.indicativeGrossPercent=999}feature{$bad.rows[0].featureSnapshot.sourceCandleIds[0]=999999}}
    Must-Reject {Assert-NumericalResearchExportResult $context.request $bad -Expanded} "Invalid expanded result accepted: $case"
}
$expandedHttp=@{calls=0;fail=$false}
function Invoke-RestMethod {
    param($Uri,$TimeoutSec,$MaximumRedirection,$ErrorAction,$Method,$ContentType,$Body)
    $expandedHttp.calls++
    if($Uri -like '*/actuator/health'){return [pscustomobject]@{status='UP'}}
    if($expandedHttp.fail){throw 'Synthetic timeout.'}
    if($Uri -notlike '*/numerical-expanded-research-export' -or $TimeoutSec -ne 90 -or $MaximumRedirection -ne 0 -or $Method -ne 'Post'){throw 'Unexpected expanded request.'}
    New-ExpandedFixture ([Text.Encoding]::UTF8.GetString($Body)|ConvertFrom-Json)
}
$out=Join-Path $temp 'expanded-reports'
& (Join-Path $PSScriptRoot 'ExportNumericalExpandedResearch.ps1') -ResearchExportPath $repairInput -RepairEvidencePath $capturedFile.FullName -OutputDirectory $out|Out-Null
Assert-Bundle ($expandedHttp.calls -eq 2) 'Expanded export overqueried.'
$expandedFile=Get-ChildItem $out -Filter '*.json'|Select-Object -First 1
$savedExpanded=Get-Content $expandedFile.FullName -Raw|ConvertFrom-Json
Assert-Bundle ($expandedFile.Length -lt 2MB -and (Get-Content $expandedFile.FullName -Raw) -notmatch "`n") 'Expanded report not compact.'
Assert-Bundle ($savedExpanded.result.candidateRowCount -eq 300 -and $savedExpanded.result.certifiedLabelCount -eq 0 -and $savedExpanded.repairSha256 -eq $repair.sha256) 'Expanded compact report incomplete.'
$expandedHttp.calls=0
& (Join-Path $PSScriptRoot 'ExportNumericalExpandedResearch.ps1') -ResearchExportPath $repairInput -RepairEvidencePath $capturedFile.FullName -ExistingExpandedReportPath $expandedFile.FullName -OutputDirectory $out|Out-Null
Assert-Bundle ($expandedHttp.calls -eq 0 -and @(Get-ChildItem $out -Filter '*.json').Count -eq 2) 'Offline reuse called server or overwrote evidence.'
$expandedHttp.fail=$true
Must-Reject {& (Join-Path $PSScriptRoot 'ExportNumericalExpandedResearch.ps1') -ResearchExportPath $repairInput -RepairEvidencePath $capturedFile.FullName -OutputDirectory $out} 'Expanded timeout swallowed.'
$failed=@(Get-ChildItem $out -Filter '*.json'|ForEach-Object {Get-Content $_.FullName -Raw|ConvertFrom-Json}|Where-Object status -eq 'FAILED_PARTIAL_REPORT')
Assert-Bundle ($failed.Count -eq 1 -and $null -ne $failed[0].request -and $failed[0].failureStage -eq 'EXPORT' -and $expandedHttp.calls -eq 2) 'Expanded input checkpoint lost or query retried.'
Write-Host "PASS: $script:checks assertions including upstream suites. Mocked HTTP; no runtime/DB/provider/model."
