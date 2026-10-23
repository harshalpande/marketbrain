#Requires -Version 7.0
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'PaytmScannerPlan.ps1')
$script:count=0
function Check([bool]$Value,[string]$Name){if(-not $Value){throw "FAIL: $Name"};$script:count++}
function Reject([scriptblock]$Action){$bad=$false;try{&$Action|Out-Null}catch{$bad=$true};Check $bad 'malformed input rejected'}
function B64([string]$Value){[Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($Value))}
function Review([string]$Id,[string]$State='UNAVAILABLE',[string]$Targets='YES',[string]$Ntp='yes'){
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
NTP_SYNCHRONIZED=$Ntp
SIMULATION_EXIT=0
UPGRADE_COUNT=0
REMOVAL_COUNT=0
CANDIDATES_B64=NONE
CAPTURE_COMPLETE=yes
END_PAYTM_MAINTENANCE_$Id
"@
@"
BEGIN_PAYTM_RESTART_$Id
VERSION=1
RUN_ID=$Id
BASELINE_B64=$(B64 $base)
TARGETS_VERIFIED=$Targets
REBOOT_MARKER=ABSENT
FAILED_UNITS_EXIT=0
FAILED_UNITS_B64=NONE
NEEDRESTART_STATE=$State
NEEDRESTART_EXIT=NOT_RUN
NEEDRESTART_B64=NONE
CAPTURE_COMPLETE=yes
END_PAYTM_RESTART_$Id
"@
}
$script:actions="I|libfixture-perl|NOT_INSTALLED|1:2.3-1`nI|needrestart|NOT_INSTALLED|3.11-1`nC|libfixture-perl|NOT_APPLICABLE|1:2.3-1`nC|needrestart|NOT_APPLICABLE|3.11-1"
function Plan([string]$Id,[string]$Actions=$script:actions,[string]$Review=(Review $Id)){
@"
BEGIN_PAYTM_SCANNER_PLAN_$Id
VERSION=1
RUN_ID=$Id
REVIEW_B64=$(B64 $Review)
SIMULATION_EXIT=0
ACTIONS_STATE=CAPTURED
ACTIONS_B64=$(if($Actions){B64 $Actions}else{'NONE'})
CAPTURE_COMPLETE=yes
END_PAYTM_SCANNER_PLAN_$Id
"@
}
$id='0123456789abcdef0123456789abcdef';$valid=Plan $id
$r=Read-PaytmScannerPlan $valid $id
Check ($r.readyForManifestReview -and $r.proposedInstallCount -eq 2 -and $r.findings.Count -eq 0) 'new-only plan captured'
Check (-not $r.installationAuthorized -and -not $r.restartClearanceGranted -and -not $r.packageOriginsVerified -and -not $r.unattendedGatewayApproved) 'capture is not authorization or source verification'
foreach($test in @(
    @($valid.Replace('SIMULATION_EXIT=0','SIMULATION_EXIT=124'),'SCANNER_INSTALL_SIMULATION_FAILED'),
    @($valid.Replace('ACTIONS_STATE=CAPTURED','ACTIONS_STATE=INVALID'),'SCANNER_ACTION_CAPTURE_INCOMPLETE'),
    @($valid.Replace('ACTIONS_STATE=CAPTURED','ACTIONS_STATE=TOO_LARGE'),'SCANNER_ACTION_CAPTURE_INCOMPLETE'),
    @((Plan $id ''),'SCANNER_NEW_INSTALL_NOT_IN_PLAN'),
    @((Plan $id $actions (Review $id PRESENT)),'SCANNER_NOW_PRESENT_DO_NOT_REINSTALL'),
    @((Plan $id $actions (Review $id UNAVAILABLE NO)),'INSTALLED_TARGETS_REVIEW'),
    @((Plan $id $actions (Review $id UNAVAILABLE YES no)),'BASELINE_NTP_SYNCHRONIZED_REVIEW'),
    @((Plan $id ($actions.Replace('I|libfixture-perl|NOT_INSTALLED','I|libfixture-perl|1.0'))),'EXISTING_PACKAGE_CHANGE_REVIEW'),
    @((Plan $id ($actions+"`nR|fixture|1.0|NOT_APPLICABLE")),'PACKAGE_REMOVAL_REVIEW'),
    @((Plan $id ($actions.Replace('C|needrestart|NOT_APPLICABLE|3.11-1','C|needrestart|NOT_APPLICABLE|3.12-1'))),'INSTALL_CONFIGURE_MISMATCH'),
    @((Plan $id ($actions+"`nC|fixture|NOT_APPLICABLE|1")),'UNEXPECTED_CONFIGURATION_REVIEW')
)){$r=Read-PaytmScannerPlan $test[0] $id;Check (-not $r.readyForManifestReview -and $test[1] -cin $r.findings) $test[1]}
foreach($bad in @(
    $valid.Replace('VERSION=1','VERSION=2'),$valid.Replace('VERSION=1',"VERSION=1`nVERSION=1"),
    $valid.Replace('VERSION=1',"VERSION=1`nUNKNOWN=x"),$valid.Replace('CAPTURE_COMPLETE=yes','CAPTURE_COMPLETE=no'),
    $valid.Replace('ACTIONS_STATE=CAPTURED','ACTIONS_STATE=OTHER'),$valid.Replace('SIMULATION_EXIT=0','SIMULATION_EXIT=OTHER'),
    $valid.Replace((B64 (Review $id)),'INVALID'),$valid.Replace((B64 $actions),'INVALID'),
    (Plan $id ($actions+"`nI|needrestart|NOT_INSTALLED|3.11-1")),(Plan $id ($actions+"`nC|needrestart|NOT_APPLICABLE|3.11-1")),
    (Plan $id ($actions.Replace('C|needrestart|NOT_APPLICABLE','C|needrestart|BAD'))),
    (Plan $id ($actions+"`nR|fixture|1|BAD")),(Plan $id ($actions+"`nPRIVATE command text")),
    ($valid+"`nPRIVATE"),('x'*90001)
)){Reject {Read-PaytmScannerPlan $bad $id}}
Reject {Read-PaytmScannerPlan $valid ('f'*32)}
Reject {New-PaytmScannerPlanPayload bad 'source'}
Reject {New-PaytmScannerPlanPayload $id 'MB_SCANNER_PLAN'}
Reject {New-PaytmScannerPlanPayload $id ('a'*40001)}
$tooMany=($actions+"`n"+((1..31|ForEach-Object{"I|fixture-$_|NOT_INSTALLED|1"}) -join "`n"))
Reject {Read-PaytmScannerPlan (Plan $id $tooMany) $id}
$payload=New-PaytmScannerPlanPayload $id 'definitions only'
Check ($payload.Contains('timeout --kill-after=5s 420s') -and $payload.Contains("psp_main '$id'")) 'bounded payload'

$global:scannerFixture=@{mode='';copied='';actions=$script:actions}
function Get-FileHash {param($LiteralPath,$Algorithm) [pscustomobject]@{Hash=if($global:scannerFixture.mode -eq 'hash'){'BAD'}else{'A5439CA9AEE38BB561F6E61CDFA45899D755FD81162DAFCADE6BCEEB635D50CC'}}}
function Set-Clipboard {param($Value) $global:scannerFixture.copied=$Value}
function Read-Host {param($Prompt) if($Prompt.Contains('Type PLAN')){if($global:scannerFixture.mode -eq 'cancel'){return 'NO'};return 'PLAN'};''}
function Get-Clipboard {
    param([switch]$Raw)
    $run=[regex]::Match($global:scannerFixture.copied,"psp_main '([a-f0-9]{32})'").Groups[1].Value
    switch($global:scannerFixture.mode){'finding'{return (Plan $run $global:scannerFixture.actions).Replace('SIMULATION_EXIT=0','SIMULATION_EXIT=100')};'invalid'{return 'PRIVATE_CLIPBOARD'};default{return Plan $run $global:scannerFixture.actions}}
}
$temp=Join-Path ([IO.Path]::GetTempPath()) ('scanner-fixtures-'+[guid]::NewGuid().ToString('N'));$null=New-Item -ItemType Directory -Path $temp
$file=Join-Path $temp 'accepted.json';$null=New-Item -ItemType File -Path $file
foreach($mode in @('clean','finding','invalid','cancel','hash')){
    $global:scannerFixture.mode=$mode;$global:scannerFixture.copied='';$failed=$false;$output=Join-Path $temp $mode
    try{& (Join-Path $PSScriptRoot 'PlanPaytmRestartScanner.ps1') -RestartEvidencePath $file -OutputDirectory $output}catch{$failed=$true}
    $files=@(Get-ChildItem $output -Filter '*.json');Check ($files.Count -eq 1) 'one output'
    $raw=Get-Content $files[0].FullName -Raw;$report=$raw|ConvertFrom-Json
    Check (-not $raw.Contains('PRIVATE_CLIPBOARD') -and -not $report.servicesRestarted -and -not $report.ordersEnabled -and -not $report.packagesChanged -and -not $report.rebootPerformed -and -not $report.gatewayStarted) 'privacy and action boundaries'
    if($mode -eq 'clean'){Check (-not $failed -and $report.status -ceq 'SCANNER_PLAN_CAPTURED_INSTALL_APPROVAL_PENDING') 'clean workflow'}
    elseif($mode -eq 'finding'){Check (-not $failed -and $report.status -ceq 'SCANNER_PLAN_CAPTURED_WITH_FINDINGS') 'simulation finding captured without execution exception'}
    else{Check ($failed -and $report.status -ceq 'REVIEW_REQUIRED') 'failed capture'}
    if($mode -in @('cancel','hash')){Check (-not $report.commandCopied -and $global:scannerFixture.copied -ceq '') 'no payload without evidence and consent'}
}
Write-Host "PASS: $script:count assertions including five mocked runner workflows. Fixtures: $temp"
