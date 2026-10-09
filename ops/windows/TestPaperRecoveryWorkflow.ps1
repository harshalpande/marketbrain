# Offline only. All native Docker operations are replaced before the runner is invoked.
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'TestPaperPersistenceReviewWorkflow.ps1')
. (Join-Path $PSScriptRoot 'PaperApprovalVerification.ps1')
. (Join-Path $PSScriptRoot 'PaperRecoveryVerification.ps1')
$start=$script:count
$java=Get-Content (Join-Path $PSScriptRoot '../../marketbrain-service/src/main/java/in/marketbrain/paper/PaperRecoveryVerification.java') -Raw
$script:names=@([regex]::Matches($java,'check\("([a-z0-9_]+)"')|ForEach-Object {$_.Groups[1].Value})
Check ($script:names.Count -eq 14) '14 fixed recovery declarations'
function Sample([string]$Phase){
    $names=if($Phase -ceq '--prepare'){@($script:names|Select-Object -First 2)}else{@($script:names|Select-Object -Last 12)}
    @{version='PAPER_RECOVERY_REVIEW_V1';status='ISOLATED_RECOVERY_CHECKS_PASSED';phase=$Phase;schema=$schema;checkCount=$names.Count;failedCount=0;elapsedSeconds=1;checks=@($names|ForEach-Object {@{name=$_;passed=$true;elapsedMillis=1}});applicationDatabaseAccessed=$false;actionExecutionEnabled=$false;approvalWriterReady=$false;syntheticDatabaseWritesPerformed=$true;providerCalls=0;telegramCalls=0;modelCalls=0;snapshotHash=('a'*64);snapshotTableCount=20}|ConvertTo-Json -Depth 6|ConvertFrom-Json
}
foreach($phase in @('--prepare','--recover')){Assert-PaperRecoveryPhase (Sample $phase) $phase $schema;Check $true 'valid phase'}
foreach($field in @('failedCount','providerCalls','telegramCalls','modelCalls','checkCount')){$v=Sample '--recover';$v.$field++;Reject {Assert-PaperRecoveryPhase $v '--recover' $schema} 'invalid count'}
foreach($field in @('applicationDatabaseAccessed','actionExecutionEnabled','approvalWriterReady','syntheticDatabaseWritesPerformed')){$v=Sample '--recover';$v.$field=-not $v.$field;Reject {Assert-PaperRecoveryPhase $v '--recover' $schema} 'invalid safety flag'}
foreach($mutation in @({param($v)$v.checks[0].passed=$false},{param($v)$v.checks[0].name=$v.checks[1].name},{param($v)$v.snapshotHash='bad'},{param($v)$v.snapshotTableCount=257},{param($v)$v.elapsedSeconds=-1})){$v=Sample '--recover';& $mutation $v;Reject {Assert-PaperRecoveryPhase $v '--recover' $schema} 'invalid recovery evidence'}
$b=[pscustomobject]@{format='CUSTOM';scope='SYNTHETIC_SCHEMA_ONLY';sourceDatabase='paper_fixture';restoredDatabase='paper_restore';sha256=('b'*64);restored=$true;containsApplicationData=$false}
Assert-PaperRecoveryPair (Sample '--prepare') (Sample '--recover') $b;Check $true 'valid pair'
$v=Sample '--recover';$v.snapshotHash='c'*64;Reject {Assert-PaperRecoveryPair (Sample '--prepare') $v $b} 'mismatched snapshot'
$b.restored=$false;Reject {Assert-PaperRecoveryPair (Sample '--prepare') (Sample '--recover') $b} 'restore required';$b.restored=$true
$b.containsApplicationData=$true;Reject {Assert-PaperRecoveryPair (Sample '--prepare') (Sample '--recover') $b} 'application data forbidden'
$mockedRecovery=$mocked.Replace('$v.receipt.tailHash=''b''*64;', '')
$mockedRecovery=$mockedRecovery.Replace("switch(`$Step){",@'
    if($Step -ceq $script:failRecoveryStep){throw 'Injected recovery stage failure'}
    $script:recoveryArguments+=,@($Arguments)
    switch($Step){
        'hash synthetic archive' {$stdout=('b'*64)+'  '+$Arguments[3]}
'@)
Check (-not $mockedRecovery.Contains('[Diagnostics.Process]::new()')) 'native Docker entirely replaced'
$runRecovery=[scriptblock]::Create($mockedRecovery)
function Reset-RecoveryMock {$script:failMock=$false;$script:failResolution=$false;$script:failPreflight=$false;$script:mockContainers=@{};$script:mockCalls=@();$script:recoveryArguments=@();$script:failRecoveryStep=''}
Reset-RecoveryMock
Reject {& $runRecovery -ApprovalStorage -ApprovalRecovery -OutputDirectory (Join-Path $testRoot 'recovery-invalid')} 'exclusive switches'
& $runRecovery -ApprovalRecovery -OutputDirectory (Join-Path $testRoot 'recovery-pass')
$r=Get-Content (Get-ChildItem (Join-Path $testRoot 'recovery-pass') -Filter '*.json'|Select-Object -First 1).FullName -Raw|ConvertFrom-Json
Check ($r.status -ceq 'ISOLATED_RECOVERY_PASSED_APPLICATION_RELEASE_BLOCKED') 'success status'
Check ($r.prepare.checkCount -eq 2 -and $r.recover.checkCount -eq 12) 'phase counts'
Check ($r.backup.restored -and -not $r.actualApplicationRestoreVerified -and -not $r.approvalWriterReady) 'bounded acceptance'
Check (@($r.cleanup|Where-Object action -eq 'REMOVED_SYNTHETIC_CONTAINER_AND_ANONYMOUS_VOLUMES').Count -eq 3) 'owned cleanup'
Check (($script:mockCalls.IndexOf('dump synthetic schema') -lt $script:mockCalls.IndexOf('restore synthetic archive atomically')) -and ($script:mockCalls.IndexOf('restore synthetic archive atomically') -lt $script:mockCalls.IndexOf('fresh JVM recovery verification'))) 'backup restore precedes validation'
$restore=@($script:recoveryArguments|Where-Object {$_ -contains 'pg_restore'})[0]
Check (($restore -contains '--single-transaction') -and ($restore -contains '--exit-on-error') -and ($restore -contains '--dbname=paper_restore') -and -not ($restore -contains '--clean')) 'atomic new target only'
foreach($stage in @('dump synthetic schema','hash synthetic archive','create restore database','restore synthetic archive atomically','fresh JVM recovery verification')){
    Reset-RecoveryMock;$script:failRecoveryStep=$stage;$dir=Join-Path $testRoot ('rf-'+[guid]::NewGuid().ToString('N').Substring(0,6))
    Reject {& $runRecovery -ApprovalRecovery -OutputDirectory $dir} 'stage failure stops'
    $r=Get-Content (Get-ChildItem $dir -Filter '*.json'|Select-Object -First 1).FullName -Raw|ConvertFrom-Json
    Check ($r.status -ceq 'FAILED' -and @($r.steps|Where-Object step -like 'remove*').Count -eq 0) 'failure preserves fixture'
    if($stage -ne 'fresh JVM recovery verification'){Check (-not ($script:mockCalls -contains 'fresh JVM recovery verification')) 'failed backup cannot proceed'}
}
Write-Host "PASS: $script:count offline assertions; $($script:count-$start) recovery additions. No database or application touched."
