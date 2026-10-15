#Requires -Version 7.0
# Offline only. All Docker, HTTP, administrator and real credential boundaries are mocked.
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'PaperRuntimeDeployment.ps1')
. (Join-Path $PSScriptRoot 'PaperAccountReadReview.ps1')
. (Join-Path $PSScriptRoot 'NumericalHistoryEvidence.ps1')
$repo=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../..'));$count=0
function Check([bool]$Ok,[string]$Name){if(-not $Ok){throw "Failed: $Name"};$script:count++}
function Reject([scriptblock]$Body,[string]$Name){$failed=$false;try{& $Body}catch{$failed=$true};Check $failed $Name}
function Container([switch]$Memory) {
    $env=@{MARKETBRAIN_EXECUTION_MODE='PAPER';MARKETBRAIN_PAPER_APPROVAL_STORAGE_ENABLED='true';MARKETBRAIN_PAPER_APPROVAL_KEY_FILE='/run/secrets/paper-approval.key';MARKETBRAIN_PAPER_READ_TOKEN=('t'*64);MARKETBRAIN_DB_PASSWORD='never-record-this-password';MARKETBRAIN_TELEGRAM_ENABLED='true'}
    if($Memory){$p=Get-PaperRuntimePolicyEnvironment '123';foreach($k in $p.Keys){$env[$k]=$p[$k]}}
    $files=@('compose.yaml','compose.paper-storage.yaml');if($Memory){$files+='compose.paper-review-memory.yaml'}
    return [pscustomobject]@{Id=$(if($Memory){'b'*64}else{'a'*64});Image=$(if($Memory){'sha256:'+('c'*64)}else{'sha256:'+('d'*64)});State=[pscustomobject]@{Running=$true;Paused=$false;StartedAt='first'};Config=[pscustomobject]@{Env=@($env.Keys|ForEach-Object{$_+'='+$env[$_]});Labels=[pscustomobject]@{'com.docker.compose.service'='marketbrain-service';'com.docker.compose.project'='marketbrain';'com.docker.compose.project.working_dir'=$repo;'com.docker.compose.project.config_files'=(@($files|ForEach-Object{Join-Path $repo $_}) -join ',')}};HostConfig=[pscustomobject]@{Privileged=$false;NetworkMode='marketbrain_default';PortBindings=[pscustomobject]@{'8080/tcp'=@([pscustomobject]@{HostIp='127.0.0.1';HostPort='8080'})};Tmpfs=[pscustomobject]@{'/run/marketbrain-writer'='rw,noexec,nosuid,nodev,size=65536,mode=0700,uid=0,gid=0'}};Mounts=@([pscustomobject]@{Type='bind';Destination='/marketbrain-review';Source='C:/MarketBrainData/Review';RW=$true},[pscustomobject]@{Type='bind';Destination='/run/secrets/paper-approval.key';Source='C:/MarketBrainData/Secrets/PaperApproval/delivery.key';RW=$false})}
}
function Plan($Before,[string]$Image) {
    $env=ConvertTo-PaperRuntimeEnvironment $Before.Config.Env;$p=Get-PaperRuntimePolicyEnvironment '123';foreach($k in $p.Keys){$env[$k]=$p[$k]}
    return [pscustomobject]@{name='marketbrain';services=[pscustomobject]@{'marketbrain-service'=[pscustomobject]@{image=$Image;environment=[pscustomobject]$env;ports=@([pscustomobject]@{host_ip='127.0.0.1';published='8080';target=8080;protocol='tcp'});volumes=@([pscustomobject]@{type='bind';source='C:/MarketBrainData/Review';target='/marketbrain-review'},[pscustomobject]@{type='bind';source='C:/MarketBrainData/Secrets/PaperApproval/delivery.key';target='/run/secrets/paper-approval.key';read_only=$true});tmpfs=@('/run/marketbrain-writer:rw,noexec,nosuid,nodev,size=65536,mode=0700,uid=0,gid=0')}}}
}
$v=Container;Assert-PaperRuntimeContainer $v $repo;Assert-PaperRuntimeContainer (Container -Memory) $repo -Memory;Check $true 'base and memory container contracts'
Assert-PaperRuntimeCompose (Plan $v 'image') $v '123' 'image';Assert-PaperRuntimePreserved $v (Container -Memory);Check $true 'planned/applied preservation'
$normalized=Plan $v 'image'
foreach($key in @('command','entrypoint','network_mode','pid','user')){$normalized.services.'marketbrain-service'|Add-Member $key $null}
$normalized.services.'marketbrain-service'|Add-Member privileged $false
foreach($key in @('devices','cap_add')){$normalized.services.'marketbrain-service'|Add-Member $key @()}
Assert-PaperRuntimeCompose ($normalized|ConvertTo-Json -Depth 10|ConvertFrom-Json) $v '123' 'image'
Check $true 'normalized null false and empty additive lists accepted'
foreach($key in @('privileged','network_mode','pid','devices','cap_add','entrypoint','command','user')){
    $p=Plan $v 'image';$p.services.'marketbrain-service'|Add-Member $key $null
    Assert-PaperRuntimeCompose ($p|ConvertTo-Json -Depth 10|ConvertFrom-Json) $v '123' 'image'
    Check $true ('null default accepted: '+$key)
}
$invalid=@(
    @{key='privileged';value=$true},@{key='privileged';value='false'},@{key='privileged';value=0},
    @{key='network_mode';value='host'},@{key='network_mode';value=''},
    @{key='pid';value='host'},@{key='pid';value=''},
    @{key='devices';value=@('/dev/sda:/dev/sda')},@{key='devices';value=''},@{key='devices';value=@($null)},
    @{key='cap_add';value=@('SYS_ADMIN')},@{key='cap_add';value=''},@{key='cap_add';value=@{}},
    @{key='command';value='do-not-record-secret-value'},@{key='command';value=''},@{key='command';value=@()},@{key='command';value=$false},
    @{key='entrypoint';value=@('/bin/sh','do-not-record-secret-value')},@{key='entrypoint';value=''},@{key='entrypoint';value=@()},
    @{key='user';value='root'},@{key='user';value=''},@{key='user';value=@()}
)
foreach($case in $invalid){
    $p=Plan $v 'image';$p.services.'marketbrain-service'|Add-Member $case.key $case.value
    $failure=$null
    try{Assert-PaperRuntimeCompose ($p|ConvertTo-Json -Depth 10|ConvertFrom-Json) $v '123' 'image'}catch{$failure=$_.Exception.Message}
    Check ($failure -ceq ('DEPLOY_UNREVIEWED_CONTAINER_SETTING_'+$case.key.ToUpperInvariant())) ('reject typed override and name only: '+$case.key)
}
foreach($bad in @('C:/x/../y','/tmp/key','\\host\share')){Reject {ConvertTo-PaperHostMount $bad} 'unsafe mount rejected'}
foreach($p in @('C:\MarketBrainData\Review','/run/desktop/mnt/host/c/MarketBrainData/Review','/host_mnt/c/MarketBrainData/Review')){Check ((ConvertTo-PaperHostMount $p) -ceq 'c:/marketbraindata/review') 'Windows bind aliases'}
Reject {ConvertTo-PaperRuntimeEnvironment @('A=one','A=two')} 'duplicate environment'
foreach($mutate in @({param($x)$x.State.Running=$false},{param($x)$x.HostConfig.Privileged=$true},{param($x)$x.HostConfig.PortBindings.'8080/tcp'[0].HostIp='0.0.0.0'},{param($x)$x.Mounts[1].RW=$true},{param($x)$x.Config.Labels.'com.docker.compose.project.working_dir'='C:\elsewhere'})){$v=Container;& $mutate $v;Reject {Assert-PaperRuntimeContainer $v $repo} 'unsafe container'}
foreach($mutate in @({param($x)$x.services.'marketbrain-service'.environment.MARKETBRAIN_DB_PASSWORD='changed'},{param($x)$x.services.'marketbrain-service'.environment.MARKETBRAIN_PAPER_REVIEW_MAX_QUANTITY='2'},{param($x)$x.services.'marketbrain-service'.volumes[1].source='C:/wrong/key'},{param($x)$x.services.'marketbrain-service'.ports[0].host_ip='0.0.0.0'},{param($x)$x.services.'marketbrain-service'|Add-Member privileged $true})){$v=Container;$p=Plan $v 'image';& $mutate $p;Reject {Assert-PaperRuntimeCompose $p $v '123' 'image'} 'unsafe planned change'}
function Account {
    return @{version='PAPER_ACCOUNT_OVERVIEW_V2';status='READ_ONLY_EXECUTION_BLOCKED';currency='INR';databaseWritesPerformed=$false;actionExecutionEnabled=$false;liveExecutionEnabled=$false;activeAccountsObserved=1;activeAccountCountIsLowerBound=$false;legacyOrdersPresent=$false;legacyFillsPresent=$false;observedAtUtc='2026-10-15T00:00:00Z';migrationAssessment='LEDGER_ATTACHED_READ_ONLY';blockers=@('AUTHENTICATED_APPROVAL_AND_RISK_INTEGRATION_PENDING','FILL_COST_AND_PNL_POLICY_PENDING');account=@{id='1';name='Default Paper Portfolio';executionMode='PAPER';startingCash='100000.00';currentCash='100000.00'};ledger=@{status='ATTACHED_READ_ONLY';cash='100000.00';reservedCash='0.00';unreservedCash='100000.00';revision='0'}}
}
function Test-Runner([string]$Scenario){
    $script:mock=@{deployed=($Scenario -ceq 'lock-only');restart=$false;ready=($Scenario -ceq 'lock-only');credentialReads=0;builds=0;deploys=0;dbChecks=0;control=@()}
    $dir=Join-Path ([IO.Path]::GetTempPath()) ('mb-runtime-deploy-test-'+[guid]::NewGuid().ToString('N'));[void][IO.Directory]::CreateDirectory($dir)
    foreach($file in @('psql.exe','writer.dpapi','credential.lock')){[IO.File]::WriteAllText((Join-Path $dir $file),'synthetic')}
    $runtimePath=Join-Path $dir 'runtime.json';$installPath=Join-Path $dir 'installation.json'
    [IO.File]::WriteAllText($runtimePath,(@{status='ISOLATED_RUNTIME_HANDOFF_PASSED_ACTIVATION_PENDING';runId='x';fixture=@{bootId='one'};postRestartFixture=@{bootId='two'};cleanupComplete=$true;finalState='LOCKED'}|ConvertTo-Json -Depth 5))
    [IO.File]::WriteAllText($installPath,(@{plan=@{planHash='synthetic';plan=@{databaseOid='123'}};target=@{database='marketbrain';port=5432}}|ConvertTo-Json -Depth 5))
    $runner=Get-Content (Join-Path $PSScriptRoot 'DeployPaperRuntimeReview.ps1') -Raw
    $runner=[regex]::Replace($runner,'(?m)^\. \(Join-Path \$PSScriptRoot .+\)\r?\n','')
    $runner=$runner.Replace('$PSScriptRoot',("'"+$PSScriptRoot.Replace("'","''")+"'"))
    $runner=$runner.Replace("'C:\MarketBrainData\Secrets\PaperReviewWriter\writer.dpapi'",("'"+(Join-Path $dir 'writer.dpapi').Replace("'","''")+"'"))
    function git {$global:LASTEXITCODE=0;if($args -contains 'rev-parse'){'e5c541a'}}
    function Get-Command {param($Name,$CommandType,$ErrorAction) [pscustomobject]@{Source='synthetic-docker.exe'}}
    function Assert-PaperCustodyPath([string]$Path){return $Path}
    function Assert-PaperPrivateAcl {}
    function Assert-PaperInstalledReport {}
    function Assert-PaperRuntimeFixture {}
    function Initialize-PaperStorageKey {return 'C:\MarketBrainData\Secrets\PaperApproval\delivery.key'}
    function Get-PaperCredentialEntropy {return ,([byte[]]@(1,2,3))}
    function Read-PaperCredential {$script:mock.credentialReads++;return ,(New-Object byte[] 48)}
    function New-PaperCredentialVerifier {return 'synthetic-verifier'}
    function New-PaperCredentialSql {param($Phase,$Envelope,$Verifier);Check ($Phase -ceq 'Verify') 'only read-only database operation';return 'synthetic-read-only-verification'}
    function Assert-PaperCredentialReceipt {param($Value,$Phase,$PlanHash);if(-not $Value.ok){throw 'DEPLOY_NOLOGIN_VERIFICATION_FAILED'}}
    function Invoke-PaperInstallerPsql {$script:mock.dbChecks++;return @{exitCode=0;timedOut=$false;elapsedSeconds=0.001;stdout=(@{ok=($Scenario -cne 'nologin-failure')}|ConvertTo-Json);sqlStates=@();assertionFailures=@()}}
    function Get-FileHash {param($LiteralPath)
        if($LiteralPath -ceq $runtimePath){return @{Hash='AC2812DF3A22F0CDBDE6EC61233E6F8A33A2CEDBB0CF2DF6E3267E2B410E9422'}}
        if($LiteralPath -ceq $installPath){return @{Hash='E213A645E4CD39D16E63BA69097E1D32B45E60DC49BF08EBE0B4B52DBD95B33D'}}
        return Microsoft.PowerShell.Utility\Get-FileHash -LiteralPath $LiteralPath
    }
    function Read-Host {param($Prompt,[switch]$AsSecureString);if($AsSecureString){return ConvertTo-SecureString 'synthetic-admin-password' -AsPlainText -Force};if($Prompt -like '*DEPLOY_LOCKED_REVIEW*'){return 'DEPLOY_LOCKED_REVIEW'};return 'postgres'}
    function Start-Sleep {}
    function Invoke-RestMethod {param($Uri,$TimeoutSec,$MaximumRedirection);if($Scenario -ceq 'health-failure'){throw 'synthetic'};return @{status='UP'}}
    function Invoke-WebRequest {param($Uri,$Headers,$TimeoutSec,$MaximumRedirection)
        Check ($MaximumRedirection -eq 0 -and $Headers['X-MarketBrain-Paper-Read-Token'] -ceq ('t'*64)) 'local authenticated read'
        $v=if($Uri.EndsWith('/storage')){@{version='PAPER_APPROVAL_STORAGE_V1';status='STORAGE_KEY_VERIFIED_ACTIONS_DISABLED';databaseWritesPerformed=$false;notificationEnabled=$false;actionExecutionEnabled=$false;liveExecutionEnabled=$false}}else{Account}
        if($Scenario -ceq 'account-drift' -and $script:mock.deployed -and $Uri.EndsWith('/overview')){$v.account.currentCash='99999.00'}
        return @{StatusCode=200;Content=($v|ConvertTo-Json -Depth 6);Headers=@{'Cache-Control'='no-store'}}
    }
    function Assert-PaperStorageStatus {param($Value);Check ($Value.status -ceq 'STORAGE_KEY_VERIFIED_ACTIONS_DISABLED') 'storage gate'}
    function Invoke-PaperRuntimeProcess {param($Executable,$Arguments,$Directory,$LimitSeconds,$InputBytes)
        $text='';$exit=0
        switch($Arguments[0]){
            'version' {$text='linux'}
            'ps' {$text=if($script:mock.deployed){'b'*64}else{'a'*64}}
            'inspect' {
                $v=Container -Memory:$script:mock.deployed
                if($script:mock.restart -and $Scenario -cne 'stale-restart'){$v.State.StartedAt='second'}
                if($script:mock.deployed -and $Scenario -ceq 'wrong-image'){$v.Image='sha256:'+('e'*64)}
                $text=ConvertTo-Json -InputObject @($v) -Depth 10 -Compress
            }
            'compose' {
                if($Arguments -contains 'config'){
                    $p=Plan (Container) $env:MARKETBRAIN_PAPER_REVIEW_IMAGE
                    # Exercise serialized Compose defaults through every full-runner path.
                    foreach($key in @('command','entrypoint','network_mode','pid','user')){$p.services.'marketbrain-service'|Add-Member $key $null}
                    $p.services.'marketbrain-service'|Add-Member privileged $false
                    foreach($key in @('devices','cap_add')){$p.services.'marketbrain-service'|Add-Member $key @()}
                    if($Scenario -ceq 'config-drift'){$p.services.'marketbrain-service'.environment.MARKETBRAIN_DB_PASSWORD='different'}
                    if($Scenario -ceq 'unsafe-command'){$p.services.'marketbrain-service'.command='do-not-record-secret-value'}
                    if($Scenario -ceq 'unsafe-privileged'){$p.services.'marketbrain-service'.privileged=$true}
                    $text=$p|ConvertTo-Json -Depth 10 -Compress
                }
                elseif($Arguments -contains 'up'){$script:mock.deploys++;$script:mock.deployed=$true;if($Scenario -ceq 'unknown-deploy'){$exit=1}}
                else{throw 'Unexpected compose'}
            }
            'build' {$script:mock.builds++;if($Scenario -ceq 'build-failure'){$exit=1}}
            'image' {$text='sha256:'+('c'*64)}
            'restart' {$script:mock.restart=$true;$script:mock.ready=$false}
            'exec' {
                $c=$Arguments[-1];$script:mock.control+=@($c)
                if($c -ceq 'UNLOCK'){Check ($InputBytes.Length -eq 64) 'secret stdin';Check (-not (($Arguments -join ' ').Contains(('0'*64)))) 'secret not in arguments';$script:mock.ready=$true;if($Scenario -ceq 'lost-unlock'){$exit=1}}
                if($c -ceq 'LOCK'){if($Scenario -ceq 'lock-failure'){$exit=1}else{$script:mock.ready=$false}}
                $text=@{version='PAPER_RUNTIME_CONTROL_V1';state=$(if($script:mock.ready){'UNLOCKED'}else{'LOCKED'});databaseAuthenticationVerified=$false;actionExecutionEnabled=$false}|ConvertTo-Json -Compress
            }
            default {throw ('Unexpected command '+$Arguments[0])}
        }
        return @{exitCode=$exit;stdout=$text;stderr='';elapsedSeconds=0.001}
    }
    $beforeEnv=[Environment]::GetEnvironmentVariable('MARKETBRAIN_PAPER_READ_TOKEN','Process')
    $failed=$false;try{& ([scriptblock]::Create($runner)) -RuntimeReportPath $runtimePath -InstallationReportPath $installPath -PostgreSqlBin $dir -OutputDirectory $dir -LockOnly:($Scenario -ceq 'lock-only')}catch{$failed=$true}
    $files=@(Get-ChildItem -LiteralPath $dir -Filter 'paper-runtime-application-*.json');Check ($files.Count -eq 1) 'one report'
    $raw=Get-Content $files[0].FullName -Raw;$r=$raw|ConvertFrom-Json
    foreach($secretValue in @(('t'*64),('0'*64),'never-record-this-password','synthetic-admin-password','synthetic-verifier','do-not-record-secret-value')){Check (-not $raw.Contains($secretValue)) 'no secret in evidence'}
    Check ([Environment]::GetEnvironmentVariable('MARKETBRAIN_PAPER_READ_TOKEN','Process') -ceq $beforeEnv) 'process environment restored'
    if($Scenario -ceq 'success'){
        Check (-not $failed -and $r.status -ceq 'APPLICATION_RUNTIME_HANDOFF_PASSED_LOCKED_NOLOGIN') ('success '+$r.failureCode)
        Check ($r.finalLockVerified -and $r.handoffPassed -and $r.restartVerified -and $r.accountReconciled -and $r.noLoginAndNoSessionsVerified) 'all success gates'
    }elseif($Scenario -ceq 'lock-only'){
        Check (-not $failed -and $r.status -ceq 'APPLICATION_RUNTIME_LOCKED_REVIEW_REQUIRED' -and -not $script:mock.ready) 'lock recovery'
        Check ($script:mock.credentialReads -eq 0 -and $script:mock.builds -eq 0 -and $script:mock.dbChecks -eq 0) 'recovery no custody build database'
    }else{Check ($failed -and $r.status -cin @('STOPPED_REVIEW_REQUIRED','RECOVERY_REQUIRED_DO_NOT_REDEPLOY')) ('failure '+$Scenario)}
    if($Scenario -cin @('config-drift','nologin-failure','unsafe-command','unsafe-privileged')){Check ($script:mock.builds -eq 0 -and $script:mock.deploys -eq 0) 'preflight failure never builds or deploys'}
    if($Scenario -clike 'unsafe-*'){
        $key=($Scenario -replace '^unsafe-','').ToUpperInvariant()
        Check ($r.failureCode -ceq ('DEPLOY_UNREVIEWED_CONTAINER_SETTING_'+$key)) 'safe field-specific error persisted'
        Check (-not $r.secretHandoffAttempted) 'rejected override never handed off credential'
    }
    if($Scenario -ceq 'build-failure'){Check ($script:mock.deploys -eq 0) 'build failure never deploys'}
    if($Scenario -ceq 'lost-unlock'){Check ($r.finalLockVerified -and -not $script:mock.ready) 'unknown unlock locked'}
    if($Scenario -ceq 'lock-failure'){Check ($r.status -ceq 'RECOVERY_REQUIRED_DO_NOT_REDEPLOY' -and -not $r.finalLockVerified) 'unknown final lock blocks completion'}
    Check (-not $r.databaseRoleChangesRequested -and -not $r.accountWritesRequested -and -not $r.proposalPublicationRequested -and -not $r.actionExecutionEnabled) 'scope unchanged'
}
foreach($case in @('success','config-drift','unsafe-command','unsafe-privileged','nologin-failure','build-failure','unknown-deploy','health-failure','wrong-image','stale-restart','lost-unlock','lock-failure','account-drift','lock-only')){Test-Runner $case}
Write-Host "PASS: $count assertions; 14 mocked application deployment scenarios. No real service, database, credentials or Docker."
