#Requires -Version 7.0
[CmdletBinding()]
param([Parameter(Mandatory)][ValidatePattern('^[A-Fa-f0-9]{64}$')][string]$AcceptedPreflightSha256,
      [string]$PreflightPath,[string]$OutputDirectory='C:\MarketBrainData\Review')
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'NumericalHistoryEvidence.ps1')
. (Join-Path $PSScriptRoot 'PaperWriterPreflight.ps1')
$repo=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../..'))
$id=[guid]::NewGuid().ToString('N');$name='mb-publisher-rehearsal-'+$id;$image=$name+':local'
$watch=[Diagnostics.Stopwatch]::StartNew();$docker=$null;$attempted=$false;$secure=$null;$payload=$null;$runtime=$null
$report=[ordered]@{version='PAPER_PUBLISHER_REHEARSAL_BUNDLE_V1';runId=$id;status='RUNNING';revision=$null;steps=@();manifest=@{};failure=$null;catalog=$null;cleanup=$null;elapsedSeconds=0;applicationRestartRequested=$false;databaseWritesRequested=$false;applicationWriterActivated=$false;actionExecutionEnabled=$false;runtimeConfigurationMatched=$false}
$report.failureCode=$null
[void](New-Item -ItemType Directory -Path $OutputDirectory -Force)
$path=Join-Path (Resolve-Path -LiteralPath $OutputDirectory).Path ('paper-publisher-rehearsal-{0}-{1}.json' -f (Get-Date -Format yyyyMMdd-HHmmss),$id.Substring(0,12))
function Save {$report.elapsedSeconds=$watch.Elapsed.TotalSeconds;Save-NumericalHistoryReport $report $path -Compact}
function Stage($Percent,$Message){Save;Write-Progress -Activity 'Publisher installation rehearsal' -Status $Message -PercentComplete $Percent;Write-Host "[$Percent%] $Message"}
function Native($Stage,[string[]]$Arguments,[int]$Limit=30,[string]$InputText) {
    $r=Invoke-PaperCatalogProcess $docker $Arguments $repo $Limit $InputText
    $report.steps+=@{stage=$Stage;exitCode=$r.exitCode;timedOut=$r.timedOut;elapsedSeconds=$r.elapsedSeconds;stdoutCharacters=$r.stdout.Length;stderrCharacters=$r.stderr.Length};Save
    if($r.exitCode -ne 0 -or $r.timedOut){$report.failureCode=$Stage.ToUpperInvariant().Replace('-','_')+'_FAILED';if($Stage -cne 'rehearsal' -or $r.timedOut){throw 'Native stage failed.'}}
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
    Stage 0 'Rehearse publisher permissions and roll them back. No install, login activation or Telegram sends.'
    if(-not $PreflightPath){$PreflightPath=(Get-ChildItem -LiteralPath $OutputDirectory -File -Filter 'paper-publisher-preflight-*.json'|Sort-Object LastWriteTimeUtc -Descending|Select-Object -First 1).FullName}
    $file=Get-Item -LiteralPath $PreflightPath
    if($file.Length -gt 2097152 -or $file.Attributes -band [IO.FileAttributes]::ReparsePoint -or (Get-FileHash -LiteralPath $file.FullName).Hash -ine $AcceptedPreflightSha256){throw 'Accepted preflight not found or changed.'}
    $saved=Get-Content -LiteralPath $file.FullName -Raw|ConvertFrom-Json
    if($saved.version -cne 'PAPER_PUBLISHER_PREFLIGHT_BUNDLE_V1' -or $saved.status -cne 'CATALOG_EVIDENCE_CAPTURED_INSTALLATION_REVIEW_REQUIRED' -or $saved.runtimeConfigurationMatched -isnot [bool] -or -not $saved.runtimeConfigurationMatched -or $saved.cleanup.exitCode -ne 0 -or $saved.cleanup.timedOut){throw 'Runtime preflight not accepted.'}
    Assert-PaperWriterCatalog $saved.catalog 'public' -Publisher
    $report.target=$saved.catalog.target;$report.acceptedPreflightSha256=$AcceptedPreflightSha256.ToUpperInvariant()
    $g=Invoke-PaperCatalogProcess 'git' @('-C',$repo,'rev-parse','HEAD') $repo 10
    if($g.exitCode -ne 0 -or $g.stdout.Trim() -cnotmatch '^[a-f0-9]{40}$'){throw 'Revision unavailable.'};$report.revision=$g.stdout.Trim()
    $g=Invoke-PaperCatalogProcess 'git' @('-C',$repo,'status','--porcelain') $repo 10
    if($g.exitCode -ne 0 -or $g.stdout.Trim()){throw 'Preserve and review local changes first.'}
    foreach($f in @('ops/windows/TestPaperPublisherInstallation.ps1','ops/windows/PaperWriterPreflight.ps1','ops/windows/NumericalHistoryEvidence.ps1','marketbrain-service/Dockerfile.paper-writer-preflight','marketbrain-service/src/main/java/in/marketbrain/paper/PaperPublisherRehearsal.java','marketbrain-service/src/main/java/in/marketbrain/paper/PaperPublisherInstallation.java','marketbrain-service/src/main/java/in/marketbrain/paper/PaperWriterPreflight.java','marketbrain-service/src/main/resources/paper/approval-publisher-v1.sql')){$report.manifest[$f]=(Get-FileHash -LiteralPath (Join-Path $repo $f)).Hash}
    $docker=[string](@(Get-Command docker.exe -CommandType Application -ErrorAction Stop)[0].Source)
    $ids=@((Native 'runtime-discovery' @('ps','--no-trunc','-q','--filter','label=com.docker.compose.service=marketbrain-service')).Trim() -split '\r?\n'|Where-Object {$_})
    if($ids.Count -ne 1 -or $ids[0] -cnotmatch '^[a-f0-9]{64}$'){throw 'Running application ambiguous.'}
    $before=Inspect $ids[0];$runtime=Get-PaperCatalogRuntimeEnvironment $before $repo
    Stage 20 'Building an isolated rehearsal client; application remains running.'
    $null=Native 'rehearsal-build' @('build','-f','marketbrain-service/Dockerfile.paper-writer-preflight','-t',$image,'marketbrain-service') 1800
    $imageId=(Native 'image-identity' @('image','inspect','--format','{{.Id}}',$image)).Trim()
    if($imageId -cnotmatch '^sha256:[a-f0-9]{64}$'){throw 'Image identity unavailable.'}
    SameRuntime (Inspect $before.Id)
    Stage 50 'Administrator credentials stay local and pass to the client only through stdin.'
    Write-Host ('Target database: {0}; OID {1}; schema public. Rehearsal creates transactional roles/functions then rolls back.' -f $report.target.database,$report.target.databaseOid)
    if((Read-Host 'Type REHEARSE to run the rollback-only transaction') -cne 'REHEARSE'){throw 'Rehearsal not requested.'}
    $admin=Read-Host 'PostgreSQL administrator username'
    if($admin -cnotmatch '^[A-Za-z_][A-Za-z0-9_]{0,62}$'){throw 'Unsupported administrator username.'}
    $secure=Read-Host 'PostgreSQL administrator password (not Windows password)' -AsSecureString
    $payload=@{url=$runtime.MARKETBRAIN_DB_URL;user=$admin;password=[Net.NetworkCredential]::new('', $secure).Password;database=$report.target.database;databaseOid=$report.target.databaseOid;schema='public'}|ConvertTo-Json -Compress
    Stage 65 'Checking administrator catalog, rehearsing permissions, rolling back and comparing catalog state.'
    $report.databaseWritesRequested=$true;$attempted=$true;Save
    $raw=Native 'rehearsal' @('run','--rm','-i','--name',$name,'--read-only','--cap-drop=ALL','--security-opt=no-new-privileges:true','--pids-limit=64','--memory=256m','--cpus=1','--tmpfs','/tmp:rw,noexec,nosuid,size=16m','--add-host','host.docker.internal:host-gateway','--entrypoint','java',$imageId,'-Xmx128m','-cp','/verification/classes:/verification/lib/*','in.marketbrain.paper.PaperPublisherRehearsal') 180 $payload
    $payload=$null;$secure.Dispose();$secure=$null
    if($raw.Length -gt 8192){throw 'Rehearsal output too large.'}
    $receipt=$raw|ConvertFrom-Json
    if($receipt.version -ceq 'PAPER_PUBLISHER_REHEARSAL_V1') {
        $report.catalog=@{version=$receipt.version}
        foreach($key in @('status','failureType','sqlState')){if($receipt.PSObject.Properties[$key] -and $receipt.$key -cmatch '^[A-Za-z0-9_]{1,100}$'){$report.catalog[$key]=$receipt.$key}}
    }
    if($report.failureCode){throw 'Rehearsal process failed.'}
    if($receipt.version -cne 'PAPER_PUBLISHER_REHEARSAL_V1' -or $receipt.status -cne 'PUBLISHER_REHEARSAL_ROLLBACK_VERIFIED' -or $receipt.rollbackVerified -isnot [bool] -or -not $receipt.rollbackVerified){throw 'Rollback unverified.'}
    foreach($flag in @('committed','loginEnabled','applicationWriterActivated','actionExecutionEnabled')){if($receipt.$flag -isnot [bool] -or $receipt.$flag){throw 'Unsafe rehearsal receipt.'}}
    $report.catalog=$receipt
    SameRuntime (Inspect $before.Id);$report.runtimeConfigurationMatched=$true
    $report.status='PUBLISHER_REHEARSAL_PASSED_INSTALLATION_PENDING'
}catch{$report.status='STOPPED_REVIEW_REQUIRED';$report.failure='Rehearsal stopped; inspect bounded stage evidence. No automatic retry.'}
finally {
    $payload=$null;$runtime=$null;if($secure){$secure.Dispose()}
    if($attempted -and $docker){try {
        $left=(Native 'owned-container-check' @('ps','-aq','--no-trunc','--filter',('name=^/'+$name+'$'))).Trim()
        if($left){if($left -cnotmatch '^[a-f0-9]{64}$'){throw 'Cleanup identity ambiguous.'};$null=Native 'owned-container-remove' @('rm','-f',$left)}
        $report.cleanup=@{exitCode=0;timedOut=$false}
    }catch{$report.cleanup=@{exitCode=1;timedOut=$false};$report.status='STOPPED_CLEANUP_REVIEW_REQUIRED'}}
    Stage 100 $report.status;Write-Progress -Activity 'Publisher installation rehearsal' -Completed
    Write-Host "Share this ONE file: $path"
}
if($report.status -cne 'PUBLISHER_REHEARSAL_PASSED_INSTALLATION_PENDING'){throw 'Rehearsal needs review. Preserve the report; do not retry automatically.'}
