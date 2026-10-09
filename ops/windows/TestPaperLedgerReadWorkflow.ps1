# Offline tests only: no application, credential, Docker or database access.
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'TestPaperAccountReadWorkflow.ps1')
function Attached {
    $v=Fixture;$v.migrationAssessment='LEDGER_ATTACHED_READ_ONLY'
    $v.blockers=@('AUTHENTICATED_APPROVAL_AND_RISK_INTEGRATION_PENDING','FILL_COST_AND_PNL_POLICY_PENDING')
    $v.ledger=[pscustomobject]@{status='ATTACHED_READ_ONLY';cash='100000.00';reservedCash='0.00';unreservedCash='100000.00';revision='0'};return $v
}
function Reject([scriptblock]$Action){$failed=$false;try{& $Action}catch{$failed=$true};Check $failed 'invalid state rejected'}
Assert-PaperAccountOverview (Attached);Check $true 'valid attached view'
$v=Fixture;$v.version='PAPER_ACCOUNT_OVERVIEW_V1';$v.PSObject.Properties.Remove('ledger')
Assert-PaperAttachmentPreflight $v;Check $true 'old deployed read preflight accepted'
Reject {Assert-PaperAccountOverview $v}
foreach($field in @('cash','reservedCash','unreservedCash','revision')){$v=Attached;$v.ledger.$field='1';Reject {Assert-PaperAccountOverview $v}}
foreach($change in @(
    {param($v)$v.account.id='2'}, {param($v)$v.account.currentCash='99999.00'},
    {param($v)$v.legacyOrdersPresent=$true}, {param($v)$v.legacyFillsPresent=$true},
    {param($v)$v.account.name='other'}, {param($v)$v.blockers=@()},
    {param($v)$v.ledger.revision=0}, {param($v)$v.actionExecutionEnabled=$true}
)){$v=Attached;& $change $v;Reject {Assert-PaperAccountOverview $v}}
$v=Fixture;$v.account.currentCash='99999.00';Reject {Assert-PaperAttachmentPreflight $v}
$v=Fixture;$v.ledger.cash='0.00';Reject {Assert-PaperAccountOverview $v}

# Replace the native process function via AST extent; all deployment orchestration stays intact.
$deploySource=Get-Content -LiteralPath (Join-Path $PSScriptRoot 'DeployPaperAccountReadPhase.ps1') -Raw
$tokens=$null;$errors=$null;$ast=[Management.Automation.Language.Parser]::ParseInput($deploySource,[ref]$tokens,[ref]$errors)
if($errors.Count){throw 'Parse error'}
$fn=$ast.Find({param($a)$a -is [Management.Automation.Language.FunctionDefinitionAst] -and $a.Name -eq 'Docker'},$true)
$mockDocker=@'
function Docker([string[]]$Arguments,[int]$Limit=60) {
    $script:dockerCalls++
    Check ($Arguments[0] -ceq 'compose') 'compose only'
    if('config' -cin $Arguments){Check ('--quiet' -cin $Arguments) 'private compose check'}
    if('build' -cin $Arguments){Check ($Limit -eq 1800) 'bounded build'}
    if('up' -cin $Arguments){$script:deployed=$true;Check ('--no-deps' -cin $Arguments) 'database not recreated'}
}
'@
$deploySource=$deploySource.Substring(0,$fn.Extent.StartOffset)+$mockDocker+$deploySource.Substring($fn.Extent.EndOffset)
$deploySource=$deploySource.Replace('#Requires -Version 7.0','# Mocked PS5-compatible harness').Replace('$PSScriptRoot',("'"+$PSScriptRoot.Replace("'","''")+"'"))
$deployRunner=[scriptblock]::Create($deploySource)
function git {if($args -contains 'status'){$global:LASTEXITCODE=0;return};$global:LASTEXITCODE=0;return 'offline'}
function Get-Command {param($Name,$CommandType,$ErrorAction);if($Name -ne 'docker.exe'){throw 'Unexpected executable'};return @{Source=(Join-Path $PSHOME 'powershell.exe')}}
function Read-Host {param($Prompt,[switch]$AsSecureString)
    if($AsSecureString){return (ConvertTo-SecureString ('t'*64) -AsPlainText -Force)}
    if($Prompt -like '*BACKED_UP*'){if($script:scenario -eq 'backup'){return 'NO'};return 'BACKED_UP'}
    return 'IDLE'
}
function Invoke-WebRequest {
    param($Uri,$Method,$TimeoutSec,$MaximumRedirection,[switch]$SkipHttpErrorCheck,$Headers)
    Check ($Method -ceq 'Get') 'read-only HTTP';Check ($MaximumRedirection -eq 0) 'redirects disabled'
    if($Uri.EndsWith('/api/v1/system/status')){return @{StatusCode=404;Content='';Headers=@{}}}
    if($Uri.EndsWith('/')){return @{StatusCode=200;Content='<div id="root"></div>';Headers=@{}}}
    if($null -eq $Headers){return @{StatusCode=401;Content='';Headers=@{}}}
    Check ($Headers['X-MarketBrain-Paper-Read-Token'] -ceq ('t'*64)) 'credential collected before preflight'
    $v=if($script:deployed){Attached}else{Fixture}
    if($script:scenario -eq 'preflight'){$v.account.currentCash='90000.00'}
    if($script:scenario -eq 'after' -and $script:deployed){$v.ledger.revision='1'}
    return @{StatusCode=200;Content=($v|ConvertTo-Json -Depth 6);Headers=@{'Cache-Control'='no-store'}}
}
foreach($case in @('success','preflight','backup','after')) {
    $script:scenario=$case;$script:deployed=$false;$script:dockerCalls=0
    $dir=Join-Path ([IO.Path]::GetTempPath()) ('mb-ledger-read-'+[guid]::NewGuid().ToString('N'))
    $failed=$false;try{& $deployRunner -Deploy -AttachLedger -OutputDirectory $dir}catch{$failed=$true}
    Check ($failed -eq ($case -ne 'success')) "deploy result $case"
    if($case -in @('preflight','backup')){Check ($script:dockerCalls -eq 0) 'gate before any Docker'}
    $files=@(Get-ChildItem -LiteralPath $dir -Filter '*.json');Check ($files.Count -eq 1) 'one JSON'
    $raw=Get-Content -LiteralPath $files[0].FullName -Raw;Check (-not $raw.Contains('t'*64)) 'token redacted'
    $r=$raw|ConvertFrom-Json;Check ($r.status -ceq $(if($case -eq 'success'){'LEDGER_ATTACHED_READ_ONLY_VERIFIED_EXECUTION_BLOCKED'}else{'STOPPED_REVIEW_REQUIRED'})) 'honest evidence status'
    Check ($r.accountMutationRequested -eq $true -and $r.legacyBalanceMutationRequested -eq $false) 'migration write disclosure'
    Check ($env:MARKETBRAIN_PAPER_READ_TOKEN -eq $originalToken) 'token env restored'
}
Write-Host "PASS: $script:checks combined offline read/deploy assertions. No real Docker or PostgreSQL used."
