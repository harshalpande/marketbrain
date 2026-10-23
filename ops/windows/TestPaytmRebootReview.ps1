#Requires -Version 7.0
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'PaytmRebootReview.ps1')
$script:count=0
function Check([bool]$Value,[string]$Name){if(-not $Value){throw "FAIL: $Name"};$script:count++}
function Reject([scriptblock]$Action){$bad=$false;try{&$Action|Out-Null}catch{$bad=$true};Check $bad 'rejected invalid evidence'}
function B64([string]$Value){[Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($Value))}
function Fixture([string]$Id,[string]$Phase='BEFORE',[string]$Scenario='clean'){
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
    if($Scenario -eq 'baseline'){$base=$base.Replace('DPKG_AUDIT=CLEAN','DPKG_AUDIT=UNKNOWN')}
    $nr="NEEDRESTART-VER: 3.11`nNEEDRESTART-KCUR: 6.12.95+deb13-amd64`nNEEDRESTART-KEXP: 6.12.95+deb13-amd64`nNEEDRESTART-KSTA: 1"
    if($Scenario -eq 'ucode'){$nr+="`nNEEDRESTART-UCSTA: 0"}
    if($Scenario -eq 'kernel'){$nr=$nr.Replace('KSTA: 1','KSTA: 2')}
    if($Scenario -eq 'unknown'){$nr+="`nUNRECOGNIZED_OUTPUT"}
    if($Scenario -eq 'container'){$nr+="`nNEEDRESTART-CONT: REDACTED"}
    if($Scenario -eq 'service'){$nr+="`nNEEDRESTART-SVC: other.service"}
    if($Phase -eq 'BEFORE' -or $Scenario -eq 'stale'){$nr+="`nNEEDRESTART-SVC: ssh.service`nNEEDRESTART-SESS: REDACTED"}
    $review=@"
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
    $boot=if($Phase -eq 'BEFORE' -or $Scenario -eq 'sameboot'){'11111111-1111-1111-1111-111111111111'}else{'22222222-2222-2222-2222-222222222222'}
    $epoch=if($Phase -eq 'BEFORE' -or $Scenario -eq 'time'){'1792750000'}else{'1792750300'}
@"
BEGIN_PAYTM_REBOOT_$Id
VERSION=1
RUN_ID=$Id
PHASE=$Phase
BOOT_ID=$boot
UTC_EPOCH=$epoch
VM=kvm
CONTAINER=none
SCANNER_PACKAGES=YES
BACKUP_READABLE=YES
JOBS_IDLE=YES
GATEWAY_DISABLED=YES
CORE_SERVICES_ACTIVE=YES
REVIEW_B64=$(B64 $review)
CAPTURE_COMPLETE=yes
END_PAYTM_REBOOT_$Id
"@
}
$id='0123456789abcdef0123456789abcdef';$valid=Fixture $id
$r=Read-PaytmRebootReceipt $valid $id BEFORE
Check ($r.checksPassed -and $r.microcodeAssessment -ceq 'NOT_ASSESSED_IN_VM_PROVIDER_MANAGED') 'VM skip explicit, not microcode pass'
Check ($r.restartReview.findings -contains 'MICROCODE_REVIEW_REQUIRED') 'raw scanner finding preserved'
Check (-not $r.gatewayActivationAuthorized -and -not $r.ordersEnabled) 'authority unchanged'
foreach($scenario in @('baseline','ucode','kernel','unknown','container','service')){Check (-not (Read-PaytmRebootReceipt (Fixture $id BEFORE $scenario) $id BEFORE).checksPassed) 'unreviewed condition blocks'}
foreach($pair in @(@('VM=kvm','VM=UNKNOWN'),@('VM=kvm','VM=none'),@('CONTAINER=none','CONTAINER=docker'),@('CONTAINER=none','CONTAINER=UNKNOWN'),@('SCANNER_PACKAGES=YES','SCANNER_PACKAGES=NO'),@('BACKUP_READABLE=YES','BACKUP_READABLE=NO'),@('JOBS_IDLE=YES','JOBS_IDLE=NO'),@('GATEWAY_DISABLED=YES','GATEWAY_DISABLED=NO'))){Check (-not (Read-PaytmRebootReceipt $valid.Replace($pair[0],$pair[1]) $id BEFORE).checksPassed) 'guard failure blocks'}
Check ((Read-PaytmRebootReceipt (Fixture $id AFTER) $id AFTER).checksPassed) 'post boot guest screen'
Check (-not (Read-PaytmRebootReceipt (Fixture $id AFTER stale) $id AFTER).checksPassed) 'post boot stale services and sessions block'
Check (-not (Read-PaytmRebootReceipt $valid.Replace('CORE_SERVICES_ACTIVE=YES','CORE_SERVICES_ACTIVE=NO') $id BEFORE).checksPassed) 'core service inactive blocks'
foreach($bad in @($valid.Replace('VERSION=1','VERSION=2'),$valid.Replace('VERSION=1',"VERSION=1`nVERSION=1"),$valid.Replace('VERSION=1',"VERSION=1`nEXTRA=1"),$valid.Replace('CAPTURE_COMPLETE=yes','CAPTURE_COMPLETE=no'),$valid.Replace($id,'f'*32),($valid+"`nPRIVATE"),$valid.Replace('BOOT_ID=11111111-1111-1111-1111-111111111111','BOOT_ID=bad'),('x'*65001))){Reject {Read-PaytmRebootReceipt $bad $id BEFORE}}
Reject {Read-PaytmRebootReceipt $valid $id AFTER}
Reject {New-PaytmRebootPayload 'bad' '' BEFORE}
Reject {New-PaytmRebootPayload $id 'MB_REBOOT_REVIEW' BEFORE}
Reject {New-PaytmRebootPayload $id '' REBOOT 'bad' '1792750000'}
foreach($phase in @('BEFORE','AFTER')){Check ((New-PaytmRebootPayload $id '# fixture' $phase).EndsWith("rb_observe '$id' '$phase'`nMB_REBOOT_REVIEW`n")) 'observation entry cannot reboot'}
$global:rbFixture=@{scenario='';copied='';rebootCopies=0;observations=0;output=''}
function Get-FileHash {param($LiteralPath,$Algorithm) [pscustomobject]@{Hash=if($global:rbFixture.scenario -eq 'hash'){'BAD'}else{'507BD7B7C94C24EA4ACE9A1258BE41106BE79468FC1FC7F5645D92DCF905ECA2'}}}
function Set-Clipboard {
    param($Value)
    $global:rbFixture.copied=$Value
    if($Value.Contains("`nrb_reboot '")){
        $global:rbFixture.rebootCopies++
        Check (@(Get-ChildItem -LiteralPath $global:rbFixture.output -Filter '*.json').Count -eq 1) 'checkpoint on disk BEFORE reboot payload copied'
    }else{$global:rbFixture.observations++}
}
function Read-Host {
    param($Prompt)
    if($Prompt.Contains('Type CONSOLE-READY')){if($global:rbFixture.scenario -eq 'console'){return 'NO'};return 'CONSOLE-READY'}
    if($Prompt.Contains('type REBOOT-VPS')){if($global:rbFixture.scenario -eq 'cancel'){return 'NO'};return 'REBOOT-VPS'}
    ''
}
function Get-Clipboard {
    param([switch]$Raw)
    if($global:rbFixture.scenario -eq 'invalid'){return 'PRIVATE_CLIPBOARD'}
    $match=[regex]::Match($global:rbFixture.copied,"rb_observe '([a-f0-9]{32})' '(BEFORE|AFTER)'")
    Fixture $match.Groups[1].Value $match.Groups[2].Value $global:rbFixture.scenario
}
$temp=Join-Path ([IO.Path]::GetTempPath()) ('reboot-fixtures-'+[guid]::NewGuid().ToString('N'));$null=New-Item -ItemType Directory -Path $temp
$anchor=Join-Path $temp 'anchor.json';$null=New-Item -ItemType File -Path $anchor
$checkpointPath=$null
foreach($scenario in @('clean','baseline','service','invalid','console','cancel','hash')){
    $global:rbFixture.scenario=$scenario;$global:rbFixture.copied='';$global:rbFixture.rebootCopies=0;$global:rbFixture.observations=0
    $output=Join-Path $temp $scenario;$global:rbFixture.output=$output;$failed=$false
    try{$result=& (Join-Path $PSScriptRoot 'CompletePaytmMaintenance.ps1') -Mode Before -ScannerEvidencePath $anchor -OutputDirectory $output}catch{$failed=$true}
    $files=@(Get-ChildItem $output -Filter '*.json');Check ($files.Count -eq 1) 'one checkpoint or failure report'
    $raw=Get-Content $files[0].FullName -Raw;$report=$raw|ConvertFrom-Json
    Check (-not $raw.Contains('PRIVATE_CLIPBOARD') -and -not $report.bootChangeObserved -and -not $report.ordersEnabled -and -not $report.gatewayActivationAuthorized) 'privacy and no reboot inference'
    if($scenario -eq 'clean'){
        Check (-not $failed -and $report.status -ceq 'REBOOT_COMMAND_PREPARED_POSTCHECK_PENDING' -and $global:rbFixture.rebootCopies -eq 1) 'confirmed reboot command only'
        $checkpointPath=$files[0].FullName
    }else{Check ($failed -and $global:rbFixture.rebootCopies -eq 0) 'no reboot payload on error or cancellation'}
    if($scenario -in @('console','hash')){Check ($global:rbFixture.observations -eq 0) 'no command before prerequisites'}
}
foreach($scenario in @('clean','sameboot','time','stale','ucode','invalid')){
    $global:rbFixture.scenario=$scenario;$global:rbFixture.rebootCopies=0
    $output=Join-Path $temp ('after-'+$scenario);$global:rbFixture.output=$output;$failed=$false
    try{& (Join-Path $PSScriptRoot 'CompletePaytmMaintenance.ps1') -Mode After -BeforeEvidencePath $checkpointPath -OutputDirectory $output|Out-Null}catch{$failed=$true}
    $files=@(Get-ChildItem $output -Filter '*.json');Check ($files.Count -eq 1) 'one after report'
    $report=Get-Content $files[0].FullName -Raw|ConvertFrom-Json
    Check ($global:rbFixture.rebootCopies -eq 0 -and -not $report.gatewayActivationAuthorized -and -not $report.ordersEnabled) 'after never reboots or enables'
    if($scenario -eq 'clean'){Check (-not $failed -and $report.bootChangeObserved -and $report.status -ceq 'VPS_REBOOT_VERIFIED_GUEST_SCREEN_CLEAR_UNATTENDED_PENDING') 'boot change and guest screen'}
    else{Check ($failed -and $report.failure) 'postboot findings preserved'}
}
Reject {Read-PaytmRebootCheckpoint (Join-Path $temp 'cancel\missing.json')}
Write-Host "PASS: $script:count assertions; thirteen mocked Before/After workflows. No VPS commands executed. Fixtures: $temp"
