#Requires -Version 7.0
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'PaytmMaintenanceUpdate.ps1')
$script:checks=0
function Check([bool]$Value,[string]$Label){if(-not $Value){throw "FAIL: $Label"};$script:checks++}
function Reject([scriptblock]$Action){$bad=$false;try{&$Action|Out-Null}catch{$bad=$true};Check $bad "reject after $script:checks"}
$id='0123456789abcdef0123456789abcdef'
function Fixture([string]$Run){
@"
BEGIN_PAYTM_UPDATE_$Run
VERSION=1
RUN_ID=$Run
PHASE=COMPLETE
EXIT_CODE=0
INSTALL_ATTEMPTED=yes
POSTCHECKS_PASSED=yes
REBOOT_MARKER=ABSENT
FAILURE_CODE=NONE
CAPTURE_COMPLETE=yes
END_PAYTM_UPDATE_$Run
"@
}
$valid=Fixture $id;$r=Read-PaytmUpdateReceipt $valid $id
Check ($r.updatePostchecksPassed -and -not $r.rebootPerformed -and -not $r.brokerReady) 'bounded pass'
Check (-not (Read-PaytmUpdateReceipt $valid.Replace('FAILURE_CODE=NONE','FAILURE_CODE=POSTCHECK') $id).updatePostchecksPassed) 'failure code prevents acceptance'
Reject {Read-PaytmUpdateReceipt $valid.Replace('FAILURE_CODE=NONE','FAILURE_CODE=UNEXPECTED_PRIVATE_TEXT') $id}
foreach($pair in @(@('PHASE=COMPLETE','PHASE=INSTALL'),@('EXIT_CODE=0','EXIT_CODE=100'),@('INSTALL_ATTEMPTED=yes','INSTALL_ATTEMPTED=no'),@('POSTCHECKS_PASSED=yes','POSTCHECKS_PASSED=no'),@('REBOOT_MARKER=ABSENT','REBOOT_MARKER=UNKNOWN'))){Check (-not (Read-PaytmUpdateReceipt $valid.Replace($pair[0],$pair[1]) $id).updatePostchecksPassed) 'failure not accepted'}
foreach($text in @($valid.Replace($id,'fedcba9876543210fedcba9876543210'),$valid.Replace('VERSION=1','VERSION=2'),$valid.Replace('VERSION=1',"VERSION=1`nVERSION=1"),$valid.Replace('VERSION=1',"VERSION=1`nSECRET=1"),$valid.Replace("VERSION=1`n",''),$valid.Replace('INSTALL_ATTEMPTED=yes','INSTALL_ATTEMPTED=maybe'),($valid+"`nprivate"),('x'*2001))){Reject {Read-PaytmUpdateReceipt $text $id}}
Reject {New-PaytmUpdatePayload 'bad' '' Apply}
Reject {New-PaytmUpdatePayload $id 'MB_REVIEWED_UPDATE' Apply}
$apply=New-PaytmUpdatePayload $id '# source' Apply;$collect=New-PaytmUpdatePayload $id '# source' Collect
Check ($apply.Contains("mu_launch '$id'")) 'apply entry'
Check ($collect.Contains("mu_poll '$id'") -and -not $collect.Contains('mu_launch')) 'collect never launches'
$global:mbUpdateFixture=@{mode='';copied='';hash='DA176C0DA7B3890C7FE41CF249CFE804EDA2BE7109905472FE03E6CB8E5B5CBE'}
function Get-FileHash {
    param($LiteralPath,$Algorithm)
    $hash=$global:mbUpdateFixture.hash
    if($LiteralPath.EndsWith('plan.json')){$hash=if($global:mbUpdateFixture.mode -eq 'planhash'){'BAD'}else{'5791623DAC303E150B4BF15AD27442DBAEA03584CDD54B097544D36416C4FB43'}}
    if($LiteralPath.EndsWith('failure.json')){$hash=if($global:mbUpdateFixture.mode -eq 'failurehash'){'BAD'}else{'84C8828053A8F9C2256E750313A72E91CE97E7F413C5F177B209ECE7DAC1FB45'}}
    [pscustomobject]@{Hash=$hash}
}
function Set-Clipboard {param($Value) $global:mbUpdateFixture.copied=$Value}
function Read-Host {
    param($Prompt)
    if($Prompt.Contains('UPDATE-REVIEWED-PACKAGES')){if($global:mbUpdateFixture.mode -eq 'cancel'){return 'NO'};return 'UPDATE-REVIEWED-PACKAGES'}
    if($Prompt.Contains('FRESH-LOGIN-OK')){if($global:mbUpdateFixture.mode -eq 'login'){return 'NO'};return 'FRESH-LOGIN-OK'}
    ''
}
function Get-Clipboard {
    param([switch]$Raw)
    $run=[regex]::Match($global:mbUpdateFixture.copied,"mu_(?:launch|poll) '([a-f0-9]{32})'").Groups[1].Value
    $text=Fixture $run
    switch($global:mbUpdateFixture.mode){'invalid'{return 'PRIVATE_LOG_DO_NOT_SHARE'};'partial'{return $text.Replace('PHASE=COMPLETE','PHASE=INSTALL').Replace('EXIT_CODE=0','EXIT_CODE=100').Replace('POSTCHECKS_PASSED=yes','POSTCHECKS_PASSED=no')};default{return $text}}
}
$temp=Join-Path ([IO.Path]::GetTempPath()) ('paytm-update-fixture-'+[guid]::NewGuid().ToString('N'))
$null=New-Item -ItemType Directory -Path $temp
$evidence=Join-Path $temp 'evidence.json';$null=New-Item -ItemType File -Path $evidence
$planPath=Join-Path $temp 'plan.json';$null=New-Item -ItemType File -Path $planPath
$failurePath=Join-Path $temp 'failure.json';$null=New-Item -ItemType File -Path $failurePath
foreach($mode in @('clean','partial','invalid','cancel','login','collect','missing','planhash','failurehash','hash')){
    $global:mbUpdateFixture.mode=$mode;$global:mbUpdateFixture.copied=''
    if($mode -eq 'hash'){$global:mbUpdateFixture.hash='BAD'}
    $out=Join-Path $temp $mode;$failed=$false;$params=@{BackupEvidencePath=$evidence;OutputDirectory=$out}
    if($mode -notin @('missing','collect')){$params.PlanEvidencePath=$planPath;$params.FailureEvidencePath=$failurePath}
    if($mode -eq 'collect'){$params.Mode='Collect';$params.RunId=$id}
    try{& (Join-Path $PSScriptRoot 'UpdatePaytmMaintenance.ps1') @params}catch{$failed=$true}
    $files=@(Get-ChildItem -LiteralPath $out -Filter '*.json');Check ($files.Count -eq 1) "one file $mode"
    $raw=Get-Content -LiteralPath $files[0].FullName -Raw;$r=$raw|ConvertFrom-Json
    Check (-not $raw.Contains('PRIVATE_LOG') -and -not $r.rebootPerformed -and -not $r.ordersEnabled) "privacy/boundary $mode"
    if($mode -in @('clean','collect')){Check (-not $failed -and $r.status -ceq 'REVIEWED_UPDATES_VERIFIED_RESTART_REVIEW_PENDING') "complete $mode"}
    elseif($mode -eq 'login'){Check (-not $failed -and $r.status -ceq 'UPDATES_POSTCHECKED_FRESH_LOGIN_PENDING') 'login not inferred'}
    else{Check ($failed -and $r.status -ceq 'REVIEW_REQUIRED') "failed $mode"}
    if($mode -in @('cancel','hash','missing','planhash','failurehash')){Check ($global:mbUpdateFixture.copied -ceq '' -and $r.packageChangeState -ceq 'NOT_STARTED') "no payload $mode"}
    if($mode -eq 'partial'){Check ($r.packageChangeState -ceq 'POSSIBLE_PARTIAL_CHANGES_REVIEW_REQUIRED') 'partial retained'}
    if($mode -eq 'invalid'){Check ($r.packageChangeState -ceq 'UNKNOWN_UNTIL_RECEIPT') 'lost receipt not false safety'}
    if($mode -eq 'collect'){Check (-not $r.ownerUpdateConfirmed -and $global:mbUpdateFixture.copied.EndsWith("mu_poll '$id'`nMB_REVIEWED_UPDATE`n")) 'collect no install approval'}
}
Write-Host "PASS: $script:checks assertions including ten mocked workflows. Fixtures: $temp"
