#Requires -Version 5.1
$ErrorActionPreference='Stop'; Set-StrictMode -Version Latest
. (Join-Path $PSScriptRoot 'PaytmTunnelVerification.ps1')
$checks=0
function Check([bool]$Condition,[string]$Message){if(-not $Condition){throw $Message};$script:checks++}
function Reject([scriptblock]$Action){$failed=$false;try{& $Action | Out-Null}catch{$failed=$true};Check $failed 'Unexpected success'}
function Result([int]$Code,[string]$Out,[string]$Err='', [bool]$Stopped=$false){[pscustomobject]@{ExitCode=$Code;Stdout=$Out;Stderr=$Err;StoppedByRunner=$Stopped}}
Check ((ConvertTo-TunnelArgument '') -ceq '""') 'Empty argument lost'
Check ((ConvertTo-TunnelArgument 'C:\path with spaces\') -ceq '"C:\path with spaces\\"') 'Trailing slash quoting'
Check ((ConvertTo-TunnelArgument 'a"b') -ceq '"a\"b"') 'Quote escaping'
Reject {ConvertTo-TunnelArgument "a`nb"}; Reject {ConvertTo-TunnelArgument ([string][char]0)}
$base=Get-TunnelBaseArguments 'public-key.pub'
foreach($flag in @('-batch','-noshare','-agent','-a','-x','-no-trivial-auth','-hostkey','-i')){Check ($base -contains $flag) "Missing $flag"}
Check ($base -contains 'marketbrain-gateway') 'Wrong username'
Check ($base -contains 'SHA256:YTQ8GV8J4qOQkY4j3dGGyCTAzyR2iX/KSJoGK0p2dKI') 'Host pin missing'
Check (-not ($base -contains '-pw')) 'Password command line forbidden'
$auth="Access granted`n"
foreach($kind in @('Session','Destination','Remote')) {
    $message=switch($kind){Session {'Server refused to open main channel: open failed'};Destination {'Server refused to open main channel: Administratively prohibited'};Remote {'Remote port forwarding from 127.0.0.1:19889 refused'}}
    $stopped=$kind -eq 'Remote'
    Assert-TunnelDenied (Result 1 '' ($auth+$message) $stopped) $kind; $checks++
    Reject {Assert-TunnelDenied (Result 1 '' $message $stopped) $kind}
    Reject {Assert-TunnelDenied (Result 1 '' ($auth+'Network error: connection reset') $stopped) $kind}
    Reject {Assert-TunnelDenied (Result 1 'unexpected output' ($auth+$message) $stopped) $kind}
}
Reject {Assert-TunnelDenied (Result 0 '' ($auth+'Server refused to open main channel')) Session}
Reject {Assert-TunnelDenied (Result 1 '' ($auth+'Server refused to open main channel') $true) Session}
foreach($status in @('200','301','403','503')){Assert-TunnelCurl (Result 0 "200|0|$status") Tls; $checks++}
foreach($bad in @((Result 0 '200|1|200'),(Result 0 '000|0|200'),(Result 56 '200|0|200'),(Result 0 '200|0|200' '' $true))){Reject {Assert-TunnelCurl $bad Tls}}
$cases=@(@('ConnectDenied',56,'403|0|000'),@('HttpDenied',0,'000|0|403'),@('TunnelStopped',7,'000|0|000'),@('ProxyStopped',56,'000|0|000'),@('ProxyStopped',52,'000|0|000'))
foreach($case in $cases){Assert-TunnelCurl (Result $case[1] $case[2]) $case[0];$checks++;Reject {Assert-TunnelCurl (Result 28 '000|0|000') $case[0]}}
Reject {Assert-TunnelCurl (Result 0 '200|0|200') ProxyStopped}
$curl=Get-TunnelCurlArguments 18889 'https://developer.paytmmoney.com/'
Check ($curl[0] -ceq '-q') 'Curl startup config not disabled'
Check ($curl -contains 'http://127.0.0.1:18889') 'Proxy not explicit'
Check ($curl[([array]::IndexOf($curl,'--noproxy')+1)] -ceq '') 'no_proxy bypass not cleared'
Check (-not ($curl -contains '-k')) 'TLS verification disabled'
Assert-TunnelDefaults $null;$checks++
Assert-TunnelDefaults ([pscustomobject]@{ProxyMethod=0;LogType=0;PortForwardings=''});$checks++
foreach($name in @('ProxyMethod','LogType','LocalPortAcceptAll','RemotePortAcceptAll','PortForwardings','RemoteCommand','RemoteCommand2')){Reject {Assert-TunnelDefaults ([pscustomobject]@{$name=1})}}
$row=[pscustomobject]@{LocalAddress='127.0.0.1';OwningProcess=123}
Assert-TunnelListenerRows @($row) 123;$checks++
Reject {Assert-TunnelListenerRows @() 123}; Reject {Assert-TunnelListenerRows @($row,$row) 123}; Reject {Assert-TunnelListenerRows @($row) 456}
foreach($address in @('0.0.0.0','::','::1','192.168.1.2')){Reject {Assert-TunnelListenerRows @([pscustomobject]@{LocalAddress=$address;OwningProcess=123}) 123}}
$run='0123456789abcdef0123456789abcdef'
$payload=Get-TunnelServerPayload $run
Check ($payload.StartsWith('sudo -n env SSH_CONNECTION="$SSH_CONNECTION" bash ')) 'sudo connection handoff missing'
Check ($payload.EndsWith("tw_main '$run'`nMARKETBRAIN_TUNNEL_WINDOW`n")) 'Wrong worker or delimiter'
Check (-not $payload.Contains('then tg_main "$@"')) 'Installer entry remains active'
Check (-not $payload.Contains('then pg_main "$@"')) 'Proxy installer entry remains active'
Check (-not $payload.Contains("`r")) 'CR in bash payload'
Check ($payload.Contains('--on-active=20m')) 'Independent watchdog missing'
Reject {Get-TunnelServerPayload "a'; reboot"}
$lines=@("BEGIN_SERVER_REPORT_$run")
foreach($name in @('SERVER_BEGIN','SERVER_HOST_IDENTITY_OK','SERVER_GATEWAY_POLICY_AND_KEY_OK','SERVER_CONFIG_UNCHANGED_INITIAL_STOPPED','SERVER_REMOTE_TEST_PORT_FREE','SERVER_READY','SERVER_STOPPED')){$lines+="$name=$run"}
$lines+="SERVER_EXIT=0 RUN=$run"; $lines+="SERVER_REPORT_END=$run WORKER_EXIT=0 LOG_EXIT=0 ELAPSED=12"; $lines+="END_SERVER_REPORT_$run"
$valid=$lines -join "`n"
$parsed=Read-TunnelServerEvidence $valid $run
Check ($parsed -ceq $valid) 'Valid evidence rejected'
foreach($line in $lines){Reject {Read-TunnelServerEvidence ($valid.Replace($line,'')) $run}}
Reject {Read-TunnelServerEvidence ($valid.Replace('SERVER_EXIT=0','SERVER_EXIT=1')) $run}
Reject {Read-TunnelServerEvidence ($valid.Replace('LOG_EXIT=0','LOG_EXIT=1')) $run}
Reject {Read-TunnelServerEvidence ($valid.Replace("END_SERVER_REPORT_$run","SERVER_ERROR fixture`nEND_SERVER_REPORT_$run")) $run}
Reject {Read-TunnelServerEvidence $valid ('f'*32)}
Reject {Read-TunnelServerEvidence ('x'*32769) $run}

# Real local child-process checks, no SSH/network, service or credential operations.
$powershell=Join-Path $PSHOME 'powershell.exe'
if(-not (Test-Path -LiteralPath $powershell)){$powershell=Join-Path $PSHOME 'pwsh.exe'}
$command='[Console]::Out.Write("local-out"); [Console]::Error.Write("local-err"); exit 7'
$encoded=[Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($command))
$handle=Start-TunnelProcess $powershell @('-NoProfile','-NonInteractive','-EncodedCommand',$encoded)
$result=Complete-TunnelProcess $handle 15
Check ($result.ExitCode -eq 7 -and $result.Stdout -ceq 'local-out' -and $result.Stderr -ceq 'local-err' -and -not $result.StoppedByRunner) 'Native exit/stdout/stderr capture'
Check ((Complete-TunnelProcess $handle -StopNow) -eq $result) 'Repeated cleanup should be idempotent'
$encoded=[Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes('Start-Sleep -Seconds 20'))
$handle=Start-TunnelProcess $powershell @('-NoProfile','-NonInteractive','-EncodedCommand',$encoded)
$result=Complete-TunnelProcess $handle 1
Check $result.StoppedByRunner 'Bounded process termination failed'
Write-Host "PASS: $checks assertions including local native-process capture/timeout. No VPS, Pageant unlock or real tunnel used."
