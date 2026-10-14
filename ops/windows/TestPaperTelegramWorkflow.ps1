# Offline only. Reuses the tested real runner with all Docker process calls replaced in memory.
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'TestPaperPersistenceReviewWorkflow.ps1')
. (Join-Path $PSScriptRoot 'PaperApprovalVerification.ps1')
. (Join-Path $PSScriptRoot 'PaperTelegramVerification.ps1')
$start=$script:count
$java=Get-Content (Join-Path $PSScriptRoot '../../marketbrain-service/src/main/java/in/marketbrain/paper/PaperTelegramVerification.java') -Raw
$declared=@([regex]::Matches($java,'check\("([a-z0-9_]+)"')|ForEach-Object {$_.Groups[1].Value})
$expected=@(Get-PaperTelegramCheckNames '--prepare')+@(Get-PaperTelegramCheckNames '--recover')
Check ($declared.Count -eq 18 -and (($declared -join ',') -ceq ($expected -join ','))) '18 independently validated scenario names'
function Sample([string]$Phase) {
    $names=@(Get-PaperTelegramCheckNames $Phase)
    @{version='PAPER_TELEGRAM_REVIEW_V1';status='ISOLATED_TELEGRAM_REVIEW_PASSED';phase=$Phase;schema=$schema;
        checkCount=$names.Count;failedCount=0;elapsedSeconds=1;checks=@($names|ForEach-Object {@{name=$_;passed=$true;elapsedMillis=1}});
        applicationDatabaseAccessed=$false;actionExecutionEnabled=$false;applicationWriterActivated=$false;
        syntheticDatabaseWritesPerformed=$true;providerCalls=0;telegramCalls=0;modelCalls=0;cashPaise=10000000;
        reservedCashPaise=0;ledgerRevision=0;orderCount=0;fillCount=0}|ConvertTo-Json -Depth 8|ConvertFrom-Json
}
foreach($phase in @('--prepare','--recover')){Assert-PaperTelegramPhase (Sample $phase) $phase $schema;Check $true 'valid phase'}
foreach($field in @('failedCount','providerCalls','telegramCalls','modelCalls','checkCount','cashPaise','reservedCashPaise','ledgerRevision','orderCount','fillCount')) {
    $v=Sample '--prepare';$v.$field++;Reject {Assert-PaperTelegramPhase $v '--prepare' $schema} 'invalid count'
    $v=Sample '--prepare';$v.$field=[string]$v.$field;Reject {Assert-PaperTelegramPhase $v '--prepare' $schema} 'string is not a counter'
}
foreach($field in @('applicationDatabaseAccessed','actionExecutionEnabled','applicationWriterActivated','syntheticDatabaseWritesPerformed')) {
    $v=Sample '--prepare';$v.$field=-not $v.$field;Reject {Assert-PaperTelegramPhase $v '--prepare' $schema} 'unsafe flag'
}
foreach($mutation in @({param($v)$v.checks[0].passed=$false},{param($v)$v.checks[0].passed='true'},
    {param($v)$v.checks[0].name=$v.checks[1].name},{param($v)$v.checks=@($v.checks|Select-Object -Skip 1)},
    {param($v)$v.elapsedSeconds=-1},{param($v)$v.applicationWriterActivated=$null},{param($v)$v.version='wrong'},
    {param($v)$v.schema='public'},{param($v)$v.phase='--other'},{param($v)$v.status='RUNNING'})) {
    $v=Sample '--prepare';& $mutation $v;Reject {Assert-PaperTelegramPhase $v '--prepare' $schema} 'invalid evidence'
}
$mockedTelegram=$mocked.Replace('$v.receipt.tailHash=''b''*64;', '')
$mockedTelegram=$mockedTelegram.Replace('switch($Step){',@'
    $script:telegramArguments+=@([pscustomobject]@{step=$Step;arguments=$Arguments})
    if($Step -ceq $script:failTelegramStep){throw 'Injected Telegram fixture stage failure'}
    switch($Step){
'@)
Check (-not $mockedTelegram.Contains('[Diagnostics.Process]::new()')) 'all Docker execution replaced'
$runTelegram=[scriptblock]::Create($mockedTelegram)
function Reset-TelegramMock {
    $script:failMock=$false;$script:failResolution=$false;$script:failPreflight=$false
    $script:mockContainers=@{};$script:mockCalls=@();$script:failTelegramStep='';$script:telegramArguments=@()
}
Reset-TelegramMock
Reject {& $runTelegram -TelegramReview -ApprovalWriter -OutputDirectory (Join-Path $testRoot 'telegram-invalid')} 'exclusive modes'
& $runTelegram -TelegramReview -OutputDirectory (Join-Path $testRoot 'telegram-pass')
$r=Get-Content (Get-ChildItem (Join-Path $testRoot 'telegram-pass') -Filter '*.json'|Select-Object -First 1).FullName -Raw|ConvertFrom-Json
Check ($r.status -ceq 'ISOLATED_TELEGRAM_WIRING_PASSED_ACTIVATION_PENDING') 'success means isolated wiring only'
Check ($r.prepare.checkCount -eq 15 -and $r.recover.checkCount -eq 3 -and -not $r.applicationWriterActivated -and -not $r.realTelegramVerified) 'counts and activation block'
Check (@($r.cleanup|Where-Object action -eq 'REMOVED_SYNTHETIC_CONTAINER_AND_ANONYMOUS_VOLUMES').Count -eq 3) 'owned fixtures cleaned'
Check ($r.manifest.'marketbrain-service/src/main/java/in/marketbrain/paper/PaperReviewWiring.java' -match '^[a-fA-F0-9]{64}$') 'wiring provenance'
foreach($step in @('create prepare verifier','create fresh recovery verifier')) {
    $arguments=@($script:telegramArguments|Where-Object step -eq $step)[0].arguments
    Check ($arguments -contains ('container:'+$r.resources.database)) 'verifier shares only this database namespace'
    Check (-not ($arguments -contains '--publish') -and -not ($arguments -contains '--mount')) 'no host access'
}
$dbArgs=@($script:telegramArguments|Where-Object step -eq 'create fixture database')[0].arguments
Check ($dbArgs -contains 'POSTGRES_INITDB_ARGS=--auth-host=scram-sha-256 --auth-local=trust') 'loopback TCP requires actual password authentication'
$readyArgs=@($script:telegramArguments|Where-Object step -eq 'database readiness')[0].arguments
Check ($readyArgs -contains '-h' -and $readyArgs -contains '127.0.0.1') 'readiness waits for final TCP server, not initdb Unix socket'
foreach($stage in @('build verification image','create internal network','prepare database fixtures','restart fixture database','fresh JVM recovery verification')) {
    Reset-TelegramMock;$script:failTelegramStep=$stage;$dir=Join-Path $testRoot ('tf-'+[guid]::NewGuid().ToString('N').Substring(0,6))
    Reject {& $runTelegram -TelegramReview -OutputDirectory $dir} 'failure propagated'
    $r=Get-Content (Get-ChildItem $dir -Filter '*.json'|Select-Object -First 1).FullName -Raw|ConvertFrom-Json
    Check ($r.status -ceq 'FAILED' -and @($r.steps|Where-Object step -like 'remove*').Count -eq 0) 'no deletion of failed evidence'
}
Write-Host "PASS: $script:count offline assertions; $($script:count-$start) Telegram additions. No real Docker, database or provider calls."
