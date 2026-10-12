# Offline only. Docker calls replaced in memory before the real runner is exercised.
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'TestPaperPersistenceReviewWorkflow.ps1')
. (Join-Path $PSScriptRoot 'PaperApprovalVerification.ps1')
. (Join-Path $PSScriptRoot 'PaperWriterVerification.ps1')
$start=$script:count
$java=Get-Content (Join-Path $PSScriptRoot '../../marketbrain-service/src/main/java/in/marketbrain/paper/PaperWriterVerification.java') -Raw
$declared=@([regex]::Matches($java,'check\("([a-z0-9_]+)"')|ForEach-Object {$_.Groups[1].Value})
$expected=@(Get-PaperWriterCheckNames '--prepare')+@(Get-PaperWriterCheckNames '--recover')
Check ($declared.Count -eq 26 -and (($declared -join ',') -ceq ($expected -join ','))) '26 fixed independently validated names'
function Sample([string]$Phase){
    $names=@(Get-PaperWriterCheckNames $Phase)
    @{version='PAPER_WRITER_REVIEW_V1';status='ISOLATED_WRITER_CHECKS_PASSED';phase=$Phase;schema=$schema;checkCount=$names.Count;failedCount=0;elapsedSeconds=1;checks=@($names|ForEach-Object {@{name=$_;passed=$true;elapsedMillis=1}});applicationDatabaseAccessed=$false;actionExecutionEnabled=$false;applicationWriterActivated=$false;syntheticDatabaseWritesPerformed=$true;providerCalls=0;telegramCalls=0;modelCalls=0;cashPaise=10000000;reservedCashPaise=0;ledgerRevision=0;orderCount=0;fillCount=0}|ConvertTo-Json -Depth 8|ConvertFrom-Json
}
foreach($phase in @('--prepare','--recover')){Assert-PaperWriterPhase (Sample $phase) $phase $schema;Check $true 'valid writer phase'}
foreach($field in @('failedCount','providerCalls','telegramCalls','modelCalls','checkCount','cashPaise','reservedCashPaise','ledgerRevision','orderCount','fillCount')){$v=Sample '--prepare';$v.$field++;Reject {Assert-PaperWriterPhase $v '--prepare' $schema} 'invalid writer count'}
foreach($field in @('applicationDatabaseAccessed','actionExecutionEnabled','applicationWriterActivated','syntheticDatabaseWritesPerformed')){$v=Sample '--prepare';$v.$field=-not $v.$field;Reject {Assert-PaperWriterPhase $v '--prepare' $schema} 'unsafe writer flag'}
foreach($mutation in @({param($v)$v.checks[0].passed=$false},{param($v)$v.checks[0].passed='true'},{param($v)$v.checks[0].name=$v.checks[1].name},{param($v)$v.checks=@($v.checks|Select-Object -Skip 1)},{param($v)$v.elapsedSeconds=-1},{param($v)$v.applicationWriterActivated=$null},{param($v)$v.version='wrong'},{param($v)$v.schema='public'})){$v=Sample '--prepare';& $mutation $v;Reject {Assert-PaperWriterPhase $v '--prepare' $schema} 'invalid writer evidence'}
$mockedWriter=$mocked.Replace('$v.receipt.tailHash=''b''*64;', '')
$mockedWriter=$mockedWriter.Replace('switch($Step){',@'
    if($Step -ceq $script:failWriterStep){throw 'Injected writer stage failure'}
    switch($Step){
'@)
Check (-not $mockedWriter.Contains('[Diagnostics.Process]::new()')) 'all native Docker replaced'
$runWriter=[scriptblock]::Create($mockedWriter)
function Reset-WriterMock {$script:failMock=$false;$script:failResolution=$false;$script:failPreflight=$false;$script:mockContainers=@{};$script:mockCalls=@();$script:failWriterStep=''}
Reset-WriterMock
Reject {& $runWriter -ApprovalWriter -ApprovalRecovery -OutputDirectory (Join-Path $testRoot 'writer-invalid')} 'exclusive switches'
& $runWriter -ApprovalWriter -OutputDirectory (Join-Path $testRoot 'writer-pass')
$r=Get-Content (Get-ChildItem (Join-Path $testRoot 'writer-pass') -Filter '*.json'|Select-Object -First 1).FullName -Raw|ConvertFrom-Json
Check ($r.status -ceq 'ISOLATED_WRITER_PASSED_APPLICATION_ACTIVATION_BLOCKED') 'bounded success status'
Check ($r.prepare.checkCount -eq 23 -and $r.recover.checkCount -eq 3 -and -not $r.applicationWriterActivated) 'new phase counts and activation block'
Check (@($r.cleanup|Where-Object action -eq 'REMOVED_SYNTHETIC_CONTAINER_AND_ANONYMOUS_VOLUMES').Count -eq 3) 'owned successful cleanup'
Check ($r.manifest.'marketbrain-service/src/main/resources/paper/approval-writer-v1.sql' -match '^[a-fA-F0-9]{64}$') 'candidate SQL hash captured'
foreach($stage in @('prepare database fixtures','restart fixture database','fresh JVM recovery verification')){
    Reset-WriterMock;$script:failWriterStep=$stage;$dir=Join-Path $testRoot ('wf-'+[guid]::NewGuid().ToString('N').Substring(0,6))
    Reject {& $runWriter -ApprovalWriter -OutputDirectory $dir} 'stage failure propagated'
    $r=Get-Content (Get-ChildItem $dir -Filter '*.json'|Select-Object -First 1).FullName -Raw|ConvertFrom-Json
    Check ($r.status -ceq 'FAILED' -and @($r.steps|Where-Object step -like 'remove*').Count -eq 0) 'failure preserves fixture'
}
Write-Host "PASS: $script:count offline assertions; $($script:count-$start) writer additions. No database, provider or model used."
