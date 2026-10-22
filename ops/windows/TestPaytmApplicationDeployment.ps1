#Requires -Version 7.0
# Runs the real deployment orchestration with synthetic Docker/HTTP boundaries only.
$ErrorActionPreference='Stop'
Set-StrictMode -Version Latest
. (Join-Path $PSScriptRoot 'PaytmTunnelVerification.ps1')
. (Join-Path $PSScriptRoot 'PaytmContainerRoute.ps1')
. (Join-Path $PSScriptRoot 'PaytmApplicationRoute.ps1')
# Reuse only the three synthetic builders, not the old deployment workflow itself.
$tokens=$null;$errors=$null
$ast=[Management.Automation.Language.Parser]::ParseFile((Join-Path $PSScriptRoot 'TestPaperRuntimeDeploymentWorkflow.ps1'),[ref]$tokens,[ref]$errors)
foreach($f in $ast.FindAll({param($a)$a -is [Management.Automation.Language.FunctionDefinitionAst] -and $a.Name -in @('Container','Plan','Account')},$true)){
    . ([scriptblock]::Create($f.Extent.Text))
}
$repo=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../..'));$route=@{Root=$repo}
function Save-Report {}
function git {$global:LASTEXITCODE=0}
function Get-Command {param($Name,$CommandType,$ErrorAction) return @{Source='synthetic-docker.exe'}}
function Get-Item {param($LiteralPath) return @{FullName='fixture-evidence';Length=100}}
function Get-FileHash {param($LiteralPath) return @{Hash=('a'*64)}}
function Get-Content {param($LiteralPath,[switch]$Raw) return ($evidence|ConvertTo-Json -Depth 12)}
function Read-Host {param($Prompt) if($scenario -eq 'cancel'){return 'NO'};return 'DEPLOY_PAYTM_ROUTE'}
function Start-Sleep {}
function Invoke-RestMethod {param($Uri,$TimeoutSec,$MaximumRedirection) if($scenario -eq 'health-failure'){throw 'fixture'};return @{status='UP'}}
function Invoke-WebRequest {param($Uri,$Headers,$TimeoutSec,$MaximumRedirection,$Method,[switch]$SkipHttpErrorCheck)
    if($MaximumRedirection -ne 0){throw 'redirect enabled'}
    if($Uri.EndsWith('/overview')){
        $a=Account
        if($scenario -eq 'account-drift' -and $script:fakeAppState.Deployed){$a.account.currentCash='99999.00'}
        return @{StatusCode=200;Headers=@{'Cache-Control'='no-store'};Content=($a|ConvertTo-Json -Depth 8)}
    }
    if(-not $Headers.ContainsKey('X-MarketBrain-Paper-Read-Token')){return @{StatusCode=401}}
    if($Headers['X-MarketBrain-Paytm-Route'] -cne 'credential-free'){throw 'marker missing'}
    $cmd=($Uri -split '/')[-1]
    if($cmd -eq 'arm'){$script:fakeAppState.Armed=$true}
    if($cmd -eq 'lock'){$script:fakeAppState.Armed=$false;if($scenario -eq 'final-lock-failure'){throw 'fixture'}}
    $status=switch($cmd){'head' {if($script:fakeAppState.Armed){'TLS_RESPONSE'}else{'LOCKED'}};'status' {'STATUS'};'arm' {'ARMED'};'lock' {'LOCKED'}}
    $v=@{version='PAYTM_APPLICATION_ROUTE_V1';bootId=$script:fakeAppState.Boot;state=$(if($script:fakeAppState.Armed){'ARMED'}else{'LOCKED'});status=$status;remainingRequests=0;httpStatus=0;tlsVerified=$false;failureType='NONE';applicationProcessVerified=$true;credentialsUsed=$false;ordersEnabled=$false}
    return @{StatusCode=200;Headers=@{'Cache-Control'='no-store'};Content=($v|ConvertTo-Json)}
}
function Invoke-PaperRuntimeProcess {param($Executable,$Arguments,$Directory,$LimitSeconds)
    $out='';$exit=0
    switch($Arguments[0]){
        'context' {$out=if($Arguments[1] -eq 'show'){'fixture'}else{'npipe:////./pipe/docker_engine'}}
        'ps' {$out=$script:fakeAppState.Current.Id}
        'inspect' {$out=$script:fakeAppState.Current|ConvertTo-Json -Depth 12}
        'exec' {$out=@{version='PAPER_RUNTIME_CONTROL_V1';state=$(if($scenario -eq 'writer-unlocked'){'UNLOCKED'}else{'LOCKED'});databaseAuthenticationVerified=$false;actionExecutionEnabled=$false}|ConvertTo-Json}
        'build' {if($scenario -eq 'build-failure'){$exit=1;$out='never-record-this-password'}}
        'image' {$out='sha256:'+('e'*64)}
        'compose' {
            if($Arguments -contains 'config'){
                $p=Plan $script:fakeAppState.Current $env:MARKETBRAIN_PAPER_REVIEW_IMAGE
                if($scenario -eq 'environment-drift'){$p.services.'marketbrain-service'.environment.MARKETBRAIN_DB_PASSWORD='changed'}
                $out=$p|ConvertTo-Json -Depth 12
            }elseif($Arguments -contains 'up'){
                $script:fakeAppState.Deployed=$true;$script:fakeAppState.Current.Id='c'*64;$script:fakeAppState.Current.Image='sha256:'+('e'*64);$script:fakeAppState.Current.State.StartedAt='second'
                if($scenario -eq 'deploy-failure'){$exit=1}
            }else{throw 'unexpected compose'}
        }
        'restart' {$script:fakeAppState.Restarted=$true;$script:fakeAppState.Current.State.StartedAt='third';if($scenario -ne 'restart-lock-failure'){$script:fakeAppState.Armed=$false;$script:fakeAppState.Boot='22222222-2222-2222-2222-222222222222'}}
        default {throw 'unexpected Docker command'}
    }
    return @{exitCode=$exit;stdout=$out;stderr='synthetic-private-output';elapsedSeconds=0.001}
}
$evidence=@{status='CONTAINER_JVM_ROUTE_PASSED_APPLICATION_WIRING_PENDING';runId=('b'*32);containerJvmRouteVerified=$true;applicationUnchanged=$true;containerProbeCleanupConfirmed=$true;serverEvidenceVerified=$true;localCleanupConfirmed=$true;ownerGatewayKeyRemoved=$true;steps=@(1..7|ForEach-Object{@{status='PASS'}});containerRouteObservations=@()}
$lines=@('BEGIN_SERVER_REPORT_'+$evidence.runId)
foreach($name in @('SERVER_BEGIN','SERVER_TERMINAL_INPUT_OK','SERVER_START_CONFIRMED','SERVER_STOP_CONFIRMED','SERVER_HOST_IDENTITY_OK','SERVER_GATEWAY_POLICY_AND_KEY_OK','SERVER_CONFIG_UNCHANGED_INITIAL_STOPPED','SERVER_REMOTE_TEST_PORT_FREE','SERVER_READY','SERVER_STOPPED')){$lines+="$name=$($evidence.runId)"}
$lines+="SERVER_EXIT=0 RUN=$($evidence.runId)";$lines+="SERVER_REPORT_END=$($evidence.runId) WORKER_EXIT=0 LOG_EXIT=0 ELAPSED=1";$lines+="END_SERVER_REPORT_$($evidence.runId)"
$evidence.serverEvidence=$lines -join "`n"
for($i=0;$i -lt 4;$i++){$tls=$i -in @(0,2);$evidence.containerRouteObservations+=@{observation=@{version='PAYTM_CONTAINER_ROUTE_V1';proxyHost='host.docker.internal';proxyPort=18889;applicationProcessVerified=$false;credentialsUsed=$false;ordersEnabled=$false;elapsedMillis=1;status=$(if($tls){'TLS_RESPONSE'}else{'TRANSPORT_FAILED'});httpStatus=$(if($tls){503}else{0});tlsVerified=$tls;failureType=$(if($tls){'NONE'}else{'ConnectException'})}}}
$count=0
foreach($scenario in @('pass','cancel','writer-unlocked','environment-drift','build-failure','deploy-failure','health-failure','account-drift','restart-lock-failure','final-lock-failure')){
    $runId=[guid]::NewGuid().ToString('N');$ContainerEvidencePath='fixture-evidence'
    $application=[ordered]@{Docker=$null;Id=$null;Token=$null;BeforeAccount=$null;Before=$null;BootId=$null;Ready=$false}
    $report=[ordered]@{deploymentAttempted=$false;applicationCommands=[Collections.Generic.List[object]]::new();applicationObservations=[Collections.Generic.List[object]]::new();applicationRouteChecks=[Collections.Generic.List[object]]::new();startupLockedVerified=$false;restartLockedVerified=$false;finalApplicationLockVerified=$false;accountPreserved=$false}
    $c=Container -Memory;$c.Config.Env+=@('MARKETBRAIN_PAYTM_ENABLED=false','MARKETBRAIN_PAYTM_ACCESS_TOKEN=')
    $script:fakeAppState=@{Current=$c;Deployed=$false;Restarted=$false;Armed=$false;Boot='11111111-1111-1111-1111-111111111111'}
    $original=[Environment]::GetEnvironmentVariable('MARKETBRAIN_DB_PASSWORD','Process');$failed=$false
    $reason=''
    try {Initialize-PaytmApplicationProbe;Test-PaytmApplicationRestart}catch{$failed=$true;$reason=$_.Exception.Message}
    finally {try{Complete-PaytmApplicationProbe}catch{$failed=$true;$reason+='; '+$_.Exception.Message}}
    if(($scenario -eq 'pass') -eq $failed){throw "Unexpected result: $scenario $reason"}
    if($scenario -eq 'pass' -and (-not $report.restartLockedVerified -or -not $report.accountPreserved -or -not $report.finalApplicationLockVerified)){throw 'incomplete successful deployment'}
    if($scenario -in @('cancel','writer-unlocked','environment-drift','build-failure') -and $script:fakeAppState.Deployed){throw 'mutation after preflight failure'}
    if([string][Environment]::GetEnvironmentVariable('MARKETBRAIN_DB_PASSWORD','Process') -cne [string]$original){throw 'environment not restored'}
    if(($report|ConvertTo-Json -Depth 14) -match 'never-record-this-password|synthetic-private-output'){throw 'secret output leaked'}
    if($application.Token){throw 'token retained'}
    $count++
}
Write-Host "PASS: $count real deployment orchestration scenarios with mocked Docker/HTTP, restoration and secret-free reporting."
