#Requires -Version 7.0
# Offline fixtures only: no SSH, package command or clipboard access.
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'PaytmMaintenanceReview.ps1')
$script:count=0
function Check([bool]$Condition,[string]$Name){if(-not $Condition){throw "FAIL: $Name"};$script:count++}
function Reject([scriptblock]$Action){$bad=$false;try{&$Action|Out-Null}catch{$bad=$true};Check $bad "rejected malformed input after $script:count assertions: $Action"}
$id='0123456789abcdef0123456789abcdef'
function Fixture([string]$RunId){
    $b64=[Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes("libc6|2.41-1|2.41-2`n"))
@"
BEGIN_PAYTM_MAINTENANCE_$RunId
VERSION=1
RUN_ID=$RunId
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
UPGRADE_COUNT=1
REMOVAL_COUNT=0
CANDIDATES_B64=$b64
CAPTURE_COMPLETE=yes
END_PAYTM_MAINTENANCE_$RunId
"@
}
$valid=Fixture $id
$r=Read-PaytmMaintenanceReceipt $valid $id
Check ($r.technicalPreflightPassed -and $r.packages.Count -eq 1) 'clean plan'
Check (-not $r.upgradeAuthorized -and -not $r.backupVerified -and -not $r.recoveryVerified -and -not $r.indexesRefreshed -and -not $r.diskRequirementCalculated) 'no overclaim'
foreach($pair in @(@('HOST_IDENTITY=MATCH','HOST_IDENTITY=MISMATCH'),@('PROXY_CONFIG=MATCH','PROXY_CONFIG=MISMATCH'),@('ALLOWLIST=MATCH','ALLOWLIST=UNKNOWN'),@('SERVICE_CONFIG=MATCH','SERVICE_CONFIG=MISMATCH'),@('SERVICE_STATE=inactive','SERVICE_STATE=active'),@('DROPINS=NONE','DROPINS=PRESENT'),@('RELOAD_NEEDED=no','RELOAD_NEEDED=yes'),@('LISTENER_COUNT=0','LISTENER_COUNT=1'),@('SSH_CONFIG_VALID=yes','SSH_CONFIG_VALID=no'),@('DPKG_AUDIT=CLEAN','DPKG_AUDIT=FINDINGS'),@('DPKG_AUDIT=CLEAN','DPKG_AUDIT=UNKNOWN'),@('HOLD_COUNT=0','HOLD_COUNT=1'),@('APT_FREE_KIB=8000000','APT_FREE_KIB=1'),@('APT_FREE_KIB=8000000','APT_FREE_KIB=UNKNOWN'),@('APT_FREE_INODES=90000','APT_FREE_INODES=1'),@('NTP_SYNCHRONIZED=yes','NTP_SYNCHRONIZED=no'),@('SIMULATION_EXIT=0','SIMULATION_EXIT=124'),@('REMOVAL_COUNT=0','REMOVAL_COUNT=1'))){
    Check (-not (Read-PaytmMaintenanceReceipt $valid.Replace($pair[0],$pair[1]) $id).technicalPreflightPassed) $pair[1]
}
foreach($bad in @($valid.Replace($id,'fedcba9876543210fedcba9876543210'),$valid.Replace('VERSION=1','VERSION=2'),$valid.Replace('VERSION=1',"VERSION=1`nVERSION=1"),$valid.Replace('VERSION=1',"VERSION=1`nEXTRA=yes"),$valid.Replace("VERSION=1`n",''),$valid.Replace('UPGRADE_COUNT=1','UPGRADE_COUNT=2'),$valid.Replace('CAPTURE_COMPLETE=yes','CAPTURE_COMPLETE=no'),($valid+"`nPRIVATE_CLIPBOARD"),('X'*40001))){Reject {Read-PaytmMaintenanceReceipt $bad $id}}
$b64=[regex]::Match($valid,'CANDIDATES_B64=(.+)').Groups[1].Value
foreach($data in @('malformed',("libc6|1|2`nlibc6|1|2"),(("libc6|1|2`n")*201))){
    $encoded=[Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($data))
    Reject {Read-PaytmMaintenanceReceipt $valid.Replace($b64,$encoded) $id}
}
Reject {Read-PaytmMaintenanceReceipt $valid.Replace($b64,'=') $id}
Reject {New-PaytmMaintenancePayload 'bad' 'a' 'b'}
Reject {New-PaytmMaintenancePayload $id 'MB_MAINTENANCE_PLAN' 'b'}
$payload=New-PaytmMaintenancePayload $id '# helpers' '# source'
Check ($payload.StartsWith("sudo -n timeout --kill-after=5s 240s bash <<'MB_MAINTENANCE_PLAN'")) 'outer timeout'
Check ($payload.Contains("pm_main '$id'")) 'only maintenance entrypoint called'
$global:mbMaintenanceFixture=@{copied='';mode=''}
function Set-Clipboard {param($Value) $global:mbMaintenanceFixture.copied=$Value}
function Read-Host {param($Prompt) if($Prompt.Contains('Type PLAN')){if($global:mbMaintenanceFixture.mode -eq 'cancel'){'NO'}else{'PLAN'}}else{''}}
function Get-Clipboard {
    param([switch]$Raw)
    $run=[regex]::Match($global:mbMaintenanceFixture.copied,"pm_main '([a-f0-9]{32})'").Groups[1].Value
    $text=Fixture $run
    switch($global:mbMaintenanceFixture.mode){'invalid'{return 'PRIVATE_CLIPBOARD_DO_NOT_SHARE'};'finding'{return $text.Replace('HOLD_COUNT=0','HOLD_COUNT=1')};default{return $text}}
}
$temp=Join-Path ([IO.Path]::GetTempPath()) ('paytm-maintenance-tests-'+[guid]::NewGuid().ToString('N'))
foreach($mode in @('clean','finding','invalid','cancel')){
    $global:mbMaintenanceFixture.mode=$mode;$out=Join-Path $temp $mode;$failed=$false
    try{& (Join-Path $PSScriptRoot 'ReviewPaytmMaintenance.ps1') -OutputDirectory $out}catch{$failed=$true}
    $files=@(Get-ChildItem -LiteralPath $out -Filter '*.json')
    Check ($files.Count -eq 1) "one report $mode"
    $raw=Get-Content -LiteralPath $files[0].FullName -Raw;$r=$raw|ConvertFrom-Json
    Check (-not $raw.Contains('PRIVATE_CLIPBOARD') -and -not $r.packagesChanged -and -not $r.ordersEnabled -and -not $r.gatewayStarted -and -not $r.backupCreated) "safe report $mode"
    if($mode -in @('invalid','cancel')){Check ($failed -and $r.status -eq 'REVIEW_REQUIRED') "failure recorded $mode"}
    elseif($mode -eq 'finding'){Check (-not $failed -and $r.status -eq 'MAINTENANCE_PLAN_CAPTURED_WITH_FINDINGS') 'finding not lost'}
    else{Check (-not $failed -and $r.status -eq 'MAINTENANCE_PLAN_CAPTURED_BACKUP_AND_APPLY_PENDING') 'plan not approval'}
}
Write-Host "PASS: $script:count assertions including four mocked launcher workflows. Fixtures retained: $temp"
