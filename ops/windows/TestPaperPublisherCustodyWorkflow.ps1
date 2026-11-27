# Offline launcher checks. Production credential helper is replaced; no production secrets accessed.
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'PaperPublisherCustody.ps1')
. (Join-Path $PSScriptRoot 'NumericalHistoryEvidence.ps1')
$repo=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../..'));$script:checks=0
function Check($ok,$why){if(-not $ok){throw $why};$script:checks++}
function Initialize-PaperPublisherCustody($Directory,$InstallationHash){$script:calls++;Check ($Directory -ceq 'C:\MarketBrainData\Secrets\PaperPublisher') 'separate publisher path';Check ($InstallationHash -ceq $script:hash) 'installation-bound entropy';if($script:case -eq 'custody-failure'){throw 'PRIVATE_SENTINEL'};return @{custodyCreated=$true;custodyVerified=$true;custodyRetained=$true}}
function Invoke-PaperCatalogProcess($Executable,[string[]]$Arguments,$WorkingDirectory,$LimitSeconds){Check ($Executable -ceq 'git') 'no Docker/database invocation';return @{exitCode=0;stdout=$(if($Arguments -contains 'rev-parse'){'a'*40}elseif($script:case -eq 'dirty'){'modified'}else{''})}}
$source=Get-Content (Join-Path $PSScriptRoot 'InitializePaperPublisherCredential.ps1') -Raw
foreach($f in @('PaperPublisherCustody.ps1','NumericalHistoryEvidence.ps1','PaperWriterPreflight.ps1')){$source=$source.Replace(". (Join-Path `$PSScriptRoot '$f')",'')}
$source=[regex]::Replace($source,'(?m)^\$repo=.*$',('$repo='''+$repo.Replace("'","''")+'''').Replace('$','$$'))
$runner=[scriptblock]::Create($source)
$root=Join-Path ([IO.Path]::GetTempPath()) ('publisher-custody-workflow-'+[guid]::NewGuid().ToString('N'));[void](New-Item -ItemType Directory -Path $root)
foreach($script:case in @('pass','hash','login-enabled','unverified','dirty','custody-failure')) {
    $script:calls=0;$v=@{version='PAPER_PUBLISHER_INSTALL_BUNDLE_V1';status='PUBLISHER_DISABLED_VERIFIED_CREDENTIALS_PENDING';commitOutcome='COMMITTED';verifyOnly=$false;runtimeConfigurationMatched=$true;cleanup=@{exitCode=0;timedOut=$false};catalog=@{disabledStateVerified=$true;loginEnabled=$false;actionExecutionEnabled=$false}}
    if($script:case -eq 'login-enabled'){$v.catalog.loginEnabled=$true};if($script:case -eq 'unverified'){$v.catalog.disabledStateVerified=$false}
    $file=Join-Path $root ($script:case+'.json');$v|ConvertTo-Json -Depth 8|Set-Content $file;$script:hash=(Get-FileHash $file).Hash
    $expected=if($script:case -eq 'hash'){'B'*64}else{$script:hash};$dir=Join-Path $root $script:case;$failed=$false
    try{& $runner -InstallationPath $file -AcceptedInstallationSha256 $expected -OutputDirectory $dir}catch{$failed=$true}
    Check ($failed -eq ($script:case -ne 'pass')) 'failure propagated'
    $files=@(Get-ChildItem $dir -Filter '*.json');Check ($files.Count -eq 1) 'one report'
    $raw=Get-Content $files[0].FullName -Raw;$r=$raw|ConvertFrom-Json
    Check (-not $raw.Contains('PRIVATE_SENTINEL')) 'no raw error leakage'
    Check (-not $r.databaseContacted -and -not $r.databaseWritesRequested -and -not $r.actionExecutionEnabled) 'local-only scope'
    if($script:case -eq 'pass'){Check ($r.custodyVerified -and $r.custodyRetained -and $r.status -eq 'PUBLISHER_CUSTODY_VERIFIED_DATABASE_STAGING_PENDING') 'custody success'}
    if($script:case -in @('hash','login-enabled','unverified','dirty')){Check ($script:calls -eq 0) 'blocked evidence does not reach custody'}
    if($script:case -eq 'custody-failure'){Check ($null -eq $r.custodyCreated -and $null -eq $r.custodyRetained -and $r.failureCode -eq 'LOCAL_CUSTODY_FAILED') 'uncertain custody state not invented'}
}
Write-Host "PASS: $script:checks mocked custody launcher assertions. Fixtures: $root"
