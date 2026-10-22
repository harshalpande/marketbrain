#Requires -Version 5.1
# Real runner control flow with fake local processes, Pageant, network and clipboard.
$ErrorActionPreference='Stop'; Set-StrictMode -Version Latest
. (Join-Path $PSScriptRoot 'PaytmTunnelVerification.ps1')
$runner=[IO.File]::ReadAllText((Join-Path $PSScriptRoot 'TestPaytmTunnelBundle.ps1'))
$import=". (Join-Path `$PSScriptRoot 'PaytmTunnelVerification.ps1')"
if(-not $runner.Contains($import)){throw 'Runner import changed; review fixture'}
$runner=$runner.Replace($import,'# Real helpers already loaded; external operations mocked by fixture.')
# The trusted repository runner is evaluated, not attachment content. Preserve its own PSScriptRoot.
$runner=$runner.Replace('$PSScriptRoot',("'"+$PSScriptRoot.Replace("'","''")+"'"))
$block=[scriptblock]::Create($runner)
$fixtureRoot=Join-Path ([IO.Path]::GetTempPath()) ('mb-tunnel-fixtures-'+[guid]::NewGuid().ToString('N'))
[void][IO.Directory]::CreateDirectory($fixtureRoot)
$fixtureReports=New-Object 'Collections.Generic.List[string]'
$fixtureDirs=New-Object 'Collections.Generic.List[string]'
$script:fixtureState=$null
function MockResult([int]$Code,[string]$Out,[string]$Err='', [bool]$Stopped=$false){[pscustomobject]@{ExitCode=$Code;Stdout=$Out;Stderr=$Err;StoppedByRunner=$Stopped;ElapsedSeconds=0.01}}
function Get-TunnelListeners([int]$Port) {
    if($fixtureState.Listener){
        if($fixtureState.Case -eq 'ListenerQueryFailure'){throw 'fixture TCP query failed'}
        $row=[pscustomobject]@{LocalAddress='127.0.0.1';LocalPort=$Port;OwningProcess=$fixtureState.Listener}
        if($fixtureState.Case -eq 'ListenerWrongOwner'){$row.OwningProcess=99999}
        if($fixtureState.Case -eq 'ListenerExposed'){$row.LocalAddress='0.0.0.0'}
        $row
        if($fixtureState.Case -eq 'ListenerDuplicate'){$row}
        if($fixtureState.Case -in @('PassDualLoopback','ListenerDualForeignOwner','ListenerDualWildcard','ListenerDualWrongPort','ListenerDualDuplicate')){
            $companion=[pscustomobject]@{LocalAddress='::1';LocalPort=$Port;OwningProcess=$fixtureState.Listener}
            if($fixtureState.Case -eq 'ListenerDualForeignOwner'){$companion.OwningProcess=99999}
            if($fixtureState.Case -eq 'ListenerDualWildcard'){$companion.LocalAddress='::'}
            if($fixtureState.Case -eq 'ListenerDualWrongPort'){$companion.LocalPort=$Port+1}
            $companion
            if($fixtureState.Case -eq 'ListenerDualDuplicate'){$companion}
        }
    }
}
function Get-ItemProperty {param($LiteralPath) $null}
function Set-Clipboard {param($Value) $fixtureState.Payload=$Value}
function Get-Clipboard {param([switch]$Raw) $fixtureState.Clipboard}
function Start-Process {param($FilePath,$WindowStyle) $fixtureState.PageantCalls++}
function Read-Host([string]$Prompt) {
    if($Prompt -like '*ADMIN-VERIFIED*'){return 'ADMIN-VERIFIED'}
    if($Prompt -like '*KEY-READY*'){return 'KEY-READY'}
    if($Prompt -match 'SERVER_READY=([a-f0-9]{32})'){
        $fixtureState.Run=$Matches[1]
        if($fixtureState.Case -eq 'InputTimeoutBeforeReady'){return 'FAILED'}
        $fixtureState.Proxy=$true;return "SERVER_READY=$($fixtureState.Run)"
    }
    if($Prompt -like '*server report is copied*') {
        $fixtureState.Proxy=$false
        $id=$fixtureState.Run
        $lines=@("BEGIN_SERVER_REPORT_$id")
        foreach($name in @('SERVER_BEGIN','SERVER_TERMINAL_INPUT_OK','SERVER_START_CONFIRMED','SERVER_STOP_CONFIRMED','SERVER_HOST_IDENTITY_OK','SERVER_GATEWAY_POLICY_AND_KEY_OK','SERVER_CONFIG_UNCHANGED_INITIAL_STOPPED','SERVER_REMOTE_TEST_PORT_FREE','SERVER_READY','SERVER_STOPPED')){$lines+="$name=$id"}
        $lines+="SERVER_EXIT=0 RUN=$id"; $lines+="SERVER_REPORT_END=$id WORKER_EXIT=0 LOG_EXIT=0 ELAPSED=25"; $lines+="END_SERVER_REPORT_$id"
        $fixtureState.Clipboard=$lines -join "`n"
        if($fixtureState.Case -eq 'BadServerEvidence'){$fixtureState.Clipboard=$fixtureState.Clipboard.Replace('SERVER_EXIT=0','SERVER_EXIT=1')}
        if($fixtureState.Case -eq 'InputTimeoutBeforeReady'){
            foreach($marker in @('SERVER_START_CONFIRMED','SERVER_STOP_CONFIRMED','SERVER_READY','SERVER_STOPPED')){$fixtureState.Clipboard=$fixtureState.Clipboard.Replace("$marker=$id",'')}
            $fixtureState.Clipboard=$fixtureState.Clipboard.Replace('SERVER_EXIT=0','SERVER_EXIT=142').Replace('WORKER_EXIT=0','WORKER_EXIT=142')
        }
        return ''
    }
    if($Prompt -like '*KEY-REMOVED*'){if($fixtureState.Case -eq 'KeyNotRemoved'){return ''}; return 'KEY-REMOVED'}
    throw "Unexpected prompt $Prompt"
}
function Start-TunnelProcess([string]$Executable,[string[]]$Arguments) {
    $fixtureState.NextId++
    $result=$null; $isTunnel=$false
    $auth="Access granted`n"
    if($Arguments -ccontains '-V'){$result=MockResult 0 'plink: Release 0.83'}
    elseif($Arguments -ccontains '--write-out') {
        $url=$Arguments[-1]
        if(-not $fixtureState.Listener){$result=MockResult 7 '000|0|000'}
        elseif(-not $fixtureState.Proxy){$result=MockResult 56 '000|0|000'}
        elseif($url -eq 'https://developer.paytmmoney.com/'){$result=MockResult 0 '200|0|503'}
        elseif($url -like 'http://*'){$result=MockResult 0 '000|0|403'}
        else {$result=MockResult 56 '403|0|000'}
        if($fixtureState.Case -eq 'ProxyAllowedForbiddenHost' -and $url -eq 'https://example.com/'){$result=MockResult 0 '200|0|200'}
    }
    elseif($Arguments -ccontains '-L') {$isTunnel=$true;$fixtureState.Listener=$fixtureState.NextId}
    elseif($Arguments -ccontains '-R') {$result=MockResult 1 '' ($auth+'Remote port forwarding from 127.0.0.1:19889 refused') $true}
    elseif($Arguments -ccontains '-nc') {
        $result=MockResult 1 '' ($auth+'Server refused to open main channel: Administratively prohibited')
        if($fixtureState.Case -eq 'WrongTargetAuthFailure'){$result=MockResult 1 '' 'Access denied'}
    }
    else {
        $result=MockResult 1 '' ($auth+'Server refused to open main channel: open failed')
        if($fixtureState.Case -eq 'PreflightAuthFailure'){$result=MockResult 1 '' 'Access denied'}
    }
    [pscustomobject]@{Process=[pscustomobject]@{Id=$fixtureState.NextId;HasExited=($null -ne $result)};Result=$result;IsTunnel=$isTunnel}
}
function Complete-TunnelProcess($Handle,[int]$LimitSeconds=20,[switch]$StopNow) {
    if($null -eq $Handle.Result) {
        $message="Access granted`n"
        if(-not $fixtureState.Proxy){$message+='Forwarded connection refused by remote: Connect failed [Connection refused]'}
        $Handle.Result=MockResult -1 '' $message $true
        $Handle.Process.HasExited=$true
        if($fixtureState.Listener -eq $Handle.Process.Id){$fixtureState.Listener=0}
    }
    $Handle.Result
}
$count=0
try {
    foreach($case in @('Pass','PassDualLoopback','PreflightAuthFailure','WrongTargetAuthFailure','ProxyAllowedForbiddenHost','BadServerEvidence','KeyNotRemoved','InputTimeoutBeforeReady','ListenerWrongOwner','ListenerExposed','ListenerDuplicate','ListenerQueryFailure','ListenerDualForeignOwner','ListenerDualWildcard','ListenerDualWrongPort','ListenerDualDuplicate')) {
        $script:fixtureState=[pscustomobject]@{Case=$case;Run='';Proxy=$false;Listener=0;NextId=1000;Payload='';Clipboard='';PageantCalls=0}
        $folder=Join-Path $fixtureRoot $case
        $fixtureDirs.Add($folder)
        $failed=$false
        try {& $block -OutputDirectory $folder -LocalPort 18889}catch{$failed=$true}
        $files=@(Get-ChildItem -LiteralPath $folder -Filter '*.json')
        if($files.Count -ne 1){throw "Expected one report for $case"}
        $fixtureReports.Add($files[0].FullName)
        $data=Get-Content -LiteralPath $files[0].FullName -Raw | ConvertFrom-Json
        if($case -in @('Pass','PassDualLoopback')) {
            if($failed -or $data.status -ne 'TUNNEL_BATCH_PASSED_APPLICATION_AND_AUTHENTICATION_PENDING' -or -not $data.serverEvidenceVerified -or -not $data.ownerGatewayKeyRemoved){throw "Happy path failed: $($data.failure)"}
            if($data.steps.Count -ne 9 -or @($data.steps | Where-Object status -ne PASS).Count){throw 'Incomplete stage ledger'}
            if($data.providerRootStatuses.Count -ne 2 -or $data.providerRootStatuses[0] -ne 503){throw '503 was lost or treated as API health'}
            if($case -eq 'PassDualLoopback' -and @($data.listenerEvidence | Where-Object {$_.rowCount -ne 2 -or -not $_.valid}).Count){throw 'Dual-loopback path lost listener evidence'}
        } elseif(-not $failed -or $data.status -ne 'REVIEW_REQUIRED'){throw "Failure incorrectly passed: $case"}
        if($fixtureState.Listener -ne 0 -or $data.ordersEnabled -or $data.brokerAuthenticationEnabled){throw 'Cleanup/safety boundary violated'}
        if($case -eq 'PreflightAuthFailure' -and $fixtureState.Payload){throw 'Proxy start payload exposed despite failed authentication preflight'}
        if($case -in @('BadServerEvidence','InputTimeoutBeforeReady') -and ($data.serverEvidenceVerified -or -not $data.serverEvidence)){throw 'Failed server evidence lost or incorrectly verified'}
        if($case -eq 'InputTimeoutBeforeReady' -and @($data.processes | Where-Object label -eq 'Allowed tunnel').Count){throw 'Tunnel opened without readiness'}
        if($data.launcherRevision -ne 'FILE_WITH_TERMINAL_STDIN_V2'){throw 'Launcher revision missing'}
        if($data.listenerValidationRevision -ne 'OWNED_LOOPBACK_PAIR_V2'){throw 'Listener revision missing'}
        if($case -like 'Listener*') {
            if($data.listenerEvidence.Count -ne 1 -or $data.providerRootStatuses.Count -ne 0 -or -not $data.localCleanupConfirmed){throw 'Listener failure capture or safe cleanup broken'}
            if($case -eq 'ListenerQueryFailure'){
                if($data.listenerEvidence[0].queryError -ne 'fixture TCP query failed'){throw 'Query error not preserved'}
            } else {
                $reason=switch($case){ListenerWrongOwner {'OWNER_PID_MISMATCH'};ListenerExposed {'UNEXPECTED_BIND_ADDRESS'};ListenerDuplicate {'DUPLICATE_LOOPBACK_LISTENER'};ListenerDualForeignOwner {'OWNER_PID_MISMATCH'};ListenerDualWildcard {'UNEXPECTED_BIND_ADDRESS'};ListenerDualWrongPort {'PORT_MISMATCH'};ListenerDualDuplicate {'DUPLICATE_LOOPBACK_LISTENER'}}
                if($data.listenerEvidence[0].reasons -notcontains $reason -or $data.listenerEvidence[0].expectedProcessId -le 0){throw 'Expected listener failure detail absent'}
            }
        }
        $count++
    }
    Write-Host "PASS: $count mocked whole-run workflows; one report per run, no real network, Pageant or VPS changes."
} finally {
    # Only exact files/directories created by this fixture. No recursive deletion.
    foreach($file in $fixtureReports){if(Test-Path -LiteralPath $file){Remove-Item -LiteralPath $file}}
    foreach($folder in $fixtureDirs){if(Test-Path -LiteralPath $folder){[IO.Directory]::Delete($folder,$false)}}
    [IO.Directory]::Delete($fixtureRoot,$false)
}
