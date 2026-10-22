# Real JDK compile, local proxy fixtures, packaging and temporary cleanup; Docker commands are mocked.
#Requires -Version 5.1
$ErrorActionPreference='Stop'; Set-StrictMode -Version Latest
. (Join-Path $PSScriptRoot 'PaytmTunnelVerification.ps1')
. (Join-Path $PSScriptRoot 'PaytmContainerRoute.ps1')
$runId=[guid]::NewGuid().ToString('N')
$fixtureId='a'*64
$route=[ordered]@{Root=(Resolve-Path (Join-Path $PSScriptRoot '../..')).Path;Docker=$null;Id=$null;Identity=$null;AppHash=$null;Work=$null;WorkCreated=$false;RemoteCreated=$false;RemoteDirectory=$null;Jar=$null;SourceHashes=@()}
$report=[ordered]@{containerProbeCleanupConfirmed=$false;applicationUnchanged=$false}
$ApplicationContainerId='';$JavaBinDirectory='';$LocalPort=18889
$TunnelEvidencePath=Join-Path ([IO.Path]::GetTempPath()) ('mb-route-fixture-'+$runId+'.json')
$lines=@("BEGIN_SERVER_REPORT_$runId")
foreach($name in @('SERVER_BEGIN','SERVER_TERMINAL_INPUT_OK','SERVER_START_CONFIRMED','SERVER_STOP_CONFIRMED','SERVER_HOST_IDENTITY_OK','SERVER_GATEWAY_POLICY_AND_KEY_OK','SERVER_CONFIG_UNCHANGED_INITIAL_STOPPED','SERVER_REMOTE_TEST_PORT_FREE','SERVER_READY','SERVER_STOPPED')){$lines+="$name=$runId"}
$lines+="SERVER_EXIT=0 RUN=$runId";$lines+="SERVER_REPORT_END=$runId WORKER_EXIT=0 LOG_EXIT=0 ELAPSED=1";$lines+="END_SERVER_REPORT_$runId"
$fixtureEvidence=@{runId=$runId;status='TUNNEL_BATCH_PASSED_APPLICATION_AND_AUTHENTICATION_PENDING';steps=@(1..9 | ForEach-Object {@{status='PASS'}});serverEvidenceVerified=$true;localCleanupConfirmed=$true;ownerGatewayKeyRemoved=$true;ordersEnabled=$false;brokerAuthenticationEnabled=$false;serverEvidence=($lines -join "`n")}
$fixtureBytes=[Text.Encoding]::UTF8.GetBytes(($fixtureEvidence | ConvertTo-Json -Depth 8))
$fixtureFile=[IO.File]::Open($TunnelEvidencePath,[IO.FileMode]::CreateNew)
try{$fixtureFile.Write($fixtureBytes,0,$fixtureBytes.Length)}finally{$fixtureFile.Dispose()}
$script:fixtureDockerCalls=New-Object 'Collections.Generic.List[object]'
function Invoke-RouteCommand([string]$Label,[string]$Executable,[string[]]$Arguments,[int]$Limit=30) {
    if($Executable -like '*docker.exe'){
        [void]$script:fixtureDockerCalls.Add([pscustomobject]@{Label=$Label;Arguments=$Arguments})
        $out=switch($Label){
            'Docker context name' {'fixture'}
            'Docker context local endpoint' {'npipe:////./pipe/docker_engine'}
            'Discover existing application container' {$fixtureId}
            'Selected application container identity' {"$fixtureId|true|fixture-start|sha256:fixture|marketbrain-service|$($route.Root)"}
            'Existing application jar hash' {('b'*64)+'  /app/app.jar'}
            'Confirm application jar unchanged' {('b'*64)+'  /app/app.jar'}
            'Container timeout availability' {'timeout fixture'}
            'Create unique temporary container probe directory' {''}
            'Copy credential-free probe jar' {
                if(-not (Test-Path -LiteralPath $Arguments[1]) -or $Arguments[2] -cne ($fixtureId+':/tmp/marketbrain-paytm-route-'+$runId+'/probe.jar')){throw 'Wrong copy boundary'}
                ''
            }
            'Verify container probe bytes' {$report.probeJarSha256+'  '+$route.RemoteDirectory+'/probe.jar'}
            'Remove only temporary container probe jar' {
                if($Arguments[-1] -cne ($route.RemoteDirectory+'/probe.jar') -or $Arguments -contains '-r'){throw 'Unsafe cleanup'}
                ''
            }
            'Remove empty probe directory' {''}
            default {throw "Unexpected Docker action: $Label"}
        }
        return [pscustomobject]@{Stdout=$out;Stderr='';ExitCode=0;StoppedByRunner=$false}
    }
    $handle=Start-TunnelProcess $Executable $Arguments
    $result=Complete-TunnelProcess $handle $Limit
    if($result.StoppedByRunner -or $result.ExitCode -ne 0){throw "Native preparation failed: $Label $($result.Stderr)"}
    $result
}
try {
    Initialize-PaytmContainerProbe
    if($report.routeLocalChecks.checks -ne 18 -or -not $route.RemoteCreated){throw 'Native preparation incomplete'}
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $zip=[IO.Compression.ZipFile]::OpenRead($route.Jar)
    try {
        $classes=@($zip.Entries | Where-Object FullName -like '*.class')
        if($classes.Count -ne 4 -or @($classes | Where-Object FullName -like '*Verification*').Count){throw 'Unexpected probe jar contents'}
    } finally {$zip.Dispose()}
    Complete-PaytmContainerProbe
    if(-not $report.containerProbeCleanupConfirmed -or -not $report.applicationUnchanged -or (Test-Path -LiteralPath $route.Work)){throw 'Preparation cleanup failed'}
    Write-Host 'PASS: native JDK preparation, 18 local proxy assertions, four-class jar, mocked copy/hash/identity and bounded cleanup. Docker NOT executed.'
} finally {
    if($route.WorkCreated -and (Test-Path -LiteralPath $route.Work)){Complete-PaytmContainerProbe}
    Remove-Item -LiteralPath $TunnelEvidencePath
}
