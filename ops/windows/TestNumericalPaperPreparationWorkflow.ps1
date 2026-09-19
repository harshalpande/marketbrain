#Requires -Version 5.1
[CmdletBinding()]
param()
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'NumericalPaperPreparation.ps1')
$repo=(Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$testRoot=Join-Path $repo ('marketbrain-service\target\paper-preparation-workflow-'+[guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $testRoot | Out-Null
$script:checks=0
function Check([bool]$Value,[string]$Name){if(-not $Value){throw "Assertion failed: $Name"};$script:checks++}
function Reject([scriptblock]$Action,[string]$Name){$failed=$false;try{& $Action | Out-Null}catch{$failed=$true};Check $failed $Name}
$runner=Join-Path $PSScriptRoot 'TestNumericalPaperPreparationBundle.ps1'
& $runner -OutputDirectory (Join-Path $testRoot 'initial')
$file=Get-ChildItem -LiteralPath (Join-Path $testRoot 'initial') -Filter '*.json' | Select-Object -First 1
$report=Get-Content -LiteralPath $file.FullName -Raw | ConvertFrom-Json
Check ($report.status -ceq 'PREPARATION_CHECKS_PASSED_RUNTIME_RELEASE_BLOCKED') 'complete bundle'
$raw=$report.process.stdout
Assert-NumericalPaperPreparation ($raw|ConvertFrom-Json) $report.policyReview;$script:checks++
foreach($key in @('runtimePaperAccountEnabled','databaseWritesPerformed','actionExecutionEnabled')){
    $r=$raw|ConvertFrom-Json;$r.$key=$true;Reject {Assert-NumericalPaperPreparation $r $report.policyReview} "reject $key"
}
foreach($key in @('providerCallCount','modelCallCount','ordersCreated','signalsCreated')){
    $r=$raw|ConvertFrom-Json;$r.$key=1;Reject {Assert-NumericalPaperPreparation $r $report.policyReview} "reject $key"
}
$mutations=@(
    {param($r) $r.checks[0].passed=$false},
    {param($r) $r.checks[1].name=$r.checks[0].name},
    {param($r) $r.accountingEvidence.initialCashPaise=10000001},
    {param($r) $r.accountingEvidence.account.cashPaise++},
    {param($r) $r.accountingEvidence.account.availableCashPaise++},
    {param($r) $r.accountingEvidence.account.reservedCashPaise=0},
    {param($r) $r.accountingEvidence.account.holdings.FIXTURE=9},
    {param($r) $r.accountingEvidence.account.orders.sell.status='OPEN'},
    {param($r) $r.accountingEvidence.journal[1].debitPaise++},
    {param($r) $r.accountingEvidence.journal[2].fillId=$r.accountingEvidence.journal[1].fillId},
    {param($r) $r.accountingEvidence.journal[1].feePaise=-1},
    {param($r) $r.accountingEvidence.journal[1].quantity=1.5},
    {param($r) $r.accountingEvidence.account.orders.buy.filledQuantity=9},
    {param($r) $r.accountingEvidence.journal[1].orderId='absent'},
    {param($r) $r.accountingEvidence.journal[1].at='2025-01-01T00:00:00Z'},
    {param($r) $r.accountingEvidence.journal[1].symbol='WRONG'},
    {param($r) $r.accountingEvidence.journal[1].kind='SELL_FILL'}
)
foreach($mutation in $mutations){$r=$raw|ConvertFrom-Json;& $mutation $r;Reject {Assert-NumericalPaperPreparation $r $report.policyReview} 'tampered paper evidence'}
$badPolicy=$report.policyReview|ConvertTo-Json -Depth 50|ConvertFrom-Json;$badPolicy.proposal.release.collectionAuthorized=$true
Reject {Assert-NumericalPaperPreparation ($raw|ConvertFrom-Json) $badPolicy} 'unapproved capture release'
$badPolicy=$report.policyReview|ConvertTo-Json -Depth 50|ConvertFrom-Json;$badPolicy.proposal.approvedByOwner=$true
Reject {Assert-NumericalPaperPreparation ($raw|ConvertFrom-Json) $badPolicy} 'false owner approval'
$checkpoint=Join-Path $testRoot 'completed-checkpoint.json';$report.status='FAILED';$report.failure='simulated reviewer interruption'
Save-NumericalHistoryReport $report $checkpoint -Compact
& $runner -OutputDirectory (Join-Path $testRoot 'replay') -ResumeReport $checkpoint
$replayFile=Get-ChildItem -LiteralPath (Join-Path $testRoot 'replay') -Filter '*.json' | Select-Object -First 1
$replay=Get-Content -LiteralPath $replayFile.FullName -Raw|ConvertFrom-Json
Check ($replay.executionMode -ceq 'OFFLINE_SAVED_RESULT_REVIEW' -and $replay.process.stdout -ceq $raw) 'completed output reused without JVM'
Check ($replay.previousReportSha256 -ceq (Get-FileHash -LiteralPath $checkpoint).Hash) 'replay checksum binding'
$report.manifest.source='0'*64;Save-NumericalHistoryReport $report $checkpoint -Compact
Reject {& $runner -OutputDirectory (Join-Path $testRoot 'bad-replay') -ResumeReport $checkpoint} 'changed source prevents replay'
$failureFile=Get-ChildItem -LiteralPath (Join-Path $testRoot 'bad-replay') -Filter '*.json' | Select-Object -First 1
$failure=Get-Content -LiteralPath $failureFile.FullName -Raw|ConvertFrom-Json
Check ($failure.status -ceq 'FAILED' -and $null -eq $failure.process -and $failure.failure -like '*mismatch*') 'failed replay checkpoint preserved without JVM'
Write-Host "PASS: $script:checks combined preparation workflow assertions. Local evidence: $testRoot"
