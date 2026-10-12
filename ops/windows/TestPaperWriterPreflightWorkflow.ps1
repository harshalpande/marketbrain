# Offline only. Native processes are replaced in memory; no Docker, database or application started.
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'NumericalHistoryEvidence.ps1')
. (Join-Path $PSScriptRoot 'PaperWriterPreflight.ps1')
$script:assertions=0
function Check($Condition,[string]$Message){if(-not $Condition){throw $Message};$script:assertions++}
function Reject([scriptblock]$Body,[string]$Message){$rejected=$false;try{& $Body}catch{$rejected=$true};Check $rejected $Message}
function Sample {
    $names=@('paper_approval_proposal','paper_approval_token','telegram_binding','paper_portfolio','paper_ledger_account','paper_ledger_command','paper_ledger_position','instrument','paper_approval_delivery','paper_approval_key_binding','paper_ledger_order','paper_ledger_fill')
    @{version='PAPER_WRITER_PREFLIGHT_V1';status='CATALOG_REVIEW_COMPLETE_APPLICATION_ACTIVATION_BLOCKED';scope='CONFIGURED_DATABASE_CATALOG_ONLY_NOT_RUNTIME_IDENTITY_OR_INSTALLATION_PROOF';connectionAttempted=$true;applicationDatabaseWritesPerformed=$false;applicationWriterActivated=$false;actionExecutionEnabled=$false;providerCalls=0;telegramCalls=0;modelCalls=0;session=@{readOnly=$true;repeatableRead=$true;unchangedSessionIdentity=$true};schema=@{schemaName='public'};tables=@($names|ForEach-Object {@{tableName=$_;present=$true;rowSecurity=$false;forceRowSecurity=$false;currentRoleOwnerMembership=$true;currentRoleSelect=$true;publicSelect=$false;publicWrite=$false}});proposedRoleCollisions=@();writerFunctionCollisions=@();publicCreateSchemas=@();publicCallableDefiners=@();installationBlockers=@('PUBLIC_TEMP_REQUIRES_IMPACT_REVIEW');catalogListBoundReached=$false;elapsedSeconds=0.3}|ConvertTo-Json -Depth 8|ConvertFrom-Json
}
Assert-PaperWriterCatalog (Sample) 'public';Check $true 'valid catalog accepted with findings, not treated as activation'
foreach($field in @('applicationDatabaseWritesPerformed','applicationWriterActivated','actionExecutionEnabled')){$v=Sample;$v.$field=$true;Reject {Assert-PaperWriterCatalog $v 'public'} $field;$v.$field='false';Reject {Assert-PaperWriterCatalog $v 'public'} 'string Boolean rejected'}
foreach($field in @('providerCalls','telegramCalls','modelCalls')){$v=Sample;$v.$field=1;Reject {Assert-PaperWriterCatalog $v 'public'} 'side effect rejected';$v.$field='0';Reject {Assert-PaperWriterCatalog $v 'public'} 'string counter rejected'}
foreach($field in @('readOnly','repeatableRead','unchangedSessionIdentity')){$v=Sample;$v.session.$field=$false;Reject {Assert-PaperWriterCatalog $v 'public'} 'session guard'}
foreach($mutation in @({param($v)$v.tables=@($v.tables|Select-Object -Skip 1)},{param($v)$v.tables[0].tableName=$v.tables[1].tableName},{param($v)$v.tables[0].publicWrite='false'},{param($v)$v.schema.schemaName='other'},{param($v)$v.elapsedSeconds=-1},{param($v)$v.elapsedSeconds=[double]::NaN},{param($v)$v.catalogListBoundReached=$true},{param($v)$v.version='wrong'},{param($v)$v.connectionAttempted=$false},{param($v)$v.PSObject.Properties.Remove('installationBlockers')})){$v=Sample;& $mutation $v;Reject {Assert-PaperWriterCatalog $v 'public'} 'bad catalog rejected'}
$source=Get-Content (Join-Path $PSScriptRoot 'GetPaperWriterPreflight.ps1') -Raw
$repo=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..'))
$mocked=$source.Replace('#Requires -Version 7.0','').Replace(". (Join-Path `$PSScriptRoot 'NumericalHistoryEvidence.ps1')",'').Replace(". (Join-Path `$PSScriptRoot 'PaperWriterPreflight.ps1')",'')
$mocked=[regex]::Replace($mocked,'(?m)^\$repo=.*$',('$repo='''+$repo.Replace("'","''")+'''').Replace('$','$$'))
$runner=[scriptblock]::Create($mocked)
$testRoot=Join-Path ([IO.Path]::GetTempPath()) ('paper-preflight-offline-'+[guid]::NewGuid().ToString('N'))
[void](New-Item -ItemType Directory -Path $testRoot)
$script:nativeCalls=@();$script:failStage='';$script:invalidReport=$false
function Invoke-PaperCatalogProcess([string]$Executable,[string[]]$Arguments,[string]$WorkingDirectory,[int]$LimitSeconds) {
    $script:nativeCalls+=,@($Arguments)
    $out='';$exitCode=0;$timeout=$false
    if($Arguments -contains 'rev-parse'){$out='a'*40}
    elseif($Arguments -contains 'run') {
        $v=Sample;if($script:invalidReport){$v.applicationWriterActivated=$true}
        $out=$v|ConvertTo-Json -Depth 8 -Compress
        if($script:failStage -ceq 'run'){$out='{"version":"PAPER_WRITER_PREFLIGHT_V1","status":"STOPPED_REVIEW_REQUIRED","failureType":"SQLException","sqlState":"08001"}';$exitCode=1}
        if($script:failStage -ceq 'timeout'){$timeout=$true;$exitCode=-999}
    }
    if(($script:failStage -ceq 'build' -and $Arguments -contains 'build') -or ($script:failStage -ceq 'cleanup' -and $Arguments -contains 'down')){$exitCode=1}
    return [pscustomobject]@{stdout=$out;stderr='SECRET_TOKEN_DO_NOT_SERIALIZE';exitCode=$exitCode;timedOut=$timeout;elapsedSeconds=0.1}
}
function Get-Command {param($Name,$CommandType,$ErrorAction);[pscustomobject]@{Source=(Get-Process -Id $PID).Path}}
function Test-Path {param($LiteralPath,$PathType);if($LiteralPath -eq (Join-Path $repo '.env')){return $true};if($PathType){Microsoft.PowerShell.Management\Test-Path -LiteralPath $LiteralPath -PathType $PathType}else{Microsoft.PowerShell.Management\Test-Path -LiteralPath $LiteralPath}}
foreach($case in @('pass','build','run','timeout','cleanup','invalid')) {
    $script:nativeCalls=@();$script:failStage=$case;$script:invalidReport=($case -ceq 'invalid')
    $dir=Join-Path $testRoot $case
    if($case -ceq 'pass'){& $runner -OutputDirectory $dir}else{Reject {& $runner -OutputDirectory $dir} 'runner failure propagated'}
    $files=@(Get-ChildItem -LiteralPath $dir -Filter '*.json');Check ($files.Count -eq 1) 'one compact report'
    $raw=Get-Content -LiteralPath $files[0].FullName -Raw;$r=$raw|ConvertFrom-Json
    Check (-not $raw.Contains('SECRET_TOKEN_DO_NOT_SERIALIZE')) 'native secret output not embedded'
    Check (-not $r.applicationRestartRequested -and -not $r.databaseWritesRequested -and -not $r.actionExecutionEnabled) 'guarded request'
    if($case -ceq 'pass'){Check ($r.status -ceq 'CATALOG_EVIDENCE_CAPTURED_INSTALLATION_REVIEW_REQUIRED') 'success retains installation gate';Check (@($r.catalog.installationBlockers).Count -eq 1) 'findings retained'}
    else{Check ($r.status -like 'STOPPED*') 'failure not success'}
    $runs=@($script:nativeCalls|Where-Object {$_ -contains 'run'});Check ($runs.Count -le 1) 'no inference or inspection loop'
    if($case -ceq 'build'){Check ($runs.Count -eq 0) 'failed build never reads database'}
    else{Check (@($script:nativeCalls|Where-Object {$_ -contains 'down'}).Count -eq 1) 'only owned inspector cleanup'}
    foreach($call in $script:nativeCalls|Where-Object {$_ -contains 'compose'}) {
        Check (-not ($call -contains 'up') -and -not ($call -contains 'restart') -and -not ($call -contains 'prune')) 'no application restart or global cleanup'
        Check (($call -join ' ') -match 'compose.paper-writer-preflight.yaml') 'standalone compose only'
    }
}
$tokens=$null;$errors=$null
[void][Management.Automation.Language.Parser]::ParseInput($source,[ref]$tokens,[ref]$errors)
Check ($errors.Count -eq 0) 'runner syntax parses'
Write-Host "PASS: $script:assertions offline assertions. No native processes, database or application used. Fixtures: $testRoot"
