# Reuse the fully mocked Docker harness, first preserving the old runner's regression coverage.
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'TestPaperPersistenceReviewWorkflow.ps1')
. (Join-Path $PSScriptRoot 'PaperLedgerVerification.ps1')
$script:ledgerCountStart=$script:count
$java=Get-Content -LiteralPath (Join-Path $PSScriptRoot '../../marketbrain-service/src/main/java/in/marketbrain/paper/PaperLedgerVerification.java') -Raw
$script:ledgerNames=@([regex]::Matches($java,'check\("([a-z0-9_]+)"')|ForEach-Object {$_.Groups[1].Value})
Check ($script:ledgerNames.Count -eq 31) '31 distinct fixture declarations'
function Sample([string]$Phase) {
    $names=if($Phase -ceq '--prepare'){@($script:ledgerNames|Select-Object -First 28)}else{@($script:ledgerNames|Select-Object -Last 3)}
    @{version='PAPER_APPLICATION_LEDGER_V1';phase=$Phase;schema=$schema;status='ISOLATED_LEDGER_CHECKS_PASSED';checkCount=$names.Count;failedCount=0;
        checks=@($names|ForEach-Object {@{name=$_;passed=$true}});applicationDatabaseAccessed=$false;actionExecutionEnabled=$false;syntheticDatabaseWritesPerformed=$true;
        cashPaise=9959990;reservedCashPaise=$(if($Phase -ceq '--prepare'){60690}else{0});revision=$(if($Phase -ceq '--prepare'){2}else{3})}|ConvertTo-Json -Depth 6|ConvertFrom-Json
}
foreach($phase in @('--prepare','--recover')){Assert-PaperLedgerPhase (Sample $phase) $phase $schema;Check $true 'valid ledger phase'}
foreach($mutation in @(
    {param($r)$r.applicationDatabaseAccessed=$true},{param($r)$r.actionExecutionEnabled=$true},{param($r)$r.syntheticDatabaseWritesPerformed=$false},
    {param($r)$r.version='OLD'},{param($r)$r.schema='public'},{param($r)$r.status='FAILED'},
    {param($r)$r.cashPaise++},{param($r)$r.reservedCashPaise=0},{param($r)$r.revision++},
    {param($r)$r.failedCount=1},{param($r)$r.checkCount--},{param($r)$r.checks[0].passed=$false},
    {param($r)$r.checks[0].name=$r.checks[1].name},{param($r)$r.cashPaise='9959990'}
)){$value=Sample '--prepare';& $mutation $value;Reject {Assert-PaperLedgerPhase $value '--prepare' $schema} 'ledger mutation rejected'}
$script:failMock=$false;$script:failResolution=$false;$script:failPreflight=$false;$script:mockContainers=@{};$script:mockCalls=@()
$run=[scriptblock]::Create($mocked.Replace('$v.receipt.tailHash=''b''*64;', 'if(-not $ApplicationLedger){$v.receipt.tailHash=''b''*64};'))
& $run -ApplicationLedger -OutputDirectory (Join-Path $testRoot 'ledger-pass')
$file=Get-ChildItem -LiteralPath (Join-Path $testRoot 'ledger-pass') -Filter 'paper-ledger-*.json'|Select-Object -First 1
$ok=Get-Content -LiteralPath $file.FullName -Raw|ConvertFrom-Json
Check ($ok.version -ceq 'PAPER_LEDGER_BUNDLE_V1' -and $ok.status -ceq 'ISOLATED_LEDGER_PASSED_APPLICATION_MIGRATION_PENDING') 'ledger result distinguished'
Check ($ok.prepare.checkCount -eq 28 -and $ok.recover.checkCount -eq 3) 'new suite selected'
Check (@($ok.cleanup|Where-Object action -eq 'REMOVED_SYNTHETIC_CONTAINER_AND_ANONYMOUS_VOLUMES').Count -eq 3) 'ledger owned cleanup'
Check (@($ok.steps|Where-Object step -eq 'restart fixture database').Count -eq 1) 'one ledger restart'
$script:failMock=$true;$script:mockContainers=@{}
Reject {& $run -ApplicationLedger -OutputDirectory (Join-Path $testRoot 'ledger-fail')} 'ledger failure propagated'
$file=Get-ChildItem -LiteralPath (Join-Path $testRoot 'ledger-fail') -Filter '*.json'|Select-Object -First 1
$bad=Get-Content -LiteralPath $file.FullName -Raw|ConvertFrom-Json
Check ($bad.status -ceq 'FAILED' -and $null -eq $bad.recover) 'no recovery after failure'
Check (@($bad.cleanup|Where-Object action -eq 'PRESERVED_STOP_REQUESTED').Count -eq 2) 'failed ledger fixtures preserved'
Write-Host "PASS: $script:count combined offline assertions; $($script:count-$script:ledgerCountStart) ledger additions. No real PostgreSQL run."
