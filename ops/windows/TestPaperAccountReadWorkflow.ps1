# Offline report/HTTP orchestration tests. No Docker, API, provider, inference or database is used.
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'PaperAccountReadReview.ps1')
$script:checks=0
function Check([bool]$Condition,[string]$Name) { if(-not $Condition){throw "Assertion failed: $Name"};$script:checks++ }
function Fixture {
    return [pscustomobject]@{version='PAPER_ACCOUNT_OVERVIEW_V2';status='READ_ONLY_EXECUTION_BLOCKED';currency='INR';observedAtUtc='2026-10-09T00:00:00Z';
        account=[pscustomobject]@{id='1';name='Default Paper Portfolio';executionMode='PAPER';startingCash='100000.00';currentCash='100000.00'};
        activeAccountsObserved=1;activeAccountCountIsLowerBound=$false;legacyOrdersPresent=$false;legacyFillsPresent=$false;
        migrationAssessment='EMPTY_ACCOUNT_REVIEWABLE';blockers=@('APPLICATION_LEDGER_MIGRATION_PENDING','AUTHENTICATED_APPROVAL_AND_RISK_INTEGRATION_PENDING','FILL_COST_AND_PNL_POLICY_PENDING');
        ledger=[pscustomobject]@{status='NOT_ATTACHED';cash=$null;reservedCash=$null;unreservedCash=$null;revision=$null};
        databaseWritesPerformed=$false;actionExecutionEnabled=$false;liveExecutionEnabled=$false}
}
Assert-PaperAccountOverview (Fixture);Check $true 'valid fixture'
foreach($field in @('databaseWritesPerformed','actionExecutionEnabled','liveExecutionEnabled','activeAccountsObserved','currency','blockers')) {
    $value=Fixture
    switch($field){'activeAccountsObserved'{$value.$field=0};'currency'{$value.$field='USD'};'blockers'{$value.$field=@()};default{$value.$field=$true}}
    $failed=$false;try {Assert-PaperAccountOverview $value}catch{$failed=$true};Check $failed "mutation $field"
}
foreach($cash in @('-1.00','1.001','NaN',100000)) {
    $value=Fixture;$value.account.currentCash=$cash
    $failed=$false;try {Assert-PaperAccountOverview $value}catch{$failed=$true};Check $failed 'invalid cash'
}
$value=Fixture;$value.account=$null;$value.activeAccountsObserved=0;$value.migrationAssessment='REVIEW_REQUIRED'
Assert-PaperAccountOverview $value;Check $true 'missing account is reportable'

function git { $global:LASTEXITCODE=0; return 'offline-test-revision' }
function Read-Host { param($Prompt,[switch]$AsSecureString);return (ConvertTo-SecureString ('t'*64) -AsPlainText -Force) }
function Invoke-RestMethod { param($Uri,$TimeoutSec,$MaximumRedirection);return @{status='UP'} }
function Invoke-WebRequest {
    param($Uri,$Method,$TimeoutSec,$MaximumRedirection,[switch]$SkipHttpErrorCheck,$Headers)
    Check ($Method -ceq 'Get') 'GET only'
    Check ($MaximumRedirection -eq 0) 'redirects disabled'
    if($Uri.EndsWith('/api/v1/system/status')){return @{StatusCode=if($script:scenario -eq 'proxy') {200}else{404};Content='';Headers=@{}}}
    if($Uri.EndsWith('/')){return @{StatusCode=200;Content='<div id="root"></div>';Headers=@{}}}
    if($null -eq $Headers){return @{StatusCode=if($script:scenario -eq 'auth'){200}else{401};Content='';Headers=@{}}}
    Check ($Headers['X-MarketBrain-Paper-Read-Token'] -ceq ('t'*64)) 'expected private header'
    return @{StatusCode=200;Content=((Fixture)|ConvertTo-Json -Depth 5);Headers=@{'Cache-Control'=if($script:scenario -eq 'cache'){'public'}else{'no-store'}}}
}
$source=Get-Content -LiteralPath (Join-Path $PSScriptRoot 'DeployPaperAccountReadPhase.ps1') -Raw
# Only HTTP-mocked no-deploy orchestration runs under PS5. The actual deploy runner explicitly requires PS7.
$source=$source.Replace('#Requires -Version 7.0','# Offline mocked compatibility harness')
$source=$source.Replace('$PSScriptRoot',("'"+$PSScriptRoot.Replace("'","''")+"'"))
$runner=[scriptblock]::Create($source)
$originalToken=$env:MARKETBRAIN_PAPER_READ_TOKEN
foreach($case in @('success','auth','proxy','cache')) {
    $script:scenario=$case
    $directory=Join-Path ([IO.Path]::GetTempPath()) ('marketbrain-paper-read-test-'+[guid]::NewGuid().ToString('N'))
    $failed=$false;try {& $runner -OutputDirectory $directory}catch{$failed=$true}
    Check ($failed -eq ($case -ne 'success')) "workflow $case"
    $files=@(Get-ChildItem -LiteralPath $directory -Filter '*.json');Check ($files.Count -eq 1) 'single evidence file'
    $text=Get-Content -LiteralPath $files[0].FullName -Raw
    Check (-not $text.Contains('t'*64)) 'no token in evidence'
    $result=$text|ConvertFrom-Json
    Check ($result.status -ceq $(if($case -eq 'success'){'READ_ONLY_INTEGRATION_VERIFIED_EXECUTION_BLOCKED'}else{'STOPPED_REVIEW_REQUIRED'})) 'honest report status'
    Check ($env:MARKETBRAIN_PAPER_READ_TOKEN -eq $originalToken) 'environment restored'
}
Write-Host "PASS: $script:checks offline assertions. Docker deployment and browser rendering not executed."
