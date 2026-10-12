# Offline only. No database, Docker, application, provider or model is started.
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'NumericalHistoryEvidence.ps1')
. (Join-Path $PSScriptRoot 'PaperWriterInstallation.ps1')
. (Join-Path $PSScriptRoot 'PaperWriterConnectionReview.ps1')
$script:checks=0
function Check($Value,[string]$Message){if(-not $Value){throw $Message};$script:checks++}
function Reject([scriptblock]$Body){$failed=$false;try{& $Body}catch{$failed=$true};Check $failed 'Expected rejection'}
function Sample {
    @{planHash=('a'*32);plan=@{version='PAPER_WRITER_INSTALL_PLAN_V1';database='marketbrain';databaseOid='123';clusterId='123456';adminSuperuser=$true;schemaExists=$true;serverVersion=180006;roleCount=1;membershipCount=0;relationCount=12;requiredTables=12;roleCollisions=0;functionCollisions=0;publicCreateSchemas=0;publicDefiners=0;defaultFunctionAcls=0;publicDatabaseCreate=$false;publicTemp=$true;roles=@(@{roleOid=10;roleName='postgres';login=$true;superuser=$true;createRole=$true;createDatabase=$true;inherit=$true;replication=$true;bypassRls=$true;temp=$true;explicitTemp=$false});memberships=@()}}|ConvertTo-Json -Depth 10|ConvertFrom-Json
}
function Receipt([string]$Phase){@{version='PAPER_WRITER_INSTALL_CHECK_V1';phase=$Phase;planHash=('a'*32);checksPassed=$true;loginEnabled=$false;applicationWriterActivated=$false;actionExecutionEnabled=$false;accountRowsWritten=$false}|ConvertTo-Json|ConvertFrom-Json}
function Installed {
    @{version='PAPER_WRITER_INSTALL_BUNDLE_V1';status='STAGED_WRITER_VERIFIED_LOGIN_AND_ACTIONS_DISABLED';commitOutcome='COMMITTED_AND_VERIFIED';failure=$null;failureCode=$null;backupConfirmed=$true;maintenanceConfirmed=$true;targetConfirmed=$true;rolesApproved=$true;rehearsalRollbackVerified=$true;applyRequested=$true;applyAttempted=$true;applicationWriterActivated=$false;actionExecutionEnabled=$false;credentialsSaved=$false;plan=(Sample);target=@{host='127.0.0.1';database='marketbrain';port=5432};steps=@('Plan','Rehearse','Plan','Apply','Verify'|ForEach-Object {@{phase=$_;exitCode=0;timedOut=$false}});rehearsal=(Receipt 'Rehearse');applyReceipt=(Receipt 'Apply');verification=(Receipt 'Verify')}|ConvertTo-Json -Depth 12|ConvertFrom-Json
}
function Inventory {
    @{version='PAPER_WRITER_CONNECTION_REVIEW_V1';database='marketbrain';databaseOid='123';clusterId='123456';serverPort=5432;serverVersion=180006;hbaEvidence='CURRENT_FILE_NOT_PROOF_OF_LOADED_RULES_OR_CLIENT_ROUTE';adminSuperuser=$true;writerLoginEnabled=$false;databaseWritesPerformed=$false;credentialsSaved=$false;applicationWriterActivated=$false;actionExecutionEnabled=$false;passwordEncryption='scram-sha-256';ssl='on';databases=@(@{name='marketbrain';oid='123';allowsConnections=$true;template=$false;writerConnect=$true;writerCreate=$false;writerTemp=$false});hbaRules=@(@{ruleNumber=1;lineNumber=10;type='host';databases=@('all');users=@('all');address='127.0.0.1';netmask='255.255.255.255';authMethod='scram-sha-256';optionsPresent=$false;hasError=$false})}|ConvertTo-Json -Depth 10|ConvertFrom-Json
}
Assert-PaperInstalledReport (Installed);Check $true 'accepted install'
for($stageIndex=0;$stageIndex -lt 5;$stageIndex++) {
    foreach($value in @([int]0,[long]0)) {
        $v=Installed;$v.steps[$stageIndex].exitCode=$value
        Assert-PaperInstalledReport $v;Check $true 'Int32 and Int64 zero accepted at every stage'
    }
    foreach($value in @([int]1,[long]1,[int]-1,[long]-1,'0',$false,$null,[double]0,[double]0.5,[decimal]0,[long]4294967296)) {
        $v=Installed;$v.steps[$stageIndex].exitCode=$value
        Reject {Assert-PaperInstalledReport $v}
        try {Assert-PaperInstalledReport $v} catch {
            Check ($_.Exception.Data['PaperConnectionCode'] -ceq 'INSTALLATION_STAGE_INVALID' -and $_.Exception.Data['PaperConnectionStageIndex'] -eq $stageIndex) 'safe fixed code and stage index'
        }
    }
}
foreach($flag in @('backupConfirmed','maintenanceConfirmed','targetConfirmed','rolesApproved','rehearsalRollbackVerified','applyRequested','applyAttempted')){$v=Installed;$v.$flag=$false;Reject {Assert-PaperInstalledReport $v};$v.$flag='true';Reject {Assert-PaperInstalledReport $v}}
foreach($flag in @('applicationWriterActivated','actionExecutionEnabled','credentialsSaved')){$v=Installed;$v.$flag=$true;Reject {Assert-PaperInstalledReport $v}}
foreach($mutation in @({param($v)$v.commitOutcome='UNKNOWN'},{param($v)$v.failure='failure'},{param($v)$v.target.host='other'},{param($v)$v.target.port='5432'},{param($v)$v.target.database='other'},{param($v)$v.steps=@()},{param($v)$v.steps[3].exitCode=1},{param($v)$v.steps[2].timedOut=$true},{param($v)$v.steps[0].phase='Apply'},{param($v)$v.verification.checksPassed=$false})){$v=Installed;& $mutation $v;Reject {Assert-PaperInstalledReport $v}}
Assert-PaperConnectionReview (Inventory) (Sample) 5432;Check $true 'inventory accepted'
foreach($field in @('serverPort','serverVersion')){$v=Inventory;$v.$field=[string]$v.$field;Reject {Assert-PaperConnectionReview $v (Sample) 5432}}
$v=Inventory;$v.hbaRules[0].ruleNumber=$null;Reject {Assert-PaperConnectionReview $v (Sample) 5432}
$v.hbaRules[0].hasError=$true;Assert-PaperConnectionReview $v (Sample) 5432;Check $true 'parse-error rows retained for review'
foreach($flag in @('writerLoginEnabled','databaseWritesPerformed','credentialsSaved','applicationWriterActivated','actionExecutionEnabled')){$v=Inventory;$v.$flag=$true;Reject {Assert-PaperConnectionReview $v (Sample) 5432};$v.$flag='false';Reject {Assert-PaperConnectionReview $v (Sample) 5432}}
foreach($mutation in @({param($v)$v.database='other'},{param($v)$v.clusterId='other'},{param($v)$v.databaseOid='other'},{param($v)$v.serverPort=5433},{param($v)$v.adminSuperuser=$false},{param($v)$v.databases=@()},{param($v)$v.databases=@($v.databases[0],$v.databases[0])},{param($v)$v.hbaRules=@()},{param($v)$v.hbaRules=@($v.hbaRules[0])*257},{param($v)$v.databases=@($v.databases[0])*129},{param($v)$v.databases[0].writerTemp='false'},{param($v)$v.hbaRules[0].hasError='false'})){$v=Inventory;& $mutation $v;Reject {Assert-PaperConnectionReview $v (Sample) 5432}}
$v=Inventory;Check (@(Get-PaperConnectionFindings $v).Count -eq 3) 'even clean inventory is not activation'
$v.databases+=@{name='postgres';oid='124';allowsConnections=$true;writerConnect=$true;writerTemp=$true;writerCreate=$false}
$v.hbaRules[0].authMethod='trust';$v.hbaRules[0].hasError=$true;$v.hbaRules[0].optionsPresent=$true;$v.ssl='off';$v.passwordEncryption='md5'
$findings=@(Get-PaperConnectionFindings $v);Check ($findings.Count -eq 10) 'all independent findings retained'
$sql=New-PaperConnectionReviewSql (Sample)
Check ($sql.Contains('SET TRANSACTION ISOLATION LEVEL REPEATABLE READ, READ ONLY;') -and $sql.EndsWith('ROLLBACK;')) 'read-only rollback'
Check ([regex]::Matches($sql,'\bROLLBACK;').Count -eq 1) 'single transaction end'
Check ($sql.Contains('LIMIT 129') -and $sql.Contains('LIMIT 257')) 'overflow sentinels'
Check ($sql -notmatch '(?i)\b(CREATE ROLE|ALTER ROLE|GRANT |REVOKE |COMMIT;|pg_reload_conf|rolpassword|pg_read_file)') 'no changes or password verifier reads'
Check ($sql.Contains("'optionsPresent',options_present") -and $sql -notmatch "'options',|'error',|'fileName',") 'sensitive HBA fields excluded'
Check ($sql.IndexOf('Staged roles must remain restricted NOLOGIN') -lt $sql.IndexOf('WITH db AS')) 'live verification before inventory'
$source=Get-Content (Join-Path $PSScriptRoot 'GetPaperWriterConnectionReview.ps1') -Raw
foreach($file in @('GetPaperWriterConnectionReview.ps1','PaperWriterConnectionReview.ps1','TestPaperWriterConnectionWorkflow.ps1')){$tokens=$null;$errors=$null;[void][Management.Automation.Language.Parser]::ParseFile((Join-Path $PSScriptRoot $file),[ref]$tokens,[ref]$errors);Check ($errors.Count -eq 0) 'PowerShell parses'}
$repo=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../..'))
$mocked=$source.Replace('#Requires -Version 7.0','')
foreach($helper in @('NumericalHistoryEvidence.ps1','PaperWriterInstallation.ps1','PaperWriterConnectionReview.ps1')){$mocked=$mocked.Replace(". (Join-Path `$PSScriptRoot '$helper')",'')}
$mocked=[regex]::Replace($mocked,'(?m)^\$repo=.*$',('$repo='''+$repo.Replace("'","''")+'''').Replace('$','$$'))
$runner=[scriptblock]::Create($mocked)
$root=Join-Path ([IO.Path]::GetTempPath()) ('paper-connection-offline-'+[guid]::NewGuid().ToString('N'));[void](New-Item -ItemType Directory -Path $root)
$inputPath=Join-Path $root 'install.json';$fixture=Installed;$fixture|Add-Member -NotePropertyName updatedAtUtc -NotePropertyValue $null;Save-NumericalHistoryReport $fixture $inputPath -Compact
function git {$global:LASTEXITCODE=0;if($args -contains 'rev-parse'){'a'*40};if($args -contains 'status' -and $script:case -eq 'dirty'){' M owned.txt'}}
function ConvertFrom-Json {
    param([Parameter(ValueFromPipeline)]$InputObject)
    process {
        if($script:case -eq 'invalid-json' -and $InputObject -like '*"steps"*'){throw 'TEST_PASSWORD_NEVER_SERIALIZE'}
        $parsed=Microsoft.PowerShell.Utility\ConvertFrom-Json -InputObject $InputObject
        if($null -ne $parsed -and $parsed.PSObject.Properties['steps']) {
            if($script:case -eq 'int64-pass'){foreach($step in $parsed.steps){$step.exitCode=[long]$step.exitCode}}
            if($script:case -eq 'invalid-stage'){$parsed.steps[3].exitCode='TEST_PASSWORD_NEVER_SERIALIZE'}
        }
        return $parsed
    }
}
function Test-Path {param($LiteralPath,$PathType);if($LiteralPath -like '*psql.exe'){return ($script:case -ne 'missing-psql')};if($PathType){Microsoft.PowerShell.Management\Test-Path -LiteralPath $LiteralPath -PathType $PathType}else{Microsoft.PowerShell.Management\Test-Path -LiteralPath $LiteralPath}}
function Read-Host {param($Prompt,[switch]$AsSecureString)
    if($AsSecureString){return (ConvertTo-SecureString 'TEST_PASSWORD_NEVER_SERIALIZE' -AsPlainText -Force)}
    if($Prompt -ceq 'Confirm the database name'){if($script:case -eq 'cancel'){return 'NO'};return 'marketbrain'}
    if($Prompt -ceq 'PostgreSQL administrator username'){return 'postgres'};throw 'Unexpected prompt'
}
function Invoke-PaperInstallerPsql([string]$Executable,[string]$Database,[int]$Port,[string]$Admin,[string]$Password,[string]$Sql) {
    $script:calls++;Check ($Sql -notmatch 'TEST_PASSWORD_NEVER_SERIALIZE') 'credential never in SQL'
    $v=Inventory;$receipt=Receipt 'Verify'
    if($script:case -eq 'wrong-cluster'){$v.clusterId='wrong'}
    if($script:case -eq 'unsafe-receipt'){$receipt.loginEnabled=$true}
    $out=($receipt|ConvertTo-Json -Compress)+"`n"+($v|ConvertTo-Json -Depth 10 -Compress)
    if($script:case -eq 'malformed'){$out='TEST_PASSWORD_NEVER_SERIALIZE'}
    if($script:case -eq 'extra-row'){$out+="`n{}"}
    if($script:case -eq 'oversized'){$out='x'*2097153}
    if($script:case -eq 'native-exception'){throw 'TEST_PASSWORD_NEVER_SERIALIZE'}
    [pscustomobject]@{stdout=$out;exitCode=if($script:case -eq 'sql-fail'){3}else{0};timedOut=($script:case -eq 'timeout');elapsedSeconds=0.1;sqlStates=@();assertionFailures=@();stderrCharacters=0}
}
foreach($script:case in @('pass','int64-pass','invalid-stage','invalid-json','missing-report','dirty','missing-psql','cancel','wrong-cluster','unsafe-receipt','malformed','extra-row','oversized','native-exception','sql-fail','timeout')) {
    $script:calls=0;$dir=Join-Path $root $script:case
    $selectedInput=if($script:case -eq 'missing-report'){Join-Path $root 'missing.json'}else{$inputPath}
    if($script:case -in @('pass','int64-pass')){& $runner -InstallationReportPath $selectedInput -OutputDirectory $dir}else{Reject {& $runner -InstallationReportPath $selectedInput -OutputDirectory $dir}}
    $files=@(Get-ChildItem -LiteralPath $dir -Filter '*.json');Check ($files.Count -eq 1) 'one report per run'
    $raw=Get-Content -LiteralPath $files[0].FullName -Raw;$r=$raw|ConvertFrom-Json
    Check (-not $raw.Contains('TEST_PASSWORD_NEVER_SERIALIZE')) 'secrets absent from success and failure'
    Check ($script:calls -le 1) 'no automatic retry'
    Check (-not $r.applicationWriterActivated -and -not $r.databaseWritesPerformed -and -not $r.credentialsSaved) 'side effects disabled'
    if($script:case -in @('pass','int64-pass')){Check ($r.status -ceq 'CONNECTION_REVIEW_CAPTURED_LOGIN_DISABLED' -and $r.reviewFindings.Count -eq 3) 'inventory not authorization'}else{Check ($r.status -ceq 'FAILED') 'failure retained'}
    if($script:case -in @('dirty','missing-psql','cancel','invalid-stage','invalid-json','missing-report')){Check ($script:calls -eq 0) 'precondition before database'}
    if($script:case -eq 'invalid-stage'){Check ($r.failureCode -ceq 'INSTALLATION_STAGE_INVALID' -and $r.installationStageIndex -eq 3) 'runner retains safe validation diagnostic'}
    if($script:case -eq 'missing-report'){Check ($r.failureCode -ceq 'INSTALLATION_REPORT_UNAVAILABLE') 'missing report distinguished'}
    if($script:case -eq 'invalid-json'){Check ($r.failureCode -ceq 'INSTALLATION_REPORT_JSON_INVALID') 'JSON parse failure distinguished without raw exception'}
}
Write-Host "PASS: $script:checks offline assertions. Native processes mocked; SQL not executed. Fixtures retained: $root"
