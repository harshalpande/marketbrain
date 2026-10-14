#Requires -Version 7.0
[CmdletBinding()]param([string]$OutputDirectory='C:\MarketBrainData\Review',[ValidateRange(60,1800)][int]$BuildTimeoutSeconds=1800)
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'PaperRuntimeReview.ps1')
. (Join-Path $PSScriptRoot 'NumericalHistoryEvidence.ps1')
$repo=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../..'));$id=[guid]::NewGuid().ToString('N')
[void][IO.Directory]::CreateDirectory($OutputDirectory)
$path=Join-Path ([IO.Path]::GetFullPath($OutputDirectory)) ('paper-runtime-review-'+(Get-Date -Format 'yyyyMMdd-HHmmss')+'-'+$id.Substring(0,12)+'.json')
$name='mb-paper-runtime-'+$id;$image=$name+':verification';$timer=[Diagnostics.Stopwatch]::StartNew()
$createAttempted=$false;$docker=$null;$secret=$null;$random=$null;$cipher=$null;$restored=$null;$entropy=$null
$report=[ordered]@{version='PAPER_RUNTIME_REVIEW_BUNDLE_V1';status='RUNNING';runId=$id;revision=$null;manifest=@{};events=@();steps=@();fixture=$null;postRestartFixture=$null;dpapiRoundTripVerified=$false;handoffSequencePassed=$false;finalState=$null;cleanupComplete=$false;failureCode=$null;cleanupFailureCode=$null;applicationDatabaseAccessed=$false;realCredentialUsed=$false;realTelegramVerified=$false;applicationWriterActivated=$false;actionExecutionEnabled=$false;elapsedSeconds=0}
function Save {$report.elapsedSeconds=$timer.Elapsed.TotalSeconds;Save-NumericalHistoryReport $report $path -Compact}
function Stage([int]$Percent,[string]$Message){$report.events+=@{percent=$Percent;message=$Message};Save;Write-Host "[$Percent%] $Message";Write-Progress -Activity 'Runtime review custody verification' -Status $Message -PercentComplete $Percent}
function Native([string[]]$Arguments,[int]$Limit,[string]$Label,[byte[]]$InputBytes=$null){
    try{$v=Invoke-PaperRuntimeProcess $docker $Arguments $repo $Limit $InputBytes}
    catch{
        $code='RUNTIME_PROCESS_FAILED';if($_.Exception.Message -cmatch '^RUNTIME_[A-Z_]+$'){$code=$_.Exception.Message}
        $report.steps+=@{phase=$Label;failureCode=$code};Save;throw $code
    }
    $row=@{phase=$Label;exitCode=$v.exitCode;elapsedSeconds=$v.elapsedSeconds;stderrCharacters=$v.stderr.Length}
    # No raw unlock output, argument strings, secrets or environment snapshots are exported.
    if($Label -ceq 'BUILD'){$row.buildOutputTail=($v.stdout+"`n"+$v.stderr).Substring([math]::Max(0,($v.stdout.Length+$v.stderr.Length+1)-6000))}
    # This fixture has synthetic data only; retain bounded startup diagnostics so failures are actionable.
    if($Label -ceq 'FIXTURE_READINESS'){$report.fixtureLogTail=($v.stdout+"`n"+$v.stderr).Substring([math]::Max(0,($v.stdout.Length+$v.stderr.Length+1)-6000))}
    $report.steps+=@($row);Save
    if($v.exitCode -ne 0){throw 'RUNTIME_NATIVE_FAILED'}
    if($Label -cne 'BUILD' -and $v.stdout.Length -gt 131072){throw 'RUNTIME_OUTPUT_BOUND'}
    return $v.stdout.Trim()
}
function Fixture([string]$Field){
    $ready=$false
    for($attempt=1;$attempt -le 20;$attempt++){
        $logs=Native @('logs','--tail','80',$name) 15 'FIXTURE_READINESS'
        $lines=@($logs -split "`n"|Where-Object {$_ -clike 'PAPER_RUNTIME_REPORT=*'})
        if($lines.Count){
            $value=$lines[-1].Substring('PAPER_RUNTIME_REPORT='.Length)|ConvertFrom-Json
            if($Field -cne 'postRestartFixture' -or $value.bootId -cne $report.fixture.bootId){
                $report[$Field]=$value;Save;Assert-PaperRuntimeFixture $value $id;$ready=$true;break
            }
        }
        Write-Host "Fixture startup $attempt/20; waiting for the recorded checks."
        if($attempt -lt 20){Start-Sleep -Seconds 1}
    }
    if(-not $ready){throw 'RUNTIME_FIXTURE_NOT_READY'}
}
function Control([string]$Command,[byte[]]$Bytes,[string]$Expected){
    $text=Native @('exec','-i',$name,'java','-Xmx32m','-cp','/verification/classes','in.marketbrain.paper.PaperRuntimeControl',$Command) 25 ('CONTROL_'+$Command) $Bytes
    $value=$text|ConvertFrom-Json;Assert-PaperRuntimeControl $value $Expected;$report.finalState=$value.state;Save
}
try {
    Stage 0 'Synthetic Windows custody and isolated Linux review test only. No real secrets, database or Telegram calls.'
    $report.revision=(& git -C $repo rev-parse HEAD|Out-String).Trim();if($LASTEXITCODE -ne 0){throw 'RUNTIME_REVISION_UNAVAILABLE'}
    if(@(& git -C $repo status --porcelain).Count -or $LASTEXITCODE -ne 0){throw 'RUNTIME_WORKTREE_NOT_CLEAN'}
    $docker=(Get-Command docker.exe -CommandType Application -ErrorAction Stop|Select-Object -First 1).Source
    foreach($file in @('ops/windows/TestPaperRuntimeReviewBundle.ps1','ops/windows/PaperRuntimeReview.ps1','ops/windows/NumericalHistoryEvidence.ps1','marketbrain-service/Dockerfile.paper-runtime-verification','marketbrain-service/src/main/java/in/marketbrain/paper/PaperRuntimeCredential.java','marketbrain-service/src/main/java/in/marketbrain/paper/PaperRuntimeControl.java','marketbrain-service/src/main/java/in/marketbrain/paper/PaperRuntimeControlServer.java','marketbrain-service/src/main/java/in/marketbrain/paper/PaperRuntimeReviewVerification.java','marketbrain-service/src/main/java/in/marketbrain/paper/PaperReviewTestPolicy.java','marketbrain-service/src/main/java/in/marketbrain/paper/PaperTelegramReviewConfiguration.java','marketbrain-service/src/main/java/in/marketbrain/paper/PaperApprovalCallback.java','marketbrain-service/src/main/java/in/marketbrain/telegram/TelegramUpdateHandler.java')){$report.manifest[$file]=(Get-FileHash -LiteralPath (Join-Path $repo $file)).Hash}
    $engine=Native @('version','--format','{{.Server.Os}}') 15 'ENGINE';if($engine -cne 'linux'){throw 'RUNTIME_LINUX_CONTAINERS_REQUIRED'}
    Stage 10 'Build verifier and run policy, credential, Spring and polling tests. Existing application is not rebuilt.'
    $null=Native @('build','-f','marketbrain-service/Dockerfile.paper-runtime-verification','-t',$image,'marketbrain-service') $BuildTimeoutSeconds 'BUILD'
    $report.imageId=Native @('image','inspect','--format','{{.Id}}',$image) 15 'IMAGE_ID'
    if($report.imageId -cnotmatch '^sha256:[a-f0-9]{64}$'){throw 'RUNTIME_IMAGE_ID'}
    Stage 45 'Run 18 checks in a disposable network-none, read-only container with a private socket directory.'
    $createAttempted=$true;Save
    $report.containerId=Native @('run','-d','--name',$name,'--label',('marketbrain.paper.runtime='+$id),'--network','none','--read-only','--memory','512m','--pids-limit','128','--tmpfs','/tmp:rw,noexec,nosuid,nodev,size=16777216','--tmpfs','/run/marketbrain-writer:rw,noexec,nosuid,nodev,size=65536,mode=0700,uid=0,gid=0',$report.imageId,$id) 45 'CREATE_FIXTURE'
    if($report.containerId -cnotmatch '^[a-f0-9]{64}$'){throw 'RUNTIME_CONTAINER_ID'}
    $network=Native @('inspect','--format','{{.HostConfig.NetworkMode}}',$name) 15 'CHECK_NETWORK'
    $readonly=Native @('inspect','--format','{{.HostConfig.ReadonlyRootfs}}',$name) 15 'CHECK_ROOT'
    if($network -cne 'none' -or $readonly -cne 'true'){throw 'RUNTIME_ISOLATION_MISMATCH'}
    Fixture 'fixture'
    Stage 60 'Create a synthetic password, protect/unprotect with CurrentUser DPAPI, then hand it over through stdin only.'
    Add-Type -AssemblyName System.Security
    $random=New-Object byte[] 32;$rng=[Security.Cryptography.RandomNumberGenerator]::Create();try{$rng.GetBytes($random)}finally{$rng.Dispose()}
    $secret=[Text.Encoding]::ASCII.GetBytes(([BitConverter]::ToString($random)).Replace('-','').ToLowerInvariant())
    $entropy=[Text.Encoding]::UTF8.GetBytes('MARKETBRAIN_SYNTHETIC_RUNTIME_'+$id)
    $cipher=[Security.Cryptography.ProtectedData]::Protect($secret,$entropy,[Security.Cryptography.DataProtectionScope]::CurrentUser)
    $restored=[Security.Cryptography.ProtectedData]::Unprotect($cipher,$entropy,[Security.Cryptography.DataProtectionScope]::CurrentUser)
    if($restored.Length -ne 64 -or [Convert]::ToBase64String($restored) -cne [Convert]::ToBase64String($secret)){throw 'RUNTIME_DPAPI_MISMATCH'}
    $report.dpapiRoundTripVerified=$true;Save
    Invoke-PaperRuntimeHandoffSequence -Secret $restored -Control {param($c,$bytes,$expected) Control $c $bytes $expected} -Restart {
        Stage 75 'Restart only the disposable verifier; the credential must disappear and review must return locked.'
        $null=Native @('restart','--time','10',$name) 40 'RESTART_FIXTURE'
        # A new per-JVM boot identity is mandatory; old Docker log lines never count as restart success.
        Fixture 'postRestartFixture'
    }
    $report.handoffSequencePassed=$true
    Stage 95 'Handoff and locked restart passed; preserve one report and remove only this owned synthetic container.'
    $report.status='ISOLATED_RUNTIME_HANDOFF_PASSED_ACTIVATION_PENDING'
} catch {
    $report.status='FAILED';$report.failureCode='RUNTIME_REVIEW_REQUIRED'
    if($_.Exception.Message -cmatch '^RUNTIME_[A-Z_]+$'){$report.failureCode=$_.Exception.Message}
} finally {
    if($createAttempted -and $docker){
        try{
            $owner=Native @('inspect','--format','{{index .Config.Labels "marketbrain.paper.runtime"}}',$name) 15 'VERIFY_CLEANUP_OWNER'
            if($owner -cne $id){throw 'RUNTIME_CLEANUP_OWNER_MISMATCH'}
            $null=Native @('stop','--time','10',$name) 30 'STOP_OWNED_FIXTURE'
            if($report.status -ceq 'ISOLATED_RUNTIME_HANDOFF_PASSED_ACTIVATION_PENDING'){
                $null=Native @('rm',$name) 15 'REMOVE_OWNED_FIXTURE';$report.cleanupComplete=$true
            }
        }catch{$report.cleanupFailureCode='RUNTIME_CLEANUP_REVIEW_REQUIRED';$report.status='FAILED'}
    }
    foreach($buffer in @($secret,$random,$cipher,$restored,$entropy)){if($null -ne $buffer){[Array]::Clear($buffer,0,$buffer.Length)}}
    Save;Write-Progress -Activity 'Runtime review custody verification' -Completed
    Write-Host ('[100%] '+$report.status+'; elapsed='+[math]::Round($report.elapsedSeconds,2)+'s')
    Write-Host "Share this ONE file: $path"
    if($report.status -ceq 'FAILED'){Write-Warning 'Failed synthetic fixture is retained where created; stop was requested only after ownership verification. Do not prune unrelated Docker resources.'}
}
if($report.status -cne 'ISOLATED_RUNTIME_HANDOFF_PASSED_ACTIVATION_PENDING'){throw ('Runtime handoff verification stopped: '+$report.failureCode+' '+$report.cleanupFailureCode)}
