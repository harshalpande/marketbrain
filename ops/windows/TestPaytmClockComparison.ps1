#Requires -Version 7.0
# Offline fixtures: no SSH, Docker, HTTP, credentials, time changes or broker access.
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'PaytmClockComparison.ps1')
$checks=0
function Check([bool]$Value,[string]$Label){if(-not $Value){throw "FAIL: $Label"};$script:checks++}
function Reject([scriptblock]$Action,[string]$Label){$caught=$false;try{&$Action|Out-Null}catch{$caught=$true};Check $caught $Label}
$t=[DateTimeOffset]::Parse('2026-10-22T00:00:00Z')
$b=Get-PaytmClockBounds $t $t.AddSeconds(1) 1 $t.AddSeconds(3)
Check ($b.lowerOffsetSeconds -eq 1.998 -and $b.upperOffsetSeconds -eq 3.002 -and $b.usable) 'asymmetric delay bounds'
Check (-not (Get-PaytmClockBounds $t $t.AddSeconds(3) 3 $t).usable) 'slow sample not usable'
Check (-not (Get-PaytmClockBounds $t $t.AddSeconds(1.5) 1 $t).usable) 'clock jump rejected'
Reject {Get-PaytmClockBounds $t $t.AddSeconds(-1) 1 $t} 'backward wall time'
Reject {Get-PaytmClockBounds $t $t 0 ([DateTimeOffset]::MaxValue);Get-PaytmClockBounds $t $t ([double]::NaN) $t} 'nonfinite timer'
function Samples([double]$Vps=0,[double]$App=0){
    @(for($i=0;$i -lt 5;$i++){
        $at=$t.AddSeconds($i*2)
        [pscustomobject]@{source='VPS';pair=$i+1;ntpSynchronized='yes';bounds=(Get-PaytmClockBounds $at $at.AddSeconds(.2) .2 $at.AddSeconds(.1+$Vps))}
        [pscustomobject]@{source='APPLICATION';pair=$i+1;bounds=(Get-PaytmClockBounds $at $at.AddSeconds(.2) .2 $at.AddSeconds(.1+$App))}
    })
}
$a=Get-PaytmClockAssessment (Samples) 10 10
Check ($a.screenPassed -and -not $a.absoluteUtcAccuracyProven -and -not $a.quoteTimingApproved) 'relative screen not absolute approval'
Check (-not (Get-PaytmClockAssessment (Samples 6 0) 10 10).screenPassed) 'VPS skew'
Check (-not (Get-PaytmClockAssessment (Samples 0 -6) 10 10).screenPassed) 'application skew'
Check ((Get-PaytmClockAssessment (Samples -3 3) 10 10).findings -contains 'APPLICATION_VPS_OUTSIDE_FIVE_SECOND_SCREEN') 'cross-source difference matters'
Check (-not (Get-PaytmClockAssessment (Samples) 12 10).screenPassed) 'between-sample jump'
Check (-not (Get-PaytmClockAssessment (Samples) 121 121).screenPassed) 'collection deadline'
Check (-not (Get-PaytmClockAssessment @() 0 0).screenPassed) 'missing samples'
$s=Samples;$s[0].ntpSynchronized='no';Check (-not (Get-PaytmClockAssessment $s 10 10).screenPassed) 'NTP unknown not accepted'
$s=Samples;$s[0].bounds=Get-PaytmClockBounds $t $t.AddSeconds(.2) .2 $t.AddSeconds(2);Check ((Get-PaytmClockAssessment $s 10 10).findings -contains 'VPS_OFFSET_NOT_STABLE_ACROSS_SAMPLES') 'inconsistent samples not best-picked'
$s=Samples;$s[2].bounds.sourceUtc=$s[0].bounds.sourceUtc;Check ((Get-PaytmClockAssessment $s 10 10).findings -contains 'VPS_REPEATED_TIMESTAMP') 'repeated time flagged'
$nonce='a'*32
$sshArgs=New-PaytmClockSshArguments $nonce
Check ($sshArgs -contains 'marketbrain-admin' -and $sshArgs -contains '-batch' -and $sshArgs -contains '-hostkey') 'admin identity pin batch'
Check ($sshArgs -cnotcontains '-pw' -and $sshArgs -cnotcontains '-L' -and $sshArgs -cnotcontains '-R' -and $sshArgs -ccontains '-a' -and $sshArgs -ccontains '-x') 'no password or forwarding'
Check ($sshArgs[-1] -notmatch 'sudo|set-time|apt-get|systemctl start|date -s') 'read-only fixed remote command'
Reject {New-PaytmClockSshArguments 'a;bad'} 'nonce injection'
$r=Read-PaytmClockSshReceipt "MB_CLOCK_V1|$nonce|1792627200000|yes" $nonce
Check ($r.ntp -eq 'yes') 'receipt accepted'
Reject {Read-PaytmClockSshReceipt "MB_CLOCK_V1|$('b'*32)|1792627200000|yes" $nonce} 'old nonce'
Reject {Read-PaytmClockSshReceipt "MB_CLOCK_V1|$nonce|1792627200000|yes`nnoise" $nonce} 'extra output'
Reject {Read-PaytmClockSshReceipt "MB_CLOCK_V1|$nonce|NaN|yes" $nonce} 'invalid epoch'

$global:clockFixture=@{mode='pass';sshCount=0;httpCount=0;containerCount=0;cleanup=0}
function Resolve-PaytmClockTool {param($Name) $Name}
function Get-Command {param($Name,$CommandType,$ErrorAction) [pscustomobject]@{Source=$Name}}
function Test-Path {param($LiteralPath) if($LiteralPath -like 'HKCU:*'){return $false};Microsoft.PowerShell.Management\Test-Path -LiteralPath $LiteralPath}
function Invoke-PaytmClockDocker {param($Docker,$Arguments,$Root) if($Arguments[1] -eq 'show'){'desktop-linux'}else{'npipe:////./pipe/dockerDesktopLinuxEngine'}}
function Get-PaytmClockContainer {
    param($Docker,$Root)
    $global:clockFixture.containerCount++
    if($global:clockFixture.mode -eq 'dockerfail'){throw 'CLOCK_DOCKER_QUERY_FAILED'}
    $id=if($global:clockFixture.mode -eq 'restart' -and $global:clockFixture.containerCount -gt 1){'b'*64}else{'a'*64}
    [pscustomobject]@{identity=[pscustomobject]@{id=$id;image='fixture';startedAt='fixture'};token='PRIVATE_TOKEN_DO_NOT_LOG'}
}
function Invoke-PaperRuntimeProcess {
    param($Executable,$Arguments,$Directory,$LimitSeconds)
    if($Arguments[0] -eq '-V'){return @{exitCode=0;stdout='plink: Release 0.83';stderr=''}}
    $global:clockFixture.sshCount++
    [Threading.Thread]::Sleep(3) # Fixture timestamps must advance at millisecond resolution.
    Check ($LimitSeconds -eq 15 -and $Arguments -contains '-hostkey') 'bounded pinned SSH'
    if($global:clockFixture.mode -eq 'sshfail'){return @{exitCode=1;stdout='PRIVATE_STDOUT';stderr='PRIVATE_STDERR'}}
    if($global:clockFixture.mode -eq 'timeout'){throw 'RUNTIME_PROCESS_TIMEOUT'}
    $n=[regex]::Match($Arguments[-1],'MB_CLOCK_V1\|([a-f0-9]{32})').Groups[1].Value
    if($global:clockFixture.mode -eq 'badnonce'){$n='f'*32}
    $offset=if($global:clockFixture.mode -eq 'skew'){10}else{0}
    @{exitCode=0;stdout="MB_CLOCK_V1|$n|$([DateTimeOffset]::UtcNow.AddSeconds($offset).ToUnixTimeMilliseconds())|yes";stderr=''}
}
function Invoke-PaytmClockApplication {
    param($Token)
    Check ($Token -ceq 'PRIVATE_TOKEN_DO_NOT_LOG') 'private token only in memory'
    $global:clockFixture.httpCount++
    [Threading.Thread]::Sleep(3)
    if($global:clockFixture.mode -eq 'httpfail'){throw 'CLOCK_APPLICATION_READ_FAILED'}
    [DateTimeOffset]::UtcNow
}
function Read-Host {
    param($Prompt)
    if($Prompt -like '*CLOCK-CHECK*'){if($global:clockFixture.mode -eq 'cancel'){'CANCEL'}else{'CLOCK-CHECK'}}
    else{$global:clockFixture.cleanup++;if($global:clockFixture.mode -eq 'cleanupfail'){'NO'}else{'KEY-REVIEWED'}}
}
$body=[IO.File]::ReadAllText((Join-Path $PSScriptRoot 'TestPaytmClockSnapshot.ps1'))
$import='. (Join-Path $PSScriptRoot ''PaytmClockComparison.ps1'')';Check ($body.Contains($import)) 'runner dependency seam'
$body=$body.Replace($import,'# mocked dependencies').Replace('$PSScriptRoot',("'"+$PSScriptRoot.Replace("'","''")+"'"))
$runner=[scriptblock]::Create($body)
$temp=Join-Path ([IO.Path]::GetTempPath()) ('paytm-clock-fixtures-'+[guid]::NewGuid().ToString('N'))
foreach($mode in @('pass','skew','sshfail','timeout','badnonce','httpfail','restart','cancel','cleanupfail','dockerfail')){
    $global:clockFixture.mode=$mode;$global:clockFixture.sshCount=0;$global:clockFixture.httpCount=0;$global:clockFixture.containerCount=0;$global:clockFixture.cleanup=0
    $folder=Join-Path $temp $mode;$failed=$false
    try{& $runner -OutputDirectory $folder}catch{$failed=$true}
    $files=@(Get-ChildItem -LiteralPath $folder -Filter '*.json');Check ($files.Count -eq 1) "one report $mode"
    $raw=[IO.File]::ReadAllText($files[0].FullName);$r=$raw|ConvertFrom-Json
    Check (-not $raw.Contains('PRIVATE_') -and -not $r.settingsChanged -and -not $r.brokerCredentialsUsed -and -not $r.quoteTimingApproved) "safe evidence $mode"
    if($mode -in @('pass','skew')){
        Check (-not $failed -and $r.samples.Count -eq 10 -and $r.containerUnchanged) "complete pairs $mode"
        if($mode -eq 'pass'){Check ($r.status -eq 'CLOCK_SNAPSHOT_WITHIN_SCREEN_RELEASE_PENDING') 'successful runner screen'}
        if($mode -eq 'skew'){Check ($r.status -eq 'CLOCK_SNAPSHOT_CAPTURED_WITH_FINDINGS') 'skew finding not acceptance'}
    }else{Check ($failed -and $r.status -eq 'REVIEW_REQUIRED') "failure retained $mode"}
    Check ($global:clockFixture.cleanup -eq $(if($mode -eq 'dockerfail'){0}else{1})) "cleanup even on cancellation $mode"
    if($mode -eq 'httpfail'){Check ($r.samples.Count -eq 1) 'partial sample retained'}
    if($mode -eq 'restart'){Check (-not $r.containerUnchanged) 'restart invalidates snapshot'}
}
Write-Host "PASS: $checks assertions, ten mocked runner workflows. No network or application access. Fixtures: $temp"
