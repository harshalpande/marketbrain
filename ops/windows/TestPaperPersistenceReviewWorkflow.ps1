# Offline fixed report/mutation checks only. Does not start Docker, Java, a service or a database.
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'PaperPersistenceVerification.ps1')
$script:count=0
function Check([bool]$Condition,[string]$Name){if(-not $Condition){throw "Failed: $Name"};$script:count++}
function Reject([scriptblock]$Body,[string]$Name){$failed=$false;try{& $Body}catch{$failed=$true};Check $failed $Name}
$testRoot=Join-Path (Resolve-Path (Join-Path $PSScriptRoot '../../marketbrain-service/target')).Path ('paper-persistence-review-'+[guid]::NewGuid().ToString('N'))
# Empty discovery fixtures only: none is executed. Exercise the production resolver,
# not a replacement of the path-selection logic that previously hid the bug.
$launcherDir=Join-Path $testRoot 'Docker Desktop path with spaces'
$otherDir=Join-Path $testRoot 'Other Docker installation'
New-Item -ItemType Directory -Path $launcherDir,$otherDir -Force|Out-Null
$exe=New-Item -ItemType File -Path (Join-Path $launcherDir 'docker.exe')
$shim=New-Item -ItemType File -Path (Join-Path $launcherDir 'docker')
$other=New-Item -ItemType File -Path (Join-Path $otherDir 'docker.exe')
& {
    function Get-Command {param($Name,$CommandType,$ErrorAction)
        Check ($Name -ceq 'docker.exe' -and $CommandType -eq 'Application') 'explicit executable discovery'
        $script:launcherMatches
    }
    $script:launcherMatches=@([pscustomobject]@{Source=$shim.FullName},[pscustomobject]@{Source=$exe.FullName},[pscustomobject]@{Source=$other.FullName})
    $resolved=Resolve-PaperDockerExecutable
    Check ($resolved -is [string] -and $resolved -ceq $exe.FullName) 'one existing exe selected with spaces and duplicate matches'
    $info=[Diagnostics.ProcessStartInfo]::new();$info.FileName=$resolved
    Check ($info.FileName -ceq $exe.FullName) 'process filename is unquoted scalar path'
    $script:launcherMatches=@([pscustomobject]@{Source=(Join-Path $testRoot 'missing/docker.exe')},[pscustomobject]@{Source=$exe.FullName})
    Check ((Resolve-PaperDockerExecutable) -ceq $exe.FullName) 'missing match skipped'
    foreach($invalid in @(@(),@([pscustomobject]@{Source=$shim.FullName}),@([pscustomobject]@{Source='docker.exe'}),@([pscustomobject]@{Source=@($exe.FullName,$other.FullName)}))){
        $script:launcherMatches=$invalid
        Reject {Resolve-PaperDockerExecutable} 'missing or invalid executable rejected'
    }
}
$schema='paper_verify_'+('a'*32)
# The frozen reconciliation trace is independent of the live database suite output.
function Sample([string]$Phase){
    $names=if($Phase -eq '--prepare'){@('committed_approval_reopens_with_reservation','same_command_duplicate_no_revision_or_cash_change','conflicting_id_rejected_without_write','partial_fill_and_cancel_survive_reconstruction','duplicate_fill_different_command_does_not_debit','overfill_rolls_back_without_journal_append','transaction_failure_rolls_back_insert_and_projection','lost_commit_ack_retry_reconciles_once','terminated_backend_rolls_back_uncommitted_command','concurrent_approvals_cannot_double_spend','concurrent_same_id_has_one_commit','lock_timeout_fails_without_partial_write','tampered_projection_blocks_reopen','tampered_command_hash_blocks_reopen','missing_account_never_reseeds','changed_policy_blocks_replay','no_op_time_cannot_hide_clock_rollback','capacity_stops_without_evicting_ids','hold_persists_without_an_order','unowned_sell_rejected','prepare_restart_fixture')}else{@('fresh_jvm_after_database_restart_reconciles','post_restart_duplicate_fill_has_no_effect','post_restart_expiry_releases_only_remaining_reservation')}
    $rows=@(@('APPROVED','buy',$null,10,0,0,0,0),@('BUY_FILL','buy','buy1',4,10000,10,40010,0),@('BUY_FILL','buy','buy2',6,10000,10,60010,0),@('APPROVED','sell',$null,4,0,0,0,0),@('SELL_FILL','sell','sell1',2,10000,10,0,19990),@('CANCELLED','sell',$null,2,0,0,0,0),@('APPROVED','pending',$null,2,0,0,0,0))
    if($Phase -eq '--recover'){$rows+=,@('EXPIRED','pending',$null,2,0,0,0,0)}
    $journal=@();$i=0;foreach($row in $rows){$i++;$journal+=@{sequence=$i;kind=$row[0];orderId=$row[1];fillId=$row[2];symbol='FIXTURE';quantity=$row[3];pricePaise=$row[4];feePaise=$row[5];debitPaise=$row[6];creditPaise=$row[7]}}
    $reserve=if($Phase -eq '--prepare'){20300}else{0};$state=if($Phase -eq '--prepare'){'OPEN'}else{'EXPIRED'}
    $o=@{buy=@{status='FILLED';filledQuantity=10};sell=@{status='CANCELLED';filledQuantity=2};pending=@{status=$state;filledQuantity=0;approval=@{quantity=2;zoneMaxPaise=10100;feeBudgetPaise=100}}}
    $audit=@{initialCashPaise=10000000;debitPaise=100020;creditPaise=19990;feesPaise=30;syntheticOrdersCreated=3;syntheticFillCount=3;journal=$journal;account=@{cashPaise=9919970;availableCashPaise=(9919970-$reserve);reservedCashPaise=$reserve;holdings=@{FIXTURE=8};reservedShares=@{};orders=$o;approvalCount=3;fillCount=3}}
    @{version='PAPER_PERSISTENCE_ENGINEERING_V1';status='ISOLATED_DATABASE_CHECKS_PASSED';phase=$Phase;schema=$schema;syntheticDatabaseWritesPerformed=$true;applicationDatabaseAccessed=$false;runtimePaperAccountEnabled=$false;actionExecutionEnabled=$false;providerCallCount=0;modelCallCount=0;realOrdersCreated=0;failedCount=0;checkCount=$names.Count;checks=@($names|ForEach-Object{@{name=$_;passed=$true;failure=$null;elapsedMillis=1}});receipt=@{revision=$i;duplicate=$false;tailHash=('a'*64);audit=$audit}}|ConvertTo-Json -Depth 20|ConvertFrom-Json
}
foreach($phase in @('--prepare','--recover')){Assert-PaperPersistencePhase (Sample $phase) $phase $schema;Check $true "$phase valid"}
$mutations=@(
    {param($r)$r.status='FAILED'}, {param($r)$r.schema='public'}, {param($r)$r.applicationDatabaseAccessed=$true},
    {param($r)$r.providerCallCount=1}, {param($r)$r.syntheticDatabaseWritesPerformed=$false}, {param($r)$r.checks[0].passed=$false},
    {param($r)$r.checks[0].name=$r.checks[1].name}, {param($r)$r.receipt.revision=8}, {param($r)$r.receipt.audit.account.cashPaise++},
    {param($r)$r.receipt.audit.account.reservedCashPaise=0}, {param($r)$r.receipt.audit.account.holdings.FIXTURE=9},
    {param($r)$r.receipt.audit.journal[1].debitPaise=40000}, {param($r)$r.receipt.audit.journal[2].fillId='buy1'},
    {param($r)$r.receipt.audit.account.orders.sell.status='OPEN'}, {param($r)$r.receipt.audit.journal[5].kind='EXPIRED'},
    {param($r)$r.receipt.audit.feesPaise=0}, {param($r)$r.receipt.tailHash='invalid'}, {param($r)$r.receipt.audit.journal[1].quantity=4.5}
)
foreach($mutation in $mutations){$r=Sample '--prepare';& $mutation $r;Reject {Assert-PaperPersistencePhase $r '--prepare' $schema} 'mutation rejected'}
$r=Sample '--recover';$r.receipt.audit.account.orders.pending.status='OPEN';Reject {Assert-PaperPersistencePhase $r '--recover' $schema} 'expiry required'
$runner=Join-Path $PSScriptRoot 'TestPaperPersistenceBundle.ps1';$tokens=$null;$errors=$null;[void][Management.Automation.Language.Parser]::ParseFile($runner,[ref]$tokens,[ref]$errors);Check ($errors.Count -eq 0) 'runner parses'
$text=Get-Content -LiteralPath $runner -Raw
Check ($text.Contains("'--internal'") -and -not $text.Contains("'--publish'") -and -not $text.Contains("'--mount'") -and -not $text.Contains("'compose'")) 'isolation command contract'
# Exercise the real orchestration/checkpoint/cleanup flow with Docker replaced entirely in memory.
# The input is this repository's runner, never an attached report or user-provided script.
$begin=$text.IndexOf('function Docker(');$end=$text.IndexOf('function Wait-Database')
Check ($begin -ge 0 -and $end -gt $begin) 'mock boundary located'
$mock=@'
function Docker([string]$Step,[string[]]$Arguments,[int]$Limit=60,[switch]$AllowFailure){
    $report['offlineMockTransport']=$true
    $script:mockCalls+=@($Step)
    if($Step -eq 'docker engine check' -and $script:failPreflight){throw 'Injected launcher or engine failure'}
    $stdout='';$exit=0
    switch($Step){
        'create fixture database' {$script:mockContainers[$db]=$true}
        'create prepare verifier' {$script:mockContainers[$prepare]=$true}
        'create fresh recovery verifier' {$script:mockContainers[$recover]=$true}
        'prepare database fixtures' {if($script:failMock){throw 'Injected Docker stage failure'};$v=Sample '--prepare';$v.schema=$schema;$stdout=$v|ConvertTo-Json -Depth 30 -Compress}
        'fresh JVM recovery verification' {$v=Sample '--recover';$v.schema=$schema;$v.receipt.tailHash='b'*64;$stdout=$v|ConvertTo-Json -Depth 30 -Compress}
        'inspect fixture ownership' {if($script:mockContainers.ContainsKey($Arguments[2])){$stdout=@(@{Config=@{Labels=@{$label=$id}}})|ConvertTo-Json -Depth 5 -Compress}else{$exit=1}}
        'inspect network ownership' {$stdout=@(@{Labels=@{$label=$id}})|ConvertTo-Json -Depth 5 -Compress}
    }
    $r=[pscustomobject]@{step=$Step;exitCode=$exit;timedOut=$false;elapsedSeconds=0;stdout=$stdout;stderr=''}
    $report.steps+=@($r);Save-Report;return $r
}
'@
$mocked=$text.Substring(0,$begin)+$mock+"`n"+$text.Substring($end)
$mocked=$mocked.Replace('$docker=Resolve-PaperDockerExecutable',"if(`$script:failResolution){throw 'Injected missing Docker executable'};`$docker='OFFLINE_NO_EXECUTABLE'")
$mocked=$mocked.Replace('$PSScriptRoot',("'"+$PSScriptRoot.Replace("'","''")+"'"))
Check (-not $mocked.Contains('[Diagnostics.Process]::new()') -and -not $mocked.Contains('Get-Command docker')) 'all Docker process execution removed'
$run=[scriptblock]::Create($mocked)
$script:failMock=$false;$script:mockContainers=@{};$script:failPreflight=$false;$script:failResolution=$false;$script:mockCalls=@()
& $run -OutputDirectory (Join-Path $testRoot 'pass')
$okFile=Get-ChildItem -LiteralPath (Join-Path $testRoot 'pass') -Filter '*.json'|Select-Object -First 1
$ok=Get-Content -LiteralPath $okFile.FullName -Raw|ConvertFrom-Json
Check ($ok.status -ceq 'ISOLATED_PERSISTENCE_PASSED_APPLICATION_RELEASE_BLOCKED') 'mock orchestration pass'
Check (@($ok.cleanup|Where-Object action -eq 'REMOVED_SYNTHETIC_CONTAINER_AND_ANONYMOUS_VOLUMES').Count -eq 3) 'owned successful fixtures removed'
Check (@($ok.steps|Where-Object step -eq 'restart fixture database').Count -eq 1) 'one restart'
Check (@($ok.steps|Where-Object step -eq 'remove completed isolated network').Count -eq 1) 'owned network cleanup'
$script:failMock=$true;$script:mockContainers=@{}
Reject {& $run -OutputDirectory (Join-Path $testRoot 'fail')} 'mock stage failure propagated'
$badFile=Get-ChildItem -LiteralPath (Join-Path $testRoot 'fail') -Filter '*.json'|Select-Object -First 1
$bad=Get-Content -LiteralPath $badFile.FullName -Raw|ConvertFrom-Json
Check ($bad.status -ceq 'FAILED' -and $bad.failure -like '*Injected*') 'failure checkpoint retained'
Check (@($bad.steps|Where-Object step -like 'remove*').Count -eq 0 -and @($bad.cleanup|Where-Object action -eq 'PRESERVED_STOP_REQUESTED').Count -eq 2) 'failed owned resources preserved and stopped'
Check (@($bad.steps|Where-Object step -eq 'restart fixture database').Count -eq 0) 'failed preparation cannot proceed to restart'
foreach($stage in @('resolution','preflight')){
    $script:failResolution=($stage -eq 'resolution');$script:failPreflight=($stage -eq 'preflight');$script:mockCalls=@();$script:mockContainers=@{}
    $earlyDir=Join-Path $testRoot $stage
    $warnings=@()
    Reject {& $run -OutputDirectory $earlyDir -WarningVariable +warnings} "$stage failure propagated"
    $earlyFile=Get-ChildItem -LiteralPath $earlyDir -Filter '*.json'|Select-Object -First 1
    $early=Get-Content -LiteralPath $earlyFile.FullName -Raw|ConvertFrom-Json
    Check ($early.status -ceq 'FAILED' -and $early.failure -like '*Injected*') "$stage failure checkpoint retained"
    Check (@($early.cleanup).Count -eq 1 -and $early.cleanup[0].action -ceq 'SKIPPED_NO_FIXTURE_CREATION_ATTEMPTED') "$stage cleanup skipped"
    $expectedCalls=if($stage -eq 'resolution'){0}else{1}
    Check ($script:mockCalls.Count -eq $expectedCalls -and $warnings.Count -eq 0) "$stage no cleanup calls or misleading warnings"
    Check ($early.syntheticDatabaseWritesPerformed -eq $false -and $null -eq $early.prepare -and $null -eq $early.recover) "$stage no database verification claimed"
}
Write-Host "PASS: $script:count offline persistence review assertions. Real PostgreSQL remains spare verification."
