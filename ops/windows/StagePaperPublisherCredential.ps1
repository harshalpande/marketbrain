#Requires -Version 7.0
[CmdletBinding()]
param([Parameter(Mandatory)][ValidatePattern('^[A-Fa-f0-9]{64}$')][string]$AcceptedCustodySha256,
      [string]$CustodyPath,[string]$OutputDirectory='C:\MarketBrainData\Review',[switch]$VerifyOnly,[switch]$PlanAccess)
$ErrorActionPreference='Stop'
if($PlanAccess){$VerifyOnly=$true}
. (Join-Path $PSScriptRoot 'PaperPublisherCustody.ps1')
. (Join-Path $PSScriptRoot 'NumericalHistoryEvidence.ps1')
. (Join-Path $PSScriptRoot 'PaperWriterPreflight.ps1')
$repo=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../..'))
$id=[guid]::NewGuid().ToString('N');$name='mb-publisher-credential-'+$id;$image=$name+':local'
$watch=[Diagnostics.Stopwatch]::StartNew();$docker=$null;$attempted=$false;$secure=$null;$payload=$null;$runtime=$null
$report=[ordered]@{version='PAPER_PUBLISHER_CREDENTIAL_BUNDLE_V1';runId=$id;status='RUNNING';revision=$null;steps=@();manifest=@{};failure=$null;catalog=$null;cleanup=$null;elapsedSeconds=0;applicationRestartRequested=$false;databaseWritesRequested=$false;applicationWriterActivated=$false;actionExecutionEnabled=$false;runtimeConfigurationMatched=$false}
$custodyLock=$null;$credentialBytes=$null;$entropy=$null;$verifier=$null
$report.failureCode=$null;$report.commitOutcome='NOT_ATTEMPTED';$report.verifyOnly=[bool]$VerifyOnly
[void](New-Item -ItemType Directory -Path $OutputDirectory -Force)
$path=Join-Path (Resolve-Path -LiteralPath $OutputDirectory).Path ('paper-publisher-credential-{0}-{1}.json' -f (Get-Date -Format yyyyMMdd-HHmmss),$id.Substring(0,12))
function Save {$report.elapsedSeconds=$watch.Elapsed.TotalSeconds;Save-NumericalHistoryReport $report $path -Compact}
function Stage($Percent,$Message){Save;Write-Progress -Activity 'Disabled publisher credential staging' -Status $Message -PercentComplete $Percent;Write-Host "[$Percent%] $Message"}
function Native($Stage,[string[]]$Arguments,[int]$Limit=30,[string]$InputText) {
    $r=Invoke-PaperCatalogProcess $docker $Arguments $repo $Limit $InputText
    $report.steps+=@{stage=$Stage;exitCode=$r.exitCode;timedOut=$r.timedOut;elapsedSeconds=$r.elapsedSeconds;stdoutCharacters=$r.stdout.Length;stderrCharacters=$r.stderr.Length};Save
    if($r.exitCode -ne 0 -or $r.timedOut){$report.failureCode=$Stage.ToUpperInvariant().Replace('-','_')+'_FAILED';if($Stage -cne 'installation' -or $r.timedOut){throw 'Native stage failed.'}}
    return $r.stdout
}
function Inspect($Id) {
    $raw=Native 'runtime-inspect' @('inspect',$Id)
    if($raw.Length -gt 1048576){throw 'Runtime output bound.'}
    $items=@($raw|ConvertFrom-Json);if($items.Count -ne 1){throw 'Runtime ambiguous.'};return $items[0]
}
function SameRuntime($Current) {
    $values=Get-PaperCatalogRuntimeEnvironment $Current $repo
    if($Current.Id -cne $before.Id -or $Current.Image -cne $before.Image -or $Current.State.StartedAt -cne $before.State.StartedAt){throw 'Runtime changed.'}
    foreach($key in $runtime.Keys){if($values[$key] -cne $runtime[$key]){throw 'Runtime database configuration changed.'}}
}
try {
    Stage 0 'Stage the existing publisher credential with login disabled. No application activation or Telegram sends.'
    if(-not $CustodyPath){$CustodyPath=(Get-ChildItem -LiteralPath $OutputDirectory -File -Filter 'paper-publisher-custody-*.json'|Sort-Object LastWriteTimeUtc -Descending|Select-Object -First 1).FullName}
    $file=Get-Item -LiteralPath (Assert-PaperCustodyPath $CustodyPath)
    if($file.Length -gt 2097152 -or (Get-FileHash -LiteralPath $file.FullName).Hash -ine $AcceptedCustodySha256){throw 'Accepted custody not found or changed.'}
    $saved=Get-Content -LiteralPath $file.FullName -Raw|ConvertFrom-Json
    if($saved.version -cne 'PAPER_PUBLISHER_CUSTODY_BUNDLE_V1' -or $saved.status -cne 'PUBLISHER_CUSTODY_VERIFIED_DATABASE_STAGING_PENDING'){throw 'Custody not accepted.'}
    foreach($flag in @('custodyVerified','custodyRetained')){if($saved.$flag -isnot [bool] -or -not $saved.$flag){throw 'Custody unverified.'}}
    if($saved.acceptedInstallationSha256 -cne '8E0BAD905192D14F9C6E9FC90DA33451C35405E0557EB9AF9AE51545D55BAE1F'){throw 'Installation binding changed.'}
    $installed=@(Get-ChildItem -LiteralPath $OutputDirectory -File -Filter 'paper-publisher-install-*.json'|Where-Object {$_.Length -le 2MB -and -not ($_.Attributes -band [IO.FileAttributes]::ReparsePoint) -and (Get-FileHash -LiteralPath $_.FullName).Hash -ceq $saved.acceptedInstallationSha256})
    if($installed.Count -ne 1){throw 'Original accepted installation required.'}
    $install=Get-Content -LiteralPath $installed[0].FullName -Raw|ConvertFrom-Json
    $report.target=$install.target;$report.acceptedCustodySha256=$AcceptedCustodySha256.ToUpperInvariant()
    $custodyDirectory=Assert-PaperCustodyPath 'C:\MarketBrainData\Secrets\PaperPublisher';Assert-PaperPrivateAcl $custodyDirectory
    $lockPath=Assert-PaperCustodyPath (Join-Path $custodyDirectory 'credential.lock')
    $custodyLock=[IO.File]::Open($lockPath,'Open','ReadWrite','None')
    $entropy=Get-PaperPublisherEntropy $saved.acceptedInstallationSha256
    $credentialBytes=Read-PaperCredential (Join-Path $custodyDirectory 'publisher.dpapi') $entropy
    $verifier=New-PaperCredentialVerifier $credentialBytes
    $g=Invoke-PaperCatalogProcess 'git' @('-C',$repo,'rev-parse','HEAD') $repo 10
    if($g.exitCode -ne 0 -or $g.stdout.Trim() -cnotmatch '^[a-f0-9]{40}$'){throw 'Revision unavailable.'};$report.revision=$g.stdout.Trim()
    $g=Invoke-PaperCatalogProcess 'git' @('-C',$repo,'status','--porcelain') $repo 10
    if($g.exitCode -ne 0 -or $g.stdout.Trim()){throw 'Preserve and review local changes first.'}
    foreach($f in @('ops/windows/StagePaperPublisherCredential.ps1','ops/windows/PaperPublisherCustody.ps1','ops/windows/PaperWriterCredential.ps1','ops/windows/PaperWriterCustody.ps1','ops/windows/PaperWriterHbaStage.ps1','ops/windows/PaperStorageKey.ps1','ops/windows/PaperWriterInstallation.ps1','ops/windows/PaperWriterConnectionReview.ps1','marketbrain-service/src/main/java/in/marketbrain/paper/PaperPublisherAccessPlan.java','marketbrain-service/src/main/java/in/marketbrain/paper/PaperPublisherCredential.java','ops/windows/PaperWriterPreflight.ps1','ops/windows/NumericalHistoryEvidence.ps1','marketbrain-service/Dockerfile.paper-writer-preflight','marketbrain-service/src/main/java/in/marketbrain/paper/PaperPublisherRehearsal.java','marketbrain-service/src/main/java/in/marketbrain/paper/PaperPublisherInstall.java','marketbrain-service/src/main/java/in/marketbrain/paper/PaperPublisherInstallation.java','marketbrain-service/src/main/java/in/marketbrain/paper/PaperWriterPreflight.java','marketbrain-service/src/main/resources/paper/approval-publisher-v1.sql')){$report.manifest[$f]=(Get-FileHash -LiteralPath (Join-Path $repo $f)).Hash}
    $docker=[string](@(Get-Command docker.exe -CommandType Application -ErrorAction Stop)[0].Source)
    $ids=@((Native 'runtime-discovery' @('ps','--no-trunc','-q','--filter','label=com.docker.compose.service=marketbrain-service')).Trim() -split '\r?\n'|Where-Object {$_})
    if($ids.Count -ne 1 -or $ids[0] -cnotmatch '^[a-f0-9]{64}$'){throw 'Running application ambiguous.'}
    $before=Inspect $ids[0];$runtime=Get-PaperCatalogRuntimeEnvironment $before $repo
    Stage 20 'Building an isolated administrative client; application remains running.'
    $null=Native 'installer-build' @('build','-f','marketbrain-service/Dockerfile.paper-writer-preflight','-t',$image,'marketbrain-service') 1800
    $imageId=(Native 'image-identity' @('image','inspect','--format','{{.Id}}',$image)).Trim()
    if($imageId -cnotmatch '^sha256:[a-f0-9]{64}$'){throw 'Image identity unavailable.'}
    SameRuntime (Inspect $before.Id)
    Stage 50 'Administrator credentials stay local and pass to the client only through stdin.'
    Write-Host ('Target database: {0}; OID {1}; schema public. Credential staging retains NOLOGIN and existing permissions. VerifyOnly changes nothing.' -f $report.target.database,$report.target.databaseOid)
    if(-not $VerifyOnly) {

        if((Read-Host 'Avoid concurrent schema or role administration. Type STAGE_DISABLED to stage the existing credential after rollback rehearsal') -cne 'STAGE_DISABLED'){throw 'Installation not requested.'}
    }
    $admin=Read-Host 'PostgreSQL administrator username'
    if($admin -cnotmatch '^[A-Za-z_][A-Za-z0-9_]{0,62}$'){throw 'Unsupported administrator username.'}
    $secure=Read-Host 'PostgreSQL administrator password (not Windows password)' -AsSecureString
    $payload=@{url=$runtime.MARKETBRAIN_DB_URL;user=$admin;password=[Net.NetworkCredential]::new('', $secure).Password;database=$report.target.database;databaseOid=$report.target.databaseOid;schema='public';verifier=$verifier}|ConvertTo-Json -Compress
    SameRuntime (Inspect $before.Id)
    Stage 65 'Rehearse password staging, verify rollback, commit and read back. Login remains disabled.'
    $report.databaseWritesRequested=(-not $VerifyOnly);$report.commitOutcome=if($VerifyOnly){'NOT_ATTEMPTED'}else{'UNKNOWN_AFTER_ATTEMPT'};$attempted=$true;Save
    $mode=if($PlanAccess){'--plan-access'}elseif($VerifyOnly){'--verify-only'}else{'--stage-disabled'}
    $raw=Native 'installation' @('run','--rm','-i','--name',$name,'--read-only','--cap-drop=ALL','--security-opt=no-new-privileges:true','--pids-limit=64','--memory=256m','--cpus=1','--tmpfs','/tmp:rw,noexec,nosuid,size=16m','--add-host','host.docker.internal:host-gateway','--entrypoint','java',$imageId,'-Xmx128m','-cp','/verification/classes:/verification/lib/*','in.marketbrain.paper.PaperPublisherCredential',$mode) 180 $payload
    $payload=$null;$secure.Dispose();$secure=$null
    if($raw.Length -gt 8192){throw 'Rehearsal output too large.'}
    $receipt=$raw|ConvertFrom-Json
    if($receipt.version -ceq 'PAPER_PUBLISHER_CREDENTIAL_V1') {
        $report.catalog=@{version=$receipt.version}
        foreach($key in @('status','failureType','sqlState')){if($receipt.PSObject.Properties[$key] -and $receipt.$key -cmatch '^[A-Za-z0-9_]{1,100}$'){$report.catalog[$key]=$receipt.$key}}
    }
    if($receipt.PSObject.Properties['commitOutcome'] -and $receipt.commitOutcome -cin @('NOT_ATTEMPTED','UNKNOWN_AFTER_ATTEMPT','COMMITTED','EXISTING_MATCH_NO_CHANGE')){$report.commitOutcome=$receipt.commitOutcome}
    if($report.failureCode){throw 'Installation process failed; do not retry. Use VerifyOnly to reconcile.'}
    $expected=if($PlanAccess){'PUBLISHER_HBA_PLAN_READY'}elseif($VerifyOnly){'HBA_RULE_INVENTORY_CAPTURED'}else{'PUBLISHER_CREDENTIAL_VERIFIED_LOGIN_DISABLED'}
    if($receipt.version -cne 'PAPER_PUBLISHER_CREDENTIAL_V1' -or $receipt.status -cne $expected -or $receipt.disabledStateVerified -isnot [bool] -or -not $receipt.disabledStateVerified){throw 'Disabled state unverified.'}
    if($receipt.credentialVerified -isnot [bool] -or -not $receipt.credentialVerified){throw 'Credential readback unverified.'}
    foreach($flag in @('loginEnabled','actionExecutionEnabled')){if($receipt.$flag -isnot [bool] -or $receipt.$flag){throw 'Unsafe installation receipt.'}}
    if(-not $VerifyOnly -and $report.commitOutcome -cnotin @('COMMITTED','EXISTING_MATCH_NO_CHANGE')){throw 'Commit not established.'}
    if($PlanAccess -and ($receipt.originalHash -cnotmatch '^[A-F0-9]{64}$' -or $receipt.candidateHash -cnotmatch '^[A-F0-9]{64}$' -or $receipt.originalHash -ceq $receipt.candidateHash)){throw 'Plan hashes invalid.'}
    $report.catalog=$receipt
    SameRuntime (Inspect $before.Id);$report.runtimeConfigurationMatched=$true
    $report.status=$expected
}catch{$report.status='STOPPED_REVIEW_REQUIRED';$report.failure='Installation or verification stopped; inspect evidence and use VerifyOnly for uncertain state. No automatic retry.'}
finally {
    $payload=$null;$runtime=$null;$verifier=$null;if($secure){$secure.Dispose()};if($custodyLock){$custodyLock.Dispose()};foreach($b in @($credentialBytes,$entropy)){if($null -ne $b){[Array]::Clear($b,0,$b.Length)}}
    if($attempted -and $docker){try {
        $left=(Native 'owned-container-check' @('ps','-aq','--no-trunc','--filter',('name=^/'+$name+'$'))).Trim()
        if($left){if($left -cnotmatch '^[a-f0-9]{64}$'){throw 'Cleanup identity ambiguous.'};$null=Native 'owned-container-remove' @('rm','-f',$left)}
        $report.cleanup=@{exitCode=0;timedOut=$false}
    }catch{$report.cleanup=@{exitCode=1;timedOut=$false};$report.status='STOPPED_CLEANUP_REVIEW_REQUIRED'}}
    Stage 100 $report.status;Write-Progress -Activity 'Disabled publisher credential staging' -Completed
    Write-Host "Share this ONE file: $path"
}
if($report.status -cnotin @('PUBLISHER_CREDENTIAL_VERIFIED_LOGIN_DISABLED','HBA_RULE_INVENTORY_CAPTURED','PUBLISHER_HBA_PLAN_READY')){throw 'Credential staging needs review. Preserve custody and report; use VerifyOnly after an uncertain result.'}

