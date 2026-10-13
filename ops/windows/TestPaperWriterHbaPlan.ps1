# Offline contracts and actual runner control flow. All DB/Docker/credentials are synthetic.
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'NumericalHistoryEvidence.ps1')
. (Join-Path $PSScriptRoot 'PaperWriterCustody.ps1')
. (Join-Path $PSScriptRoot 'PaperWriterRestriction.ps1')
. (Join-Path $PSScriptRoot 'PaperWriterAccessReview.ps1')
. (Join-Path $PSScriptRoot 'PaperWriterHbaPlan.ps1')
$script:checks=0
function Check([bool]$Value,[string]$Name){if(-not $Value){throw $Name};$script:checks++}
function Denied([scriptblock]$Action,[string]$Code){$caught=$null;try{& $Action|Out-Null}catch{$caught=$_.Exception.Message};Check ($caught -ceq $Code) ('Expected '+$Code)}
$work=Join-Path ([IO.Path]::GetTempPath()) ('mb-hba-plan-test-'+[guid]::NewGuid().ToString('N'))
[void][IO.Directory]::CreateDirectory($work)
$hba=Join-Path $work 'pg_hba.conf';$psqlPath=Join-Path $work 'psql.exe'
$bytes=[Text.Encoding]::UTF8.GetBytes("# PRIVATE_COMMENT_SENTINEL`r`nlocal all all scram-sha-256`r`nhost all all 127.0.0.1/32 scram-sha-256`r`n")
[IO.File]::WriteAllBytes($hba,$bytes);[IO.File]::WriteAllBytes($psqlPath,@())
$script:base=[pscustomobject]@{version='PAPER_HBA_METADATA_V1';database='marketbrain';databaseOid='16389';clusterId='7679149914381758260';serverPort=5432;serverVersion=180000;serverStartEpoch='1790000000.123456';adminSuperuser=$true;writerCount=1;writerLoginEnabled=$false;hbaPath=$hba;hbaBytes=$bytes.Length;hbaHash=(Get-PaperRestrictionHash $bytes);hbaRuleCount=2;hbaErrorCount=0;readOnly=$true}
Assert-PaperHbaMetadata $script:base
$plan=Read-PaperHbaLocalPlan $script:base
Check ($plan.existingBytesPreserved -and -not $plan.hbaChanged -and -not $plan.applyImplemented -and -not $plan.backupCreated) 'Read-only candidate plan'
Check (($plan|ConvertTo-Json -Depth 5) -notmatch 'PRIVATE_COMMENT_SENTINEL') 'Original contents never included'
Check ($plan.candidateBytes -gt $bytes.Length -and $plan.candidateHash -cne $plan.originalHash -and $plan.aclFingerprint -match '^[A-F0-9]{64}$') 'Plan hashes and size recorded'
foreach($case in @(@('clusterId','wrong','HBA_PLAN_DATABASE_IDENTITY_MISMATCH'),@('databaseOid','999','HBA_PLAN_DATABASE_IDENTITY_MISMATCH'),@('writerLoginEnabled',$true,'HBA_PLAN_WRITER_NOT_DISABLED'),@('writerCount',0,'HBA_PLAN_WRITER_NOT_DISABLED'),@('hbaBytes',1048577,'HBA_PLAN_FILE_METADATA_INVALID'),@('hbaErrorCount',1,'HBA_PLAN_FILE_METADATA_INVALID'),@('hbaRuleCount',257,'HBA_PLAN_FILE_METADATA_INVALID'),@('serverVersion',170000,'HBA_PLAN_SERVER_UNSUPPORTED'),@('readOnly',$false,'HBA_PLAN_READ_ONLY_ADMIN_REQUIRED'),@('adminSuperuser',$false,'HBA_PLAN_READ_ONLY_ADMIN_REQUIRED'),@('hbaBytes','10','HBA_PLAN_METADATA_TYPE_INVALID'))){
    $v=$script:base|ConvertTo-Json|ConvertFrom-Json;$v.($case[0])=$case[1]
    Denied {Assert-PaperHbaMetadata $v} $case[2]
}
Denied {New-PaperHbaFilePlan ([byte[]]@(1,2)) $script:base 'D:fixture'} 'HBA_PLAN_LOCAL_SERVER_FILE_MISMATCH'
Denied {New-PaperHbaFilePlan $bytes $script:base ''} 'HBA_PLAN_ACL_UNAVAILABLE'
$sql=New-PaperHbaMetadataSql
Check ($sql.Contains('BEGIN READ ONLY;') -and $sql.Trim().EndsWith('ROLLBACK;') -and $sql.Contains('1048577') -and $sql.Contains('LIMIT 257')) 'Bounded read-only SQL'
Check ($sql -notmatch '(?i)ALTER\s|CREATE\s|DROP\s|INSERT\s|UPDATE\s|DELETE\s|COPY\s|pg_reload_conf|pg_read_file\(') 'No modifying SQL or raw text file output'
$bad=Join-Path $work 'bad.json';[IO.File]::WriteAllText($bad,'{}')
Denied {Read-PaperHbaPreparation $bad} 'HBA_PLAN_EVIDENCE_HASH_MISMATCH'
$script:localPlanImplementation=(Get-Item Function:\Read-PaperHbaLocalPlan).ScriptBlock
function Read-PaperHbaLocalPlan($Metadata){
    $script:localReads++;$value=& $script:localPlanImplementation $Metadata
    if($script:mode -ceq 'acl-drift' -and $script:localReads -gt 1){$value.aclFingerprint='B'*64}
    return $value
}
function Read-PaperHbaPreparation($Path){if($script:mode -ceq 'bad-input'){throw 'HBA_PLAN_EVIDENCE_HASH_MISMATCH'};return [pscustomobject]@{}}
function git {$global:LASTEXITCODE=0;if($args -contains 'status' -and $script:mode -ceq 'dirty'){' M unrelated'};if($args -contains 'rev-parse'){'a'*40}}
function Get-Command {param($Name,$CommandType,$ErrorAction);[pscustomobject]@{Source=$Name}}
function Read-Host {param($Prompt,[switch]$AsSecureString);if($AsSecureString){ConvertTo-SecureString 'PASSWORD_SENTINEL' -AsPlainText -Force}elseif($Prompt -like '*type marketbrain*'){'marketbrain'}else{'postgres'}}
function Invoke-PaperInstallerPsql($Executable,$Database,$Port,$Admin,$Password,$Sql){
    $script:dbCalls++
    Check ($Database -ceq 'marketbrain' -and $Port -eq 5432 -and $Sql -ceq (New-PaperHbaMetadataSql)) 'Fixed read-only database query'
    $v=$script:base|ConvertTo-Json|ConvertFrom-Json
    if($script:mode -ceq 'wrong-db'){$v.clusterId='wrong'}
    if($script:mode -ceq 'enabled-writer'){$v.writerLoginEnabled=$true}
    if($script:mode -ceq 'server-drift' -and $script:dbCalls -gt 1){$v.serverStartEpoch='1790000001.123456'}
    if($script:mode -ceq 'file-drift' -and $script:dbCalls -gt 1){$v.hbaHash='A'*64}
    [pscustomobject]@{exitCode=if($script:mode -ceq 'sql-error'){1}else{0};timedOut=($script:mode -ceq 'sql-timeout');elapsedSeconds=0.01;sqlStates=@();stdout=($v|ConvertTo-Json -Compress)}
}
function Invoke-PaperCatalogProcess($Executable,$Arguments,$WorkingDirectory,$LimitSeconds){
    Check ($LimitSeconds -le 60 -and ($Arguments -join ' ') -notmatch 'PASSWORD_SENTINEL') 'Bounded process and no password in arguments'
    $output='';$exit=0
    if($Executable -ceq 'javac'){
        $folder=$Arguments[3];$package=Join-Path $folder 'in\marketbrain\paper';[void][IO.Directory]::CreateDirectory($package)
        [IO.File]::WriteAllBytes((Join-Path $package 'PaperApplicationRouteProbe.class'),@())
        if($script:mode -ceq 'compile-fail'){$exit=1}
    }elseif($Arguments[0] -ceq 'ps'){$output=if($script:mode -ceq 'ambiguous-container'){"abcdef012345`nabcdef678901"}else{'abcdef012345'}}
    elseif($Arguments -contains 'java'){
        $run=$Arguments[-1]
        $v=[pscustomobject]@{version='PAPER_APPLICATION_ROUTE_V1';status='READ_ONLY_APPLICATION_ROUTE_OBSERVED';database='marketbrain';databaseOid='16389';applicationUser='marketbrain_app';sessionUser='marketbrain_app';clientAddress='127.0.0.1';serverAddress='127.0.0.1';serverPort=5432;serverStartEpoch='1790000000.123456';applicationName=('mb-route-'+$run);readOnly=$true;databaseWritesPerformed=$false;writerLoginAttempted=$false;actionExecutionEnabled=$false}
        if($script:mode -ceq 'wrong-route'){$v.clientAddress='192.168.1.20'}
        $output=$v|ConvertTo-Json -Compress
    }elseif($script:mode -in @('cleanup-error','copy-fail') -and $Arguments -contains 'rmdir'){$exit=1}
    if($script:mode -ceq 'copy-fail' -and $Arguments[0] -ceq 'cp'){$exit=1}
    [pscustomobject]@{stdout=$output;stderr='PASSWORD_SENTINEL';exitCode=$exit;timedOut=$false;elapsedSeconds=0.01}
}
$runnerPath=Join-Path $PSScriptRoot 'GetPaperWriterHbaPlan.ps1'
$text=Get-Content -LiteralPath $runnerPath -Raw
$text=$text.Replace('#Requires -Version 7.0','')
$text=[regex]::Replace($text,'(?m)^\. \(Join-Path \$PSScriptRoot ''[^'']+''\)\r?\n','')
$text=$text.Replace('$PSScriptRoot',("'"+$PSScriptRoot.Replace("'","''")+"'"))
$text=[regex]::Replace($text,'(?m)^    \$principal=.*\r?\n','')
$text=[regex]::Replace($text,'(?m)^    if\(-not \$principal\.IsInRole.*\r?\n','')
$runner=[scriptblock]::Create($text)
foreach($script:mode in @('pass','bad-input','dirty','wrong-db','enabled-writer','sql-error','wrong-route','server-drift','file-drift','ambiguous-container','cleanup-error','compile-fail','copy-fail','acl-drift','sql-timeout')){
    $dir=Join-Path $work $script:mode;$script:dbCalls=0;$script:localReads=0;$threw=$false
    try {& $runner -PreparationReportPath $bad -PostgreSqlBin $work -OutputDirectory $dir}catch{$threw=$true}
    $files=@(Get-ChildItem -LiteralPath $dir -Filter '*.json');Check ($files.Count -eq 1) 'One report'
    $raw=Get-Content -LiteralPath $files[0].FullName -Raw;$v=$raw|ConvertFrom-Json
    Check ($raw -notmatch 'PASSWORD_SENTINEL|PRIVATE_COMMENT_SENTINEL') 'Secrets and original file text excluded'
    foreach($flag in @('databaseWritesPerformed','hbaChanged','firewallChanged','writerLoginAttempted','credentialsSaved','applicationWriterActivated','actionExecutionEnabled')){Check ($v.$flag -is [bool] -and -not $v.$flag) ('Safety '+$flag)}
    if($script:mode -ceq 'pass'){Check (-not $threw -and $v.status -ceq 'HBA_PLAN_CAPTURED_APPLY_BLOCKED' -and $v.cleanupComplete -and $script:dbCalls -eq 2 -and $v.planFingerprint -match '^[A-F0-9]{64}$') 'Full read-only plan flow'}
    else{Check ($threw -and $v.status -ceq 'FAILED' -and $v.failureCode) ('Failed closed '+$script:mode)}
    if($script:mode -in @('bad-input','dirty','ambiguous-container')){Check ($script:dbCalls -eq 0) 'Preflight failure skips database'}
    if($script:mode -ceq 'copy-fail'){Check ($v.failureCode -ceq 'HBA_PLAN_NATIVE_STAGE_FAILED' -and $v.cleanupFailureCode -ceq 'HBA_PLAN_DIAGNOSTIC_CLEANUP_REQUIRED') 'Cleanup does not hide original failure'}
    if($script:mode -ceq 'acl-drift'){Check ($v.failureCode -ceq 'HBA_PLAN_FILE_OR_ACL_CHANGED') 'ACL drift prevents plan completion'}
    Check ((Get-PaperRestrictionHash ([IO.File]::ReadAllBytes($hba))) -ceq $script:base.hbaHash) 'Fixture authentication file unchanged'
    # A deliberately failed container cleanup still permits local fixture cleanup; runner retains its generated directory.
    foreach($probe in @(Get-ChildItem -LiteralPath $dir -Directory)){
        Check ($probe.Name -match '^hba-probe-[a-f0-9]{32}$') 'Owned fixture cleanup'
        [IO.File]::Delete((Join-Path $probe.FullName 'in\marketbrain\paper\PaperApplicationRouteProbe.class'))
        foreach($suffix in @('in\marketbrain\paper','in\marketbrain','in')){$p=Join-Path $probe.FullName $suffix;if([IO.Directory]::Exists($p)){[IO.Directory]::Delete($p,$false)}}
        [IO.Directory]::Delete($probe.FullName,$false)
    }
    [IO.File]::Delete($files[0].FullName);[IO.Directory]::Delete($dir,$false)
}
foreach($file in @('PaperWriterHbaPlan.ps1','GetPaperWriterHbaPlan.ps1','TestPaperWriterHbaPlan.ps1')){
    $tokens=$null;$errors=$null;$null=[Management.Automation.Language.Parser]::ParseFile((Join-Path $PSScriptRoot $file),[ref]$tokens,[ref]$errors)
    Check ($errors.Count -eq 0) ('Parses '+$file)
}
[IO.File]::Delete($hba);[IO.File]::Delete($psqlPath);[IO.File]::Delete($bad);[IO.Directory]::Delete($work,$false)
Write-Host "PASS: $script:checks HBA plan assertions; synthetic files, mocked PostgreSQL/Docker only."
