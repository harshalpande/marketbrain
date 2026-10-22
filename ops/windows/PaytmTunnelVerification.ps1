#Requires -Version 5.1
# Sourceable, no side effects. No PPK/password loading, saved-session or registry writes.
function ConvertTo-TunnelArgument([string]$Value) {
    if($Value -match "[\r\n\x00]"){throw 'Unsafe native argument'}
    '"'+[regex]::Replace([regex]::Replace($Value,'(\\*)"','$1$1\"'),'(\\+)$','$1$1')+'"'
}
function Start-TunnelProcess([string]$Executable,[string[]]$Arguments) {
    $info=New-Object Diagnostics.ProcessStartInfo
    $info.FileName=$Executable
    $info.Arguments=($Arguments | ForEach-Object {ConvertTo-TunnelArgument $_}) -join ' '
    $info.UseShellExecute=$false; $info.CreateNoWindow=$true
    $info.RedirectStandardOutput=$true; $info.RedirectStandardError=$true; $info.RedirectStandardInput=$true
    # Empty proxy-related environment is not sufficient alone: every curl also has explicit proxy/no-proxy flags.
    foreach($name in @('HTTP_PROXY','HTTPS_PROXY','ALL_PROXY','NO_PROXY')){$info.EnvironmentVariables.Remove($name)}
    $process=New-Object Diagnostics.Process; $process.StartInfo=$info
    $started=$false
    try {
        if(-not $process.Start()){throw 'Native process did not start'}
        $started=$true
        $out=$process.StandardOutput.ReadToEndAsync(); $err=$process.StandardError.ReadToEndAsync()
        $process.StandardInput.Close()
        [pscustomobject]@{Process=$process; Out=$out; Err=$err; Watch=[Diagnostics.Stopwatch]::StartNew(); Result=$null}
    } catch {
        try {if($started -and -not $process.HasExited){$process.Kill();[void]$process.WaitForExit(5000)}}
        finally {$process.Dispose()}
        throw
    }
}
function Complete-TunnelProcess($Handle,[int]$LimitSeconds=20,[switch]$StopNow) {
    if($null -ne $Handle.Result){return $Handle.Result}
    $stopped=$false
    if(-not $Handle.Process.HasExited) {
        if($StopNow -or -not $Handle.Process.WaitForExit($LimitSeconds*1000)) {
            $stopped=$true
            $Handle.Process.Kill() # Exact Process handle owned by this run; never by name.
            if(-not $Handle.Process.WaitForExit(5000)){throw 'Owned process did not stop'}
        }
    }
    if(-not $Handle.Out.Wait(5000) -or -not $Handle.Err.Wait(5000)){throw 'Native output capture incomplete'}
    $stdout=$Handle.Out.Result; $stderr=$Handle.Err.Result
    if($stdout.Length -gt 131072 -or $stderr.Length -gt 131072){throw 'Unexpectedly large native output; review required'}
    $Handle.Watch.Stop()
    $Handle.Result=[pscustomobject]@{ExitCode=$Handle.Process.ExitCode; StoppedByRunner=$stopped; Stdout=$stdout; Stderr=$stderr; ElapsedSeconds=[math]::Round($Handle.Watch.Elapsed.TotalSeconds,3)}
    $Handle.Process.Dispose()
    $Handle.Result
}
function Get-TunnelBaseArguments([string]$PublicKeyFile) {
    @('-ssh','-2','-4','-P','22','-l','marketbrain-gateway','-batch','-v','-noshare','-agent','-a','-x','-no-trivial-auth',
      '-hostkey','SHA256:YTQ8GV8J4qOQkY4j3dGGyCTAzyR2iX/KSJoGK0p2dKI','-i',$PublicKeyFile)
}
function Assert-TunnelAuthenticated($Result) {
    if($Result.Stderr -notmatch '(?m)^Access granted\s*$'){throw 'SSH authentication success not established; this is NOT a passing denial test'}
}
function Assert-TunnelDenied($Result,[ValidateSet('Session','Remote','Destination')]$Kind) {
    Assert-TunnelAuthenticated $Result
    $pattern=switch($Kind){
        Session {'(?i)(Server refused to open main channel|Server refused to open a session|Unable to open (a )?session|session.*(open failed|refused)|Channel open failed.*(administratively prohibited|open failed))'}
        Remote {'(?i)Remote port forwarding.*(refused|failed)'}
        Destination {'(?i)(administratively prohibited|administratively disabled)'}
    }
    if($Result.Stderr -notmatch $pattern){throw "Explicit $Kind refusal missing; timeout or disconnect alone is not a pass"}
    if($Kind -ne 'Remote' -and ($Result.StoppedByRunner -or $Result.ExitCode -eq 0)){throw 'Expected completed failed SSH request'}
    if($Result.Stdout.Trim()){throw 'Unexpected remote session output'}
}
function Assert-TunnelCurl($Result,[ValidateSet('Tls','ConnectDenied','HttpDenied','TunnelStopped','ProxyStopped')]$Kind) {
    if($Result.StoppedByRunner){throw 'Probe timed out; not an accepted outcome'}
    $value=$Result.Stdout.Trim()
    $ok=switch($Kind){
        Tls { $Result.ExitCode -eq 0 -and $value -match '^200\|0\|[2-5][0-9][0-9]$' }
        ConnectDenied { $Result.ExitCode -eq 56 -and $value -eq '403|0|000' }
        HttpDenied { $Result.ExitCode -eq 0 -and $value -eq '000|0|403' }
        TunnelStopped { $Result.ExitCode -eq 7 -and $value -eq '000|0|000' }
        ProxyStopped { $Result.ExitCode -in @(52,56) -and $value -eq '000|0|000' }
    }
    if(-not $ok){throw "Unexpected $Kind probe: exit=$($Result.ExitCode), response=$value"}
}
function Get-TunnelCurlArguments([int]$Port,[string]$Url) {
    @('-q','--silent','--show-error','--head','--output','NUL','--connect-timeout','5','--max-time','15',
      '--proxy',"http://127.0.0.1:$Port",'--noproxy','','--write-out','%{http_connect}|%{ssl_verify_result}|%{http_code}',$Url)
}
function Assert-TunnelDefaults($Settings) {
    if($null -eq $Settings){return}
    foreach($name in @('ProxyMethod','LogType','LocalPortAcceptAll','RemotePortAcceptAll')) {
        if($Settings.PSObject.Properties[$name] -and [int]$Settings.$name -ne 0){throw "PuTTY Default Settings $name is non-default; review, do not overwrite"}
    }
    foreach($name in @('PortForwardings','RemoteCommand','RemoteCommand2')) {
        if($Settings.PSObject.Properties[$name] -and [string]$Settings.$name){throw "PuTTY Default Settings $name is configured; review required"}
    }
}
function Get-TunnelListeners([int]$Port) {
    # Query all listeners: missing-port lookup errors must not masquerade as inspection failure.
    @(Get-NetTCPConnection -State Listen -ErrorAction Stop | Where-Object {$_.LocalPort -eq $Port})
}
function Get-TunnelListenerAssessment($Rows,[int]$ProcessId,[int]$Port=0,[string]$Label='Listener') {
    $items=@($Rows | Where-Object {$null -ne $_})
    $observed=@(foreach($item in $items){
        [pscustomobject]@{
            localAddress=[string]$item.LocalAddress
            localPort=if($item.PSObject.Properties['LocalPort']){[int]$item.LocalPort}else{$null}
            owningProcess=[long]$item.OwningProcess
            state=if($item.PSObject.Properties['State']){[string]$item.State}else{$null}
        }
    })
    $reasons=@()
    if($items.Count -eq 0){$reasons+='MISSING'}
    if($items.Count -gt 1){$reasons+='MULTIPLE_LISTENERS'}
    foreach($row in $observed){
        if($row.localAddress -cne '127.0.0.1'){$reasons+='NON_LOOPBACK_ADDRESS'}
        if($row.owningProcess -ne $ProcessId){$reasons+='OWNER_PID_MISMATCH'}
        if($Port -gt 0 -and $row.localPort -ne $Port){$reasons+='PORT_MISMATCH'}
    }
    [pscustomobject]@{label=$Label;observedUtc=[DateTime]::UtcNow.ToString('o');expectedAddress='127.0.0.1';expectedPort=$Port;expectedProcessId=$ProcessId;rowCount=$items.Count;rows=$observed;reasons=@($reasons | Select-Object -Unique);valid=($reasons.Count -eq 0)}
}
function Assert-TunnelListenerAssessment($Assessment) {
    if(-not $Assessment.valid){
        throw ('Tunnel listener validation failed: '+($Assessment | ConvertTo-Json -Depth 5 -Compress))
    }
}
function Assert-TunnelListenerRows($Rows,[int]$ProcessId,[int]$Port=0,$Evidence=$null,[string]$Label='Listener') {
    $assessment=Get-TunnelListenerAssessment $Rows $ProcessId $Port $Label
    if($null -ne $Evidence){[void]$Evidence.Add($assessment)}
    Assert-TunnelListenerAssessment $assessment
}
function Wait-TunnelListener($Handle,[int]$Port,$Evidence=$null,[string]$Label='Listener readiness') {
    for($i=0;$i -lt 30;$i++) {
        if($Handle.Process.HasExited){throw 'Tunnel exited before listener became ready'}
        try {$rows=@(Get-TunnelListeners $Port)} catch {
            if($null -ne $Evidence){[void]$Evidence.Add([pscustomobject]@{label=$Label;observedUtc=[DateTime]::UtcNow.ToString('o');expectedPort=$Port;expectedProcessId=$Handle.Process.Id;queryError=$_.Exception.Message;valid=$false})}
            throw
        }
        $assessment=Get-TunnelListenerAssessment $rows $Handle.Process.Id $Port $Label
        if($null -ne $Evidence){[void]$Evidence.Add($assessment)}
        # Only absence is retried. An unexpected address, extra row or owner fails immediately.
        if($rows.Count){Assert-TunnelListenerAssessment $assessment; return}
        Start-Sleep -Milliseconds 500
    }
    throw 'Tunnel listener readiness timeout'
}
function New-TunnelFileLauncher([string]$Body) {
    if(-not $Body.EndsWith("`n") -or $Body.Length -gt 80000 -or $Body.Contains([char]0) -or $Body.Contains("`r") -or $Body.Contains('MARKETBRAIN_TUNNEL_FILE')){throw 'Unsafe staged script body'}
    $sha=[Security.Cryptography.SHA256]::Create()
    try {$digest=([BitConverter]::ToString($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($Body)))).Replace('-','').ToLowerInvariant()} finally {$sha.Dispose()}
    # The here-document belongs to cat INSIDE bash -c, never to sudo's stdin.
    # Preserve stdin as a terminal through sudo/use_pty and the file execution.
    $prepare=@'
set -Eeuo pipefail
export PATH=/usr/sbin:/usr/bin:/sbin:/bin LC_ALL=C
umask 077
[ "$(id -u)" = 0 ] || { printf 'LAUNCHER_ERROR: root required\n' >&2; exit 1; }
[ "${SUDO_USER:-}" = marketbrain-admin ] || { printf 'LAUNCHER_ERROR: use the administrator session\n' >&2; exit 1; }
[ -t 0 ] || { printf 'LAUNCHER_ERROR: stdin must be the PuTTY terminal\n' >&2; exit 1; }
mb_script_dir=$(mktemp -d /tmp/marketbrain-tunnel-script-XXXXXXXX)
cat >"$mb_script_dir/window.sh" <<'MARKETBRAIN_TUNNEL_FILE'
'@
    $prepare=$prepare.Replace("`r`n","`n") # Git's Windows checkout may use CRLF inside the here-string.
    $prepare=$prepare+"`n"+$Body+"MARKETBRAIN_TUNNEL_FILE`n"+
        "printf '%s  %s\n' '$digest' "+'"$mb_script_dir/window.sh" | sha256sum --check --status'+"`n"+
        'chmod 400 "$mb_script_dir/window.sh"'+"`n"+
        'printf "Private script verified: %s/window.sh\n" "$mb_script_dir"'+"`n"+
        'bash "$mb_script_dir/window.sh" </dev/tty'+"`n"
    # POSIX single-quote encoding: a literal apostrophe becomes '"'"'.
    $escapedQuote="'"+'"'+"'"+'"'+"'"
    $quoted="'"+$prepare.Replace("'",$escapedQuote)+"'"
    'sudo -n env SSH_CONNECTION="$SSH_CONNECTION" bash -c '+$quoted+' </dev/tty'+"`n"
}
function Get-TunnelServerPayload([string]$RunId) {
    if($RunId -cnotmatch '^[a-f0-9]{32}$'){throw 'Invalid run ID'}
    $parts=@()
    foreach($name in @('InstallPaytmTunnelIdentity.sh','StagePaytmLoopbackProxy.sh','RunPaytmTunnelWindow.sh')) {
        $path=Join-Path $PSScriptRoot "..\linux\$name"
        $body=[IO.File]::ReadAllText((Resolve-Path -LiteralPath $path).Path).Replace("`r`n","`n")
        if($body.Contains([char]0) -or $body.Contains('MARKETBRAIN_TUNNEL_WINDOW')){throw 'Unsafe source boundary'}
        if($name -ne 'RunPaytmTunnelWindow.sh') {
            $entry=if($name -eq 'InstallPaytmTunnelIdentity.sh'){'if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then tg_main "$@"; fi'}else{'if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then pg_main "$@"; fi'}
            if(-not $body.Contains($entry)){throw 'Unexpected source entry; refuse to compose remote payload'}
            $body=$body.Replace($entry,'')
        }
        $parts += $body
    }
    $body=($parts -join "`n")+"`ntw_main '$RunId'`n"
    if($body.Length -gt 80000){throw 'Unexpected payload size'}
    New-TunnelFileLauncher $body
}
function Read-TunnelServerEvidence([string]$Clipboard,[string]$RunId) {
    if($RunId -cnotmatch '^[a-f0-9]{32}$' -or $Clipboard.Length -gt 32768){throw 'Invalid server evidence size/run'}
    $text=$Clipboard.Replace("`r",'')
    $begin="BEGIN_SERVER_REPORT_$RunId"; $end="END_SERVER_REPORT_$RunId"
    $start=$text.IndexOf($begin,[StringComparison]::Ordinal); $finish=$text.IndexOf($end,[StringComparison]::Ordinal)
    if($start -lt 0 -or $finish -le $start){throw 'Copy the complete bounded server report, not terminal history'}
    $block=$text.Substring($start,$finish+$end.Length-$start)
    foreach($name in @('SERVER_BEGIN','SERVER_TERMINAL_INPUT_OK','SERVER_START_CONFIRMED','SERVER_STOP_CONFIRMED','SERVER_HOST_IDENTITY_OK','SERVER_GATEWAY_POLICY_AND_KEY_OK','SERVER_CONFIG_UNCHANGED_INITIAL_STOPPED','SERVER_REMOTE_TEST_PORT_FREE','SERVER_READY','SERVER_STOPPED')) {
        if($block -cnotmatch "(?m)^$name=$RunId`$"){throw "Missing server evidence marker: $name"}
    }
    if($block -cnotmatch "(?m)^SERVER_EXIT=0 RUN=$RunId`$" -or $block -cnotmatch "(?m)^SERVER_REPORT_END=$RunId WORKER_EXIT=0 LOG_EXIT=0 ELAPSED=\d+`$"){throw 'Server worker or log capture did not pass'}
    if($block -match 'SERVER_ERROR|SERVER_CLEANUP_FAILED'){throw 'Server failure present'}
    $block
}
