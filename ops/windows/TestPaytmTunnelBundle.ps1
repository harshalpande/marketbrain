#Requires -Version 5.1
[CmdletBinding()]
param([string]$OutputDirectory='C:\MarketBrainData\Review',[ValidateRange(1024,65535)][int]$LocalPort=18889)
$ErrorActionPreference='Stop'; Set-StrictMode -Version Latest
. (Join-Path $PSScriptRoot 'PaytmTunnelVerification.ps1')
$runId=[guid]::NewGuid().ToString('N')
$watch=[Diagnostics.Stopwatch]::StartNew()
$handles=New-Object 'Collections.Generic.List[object]'
$steps=New-Object 'Collections.Generic.List[object]'
$report=[ordered]@{schemaVersion=1;runId=$runId;startedUtc=[DateTime]::UtcNow.ToString('o');status='RUNNING';scope='SPARE_TO_VPS_TUNNEL_ONLY';steps=$steps;processes=@();serverEvidence=$null;serverEvidenceVerified=$false;priorInstallationLogReviewed=$false;ownerFreshAdminConfirmed=$false;ownerGatewayKeyRemoved=$false;localCleanupConfirmed=$false;providerRootStatuses=@();failure=$null;elapsedSeconds=0;applicationContainerVerified=$false;brokerAuthenticationEnabled=$false;ordersEnabled=$false}
$session=[ordered]@{ServerRequested=$false;PageantRequested=$false;Tunnel=$null}; $passed=$false
$report.egressReobserved=$false
$report.launcherRevision='FILE_WITH_TERMINAL_STDIN_V2'
$report.listenerValidationRevision='OBSERVED_ENDPOINT_AND_OWNER_V1'
$report.listenerEvidence=New-Object 'Collections.Generic.List[object]'
$report.powerShellVersion=$PSVersionTable.PSVersion.ToString()
$reportPath=$null
function Save-Report {
    if($reportPath){$report.elapsedSeconds=[math]::Round($watch.Elapsed.TotalSeconds,3); [IO.File]::WriteAllText($reportPath,($report | ConvertTo-Json -Depth 12),(New-Object Text.UTF8Encoding($false)))}
}
function Stage([string]$Id,[int]$Percent,[scriptblock]$Action) {
    Write-Progress -Activity 'Paytm restricted tunnel verification' -Status $Id -PercentComplete $Percent
    Write-Host "[$Percent%] $Id"
    $timer=[Diagnostics.Stopwatch]::StartNew(); $entry=[ordered]@{id=$Id;status='RUNNING';elapsedSeconds=0;failure=$null}
    $steps.Add($entry); Save-Report
    try { & $Action; $entry.status='PASS' } catch {$entry.status='FAIL';$entry.failure=$_.Exception.Message;throw}
    finally {$entry.elapsedSeconds=[math]::Round($timer.Elapsed.TotalSeconds,3);Save-Report}
}
function Find-Tool([string]$Name) {
    $candidates=@()
    foreach($root in @($env:ProgramFiles,${env:ProgramFiles(x86)})){if($root){$candidates+=Join-Path $root "PuTTY\$Name"}}
    $command=Get-Command $Name -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
    if($command){$candidates+=$command.Source}
    foreach($candidate in $candidates){if(Test-Path -LiteralPath $candidate -PathType Leaf){return $candidate}}
    throw "$Name missing; no installation or download attempted"
}
function Start-Owned([string]$Label,[string]$Executable,[string[]]$Arguments) {
    $handle=Start-TunnelProcess $Executable $Arguments
    $handle | Add-Member NoteProperty Label $Label
    $handles.Add($handle)
    $handle
}
function Probe([string]$Label,[string]$Executable,[string[]]$Arguments,[int]$Limit=20) {
    $handle=Start-Owned $Label $Executable $Arguments
    Complete-TunnelProcess $handle $Limit
}
function Start-Forward([string]$Label) {
    $existing=@(Get-TunnelListeners $LocalPort)
    if($existing.Count){
        [void]$report.listenerEvidence.Add((Get-TunnelListenerAssessment $existing 0 $LocalPort "$Label pre-start occupied port"))
        throw 'Local test port occupied; no process will be displaced'
    }
    $handle=Start-Owned $Label $plink ($sshArgs+@('-T','-N','-L',"127.0.0.1:${LocalPort}:127.0.0.1:18888",'130.250.191.137'))
    try {Wait-TunnelListener $handle $LocalPort -Evidence $report.listenerEvidence -Label $Label}
    finally {Save-Report}
    $handle
}
function Curl-Probe([string]$Label,[string]$Url,[string]$Kind) {
    $result=Probe $Label $curl (Get-TunnelCurlArguments $LocalPort $Url)
    Assert-TunnelCurl $result $Kind
    if($Kind -eq 'Tls'){$report.providerRootStatuses+= [int]($result.Stdout.Trim().Split('|')[2])}
}
function Collect-ServerStop {
    Write-Host 'PUTTY: if the test is still waiting for STOP, type STOP there and press ENTER.'
    Write-Host 'If PuTTY has returned to marketbrain-admin@...$, the test ended: do NOT type STOP as a Linux command.'
    Write-Host 'Copy the current run report, even if it reports failure: BEGIN_SERVER_REPORT through END_SERVER_REPORT.'
    Write-Host 'Select/copy ONLY that complete report block (not earlier terminal history) to the Windows clipboard.'
    [void](Read-Host 'Press Enter here AFTER the server report is copied')
    $clipboard=Get-Clipboard -Raw
    # Preserve bounded current-run failure evidence too; never save unrelated clipboard history.
    if($clipboard -and $clipboard.Length -le 32768) {
        $begin="BEGIN_SERVER_REPORT_$runId"; $end="END_SERVER_REPORT_$runId"
        $first=$clipboard.IndexOf($begin,[StringComparison]::Ordinal); $last=$clipboard.IndexOf($end,[StringComparison]::Ordinal)
        if($first -ge 0 -and $last -gt $first){$report.serverEvidence=$clipboard.Substring($first,$last+$end.Length-$first);Save-Report}
    }
    $report.serverEvidence=Read-TunnelServerEvidence $clipboard $runId
    $report.serverEvidenceVerified=$true
    Save-Report
}
try {
    if($env:OS -ne 'Windows_NT'){throw 'Run on spare Windows laptop only'}
    [void][IO.Directory]::CreateDirectory($OutputDirectory)
    $reportPath=Join-Path ([IO.Path]::GetFullPath($OutputDirectory)) ('paytm-tunnel-verification-{0}-{1}.json' -f (Get-Date -Format yyyyMMdd-HHmmss),$runId)
    $file=[IO.File]::Open($reportPath,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::None); $file.Dispose()
    Save-Report
    $plink=Find-Tool 'plink.exe'; $pageant=Find-Tool 'pageant.exe'; $curl=Find-Tool 'curl.exe'
    $publicKey=(Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..\keys\paytm-gateway.pub')).Path
    if([IO.File]::ReadAllText($publicKey).Trim() -cne 'ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIN0RPkYq7LMb/7fELzlnQIopM+xrLgxF1gBljdHiEdKJ marketbrain-paytm-gateway'){throw 'Public selector key changed'}
    $sshArgs=Get-TunnelBaseArguments $publicKey
    $serverPayload=Get-TunnelServerPayload $runId
    $sha=[Security.Cryptography.SHA256]::Create()
    try {$report.serverPayloadSha256=([BitConverter]::ToString($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($serverPayload)))).Replace('-','').ToLowerInvariant()} finally {$sha.Dispose()}
    Stage 'Local tools, settings and fresh-admin prerequisite' 5 {
        $existing=@(Get-TunnelListeners $LocalPort)
        if($existing.Count){
            [void]$report.listenerEvidence.Add((Get-TunnelListenerAssessment $existing 0 $LocalPort 'Initial occupied port'))
            throw 'Local test port already occupied; no process will be displaced'
        }
        $settingsPath='HKCU:\Software\SimonTatham\PuTTY\Sessions\Default%20Settings'
        $settings=$null
        if(Test-Path -LiteralPath $settingsPath){$settings=Get-ItemProperty -LiteralPath $settingsPath}
        Assert-TunnelDefaults $settings
        $version=Probe 'Plink version' $plink @('-V') 5
        if($version.ExitCode -ne 0 -or ($version.Stdout+$version.Stderr) -notmatch 'Release (\d+)\.(\d+)'){throw 'Cannot verify PuTTY release'}
        if([version]($Matches[1]+'.'+$Matches[2]) -lt [version]'0.83'){throw 'PuTTY 0.83 or newer required; stop for reviewed update'}
        Write-Host 'Prerequisite: original administrator key works in a NEW PuTTY session; sudo whoami returns root.'
        if((Read-Host 'Type ADMIN-VERIFIED only if that check passed') -cne 'ADMIN-VERIFIED'){throw 'Fresh administrator check not confirmed'}
        $report.ownerFreshAdminConfirmed=$true
    }
    Stage 'Temporary interactive gateway-key unlock in Pageant' 10 {
        Write-Host 'Pageant holds the gateway key in local memory for this batch. Do NOT load it onto the VPS or remove its passphrase.'
        Write-Host 'In Pageant choose Add Key, select the NEW gateway PPK and enter its passphrase privately.'
        Write-Host 'Expected public fingerprint: SHA256:fRekz3jjaYJxnK5dDXMzq9mDEB4Z3BEHhjfNJCx07UI'
        Write-Host 'Do not delete other keys. At the end remove ONLY this gateway key from Pageant.'
        Start-Process -FilePath $pageant -WindowStyle Normal | Out-Null
        $session.PageantRequested=$true
        if((Read-Host 'Type KEY-READY when the gateway key is loaded') -cne 'KEY-READY'){throw 'Gateway key not confirmed'}
        $auth=Probe 'Authenticated command-channel denial before proxy start' $plink ($sshArgs+@('-T','130.250.191.137','/usr/bin/true')) 20
        Assert-TunnelDenied $auth Session
    }
    Stage 'Guarded VPS window and independent stop timer' 20 {
        Set-Clipboard -Value $serverPayload
        Write-Host 'POWERSHELL: leave this window waiting. The VPS command is now on your clipboard.'
        Write-Host 'PUTTY: manually type sudo -v (do not copy it), then paste the clipboard command. Installer is NOT rerun.'
        Write-Host 'The corrected launcher verifies a private script file and preserves terminal input.'
        Write-Host 'PUTTY: when asked, type START-TEST and press ENTER there. Wait for START-TEST accepted and then SERVER_READY=...'
        Write-Host 'Only AFTER PuTTY prints SERVER_READY, copy that full output line into the PowerShell prompt below. Never run SERVER_READY as a PuTTY command.'
        $session.ServerRequested=$true
        if((Read-Host "POWERSHELL waiting: paste SERVER_READY=$runId only after PUTTY prints it (or type FAILED if the VPS test ends)") -cne "SERVER_READY=$runId"){throw 'Server readiness not confirmed'}
    }
    Stage 'Loopback-only allowed tunnel and Paytm TLS' 30 {
        $session.Tunnel=Start-Forward 'Allowed tunnel'
        Curl-Probe 'Allowed Paytm HEAD' 'https://developer.paytmmoney.com/' Tls
    }
    Stage 'PTY-requested session, wrong target and remote-forward denials' 45 {
        $result=Probe 'PTY-requested session denial' $plink ($sshArgs+@('-t','130.250.191.137','/usr/bin/true')) 20
        Assert-TunnelDenied $result Session
        $result=Probe 'Wrong destination 127.0.0.1:22' $plink ($sshArgs+@('-T','-nc','127.0.0.1:22','130.250.191.137')) 20
        Assert-TunnelDenied $result Destination
        $result=Probe 'Remote forwarding denial' $plink ($sshArgs+@('-T','-N','-R','127.0.0.1:19889:127.0.0.1:9','130.250.191.137')) 10
        Assert-TunnelDenied $result Remote
    }
    Stage 'Proxy allowlist, port and plaintext denials' 60 {
        foreach($url in @('https://example.com/','https://developer.paytmmoney.com.invalid/','https://developer.paytmmoney.com:80/','https://api.ipify.org/')){Curl-Probe "Denied $url" $url ConnectDenied}
        Curl-Probe 'Plain HTTP denied' 'http://developer.paytmmoney.com/' HttpDenied
    }
    Stage 'Closed tunnel refusal and fresh reconnect' 70 {
        $result=Complete-TunnelProcess $session.Tunnel -StopNow
        Assert-TunnelAuthenticated $result
        if(@(Get-TunnelListeners $LocalPort).Count){throw 'Listener remains after closing owned tunnel'}
        Curl-Probe 'Closed tunnel must refuse' 'https://developer.paytmmoney.com/' TunnelStopped
        $session.Tunnel=Start-Forward 'Reconnected tunnel'
        Curl-Probe 'Paytm HEAD after reconnect' 'https://developer.paytmmoney.com/' Tls
    }
    Stage 'Stop VPS proxy and capture consolidated server evidence' 80 { Collect-ServerStop }
    Stage 'Stopped backend cannot fall back; local tunnel cleanup' 90 {
        if($session.Tunnel.Process.HasExited){throw 'Tunnel unexpectedly exited; stopped-backend test is inconclusive'}
        Assert-TunnelListenerRows @(Get-TunnelListeners $LocalPort) $session.Tunnel.Process.Id -Port $LocalPort -Evidence $report.listenerEvidence -Label 'Stopped-backend listener'
        Curl-Probe 'Stopped VPS backend' 'https://developer.paytmmoney.com/' ProxyStopped
        $result=Complete-TunnelProcess $session.Tunnel -StopNow
        Assert-TunnelAuthenticated $result
        if($result.Stderr -notmatch '(?i)Forwarded connection refused by remote.*Connection refused'){throw 'Explicit backend connection-refused evidence missing'}
        if(@(Get-TunnelListeners $LocalPort).Count){throw 'Local listener remains'}
        $report.localCleanupConfirmed=$true
    }
    $passed=$true
} catch { $report.failure=$_.Exception.Message }
finally {
    foreach($handle in $handles) {
        try {$result=Complete-TunnelProcess $handle -StopNow; $report.processes+= [ordered]@{label=$handle.Label;result=$result}}
        catch {$passed=$false;$report.failure="Cleanup/capture: $($_.Exception.Message)"}
    }
    if($session.ServerRequested -and -not $report.serverEvidenceVerified) {
        Write-Warning 'Server completion needs review. STOP applies only to a still-running test prompt, not the Linux shell. Do not restart the proxy.'
        try {Collect-ServerStop} catch {$report.failure="$($report.failure); Server evidence: $($_.Exception.Message)"}
    }
    if($session.PageantRequested) {
        Write-Host 'In Pageant View Keys, remove ONLY the gateway key used for this test. Keep its encrypted PPK file and any unrelated keys.'
        try {$report.ownerGatewayKeyRemoved=((Read-Host 'Type KEY-REMOVED once done') -ceq 'KEY-REMOVED')} catch {$report.ownerGatewayKeyRemoved=$false}
    }
    try {if(@(Get-TunnelListeners $LocalPort).Count -eq 0){$report.localCleanupConfirmed=$true}} catch {$report.localCleanupConfirmed=$false}
    $report.status=if($passed -and $report.serverEvidenceVerified -and $report.localCleanupConfirmed -and $report.ownerGatewayKeyRemoved){'TUNNEL_BATCH_PASSED_APPLICATION_AND_AUTHENTICATION_PENDING'}else{'REVIEW_REQUIRED'}
    $watch.Stop(); Save-Report
    Write-Progress -Activity 'Paytm restricted tunnel verification' -Completed
    Write-Host "[100%] $($report.status); elapsed=$($report.elapsedSeconds)s"
    Write-Host "Share this ONE file: $reportPath"
    Write-Host 'Root HEAD 503, if observed, remains an API-readiness warning. No credentials, application routing or trades were tested.'
}
if($report.status -ne 'TUNNEL_BATCH_PASSED_APPLICATION_AND_AUTHENTICATION_PENDING'){throw "Review report: $($report.failure)"}
