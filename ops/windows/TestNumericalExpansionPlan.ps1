#Requires -Version 5.1
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'TestNumericalResearchExport.ps1')
. (Join-Path $PSScriptRoot 'NumericalExpansionPlan.ps1')
. (Join-Path $PSScriptRoot 'NumericalHistoryEvidence.ps1')
function New-ExpansionFixture {
    $requestCopy=Copy-Bundle $request
    $older=@(for($d=[datetime]'2024-06-06';$d -lt [datetime]'2025-04-01';$d=$d.AddDays(1)){
        if([int]$d.DayOfWeek -ge 1 -and [int]$d.DayOfWeek -le 5){[pscustomobject]@{candleId=2000+$d.DayOfYear;date=$d.ToString('yyyy-MM-dd');source='UPSTOX';receivedAt='2026-09-01T00:00:00Z';excluded=$false;open=100;high=120;low=80;close=110;volume=1000}}
    })
    # The synthetic prior-year/year-turn ID allocation must also remain unique.
    for($i=0;$i -lt $older.Count;$i++){$older[$i].candleId=3000+$i}
    $requestCopy.instruments[0].bars=$older+@($requestCopy.instruments[0].bars)
    $second=Copy-Bundle $requestCopy.instruments[0];$second.instrumentId=2;$second.symbol='SECOND'
    foreach($bar in $second.bars){$bar.candleId+=10000}
    $requestCopy.instruments=@($requestCopy.instruments[0],$second)
    [pscustomobject]@{sha256=('a'*64);data=[pscustomobject]@{version='NUMERICAL_RESEARCH_EXPORT_COLLECTION_V1';status='RESEARCH_EXPORT_TRAINING_BLOCKED';request=$requestCopy
        result=(New-ExportFixture $requestCopy);calendar=$calendar;extension=$extension}}
}
$fixture=New-ExpansionFixture;$before=$fixture|ConvertTo-Json -Depth 16 -Compress
$plan=New-NumericalExpansionPlan $fixture
Assert-Bundle ($plan.layout.assignments.Count -eq 150 -and $plan.provisionalCandidateRowCount -eq 300 -and $plan.provisionalRetainedRowCount -eq 200) 'Wrong expansion sizes.'
foreach($partition in @('TRAIN','VALIDATION','SHADOW_TEST')){
    $rows=@($plan.layout.assignments|Where-Object {$_.partition -eq $partition -and $_.state -eq 'RETAINED_PROVISIONAL'})
    $expected=if($partition -eq 'TRAIN'){60}else{20}
    Assert-Bundle ($rows.Count -eq $expected) "Wrong retained count: $partition"
    if($partition -ne 'SHADOW_TEST'){
        $boundary=if($partition -eq 'TRAIN'){$plan.layout.validationFrom}else{$plan.layout.shadowTestFrom}
        Assert-Bundle (@($rows|Where-Object {$_.exitDate -ge $boundary}).Count -eq 0) 'Outcome crossed next partition.'
    }
}
Assert-Bundle (@($plan.layout.assignments|Where-Object state -eq 'PURGED_LABEL_OVERLAP').Count -eq 40 -and @($plan.layout.assignments|Where-Object state -eq 'FIVE_DATE_BOUNDARY_GAP').Count -eq 10) 'Wrong purge/gap count.'
Assert-Bundle ($plan.previouslyReviewedShadowTestDateCount -eq 20 -and -not $plan.untouchedTest -and -not $plan.trainingAuthorized) 'Inspected outcomes presented as untouched or authorized.'
Assert-Bundle ($plan.calendarExtensionRequiredDates.Count -gt 0 -and @($plan.instruments|Where-Object {-not $_.completeObservedPath}).Count -eq 0) 'Calendar unknown or stored completeness misreported.'
Assert-Bundle (($fixture|ConvertTo-Json -Depth 16 -Compress) -eq $before) 'Planner mutated evidence.'
$missing=New-ExpansionFixture
$missing.data.request.instruments[1].bars=@($missing.data.request.instruments[1].bars|Where-Object {$_.date -ne $plan.featureFrom})
$gap=New-NumericalExpansionPlan $missing
Assert-Bundle ($gap.instruments[1].missingDates.Count -eq 1 -and $gap.layout.validationFrom -eq $plan.layout.validationFrom) 'Intersection hid a missing date or moved boundary.'
$bad=New-ExpansionFixture
$target=@($bad.data.request.instruments[1].bars|Where-Object {$_.date -eq $plan.featureFrom})[0];$target.excluded=$true;$target.close=-1
$quality=New-NumericalExpansionPlan $bad
Assert-Bundle ($quality.instruments[1].excludedDates.Count -eq 1 -and $quality.instruments[1].invalidDates.Count -eq 1 -and -not $quality.instruments[1].completeObservedPath) 'Old invalid/excluded inputs hidden.'
$bad=New-ExpansionFixture;$bad.data.request.instruments[0].bars[0].candleId=$bad.data.request.instruments[0].bars[1].candleId
Must-Reject {New-NumericalExpansionPlan $bad} 'Duplicate source IDs accepted.'
$days=@($fixture.data.request.instruments[0].bars.date|Select-Object -Last 170);$days[1]=$days[0]
Must-Reject {New-NumericalDevelopmentLayout $days} 'Duplicate layout dates accepted.'
Must-Reject {New-NumericalDevelopmentLayout @('2026-06-05')} 'Short history accepted.'
function Invoke-RestMethod {throw 'Planner must never call HTTP.'}
$inputPath=Join-Path $temp 'expansion-fixture.json'
# Save fixture with the same runtime evidence writer used by the collectors.
$fixture.data|Add-Member updatedAtUtc $null
Save-NumericalHistoryReport $fixture.data $inputPath
$planDirectory=Join-Path $temp 'plans'
& (Join-Path $PSScriptRoot 'PrepareNumericalExpansionPlan.ps1') -ResearchExportPath $inputPath -OutputDirectory $planDirectory | Out-Null
& (Join-Path $PSScriptRoot 'PrepareNumericalExpansionPlan.ps1') -ResearchExportPath $inputPath -OutputDirectory $planDirectory | Out-Null
Assert-Bundle (@(Get-ChildItem $planDirectory -Filter '*.json').Count -eq 2) 'Plan overwritten.'
Must-Reject {& (Join-Path $PSScriptRoot 'PrepareNumericalExpansionPlan.ps1') -ResearchExportPath (Join-Path $temp 'absent.json') -OutputDirectory $planDirectory} 'Missing file swallowed.'
$failed=@(Get-ChildItem $planDirectory -Filter '*.json'|ForEach-Object {Get-Content $_.FullName -Raw|ConvertFrom-Json}|Where-Object status -eq 'FAILED_PARTIAL_REPORT')
Assert-Bundle ($failed.Count -eq 1 -and $failed[0].failureStage -eq 'INPUT') 'Failure evidence missing.'
Write-Host "PASS: $script:checks assertions including upstream suites. No runtime services used."
