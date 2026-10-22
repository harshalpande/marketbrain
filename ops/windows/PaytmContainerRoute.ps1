# Sourceable route-probe helpers. Called by the bounded tunnel runner; never print container environment.
function Assert-PaytmRouteObservation($Value,[bool]$ExpectTls) {
    if($Value.version -cne 'PAYTM_CONTAINER_ROUTE_V1' -or $Value.proxyHost -cne 'host.docker.internal' -or
       $Value.proxyPort -ne 18889 -or $Value.applicationProcessVerified -isnot [bool] -or $Value.applicationProcessVerified -or
       $Value.credentialsUsed -isnot [bool] -or $Value.credentialsUsed -or $Value.ordersEnabled -isnot [bool] -or $Value.ordersEnabled -or
       $Value.tlsVerified -isnot [bool] -or $Value.elapsedMillis -lt 0 -or $Value.elapsedMillis -gt 30000){throw 'Unexpected container probe contract'}
    if($ExpectTls){
        if($Value.status -cne 'TLS_RESPONSE' -or -not $Value.tlsVerified -or $Value.httpStatus -lt 200 -or $Value.httpStatus -gt 599 -or $Value.failureType -cne 'NONE'){throw 'Container did not reach Paytm TLS through the required host gateway. Do not expose the Windows listener or enable direct fallback.'}
    } elseif($Value.status -cne 'TRANSPORT_FAILED' -or $Value.tlsVerified -or $Value.httpStatus -ne 0 -or $Value.failureType -cnotin @('IOException','ConnectException','HttpConnectTimeoutException','HttpTimeoutException','SSLHandshakeException','SSLException')) {
        throw 'Unavailable gateway did not produce a conclusive transport refusal'
    }
}
function Invoke-RouteCommand([string]$Label,[string]$Executable,[string[]]$Arguments,[int]$Limit=30) {
    Write-Host "  Route check: $Label"
    $result=Probe $Label $Executable $Arguments $Limit
    if($result.StoppedByRunner -or $result.ExitCode -ne 0){throw "Route step failed: $Label. See captured output; no automatic retry."}
    $result
}
function Get-PaytmContainerIdentity([string]$Id) {
    if($Id -cnotmatch '^[a-f0-9]{12,64}$'){throw 'Invalid application container ID'}
    $format='{{.Id}}|{{.State.Running}}|{{.State.StartedAt}}|{{.Image}}|{{index .Config.Labels "com.docker.compose.service"}}|{{index .Config.Labels "com.docker.compose.project.working_dir"}}'
    $value=Invoke-RouteCommand 'Selected application container identity' $route.Docker @('inspect','--format',$format,$Id)
    $parts=$value.Stdout.Trim().Split('|')
    if($parts.Count -ne 6 -or $parts[0] -cnotmatch '^[a-f0-9]{64}$' -or $parts[1] -cne 'true' -or
       $parts[4] -cne 'marketbrain-service' -or $parts[5].TrimEnd('\','/') -ine $route.Root.TrimEnd('\','/')){throw 'Container is not the running MarketBrain service from this checkout'}
    [pscustomobject]@{id=$parts[0];startedAt=$parts[2];image=$parts[3];service=$parts[4]}
}
function Initialize-PaytmContainerProbe {
    if($LocalPort -ne 18889){throw 'Container route probe is restricted to local port 18889'}
    if(-not $TunnelEvidencePath){throw 'Provide -TunnelEvidencePath to the accepted tunnel JSON'}
    foreach($name in @('JAVA_TOOL_OPTIONS','JDK_JAVA_OPTIONS','_JAVA_OPTIONS')){
        if([Environment]::GetEnvironmentVariable($name)){throw "Local $name override requires review before compiling the probe; value not recorded"}
    }
    $file=Get-Item -LiteralPath $TunnelEvidencePath
    if($file.Length -gt 262144){throw 'Tunnel evidence exceeds bound'}
    $accepted=Get-Content -LiteralPath $file.FullName -Raw | ConvertFrom-Json
    if($accepted.status -cne 'TUNNEL_BATCH_PASSED_APPLICATION_AND_AUTHENTICATION_PENDING' -or
       @($accepted.steps).Count -ne 9 -or @($accepted.steps | Where-Object status -ne PASS).Count -ne 0 -or
       -not $accepted.serverEvidenceVerified -or -not $accepted.localCleanupConfirmed -or -not $accepted.ownerGatewayKeyRemoved -or
       $accepted.ordersEnabled -or $accepted.brokerAuthenticationEnabled -or $accepted.runId -cnotmatch '^[a-f0-9]{32}$'){throw 'Prior tunnel acceptance evidence is incomplete'}
    $null=Read-TunnelServerEvidence $accepted.serverEvidence $accepted.runId
    $report.acceptedTunnelEvidence=[ordered]@{runId=$accepted.runId;sha256=(Get-FileHash -LiteralPath $file.FullName -Algorithm SHA256).Hash}
    if($env:DOCKER_HOST){throw 'DOCKER_HOST override must be reviewed before selecting a local application container'}
    $route.Docker=(Get-Command docker.exe -CommandType Application -ErrorAction Stop | Select-Object -First 1).Source
    $context=Invoke-RouteCommand 'Docker context name' $route.Docker @('context','show')
    $endpoint=Invoke-RouteCommand 'Docker context local endpoint' $route.Docker @('context','inspect',$context.Stdout.Trim(),'--format','{{.Endpoints.docker.Host}}')
    if($endpoint.Stdout.Trim() -notmatch '^npipe://'){throw 'Only a local Windows Docker named-pipe context is permitted'}
    if(-not $ApplicationContainerId){
        $selection=Invoke-RouteCommand 'Discover existing application container' $route.Docker @('ps','--no-trunc','--filter','label=com.docker.compose.service=marketbrain-service','--format','{{.ID}}')
        $ids=@($selection.Stdout.Trim() -split '\r?\n' | Where-Object {$_})
        if($ids.Count -ne 1){throw 'Expected one application container. Supply -ApplicationContainerId only after reviewing selection.'}
        $ApplicationContainerId=$ids[0]
    }
    $route.Identity=Get-PaytmContainerIdentity $ApplicationContainerId
    $route.Id=$route.Identity.id
    $report.containerIdentity=$route.Identity
    $appHash=Invoke-RouteCommand 'Existing application jar hash' $route.Docker @('exec',$route.Id,'sha256sum','/app/app.jar')
    if($appHash.Stdout -notmatch '^([a-f0-9]{64})\s+/app/app.jar\s*$'){throw 'Cannot verify existing application artifact'}
    $route.AppHash=$Matches[1]; $report.applicationJarSha256=$route.AppHash
    $null=Invoke-RouteCommand 'Container timeout availability' $route.Docker @('exec',$route.Id,'timeout','--version')
    if(-not $JavaBinDirectory){$JavaBinDirectory=Split-Path -Parent (Get-Command javac.exe -CommandType Application -ErrorAction Stop | Select-Object -First 1).Source}
    $javac=Join-Path $JavaBinDirectory 'javac.exe'; $java=Join-Path $JavaBinDirectory 'java.exe'; $jar=Join-Path $JavaBinDirectory 'jar.exe'
    foreach($tool in @($javac,$java,$jar)){if(-not (Test-Path -LiteralPath $tool -PathType Leaf)){throw 'Native JDK 21+ javac/java/jar are required; nothing is installed automatically'}}
    $version=Invoke-RouteCommand 'Native compiler version' $javac @('-version')
    if(($version.Stdout+$version.Stderr) -notmatch 'javac\s+(\d+)' -or [int]$Matches[1] -lt 21){throw 'JDK 21+ required'}
    $route.Work=Join-Path ([IO.Path]::GetTempPath()) ('marketbrain-container-route-'+$runId)
    if(Test-Path -LiteralPath $route.Work){throw 'Refusing to reuse a temporary path'}
    [void][IO.Directory]::CreateDirectory($route.Work); $route.WorkCreated=$true
    $classes=Join-Path $route.Work 'classes'; [void][IO.Directory]::CreateDirectory($classes)
    $sources=@('marketbrain-service/src/main/java/in/marketbrain/marketdata/paytm/PaytmGatewayTransport.java',
        'marketbrain-service/src/main/java/in/marketbrain/marketdata/paytm/PaytmGatewayProbe.java',
        'marketbrain-service/src/test/java/in/marketbrain/marketdata/paytm/PaytmRouteVerification.java')
    $paths=@($sources | ForEach-Object {Join-Path $route.Root $_})
    $route.SourceHashes=@($paths | ForEach-Object {(Get-FileHash -LiteralPath $_ -Algorithm SHA256).Hash})
    $report.probeSources=@(for($i=0;$i -lt $sources.Count;$i++){[ordered]@{path=$sources[$i];sha256=$route.SourceHashes[$i]}})
    $null=Invoke-RouteCommand 'Compile credential-free route probe' $javac (@('-J-Xmx256m','--release','21','-encoding','UTF-8','-d',$classes)+$paths) 60
    $verification=Invoke-RouteCommand 'Local required-proxy negative fixtures' $java @('-Xmx96m','-cp',$classes,'in.marketbrain.marketdata.paytm.PaytmRouteVerification','--local-only') 40
    $report.routeLocalChecks=$verification.Stdout | ConvertFrom-Json
    if($report.routeLocalChecks.version -cne 'PAYTM_ROUTE_LOCAL_V1' -or $report.routeLocalChecks.checks -ne 18 -or $report.routeLocalChecks.passed -ne $true -or $report.routeLocalChecks.externalCalls -ne 0){throw 'Local route fixture contract failed'}
    for($i=0;$i -lt $paths.Count;$i++){if((Get-FileHash -LiteralPath $paths[$i]).Hash -cne $route.SourceHashes[$i]){throw 'Probe source changed during compilation'}}
    $route.Jar=Join-Path $route.Work 'probe.jar'
    $jarArgs=@('--create','--file',$route.Jar)
    foreach($class in @(Get-ChildItem -LiteralPath (Join-Path $classes 'in/marketbrain/marketdata/paytm') -Filter 'PaytmGateway*.class')){
        $jarArgs+=@('-C',$classes,('in/marketbrain/marketdata/paytm/'+$class.Name))
    }
    $null=Invoke-RouteCommand 'Package probe classes only' $jar $jarArgs
    $report.probeJarSha256=(Get-FileHash -LiteralPath $route.Jar).Hash.ToLowerInvariant()
    $route.RemoteDirectory='/tmp/marketbrain-paytm-route-'+$runId
    $null=Invoke-RouteCommand 'Create unique temporary container probe directory' $route.Docker @('exec',$route.Id,'mkdir','-m','700','--',$route.RemoteDirectory)
    $route.RemoteCreated=$true
    $null=Invoke-RouteCommand 'Copy credential-free probe jar' $route.Docker @('cp',$route.Jar,($route.Id+':'+$route.RemoteDirectory+'/probe.jar'))
    $hash=Invoke-RouteCommand 'Verify container probe bytes' $route.Docker @('exec',$route.Id,'sha256sum',($route.RemoteDirectory+'/probe.jar'))
    if($hash.Stdout.Split(' ')[0] -cne $report.probeJarSha256){throw 'Container probe hash mismatch'}
}
function Invoke-PaytmContainerHead([string]$Label,[bool]$ExpectTls) {
    $identity=Get-PaytmContainerIdentity $route.Id
    if($identity.startedAt -cne $route.Identity.startedAt -or $identity.image -cne $route.Identity.image){throw 'Application container changed during probe'}
    $result=Invoke-RouteCommand $Label $route.Docker @('exec','-e','JAVA_TOOL_OPTIONS=','-e','JDK_JAVA_OPTIONS=','-e','_JAVA_OPTIONS=',
        $route.Id,'timeout','-s','KILL','25s','java','-Xmx64m','-cp',($route.RemoteDirectory+'/probe.jar'),
        'in.marketbrain.marketdata.paytm.PaytmGatewayProbe','--credential-free-container-head','18889') 35
    $observation=$result.Stdout | ConvertFrom-Json
    [void]$report.containerRouteObservations.Add([ordered]@{label=$Label;expectedTls=$ExpectTls;observation=$observation})
    Save-Report
    Assert-PaytmRouteObservation $observation $ExpectTls
}
function Complete-PaytmContainerProbe {
    try {
        if($route.RemoteCreated){
            if($route.RemoteDirectory -cne ('/tmp/marketbrain-paytm-route-'+$runId)){throw 'Unexpected probe cleanup target'}
            $null=Invoke-RouteCommand 'Remove only temporary container probe jar' $route.Docker @('exec',$route.Id,'rm','-f','--',($route.RemoteDirectory+'/probe.jar'))
            $null=Invoke-RouteCommand 'Remove empty probe directory' $route.Docker @('exec',$route.Id,'rmdir','--',$route.RemoteDirectory)
        }
        if($route.Id){
            $identity=Get-PaytmContainerIdentity $route.Id
            $hash=Invoke-RouteCommand 'Confirm application jar unchanged' $route.Docker @('exec',$route.Id,'sha256sum','/app/app.jar')
            if($identity.startedAt -cne $route.Identity.startedAt -or $identity.image -cne $route.Identity.image -or $hash.Stdout.Split(' ')[0] -cne $route.AppHash){throw 'Application identity/artifact changed during test'}
            $report.applicationUnchanged=$true
        }
        $report.containerProbeCleanupConfirmed=$true
    } finally {
        if($route.WorkCreated){
            $expected=[IO.Path]::GetFullPath((Join-Path ([IO.Path]::GetTempPath()) ('marketbrain-container-route-'+$runId)))
            $actual=(Resolve-Path -LiteralPath $route.Work).Path
            if($actual -cne $expected -or (Get-Item -LiteralPath $actual).Attributes -band [IO.FileAttributes]::ReparsePoint){throw 'Temporary local probe identity changed; retained'}
            Remove-Item -LiteralPath $actual -Recurse -Force
        }
    }
}
