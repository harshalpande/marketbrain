#Requires -Version 5.1
# Developer offline checks only. No Docker, service, provider, database or model.
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'NumericalTenFeatureEngineering.ps1')
$folder=Join-Path $PSScriptRoot ('..\..\marketbrain-service\target\ten-feature-workflow-'+[guid]::NewGuid().ToString('N'))
$runner=Join-Path $PSScriptRoot 'TestNumericalTenFeatureBundle.ps1'
$count=0
& $runner -Runtime Java -OutputDirectory $folder
$files=@(Get-ChildItem -LiteralPath $folder -File)
if($files.Count -ne 1){throw 'Expected one shareable result.'};$count++
$original=$files[0].FullName;$originalHash=(Get-FileHash -LiteralPath $original).Hash
$r=Get-Content -LiteralPath $original -Raw | ConvertFrom-Json
if($r.status -cne 'SYNTHETIC_CHECKS_PASSED_MARKET_FIT_BLOCKED'){throw 'Wrong envelope status.'};$count++
Assert-TenFeatureBundle $r.javaResult;$count++
foreach($case in @('status','safety','check','duplicateCheck','alpha','featureOrder','featureUnits','constantCoefficient','constant','scale','coefficient','target','metric','prediction','cost','loss','artifact','uncertainty','coverage','gate')) {
    $bad=$r.javaResult | ConvertTo-Json -Depth 60 | ConvertFrom-Json
    switch($case){
        status {$bad.status='PASS'} safety {$bad.actionExecutionEnabled=$true}
        check {$bad.checks=@($bad.checks | Select-Object -Skip 1)} duplicateCheck {$bad.checks[1]=$bad.checks[0]}
        alpha {$bad.configuration.alpha=1} featureOrder {$bad.folds[0].model.featureOrder[0]='actualRank'}
        featureUnits {$bad.folds[0].model.featureUnits[0]='RATIO'} constantCoefficient {$bad.folds[0].model.coefficients[9]=2}
        constant {$bad.folds[0].model.scales[9]=0} scale {$bad.folds[0].model.scales[0]=0}
        coefficient {$bad.folds[0].model.coefficients[0]+=1} target {$bad.folds[0].test.comparisons[0].predictions[0].observed=999}
        metric {$bad.folds[0].test.comparisons[0].metrics.mae=999} prediction {$bad.folds[0].test.comparisons[2].predictions[0].predicted=999}
        cost {$bad.folds[0].test.comparisons[2].hypotheticalCosts[0].selectedCount=999}
        loss {$bad.folds[2].test.comparisons[2].maeImprovementVsZeroPercent=99}
        artifact {$bad.folds[0].artifact+='x'} uncertainty {$bad.syntheticUncertaintyChecks[0].scope='MARKET_ACCEPTED'}
        coverage {$bad.folds[0].test.evaluatedRows=1} gate {$bad.readiness.blockers=@()}
    }
    $rejected=$false;try{Assert-TenFeatureBundle $bad}catch{$rejected=$true}
    if(-not $rejected){throw "Accepted corrupt result: $case"};$count++
}
& $runner -Runtime Java -OutputDirectory $folder -ResumeReport $original
$replayed=Get-ChildItem -LiteralPath $folder -File | Where-Object {$_.FullName -ne $original} | Select-Object -First 1
$replay=Get-Content -LiteralPath $replayed.FullName -Raw | ConvertFrom-Json
if($replay.executionMode -cne 'OFFLINE_SAVED_RESULT_REVIEW' -or $replay.previousReportSha256 -cne $originalHash){throw 'Resume did not bind original evidence.'};$count++
if((Get-FileHash -LiteralPath $original).Hash -cne $originalHash){throw 'Original evidence changed.'};$count++
# Bound child timeout, without invoking any service or model.
$process=Invoke-EvaluationProcess (Get-Command powershell.exe).Source @('-NoProfile','-Command','Start-Sleep -Seconds 10') 1
if(-not $process.timedOut -or $process.exitCode -ne -999){throw 'Timeout not bounded.'};$count++
# Serialize test fixtures using the existing atomic checkpoint writer.
foreach($case in @('manifest','checksum','failedProcess','partial')) {
    $bad=$r | ConvertTo-Json -Depth 60 | ConvertFrom-Json
    switch($case){manifest {$bad.manifest.source='changed'} checksum {$bad.javaResultTextSha256='wrong'} failedProcess {$bad.process.exitCode=1} partial {$bad.javaResult=$null}}
    $fixture=Join-Path $folder ($case+'.json');Save-NumericalHistoryReport $bad $fixture -Compact
    $before=@(Get-ChildItem -LiteralPath $folder -Filter 'numerical-ten-feature-*.json').Count
    $rejected=$false;try{& $runner -Runtime Java -OutputDirectory $folder -ResumeReport $fixture}catch{$rejected=$true}
    if(-not $rejected){throw "Accepted invalid resume: $case"};$count++
    $after=@(Get-ChildItem -LiteralPath $folder -Filter 'numerical-ten-feature-*.json')
    if($after.Count -ne $before+1){throw 'Failure evidence not persisted.'};$count++
}
$oldCulture=[Threading.Thread]::CurrentThread.CurrentCulture
try {
    foreach($culture in @('en-US','en-IN','fr-FR')) {
        [Threading.Thread]::CurrentThread.CurrentCulture=[Globalization.CultureInfo]::GetCultureInfo($culture)
        Assert-TenFeatureBundle $r.javaResult;$count++
    }
} finally {[Threading.Thread]::CurrentThread.CurrentCulture=$oldCulture}
$utc=[datetime]::SpecifyKind([datetime]'2020-01-01T10:30:00',[DateTimeKind]::Utc)
foreach($value in @('2020-01-01T10:30:00Z','2020-01-01T16:00:00+05:30',$utc,$utc.ToLocalTime(),([DateTimeOffset]$utc))) {
    if((ConvertTo-TenFeatureUtc $value).UtcTicks -ne $utc.Ticks){throw 'Timestamp drift.'};$count++
}
foreach($value in @('2020-01-01T10:30:00','not-a-date',[datetime]::SpecifyKind($utc,[DateTimeKind]::Unspecified))) {
    $rejected=$false;try{ConvertTo-TenFeatureUtc $value | Out-Null}catch{$rejected=$true}
    if(-not $rejected){throw 'Ambiguous timestamp accepted.'};$count++
}
Write-Host "Ten-feature workflow passed: $count assertions. Evidence: $folder"
