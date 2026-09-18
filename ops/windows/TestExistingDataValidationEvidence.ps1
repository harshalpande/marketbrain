#Requires -Version 5.1
$ErrorActionPreference='Stop'
$root=Join-Path ([IO.Path]::GetTempPath()) ('marketbrain-saved-evidence-test-'+[guid]::NewGuid().ToString('N'))
[void](New-Item -ItemType Directory -Path $root)
$state=[pscustomobject]@{checks=0}
function Assert-Saved([bool]$Condition,[string]$Message){if(-not $Condition){throw $Message};$state.checks++}
function Invoke-RestMethod {throw 'Unexpected HTTP call'}
function Invoke-WebRequest {throw 'Unexpected HTTP call'}
$sample=[pscustomobject]@{jobId='fixture';qualityStatus='PASS';instrumentCount=50;totalCandles=124858;unresolvedFindingCount=0;providerMismatchCount=0;modelTrainingEligible=$true;secret='SECRET_TEST_MARKER';providerSpotChecks=@([pscustomobject]@{status='MATCHED'},[pscustomobject]@{status='MATCHED'})}
$fixture=Join-Path $root 'final-provider-quality-fixture.json'
[IO.File]::WriteAllText($fixture,($sample | ConvertTo-Json -Depth 5))
[IO.File]::WriteAllText((Join-Path $root 'final-provider-quality-invalid.json'),'{ invalid SECRET_TEST_MARKER')
[IO.File]::WriteAllText((Join-Path $root 'remaining-data-analysis-old.json'),($sample | ConvertTo-Json -Depth 5))
[IO.File]::WriteAllText((Join-Path $root 'credentials.json'),'SECRET_TEST_MARKER')
$large=Join-Path $root 'expansion-batch-4-final-provider-quality-large.json'
$stream=[IO.File]::Create($large);try{$stream.SetLength(16MB+1)}finally{$stream.Dispose()}
$medium=Join-Path $root 'expansion-batch-3-final-provider-quality-medium.json'
[IO.File]::WriteAllText($medium,('{"qualityStatus":"PASS","instrumentCount":200,"padding":"'+('x'*12MB)+'"}'))
$checkpoint=Join-Path $root 'expansion-batch-4-final-quality-checkpoints-fixture.json'
[IO.File]::WriteAllText($checkpoint,'{"status":"ELIGIBLE","failedInvariantCount":0,"failedInvariants":[],"databaseProviderChangedMetrics":[],"remediationOrJobCheckpointChanged":false}')
$entry=Join-Path $PSScriptRoot 'GetExistingDataValidationEvidence.ps1'
$out=Join-Path $root 'output'
& $entry -ReviewDirectory $root -OutputDirectory $out
$files=@(Get-ChildItem $out -Filter '*.json');Assert-Saved ($files.Count -eq 1) 'Expected one shareable report.'
$raw=Get-Content $files[0].FullName -Raw;$r=$raw | ConvertFrom-Json
Assert-Saved ($r.status -eq 'PARTIAL_SAVED_EVIDENCE_REVIEW_REQUIRED') 'Partial evidence hidden.'
Assert-Saved ($r.files.Count -eq 5 -and $r.summary.capturedSummaries -eq 3) 'Selection/summary count wrong.'
$saved=$r.files | Where-Object name -eq 'final-provider-quality-fixture.json'
Assert-Saved ($saved.sha256 -eq (Get-FileHash $fixture).Hash) 'Hash not over exact input bytes.'
Assert-Saved ($saved.metrics.savedProviderMatchedCount -eq 2 -and $saved.metrics.instrumentCount -eq 50) 'Saved metrics lost.'
Assert-Saved ($raw -notmatch 'SECRET_TEST_MARKER|credentials.json') 'Nonallowlisted data leaked.'
Assert-Saved (-not $r.trainingAuthorized -and $r.providerCallCount -eq 0 -and -not $r.databaseWritesPerformed) 'Training/side effects enabled.'
Assert-Saved (@($r.files | Where-Object status -eq 'SKIPPED_LINK_OR_SIZE_BUDGET').Count -eq 1) 'Oversized file read.'
Assert-Saved (@($r.files | Where-Object name -eq 'remaining-data-analysis-old.json').Count -eq 0) 'Intermediate report consumed final-only budget.'
Assert-Saved (($r.files | Where-Object name -eq 'expansion-batch-3-final-provider-quality-medium.json').metrics.instrumentCount -eq 200) '12 MiB final report lost.'
$checkpointMetrics=($r.files | Where-Object name -eq 'expansion-batch-4-final-quality-checkpoints-fixture.json').metrics
Assert-Saved ($checkpointMetrics.failedInvariantCount -eq 0 -and $checkpointMetrics.failedInvariantsCount -eq 0 -and $checkpointMetrics.databaseProviderChangedMetricsCount -eq 0) 'Checkpoint failure indicators lost.'
Assert-Saved (($r.files | Where-Object status -eq 'SKIPPED_LINK_OR_SIZE_BUDGET').skipReason -eq 'PER_FILE_LIMIT') 'Skip reason ambiguous.'
$allOut=Join-Path $root 'with-intermediate'
& $entry -ReviewDirectory $root -OutputDirectory $allOut -IncludeIntermediate
$all=Get-Content (Get-ChildItem $allOut -Filter '*.json')[0].FullName -Raw | ConvertFrom-Json
Assert-Saved ($all.files[-1].name -eq 'remaining-data-analysis-old.json' -and $all.selectionMode -eq 'FINAL_FIRST_WITH_INTERMEDIATE') 'Intermediate reports did not follow finals.'
$empty=Join-Path $root 'empty';[void](New-Item -ItemType Directory -Path $empty)
& $entry -ReviewDirectory $empty -OutputDirectory $empty
$r=Get-Content (Get-ChildItem $empty -Filter '*.json')[0].FullName -Raw | ConvertFrom-Json
Assert-Saved ($r.status -eq 'NO_SAVED_SUMMARY_FOUND' -and -not $r.trainingAuthorized) 'Missing evidence treated as validated.'
Write-Host "PASS: $($state.checks) saved-evidence assertions. Temporary fixtures retained: $root"
