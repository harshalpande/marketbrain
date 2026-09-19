#Requires -Version 5.1
# Developer-only offline fixture tests. No service or Docker execution.
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'NumericalEvaluationEngineering.ps1')
$folder=Join-Path $PSScriptRoot ('..\..\marketbrain-service\target\robustness-workflow-'+[guid]::NewGuid().ToString('N'))
& (Join-Path $PSScriptRoot 'TestNumericalRobustnessBundle.ps1') -Runtime Java -OutputDirectory $folder
$files=@(Get-ChildItem -LiteralPath $folder -File);$count=0
if($files.Count -ne 1){throw 'One report expected.'};$count++
$report=Get-Content -LiteralPath $files[0].FullName -Raw | ConvertFrom-Json
if($report.status -ne 'SYNTHETIC_CHECKS_PASSED_TRAINING_BLOCKED' -or $report.version -ne 'NUMERICAL_ROBUSTNESS_BUNDLE_COLLECTION_V1' -or $report.suite -ne 'Robustness'){throw 'Wrong robustness envelope.'};$count++
Assert-NumericalRobustnessBundle $report.javaResult;$count++
$rejected=$false;try{Assert-BaselineNumber 1 ([double]::NaN) 'invalid expected value'}catch{$rejected=$true}
if(-not $rejected){throw 'Non-finite expected value accepted.'};$count++
foreach($case in @('status','training','synthetic','provider','checks','name','timing','blocker','promotion','horizon','fold','hash','guard','pooled','target','metric','cost','costCount','coverage','costNet','noSelection','regression')){
    $bad=$report.javaResult | ConvertTo-Json -Depth 40 | ConvertFrom-Json
    switch($case){
        status{$bad.status='PASS'}training{$bad.realMarketTrainingAuthorized=$true}synthetic{$bad.syntheticOnly=$false}provider{$bad.providerCallCount=1}
        checks{$bad.checkCount=11}name{$bad.checks[0].name='wrong'}timing{$bad.checks[0].elapsedMillis=-1}
        blocker{$bad.readiness.blockers=@()}promotion{$bad.readiness.automaticPromotionEnabled=$true}
        horizon{$bad.horizons[1]=$bad.horizons[0]}fold{$bad.horizons[0].folds[1]=$bad.horizons[0].folds[0]}
        hash{$bad.horizons[0].folds[0].fixtureSha256='bad'}guard{$bad.horizons[0].folds[0].guard.status='REJECTED'}
        pooled{$bad.horizons[0].pooledTest[0].predictions=@()}
        target{$bad.horizons[0].pooledTest[2].predictions[0].observed=999}
        metric{$bad.horizons[0].pooledTest[2].errors.equalDateWeighted.mae=999}
        cost{$bad.horizons[0].hypotheticalCosts[2].costs[0].roundTripCostBps=5}
        costCount{$bad.horizons[0].hypotheticalCosts[2].costs[0].selectedCount=999}
        coverage{$bad.horizons[0].hypotheticalCosts[2].costs[0].coveragePercent=999}
        costNet{$bad.horizons[0].hypotheticalCosts[2].costs[0].meanSelectedNetPercent=999}
        noSelection{$bad.horizons[0].hypotheticalCosts[0].costs[0].meanSelectedNetPercent=0}
        regression{$bad.baselineRegression.failedCheckCount=1}
    }
    $rejected=$false;try{Assert-NumericalRobustnessBundle $bad}catch{$rejected=$true}
    if(-not $rejected){throw "Accepted corrupt report: $case"};$count++
}
Write-Host "Robustness workflow passed: $count assertions. Evidence: $folder"
