#Requires -Version 7.0
# Offline: hash/clipboard/owner input mocked; no VPS or private archive access.
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'PaytmMaintenanceBackup.ps1')
$script:checks=0
function Check([bool]$Value,[string]$Label){if(-not $Value){throw "FAIL: $Label"};$script:checks++}
function Reject([scriptblock]$Action){$bad=$false;try{&$Action|Out-Null}catch{$bad=$true};Check $bad "reject after $script:checks"}
$id='0123456789abcdef0123456789abcdef'
function Fixture([string]$Run){
@"
BEGIN_PAYTM_BACKUP_$Run
VERSION=1
RUN_ID=$Run
PHASE=COMPLETE
EXIT_CODE=0
DIRECTORY_CREATED=yes
ARCHIVE_VERIFIED=yes
ARCHIVE_SHA256=$('a'*64)
ARCHIVE_BYTES=20480
PACKAGE_STATE_UNCHANGED=yes
CAPTURE_COMPLETE=yes
END_PAYTM_BACKUP_$Run
"@
}
$valid=Fixture $id;$r=Read-PaytmBackupReceipt $valid $id
Check $r.archiveComparisonPassed 'complete receipt'
Check (-not $r.offHostBackupVerified -and -not $r.restoreTestPerformed -and -not $r.fullSystemRollbackProven -and -not $r.upgradeAuthorized) 'claims bounded'
Check ($r.privateDirectory -ceq "/var/backups/marketbrain-maintenance/$id") 'derived fixed path'
foreach($pair in @(@('PHASE=COMPLETE','PHASE=CAPTURE'),@('EXIT_CODE=0','EXIT_CODE=124'),@('DIRECTORY_CREATED=yes','DIRECTORY_CREATED=no'),@('ARCHIVE_VERIFIED=yes','ARCHIVE_VERIFIED=no'),@('ARCHIVE_BYTES=20480','ARCHIVE_BYTES=0'),@('PACKAGE_STATE_UNCHANGED=yes','PACKAGE_STATE_UNCHANGED=no'),@(('ARCHIVE_SHA256='+('a'*64)),'ARCHIVE_SHA256=NONE'))){Check (-not (Read-PaytmBackupReceipt $valid.Replace($pair[0],$pair[1]) $id).archiveComparisonPassed) 'failure not accepted'}
foreach($text in @($valid.Replace($id,'fedcba9876543210fedcba9876543210'),$valid.Replace('VERSION=1','VERSION=2'),$valid.Replace('VERSION=1',"VERSION=1`nVERSION=1"),$valid.Replace('VERSION=1',"VERSION=1`nSECRET=1"),$valid.Replace("VERSION=1`n",''),$valid.Replace('CAPTURE_COMPLETE=yes','CAPTURE_COMPLETE=no'),$valid.Replace('DIRECTORY_CREATED=yes','DIRECTORY_CREATED=maybe'),$valid.Replace('PHASE=COMPLETE','PHASE=UNKNOWN'),$valid.Replace(('a'*64),'BADHASH'),($valid+"`nsecret"),('x'*3001))){Reject {Read-PaytmBackupReceipt $text $id}}
Reject {New-PaytmBackupPayload 'bad' '' ''}
Reject {New-PaytmBackupPayload $id 'MB_PRIVATE_BACKUP' ''}
Reject {New-PaytmBackupPayload $id ('x'*26001) ''}
$payload=New-PaytmBackupPayload $id '# helpers' '# source'
Check ($payload.StartsWith("sudo -n timeout --kill-after=10s 600s bash <<'MB_PRIVATE_BACKUP'")) 'bounded payload'
Check ($payload.Contains("pb_main '$id'")) 'fixed run'
$global:mbBackupFixture=@{mode='';copied='';hash='51F1CC9FE4F54AC8CAF36F298F8CB26E4D0947B72F05FE7E52A500A470CB6F27'}
function Get-FileHash {param($LiteralPath,$Algorithm) [pscustomobject]@{Hash=$global:mbBackupFixture.hash}}
function Set-Clipboard {param($Value) $global:mbBackupFixture.copied=$Value}
function Read-Host {
    param($Prompt)
    if($Prompt.Contains('CONSOLE-LOGIN-OK')){if($global:mbBackupFixture.mode -eq 'console'){return 'NO'};return 'CONSOLE-LOGIN-OK'}
    if($Prompt.Contains('CREATE-PRIVATE-BACKUP')){if($global:mbBackupFixture.mode -eq 'cancel'){return 'NO'};return 'CREATE-PRIVATE-BACKUP'}
    ''
}
function Get-Clipboard {
    param([switch]$Raw)
    $run=[regex]::Match($global:mbBackupFixture.copied,"pb_main '([a-f0-9]{32})'").Groups[1].Value
    $text=Fixture $run
    switch($global:mbBackupFixture.mode){'invalid'{return 'PRIVATE_ARCHIVE_DATA_DO_NOT_SHARE'};'partial'{return $text.Replace('PHASE=COMPLETE','PHASE=CAPTURE').Replace('EXIT_CODE=0','EXIT_CODE=1').Replace('ARCHIVE_VERIFIED=yes','ARCHIVE_VERIFIED=no')};default{return $text}}
}
$temp=Join-Path ([IO.Path]::GetTempPath()) ('paytm-backup-fixture-'+[guid]::NewGuid().ToString('N'))
$null=New-Item -ItemType Directory -Path $temp
$evidence=Join-Path $temp 'evidence.json';$null=New-Item -ItemType File -Path $evidence
foreach($mode in @('clean','partial','invalid','console','cancel','hash')){
    $global:mbBackupFixture.mode=$mode;$global:mbBackupFixture.copied=''
    if($mode -eq 'hash'){$global:mbBackupFixture.hash='BAD'}
    $out=Join-Path $temp $mode;$failed=$false
    try{& (Join-Path $PSScriptRoot 'BackupPaytmMaintenance.ps1') -MaintenanceEvidencePath $evidence -OutputDirectory $out}catch{$failed=$true}
    $files=@(Get-ChildItem -LiteralPath $out -Filter '*.json');Check ($files.Count -eq 1) "one file $mode"
    $raw=Get-Content -LiteralPath $files[0].FullName -Raw;$r=$raw|ConvertFrom-Json
    Check (-not $raw.Contains('PRIVATE_ARCHIVE_DATA') -and -not $r.packagesChanged -and -not $r.ordersEnabled -and -not $r.upgradeAuthorized) "privacy/boundary $mode"
    if($mode -eq 'clean'){Check (-not $failed -and $r.backupState -ceq 'LOCAL_ARCHIVE_COMPARED') 'clean stage'}
    else{Check ($failed -and $r.status -ceq 'REVIEW_REQUIRED') "failed $mode"}
    if($mode -in @('console','cancel','hash')){Check ($global:mbBackupFixture.copied -ceq '' -and $r.backupState -ceq 'NOT_STARTED') "no payload without guards $mode"}
    if($mode -eq 'partial'){Check ($r.backupState -ceq 'PARTIAL_PRIVATE_FILES_RETAINED') 'partial retained'}
    if($mode -eq 'invalid'){Check ($r.backupState -ceq 'UNKNOWN_UNTIL_RECEIPT') 'lost receipt not assumed safe'}
}
Write-Host "PASS: $script:checks offline assertions including six launcher workflows. Fixtures retained: $temp"
