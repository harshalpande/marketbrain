# Offline: generated synthetic custody only. Database and prompts are mocked; no real credentials or runtime configuration.
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'PaperWriterCredential.ps1')
. (Join-Path $PSScriptRoot 'NumericalHistoryEvidence.ps1')
$script:checks=0
function Check($Value,[string]$Message){if(-not $Value){throw $Message};$script:checks++}
function Reject([scriptblock]$Action){$failed=$false;try{$null=& $Action}catch{$failed=$true};Check $failed 'Expected rejection'}
function Sample {
    $p=@{planHash=('a'*32);plan=@{version='PAPER_WRITER_INSTALL_PLAN_V1';database='marketbrain';databaseOid='123';clusterId='123456';adminSuperuser=$true;schemaExists=$true;serverVersion=180006;roleCount=1;membershipCount=0;relationCount=12;requiredTables=12;roleCollisions=0;functionCollisions=0;publicCreateSchemas=0;publicDefiners=0;defaultFunctionAcls=0;publicDatabaseCreate=$false;publicTemp=$true;roles=@(@{roleOid=10;roleName='postgres';login=$true;superuser=$true;createRole=$true;createDatabase=$true;inherit=$true;replication=$true;bypassRls=$true;temp=$true;explicitTemp=$false});memberships=@()}}
    $saved=@{version='PAPER_WRITER_INSTALL_BUNDLE_V1';status='STAGED_WRITER_VERIFIED_LOGIN_AND_ACTIONS_DISABLED';commitOutcome='COMMITTED_AND_VERIFIED';failure=$null;failureCode=$null;plan=$p;target=@{host='127.0.0.1';port=5432;database='marketbrain'};steps=@()}
    foreach($flag in @('backupConfirmed','maintenanceConfirmed','targetConfirmed','rolesApproved','rehearsalRollbackVerified','applyRequested','applyAttempted')){$saved[$flag]=$true}
    foreach($flag in @('applicationWriterActivated','actionExecutionEnabled','credentialsSaved')){$saved[$flag]=$false}
    foreach($phase in @('Plan','Rehearse','Plan','Apply','Verify')){$saved.steps+=@{phase=$phase;exitCode=0;timedOut=$false}}
    foreach($pair in @(@('rehearsal','Rehearse'),@('applyReceipt','Apply'),@('verification','Verify'))){$saved[$pair[0]]=@{version='PAPER_WRITER_INSTALL_CHECK_V1';phase=$pair[1];planHash=('a'*32);checksPassed=$true;loginEnabled=$false;applicationWriterActivated=$false;actionExecutionEnabled=$false;accountRowsWritten=$false}}
    return $saved|ConvertTo-Json -Depth 14|ConvertFrom-Json
}
function Receipt([string]$Phase,[string]$State='MATCH'){
    @{version='PAPER_WRITER_CREDENTIAL_CHECK_V1';phase=$Phase;planHash=('a'*32);state=$State;writerLoginEnabled=$false;helperLoginEnabled=$false;accountRowsWritten=$false;applicationWriterActivated=$false;actionExecutionEnabled=$false}|ConvertTo-Json|ConvertFrom-Json
}
$watch=[Diagnostics.Stopwatch]::StartNew()
$root=Join-Path ([IO.Path]::GetTempPath()) ('paper-credential-offline-'+[Guid]::NewGuid().ToString('N'))
[void](New-Item -ItemType Directory -Path $root);Protect-PaperHbaBackupAcl $root -Directory
$fixturePayload=[byte[]](0..47);$entropy=Get-PaperCredentialEntropy (Sample)
$golden='SCRAM-SHA-256$4096:ICEiIyQlJicoKSorLC0uLw==$+wZyJkKrhoiF/HTRu9lzgG7BOKa3Bhbp0dW+t1gyZNo=:1DkuxCiuPWk/n9XxLPWpEnHSVpsv/0A3Yps9zkg9PJw='
try {
    # Golden vector independently generated with Node crypto PBKDF2/HMAC/SHA256.
    Check ((New-PaperCredentialVerifier $fixturePayload) -ceq $golden) 'SCRAM golden vector'
    Check (($fixturePayload -join ',') -ceq ((0..47) -join ',')) 'caller buffer not erased'
    Reject {New-PaperCredentialVerifier (New-Object byte[] 47)};Reject {New-PaperCredentialVerifier $null}
    $blob=Join-Path $root 'test.dpapi';Save-PaperCredential $blob $fixturePayload $entropy
    $bytes=Read-PaperCredential $blob $entropy
    Check (($bytes -join ',') -ceq ($fixturePayload -join ',')) 'same-owner exact roundtrip'
    Check (-not [Text.Encoding]::UTF8.GetString([IO.File]::ReadAllBytes($blob)).Contains($golden)) 'verifier not stored as plaintext'
    Reject {Save-PaperCredential $blob $fixturePayload $entropy}
    Reject {Read-PaperCredential $blob ([Text.Encoding]::UTF8.GetBytes('another-target'))}
    foreach($field in @('clusterId','databaseOid')){$s=Sample;$s.plan.plan.$field='999';Reject {Read-PaperCredential $blob (Get-PaperCredentialEntropy $s)}}
    $s=Sample;$s.target.port=5433;Reject {Read-PaperCredential $blob (Get-PaperCredentialEntropy $s)}
    Reject {Save-PaperCredential (Join-Path $root 'bad.dpapi') (New-Object byte[] 32) $entropy}
    $original=[IO.File]::ReadAllBytes($blob);$corrupt=[byte[]]$original.Clone();$corrupt[$corrupt.Length-1]=$corrupt[$corrupt.Length-1] -bxor 1
    [IO.File]::WriteAllBytes($blob,$corrupt);Reject {Read-PaperCredential $blob $entropy}
    [IO.File]::WriteAllBytes($blob,(New-Object byte[] 4097));Reject {Read-PaperCredential $blob $entropy}
    [IO.File]::WriteAllBytes($blob,$original)
    $badAcl=Join-Path $root 'inherited.dpapi';[IO.File]::WriteAllBytes($badAcl,$original);Reject {Read-PaperCredential $badAcl $entropy}
    foreach($phase in @('Inspect','Rehearse','Stage','Verify')){
        $sql=New-PaperCredentialSql $phase (Sample).plan $golden
        Check ($sql -notmatch '__[A-Z_]+__') 'no unresolved tokens'
        Check ($sql.Contains('Verification target mismatch') -and $sql.Contains('Column mutation boundary mismatch')) 'installed identity and permissions guarded'
        Check ($sql.Contains('pg_try_advisory_xact_lock') -and $sql.Contains('Writer sessions must be absent')) 'concurrency guards'
        Check ($sql.Contains("statement_timeout='15s'") -and $sql.Contains("lock_timeout='3s'")) 'bounded database stages'
        Check ($sql -notmatch '(?i)\bGRANT\s|\bREVOKE\s|\bINSERT\s|\bDELETE\s|\bUPDATE\s+public\.|\bLOGIN\s+PASSWORD') 'no broadened permissions or account operations'
        Check ($sql.EndsWith($(if($phase -ceq 'Stage'){'COMMIT;'}else{'ROLLBACK;'}))) 'transaction end'
        Check ($sql.Contains('SET TRANSACTION READ ONLY;') -eq ($phase -cin @('Inspect','Verify'))) 'read-only modes'
        Check ($sql.Contains('ALTER ROLE marketbrain_paper_review_writer NOLOGIN PASSWORD') -eq ($phase -cin @('Stage','Rehearse'))) 'only writer password changes'
        Check ($sql.IndexOf('Existing credential differs preserve custody') -lt $sql.IndexOf('SELECT jsonb_build_object')) 'conflict stops receipt'
    }
    Reject {New-PaperCredentialSql 'Stage' (Sample).plan "';ALTER ROLE other LOGIN;--"}
    foreach($field in @('writerLoginEnabled','helperLoginEnabled','accountRowsWritten','applicationWriterActivated','actionExecutionEnabled')){
        $v=Receipt 'Verify';$v.$field=$true;Reject {Assert-PaperCredentialReceipt $v 'Verify' ('a'*32)}
        $v.$field='false';Reject {Assert-PaperCredentialReceipt $v 'Verify' ('a'*32)}
    }
    Reject {Assert-PaperCredentialReceipt (Receipt 'Inspect') 'Stage' ('a'*32)}
    Reject {Assert-PaperCredentialReceipt (Receipt 'Verify' 'MISSING') 'Verify' ('a'*32)}
    Reject {Assert-PaperCredentialReceipt (Receipt 'Inspect' 'OTHER') 'Inspect' ('a'*32)}
    Reject {Assert-PaperCredentialReceipt (Receipt 'Inspect') 'Inspect' ('b'*32)}

    # Actual runner, actual DPAPI/ACL/atomic reports; only git, credential prompts and psql are mocked.
    $source=Get-Content (Join-Path $PSScriptRoot 'SetPaperWriterCredential.ps1') -Raw
    $repo=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../..'))
    $mocked=$source.Replace('#Requires -Version 7.0','').Replace(". (Join-Path `$PSScriptRoot 'PaperWriterCredential.ps1')",'').Replace(". (Join-Path `$PSScriptRoot 'NumericalHistoryEvidence.ps1')",'')
    $mocked=[regex]::Replace($mocked,'(?m)^\$repo=.*$',('$repo='''+$repo.Replace("'","''")+'''').Replace('$','$$'))
    $mocked=$mocked.Replace("'C:\MarketBrainData\Secrets\PaperReviewWriter'",'$script:caseSecrets')
    $runner=[scriptblock]::Create($mocked)
    function git {$global:LASTEXITCODE=0;if($args -contains 'rev-parse'){'a'*40};if($script:case -ceq 'dirty' -and $args -contains 'status'){' M user-work'}}
    function Test-Path {param($LiteralPath,$PathType);if($LiteralPath -like '*psql.exe'){return $script:case -cne 'no-psql'};if($PathType){Microsoft.PowerShell.Management\Test-Path -LiteralPath $LiteralPath -PathType $PathType}else{Microsoft.PowerShell.Management\Test-Path -LiteralPath $LiteralPath}}
    function Get-FileHash {param($LiteralPath,$Algorithm='SHA256');if($LiteralPath -ceq $script:acceptedFixture){return [pscustomobject]@{Hash=$(if($script:case -ceq 'wrong-evidence'){'0'*64}else{'E213A645E4CD39D16E63BA69097E1D32B45E60DC49BF08EBE0B4B52DBD95B33D'})}};Microsoft.PowerShell.Utility\Get-FileHash -LiteralPath $LiteralPath -Algorithm $Algorithm}
    function Read-Host {param($Prompt,[switch]$AsSecureString)
        if($AsSecureString){return ConvertTo-SecureString 'SYNTHETIC_ADMIN_SECRET_DO_NOT_EXPORT' -AsPlainText -Force}
        if($Prompt -ceq 'Confirm database name'){return 'marketbrain'}
        if($Prompt -like 'Type STAGE*'){if($script:case -ceq 'cancel'){return 'NO'};return 'STAGE_DISABLED_WRITER'}
        if($Prompt -like 'PostgreSQL administrator username*'){if($script:case -ceq 'bad-admin'){return "bad';name"};return 'postgres'}
        throw 'Unexpected prompt'
    }
    function Invoke-PaperInstallerPsql($Executable,$Database,$Port,$Admin,$Password,$Sql){
        Check ($Password -ceq 'SYNTHETIC_ADMIN_SECRET_DO_NOT_EXPORT' -and -not $Sql.Contains($Password)) 'admin not in SQL'
        $operation=[regex]::Match($Sql,"'phase','(Inspect|Rehearse|Stage|Verify)'").Groups[1].Value
        $script:called+=,$operation
        $state=if($operation -ceq 'Inspect'){$script:dbState}else{'MATCH'}
        $v=Receipt $operation $state;$exitCode=0;$timeout=$false
        if($script:case -ceq 'rollback-drift' -and $operation -ceq 'Inspect' -and $script:called.Count -gt 1){$v.state='MATCH'}
        if($script:case -ceq 'unsafe' -and $operation -ceq 'Rehearse'){$v.writerLoginEnabled=$true}
        if($script:case -ceq 'rehearse-fail' -and $operation -ceq 'Rehearse'){$exitCode=3}
        if($script:case -ceq 'timeout' -and $operation -ceq 'Rehearse'){$timeout=$true;$exitCode=-999}
        if($script:case -ceq 'conflict'){$exitCode=3}
        if($operation -ceq 'Stage'){$script:dbState='MATCH';if($script:case -ceq 'lost-commit'){$exitCode=3}}
        if($script:case -ceq 'readback-fail' -and $operation -ceq 'Verify'){$exitCode=3}
        $output=if($script:case -ceq 'bad-output'){'SYNTHETIC_ADMIN_SECRET_DO_NOT_EXPORT'}else{$v|ConvertTo-Json -Compress}
        return [pscustomobject]@{stdout=$output;exitCode=$exitCode;timedOut=$timeout;elapsedSeconds=0.1;sqlStates=@();assertionFailures=@();inputLocations=@();stderrCharacters=0}
    }
    $script:acceptedFixture=Join-Path $root 'accepted.json';Sample|ConvertTo-Json -Depth 14|Set-Content -LiteralPath $script:acceptedFixture
    $cases=@('pass','resume','verify','verify-missing','cancel','wrong-evidence','dirty','no-psql','rehearse-fail','timeout','rollback-drift','unsafe','conflict','lost-commit','readback-fail','bad-custody','locked','bad-admin','bad-output','verify-db-missing')
    foreach($script:case in $cases){
        $script:called=@();$script:dbState='MISSING';$script:caseSecrets=Join-Path $root ($script:case+'-private');$caseOut=Join-Path $root ($script:case+'-report');$held=$null
        if($script:case -cin @('resume','verify','bad-custody','locked','verify-db-missing')){
            [void](New-Item -ItemType Directory -Path $script:caseSecrets);Protect-PaperHbaBackupAcl $script:caseSecrets -Directory
            Save-PaperCredential (Join-Path $script:caseSecrets 'writer.dpapi') $fixturePayload $entropy
            $script:dbState='MATCH'
            if($script:case -ceq 'verify-db-missing'){$script:dbState='MISSING'}
            if($script:case -ceq 'bad-custody'){[IO.File]::WriteAllBytes((Join-Path $script:caseSecrets 'writer.dpapi'),(New-Object byte[] 1))}
            if($script:case -ceq 'locked'){$held=[IO.File]::Open((Join-Path $script:caseSecrets 'credential.lock'),'OpenOrCreate','ReadWrite','None')}
        }
        $mode=if($script:case -cin @('verify','verify-missing','verify-db-missing')){'Verify'}else{'Stage'}
        try {if($script:case -cin @('pass','resume','verify')){& $runner -InstallationReportPath $script:acceptedFixture -Mode $mode -OutputDirectory $caseOut}else{Reject {& $runner -InstallationReportPath $script:acceptedFixture -Mode $mode -OutputDirectory $caseOut}}}finally{if($held){$held.Dispose()}}
        $files=@(Get-ChildItem -LiteralPath $caseOut -Filter '*.json');Check ($files.Count -eq 1) 'one shareable report'
        $raw=Get-Content -LiteralPath $files[0].FullName -Raw;$r=$raw|ConvertFrom-Json
        Check (-not $raw.Contains('SYNTHETIC_ADMIN_SECRET_DO_NOT_EXPORT') -and -not $raw.Contains('SCRAM-SHA-256$') -and -not $raw.Contains($golden)) 'no admin secret or verifier in evidence'
        Check (-not $r.applicationWriterActivated -and -not $r.actionExecutionEnabled -and -not $r.accountRowsWritten) 'safety boundaries'
        $progressCorrect=$true;for($i=1;$i -lt $r.events.Count;$i++){if($r.events[$i].percent -lt $r.events[$i-1].percent){$progressCorrect=$false}};Check $progressCorrect 'progress never goes backwards'
        Check (@($script:called|Where-Object {$_ -ceq 'Stage'}).Count -le 1) 'no automatic apply retry'
        if($script:case -ceq 'pass'){Check (($script:called -join ',') -ceq 'Inspect,Rehearse,Inspect,Stage,Verify') 'full guarded sequence';Check ($r.commitOutcome -ceq 'CREDENTIAL_COMMITTED_AND_VERIFIED') 'commit plus independent readback'}
        elseif($script:case -cin @('resume','verify')){Check (($script:called -join ',') -ceq 'Inspect') 'resume only inspects';Check ($r.commitOutcome -ceq 'EXISTING_CREDENTIAL_VERIFIED_NO_CHANGE') 'existing credential preserved';Check (-not $r.custodyCreated -and -not $r.applyAttempted) 'no generation or replacement on resume'}
        else {Check ($r.status -ceq 'STOPPED_REVIEW_REQUIRED') 'failure not success'}
        if($script:case -cin @('lost-commit','readback-fail')){Check ($r.commitOutcome -ceq 'UNKNOWN_VERIFY_BEFORE_RETRY') 'uncertain commit preserved';Check $r.custodyRetained 'custody preserved for recovery'}
        elseif($script:case -cne 'pass'){Check (-not $r.applyAttempted) 'no premature mutation'}
        if($script:case -cin @('cancel','wrong-evidence','dirty','no-psql','verify-missing','bad-custody','locked','bad-admin')){Check ($script:called.Count -eq 0) 'early fail before database'}
    }
    $watch.Stop();Write-Host ("PASS: $script:checks offline assertions; 20 runner scenarios; elapsed="+$watch.Elapsed.TotalSeconds+'s. Database mocked; only synthetic Windows custody used.')
} finally {
    [Array]::Clear($fixturePayload,0,$fixturePayload.Length);[Array]::Clear($entropy,0,$entropy.Length)
    # This unique owned temporary directory contains only generated test fixtures.
    $resolved=[IO.Path]::GetFullPath($root);$tempBase=[IO.Path]::GetFullPath([IO.Path]::GetTempPath())
    if($resolved.StartsWith($tempBase,[StringComparison]::OrdinalIgnoreCase) -and [IO.Path]::GetFileName($resolved) -cmatch '^paper-credential-offline-[a-f0-9]{32}$'){
        Remove-Item -LiteralPath $resolved -Recurse -Force
    }else{throw 'Synthetic cleanup scope refused'}
}
