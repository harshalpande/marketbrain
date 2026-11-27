# Offline launcher tests. All process invocation and local prompts are mocked.
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'NumericalHistoryEvidence.ps1')
. (Join-Path $PSScriptRoot 'PaperWriterPreflight.ps1')
$repo=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../..'))
$script:checks=0
function Check($ok,$message){if(-not $ok){throw $message};$script:checks++}
function Assert-PaperWriterCatalog {}
function Get-Command {param($Name,$CommandType,$ErrorAction);[pscustomobject]@{Source=(Get-Process -Id $PID).Path}}
function Read-Host {param($Prompt,[switch]$AsSecureString);if($AsSecureString){return ConvertTo-SecureString 'LOCAL_ADMIN_SECRET' -AsPlainText -Force};if($Prompt -like 'Confirm a current*'){return 'BACKED_UP'};if($Prompt -like 'Avoid concurrent*'){return 'STAGE_DISABLED'};return 'postgres'}
function Runtime {
    [pscustomobject]@{Id=('a'*64);Image='fixture-image';State=@{Running=$true;StartedAt='fixture-start'};Config=@{Labels=@{'com.docker.compose.service'='marketbrain-service';'com.docker.compose.project.working_dir'=$repo};Env=@('MARKETBRAIN_EXECUTION_MODE=PAPER','MARKETBRAIN_DB_URL=jdbc:postgresql://host.docker.internal:5432/marketbrain','MARKETBRAIN_DB_USERNAME=app','MARKETBRAIN_DB_PASSWORD=LOCAL_APP_SECRET')}}
}
function Invoke-PaperCatalogProcess($Executable,[string[]]$Arguments,$WorkingDirectory,$LimitSeconds,[string]$InputText) {
    $script:calls+=,@($Arguments);$out='';$code=0;$timeout=$false
    Check (-not ($Arguments -join ' ').Contains('LOCAL_ADMIN_SECRET')) 'secret leaked to process arguments'
    if($Arguments -contains 'rev-parse'){$out='c'*40}
    elseif($Arguments[0] -eq 'ps' -and $Arguments -contains '-q'){$out='a'*64}
    elseif($Arguments[0] -eq 'inspect'){$v=Runtime;if($script:case -eq 'stopped'){$v.State.Running=$false};$out=@($v)|ConvertTo-Json -Depth 8}
    elseif($Arguments[0] -eq 'image'){$out='sha256:'+('b'*64)}
    elseif($Arguments[0] -eq 'build' -and $script:case -eq 'build'){$code=1;$out='LOCAL_ADMIN_SECRET'}
    elseif($Arguments[0] -eq 'run') {
        Check ($InputText.Contains('LOCAL_ADMIN_SECRET')) 'secret supplied only through stdin'
        Check ($Arguments -contains '--read-only' -and $Arguments -contains '--cap-drop=ALL') 'restricted client'
        $v=@{version='PAPER_PUBLISHER_CREDENTIAL_V1';status='PUBLISHER_CREDENTIAL_VERIFIED_LOGIN_DISABLED';disabledStateVerified=$true;credentialVerified=$true;commitOutcome='COMMITTED';loginEnabled=$false;actionExecutionEnabled=$false};if($Arguments -contains '--verify-only'){$v.status='PUBLISHER_CREDENTIAL_VERIFIED_LOGIN_DISABLED';$v.commitOutcome='NOT_ATTEMPTED'}
        if($script:case -eq 'unsafe'){$v.loginEnabled=$true}
        if($script:case -eq 'timeout'){$timeout=$true;$code=-999}
    if($script:case -eq 'sql'){$code=1;$v.status='STOPPED_REVIEW_REQUIRED';$v.commitOutcome='NOT_ATTEMPTED';$v.failureType='PSQLException';$v.sqlState='28P01'};if($script:case -eq 'after-commit'){$code=1;$v.status='STOPPED_REVIEW_REQUIRED'}
        $out=$v|ConvertTo-Json -Compress;if($script:case -eq 'unknown'){$out='';$code=1}
    }
    return [pscustomobject]@{exitCode=$code;stdout=$out;stderr='LOCAL_ADMIN_SECRET';timedOut=$timeout;elapsedSeconds=0.1}
}
$source=Get-Content (Join-Path $PSScriptRoot 'StagePaperPublisherCredential.ps1') -Raw
$source=$source.Replace(". (Join-Path `$PSScriptRoot 'NumericalHistoryEvidence.ps1')",'').Replace(". (Join-Path `$PSScriptRoot 'PaperWriterPreflight.ps1')",'')
$source=[regex]::Replace($source,'(?m)^\$repo=.*$',('$repo='''+$repo.Replace("'","''")+'''').Replace('$','$$'))
$source=$source.Replace(". (Join-Path `$PSScriptRoot 'PaperPublisherCustody.ps1')",'')
$runner=[scriptblock]::Create($source)
$root=Join-Path ([IO.Path]::GetTempPath()) ('publisher-install-fixtures-'+[guid]::NewGuid().ToString('N'))
[void](New-Item -ItemType Directory -Path $root)
$preflight=Join-Path $root 'preflight.json'
$installation=Join-Path $root 'paper-publisher-install-20261127-140000-ffffffffffff.json'
@{target=@{database='marketbrain';databaseOid=42}}|ConvertTo-Json|Set-Content $installation
$installHash=(Get-FileHash $installation).Hash
$source=$source.Replace('8E0BAD905192D14F9C6E9FC90DA33451C35405E0557EB9AF9AE51545D55BAE1F',$installHash).Replace("'C:\MarketBrainData\Secrets\PaperPublisher'",("'"+$root+"'"))
$runner=[scriptblock]::Create($source)
[IO.File]::WriteAllText((Join-Path $root 'credential.lock'),'')
function Assert-PaperCustodyPath($p){return $p}
function Assert-PaperPrivateAcl($p){}
function Get-PaperPublisherEntropy($hash){return ,([byte[]]@(1,2))}
function Read-PaperCredential($p,$e){return ,(New-Object byte[] 48)}
function New-PaperCredentialVerifier($b){return 'PRIVATE_VERIFIER'}
@{version='PAPER_PUBLISHER_CUSTODY_BUNDLE_V1';status='PUBLISHER_CUSTODY_VERIFIED_DATABASE_STAGING_PENDING';custodyVerified=$true;custodyRetained=$true;acceptedInstallationSha256=$installHash}|ConvertTo-Json|Set-Content $preflight
$hash=(Get-FileHash $preflight).Hash
foreach($script:case in @('pass','verify','stopped','build','unsafe','timeout','sql','unknown','after-commit','hash')) {
    $script:calls=@();$failed=$false;$directory=Join-Path $root $script:case
    [void](New-Item -ItemType Directory -Path $directory -Force);Copy-Item $installation $directory
    $expectedHash=if($script:case -eq 'hash'){'D'*64}else{$hash}
    try{& $runner -AcceptedCustodySha256 $expectedHash -CustodyPath $preflight -OutputDirectory $directory -VerifyOnly:($script:case -eq 'verify')}catch{$failed=$true}
    Check ($failed -eq ($script:case -notin @('pass','verify'))) 'failure propagation'
    $files=@(Get-ChildItem $directory -Filter 'paper-publisher-credential-*.json');Check ($files.Count -eq 1) 'single report'
    $raw=Get-Content $files[0].FullName -Raw;$r=$raw|ConvertFrom-Json
    Check (-not $raw.Contains('LOCAL_ADMIN_SECRET') -and -not $raw.Contains('LOCAL_APP_SECRET')) 'report redaction';Check (-not $raw.Contains('PRIVATE_VERIFIER')) 'verifier redaction'
    Check (-not $r.applicationRestartRequested -and -not $r.actionExecutionEnabled) 'no activation requested'
    Check (@($script:calls|Where-Object {$_ -contains 'run'}).Count -le 1) 'no automatic retries'
    if($script:case -eq 'pass'){Check ($r.status -eq 'PUBLISHER_CREDENTIAL_VERIFIED_LOGIN_DISABLED' -and $r.catalog.disabledStateVerified -and $r.runtimeConfigurationMatched) 'successful rollback and runtime recheck'}
    if($script:case -eq 'verify'){Check (-not $r.databaseWritesRequested -and $r.commitOutcome -eq 'NOT_ATTEMPTED') 'verify-only cannot request commit'}
    if($script:case -in @('unknown','timeout')){Check ($r.commitOutcome -eq 'UNKNOWN_AFTER_ATTEMPT') 'uncertain commit retained'}
    if($script:case -eq 'after-commit'){Check ($r.commitOutcome -eq 'COMMITTED') 'known commit retained after failed readback'}
    if($script:case -eq 'sql'){Check ($r.catalog.sqlState -eq '28P01') 'sanitized SQLSTATE retained'}
    if($script:case -in @('stopped','build','hash')){Check (@($script:calls|Where-Object {$_ -contains 'run'}).Count -eq 0) 'prerequisite failure cannot reach database'}
}
Write-Host "PASS: $script:checks offline publisher credential assertions. Fixtures retained: $root"


