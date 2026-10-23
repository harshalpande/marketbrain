#Requires -Version 7.0
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'PaytmScannerInstall.ps1')
$script:count=0
function Check([bool]$Value,[string]$Name){if(-not $Value){throw "FAIL: $Name"};$script:count++}
function Reject([scriptblock]$Action){$bad=$false;try{&$Action|Out-Null}catch{$bad=$true};Check $bad 'rejected malformed input'}
function B64([string]$Value){[Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($Value))}
function Review([string]$Id,[string]$Microcode='1'){
    $base=@"
BEGIN_PAYTM_MAINTENANCE_$Id
VERSION=1
RUN_ID=$Id
HOST_IDENTITY=MATCH
PROXY_CONFIG=MATCH
ALLOWLIST=MATCH
SERVICE_CONFIG=MATCH
SERVICE_STATE=inactive
DROPINS=NONE
RELOAD_NEEDED=no
LISTENER_COUNT=0
SSH_CONFIG_VALID=yes
DPKG_AUDIT=CLEAN
HOLD_COUNT=0
APT_FREE_KIB=8000000
APT_FREE_INODES=90000
NTP_SYNCHRONIZED=yes
SIMULATION_EXIT=0
UPGRADE_COUNT=0
REMOVAL_COUNT=0
CANDIDATES_B64=NONE
CAPTURE_COMPLETE=yes
END_PAYTM_MAINTENANCE_$Id
"@
    $nr="NEEDRESTART-VER: 3.11`nNEEDRESTART-KCUR: 6.12.95+deb13-amd64`nNEEDRESTART-KEXP: 6.12.95+deb13-amd64`nNEEDRESTART-KSTA: 1`nNEEDRESTART-UCSTA: $Microcode"
@"
BEGIN_PAYTM_RESTART_$Id
VERSION=1
RUN_ID=$Id
BASELINE_B64=$(B64 $base)
TARGETS_VERIFIED=YES
REBOOT_MARKER=ABSENT
FAILED_UNITS_EXIT=0
FAILED_UNITS_B64=NONE
NEEDRESTART_STATE=PRESENT
NEEDRESTART_EXIT=0
NEEDRESTART_B64=$(B64 $nr)
CAPTURE_COMPLETE=yes
END_PAYTM_RESTART_$Id
"@
}
function Receipt([string]$Id,[string]$Microcode='1'){
@"
BEGIN_PAYTM_SCANNER_INSTALL_$Id
VERSION=1
RUN_ID=$Id
PHASE=COMPLETE
EXIT_CODE=0
INSTALL_ATTEMPTED=yes
POSTCHECKS_PASSED=yes
ORIGINS_VERIFIED=yes
LIST_ONLY_CONFIGURED=yes
REVIEW_B64=$(B64 (Review $Id $Microcode))
FAILURE_CODE=NONE
CAPTURE_COMPLETE=yes
END_PAYTM_SCANNER_INSTALL_$Id
"@
}
$id='0123456789abcdef0123456789abcdef';$valid=Receipt $id
$r=Read-PaytmScannerInstallReceipt $valid $id
Check ($r.installationAndCaptureCompleted -and $r.installationVerified -and $r.restartReview.noKnownRestartFindings) 'completed install and screen'
Check (-not $r.restartAuthorized -and -not $r.unattendedGatewayApproved) 'no activation authority'
$r=Read-PaytmScannerInstallReceipt (Receipt $id '0') $id
Check ($r.installationAndCaptureCompleted -and -not $r.restartReview.noKnownRestartFindings -and 'MICROCODE_REVIEW_REQUIRED' -cin $r.restartReview.findings) 'unknown VM microcode remains finding'
foreach($pair in @(@('PHASE=COMPLETE','PHASE=SCAN'),@('EXIT_CODE=0','EXIT_CODE=1'),@('INSTALL_ATTEMPTED=yes','INSTALL_ATTEMPTED=no'),@('POSTCHECKS_PASSED=yes','POSTCHECKS_PASSED=no'),@('ORIGINS_VERIFIED=yes','ORIGINS_VERIFIED=no'),@('LIST_ONLY_CONFIGURED=yes','LIST_ONLY_CONFIGURED=no'),@('FAILURE_CODE=NONE','FAILURE_CODE=SCAN_FAILED'),@(('REVIEW_B64='+(B64 (Review $id))),'REVIEW_B64=NONE'))){
    $r=Read-PaytmScannerInstallReceipt ($valid.Replace($pair[0],$pair[1])) $id
    Check (-not $r.installationAndCaptureCompleted) 'incomplete state never accepted'
}
$partial=$valid.Replace('PHASE=COMPLETE','PHASE=INSTALL').Replace('EXIT_CODE=0','EXIT_CODE=1').Replace('POSTCHECKS_PASSED=yes','POSTCHECKS_PASSED=no').Replace('FAILURE_CODE=NONE','FAILURE_CODE=INSTALL_FAILED_NO_AUTO_REPAIR').Replace(('REVIEW_B64='+(B64 (Review $id))),'REVIEW_B64=NONE')
$r=Read-PaytmScannerInstallReceipt $partial $id;Check ($r.packageChangeState -ceq 'POSSIBLE_PARTIAL_CHANGES_REVIEW_REQUIRED') 'partial installation preserved'
$r=Read-PaytmScannerInstallReceipt ($partial.Replace('INSTALL_ATTEMPTED=yes','INSTALL_ATTEMPTED=no')) $id;Check ($r.packageChangeState -ceq 'INSTALL_NOT_ATTEMPTED') 'preinstall stop distinguished'
foreach($bad in @($valid.Replace('VERSION=1','VERSION=2'),$valid.Replace('VERSION=1',"VERSION=1`nVERSION=1"),$valid.Replace('VERSION=1',"VERSION=1`nUNKNOWN=x"),$valid.Replace('PHASE=COMPLETE','PHASE=OTHER'),$valid.Replace('EXIT_CODE=0','EXIT_CODE=BAD'),$valid.Replace('ORIGINS_VERIFIED=yes','ORIGINS_VERIFIED=maybe'),$valid.Replace('FAILURE_CODE=NONE','FAILURE_CODE=PRIVATE'),$valid.Replace((B64 (Review $id)),'INVALID'),$valid.Replace('CAPTURE_COMPLETE=yes','CAPTURE_COMPLETE=no'),($valid+"`nPRIVATE"),('x'*60001))){Reject {Read-PaytmScannerInstallReceipt $bad $id}}
Reject {Read-PaytmScannerInstallReceipt $valid ('f'*32)}
Reject {New-PaytmScannerInstallPayload bad 'source' Apply}
Reject {New-PaytmScannerInstallPayload $id 'MB_SCANNER_INSTALL' Apply}
Reject {New-PaytmScannerInstallPayload $id ('a'*90001) Apply}
$payload=New-PaytmScannerInstallPayload $id 'definitions' Collect
Check ($payload.Contains("si_poll '$id'") -and -not $payload.Contains('si_launch')) 'collect entrypoint cannot launch'
$payload=New-PaytmScannerInstallPayload $id 'definitions' Apply
Check ($payload.Contains("si_launch '$id'") -and -not $payload.Contains('timeout')) 'installer not killed by launcher timer'

$global:installFixture=@{mode='';copied='';installPromptSeen=$false}
function Get-FileHash {param($LiteralPath,$Algorithm) [pscustomobject]@{Hash=if($global:installFixture.mode -eq 'hash'){'BAD'}else{'545290116C8C0D6B3F852A3EE50A405B66B711A6A282BD646B59753FB8A657B2'}}}
function Set-Clipboard {param($Value) $global:installFixture.copied=$Value}
function Read-Host {param($Prompt) if($Prompt.Contains('Type INSTALL-SCANNER')){$global:installFixture.installPromptSeen=$true;if($global:installFixture.mode -eq 'cancel'){return 'NO'};return 'INSTALL-SCANNER'};''}
function Get-Clipboard {
    param([switch]$Raw)
    $run=[regex]::Match($global:installFixture.copied,"si_(?:launch|poll) '([a-f0-9]{32})'").Groups[1].Value
    switch($global:installFixture.mode){
        'finding' {return Receipt $run '0'}
        'partial' {return (Receipt $run).Replace('PHASE=COMPLETE','PHASE=INSTALL').Replace('EXIT_CODE=0','EXIT_CODE=1').Replace('POSTCHECKS_PASSED=yes','POSTCHECKS_PASSED=no').Replace('FAILURE_CODE=NONE','FAILURE_CODE=INSTALL_FAILED_NO_AUTO_REPAIR').Replace(('REVIEW_B64='+(B64 (Review $run))),'REVIEW_B64=NONE')}
        'invalid' {return 'PRIVATE_CLIPBOARD'}
        default {return Receipt $run}
    }
}
$temp=Join-Path ([IO.Path]::GetTempPath()) ('scanner-install-fixtures-'+[guid]::NewGuid().ToString('N'));$null=New-Item -ItemType Directory -Path $temp
$file=Join-Path $temp 'accepted.json';$null=New-Item -ItemType File -Path $file
foreach($mode in @('clean','finding','partial','invalid','cancel','hash','collect','badcollect')){
    $global:installFixture.mode=$mode;$global:installFixture.copied='';$global:installFixture.installPromptSeen=$false;$failed=$false;$output=Join-Path $temp $mode
    $params=@{PlanEvidencePath=$file;OutputDirectory=$output};if($mode -in @('collect','badcollect')){$params.Mode='Collect';$params.RunId=if($mode -eq 'collect'){$id}else{'bad'}}
    try{& (Join-Path $PSScriptRoot 'InstallPaytmRestartScanner.ps1') @params}catch{$failed=$true}
    $files=@(Get-ChildItem $output -Filter '*.json');Check ($files.Count -eq 1) 'one report'
    $raw=Get-Content $files[0].FullName -Raw;$report=$raw|ConvertFrom-Json
    Check (-not $raw.Contains('PRIVATE_CLIPBOARD') -and -not $report.rebootPerformed -and -not $report.ordersEnabled -and -not $report.gatewayActivationAuthorized) 'privacy and action boundaries'
    if($mode -in @('clean','collect')){Check (-not $failed -and $report.status -ceq 'SCANNER_INSTALLED_SCREEN_CLEAR_UNATTENDED_PENDING') 'completed workflow'}
    elseif($mode -eq 'finding'){Check (-not $failed -and $report.status -ceq 'SCANNER_INSTALLED_RESTART_FINDINGS_REVIEW_REQUIRED') 'findings do not report failed install'}
    else{Check ($failed -and $report.status -ceq 'REVIEW_REQUIRED') 'failure retained'}
    if($mode -eq 'partial'){Check ($report.packageChangeState -ceq 'POSSIBLE_PARTIAL_CHANGES_REVIEW_REQUIRED') 'partial state not erased'}
    if($mode -in @('cancel','hash','badcollect')){Check (-not $report.commandCopied -and -not $global:installFixture.copied) 'no payload on rejected precondition'}
    if($mode -eq 'collect'){Check (-not $global:installFixture.installPromptSeen -and -not $report.ownerInstallConfirmed -and $global:installFixture.copied.EndsWith("si_poll '$id'`nMB_SCANNER_INSTALL`n")) 'collect prompts and entrypoint stay read-only'}
}
Write-Host "PASS: $script:count assertions including eight mocked runner workflows. Fixtures: $temp"
