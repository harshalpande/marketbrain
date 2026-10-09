# Offline HTTP/native/key provisioning mocks. Never accesses the actual key directory or Docker.
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'TestPaperLedgerReadWorkflow.ps1')
$start=$script:checks
$source=Get-Content (Join-Path $PSScriptRoot 'DeployPaperApprovalStorage.ps1') -Raw
$tokens=$null;$errors=$null;$ast=[Management.Automation.Language.Parser]::ParseInput($source,[ref]$tokens,[ref]$errors)
Check ($errors.Count -eq 0) 'new runner parses'
$fn=$ast.Find({param($a)$a -is [Management.Automation.Language.FunctionDefinitionAst] -and $a.Name -eq 'Docker'},$true)
$source=$source.Substring(0,$fn.Extent.StartOffset)+$mockDocker+$source.Substring($fn.Extent.EndOffset)
$source=$source.Replace('#Requires -Version 7.0','# Offline mocked harness').Replace('$PSScriptRoot',("'"+$PSScriptRoot.Replace("'","''")+"'"))
$source=$source.Replace('Initialize-PaperStorageKey -Create:$CreateKey','Mock-Key -Create:$CreateKey')
$source=$source.Replace("& (Join-Path '"+$PSScriptRoot.Replace("'","''")+"' 'TestPaperPersistenceBundle.ps1')",'Mock-Isolated')
$runner=[scriptblock]::Create($source)
function Mock-Key {param([switch]$Create);$script:keyCalls++;return 'C:\fixture-only\key'}
function Mock-Isolated {param([switch]$ApprovalStorage,$BuildTimeoutSeconds,$OutputDirectory);$script:isolatedCalls++;[void](New-Item -ItemType Directory -Path $OutputDirectory -Force);$r=@{status=if($script:scenario -eq 'isolated'){'FAILED'}else{'ISOLATED_STORAGE_PASSED_APPLICATION_DEPLOYMENT_PENDING'}};Save-NumericalHistoryReport $r (Join-Path $OutputDirectory 'paper-storage-fixture.json') -Compact;if($script:scenario -eq 'isolated'){throw 'Fixture preflight failure'}}
function Read-Host {param($Prompt,[switch]$AsSecureString)
    if($AsSecureString){return ConvertTo-SecureString ('t'*64) -AsPlainText -Force}
    if($Prompt -like '*KEY_BACKED_UP*'){if($script:scenario -eq 'keybackup'){return 'NO'};return 'KEY_BACKED_UP'}
    if($Prompt -like '*BACKED_UP*'){if($script:scenario -eq 'backup'){return 'NO'};return 'BACKED_UP'}
    return 'IDLE'
}
function Invoke-WebRequest {
    param($Uri,$Method,$TimeoutSec,$MaximumRedirection,[switch]$SkipHttpErrorCheck,$Headers)
    Check ($Method -ceq 'Get' -and $MaximumRedirection -eq 0) 'bounded read-only HTTP'
    if($Uri.EndsWith('/api/v1/system/status')){return @{StatusCode=404;Content='';Headers=@{}}}
    if($Uri.EndsWith('/')){return @{StatusCode=200;Content='<div id="root"></div>';Headers=@{}}}
    if($Uri.EndsWith('/api/v1/paper/approval/storage')){
        if(-not $script:deployed){return @{StatusCode=404;Content='';Headers=@{}}}
        if($null -eq $Headers){return @{StatusCode=401;Content='';Headers=@{}}}
        $v=@{version='PAPER_APPROVAL_STORAGE_V1';status=if($script:scenario -eq 'blocked'){'STORAGE_SETUP_BLOCKED'}else{'STORAGE_KEY_VERIFIED_ACTIONS_DISABLED'};databaseWritesPerformed=$false;notificationEnabled=$false;actionExecutionEnabled=$false;liveExecutionEnabled=$false}
        return @{StatusCode=200;Content=($v|ConvertTo-Json);Headers=@{'Cache-Control'='no-store'}}
    }
    if($null -eq $Headers){return @{StatusCode=401;Content='';Headers=@{}}}
    $v=Attached;if($script:scenario -eq 'preflight'){$v.account.currentCash='90000.00'}
    return @{StatusCode=200;Content=($v|ConvertTo-Json -Depth 6);Headers=@{'Cache-Control'='no-store'}}
}
foreach($case in @('success','preflight','backup','isolated','keybackup','blocked')){
    $script:scenario=$case;$script:deployed=$false;$script:dockerCalls=0;$script:keyCalls=0;$script:isolatedCalls=0
    $dir=Join-Path ([IO.Path]::GetTempPath()) ('mb-storage-deploy-'+[guid]::NewGuid().ToString('N'))
    $failed=$false;try{& $runner -Deploy -CreateKey -OutputDirectory $dir}catch{$failed=$true}
    Check ($failed -eq ($case -ne 'success')) "storage deploy $case"
    if($case -in @('preflight','backup','isolated','keybackup')){Check ($script:dockerCalls -eq 0) 'no app build before gates'}
    if($case -in @('preflight','backup','isolated')){Check ($script:keyCalls -eq 0) 'no key before gates'}
    $files=@(Get-ChildItem -LiteralPath $dir -Filter 'paper-storage-application-*.json');Check ($files.Count -eq 1) 'one shareable report'
    $raw=Get-Content $files[0].FullName -Raw;Check (-not $raw.Contains('t'*64)) 'no read secret'
    $r=$raw|ConvertFrom-Json;Check ($r.status -ceq $(if($case -eq 'success'){'APPLICATION_APPROVAL_STORAGE_VERIFIED_ACTIONS_DISABLED'}else{'STOPPED_REVIEW_REQUIRED'})) 'honest storage status'
    Check ($env:MARKETBRAIN_PAPER_READ_TOKEN -eq $originalToken) 'read token restored'
}
Write-Host "PASS: $script:checks offline assertions; $($script:checks-$start) new storage deploy assertions. No real keys, API or Docker used."
