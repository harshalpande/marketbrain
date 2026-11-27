# Offline launcher tests. All process invocation and local prompts are mocked.
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'NumericalHistoryEvidence.ps1')
. (Join-Path $PSScriptRoot 'PaperWriterPreflight.ps1')
$repo=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../..'))
$script:checks=0
function Check($ok,$message){if(-not $ok){throw $message};$script:checks++}
function Assert-PaperWriterCatalog {}
function Get-Command {param($Name,$CommandType,$ErrorAction);[pscustomobject]@{Source=(Get-Process -Id $PID).Path}}
function Read-Host {param($Prompt,[switch]$AsSecureString);if($AsSecureString){return ConvertTo-SecureString 'LOCAL_ADMIN_SECRET' -AsPlainText -Force};if($Prompt -like 'Type REHEARSE*'){return 'REHEARSE'};return 'postgres'}
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
        $v=@{version='PAPER_PUBLISHER_REHEARSAL_V1';status='PUBLISHER_REHEARSAL_ROLLBACK_VERIFIED';rollbackVerified=$true;committed=$false;loginEnabled=$false;applicationWriterActivated=$false;actionExecutionEnabled=$false}
        if($script:case -eq 'unsafe'){$v.committed=$true}
        if($script:case -eq 'timeout'){$timeout=$true;$code=-999}
        if($script:case -eq 'sql'){$code=1;$v.status='STOPPED_REVIEW_REQUIRED';$v.failureType='PSQLException';$v.sqlState='28P01'}
        $out=$v|ConvertTo-Json -Compress
    }
    return [pscustomobject]@{exitCode=$code;stdout=$out;stderr='LOCAL_ADMIN_SECRET';timedOut=$timeout;elapsedSeconds=0.1}
}
$source=Get-Content (Join-Path $PSScriptRoot 'TestPaperPublisherInstallation.ps1') -Raw
$source=$source.Replace(". (Join-Path `$PSScriptRoot 'NumericalHistoryEvidence.ps1')",'').Replace(". (Join-Path `$PSScriptRoot 'PaperWriterPreflight.ps1')",'')
$source=[regex]::Replace($source,'(?m)^\$repo=.*$',('$repo='''+$repo.Replace("'","''")+'''').Replace('$','$$'))
$runner=[scriptblock]::Create($source)
$root=Join-Path ([IO.Path]::GetTempPath()) ('publisher-rehearsal-fixtures-'+[guid]::NewGuid().ToString('N'))
[void](New-Item -ItemType Directory -Path $root)
$preflight=Join-Path $root 'preflight.json'
@{version='PAPER_PUBLISHER_PREFLIGHT_BUNDLE_V1';status='CATALOG_EVIDENCE_CAPTURED_INSTALLATION_REVIEW_REQUIRED';runtimeConfigurationMatched=$true;cleanup=@{exitCode=0;timedOut=$false};catalog=@{target=@{database='marketbrain';databaseOid=42}}}|ConvertTo-Json -Depth 8|Set-Content $preflight
$hash=(Get-FileHash $preflight).Hash
foreach($script:case in @('pass','stopped','build','unsafe','timeout','sql','hash')) {
    $script:calls=@();$failed=$false;$directory=Join-Path $root $script:case
    $expectedHash=if($script:case -eq 'hash'){'D'*64}else{$hash}
    try{& $runner -AcceptedPreflightSha256 $expectedHash -PreflightPath $preflight -OutputDirectory $directory}catch{$failed=$true}
    Check ($failed -eq ($script:case -ne 'pass')) 'failure propagation'
    $files=@(Get-ChildItem $directory -Filter '*.json');Check ($files.Count -eq 1) 'single report'
    $raw=Get-Content $files[0].FullName -Raw;$r=$raw|ConvertFrom-Json
    Check (-not $raw.Contains('LOCAL_ADMIN_SECRET') -and -not $raw.Contains('LOCAL_APP_SECRET')) 'report redaction'
    Check (-not $r.applicationRestartRequested -and -not $r.actionExecutionEnabled) 'no activation requested'
    Check (@($script:calls|Where-Object {$_ -contains 'run'}).Count -le 1) 'no automatic retries'
    if($script:case -eq 'pass'){Check ($r.status -eq 'PUBLISHER_REHEARSAL_PASSED_INSTALLATION_PENDING' -and $r.catalog.rollbackVerified -and $r.runtimeConfigurationMatched) 'successful rollback and runtime recheck'}
    if($script:case -eq 'sql'){Check ($r.catalog.sqlState -eq '28P01') 'sanitized SQLSTATE retained'}
    if($script:case -in @('stopped','build','hash')){Check (@($script:calls|Where-Object {$_ -contains 'run'}).Count -eq 0) 'prerequisite failure cannot reach database'}
}
Write-Host "PASS: $script:checks offline publisher rehearsal assertions. Fixtures retained: $root"
