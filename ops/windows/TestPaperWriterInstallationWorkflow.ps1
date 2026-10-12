# Offline only: SQL is generated, never executed. Real runner with native I/O mocked.
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'NumericalHistoryEvidence.ps1')
. (Join-Path $PSScriptRoot 'PaperWriterInstallation.ps1')
$script:checks=0
function Check($Value,[string]$Message){if(-not $Value){throw $Message};$script:checks++}
function Reject([scriptblock]$Body){$failed=$false;try{& $Body}catch{$failed=$true};Check $failed 'Expected rejection'}
function Sample {
    @{planHash=('a'*32);plan=@{version='PAPER_WRITER_INSTALL_PLAN_V1';database='marketbrain';databaseOid='123';clusterId='123456';adminSuperuser=$true;schemaExists=$true;serverVersion=180006;roleCount=1;membershipCount=0;relationCount=12;requiredTables=12;roleCollisions=0;functionCollisions=0;publicCreateSchemas=0;publicDefiners=0;defaultFunctionAcls=0;publicDatabaseCreate=$false;publicTemp=$true;roles=@(@{roleOid=10;roleName='postgres';login=$true;superuser=$true;createRole=$true;createDatabase=$true;inherit=$true;replication=$true;bypassRls=$true;temp=$true;explicitTemp=$false});memberships=@()}}|ConvertTo-Json -Depth 10|ConvertFrom-Json
}
function Receipt([string]$Phase){@{version='PAPER_WRITER_INSTALL_CHECK_V1';phase=$Phase;planHash=('a'*32);checksPassed=$true;loginEnabled=$false;applicationWriterActivated=$false;actionExecutionEnabled=$false;accountRowsWritten=$false}|ConvertTo-Json|ConvertFrom-Json}
Assert-PaperWriterInstallPlan (Sample);Check $true 'valid plan'
foreach($field in @('roleCollisions','functionCollisions','publicCreateSchemas','publicDefiners','defaultFunctionAcls')){$v=Sample;$v.plan.$field=1;Reject {Assert-PaperWriterInstallPlan $v}}
foreach($field in @('serverVersion','roleCount','membershipCount','relationCount','requiredTables')){$v=Sample;$v.plan.$field='1';Reject {Assert-PaperWriterInstallPlan $v};$v.plan.$field=-1;Reject {Assert-PaperWriterInstallPlan $v}}
foreach($mutation in @({param($p)$p.planHash='injection'},{param($p)$p.plan.database="x';DROP ROLE x;--"},{param($p)$p.plan.databaseOid='x'},{param($p)$p.plan.clusterId='x'},{param($p)$p.plan.adminSuperuser=$false},{param($p)$p.plan.schemaExists=$false},{param($p)$p.plan.publicTemp='false'},{param($p)$p.plan.publicDatabaseCreate=$true},{param($p)$p.plan.roleCount=129},{param($p)$p.plan.roleCount=0},{param($p)$p.plan.membershipCount=257},{param($p)$p.plan.relationCount=513},{param($p)$p.plan.serverVersion=170000},{param($p)$p.plan.serverVersion=190000},{param($p)$p.plan.roles[0].roleName="bad`nrole"},{param($p)$p.plan.roles[0].login='false'},{param($p)$p.plan.roles=@()},{param($p)$p.plan.roleCount=2;$p.plan.roles=@($p.plan.roles[0],$p.plan.roles[0])})){$v=Sample;& $mutation $v;Reject {Assert-PaperWriterInstallPlan $v}}
Assert-PaperWriterInstallReceipt (Receipt 'Verify') 'Verify' ('a'*32);Check $true 'valid receipt'
foreach($field in @('loginEnabled','applicationWriterActivated','actionExecutionEnabled','accountRowsWritten')){$v=Receipt 'Verify';$v.$field=$true;Reject {Assert-PaperWriterInstallReceipt $v 'Verify' ('a'*32)};$v.$field='false';Reject {Assert-PaperWriterInstallReceipt $v 'Verify' ('a'*32)}}
$v=Receipt 'Verify';$v.checksPassed=$false;Reject {Assert-PaperWriterInstallReceipt $v 'Verify' ('a'*32)}
Reject {Assert-PaperWriterInstallReceipt (Receipt 'Apply') 'Verify' ('a'*32)}
Reject {Assert-PaperWriterInstallReceipt (Receipt 'Verify') 'Verify' ('b'*32)}
Check ((ConvertTo-PaperSqlLiteral "O'Brien") -ceq "'O''Brien'") 'SQL literal escaping'
Reject {ConvertTo-PaperSqlLiteral ([string][char]0)}
Reject {Get-PaperWriterInstallResource '../other.sql'}
$v=Sample;$v.plan.roles[0].roleName='$mb$';Reject {New-PaperWriterInstallSql 'Rehearse' $v}
foreach($phase in @('Plan','Rehearse','Apply','Verify')) {
    $sql=New-PaperWriterInstallSql $phase (Sample)
    Check ($sql -notmatch '__[A-Z_]+__') 'no unresolved SQL placeholders'
    Check ($sql.StartsWith('BEGIN;') -and $sql.Contains("statement_timeout='15s'") -and $sql.Contains("lock_timeout='3s'")) 'bounded transaction'
    if($phase -in @('Plan','Verify')){Check ($sql.Contains('SET TRANSACTION READ ONLY;') -and $sql.EndsWith('ROLLBACK;')) 'read-only rollback';Check ($sql -notmatch '(?i)CREATE ROLE|GRANT |REVOKE |ALTER FUNCTION|UPDATE public\.') 'read mode not installation'}
    else {
        Check ($sql.IndexOf('Approved catalog plan changed') -lt $sql.IndexOf('CREATE ROLE')) 'guard before changes'
        Check ($sql.Contains('REVOKE TEMPORARY ON DATABASE %I FROM PUBLIC RESTRICT')) 'narrow database revoke'
        Check ($sql.Contains('GRANT TEMPORARY ON DATABASE %I TO %I')) 'existing role preservation'
        Check ([regex]::Matches($sql,'NOLOGIN PASSWORD NULL').Count -eq 2) 'both roles non-login'
        Check ($sql -notmatch 'DROP |CASCADE|ALL TABLES|ALTER DEFAULT PRIVILEGES|PASSWORD ''') 'no broad destructive changes or credentials'
        Check ($sql.Contains('Wrong function signatures') -and $sql.Contains('Column mutation boundary mismatch')) 'independent permission assertions'
        Check ($sql.EndsWith($(if($phase -eq 'Apply'){'COMMIT;'}else{'ROLLBACK;'}))) 'correct transaction ending'
    }
}
$source=Get-Content (Join-Path $PSScriptRoot 'InstallPaperApprovalWriter.ps1') -Raw
$helper=Get-Content (Join-Path $PSScriptRoot 'PaperWriterInstallation.ps1') -Raw
foreach($src in @($source,$helper)){$tokens=$null;$errors=$null;[void][Management.Automation.Language.Parser]::ParseInput($src,[ref]$tokens,[ref]$errors);Check ($errors.Count -eq 0) 'PowerShell parses'}
Check ($helper.Contains("Environment['PGPASSWORD']") -and $helper.Contains("Remove('PGPASSWORD')")) 'password child environment only'
Check ($helper.Contains('ReadToEndAsync') -and $helper.Contains('120') -and $helper.Contains('ON_ERROR_STOP=1')) 'bounded drained native execution'
$verifySql=Get-PaperWriterInstallResource 'writer-install-verify-v1.sql'
Check ($verifySql.Contains('FOR v_relation IN SELECT c.oid') -and $verifySql.Contains('attrelid=v_relation.oid')) 'record variables do not shadow catalog aliases'
Check ($verifySql.Contains('Required tables changed') -and $verifySql.Contains("left(n.nspname,3)<>'pg_'")) 'required objects and exact system namespace exclusion'
$repo=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../..'))
$mocked=$source.Replace('#Requires -Version 7.0','').Replace(". (Join-Path `$PSScriptRoot 'NumericalHistoryEvidence.ps1')",'').Replace(". (Join-Path `$PSScriptRoot 'PaperWriterInstallation.ps1')",'')
$mocked=[regex]::Replace($mocked,'(?m)^\$repo=.*$',('$repo='''+$repo.Replace("'","''")+'''').Replace('$','$$'))
$runner=[scriptblock]::Create($mocked)
$root=Join-Path ([IO.Path]::GetTempPath()) ('paper-install-offline-'+[guid]::NewGuid().ToString('N'));[void](New-Item -ItemType Directory -Path $root)
function git {$global:LASTEXITCODE=0;if($args -contains 'rev-parse'){'a'*40}}
function Test-Path {param($LiteralPath,$PathType);if($LiteralPath -like '*psql.exe'){return $true};if($PathType){Microsoft.PowerShell.Management\Test-Path -LiteralPath $LiteralPath -PathType $PathType}else{Microsoft.PowerShell.Management\Test-Path -LiteralPath $LiteralPath}}
function Read-Host {param($Prompt,[switch]$AsSecureString)
    if($AsSecureString){return (ConvertTo-SecureString 'TEST_PASSWORD_NEVER_SERIALIZE' -AsPlainText -Force)}
    if($Prompt -like 'Type the database*'){return 'marketbrain'}
    if($Prompt -like 'PostgreSQL administrator username*'){return 'postgres'}
    if($Prompt -like '*BACKED_UP*'){if($script:case -eq 'backup-cancel'){return 'NO'};return 'BACKED_UP'}
    if($Prompt -like '*IDLE*'){return 'IDLE'}
    if($Prompt -like '*APPROVE_ROLES*'){if($script:case -eq 'roles-cancel'){return 'NO'};return 'APPROVE_ROLES'}
    if($Prompt -like '*INSTALL*'){if($script:case -eq 'commit-cancel'){return 'NO'};return ('INSTALL '+('a'*32))}
    throw 'Unrecognized prompt'
}
function Invoke-PaperInstallerPsql([string]$Executable,[string]$Database,[int]$Port,[string]$Admin,[string]$Password,[string]$Sql) {
    $phase=if($Sql -match "'phase','(\w+)'"){$Matches[1]}else{'Plan'};$script:phases+=,$phase
    Check ($Password -ceq 'TEST_PASSWORD_NEVER_SERIALIZE') 'password not SQL or arguments'
    Check (-not $Sql.Contains($Password)) 'no SQL password'
    $v=if($phase -eq 'Plan'){Sample}else{Receipt $phase}
    if($script:case -eq 'drift' -and @($script:phases|Where-Object {$_ -eq 'Plan'}).Count -eq 2){$v.planHash='b'*32}
    if($script:case -eq 'unsafe-receipt' -and $phase -eq 'Rehearse'){$v.actionExecutionEnabled=$true}
    $exitCode=0;$timedOut=$false
    if(($script:case -eq 'rehearsal-fail' -and $phase -eq 'Rehearse') -or ($script:case -eq 'lost-commit' -and $phase -eq 'Apply') -or ($script:case -eq 'verify-fail' -and $phase -eq 'Verify')){$exitCode=1}
    if($script:case -eq 'timeout' -and $phase -eq 'Rehearse'){$exitCode=-999;$timedOut=$true}
    [pscustomobject]@{stdout=($v|ConvertTo-Json -Depth 10 -Compress);exitCode=$exitCode;timedOut=$timedOut;elapsedSeconds=0.1;sqlStates=@();assertionFailures=@();stderrCharacters=0}
}
$passedPath=$null
foreach($script:case in @('pass','plan-only','backup-cancel','roles-cancel','commit-cancel','rehearsal-fail','unsafe-receipt','timeout','drift','lost-commit','verify-fail','verify-only')) {
    $script:phases=@();$dir=Join-Path $root $script:case
    $parameters=@{OutputDirectory=$dir;Apply=$true}
    if($script:case -eq 'plan-only'){$parameters.Apply=$false}
    if($script:case -eq 'verify-only'){$parameters.Remove('Apply');$parameters.VerifyReportPath=$passedPath}
    if($script:case -in @('pass','plan-only','verify-only')){& $runner @parameters}else{Reject {& $runner @parameters}}
    $files=@(Get-ChildItem -LiteralPath $dir -Filter '*.json');Check ($files.Count -eq 1) 'one report'
    $raw=Get-Content -LiteralPath $files[0].FullName -Raw;$r=$raw|ConvertFrom-Json
    Check (-not $raw.Contains('TEST_PASSWORD_NEVER_SERIALIZE')) 'no secret in evidence'
    Check (-not $r.applicationWriterActivated -and -not $r.actionExecutionEnabled -and -not $r.credentialsSaved) 'activation remains off'
    Check (@($script:phases|Where-Object {$_ -eq 'Apply'}).Count -le 1) 'no apply retry'
    if($script:case -eq 'pass'){Check ($r.commitOutcome -eq 'COMMITTED_AND_VERIFIED') 'readback required';Check (($script:phases -join ',') -eq 'Plan,Rehearse,Plan,Apply,Verify') 'stage order';Check $r.rehearsalRollbackVerified 'rollback verified';$passedPath=$files[0].FullName}
    elseif($script:case -eq 'plan-only'){Check ($r.status -eq 'INSTALLATION_PLAN_CAPTURED_NO_CHANGES') 'default no changes';Check (($script:phases -join ',') -eq 'Plan') 'only plan'}
    elseif($script:case -eq 'verify-only'){Check ($r.commitOutcome -eq 'STAGED_STATE_VERIFIED') 'saved verification';Check (($script:phases -join ',') -eq 'Verify') 'no verification writes'}
    else{Check ($r.status -eq 'STOPPED_REVIEW_REQUIRED') 'failed workflow not success'}
    if($script:case -eq 'lost-commit'){Check ($r.commitOutcome -eq 'UNKNOWN_VERIFY_BEFORE_RETRY') 'unknown commit preserved'}
    elseif($script:case -eq 'verify-fail'){Check ($r.commitOutcome -eq 'COMMIT_ACKNOWLEDGED_READBACK_PENDING') 'readback failure not undone'}
    elseif($script:case -notin @('pass','verify-only','plan-only')){Check (-not $r.applyAttempted) 'precommit guard prevented apply'}
}
Write-Host "PASS: $script:checks offline assertions. SQL not executed; native processes mocked. Fixtures retained: $root"
