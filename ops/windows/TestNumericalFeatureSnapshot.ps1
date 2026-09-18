#Requires -Version 5.1
# HTTP is mocked. Only unique temporary fixture reports are written.
$ErrorActionPreference='Stop'
$state=[pscustomobject]@{mode='ok';calls=0;checks=0}
$run=[guid]'5bdbfcc1-d990-48d8-9e98-d4927596d917'
$root=Join-Path ([IO.Path]::GetTempPath()) ('marketbrain-features-test-'+[guid]::NewGuid().ToString('N'))
[void](New-Item -ItemType Directory -Path $root)
function Invoke-RestMethod {
    param($Uri,$Method,$TimeoutSec,$MaximumRedirection,$ErrorAction)
    $state.calls++
    if($Method -ne 'Get' -or $MaximumRedirection -ne 0){throw 'Unexpected request.'}
    if($Uri -like '*/actuator/health'){return [pscustomobject]@{status='UP'}}
    if($Uri -notlike '*/numerical-feature-snapshot?*' -or $TimeoutSec -ne 60){throw 'Unexpected scope/timeout.'}
    if($state.mode -eq 'timeout'){throw [TimeoutException]::new('Fixture timeout')}
    $dates=@('2026-04-10','2026-05-08','2026-06-05')
    $rows=@(foreach($d in $dates){[pscustomobject]@{decisionDate=$d;status='FEATURES_ONLY_CALENDAR_UNVERIFIED';observationCount=252;sourceCandleIds=@(1..252);features=[pscustomobject]@{dailyReturnPercent=1}}})
    $item=[pscustomobject]@{instrumentId=1;symbol='FIXTURE';rows=$rows;canonicalBars=@();rawRowCount=252;truncated=$false}
    $p=[pscustomobject]@{status='FEATURE_SNAPSHOT_REVIEW_REQUIRED';payloadSha256=('a'*64);partial=$false;trainingAuthorized=$false;databaseWritesPerformed=$false;modelCallCount=0;providerCallCount=0;ordersCreated=0
        payload=[pscustomobject]@{version='OBSERVED_252_FEATURE_SNAPSHOT_V1';datasetRunId=$run.ToString();datasetManifestHash=('b'*64);offset=0;limit=4;decisionDates=$dates;instruments=@($item)}}
    switch($state.mode){
        training {$p.trainingAuthorized=$true}
        scope {$p.payload.datasetRunId=[guid]::NewGuid().ToString()}
        rows {$item.rows=@($rows[0])}
        duplicate {$p.payload.instruments=@($item,$item)}
        partial {$p.partial=$true}
        dates {$rows[0].decisionDate='2020-01-01'}
        counter {$p.modelCallCount='0'}
        blocked {$rows[0].features=$null;$rows[0].status='INSUFFICIENT_OBSERVATIONS';$rows[0].observationCount=20}
    }
    return $p
}
foreach($mode in @('ok','training','scope','rows','duplicate','partial','dates','counter','timeout','blocked')){
    $state.mode=$mode;$state.calls=0;$failed=$false
    $directory=Join-Path $root $mode
    try{& (Join-Path $PSScriptRoot 'GetNumericalFeatureSnapshot.ps1') -DatasetRunId $run -OutputDirectory $directory | Out-Null}catch{$failed=$true}
    $expectedFailure=$mode -notin @('ok','blocked')
    if($failed -ne $expectedFailure){throw "Unexpected failure state for $mode"};$state.checks++
    $files=@(Get-ChildItem -LiteralPath $directory -Filter '*.json')
    if($files.Count -ne 1){throw 'Expected one report.'};$state.checks++
    $report=Get-Content -LiteralPath $files[0].FullName -Raw | ConvertFrom-Json
    if($expectedFailure -and $report.status -ne 'FAILED_PARTIAL_REPORT'){throw 'Failure evidence missing.'}
    if(-not $expectedFailure -and $report.status -ne 'FEATURE_SNAPSHOT_REVIEW_REQUIRED'){throw 'Success state incorrect.'};$state.checks++
    if($state.calls -ne 2){throw 'Request retry or missing call.'};$state.checks++
    if($mode -eq 'blocked' -and ($report.summary.blockedRows -ne 1 -or $report.summary.computedFeatureRows -ne 2)){throw 'Blocked denominator lost.'}
}
Write-Host "PASS: $($state.checks) assertions; HTTP mocked; fixtures retained in $root"
