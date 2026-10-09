# Offline only: the complete Docker boundary is replaced with fixtures before invocation.
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'TestPaperPersistenceReviewWorkflow.ps1')
. (Join-Path $PSScriptRoot 'PaperApprovalVerification.ps1')
. (Join-Path $PSScriptRoot 'PaperDeliveryVerification.ps1')
$script:deliveryStart=$script:count
$java=Get-Content -LiteralPath (Join-Path $PSScriptRoot '../../marketbrain-service/src/main/java/in/marketbrain/paper/PaperDeliveryVerification.java') -Raw
$script:deliveryNames=@([regex]::Matches($java,'check\("([a-z0-9_]+)"')|ForEach-Object {$_.Groups[1].Value})
Check ($script:deliveryNames.Count -eq 24) '24 fixed delivery declarations'
function Sample([string]$Phase){
    $names=if($Phase -ceq '--prepare'){@($script:deliveryNames|Select-Object -First 21)}else{@($script:deliveryNames|Select-Object -Last 3)}
    @{version='PAPER_DELIVERY_REVIEW_V1';phase=$Phase;schema=$schema;status='ISOLATED_DELIVERY_CHECKS_PASSED';checkCount=$names.Count;failedCount=0;elapsedSeconds=1;
      checks=@($names|ForEach-Object {@{name=$_;passed=$true;elapsedMillis=1}});applicationDatabaseAccessed=$false;actionExecutionEnabled=$false;syntheticDatabaseWritesPerformed=$true;
      providerCalls=0;telegramCalls=0;modelCalls=0;httpTransport='FAKE_NO_NETWORK';cashPaise=10000000;reservedCashPaise=0;ledgerRevision=0;orderCount=0;fillCount=0;decisionCount=1;
      deliveryCount=3;uncertainCount=1;pendingCount=$(if($Phase -ceq '--prepare'){1}else{0})}|ConvertTo-Json -Depth 6|ConvertFrom-Json
}
foreach($phase in @('--prepare','--recover')){Assert-PaperDeliveryPhase (Sample $phase) $phase $schema;Check $true 'valid delivery phase'}
foreach($mutation in @(
    {param($r)$r.applicationDatabaseAccessed=$true},{param($r)$r.actionExecutionEnabled=$true},{param($r)$r.syntheticDatabaseWritesPerformed=$false},
    {param($r)$r.providerCalls=1},{param($r)$r.telegramCalls=1},{param($r)$r.modelCalls=1},{param($r)$r.httpTransport='REAL'},
    {param($r)$r.orderCount=1},{param($r)$r.fillCount=1},{param($r)$r.cashPaise++},{param($r)$r.reservedCashPaise=1},{param($r)$r.ledgerRevision=1},
    {param($r)$r.deliveryCount=2},{param($r)$r.pendingCount=0},{param($r)$r.uncertainCount=0},{param($r)$r.decisionCount=2},
    {param($r)$r.version='OLD'},{param($r)$r.schema='public'},{param($r)$r.status='FAILED'},{param($r)$r.failedCount=1},
    {param($r)$r.checkCount--},{param($r)$r.checks[0].passed=$false},{param($r)$r.checks[0].name=$r.checks[1].name},{param($r)$r.cashPaise='10000000'},
    {param($r)$r.elapsedSeconds=-1},{param($r)$r.checks[0].elapsedMillis=-1}
)){$value=Sample '--prepare';& $mutation $value;Reject {Assert-PaperDeliveryPhase $value '--prepare' $schema} 'delivery mutation rejected'}
$script:failMock=$false;$script:failResolution=$false;$script:failPreflight=$false;$script:mockContainers=@{};$script:mockCalls=@()
$run=[scriptblock]::Create($mocked.Replace('$v.receipt.tailHash=''b''*64;', 'if(-not $ApprovalDelivery){$v.receipt.tailHash=''b''*64};'))
Reject {& $run -ApprovalReview -ApprovalDelivery -OutputDirectory (Join-Path $testRoot 'invalid')} 'mutually exclusive suites'
& $run -ApprovalDelivery -OutputDirectory (Join-Path $testRoot 'delivery-pass')
$file=Get-ChildItem -LiteralPath (Join-Path $testRoot 'delivery-pass') -Filter 'paper-delivery-*.json'|Select-Object -First 1
$ok=Get-Content -LiteralPath $file.FullName -Raw|ConvertFrom-Json
Check ($ok.version -ceq 'PAPER_DELIVERY_BUNDLE_V1' -and $ok.status -ceq 'ISOLATED_DELIVERY_PASSED_LIVE_TRANSPORT_AND_EXECUTION_BLOCKED') 'delivery result distinguished'
Check ($ok.prepare.checkCount -eq 21 -and $ok.recover.checkCount -eq 3) 'new suite selected'
Check (@($ok.cleanup|Where-Object action -eq 'REMOVED_SYNTHETIC_CONTAINER_AND_ANONYMOUS_VOLUMES').Count -eq 3) 'owned cleanup'
$script:failMock=$true;$script:mockContainers=@{}
Reject {& $run -ApprovalDelivery -OutputDirectory (Join-Path $testRoot 'delivery-fail')} 'failure propagated'
$file=Get-ChildItem -LiteralPath (Join-Path $testRoot 'delivery-fail') -Filter '*.json'|Select-Object -First 1
$bad=Get-Content -LiteralPath $file.FullName -Raw|ConvertFrom-Json
Check ($bad.status -ceq 'FAILED' -and $null -eq $bad.recover) 'no recovery after failure'
Check (@($bad.cleanup|Where-Object action -eq 'PRESERVED_STOP_REQUESTED').Count -eq 2) 'failed fixtures preserved'
Write-Host "PASS: $script:count combined offline assertions; $($script:count-$script:deliveryStart) delivery additions. Real PostgreSQL pending spare."
