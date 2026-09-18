#Requires -Version 5.1
# Offline assessment and entrypoint tests only; no live service or database calls.
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'NumericalDataReadiness.ps1')
$testState=[pscustomobject]@{checks=0;httpCalls=0}
function Assert-Readiness([bool]$Condition,[string]$Message){if(-not $Condition){throw $Message};$testState.checks++}
$run=[guid]'5bdbfcc1-d990-48d8-9e98-d4927596d917'
function New-AuditFixture {
    [pscustomobject]@{
        datasetRunId=$run.ToString();datasetContractVersion='PROTOTYPE_SWING_TRAINING_DATASET_V1';sourceUniverseCode='CURRENT_SNAPSHOT_PROTOTYPE';status='REVIEW_REQUIRED';datasetManifestHash=('a'*64)
        asOf='2026-06-05';labelThrough='2026-09-08';instrumentCount=10;featureEligibleCount=8;fullyLabeledCount=6;rightCensoredCount=2;insufficientHistoryCount=1;staleCount=1;noEligibleDataCount=0;persistedItemCount=10;persistedLabelCount=18
        pointInTimeSafe=$true;futureLabelsSeparated=$true;survivorshipRiskPresent=$true;prototypeTrainingEligible=$true;benchmarkTrainingEligible=$false
        databaseWritesPerformed=$false;ollamaCallCount=0;signalsCreated=0;ordersCreated=0;failedCheckpoints=@()
        classificationCounts=@([pscustomobject]@{classification='LABELED';count=6},[pscustomobject]@{classification='RIGHT_CENSORED';count=2},[pscustomobject]@{classification='INSUFFICIENT_HISTORY';count=1},[pscustomobject]@{classification='STALE';count=1})
        horizonAudits=@(5,20,60 | ForEach-Object {[pscustomobject]@{horizonSessions=$_;labelCount=6}})
    }
}
$r=Measure-NumericalDataReadiness (New-AuditFixture) $run
Assert-Readiness ($r.status -eq 'PROTOTYPE_AUDIT_CONSISTENT_NOT_TRAINING_READY' -and $r.failures.Count -eq 0) 'Valid fixture blocked.'
Assert-Readiness ($r.featureEligiblePercent -eq 80 -and $r.fullyLabeledPercent -eq 60 -and $r.reported20SessionLabelCount -eq 6) 'Bad denominators.'
Assert-Readiness (-not $r.trainingAuthorized -and $r.observedDecisionDateCount -eq 1 -and $r.blockers.Count -eq 5) 'Single-date audit authorized training.'
foreach ($field in @('instrumentCount','persistedItemCount','persistedLabelCount','featureEligibleCount','fullyLabeledCount')) {
    $a=New-AuditFixture;$a.$field++
    Assert-Readiness ((Measure-NumericalDataReadiness $a $run).status -eq 'AUDIT_BLOCKED') ('Count mismatch accepted: '+$field)
}
foreach ($field in @('futureLabelsSeparated','pointInTimeSafe','prototypeTrainingEligible')) {
    $a=New-AuditFixture;$a.$field=$false
    Assert-Readiness ((Measure-NumericalDataReadiness $a $run).status -eq 'AUDIT_BLOCKED') ('Unsafe flag accepted: '+$field)
}
foreach ($field in @('databaseWritesPerformed','ordersCreated','ollamaCallCount')) {
    $a=New-AuditFixture;$a.$field=1
    Assert-Readiness ((Measure-NumericalDataReadiness $a $run).status -eq 'AUDIT_BLOCKED') 'Side effect accepted.'
}
$a=New-AuditFixture;$a.PSObject.Properties.Remove('instrumentCount')
Assert-Readiness ((Measure-NumericalDataReadiness $a $run).failures -contains 'INVALID_COUNT_instrumentCount') 'Missing count accepted.'
$a=New-AuditFixture;$a.instrumentCount='10'
Assert-Readiness ((Measure-NumericalDataReadiness $a $run).status -eq 'AUDIT_BLOCKED') 'String count accepted.'
$a=New-AuditFixture;$a.horizonAudits=@($a.horizonAudits[0],$a.horizonAudits[0],$a.horizonAudits[2])
Assert-Readiness ((Measure-NumericalDataReadiness $a $run).failures -contains 'HORIZON_DUPLICATE_OR_MISSING_20') 'Missing 20-session horizon accepted.'
$a=New-AuditFixture;$a.horizonAudits[1].labelCount=0
Assert-Readiness ((Measure-NumericalDataReadiness $a $run).failures -contains 'NO_20_SESSION_LABELS') 'Zero labels accepted.'
$a=New-AuditFixture;$a.classificationCounts[0].count=5
Assert-Readiness ((Measure-NumericalDataReadiness $a $run).status -eq 'AUDIT_BLOCKED') 'Actual classification mismatch accepted.'
$a=New-AuditFixture;$a.failedCheckpoints=@('LABEL_COUNT')
Assert-Readiness ((Measure-NumericalDataReadiness $a $run).failures -contains 'SERVER_CHECKPOINT_FAILURES') 'Server failure ignored.'
$a=New-AuditFixture;$a.labelThrough=$a.asOf
Assert-Readiness ((Measure-NumericalDataReadiness $a $run).status -eq 'AUDIT_BLOCKED') 'Invalid window accepted.'
Assert-Readiness ((Measure-NumericalDataReadiness (New-AuditFixture) ([guid]::NewGuid())).failures -contains 'DATASET_ID_MISMATCH') 'Run mismatch accepted.'
$root=Join-Path ([IO.Path]::GetTempPath()) ('marketbrain-readiness-test-'+[guid]::NewGuid().ToString('N'))
[void](New-Item -ItemType Directory -Path $root)
$fixture=Join-Path $root 'audit.json'
[IO.File]::WriteAllText($fixture,((New-AuditFixture) | ConvertTo-Json -Depth 10))
function Invoke-RestMethod {
    param($Uri,$Method,$TimeoutSec,$MaximumRedirection,$ErrorAction)
    $testState.httpCalls++
    Assert-Readiness ($Method -eq 'Get' -and $MaximumRedirection -eq 0 -and $TimeoutSec -le 60) 'Unsafe HTTP parameters.'
    if($Uri -eq 'http://127.0.0.1:8080/actuator/health'){return [pscustomobject]@{status='UP'}}
    Assert-Readiness ($Uri -eq ('http://127.0.0.1:8080/api/v1/training/prototype-swing-dataset-audit?datasetRunId='+$run)) 'Wrong endpoint or missing explicit run.'
    return New-AuditFixture
}
$entry=Join-Path $PSScriptRoot 'GetNumericalPredictionDataReadiness.ps1'
& $entry -DatasetRunId $run -OutputDirectory $root -ExistingAuditPath $fixture
Assert-Readiness ($testState.httpCalls -eq 0) 'Saved-audit mode called API.'
& $entry -DatasetRunId $run -OutputDirectory $root
Assert-Readiness ($testState.httpCalls -eq 2) 'Live mode wrong call count.'
$reports=@(Get-ChildItem -LiteralPath $root -Filter 'numerical-data-readiness-*.json')
Assert-Readiness ($reports.Count -eq 2) 'Reports collided.'
foreach($file in $reports){$saved=Get-Content $file.FullName -Raw | ConvertFrom-Json;Assert-Readiness ($saved.status -eq 'PROTOTYPE_AUDIT_CONSISTENT_NOT_TRAINING_READY' -and -not $saved.assessment.trainingAuthorized) 'Report granted training.'}
function Invoke-RestMethod {throw 'SECRET_TEST_MARKER'}
$failed=$false;try{& $entry -DatasetRunId $run -OutputDirectory $root} catch {$failed=$true}
Assert-Readiness $failed 'Network failure swallowed.'
$last=Get-ChildItem $root -Filter 'numerical-data-readiness-*.json' | Sort-Object LastWriteTime -Descending | Select-Object -First 1
$raw=Get-Content $last.FullName -Raw;$saved=$raw | ConvertFrom-Json
Assert-Readiness ($saved.status -eq 'FAILED_PARTIAL_REPORT' -and $raw -notmatch 'SECRET_TEST_MARKER') 'Partial failure report missing or leaked error body.'
Write-Host "PASS: $($testState.checks) offline readiness assertions. Fixtures retained: $root"
