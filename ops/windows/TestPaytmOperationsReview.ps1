#Requires -Version 7.0
# Offline fixtures: clipboard, owner input and file hash are mocked. No VPS/network calls.
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'PaytmOperationsReview.ps1')
$script:count=0
function Check([bool]$Condition,[string]$Label){if(-not $Condition){throw "FAIL: $Label"};$script:count++}
function Reject([scriptblock]$Action,[string]$Label){$bad=$false;try{&$Action|Out-Null}catch{$bad=$true};Check $bad $Label}
$id='0123456789abcdef0123456789abcdef';$now=[DateTimeOffset]::UtcNow
function Fixture([string]$Id,[DateTimeOffset]$Time) {
@"
BEGIN_PAYTM_OPERATIONS_$Id
VERSION=1
RUN_ID=$Id
HOST_IDENTITY=MATCH
UTC_EPOCH=$($Time.ToUnixTimeSeconds())
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
SSH_VERSION=1:10.0p1-7
PROXY_VERSION=1.11.2-1
APT_OLDEST_RELEASE_EPOCH=$($Time.AddDays(-1).ToUnixTimeSeconds())
CACHED_UPGRADE_COUNT=0
REBOOT_MARKER=ABSENT
CAPTURE_COMPLETE=yes
END_PAYTM_OPERATIONS_$Id
"@
}
$valid=Fixture $id $now
function Parse([string]$Text){Read-PaytmOperationsReceipt $Text $id $now.AddSeconds(-10) $now.AddSeconds(10)}
$r=Parse $valid
Check ($r.findings.Count -eq 0) 'clean capture'
Check (-not $r.clockAccuracyProven -and -not $r.applicationProxyEgressReobserved -and -not $r.fullyPatchedProven) 'no inferred acceptance'
Check ($r.collectionWindowSeconds -eq 20 -and $r.oldestReleaseMetadataAgeDays -eq 1) 'timing'
foreach($pair in @(@('HOST_IDENTITY=MATCH','HOST_IDENTITY=MISMATCH'),@('PROXY_CONFIG=MATCH','PROXY_CONFIG=MISMATCH'),@('ALLOWLIST=MATCH','ALLOWLIST=UNKNOWN'),@('SERVICE_CONFIG=MATCH','SERVICE_CONFIG=MISMATCH'),@('SERVICE_STATE=inactive','SERVICE_STATE=active'),@('DROPINS=NONE','DROPINS=PRESENT'),@('RELOAD_NEEDED=no','RELOAD_NEEDED=yes'),@('LISTENER_COUNT=0','LISTENER_COUNT=2'),@('WATCHDOG_UNIT_COUNT=0','WATCHDOG_UNIT_COUNT=1'),@('VPS_BOUND_PUBLIC_IPV4=130.250.191.137','VPS_BOUND_PUBLIC_IPV4=192.0.2.1'),@('NTP_SYNCHRONIZED=yes','NTP_SYNCHRONIZED=no'),@('CACHED_UPGRADE_COUNT=0','CACHED_UPGRADE_COUNT=7'),@('CACHED_UPGRADE_COUNT=0','CACHED_UPGRADE_COUNT=UNKNOWN'),@('REBOOT_MARKER=ABSENT','REBOOT_MARKER=PRESENT'),@('SSH_VERSION=1:10.0p1-7','SSH_VERSION=UNKNOWN'))) {
    Check ((Parse $valid.Replace($pair[0],$pair[1])).findings.Count -gt 0) $pair[1]
}
Check ((Parse (Fixture $id $now.AddMinutes(1))).findings -contains 'CLOCK_OUTSIDE_COLLECTION_WINDOW') 'clock future'
Check ((Parse (Fixture $id $now.AddMinutes(-1))).findings -contains 'CLOCK_OUTSIDE_COLLECTION_WINDOW') 'clock past'
Check ((Parse $valid.Replace("UTC_EPOCH=$($now.ToUnixTimeSeconds())",'UTC_EPOCH=UNKNOWN')).findings -contains 'SERVER_TIME_UNKNOWN') 'clock unknown'
Check ((Parse $valid.Replace("APT_OLDEST_RELEASE_EPOCH=$($now.AddDays(-1).ToUnixTimeSeconds())","APT_OLDEST_RELEASE_EPOCH=$($now.AddDays(-9).ToUnixTimeSeconds())")).findings -contains 'APT_CACHE_DATE_REVIEW') 'stale cache'
Check ((Parse $valid.Replace("APT_OLDEST_RELEASE_EPOCH=$($now.AddDays(-1).ToUnixTimeSeconds())",'APT_OLDEST_RELEASE_EPOCH=UNKNOWN')).findings -contains 'APT_CACHE_DATE_UNKNOWN') 'unknown cache'
foreach($bad in @($valid.Replace($id,'fedcba9876543210fedcba9876543210'),$valid.Replace('VERSION=1','VERSION=2'),$valid.Replace('CAPTURE_COMPLETE=yes','CAPTURE_COMPLETE=no'),$valid.Replace('VERSION=1',"VERSION=1`nVERSION=1"),$valid.Replace('VERSION=1',"VERSION=1`nUNEXPECTED=1"),$valid.Replace("VERSION=1`n",''),$valid.Replace('KERNEL=6.12.95+deb13-amd64','KERNEL=$(do-not-execute)'),('X'*8001),($valid+"`nSHELL_OUTPUT"))) {Reject {Parse $bad} 'malformed receipt'}
Reject {Read-PaytmOperationsReceipt $valid $id $now $now.AddMinutes(21)} 'stale window'
Reject {Read-PaytmOperationsReceipt $valid $id $now $now.AddSeconds(-1)} 'local clock reversed'
Reject {New-PaytmOperationsPayload "bad';cmd" 'text'} 'payload id injection'
Reject {New-PaytmOperationsPayload $id 'MB_OPERATIONS_READ_ONLY'} 'heredoc injection'
$payload=New-PaytmOperationsPayload $id '# test'
Check ($payload.StartsWith("sudo -n timeout 180s bash <<'MB_OPERATIONS_READ_ONLY'")) 'bounded sudo payload'
Check ($payload.Contains("po_main '$id'")) 'run pinned'
$global:mbOpsTestState=@{hash='BAD';copied='';mode=''}
function Get-FileHash {param($LiteralPath,$Algorithm) [pscustomobject]@{Hash=$global:mbOpsTestState.hash}}
$temp=Join-Path ([IO.Path]::GetTempPath()) ('paytm-ops-fixture-'+[guid]::NewGuid().ToString('N'))
$null=New-Item -ItemType Directory -Path $temp
$file=Join-Path $temp 'fixture.json';$null=New-Item -ItemType File -Path $file
Reject {Assert-PaytmAcceptedApplicationReport $file} 'wrong acceptance hash'
$global:mbOpsTestState.hash='E7AD80D611B693FF892DD3765C87FF333E554A4343E2647C08D7725F5A804973'
Check ((Assert-PaytmAcceptedApplicationReport $file).runId -eq '223cdc084de64c90a80c527032ac6879') 'pinned acceptance'
function Set-Clipboard {param($Value) $global:mbOpsTestState.copied=$Value}
function Read-Host {param($Prompt) ''}
function Get-Clipboard {
    param([switch]$Raw)
    $match=[regex]::Match($global:mbOpsTestState.copied,"po_main '([a-f0-9]{32})'")
    $text=Fixture $match.Groups[1].Value ([DateTimeOffset]::UtcNow)
    switch($global:mbOpsTestState.mode){'finding'{$text=$text.Replace('NTP_SYNCHRONIZED=yes','NTP_SYNCHRONIZED=no')};'invalid'{$text='PRIVATE_ARBITRARY_CLIPBOARD_MUST_NOT_LEAK'}}
    $text
}
foreach($mode in @('clean','finding','invalid','hash')) {
    $global:mbOpsTestState.mode=$mode;$out=Join-Path $temp $mode
    if($mode -eq 'hash'){$global:mbOpsTestState.hash='BAD'}
    $failed=$false
    try {& (Join-Path $PSScriptRoot 'ReviewPaytmOperations.ps1') -ApplicationEvidencePath $file -OutputDirectory $out}catch{$failed=$true}
    $files=@(Get-ChildItem -LiteralPath $out -Filter '*.json')
    Check ($files.Count -eq 1) "one report $mode"
    $raw=Get-Content -LiteralPath $files[0].FullName -Raw;$report=$raw|ConvertFrom-Json
    Check (-not $raw.Contains('PRIVATE_ARBITRARY') -and -not $report.settingsChanged -and -not $report.brokerCredentialsUsed -and -not $report.proxyStarted) "safe report $mode"
    if($mode -in @('invalid','hash')){Check ($failed -and $report.status -eq 'REVIEW_REQUIRED') "failure captured $mode"}
    elseif($mode -eq 'finding'){Check (-not $failed -and $report.status -eq 'SNAPSHOT_CAPTURED_WITH_FINDINGS') 'findings preserved'}
    else{Check (-not $failed -and $report.status -eq 'SNAPSHOT_CAPTURED_LOGIN_AND_MAINTENANCE_REVIEW_PENDING') 'capture not activation'}
}
Write-Host "PASS: $script:count offline assertions including four full mocked collection workflows. Fixtures retained: $temp"
