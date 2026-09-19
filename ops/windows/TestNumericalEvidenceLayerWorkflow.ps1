#Requires -Version 5.1
[CmdletBinding()]
param([Parameter(Mandatory=$true)][string]$SavedMappingReportPath)
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'NumericalEvidenceLayer.ps1')
$repo=(Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$testRoot=Join-Path $repo ('marketbrain-service\target\evidence-workflow-'+[guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $testRoot | Out-Null
$script:checks=0
function Check([bool]$Value,[string]$Name){if(-not $Value){throw "Assertion failed: $Name"};$script:checks++}
function Reject([scriptblock]$Action,[string]$Name){$failed=$false;try{& $Action | Out-Null}catch{$failed=$true};Check $failed $Name}
$inputHash=(Get-FileHash -LiteralPath $SavedMappingReportPath).Hash
& (Join-Path $PSScriptRoot 'TestNumericalEvidenceLayerBundle.ps1') -SavedMappingReportPath $SavedMappingReportPath -OutputDirectory (Join-Path $testRoot 'initial')
$file=Get-ChildItem -LiteralPath (Join-Path $testRoot 'initial') -Filter '*.json' | Select-Object -First 1
$report=Get-Content -LiteralPath $file.FullName -Raw | ConvertFrom-Json
Check ($report.status -ceq 'EVIDENCE_ENGINEERING_PASSED_COLLECTION_AND_FIT_BLOCKED') 'complete bundle'
Check ($report.retrospective.rowCount -eq 600 -and $report.retrospective.lateReceiptRows -eq 600 -and $null -eq $report.retrospective.retrospectiveTrainingEligibleRows) 'honest saved eligibility'
Check ((Get-FileHash -LiteralPath $SavedMappingReportPath).Hash -ceq $inputHash) 'input unchanged'
$raw=$report.process.stdout
Assert-EvidenceLayerResult ($raw | ConvertFrom-Json);$script:checks++
foreach($key in @('marketDataCollectionEnabled','marketFitAuthorized','databaseWritesPerformed','actionExecutionEnabled')){
    $r=$raw | ConvertFrom-Json;$r.$key=$true;Reject {Assert-EvidenceLayerResult $r} "reject $key"
}
foreach($key in @('ordersCreated','providerCallCount','llmCallCount','signalsCreated')){
    $r=$raw | ConvertFrom-Json;$r.$key=1;Reject {Assert-EvidenceLayerResult $r} "reject $key"
}
$mutations=@(
    {param($r) $r.checks[0].passed=$false},
    {param($r) $r.checks[1].name=$r.checks[0].name},
    {param($r) $r.audit.entries[1].previousHash='0'*64},
    {param($r) $r.audit.entries[0].snapshotId='0'*64},
    {param($r) $r.audit.entries[1].disposition='ORIGINAL_RECORDED'},
    {param($r) $r.audit.entries[2].snapshot.supersedesId='0'*64},
    {param($r) $r.audit.entries[0].assessment.trainingEligible=$true},
    {param($r) $r.audit.entries[0].assessment.collectionAuthorized=$true},
    {param($r) $r.audit.entries[3].assessment.reasons=@()},
    {param($r) $r.recovery.sourceFileHash='0'*64},
    {param($r) $r.recovery.recoveredFileHash='1'*64},
    {param($r) $r.recovery.recoveredEntries=2},
    {param($r) $r.fixturePolicyNotRuntimeDefaults.maxFeatureAgeSeconds=600},
    {param($r) $r.featureOrder[0]='actualRank'},
    {param($r) $r.ledgerBase64='AA=='},
    {param($r) $b=[Convert]::FromBase64String($r.ledgerBase64);$b[$b.Length-1]=$b[$b.Length-1] -bxor 1;$r.ledgerBase64=[Convert]::ToBase64String($b);$r.audit.fileHash=Get-EvidenceBytesHash $b}
)
foreach($mutation in $mutations){$r=$raw | ConvertFrom-Json;& $mutation $r;Reject {Assert-EvidenceLayerResult $r} 'tampered evidence'}
# Completed process output can be reused after a reviewer interruption without executing Java again.
$report.status='FAILED';$report.failure='simulated post-process interruption'
$checkpoint=Join-Path $testRoot 'checkpoint.json';Save-NumericalHistoryReport $report $checkpoint -Compact
& (Join-Path $PSScriptRoot 'TestNumericalEvidenceLayerBundle.ps1') -SavedMappingReportPath $SavedMappingReportPath -OutputDirectory (Join-Path $testRoot 'replay') -ResumeReport $checkpoint
$replayFile=Get-ChildItem -LiteralPath (Join-Path $testRoot 'replay') -Filter '*.json' | Select-Object -First 1
$replay=Get-Content -LiteralPath $replayFile.FullName -Raw | ConvertFrom-Json
Check ($replay.executionMode -ceq 'OFFLINE_SAVED_RESULT_REVIEW' -and $replay.process.stdout -ceq $raw) 'reuse without JVM'
Check ($replay.previousReportSha256 -ceq (Get-FileHash -LiteralPath $checkpoint).Hash) 'replay source binding'
$report.manifest.source='0'*64;Save-NumericalHistoryReport $report $checkpoint -Compact
Reject {& (Join-Path $PSScriptRoot 'TestNumericalEvidenceLayerBundle.ps1') -SavedMappingReportPath $SavedMappingReportPath -OutputDirectory (Join-Path $testRoot 'bad-replay') -ResumeReport $checkpoint} 'changed implementation rejects replay'
$failureFile=Get-ChildItem -LiteralPath (Join-Path $testRoot 'bad-replay') -Filter '*.json' | Select-Object -First 1
$failure=Get-Content -LiteralPath $failureFile.FullName -Raw | ConvertFrom-Json
Check ($failure.status -ceq 'FAILED' -and $null -eq $failure.process -and $failure.failure -like '*identity mismatch*') 'failure checkpoint before execution'
Reject {Get-RetrospectiveSnapshotAssessment $checkpoint} 'unapproved snapshot rejects'
Reject {Get-RetrospectiveSnapshotAssessment (Join-Path $testRoot 'missing.json')} 'missing input no recollection'
Check ((Get-FileHash -LiteralPath $SavedMappingReportPath).Hash -ceq $inputHash) 'input remains unchanged at end'
Write-Host "PASS: $script:checks evidence workflow assertions. Retained local fixture reports: $testRoot"
