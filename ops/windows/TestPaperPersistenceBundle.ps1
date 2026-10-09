#Requires -Version 5.1
[CmdletBinding()]
param([string]$OutputDirectory='C:\MarketBrainData\Review',[ValidateRange(60,1800)][int]$BuildTimeoutSeconds=900,[switch]$ApplicationLedger,[switch]$ApprovalReview)
$ErrorActionPreference='Stop'
if($ApplicationLedger -and $ApprovalReview){throw 'Choose one isolated suite only.'}
. (Join-Path $PSScriptRoot 'PaperPersistenceVerification.ps1')
. (Join-Path $PSScriptRoot 'PaperLedgerVerification.ps1')
. (Join-Path $PSScriptRoot 'PaperApprovalVerification.ps1')
$successStatus=if($ApplicationLedger){'ISOLATED_LEDGER_PASSED_APPLICATION_MIGRATION_PENDING'}else{'ISOLATED_PERSISTENCE_PASSED_APPLICATION_RELEASE_BLOCKED'}
$dockerfile=if($ApplicationLedger){'marketbrain-service/Dockerfile.paper-ledger-verification'}else{'marketbrain-service/Dockerfile.paper-verification'}
if($ApprovalReview){$successStatus='ISOLATED_APPROVAL_PASSED_TRANSPORT_AND_EXECUTION_BLOCKED';$dockerfile='marketbrain-service/Dockerfile.paper-approval-verification'}
$root=(Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$id=[guid]::NewGuid().ToString('N');$prefix='mb-paper-'+$id.Substring(0,12);$schema='paper_verify_'+$id
$network=$prefix+'-net';$db=$prefix+'-db';$prepare=$prefix+'-prepare';$recover=$prefix+'-recover';$image=$prefix+':verification'
$label='marketbrain.paper.run';$docker=$null;$fixtureCreationAttempted=$false
$timer=[Diagnostics.Stopwatch]::StartNew();$report=[ordered]@{version='PAPER_PERSISTENCE_BUNDLE_V1';runId=$id;status='RUNNING';createdAtUtc=[DateTime]::UtcNow.ToString('o');elapsedSeconds=0;powerShellVersion=$PSVersionTable.PSVersion.ToString();manifest=@{};events=@();steps=@();prepare=$null;recover=$null;failure=$null;cleanup=@();syntheticDatabaseWritesPerformed=$false;applicationDatabaseAccessed=$false;actionExecutionEnabled=$false;resources=@{network=$network;database=$db;prepare=$prepare;recover=$recover;image=$image;schema=$schema}}
if($ApplicationLedger){$report.version='PAPER_LEDGER_BUNDLE_V1'}
if($ApprovalReview){$report.version='PAPER_APPROVAL_BUNDLE_V1'}
New-Item -ItemType Directory -Path $OutputDirectory -Force|Out-Null
$path=Join-Path (Resolve-Path -LiteralPath $OutputDirectory).Path ('paper-persistence-{0}-{1}.json' -f (Get-Date -Format 'yyyyMMdd-HHmmss'),$id.Substring(0,12))
if($ApplicationLedger){$path=Join-Path (Resolve-Path -LiteralPath $OutputDirectory).Path ('paper-ledger-{0}-{1}.json' -f (Get-Date -Format 'yyyyMMdd-HHmmss'),$id.Substring(0,12))}
if($ApprovalReview){$path=Join-Path (Resolve-Path -LiteralPath $OutputDirectory).Path ('paper-approval-{0}-{1}.json' -f (Get-Date -Format 'yyyyMMdd-HHmmss'),$id.Substring(0,12))}
if($path.Length+41 -ge 260 -or (Test-Path -LiteralPath $path)){throw 'Unsafe or existing report path.'}
function Save-Report { $report.elapsedSeconds=$timer.Elapsed.TotalSeconds;Save-NumericalHistoryReport $report $path -Compact }
function Progress([int]$Percent,[string]$Detail){Write-Host "[$Percent%] $Detail";Write-Progress -Activity 'Isolated paper persistence' -Status $Detail -PercentComplete $Percent;$report.events+=@{atUtc=[DateTime]::UtcNow.ToString('o');percent=$Percent;detail=$Detail};Save-Report}
function Docker([string]$Step,[string[]]$Arguments,[int]$Limit=60,[switch]$AllowFailure){
    $info=[Diagnostics.ProcessStartInfo]::new();$info.FileName=$docker;$info.Arguments=($Arguments|ForEach-Object{ConvertTo-EvaluationProcessArgument $_}) -join ' ';$info.UseShellExecute=$false;$info.CreateNoWindow=$true;$info.RedirectStandardOutput=$true;$info.RedirectStandardError=$true
    $p=[Diagnostics.Process]::new();$p.StartInfo=$info;$watch=[Diagnostics.Stopwatch]::StartNew();$heartbeat=0;$done=$false
    try{[void]$p.Start();$out=$p.StandardOutput.ReadToEndAsync();$err=$p.StandardError.ReadToEndAsync();while($watch.Elapsed.TotalSeconds -lt $Limit){if($p.WaitForExit(250)){$done=$true;break};if($watch.Elapsed.TotalSeconds-$heartbeat -ge 10){$heartbeat=$watch.Elapsed.TotalSeconds;Write-Host ('  {0}: {1:N0}s elapsed (limit {2}s)' -f $Step,$heartbeat,$Limit)}}
        if(-not $done){$p.Kill();[void]$p.WaitForExit(5000)};if(-not $out.Wait(5000) -or -not $err.Wait(5000)){throw 'Docker output drain timed out.'}
        $r=[pscustomobject]@{step=$Step;exitCode=if($done){$p.ExitCode}else{-999};timedOut=(-not $done);elapsedSeconds=$watch.Elapsed.TotalSeconds;stdout=$out.Result;stderr=$err.Result}
        $report.steps+=@($r);Save-Report
        if(-not $AllowFailure -and ($r.exitCode -ne 0 -or $r.timedOut)){throw "Docker step failed: $Step. Embedded output preserved; no automatic test retry."};return $r
    }finally{try{if(-not $p.HasExited){$p.Kill()}}catch{};$p.Dispose()}
}
function Wait-Database {
    for($attempt=1;$attempt -le 30;$attempt++){$r=Docker 'database readiness' @('exec',$db,'pg_isready','-U','paper_fixture','-d','paper_fixture') 10 -AllowFailure;if($r.exitCode -eq 0){return};Write-Host "  Database readiness $attempt/30";Start-Sleep -Seconds 2};throw 'Isolated database not ready.'
}
function Owned-Container([string]$Name){$r=Docker 'inspect fixture ownership' @('container','inspect',$Name) 15 -AllowFailure;if($r.exitCode -ne 0){return $false};$v=@($r.stdout|ConvertFrom-Json)[0];return ($v.Config.Labels.$label -ceq $id)}
try {
    Progress 0 'Isolated synthetic database test only. Existing service, database, provider and models are not used.'
    $docker=Resolve-PaperDockerExecutable
    $report.manifest.dockerExecutable=$docker;Save-Report
    Write-Host "Docker executable: $docker"
    $git=Invoke-EvaluationProcess 'git' @('-C',$root,'rev-parse','HEAD') 10;if($git.exitCode -ne 0){throw 'Cannot identify revision'};$report.manifest.codeRevision=$git.stdout.Trim()
    foreach($file in @('marketbrain-service/src/main/java/in/marketbrain/paper/PaperAccountEngineering.java','marketbrain-service/src/main/java/in/marketbrain/paper/PaperPersistenceEngineering.java','marketbrain-service/src/main/java/in/marketbrain/paper/PaperPersistenceVerification.java','marketbrain-service/Dockerfile.paper-verification','marketbrain-service/pom.xml','ops/windows/PaperPersistenceVerification.ps1','ops/windows/TestPaperPersistenceBundle.ps1','ops/windows/NumericalPaperPreparation.ps1','ops/windows/NumericalTenFeatureEngineering.ps1','ops/windows/NumericalEvaluationEngineering.ps1','ops/windows/NumericalHistoryEvidence.ps1')){$report.manifest[$file]=(Get-FileHash -LiteralPath (Join-Path $root $file)).Hash}
    if($ApplicationLedger){foreach($file in @($dockerfile,'marketbrain-service/src/main/java/in/marketbrain/paper/PaperLedgerStore.java','marketbrain-service/src/main/java/in/marketbrain/paper/PaperLedgerVerification.java','marketbrain-service/src/main/resources/db/migration/V1__create_marketbrain_paper_foundation.sql','marketbrain-service/src/main/resources/paper/ledger-v1.sql','ops/windows/PaperLedgerVerification.ps1')){$report.manifest[$file]=(Get-FileHash -LiteralPath (Join-Path $root $file)).Hash}}
    if($ApprovalReview){foreach($file in @($dockerfile,'marketbrain-service/src/main/java/in/marketbrain/paper/PaperApprovalReview.java','marketbrain-service/src/main/java/in/marketbrain/paper/PaperApprovalVerification.java','marketbrain-service/src/main/java/in/marketbrain/paper/PaperLedgerStore.java','marketbrain-service/src/main/java/in/marketbrain/paper/PaperLedgerVerification.java','marketbrain-service/src/main/resources/paper/approval-v1.sql','marketbrain-service/src/main/resources/paper/ledger-v1.sql','marketbrain-service/src/main/resources/db/migration/V1__create_marketbrain_paper_foundation.sql','marketbrain-service/src/main/resources/db/migration/V2__make_alert_delivery_channel_neutral.sql','marketbrain-service/src/main/resources/db/migration/V3__create_telegram_delivery_foundation.sql','ops/windows/PaperApprovalVerification.ps1')){$report.manifest[$file]=(Get-FileHash -LiteralPath (Join-Path $root $file)).Hash}}
    [void](Docker 'docker engine check' @('version','--format','{{.Server.Version}}') 30)
    Progress 10 'Building isolated verification image; no application deployment or restart.'
    [void](Docker 'build verification image' @('build','-f',(Join-Path $root $dockerfile),'-t',$image,(Join-Path $root 'marketbrain-service')) $BuildTimeoutSeconds)
    [void](Docker 'pull fixture database image' @('pull','postgres:17') 300)
    $report.manifest.verificationImage=(Docker 'verification image identity' @('image','inspect',$image,'--format','{{.Id}}') 15).stdout.Trim()
    $report.manifest.databaseImage=(Docker 'database image identity' @('image','inspect','postgres:17','--format','{{.Id}}') 15).stdout.Trim()
    Progress 35 'Creating labelled internal-only test network and database; no published ports or host mounts.'
    # Mark before invocation: even an uncertain network-create result needs ownership checks.
    $fixtureCreationAttempted=$true
    [void](Docker 'create internal network' @('network','create','--internal','--label',"$label=$id",$network) 20)
    [void](Docker 'create fixture database' @('create','--name',$db,'--network',$network,'--network-alias','db','--label',"$label=$id",'--memory','512m','--cpus','1','-e','POSTGRES_USER=paper_fixture','-e','POSTGRES_DB=paper_fixture','-e','POSTGRES_PASSWORD=isolated_fixture_only',$report.manifest.databaseImage) 30)
    $report.syntheticDatabaseWritesPerformed=$null;Save-Report
    [void](Docker 'start fixture database' @('start',$db) 20);Wait-Database
    $report.syntheticDatabaseWritesPerformed=$true
    Progress 45 'Checking transactions, rollback, duplicate handling, corruption and competing approvals.'
    [void](Docker 'create prepare verifier' @('create','--name',$prepare,'--network',$network,'--label',"$label=$id",'--memory','384m','--cpus','1',$report.manifest.verificationImage,'--prepare',$schema) 20)
    $p=Docker 'prepare database fixtures' @('start','-a',$prepare) 300
    $report.prepare=$p.stdout|ConvertFrom-Json;Save-Report
    if($ApprovalReview){Assert-PaperApprovalPhase $report.prepare '--prepare' $schema}elseif($ApplicationLedger){Assert-PaperLedgerPhase $report.prepare '--prepare' $schema}else{Assert-PaperPersistencePhase $report.prepare '--prepare' $schema}
    Progress 75 'Restarting only the disposable PostgreSQL container; committed fixture records must survive.'
    [void](Docker 'restart fixture database' @('restart','--time','10',$db) 30);Wait-Database
    [void](Docker 'create fresh recovery verifier' @('create','--name',$recover,'--network',$network,'--label',"$label=$id",'--memory','384m','--cpus','1',$report.manifest.verificationImage,'--recover',$schema) 20)
    $p=Docker 'fresh JVM recovery verification' @('start','-a',$recover) 120
    $report.recover=$p.stdout|ConvertFrom-Json;Save-Report
    if($ApprovalReview){Assert-PaperApprovalPhase $report.recover '--recover' $schema}elseif($ApplicationLedger){Assert-PaperLedgerPhase $report.recover '--recover' $schema}else{
        Assert-PaperPersistencePhase $report.recover '--recover' $schema
        if($report.prepare.receipt.tailHash -ceq $report.recover.receipt.tailHash){throw 'Expiry did not advance persisted history.'}
    }
    $report.status=$successStatus
    Progress 95 'Accounting and restart checks passed; saving evidence before disposable test cleanup.'
} catch {$report.status='FAILED';$report.failure=$_.Exception.Message;Save-Report}
finally {
    try {
        if(-not $fixtureCreationAttempted){
            $report.cleanup+=@{action='SKIPPED_NO_FIXTURE_CREATION_ATTEMPTED'}
        }else{
        if(Owned-Container $db){[void](Docker 'fixture database diagnostic logs' @('logs','--tail','100',$db) 15 -AllowFailure)}
        foreach($name in @($prepare,$recover,$db)){
            if(Owned-Container $name){
                if($report.status -ceq $successStatus){[void](Docker 'remove completed disposable fixture' @('rm','-f','-v',$name) 30);$report.cleanup+=@{resource=$name;action='REMOVED_SYNTHETIC_CONTAINER_AND_ANONYMOUS_VOLUMES'}}
                else{[void](Docker 'stop failed fixture preserving evidence' @('stop','--time','5',$name) 15 -AllowFailure);$report.cleanup+=@{resource=$name;action='PRESERVED_STOP_REQUESTED'}}
            }
        }
        if($report.status -ceq $successStatus){
            $n=Docker 'inspect network ownership' @('network','inspect',$network) 15 -AllowFailure
            if($n.exitCode -eq 0 -and @($n.stdout|ConvertFrom-Json)[0].Labels.$label -ceq $id){[void](Docker 'remove completed isolated network' @('network','rm',$network) 20)}
        }
        }
    }catch{$report.cleanup+=@{action='CLEANUP_INCOMPLETE';detail=$_.Exception.Message};Write-Warning 'Isolated fixture cleanup could not be confirmed. See report; do not prune unrelated resources.'}
    $timer.Stop();Save-Report;Write-Progress -Activity 'Isolated paper persistence' -Completed
    Write-Host ('[100%] {0}; elapsed={1:N2}s' -f $report.status,$report.elapsedSeconds);Write-Host "Share this ONE file: $path"
    if(-not $fixtureCreationAttempted){Write-Host 'No fixture network, container or database creation was attempted. Evidence and any built images are retained.'}
    else{Write-Host 'See cleanup records for removal or preservation of this run only. Evidence and built images are retained.'}
}
if($report.status -ne $successStatus){throw $report.failure}
