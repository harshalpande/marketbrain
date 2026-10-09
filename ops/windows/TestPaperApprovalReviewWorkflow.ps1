# Entire Docker boundary is mocked. No provider, model or application database execution.
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'TestPaperPersistenceReviewWorkflow.ps1')
. (Join-Path $PSScriptRoot 'PaperApprovalVerification.ps1')
$script:approvalStart=$script:count
$java=Get-Content -LiteralPath (Join-Path $PSScriptRoot '../../marketbrain-service/src/main/java/in/marketbrain/paper/PaperApprovalVerification.java') -Raw
$script:approvalNames=@([regex]::Matches($java,'check\("([a-z0-9_]+)"')|ForEach-Object {$_.Groups[1].Value})
Check ($script:approvalNames.Count -eq 32) '32 fixed scenario declarations'
function Sample([string]$Phase){
    $names=if($Phase -ceq '--prepare'){@($script:approvalNames|Select-Object -First 30)}else{@($script:approvalNames|Select-Object -Last 2)}
    @{version='PAPER_APPROVAL_REVIEW_V1';phase=$Phase;schema=$schema;status='ISOLATED_APPROVAL_CHECKS_PASSED';checkCount=$names.Count;failedCount=0;elapsedSeconds=1;
      checks=@($names|ForEach-Object {@{name=$_;passed=$true;elapsedMillis=1}});applicationDatabaseAccessed=$false;actionExecutionEnabled=$false;syntheticDatabaseWritesPerformed=$true;
      providerCalls=0;telegramCalls=0;modelCalls=0;cashPaise=10000000;reservedCashPaise=0;ledgerRevision=0;orderCount=0;fillCount=0;decisionCount=1}|ConvertTo-Json -Depth 6|ConvertFrom-Json
}
foreach($phase in @('--prepare','--recover')){Assert-PaperApprovalPhase (Sample $phase) $phase $schema;Check $true 'valid approval phase'}
foreach($mutation in @(
    {param($r)$r.applicationDatabaseAccessed=$true},{param($r)$r.actionExecutionEnabled=$true},{param($r)$r.syntheticDatabaseWritesPerformed=$false},
    {param($r)$r.providerCalls=1},{param($r)$r.telegramCalls=1},{param($r)$r.modelCalls=1},{param($r)$r.orderCount=1},{param($r)$r.fillCount=1},
    {param($r)$r.ledgerRevision=1},{param($r)$r.cashPaise++},{param($r)$r.reservedCashPaise=1},{param($r)$r.decisionCount=2},
    {param($r)$r.version='OLD'},{param($r)$r.schema='public'},{param($r)$r.status='FAILED'},{param($r)$r.phase='wrong'},
    {param($r)$r.failedCount=1},{param($r)$r.checkCount--},{param($r)$r.checks[0].passed=$false},{param($r)$r.checks[0].name=$r.checks[1].name},
    {param($r)$r.cashPaise='10000000'},{param($r)$r.elapsedSeconds=-1},{param($r)$r.checks[0].elapsedMillis=-1}
)){$value=Sample '--prepare';& $mutation $value;Reject {Assert-PaperApprovalPhase $value '--prepare' $schema} 'approval mutation rejected'}
$script:failMock=$false;$script:failResolution=$false;$script:failPreflight=$false;$script:mockContainers=@{};$script:mockCalls=@()
$run=[scriptblock]::Create($mocked.Replace('$v.receipt.tailHash=''b''*64;', 'if(-not $ApprovalReview){$v.receipt.tailHash=''b''*64};'))
Reject {& $run -ApprovalReview -ApplicationLedger -OutputDirectory (Join-Path $testRoot 'invalid')} 'mutually exclusive suites'
& $run -ApprovalReview -OutputDirectory (Join-Path $testRoot 'approval-pass')
$file=Get-ChildItem -LiteralPath (Join-Path $testRoot 'approval-pass') -Filter 'paper-approval-*.json'|Select-Object -First 1
$ok=Get-Content -LiteralPath $file.FullName -Raw|ConvertFrom-Json
Check ($ok.version -ceq 'PAPER_APPROVAL_BUNDLE_V1' -and $ok.status -ceq 'ISOLATED_APPROVAL_PASSED_TRANSPORT_AND_EXECUTION_BLOCKED') 'approval result distinguished'
Check ($ok.prepare.checkCount -eq 30 -and $ok.recover.checkCount -eq 2) 'only new suite selected'
Check (@($ok.cleanup|Where-Object action -eq 'REMOVED_SYNTHETIC_CONTAINER_AND_ANONYMOUS_VOLUMES').Count -eq 3) 'owned cleanup'
Check (@($ok.steps|Where-Object step -eq 'restart fixture database').Count -eq 1) 'one isolated restart'
$script:failMock=$true;$script:mockContainers=@{}
Reject {& $run -ApprovalReview -OutputDirectory (Join-Path $testRoot 'approval-fail')} 'failure propagated'
$file=Get-ChildItem -LiteralPath (Join-Path $testRoot 'approval-fail') -Filter '*.json'|Select-Object -First 1
$bad=Get-Content -LiteralPath $file.FullName -Raw|ConvertFrom-Json
Check ($bad.status -ceq 'FAILED' -and $null -eq $bad.recover) 'no recovery after failure'
Check (@($bad.cleanup|Where-Object action -eq 'PRESERVED_STOP_REQUESTED').Count -eq 2) 'failed fixtures preserved'
Write-Host "PASS: $script:count combined offline assertions; $($script:count-$script:approvalStart) approval additions. Real PostgreSQL pending spare."
