#Requires -Version 7.0
[CmdletBinding()]param(
 [string]$RuntimeReportPath='C:\MarketBrainData\Review\paper-runtime-review-20261015-141726-1b8abb8c6f34.json',
 [string]$InstallationReportPath='C:\MarketBrainData\Review\paper-writer-install-20261012-151121-ca9707876fe9.json',
 [string]$PostgreSqlBin='C:\Program Files\PostgreSQL\18\bin',
 [string]$OutputDirectory='C:\MarketBrainData\Review',
 [switch]$LockOnly
)
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'PaperRuntimeDeployment.ps1')
. (Join-Path $PSScriptRoot 'PaperWriterCredential.ps1')
. (Join-Path $PSScriptRoot 'PaperAccountReadReview.ps1')
. (Join-Path $PSScriptRoot 'NumericalHistoryEvidence.ps1')
$repo=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../..'));$id=[guid]::NewGuid().ToString('N')
$out=Assert-PaperCustodyPath $OutputDirectory;[void][IO.Directory]::CreateDirectory($out)
$path=Join-Path $out ('paper-runtime-application-'+(Get-Date -Format 'yyyyMMdd-HHmmss')+'-'+$id.Substring(0,12)+'.json')
$timer=[Diagnostics.Stopwatch]::StartNew();$docker=$null;$container=$null;$token=$null;$secure=$null;$password=$null;$payload=$null;$secret=$null;$entropy=$null;$verifier=$null;$custodyLock=$null;$before=$null;$after=$null;$plan=$null;$priorEnv=@{}
$report=[ordered]@{version='PAPER_RUNTIME_APPLICATION_V1';status='RUNNING';runId=$id;revision=$null;lockOnly=[bool]$LockOnly;events=@();steps=@();manifest=@{};deploymentAttempted=$false;secretHandoffAttempted=$false;handoffPassed=$false;restartVerified=$false;finalState=$null;finalLockVerified=$false;noLoginAndNoSessionsVerified=$false;accountReconciled=$false;databaseRoleChangesRequested=$false;accountWritesRequested=$false;proposalPublicationRequested=$false;actionExecutionEnabled=$false;failureCode=$null;recoveryFailureCode=$null;elapsedSeconds=0}
function Save {$report.elapsedSeconds=$timer.Elapsed.TotalSeconds;Save-NumericalHistoryReport $report $path -Compact}
function Stage([int]$Percent,[string]$Message){$report.events+=@{percent=$Percent;message=$Message};Save;Write-Host "[$Percent%] $Message";Write-Progress -Activity 'Guarded application runtime handoff' -PercentComplete $Percent -Status $Message}
function Native([string[]]$Arguments,[int]$Limit,[string]$Phase,[byte[]]$Bytes=$null){
    try{$v=Invoke-PaperRuntimeProcess $docker $Arguments $repo $Limit $Bytes}
    catch{$report.steps+=@{phase=$Phase;failureCode='DEPLOY_NATIVE_EXCEPTION'};Save;throw 'DEPLOY_NATIVE_EXCEPTION'}
    # Docker inspect/config may contain credentials. Never export raw stdout/stderr, arguments or hashes of secrets.
    $report.steps+=@{phase=$Phase;exitCode=$v.exitCode;elapsedSeconds=$v.elapsedSeconds;stderrCharacters=$v.stderr.Length};Save
    if($v.exitCode -ne 0){throw 'DEPLOY_NATIVE_FAILED'}
    if($Phase -cne 'BUILD' -and $v.stdout.Length -gt 4MB){throw 'DEPLOY_OUTPUT_BOUND'}
    return $v.stdout.Trim()
}
function Locate {
    $found=Native @('ps','--filter','label=com.docker.compose.service=marketbrain-service','--format','{{.ID}}') 15 'LOCATE'
    if($found -cnotmatch '^[a-f0-9]{12,64}$'){throw 'DEPLOY_AMBIGUOUS_APPLICATION'}
    $rows=@((Native @('inspect',$found) 15 'INSPECT')|ConvertFrom-Json)
    if($rows.Count -ne 1){throw 'DEPLOY_INSPECT_COUNT'};return $rows[0]
}
function Control([string]$Command,[byte[]]$Bytes,[string]$Expected){
    if($Command -ceq 'UNLOCK'){VerifyDatabase 'BEFORE_UNLOCK';$report.secretHandoffAttempted=$true;Save}
    $text=Native @('exec','-i',$container,'java','-Xmx32m','-cp','/app/control','in.marketbrain.paper.PaperRuntimeControl',$Command) 25 ('CONTROL_'+$Command) $Bytes
    $value=$text|ConvertFrom-Json;Assert-PaperRuntimeControl $value $Expected
    $report.finalState=$value.state;Save
}
function VerifyDatabase([string]$Phase){
    $report.noLoginAndNoSessionsVerified=$false;Save
    $sql=New-PaperCredentialSql 'Verify' $saved.plan $verifier
    try{$v=Invoke-PaperInstallerPsql $psql $saved.target.database $saved.target.port $admin $password $sql}finally{$sql=$null}
    $report.steps+=@{phase=$Phase;exitCode=$v.exitCode;timedOut=$v.timedOut;elapsedSeconds=$v.elapsedSeconds;sqlStates=$v.sqlStates;assertionFailures=$v.assertionFailures};Save
    if($v.exitCode -ne 0 -or $v.timedOut -or $v.stdout.Length -gt 8192){throw 'DEPLOY_NOLOGIN_VERIFICATION_FAILED'}
    Assert-PaperCredentialReceipt ($v.stdout.Trim()|ConvertFrom-Json) 'Verify' $saved.plan.planHash
    $report.noLoginAndNoSessionsVerified=$true;Save
}
function ReadAccount {
    $response=Invoke-WebRequest 'http://127.0.0.1:8080/api/v1/paper/account/overview' -Headers @{'X-MarketBrain-Paper-Read-Token'=$token} -TimeoutSec 20 -MaximumRedirection 0
    if($response.StatusCode -ne 200 -or ($response.Headers['Cache-Control'] -join ',') -notmatch 'no-store'){throw 'DEPLOY_ACCOUNT_READ_FAILED'}
    $value=$response.Content|ConvertFrom-Json;Assert-PaperAttachmentPreflight $value
    if($value.ledger.status -cne 'ATTACHED_READ_ONLY'){throw 'DEPLOY_LEDGER_REQUIRED'};return $value
}
function ReadStorage {
    $response=Invoke-WebRequest 'http://127.0.0.1:8080/api/v1/paper/approval/storage' -Headers @{'X-MarketBrain-Paper-Read-Token'=$token} -TimeoutSec 20 -MaximumRedirection 0
    if($response.StatusCode -ne 200 -or ($response.Headers['Cache-Control'] -join ',') -notmatch 'no-store'){throw 'DEPLOY_STORAGE_READ_FAILED'}
    $value=$response.Content|ConvertFrom-Json;Assert-PaperStorageStatus $value;return $value
}
function Health {
    for($attempt=1;$attempt -le 30;$attempt++){
        try{$h=Invoke-RestMethod 'http://127.0.0.1:8080/actuator/health' -TimeoutSec 10 -MaximumRedirection 0;if($h.status -ceq 'UP'){return}}catch{}
        Write-Host "Health $attempt/30 not ready.";if($attempt -lt 30){Start-Sleep -Seconds 5}
    };throw 'DEPLOY_HEALTH_DEADLINE'
}
try {
    Stage 0 'Actual service handoff only. NOLOGIN remains unchanged; no proposals, orders, reservations or fills.'
    $docker=(Get-Command docker.exe -CommandType Application -ErrorAction Stop|Select-Object -First 1).Source
    if((Native @('version','--format','{{.Server.Os}}') 15 'ENGINE') -cne 'linux'){throw 'DEPLOY_LINUX_REQUIRED'}
    $report.revision=(& git -C $repo rev-parse HEAD|Out-String).Trim();if($LASTEXITCODE -ne 0){throw 'DEPLOY_REVISION'}
    if(@(& git -C $repo status --porcelain).Count -or $LASTEXITCODE -ne 0){throw 'DEPLOY_DIRTY_WORKTREE'}
    $before=Locate
    if($LockOnly){
        Assert-PaperRuntimeContainer $before $repo -Memory;$container=$before.Id;$report.containerId=$container
        Control 'LOCK' $null 'LOCKED';Control 'STATUS' $null 'LOCKED';$report.finalLockVerified=$true
        $report.status='APPLICATION_RUNTIME_LOCKED_REVIEW_REQUIRED'
    }else{
        Assert-PaperRuntimeContainer $before $repo
        $report.priorContainerId=$before.Id;$report.priorImageId=$before.Image
        foreach($input in @(@($RuntimeReportPath,'AC2812DF3A22F0CDBDE6EC61233E6F8A33A2CEDBB0CF2DF6E3267E2B410E9422'),@($InstallationReportPath,'E213A645E4CD39D16E63BA69097E1D32B45E60DC49BF08EBE0B4B52DBD95B33D'))){
            $file=Assert-PaperCustodyPath $input[0]
            if((Get-Item -LiteralPath $file).Length -gt 2MB -or (Get-FileHash -LiteralPath $file).Hash -cne $input[1]){throw 'DEPLOY_ACCEPTED_REPORT_MISMATCH'}
        }
        $runtime=Get-Content -LiteralPath $RuntimeReportPath -Raw|ConvertFrom-Json
        Assert-PaperRuntimeFixture $runtime.fixture $runtime.runId;Assert-PaperRuntimeFixture $runtime.postRestartFixture $runtime.runId
        if($runtime.status -cne 'ISOLATED_RUNTIME_HANDOFF_PASSED_ACTIVATION_PENDING' -or -not $runtime.cleanupComplete -or $runtime.finalState -cne 'LOCKED' -or $runtime.fixture.bootId -ceq $runtime.postRestartFixture.bootId){throw 'DEPLOY_RUNTIME_EVIDENCE'}
        $saved=Get-Content -LiteralPath $InstallationReportPath -Raw|ConvertFrom-Json;Assert-PaperInstalledReport $saved
        # No new Flyway migration is authorized by this handoff; stop if the accepted schema source changed.
        & git -C $repo diff --quiet e5c541a HEAD -- marketbrain-service/src/main/resources/db/migration
        if($LASTEXITCODE -ne 0){throw 'DEPLOY_MIGRATION_REVIEW_REQUIRED'}
        $envMap=ConvertTo-PaperRuntimeEnvironment $before.Config.Env;$token=$envMap.MARKETBRAIN_PAPER_READ_TOKEN
        $report.beforeAccount=ReadAccount;$report.beforeStorage=ReadStorage
        $keyFile=Initialize-PaperStorageKey
        $mountedKey=@($before.Mounts|Where-Object Destination -CEQ '/run/secrets/paper-approval.key')[0]
        if((ConvertTo-PaperHostMount $mountedKey.Source) -cne (ConvertTo-PaperHostMount $keyFile)){throw 'DEPLOY_KEY_SOURCE_CHANGED'}
        if((Read-Host 'Stop other writer work and confirm all application jobs are idle. Type DEPLOY_LOCKED_REVIEW to rebuild/recreate the service and restart it once for verification') -cne 'DEPLOY_LOCKED_REVIEW'){throw 'DEPLOY_NOT_CONFIRMED'}
        $psql=Join-Path (Assert-PaperCustodyPath $PostgreSqlBin) 'psql.exe';if(-not(Test-Path -LiteralPath $psql -PathType Leaf)){throw 'DEPLOY_PSQL_MISSING'}
        $admin=Read-Host 'PostgreSQL administrator username (read-only verification; not Windows login)';if($admin -cnotmatch '^[A-Za-z_][A-Za-z0-9_]{0,62}$'){throw 'DEPLOY_ADMIN_INVALID'}
        $secure=Read-Host 'PostgreSQL administrator password (local only)' -AsSecureString;$password=[Net.NetworkCredential]::new('',$secure).Password;if(-not $password){throw 'DEPLOY_ADMIN_REQUIRED'}
        Stage 15 'Open existing protected custody under its owner; verify role remains NOLOGIN with no writer sessions.'
        $credential=Assert-PaperCustodyPath 'C:\MarketBrainData\Secrets\PaperReviewWriter\writer.dpapi'
        Assert-PaperPrivateAcl ([IO.Path]::GetDirectoryName($credential))
        $lockPath=Assert-PaperCustodyPath (Join-Path ([IO.Path]::GetDirectoryName($credential)) 'credential.lock');$custodyLock=[IO.File]::Open($lockPath,'Open','ReadWrite','None')
        $entropy=Get-PaperCredentialEntropy $saved;$payload=Read-PaperCredential $credential $entropy;$verifier=New-PaperCredentialVerifier $payload
        $secret=[Text.Encoding]::ASCII.GetBytes(([BitConverter]::ToString($payload,0,32)).Replace('-','').ToLowerInvariant())
        VerifyDatabase 'INITIAL_NOLOGIN'
        $image='marketbrain-runtime-'+$id+':review';$project=$before.Config.Labels.'com.docker.compose.project'
        $overrides=@{MARKETBRAIN_PAPER_READ_TOKEN=$token;MARKETBRAIN_PAPER_APPROVAL_KEY_HOST_FILE=$keyFile;MARKETBRAIN_PAPER_REVIEW_DATABASE_OID=[string]$saved.plan.plan.databaseOid;MARKETBRAIN_PAPER_REVIEW_IMAGE=$image}
        foreach($key in $overrides.Keys){$priorEnv[$key]=[Environment]::GetEnvironmentVariable($key,'Process');[Environment]::SetEnvironmentVariable($key,$overrides[$key],'Process')}
        $compose=@('compose','--project-name',$project,'--env-file','.env','-f','compose.yaml','-f','compose.paper-storage.yaml','-f','compose.paper-review-memory.yaml')
        # Private in-memory config comparison: never serialize resolved environment values into evidence.
        $plan=(Native ($compose+@('config','--format','json')) 30 'CONFIG_COMPARE')|ConvertFrom-Json
        Assert-PaperRuntimeCompose $plan $before ([string]$saved.plan.plan.databaseOid) $image
        foreach($file in @('compose.yaml','compose.paper-storage.yaml','compose.paper-review-memory.yaml','marketbrain-service/Dockerfile','ops/windows/DeployPaperRuntimeReview.ps1','ops/windows/PaperRuntimeDeployment.ps1','ops/windows/PaperRuntimeReview.ps1','ops/windows/PaperWriterCredential.ps1','marketbrain-service/src/main/java/in/marketbrain/paper/PaperRuntimeControl.java','marketbrain-service/src/main/java/in/marketbrain/paper/PaperRuntimeControlServer.java','marketbrain-service/src/main/java/in/marketbrain/paper/PaperTelegramReviewConfiguration.java')){$report.manifest[$file]=(Get-FileHash -LiteralPath (Join-Path $repo $file)).Hash}
        Stage 30 'Build the service image only. Existing service continues running during the build.'
        $null=Native @('build','-f','marketbrain-service/Dockerfile','-t',$image,'marketbrain-service') 1800 'BUILD'
        $report.imageId=Native @('image','inspect','--format','{{.Id}}',$image) 15 'IMAGE_ID'
        if($report.imageId -cnotmatch '^sha256:[a-f0-9]{64}$'){throw 'DEPLOY_IMAGE_ID'}
        VerifyDatabase 'PRE_DEPLOY_NOLOGIN';$null=ReadAccount
        Stage 50 'Recreate only marketbrain-service with existing environment/storage plus approved locked review settings.'
        $report.deploymentAttempted=$true;Save
        $null=Native ($compose+@('up','-d','--no-deps','--no-build','--pull','never','--force-recreate','marketbrain-service')) 180 'DEPLOY'
        Health;$after=Locate;Assert-PaperRuntimeContainer $after $repo -Memory;Assert-PaperRuntimePreserved $before $after
        if($after.Image -cne $report.imageId -or $after.Id -ceq $before.Id){throw 'DEPLOY_NEW_IMAGE_NOT_OBSERVED'}
        $container=$after.Id;$report.containerId=$container;Control 'STATUS' $null 'LOCKED'
        Stage 70 'Briefly unlock with the existing credential while NOLOGIN remains enforced; verify restart discards it.'
        Invoke-PaperRuntimeHandoffSequence -Secret $secret -Control {param($c,$b,$e) Control $c $b $e} -Restart {
            $priorStart=$after.State.StartedAt
            $null=Native @('restart','--time','10',$container) 40 'RESTART_APPLICATION';Health
            $restarted=Locate;Assert-PaperRuntimeContainer $restarted $repo -Memory;Assert-PaperRuntimePreserved $before $restarted
            if($restarted.Id -cne $container -or $restarted.Image -cne $report.imageId -or $restarted.State.StartedAt -ceq $priorStart){throw 'DEPLOY_RESTART_NOT_OBSERVED'}
            $report.restartVerified=$true;Save
        }
        $report.handoffPassed=$true;$report.finalLockVerified=$true
        Stage 90 'Independently verify NOLOGIN, no writer sessions, unchanged account and preserved approval storage.'
        VerifyDatabase 'FINAL_NOLOGIN';$report.afterAccount=ReadAccount;$report.afterStorage=ReadStorage
        if($report.beforeAccount.account.id -cne $report.afterAccount.account.id -or $report.beforeAccount.ledger.revision -cne $report.afterAccount.ledger.revision){throw 'DEPLOY_ACCOUNT_CHANGED'}
        $report.accountReconciled=$true;$report.status='APPLICATION_RUNTIME_HANDOFF_PASSED_LOCKED_NOLOGIN'
    }
}catch{
    $report.status='STOPPED_REVIEW_REQUIRED';$report.failureCode='DEPLOY_REVIEW_REQUIRED'
    if($_.Exception.Message -cmatch '^(DEPLOY|CREDENTIAL|CUSTODY|RUNTIME)_[A-Z_]+$'){$report.failureCode=$_.Exception.Message}
}finally{
    if($container -and $report.secretHandoffAttempted -and -not $report.finalLockVerified){
        try{Control 'LOCK' $null 'LOCKED';Control 'STATUS' $null 'LOCKED';$report.finalLockVerified=$true}
        catch{$report.recoveryFailureCode='DEPLOY_LOCK_NOT_VERIFIED';$report.status='RECOVERY_REQUIRED_DO_NOT_REDEPLOY'}
    }
    if($custodyLock){$custodyLock.Dispose()};foreach($bytes in @($payload,$secret,$entropy)){if($null -ne $bytes){[Array]::Clear($bytes,0,$bytes.Length)}}
    foreach($key in $priorEnv.Keys){
        if($null -eq $priorEnv[$key]){Remove-Item -LiteralPath ('Env:\'+$key) -ErrorAction SilentlyContinue}
        else{[Environment]::SetEnvironmentVariable($key,$priorEnv[$key],'Process')}
    }
    $password=$null;$verifier=$null;$token=$null;$plan=$null;$before=$null;$after=$null;if($secure){$secure.Dispose()}
    Save;Write-Progress -Activity 'Guarded application runtime handoff' -Completed
    Write-Host ('[100%] '+$report.status+'; elapsed='+[math]::Round($report.elapsedSeconds,2)+'s');Write-Host "Share this ONE file: $path"
    if($report.status -cin @('STOPPED_REVIEW_REQUIRED','RECOVERY_REQUIRED_DO_NOT_REDEPLOY')){Write-Warning 'Do not repeat deployment automatically. Preserve the report. LockOnly performs only a local lock/status check; no redeploy or credential read.'}
}
if($report.status -cnotin @('APPLICATION_RUNTIME_HANDOFF_PASSED_LOCKED_NOLOGIN','APPLICATION_RUNTIME_LOCKED_REVIEW_REQUIRED')){throw ('Application handoff stopped: '+$report.failureCode+' '+$report.recoveryFailureCode)}
