# Offline: all native Docker and listener calls mocked. Never changes network configuration.
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'PaperWriterPrivateBoundary.ps1')
$script:count=0
function Check([bool]$Value,[string]$Label){if(-not $Value){throw $Label};$script:count++}
function Snapshot([string]$Ip='127.0.0.1',[string]$Mode='marketbrain_default',[bool]$Running=$true){
    return [pscustomobject]@{running=$Running;networkMode=$Mode;ports=[pscustomobject]@{'8080/tcp'=@([pscustomobject]@{HostIp=$Ip;HostPort='8080'})}}
}
foreach($ip in @('127.0.0.1','::1')){Check ((Get-PaperPortAssessment (Snapshot $ip) '8080/tcp' '8080').loopbackBindingsObserved) 'Loopback binding'}
foreach($ip in @('0.0.0.0','::','192.168.0.2','')){Check (-not (Get-PaperPortAssessment (Snapshot $ip) '8080/tcp' '8080').loopbackBindingsObserved) 'Non-loopback binding'}
foreach($mode in @('host','none','container:abc','')){Check (-not (Get-PaperPortAssessment (Snapshot '127.0.0.1' $mode) '8080/tcp' '8080').loopbackBindingsObserved) 'Network mode'}
Check (-not (Get-PaperPortAssessment (Snapshot '127.0.0.1' 'bridge' $false) '8080/tcp' '8080').loopbackBindingsObserved) 'Stopped'
Check (-not (Get-PaperPortAssessment (Snapshot) '80/tcp' '8081').loopbackBindingsObserved) 'Missing expected port'
$empty=[pscustomobject]@{running=$true;networkMode='bridge';ports=$null}
Check (-not (Get-PaperPortAssessment $empty '8080/tcp' '8080').loopbackBindingsObserved) 'Empty ports'
$snapshot=Snapshot;$snapshot.ports.'8080/tcp'+=[pscustomobject]@{HostIp='0.0.0.0';HostPort='8080'}
Check (-not (Get-PaperPortAssessment $snapshot '8080/tcp' '8080').loopbackBindingsObserved) 'Mixed bindings'

# Simulate PowerShell 7 JSON/process behavior without invoking native tools locally.
$originalVersion=$PSVersionTable.PSVersion
try {
    $PSVersionTable.PSVersion=[version]'7.6.6'
    function Get-Command {param($Name,$CommandType,$ErrorAction);[pscustomobject]@{Source='C:\synthetic\docker.exe'}}
    function Get-NetTCPConnection {param($State,$LocalPort,$ErrorAction);if($script:mode -ceq 'listener-fail'){throw 'PRIVATE ERROR MUST NOT BE REPORTED'};[pscustomobject]@{LocalAddress='0.0.0.0';LocalPort=5432}}
    function Invoke-PaperCatalogProcess($Executable,$Arguments,$WorkingDirectory,$LimitSeconds){
        Check ($Executable -ceq 'C:\synthetic\docker.exe' -and $LimitSeconds -eq 15) 'Bounded exact executable'
        Check ($Arguments[0] -in @('ps','inspect','exec')) 'Only inspection operations'
        if($script:mode -ceq 'native-throw'){throw 'PRIVATE RAW ERROR'}
        $stdout='';$exit=0;$timedOut=$false
        if($script:mode -ceq 'timeout'){$timedOut=$true}
        if($script:mode -ceq 'native-fail'){$exit=1}
        switch($Arguments[0]){
            'ps' {$stdout=if($Arguments -contains 'label=com.docker.compose.service=marketbrain-service'){'abcdef012345'}else{'abcdef012346'}
                if($script:mode -ceq 'ambiguous'){$stdout="abcdef012345`nabcdef012347"}
                if($script:mode -ceq 'missing'){$stdout=''}
            }
            'inspect' {
                Check ($Arguments[2] -notmatch 'Env|Config\}\}') 'No environment dump'
                $s=Snapshot
                if($Arguments[3] -ceq 'abcdef012346'){$s.ports=[pscustomobject]@{'80/tcp'=@([pscustomobject]@{HostIp='127.0.0.1';HostPort='8081'})}}
                $stdout=$s|ConvertTo-Json -Depth 5 -Compress
                if($script:mode -ceq 'bad-json'){$stdout='not json'}
            }
            'exec' {
                Check ($Arguments[2] -ceq '/bin/sh' -and $Arguments[3] -ceq '-c') 'Fixed shell classification'
                Check ($Arguments[4] -notmatch 'PASSWORD|USERNAME|printenv|env\s') 'No secret output requested'
                $stdout=if($script:mode -ceq 'unknown-route'){'UNRECOGNIZED_ROUTE'}elseif($script:mode -ceq 'bad-route'){'untrusted-secret-output'}else{'SAME_MACHINE_HOST_ALIAS'}
            }
        }
        if($script:mode -ceq 'oversize'){$stdout='x'*65537}
        return [pscustomobject]@{stdout=$stdout;stderr='PRIVATE STDERR';exitCode=$exit;timedOut=$timedOut;elapsedSeconds=0.01}
    }
    foreach($script:mode in @('ok','unknown-route','bad-route','ambiguous','missing','bad-json','timeout','native-fail','native-throw','oversize','listener-fail')){
        $report=Get-PaperWriterPrivateBoundary
        if($script:mode -in @('ok','unknown-route')){
            Check ($report.status -ceq 'OBSERVATIONS_CAPTURED_REVIEW_REQUIRED') 'Captured only'
            Check ($report.containers.Count -eq 2 -and $report.steps.Count -eq 5) 'Both services and configured route'
            Check ($report.findings -contains 'DATABASE_NON_LOOPBACK_LISTENER_REQUIRES_HBA_FIREWALL_REVIEW') 'Wildcard is review not public proof'
            if($script:mode -ceq 'unknown-route'){Check ($report.findings -contains 'CONFIGURED_DATABASE_ROUTE_NEEDS_REVIEW') 'Unknown route flagged'}
        }else{Check ($report.status -ceq 'INCOMPLETE' -and $report.failureCode) 'Incomplete not accepted'}
        Check (-not $report.actualDatabaseSessionProven -and -not $report.activationAuthorized -and -not $report.firewallVerified -and -not $report.externalReachabilityTested) 'No invented proof or activation'
        $json=$report|ConvertTo-Json -Depth 12
        Check ($json -notmatch 'PRIVATE|untrusted-secret-output') 'No raw error or unrecognized output retained'
    }
} finally {$PSVersionTable.PSVersion=$originalVersion;Remove-Item Function:\Get-Command,Function:\Get-NetTCPConnection,Function:\Invoke-PaperCatalogProcess}
Write-Host "PASS: $script:count private-boundary assertions; all runtime access mocked."
