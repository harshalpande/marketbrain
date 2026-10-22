#Requires -Version 7.0
# Offline only. No actual resync, Windows service changes or VPS/APT execution.
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'PaytmOperationsReview.ps1')
. (Join-Path $PSScriptRoot 'PaytmOperationsFollowUp.ps1')
$global:mbFollowupFixture=@{admin=$true;state='Running';startType='Manual';syncExit=0;calls=@();mode='pass';copied='';timeCalls=0}
$checks=0
function Check([bool]$Value,[string]$Label){if(-not $Value){throw "FAIL: $Label"};$script:checks++}
function Reject([scriptblock]$Action,[string]$Label){$failed=$false;try{&$Action|Out-Null}catch{$failed=$true};Check $failed $Label}
function Test-PaytmOperationsAdministrator {$global:mbFollowupFixture.admin}
function Get-Service {
    param($Name,$ErrorAction)
    $s=[pscustomobject]@{Status=$global:mbFollowupFixture.state;StartType=$global:mbFollowupFixture.startType}
    $s|Add-Member -MemberType ScriptMethod -Name WaitForStatus -Value {param($status,$timeout)}
    $s
}
function Invoke-PaperRuntimeProcess {
    param($Executable,$Arguments,$Directory,$LimitSeconds)
    $global:mbFollowupFixture.calls+=($Arguments -join ' ')
    if($global:mbFollowupFixture.mode -eq 'timeout'){throw 'RUNTIME_PROCESS_TIMEOUT'}
    $code=if($Arguments[0] -eq '/resync'){$global:mbFollowupFixture.syncExit}else{0}
    @{exitCode=$code;stdout='Synthetic time status';stderr='';elapsedSeconds=0.01}
}
$r=Invoke-PaytmWindowsTimeReview
Check ($r.resyncCommandSucceeded -and $r.commands.Count -eq 4 -and -not $r.clockAccuracyProven -and -not $r.vpsTimeChanged) 'resync is not accuracy proof'
Check (($global:mbFollowupFixture.calls -join ' ') -notmatch '/config|Set-Date') 'no peer or manual time rewrite'
$global:mbFollowupFixture.state='Stopped';$r=Invoke-PaytmWindowsTimeReview
Check ($r.serviceStartAttempted -and $r.commands.Count -eq 5) 'stopped service starts with bounded native command'
$global:mbFollowupFixture.startType='Disabled';$r=Invoke-PaytmWindowsTimeReview
Check (-not $r.resyncAttempted -and -not $r.serviceStartAttempted -and $r.failure -eq 'OPS_WINDOWS_TIME_DISABLED_REVIEW_POLICY') 'disabled policy preserved'
$global:mbFollowupFixture.startType='Manual';$global:mbFollowupFixture.state='Running';$global:mbFollowupFixture.syncExit=5
$r=Invoke-PaytmWindowsTimeReview
Check (-not $r.resyncCommandSucceeded -and $r.commands.Count -eq 4 -and $r.failure) 'failed resync retains after queries'
$global:mbFollowupFixture.mode='timeout';$r=Invoke-PaytmWindowsTimeReview
Check ($r.commands[0].failure -eq 'TIME_COMMAND_TIMEOUT' -and -not $r.resyncCommandSucceeded) 'bounded command timeout captured'
$global:mbFollowupFixture.mode='pass';$global:mbFollowupFixture.admin=$false;$r=Invoke-PaytmWindowsTimeReview
Check ($r.commands.Count -eq 0 -and $r.failure -eq 'OPS_ADMIN_POWERSHELL_REQUIRED') 'admin before changes'
$global:mbFollowupFixture.admin=$true;$global:mbFollowupFixture.syncExit=0
function Receipt([string]$Id,[DateTimeOffset]$Now){
    $encoded=[Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes("tinyproxy-bin|1.11.2-1|1.11.2-2`n"))
@"
BEGIN_PAYTM_OPERATIONS_$Id
VERSION=2
RUN_ID=$Id
HOST_IDENTITY=MATCH
UTC_EPOCH=$($Now.ToUnixTimeSeconds())
PROXY_CONFIG=MATCH
ALLOWLIST=MATCH
SERVICE_CONFIG=MATCH
SERVICE_STATE=inactive
DROPINS=NONE
RELOAD_NEEDED=no
LISTENER_COUNT=0
WATCHDOG_UNIT_COUNT=0
VPS_BOUND_PUBLIC_IPV4=130.250.191.137
NTP_SYNCHRONIZED=yes
KERNEL=6.12.95+deb13-amd64
SSH_VERSION=1:10.0p1-7+deb13u4
PROXY_VERSION=1.11.2-1
APT_OLDEST_RELEASE_EPOCH=$($Now.AddDays(-40).ToUnixTimeSeconds())
CACHED_UPGRADE_COUNT=1
REBOOT_MARKER=ABSENT
APT_UPDATE_EXIT=0
APT_UPDATE_SECONDS=5
APT_SIMULATION_EXIT=0
UPGRADE_CANDIDATES_B64=$encoded
CAPTURE_COMPLETE=yes
END_PAYTM_OPERATIONS_$Id
"@
}
$id='0123456789abcdef0123456789abcdef';$now=[DateTimeOffset]::UtcNow;$valid=Receipt $id $now
function Parse([string]$Text){Read-PaytmOperationsReceipt $Text $id $now.AddSeconds(-10) $now.AddSeconds(10) -ExpectedVersion 2}
$r=Parse $valid
Check ($r.packageIndexesRefreshed -and $r.findings -notcontains 'APT_CACHE_DATE_REVIEW') 'refresh success beats old Release mtime heuristic'
Check ($r.upgradeCandidates.Count -eq 1 -and $r.upgradeCandidates[0].package -eq 'tinyproxy-bin') 'safe upgrade list'
Check ($r.findings -contains 'CACHED_UPGRADES_PRESENT' -and -not $r.fullyPatchedProven) 'upgrades remain review findings'
$empty=[regex]::Replace($valid.Replace('CACHED_UPGRADE_COUNT=1','CACHED_UPGRADE_COUNT=0'),'(?m)^UPGRADE_CANDIDATES_B64=.*$','UPGRADE_CANDIDATES_B64=NONE')
Check ((Parse $empty).findings.Count -eq 0) 'empty successful simulation'
$r=Parse $valid.Replace('APT_UPDATE_EXIT=0','APT_UPDATE_EXIT=100')
Check (-not $r.packageIndexesRefreshed -and $r.findings -contains 'APT_REFRESH_FAILED_CANDIDATES_MAY_BE_STALE') 'partial refresh cannot pass'
Reject {Parse $valid.Replace('CACHED_UPGRADE_COUNT=1','CACHED_UPGRADE_COUNT=2')} 'count mismatch'
Reject {Parse $valid.Replace('APT_UPDATE_EXIT=0','APT_UPDATE_EXIT=UNKNOWN')} 'unknown exit not zero'
Reject {Parse $valid.Replace('VERSION=2','VERSION=1')} 'wrong receipt version'
$encoded=[Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes('SECRET_BAD_ROW'))
Reject {Parse ([regex]::Replace($valid,'(?m)^UPGRADE_CANDIDATES_B64=.*$',"UPGRADE_CANDIDATES_B64=$encoded"))} 'malicious upgrade row rejected'
$payload=New-PaytmOperationsPayload $id '# fixture' -RefreshReviewed
Check ($payload.Contains('timeout --kill-after=10s 420s') -and $payload.Contains("po_main '$id' refresh-reviewed")) 'refresh requires explicit payload mode'

# Exercise the unchanged runner body with only imports replaced by these fixture dependencies.
$body=[IO.File]::ReadAllText((Join-Path $PSScriptRoot 'ReviewPaytmOperationsFollowUp.ps1'))
foreach($library in @('PaytmOperationsReview.ps1','PaytmOperationsFollowUp.ps1')){
    $import='. (Join-Path $PSScriptRoot '''+$library+''')'
    Check ($body.Contains($import)) 'expected dependency import'
    $body=$body.Replace($import,'# fixture dependencies already loaded')
}
$body=$body.Replace('$PSScriptRoot',("'"+$PSScriptRoot.Replace("'","''")+"'"))
$runner=[scriptblock]::Create($body)
function Assert-PaytmReviewedOperationsReport {param($Path) if($global:mbFollowupFixture.mode -eq 'hash'){throw 'OPS_PRIOR_REPORT_HASH_MISMATCH'};@{runId='fixture';sha256='fixture'}}
function Invoke-PaytmWindowsTimeReview {
    $global:mbFollowupFixture.timeCalls++
    [pscustomobject]@{status='FIXTURE';failure=$(if($global:mbFollowupFixture.mode -eq 'timefail'){'OPS_WINDOWS_RESYNC_OR_STATUS_FAILED'}else{$null})}
}
function Get-PaytmWindowsSshInventory {@{fixture=$true}}
function Read-Host {param($Prompt) if($Prompt -like '*SYNC_AND_REFRESH*'){if($global:mbFollowupFixture.mode -eq 'cancel'){'NO'}else{'SYNC_AND_REFRESH'}}else{''}}
function Set-Clipboard {param($Value) $global:mbFollowupFixture.copied=$Value}
function Get-Clipboard {
    param([switch]$Raw)
    if($global:mbFollowupFixture.mode -eq 'invalid'){return 'PRIVATE_CLIPBOARD_DO_NOT_LOG'}
    $m=[regex]::Match($global:mbFollowupFixture.copied,"po_main '([a-f0-9]{32})'")
    $text=Receipt $m.Groups[1].Value ([DateTimeOffset]::UtcNow)
    if($global:mbFollowupFixture.mode -eq 'refreshfail'){$text=$text.Replace('APT_UPDATE_EXIT=0','APT_UPDATE_EXIT=100')}
    if($global:mbFollowupFixture.mode -eq 'clean'){$text=[regex]::Replace($text.Replace('CACHED_UPGRADE_COUNT=1','CACHED_UPGRADE_COUNT=0'),'(?m)^UPGRADE_CANDIDATES_B64=.*$','UPGRADE_CANDIDATES_B64=NONE')}
    $text
}
$temp=Join-Path ([IO.Path]::GetTempPath()) ('paytm-followup-fixtures-'+[guid]::NewGuid().ToString('N'))
foreach($mode in @('pass','clean','timefail','refreshfail','cancel','notadmin','hash','invalid')){
    $global:mbFollowupFixture.mode=$mode;$global:mbFollowupFixture.admin=($mode -ne 'notadmin');$global:mbFollowupFixture.timeCalls=0
    $folder=Join-Path $temp $mode;$failed=$false
    try{& $runner -OperationsEvidencePath 'fixture' -OutputDirectory $folder}catch{$failed=$true}
    $files=@(Get-ChildItem -LiteralPath $folder -Filter '*.json');Check ($files.Count -eq 1) "one report $mode"
    $raw=Get-Content -LiteralPath $files[0].FullName -Raw;$r=$raw|ConvertFrom-Json
    Check (-not $raw.Contains('PRIVATE_CLIPBOARD') -and -not $r.vpsTimeChanged -and -not $r.ordersEnabled -and -not $r.packageInstallationRequested) "boundaries $mode"
    if($mode -in @('cancel','notadmin','hash')){Check ($failed -and $global:mbFollowupFixture.timeCalls -eq 0 -and -not $r.vpsRefreshCommandPrepared) "no mutations before consent/prerequisites $mode"}
    elseif($mode -eq 'invalid'){Check ($failed -and $r.failure -eq 'OPS_CURRENT_RUN_BLOCK_REQUIRED') 'invalid clipboard fails safely'}
    elseif($mode -eq 'clean'){Check (-not $failed -and $r.status -eq 'FOLLOWUP_CAPTURED_UNATTENDED_PROVISIONING_PENDING') 'no findings does not activate unattended mode'}
    else{Check (-not $failed -and $r.status -eq 'FOLLOWUP_CAPTURED_WITH_FINDINGS') "capture findings $mode"}
    if($mode -eq 'timefail'){Check ($r.observations.findings -contains 'WINDOWS_TIME_REVIEW_REQUIRED') 'Windows failure does not lose VPS results'}
}
Write-Host "PASS: $checks assertions, including eight mocked follow-up workflows. No real clock/package/service changes. Fixtures: $temp"
