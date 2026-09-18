#Requires -Version 5.1
# Mocked HTTP, synthetic saved input; no live calls or real data changes.
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'NumericalFeatureCalendar.ps1')
$calendar=Get-Content -LiteralPath (Join-Path $PSScriptRoot '..\data\nse-cm-calendar-20250401-20260605-v1.json') -Raw | ConvertFrom-Json
$sessions=@(Get-NumericalCalendarSessions $calendar)
$bars=@(for($i=0;$i -lt $sessions.Count;$i++){[pscustomobject]@{candleId=$i+1;date=$sessions[$i];source='UPSTOX';excluded=$false}})
$dates=@('2026-04-10','2026-05-08','2026-06-05')
$rows=@(foreach($date in $dates){$window=@($bars|Where-Object {$_.date -le $date}|Select-Object -Last 252);[pscustomobject]@{
    decisionDate=$date;status='FEATURES_ONLY_CALENDAR_UNVERIFIED';featureFrom=$window[0].date;observationCount=252;sourceCandleIds=@($window.candleId);features=[pscustomobject]@{fixture=$true}}})
$run='5bdbfcc1-d990-48d8-9e98-d4927596d917'
$inputFixture=[pscustomobject]@{
    version='NUMERICAL_FEATURE_EVIDENCE_V1';status='FEATURE_SNAPSHOT_REVIEW_REQUIRED';datasetRunId=$run
    snapshot=[pscustomobject]@{status='FEATURE_SNAPSHOT_REVIEW_REQUIRED';payloadSha256=('a'*64);partial=$false;trainingAuthorized=$false;databaseWritesPerformed=$false;modelCallCount=0;providerCallCount=0;ordersCreated=0
        payload=[pscustomobject]@{version='OBSERVED_252_FEATURE_SNAPSHOT_V1';datasetRunId=$run;datasetManifestHash=('b'*64);asOf='2026-06-05';windowFrom='2024-06-06';offset=0;limit=1;decisionDates=$dates
            instruments=@([pscustomobject]@{instrumentId=2;symbol='FIXTURE';rawRowCount=$bars.Count;truncated=$false;canonicalBars=$bars;rows=$rows})}}
}
$state=[pscustomobject]@{mode='ok';calls=0;checks=0}
function Invoke-RestMethod {
    param($Uri,$Method,$TimeoutSec,$MaximumRedirection,$ErrorAction)
    $state.calls++
    if($Method -ne 'Get' -or $MaximumRedirection -ne 0){throw 'Wrong transport settings.'}
    if($Uri -like '*/actuator/health'){return [pscustomobject]@{status='UP'}}
    if($Uri -notlike '*/numerical-price-evidence?*fromDate=2025-04-03&offset=0&limit=1' -or $TimeoutSec -ne 60){throw 'Wrong query scope.'}
    if($state.mode -eq 'timeout'){throw [TimeoutException]::new('Mock query timeout')}
    $item=[pscustomobject]@{instrumentId=2;symbol='FIXTURE';partial=$false;jobLinks=@();chunks=@();corporateActions=@();resolutionEventsInspected=0;latestRelevantResolutions=@();overlappingActiveExclusionCount=0;revokedFindingCount=0
        remainingGates=@('CORPORATE_ACTION_COVERAGE_UNKNOWN','NO_VERIFIED_ADJUSTMENT_FACTORS_OR_EXECUTABLE_PRICE_BINDING')}
    $r=[pscustomobject]@{version='NUMERICAL_PRICE_EVIDENCE_V1';status='PRICE_POLICY_REVIEW_REQUIRED';datasetRunId=$run;datasetManifestHash=('b'*64);fromDate='2025-04-03';throughDate='2026-06-05';offset=0;limit=1
        jobsObserved=0;jobCatalogTruncated=$false;instruments=@($item);partial=$false;trainingAuthorized=$false;databaseWritesPerformed=$false;modelCallCount=0;providerCallCount=0;ordersCreated=0}
    switch($state.mode){
        manifest {$r.datasetManifestHash='c'*64}
        scope {$r.fromDate='2025-04-02'}
        identity {$item.instrumentId=3}
        training {$r.trainingAuthorized=$true}
        counter {$r.providerCallCount=1}
        gate {$item.remainingGates=@()}
        capMismatch {$r.partial=$true}
        capped {$r.jobsObserved=21;$r.jobCatalogTruncated=$true;$r.partial=$true;$item.partial=$true}
    }
    return $r
}
$root=Join-Path ([IO.Path]::GetTempPath()) ('marketbrain-price-tests-'+[guid]::NewGuid().ToString('N'));[void](New-Item -ItemType Directory -Path $root)
$inputPath=Join-Path $root 'features.json'
[IO.File]::WriteAllText($inputPath,($inputFixture|ConvertTo-Json -Depth 16),[Text.UTF8Encoding]::new($false))
$inputHash=(Get-FileHash -LiteralPath $inputPath).Hash
foreach($mode in @('ok','manifest','scope','identity','training','counter','gate','capMismatch','capped','timeout')){
    $state.mode=$mode;$state.calls=0;$failed=$false;$directory=Join-Path $root $mode
    try{& (Join-Path $PSScriptRoot 'GetNumericalPriceEvidence.ps1') -FeatureEvidencePath $inputPath -OutputDirectory $directory | Out-Null}catch{$failed=$true}
    $shouldFail=$mode -notin @('ok','capped')
    if($failed -ne $shouldFail){throw "Unexpected failure for $mode"};$state.checks++
    $files=@(Get-ChildItem -LiteralPath $directory -Filter '*.json');if($files.Count -ne 1){throw 'One output expected.'};$state.checks++
    $report=Get-Content -LiteralPath $files[0].FullName -Raw | ConvertFrom-Json
    $expected=if($shouldFail){'FAILED_PARTIAL_REPORT'}elseif($mode -eq 'capped'){'PARTIAL_PRICE_POLICY_REVIEW_REQUIRED'}else{'PRICE_POLICY_REVIEW_REQUIRED'}
    if($report.status -ne $expected){throw 'Wrong report state.'};$state.checks++
    if($state.calls -ne 2 -or $report.inputSha256 -ne $inputHash){throw 'Retry/input hash mismatch.'};$state.checks++
}
if((Get-FileHash -LiteralPath $inputPath).Hash -ne $inputHash){throw 'Input mutated.'};$state.checks++
Write-Host "PASS: $($state.checks) assertions. Mocked HTTP; fixtures retained: $root"
