# Definitions only. Private Docker inspect/config and read tokens never enter report/process captures.
. (Join-Path $PSScriptRoot 'PaperRuntimeDeployment.ps1')
. (Join-Path $PSScriptRoot 'PaperAccountReadReview.ps1')
function ConvertFrom-PaytmPrivateJson([string]$Text) {
    try {return ($Text|ConvertFrom-Json)} catch {throw 'APP_ROUTE_PRIVATE_JSON_INVALID'}
}
function Invoke-PaytmPrivateDocker([string[]]$Arguments,[string]$Phase,[int]$Limit=30) {
    Write-Host "  Application route: $Phase"
    try {$v=Invoke-PaperRuntimeProcess $application.Docker $Arguments $route.Root $Limit}
    catch {throw "APP_ROUTE_NATIVE_EXCEPTION_$Phase"}
    [void]$report.applicationCommands.Add([ordered]@{phase=$Phase;exitCode=$v.exitCode;elapsedSeconds=$v.elapsedSeconds})
    Save-Report
    if($v.exitCode -ne 0){throw "APP_ROUTE_NATIVE_FAILED_$Phase"}
    return $v.stdout.Trim()
}
function Get-PaytmApplicationContainer {
    $id=Invoke-PaytmPrivateDocker @('ps','--filter','label=com.docker.compose.service=marketbrain-service','--format','{{.ID}}') 'LOCATE'
    if($id -cnotmatch '^[a-f0-9]{12,64}$'){throw 'APP_ROUTE_AMBIGUOUS_CONTAINER'}
    $rows=@(ConvertFrom-PaytmPrivateJson (Invoke-PaytmPrivateDocker @('inspect',$id) 'PRIVATE_INSPECT'))
    if($rows.Count -ne 1){throw 'APP_ROUTE_CONTAINER_COUNT'}
    Assert-PaperRuntimeContainer $rows[0] $route.Root -Memory
    return $rows[0]
}
function Invoke-PaytmApplicationHttp([string]$Command,[switch]$WithoutToken) {
    if($Command -cnotin @('status','arm','head','lock')){throw 'APP_ROUTE_INVALID_COMMAND'}
    $headers=@{'X-MarketBrain-Paytm-Route'='credential-free'}
    if(-not $WithoutToken){$headers['X-MarketBrain-Paper-Read-Token']=$application.Token}
    try {$response=Invoke-WebRequest -Uri ('http://127.0.0.1:8080/api/v1/paytm/route/'+$Command) -Method Post -Headers $headers -TimeoutSec 25 -MaximumRedirection 0 -SkipHttpErrorCheck}
    catch {throw 'APP_ROUTE_HTTP_UNAVAILABLE'}
    if($WithoutToken){if($response.StatusCode -ne 401){throw 'APP_ROUTE_AUTH_BOUNDARY'};return}
    if($response.StatusCode -ne 200 -or ($response.Headers['Cache-Control'] -join ',') -notmatch 'no-store'){throw 'APP_ROUTE_HTTP_CONTRACT'}
    $v=$response.Content | ConvertFrom-Json
    Assert-PaytmApplicationReceipt $v
    [void]$report.applicationObservations.Add([ordered]@{command=$Command;receipt=$v});Save-Report
    return $v
}
function Assert-PaytmApplicationReceipt($v) {
    if($v.version -cne 'PAYTM_APPLICATION_ROUTE_V1' -or $v.bootId -cnotmatch '^[a-f0-9-]{36}$' -or
        $v.state -cnotin @('LOCKED','ARMED') -or $v.applicationProcessVerified -isnot [bool] -or -not $v.applicationProcessVerified -or
        $v.credentialsUsed -isnot [bool] -or $v.credentialsUsed -or $v.ordersEnabled -isnot [bool] -or $v.ordersEnabled -or
        $v.tlsVerified -isnot [bool] -or $v.remainingRequests -lt 0 -or $v.remainingRequests -gt 4){throw 'APP_ROUTE_RECEIPT_CONTRACT'}
}
function Read-PaytmPaperAccount {
    try {$response=Invoke-WebRequest 'http://127.0.0.1:8080/api/v1/paper/account/overview' -Headers @{'X-MarketBrain-Paper-Read-Token'=$application.Token} -TimeoutSec 20 -MaximumRedirection 0}
    catch {throw 'APP_ROUTE_ACCOUNT_READ_FAILED'}
    if($response.StatusCode -ne 200 -or ($response.Headers['Cache-Control'] -join ',') -notmatch 'no-store'){throw 'APP_ROUTE_ACCOUNT_HEADERS'}
    $v=$response.Content|ConvertFrom-Json;Assert-PaperAttachmentPreflight $v
    if($v.ledger.status -cne 'ATTACHED_READ_ONLY'){throw 'APP_ROUTE_LEDGER_REQUIRED'}
    # Deliberately exclude observation time. Compare recorded account/ledger/history state, not market-data writes.
    return ([ordered]@{account=$v.account;ledger=$v.ledger;legacyOrders=$v.legacyOrdersPresent;legacyFills=$v.legacyFillsPresent}|ConvertTo-Json -Depth 6 -Compress)
}
function Assert-PaytmWriterLocked {
    $text=Invoke-PaytmPrivateDocker @('exec',$application.Id,'java','-Xmx32m','-cp','/app/control','in.marketbrain.paper.PaperRuntimeControl','STATUS') 'PAPER_WRITER_STATUS'
    Assert-PaperRuntimeControl ($text|ConvertFrom-Json) 'LOCKED'
}
function Wait-PaytmApplicationHealth {
    for($attempt=1;$attempt -le 30;$attempt++) {
        try {$h=Invoke-RestMethod 'http://127.0.0.1:8080/actuator/health' -TimeoutSec 5 -MaximumRedirection 0;if($h.status -ceq 'UP'){return}}catch{}
        Write-Host "Application health $attempt/30 not ready.";if($attempt -lt 30){Start-Sleep -Seconds 5}
    };throw 'APP_ROUTE_HEALTH_DEADLINE'
}
function Initialize-PaytmApplicationProbe {
    if($PSVersionTable.PSVersion.Major -lt 7){throw 'APP_ROUTE_REQUIRES_POWERSHELL_7'}
    if(-not $ContainerEvidencePath){throw 'APP_ROUTE_CONTAINER_EVIDENCE_REQUIRED'}
    $file=Get-Item -LiteralPath $ContainerEvidencePath
    if($file.Length -gt 262144){throw 'APP_ROUTE_EVIDENCE_BOUND'}
    $prior=Get-Content -LiteralPath $file.FullName -Raw|ConvertFrom-Json
    if($prior.status -cne 'CONTAINER_JVM_ROUTE_PASSED_APPLICATION_WIRING_PENDING' -or
       -not $prior.containerJvmRouteVerified -or -not $prior.applicationUnchanged -or -not $prior.containerProbeCleanupConfirmed -or
       -not $prior.serverEvidenceVerified -or -not $prior.localCleanupConfirmed -or -not $prior.ownerGatewayKeyRemoved -or
       @($prior.steps).Count -ne 7 -or @($prior.steps|Where-Object status -ne PASS).Count -ne 0 -or
       @($prior.containerRouteObservations).Count -ne 4){throw 'APP_ROUTE_PRIOR_EVIDENCE'}
    $null=Read-TunnelServerEvidence $prior.serverEvidence $prior.runId
    for($i=0;$i -lt 4;$i++){Assert-PaytmRouteObservation $prior.containerRouteObservations[$i].observation ($i -in @(0,2))}
    $report.acceptedContainerEvidence=[ordered]@{runId=$prior.runId;sha256=(Get-FileHash -LiteralPath $file.FullName).Hash}
    if($env:DOCKER_HOST){throw 'APP_ROUTE_REMOTE_DOCKER_OVERRIDE'}
    $application.Docker=(Get-Command docker.exe -CommandType Application -ErrorAction Stop|Select-Object -First 1).Source
    $context=Invoke-PaytmPrivateDocker @('context','show') 'CONTEXT'
    if((Invoke-PaytmPrivateDocker @('context','inspect',$context,'--format','{{.Endpoints.docker.Host}}') 'ENDPOINT') -notmatch '^npipe://'){throw 'APP_ROUTE_LOCAL_DOCKER_REQUIRED'}
    if(@(& git -C $route.Root status --porcelain).Count -or $LASTEXITCODE -ne 0){throw 'APP_ROUTE_CLEAN_CHECKOUT_REQUIRED'}
    & git -C $route.Root diff --quiet e5c541a HEAD -- marketbrain-service/src/main/resources/db/migration
    if($LASTEXITCODE -ne 0){throw 'APP_ROUTE_MIGRATION_REVIEW_REQUIRED'}
    $before=Get-PaytmApplicationContainer;$application.Id=$before.Id
    $report.priorContainerId=$before.Id;$report.priorImageId=$before.Image
    $envMap=ConvertTo-PaperRuntimeEnvironment $before.Config.Env
    if($envMap.MARKETBRAIN_PAYTM_ENABLED -cne 'false' -or $envMap.MARKETBRAIN_PAYTM_ACCESS_TOKEN){throw 'APP_ROUTE_BROKER_MUST_REMAIN_DISABLED'}
    foreach($key in @('JAVA_TOOL_OPTIONS','JDK_JAVA_OPTIONS','_JAVA_OPTIONS')){if($envMap[$key]){throw 'APP_ROUTE_JAVA_OVERRIDE_REVIEW'}}
    $application.Token=$envMap.MARKETBRAIN_PAPER_READ_TOKEN
    Assert-PaytmWriterLocked
    $application.BeforeAccount=Read-PaytmPaperAccount
    $report.accountBefore=$application.BeforeAccount|ConvertFrom-Json
    if((Read-Host 'Confirm all MarketBrain jobs are idle. Type DEPLOY_PAYTM_ROUTE to rebuild/recreate only the service and restart it once; daily alerts briefly pause') -cne 'DEPLOY_PAYTM_ROUTE'){throw 'APP_ROUTE_DEPLOY_NOT_CONFIRMED'}
    $image='marketbrain-paytm-route-'+$runId+':review';$project=$before.Config.Labels.'com.docker.compose.project'
    $saved=@{}
    try {
        $overrides=@{};foreach($key in $envMap.Keys){if($key -clike 'MARKETBRAIN_*'){$overrides[$key]=$envMap[$key]}}
        $overrides.MARKETBRAIN_PAPER_APPROVAL_KEY_HOST_FILE=ConvertTo-PaperHostMount (@($before.Mounts|Where-Object Destination -CEQ '/run/secrets/paper-approval.key')[0].Source)
        $overrides.MARKETBRAIN_PAPER_REVIEW_IMAGE=$image
        foreach($key in $overrides.Keys){$saved[$key]=[Environment]::GetEnvironmentVariable($key,'Process');[Environment]::SetEnvironmentVariable($key,$overrides[$key],'Process')}
        $compose=@('compose','--project-name',$project,'--env-file','.env','-f','compose.yaml','-f','compose.paper-storage.yaml','-f','compose.paper-review-memory.yaml')
        $plan=ConvertFrom-PaytmPrivateJson (Invoke-PaytmPrivateDocker ($compose+@('config','--format','json')) 'PRIVATE_COMPOSE_COMPARE')
        Assert-PaperRuntimeCompose $plan $before $envMap.MARKETBRAIN_PAPER_REVIEW_DATABASE_OID $image
        $null=Invoke-PaytmPrivateDocker @('build','-f','marketbrain-service/Dockerfile','-t',$image,'marketbrain-service') 'BUILD' 1800
        $report.imageId=Invoke-PaytmPrivateDocker @('image','inspect','--format','{{.Id}}',$image) 'IMAGE'
        if($report.imageId -cnotmatch '^sha256:[a-f0-9]{64}$'){throw 'APP_ROUTE_IMAGE_ID'}
        Assert-PaytmWriterLocked
        $current=Get-PaytmApplicationContainer
        if($current.Id -cne $before.Id -or $current.State.StartedAt -cne $before.State.StartedAt -or (Read-PaytmPaperAccount) -cne $application.BeforeAccount){throw 'APP_ROUTE_PRE_DEPLOY_DRIFT'}
        $report.deploymentAttempted=$true;Save-Report
        $null=Invoke-PaytmPrivateDocker ($compose+@('up','-d','--no-deps','--no-build','--pull','never','--force-recreate','marketbrain-service')) 'DEPLOY' 180
        Wait-PaytmApplicationHealth
        $after=Get-PaytmApplicationContainer;Assert-PaperRuntimePreserved $before $after
        if($after.Image -cne $report.imageId -or $after.Id -ceq $before.Id){throw 'APP_ROUTE_NEW_IMAGE_REQUIRED'}
        $application.Id=$after.Id;$application.Before=$after;$report.containerId=$after.Id
        Assert-PaytmWriterLocked
        if((Read-PaytmPaperAccount) -cne $application.BeforeAccount){throw 'APP_ROUTE_ACCOUNT_CHANGED'}
        Invoke-PaytmApplicationHttp 'status' -WithoutToken
        $state=Invoke-PaytmApplicationHttp 'status';if($state.state -cne 'LOCKED'){throw 'APP_ROUTE_STARTUP_NOT_LOCKED'}
        $application.BootId=$state.bootId;$application.Ready=$true
        $locked=Invoke-PaytmApplicationHttp 'head';if($locked.status -cne 'LOCKED'){throw 'APP_ROUTE_LOCKED_REQUEST_NOT_BLOCKED'}
        $report.startupLockedVerified=$true
    } finally {foreach($key in $saved.Keys){[Environment]::SetEnvironmentVariable($key,$saved[$key],'Process')}}
}
function Invoke-PaytmApplicationHead([string]$Label,[bool]$ExpectTls) {
    # Explicit diagnostic rearm. This never unlocks credentials or the paper writer.
    if($ExpectTls){$state=Invoke-PaytmApplicationHttp 'arm';if($state.state -cne 'ARMED'){throw 'APP_ROUTE_ARM_FAILED'}}
    $v=Invoke-PaytmApplicationHttp 'head'
    if($v.bootId -cne $application.BootId){throw 'APP_ROUTE_UNEXPECTED_RESTART'}
    if($ExpectTls){
        if($v.status -cne 'TLS_RESPONSE' -or -not $v.tlsVerified -or $v.httpStatus -lt 200 -or $v.httpStatus -gt 599 -or $v.failureType -cne 'NONE'){throw 'APP_ROUTE_TLS_FAILED'}
    }else{
        if($v.status -cne 'TRANSPORT_FAILED' -or $v.tlsVerified -or $v.httpStatus -ne 0 -or $v.state -cne 'LOCKED' -or $v.failureType -cnotin @('IOException','ConnectException','HttpConnectTimeoutException','HttpTimeoutException','SSLHandshakeException','SSLException')){throw 'APP_ROUTE_FAILURE_NOT_CLOSED'}
        if((Invoke-PaytmApplicationHttp 'head').status -cne 'LOCKED'){throw 'APP_ROUTE_FAILURE_LOCK_NOT_PRESERVED'}
    }
    [void]$report.applicationRouteChecks.Add([ordered]@{label=$Label;expectedTls=$ExpectTls;passed=$true});Save-Report
}
function Test-PaytmApplicationRestart {
    $armed=Invoke-PaytmApplicationHttp 'arm';if($armed.state -cne 'ARMED'){throw 'APP_ROUTE_RESTART_ARM_FAILED'}
    $null=Invoke-PaytmPrivateDocker @('restart','--time','30',$application.Id) 'RESTART' 90
    Wait-PaytmApplicationHealth
    $after=Get-PaytmApplicationContainer;Assert-PaperRuntimePreserved $application.Before $after
    if($after.Id -cne $application.Id -or $after.Image -cne $report.imageId -or $after.State.StartedAt -ceq $application.Before.State.StartedAt){throw 'APP_ROUTE_RESTART_IDENTITY'}
    $v=Invoke-PaytmApplicationHttp 'status'
    if($v.state -cne 'LOCKED' -or $v.bootId -ceq $application.BootId){throw 'APP_ROUTE_RESTART_DID_NOT_LOCK'}
    if((Invoke-PaytmApplicationHttp 'head').status -cne 'LOCKED'){throw 'APP_ROUTE_RESTART_HEAD_NOT_LOCKED'}
    Assert-PaytmWriterLocked
    $report.restartLockedVerified=$true
}
function Complete-PaytmApplicationProbe {
    try {
        if($report.deploymentAttempted){
            $v=Invoke-PaytmApplicationHttp 'lock';if($v.state -cne 'LOCKED'){throw 'APP_ROUTE_FINAL_LOCK_FAILED'}
            $report.finalApplicationLockVerified=$true
            if((Read-PaytmPaperAccount) -cne $application.BeforeAccount){throw 'APP_ROUTE_FINAL_ACCOUNT_CHANGED'}
            $report.accountPreserved=$true
        }
    } finally {$application.Token=$null}
}
