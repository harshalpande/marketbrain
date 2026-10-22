#Requires -Version 7.0
# Mocked diagnostics and whole-runner evidence checks. No actual service operations.
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'PaytmWindowsTimeAccess.ps1')
$checks=0
function Check([bool]$Value,[string]$Label){if(-not $Value){throw "FAIL: $Label"};$script:checks++}
function Reject([scriptblock]$Action,[string]$Label){$failed=$false;try{&$Action|Out-Null}catch{$failed=$true};Check $failed $Label}
function Probe([bool]$Allowed=$false,[bool]$Admin=$true){
    $rights=@();$masks=[ordered]@{QUERY_CONFIG=1;QUERY_STATUS=4;READ_CONTROL=131072;SERVICE_START=16}
    foreach($name in $masks.Keys){$ok=($name -ne 'SERVICE_START' -or $Allowed);$rights+=@{right=$name;mask=$masks[$name];allowed=$ok;stage='OpenService';win32Error=$(if($ok){0}else{5})}}
    @{schemaVersion=1;target='LOCAL_W32Time';administratorEnabled=$Admin;rights=$rights;serviceStartInvoked=$false;securityChanged=$false}|ConvertTo-Json -Depth 6 -Compress
}
$p=Read-PaytmTimeAccessProbe (Probe)
Check ($p.rights.Count -eq 4 -and -not $p.rights[3].allowed) 'denied start captured'
Check ((Read-PaytmTimeAccessProbe (Probe $true)).rights[3].allowed) 'allowed handle captured'
Reject {Read-PaytmTimeAccessProbe 'not json'} 'bad JSON'
Reject {Read-PaytmTimeAccessProbe ((Probe).Replace('LOCAL_W32Time','OTHER'))} 'wrong target'
Reject {Read-PaytmTimeAccessProbe ((Probe).Replace('"serviceStartInvoked":false','"serviceStartInvoked":true'))} 'mutation claim'
Reject {Read-PaytmTimeAccessProbe ((Probe).Replace('"securityChanged":false','"securityChanged":"false"'))} 'string safety flag'
Reject {Read-PaytmTimeAccessProbe ((Probe).Replace('SERVICE_START','QUERY_CONFIG'))} 'duplicate right'
Reject {Read-PaytmTimeAccessProbe ((Probe).Replace('"mask":16','"mask":983551'))} 'excess access mask'
Reject {Read-PaytmTimeAccessProbe ((Probe).Replace('"win32Error":5','"win32Error":0'))} 'denied zero error inconsistent'
Reject {Read-PaytmTimeAccessProbe ((Probe $true).Replace('"win32Error":0','"win32Error":5'))} 'allowed nonzero error inconsistent'
$specs=@(Get-PaytmTimeAccessCommandSpecs)
Check ($specs.Count -eq 7) 'bounded fixed queries'
foreach($spec in $specs){Check (($spec.arguments -join ' ') -notmatch '(?i)(^|\s)(start|stop|config|sdset|delete|add|/resync|/register|/unregister)(\s|$)') 'no mutation command'}
$global:mbTimeAccessFixture=@{mode='deny';admin=$true;queries=0;children=0}
function Test-PaytmOperationsAdministrator {$global:mbTimeAccessFixture.admin}
function Invoke-PaytmTimeCommand {
    param($Label,$Executable,$Arguments)
    $global:mbTimeAccessFixture.queries++
    $failed=($global:mbTimeAccessFixture.mode -eq 'queryfail')
    [pscustomobject]@{label=$Label;exitCode=$(if($failed){5}else{0});output='fixture';failure=$null;elapsedSeconds=0.01}
}
function Invoke-PaperRuntimeProcess {
    param($Executable,$Arguments,$Directory,$LimitSeconds)
    $global:mbTimeAccessFixture.children++
    Check ($LimitSeconds -eq 30 -and $Arguments[2] -eq '-File' -and $Arguments[-1].EndsWith('ReadPaytmTimeAccessProbe.ps1')) 'fixed bounded child'
    if($global:mbTimeAccessFixture.mode -eq 'timeout'){throw 'RUNTIME_PROCESS_TIMEOUT'}
    $raw=if($global:mbTimeAccessFixture.mode -eq 'invalid'){'PRIVATE_INVALID_OUTPUT'}else{Probe ($global:mbTimeAccessFixture.mode -eq 'allowed') ($global:mbTimeAccessFixture.mode -ne 'childadmin')}
    @{exitCode=$(if($global:mbTimeAccessFixture.mode -eq 'childfail'){1}else{0});stdout=$raw;stderr='PRIVATE_ERROR_NOT_LOGGED';elapsedSeconds=0.01}
}
function Assert-PaytmTimeAccessEvidence {
    param($Path)
    if($global:mbTimeAccessFixture.mode -eq 'hash'){throw 'OPS_TIME_ACCESS_PRIOR_HASH_MISMATCH'}
    @{runId='fixture';sha256='fixture'}
}
$body=[IO.File]::ReadAllText((Join-Path $PSScriptRoot 'ReviewPaytmWindowsTimeAccess.ps1'))
$import='. (Join-Path $PSScriptRoot ''PaytmWindowsTimeAccess.ps1'')'
Check ($body.Contains($import)) 'runner dependency seam'
$body=$body.Replace($import,'# dependencies mocked').Replace('$PSScriptRoot',("'"+$PSScriptRoot.Replace("'","''")+"'"))
$runner=[scriptblock]::Create($body)
$temp=Join-Path ([IO.Path]::GetTempPath()) ('paytm-time-access-fixtures-'+[guid]::NewGuid().ToString('N'))
foreach($mode in @('deny','allowed','queryfail','childadmin','timeout','invalid','childfail','notadmin','hash')){
    $global:mbTimeAccessFixture.mode=$mode;$global:mbTimeAccessFixture.admin=($mode -ne 'notadmin');$global:mbTimeAccessFixture.queries=0;$global:mbTimeAccessFixture.children=0
    $folder=Join-Path $temp $mode;$failed=$false
    try{& $runner -OperationsEvidencePath 'fixture' -OutputDirectory $folder}catch{$failed=$true}
    $files=@(Get-ChildItem -LiteralPath $folder -Filter '*.json')
    Check ($files.Count -eq 1) "one JSON $mode"
    $raw=[IO.File]::ReadAllText($files[0].FullName);$r=$raw|ConvertFrom-Json
    Check (-not $r.clockChanged -and -not $r.serviceStartInvoked -and -not $r.securityChanged -and -not $r.vpsAccessed -and -not $r.ordersEnabled -and -not $raw.Contains('PRIVATE_')) "boundaries $mode"
    if($mode -in @('notadmin','hash')){
        Check ($failed -and $global:mbTimeAccessFixture.queries -eq 0 -and $global:mbTimeAccessFixture.children -eq 0) "prerequisites $mode"
    }else{
        Check (-not $failed -and $global:mbTimeAccessFixture.queries -eq 7 -and $global:mbTimeAccessFixture.children -eq 1) "all bounded diagnostics $mode"
        Check (-not $r.inspection.clockAccuracyProven) 'never accuracy proof'
        if($mode -in @('timeout','invalid','childfail')){Check ($r.status -eq 'TIME_ACCESS_PARTIAL_REVIEW_REQUIRED' -and $r.inspection.commands.Count -eq 7) 'partial retains queries'}
        else{Check ($r.status -eq 'TIME_ACCESS_CAPTURED_REPAIR_REVIEW_PENDING') 'capture not repair'}
        if($mode -eq 'deny'){Check ($r.inspection.findings -contains 'START_HANDLE_ACCESS_DENIED') 'precise access denial'}
        if($mode -eq 'allowed'){Check ($r.inspection.findings -contains 'START_HANDLE_ALLOWED_NOT_START_OR_SYNC_PROOF') 'allowed handle not proof of actual start'}
        if($mode -eq 'childadmin'){Check ($r.inspection.findings -contains 'CHILD_ADMINISTRATOR_NOT_ENABLED') 'child token difference retained'}
        if($mode -eq 'queryfail'){Check ($r.inspection.findings.Count -eq 8) 'each query failure retained'}
    }
}
$native=[IO.File]::ReadAllText((Join-Path $PSScriptRoot 'PaytmTimeAccessProbe.cs'))
Add-Type -TypeDefinition $native
Check ($null -ne ('MarketBrain.Diagnostics.TimeServiceAccess' -as [type])) 'native probe compiles without invoking'
Check (-not ($native -match 'extern.*(StartService|SetService|ChangeService|AdjustToken|CreateService)')) 'no native mutation imports'
Check ($native.Contains('OpenSCManagerW(null, null, 0x0001)') -and $native.Contains('OpenServiceW(manager, "W32Time", masks[i])')) 'local fixed target minimal handle rights'
Write-Host "PASS: $checks assertions, nine mocked workflows; native probe compiled only. No actual service operations. Fixtures: $temp"
