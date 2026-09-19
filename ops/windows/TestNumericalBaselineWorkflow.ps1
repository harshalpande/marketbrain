#Requires -Version 5.1
# Offline developer tests: JDK only, no Docker/service/provider/model.
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'NumericalEvaluationEngineering.ps1')
$count=0
$folder=Join-Path $PSScriptRoot ('..\..\marketbrain-service\target\baseline-workflow-'+[guid]::NewGuid().ToString('N'))
& (Join-Path $PSScriptRoot 'TestNumericalPredictionBundle.ps1') -Runtime Java -OutputDirectory $folder
$files=@(Get-ChildItem -LiteralPath $folder -File)
if($files.Count -ne 1){throw 'Bundle must produce exactly one evidence file.'};$count++
$report=Get-Content -LiteralPath $files[0].FullName -Raw | ConvertFrom-Json
if($report.status -ne 'SYNTHETIC_CHECKS_PASSED_TRAINING_BLOCKED' -or $report.version -ne 'NUMERICAL_PREDICTION_BUNDLE_COLLECTION_V1' -or $report.suite -ne 'Baselines'){throw 'Wrong envelope.'};$count++
Assert-NumericalBaselineBundle $report.javaResult;$count++
foreach($case in @('status','realTraining','promotion','synthetic','checks','checkName','penalty','scenarios','hash','guard','model','rows','prediction','metric','target','winner','ranking','regression')){
    $bad=$report.javaResult | ConvertTo-Json -Depth 30 | ConvertFrom-Json
    switch($case){
        status{$bad.status='PASS'}realTraining{$bad.realMarketTrainingAuthorized=$true}promotion{$bad.automaticPromotionEnabled=$true}
        synthetic{$bad.syntheticOnly=$false}checks{$bad.checks=@($bad.checks|Select-Object -Skip 1)}checkName{$bad.checks[0].name='wrong'}
        penalty{$bad.configuration.ridgePenalty=1}scenarios{$bad.scenarios[1]=$bad.scenarios[0]}hash{$bad.scenarios[0].modelSha256='missing'}
        guard{$bad.scenarios[0].guard.status='FAILED'}model{$bad.scenarios[0].model.scales[0]=0}
        rows{$bad.scenarios[0].test.comparisons[0].predictions=@()}
        prediction{$bad.scenarios[0].test.comparisons[0].predictions[0].predicted=1}
        metric{$bad.scenarios[0].test.comparisons[2].errors.equalDateWeighted.mae=0}
        target{$bad.scenarios[0].test.comparisons[2].predictions[0].observed=999}
        winner{$bad.scenarios[0].test.lowestMaePredictors=@('ZERO')}
        ranking{$bad.scenarios[0].test.comparisons[0].ranking.dateCount=14}
        regression{$bad.evaluationRegression.checkCount=21}
    }
    $rejected=$false;try{Assert-NumericalBaselineBundle $bad}catch{$rejected=$true}
    if(-not $rejected){throw "Accepted corrupt bundle: $case"};$count++
}
Write-Host "Baseline workflow passed: $count assertions. Evidence: $folder"
