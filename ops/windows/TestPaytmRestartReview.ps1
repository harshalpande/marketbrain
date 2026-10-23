#Requires -Version 7.0
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'PaytmRestartReview.ps1')
$script:count=0
function Check([bool]$Value,[string]$Name){if(-not $Value){throw "FAIL: $Name"};$script:count++}
function Reject([scriptblock]$Action){$bad=$false;try{&$Action|Out-Null}catch{$bad=$true};Check $bad 'malformed input rejected'}
function B64([string]$Value){[Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($Value))}
function Base([string]$Id){
@"
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
}
$nr="NEEDRESTART-VER: 3.11`nNEEDRESTART-KCUR: 6.12.95+deb13-amd64`nNEEDRESTART-KEXP: 6.12.95+deb13-amd64`nNEEDRESTART-KSTA: 1`nNEEDRESTART-UCSTA: 1"
function Fixture([string]$Id){
@"
BEGIN_PAYTM_RESTART_$Id
VERSION=1
RUN_ID=$Id
BASELINE_B64=$(B64 (Base $Id))
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
$id='0123456789abcdef0123456789abcdef';$valid=Fixture $id
$r=Read-PaytmRestartReceipt $valid $id
Check ($r.noKnownRestartFindings -and -not $r.restartAuthorized -and -not $r.unattendedGatewayApproved) 'clear is not authorization'
foreach($pair in @(@('TARGETS_VERIFIED=YES','TARGETS_VERIFIED=NO'),@('REBOOT_MARKER=ABSENT','REBOOT_MARKER=PRESENT'),@('FAILED_UNITS_EXIT=0','FAILED_UNITS_EXIT=124'),@('FAILED_UNITS_B64=NONE','FAILED_UNITS_B64=TOO_LARGE'),@('NEEDRESTART_STATE=PRESENT','NEEDRESTART_STATE=UNAVAILABLE'),@('NEEDRESTART_EXIT=0','NEEDRESTART_EXIT=124'),@(('NEEDRESTART_B64='+(B64 $nr)),'NEEDRESTART_B64=NONE'))){Check (-not (Read-PaytmRestartReceipt $valid.Replace($pair[0],$pair[1]) $id).noKnownRestartFindings) 'incomplete finding'}
foreach($data in @($nr.Replace('KSTA: 1','KSTA: 0'),$nr.Replace('KSTA: 1','KSTA: 2'),$nr.Replace('KSTA: 1','KSTA: 3'),$nr.Replace('UCSTA: 1','UCSTA: 0'),$nr.Replace('UCSTA: 1','UCSTA: 2'),($nr+"`nNEEDRESTART-SVC: ssh.service"),($nr+"`nNEEDRESTART-SESS: REDACTED"),($nr+"`nNEEDRESTART-CONT: REDACTED"),($nr+"`nUNRECOGNIZED_OUTPUT"),'NEEDRESTART-VER: 3.11')){
    Check (-not (Read-PaytmRestartReceipt $valid.Replace((B64 $nr),(B64 $data)) $id).noKnownRestartFindings) 'scanner finding'
}
$old='marketbrain-maintenance-7fb461f8bff74ee0bb15a5afed8c49bc.service'
$r=Read-PaytmRestartReceipt $valid.Replace('FAILED_UNITS_B64=NONE',('FAILED_UNITS_B64='+(B64 $old))) $id
Check ($r.noKnownRestartFindings -and $r.historicalFailedUnitObserved) 'known historic failure remains visible'
Check (-not (Read-PaytmRestartReceipt $valid.Replace('FAILED_UNITS_B64=NONE',('FAILED_UNITS_B64='+(B64 ($old+"`nssh.service")))) $id).noKnownRestartFindings) 'other failure not exempt'
$badBase=(Base $id).Replace('NTP_SYNCHRONIZED=yes','NTP_SYNCHRONIZED=no')
Check (-not (Read-PaytmRestartReceipt $valid.Replace((B64 (Base $id)),(B64 $badBase)) $id).noKnownRestartFindings) 'baseline propagated'
foreach($text in @($valid.Replace($id,'fedcba9876543210fedcba9876543210'),$valid.Replace('VERSION=1','VERSION=2'),$valid.Replace('VERSION=1',"VERSION=1`nVERSION=1"),$valid.Replace('VERSION=1',"VERSION=1`nUNKNOWN=1"),$valid.Replace("VERSION=1`n",''),($valid+"`nPRIVATE"),$valid.Replace((B64 $nr),'='),$valid.Replace((B64 $nr),(B64 ($nr+"`nNEEDRESTART-KSTA: 1"))),$valid.Replace((B64 $nr),(B64 ($nr+"`nNEEDRESTART-SESS: PRIVATE"))),('x'*120001))){Reject {Read-PaytmRestartReceipt $text $id}}
Reject {New-PaytmRestartPayload 'bad' ''};Reject {New-PaytmRestartPayload $id 'MB_RESTART_REVIEW'}
Check ((New-PaytmRestartPayload $id '# fixture').Contains('timeout --kill-after=5s 300s bash')) 'bounded observation'
$global:restartFixture=@{mode='';copied=''}
function Get-FileHash {param($LiteralPath,$Algorithm) [pscustomobject]@{Hash=if($global:restartFixture.mode -eq 'hash'){'BAD'}else{'146AF6DC88625F881981900DB571A1BCEDA3BCFAB67FB4470A13F4850A120EF5'}}}
function Set-Clipboard {param($Value) $global:restartFixture.copied=$Value}
function Read-Host {param($Prompt) if($Prompt.Contains('Type REVIEW')){if($global:restartFixture.mode -eq 'cancel'){return 'NO'};return 'REVIEW'};''}
function Get-Clipboard {
    param([switch]$Raw)
    $run=[regex]::Match($global:restartFixture.copied,"pr_main '([a-f0-9]{32})'").Groups[1].Value
    $text=Fixture $run
    switch($global:restartFixture.mode){'missing'{return $text.Replace('NEEDRESTART_STATE=PRESENT','NEEDRESTART_STATE=UNAVAILABLE').Replace('NEEDRESTART_EXIT=0','NEEDRESTART_EXIT=NOT_RUN').Replace((B64 $nr),'NONE')};'invalid'{return 'PRIVATE_CLIPBOARD'};default{return $text}}
}
$temp=Join-Path ([IO.Path]::GetTempPath()) ('restart-fixtures-'+[guid]::NewGuid().ToString('N'));$null=New-Item -ItemType Directory -Path $temp
$file=Join-Path $temp 'accepted.json';$null=New-Item -ItemType File -Path $file
foreach($mode in @('clean','missing','invalid','cancel','hash')){
    $global:restartFixture.mode=$mode;$global:restartFixture.copied='';$failed=$false;$output=Join-Path $temp $mode
    try{& (Join-Path $PSScriptRoot 'ReviewPaytmRestart.ps1') -UpdateEvidencePath $file -OutputDirectory $output}catch{$failed=$true}
    $files=@(Get-ChildItem $output -Filter '*.json');Check ($files.Count -eq 1) 'one output'
    $raw=Get-Content $files[0].FullName -Raw;$report=$raw|ConvertFrom-Json
    Check (-not $raw.Contains('PRIVATE_CLIPBOARD') -and -not $report.servicesRestarted -and -not $report.ordersEnabled -and -not $report.packagesChanged -and -not $report.rebootPerformed) 'privacy and action boundaries'
    if($mode -eq 'clean'){Check (-not $failed -and $report.status -ceq 'RESTART_SCREEN_NO_KNOWN_FINDINGS_UNATTENDED_PENDING') 'clean workflow'}
    elseif($mode -eq 'missing'){Check (-not $failed -and $report.status -ceq 'RESTART_REVIEW_CAPTURED_WITH_FINDINGS') 'missing scanner is not clear or execution exception'}
    else{Check ($failed -and $report.status -ceq 'REVIEW_REQUIRED') 'failed capture'}
    if($mode -in @('cancel','hash')){Check (-not $report.commandCopied -and $global:restartFixture.copied -ceq '') 'no payload without evidence and consent'}
}
Write-Host "PASS: $script:count assertions including five mocked runner workflows. Fixtures: $temp"
