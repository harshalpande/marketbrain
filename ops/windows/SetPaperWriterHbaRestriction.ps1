#Requires -Version 7.0
[CmdletBinding()]param(
    [Parameter(Mandatory)][string]$ReviewedPlanPath,
    [switch]$Apply,
    [string]$PostgreSqlBin='C:\Program Files\PostgreSQL\18\bin',
    [string]$OutputDirectory='C:\MarketBrainData\Review'
)
$ErrorActionPreference='Stop'
foreach($file in @('NumericalHistoryEvidence.ps1','PaperWriterCustody.ps1','PaperWriterPreflight.ps1','PaperWriterInstallation.ps1','PaperWriterAccessReview.ps1','PaperWriterRestriction.ps1','PaperWriterHbaPlan.ps1','PaperWriterHbaStage.ps1')){. (Join-Path $PSScriptRoot $file)}
$root=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../..'));$id=[Guid]::NewGuid().ToString('N')
$out=Assert-PaperCustodyPath $OutputDirectory;[void][IO.Directory]::CreateDirectory($out)
$path=Join-Path $out ('paper-writer-hba-stage-'+(Get-Date -Format 'yyyyMMdd-HHmmss')+'-'+$id.Substring(0,12)+'.json')
$fixture=Join-Path $out ('hba-stage-probe-'+$id);$containerPath='/tmp/mb-hba-stage-'+$id
$timer=[Diagnostics.Stopwatch]::StartNew();$password=$null;$secure=$null;$containerId=$null;$created=$false;$copied=$false;$held=$false;$mutex=$null
$report=[ordered]@{version='PAPER_WRITER_HBA_STAGE_V1';status='RUNNING';runId=$id;revision=$null;sourceHash=$null;manifest=@{};events=@();steps=@();phase='PREFLIGHT';metadataBefore=$null;metadataAfter=$null;routeBefore=$null;routeAfter=$null;backupDirectory=$null;replacementAttempted=$false;hbaChanged=$false;postValidationPassed=$false;recoveryStatus=$null;rollbackFileVerified=$false;rollbackConnectionsVerified=$false;failureCode=$null;cleanupFailureCode=$null;cleanupComplete=$false;databaseContacted=$false;databaseWritesPerformed=$false;firewallChanged=$false;writerLoginAttempted=$false;credentialsSaved=$false;applicationWriterActivated=$false;actionExecutionEnabled=$false;elapsedSeconds=0}
function Save {$report.elapsedSeconds=$timer.Elapsed.TotalSeconds;Save-NumericalHistoryReport $report $path -Compact}
function Stage([int]$Percent,[string]$Phase,[string]$Message){$report.phase=$Phase;$report.events+=@{percent=$Percent;message=$Message};Save;Write-Host "[$Percent%] $Message";Write-Progress -Activity 'Writer authentication restriction' -Status $Message -PercentComplete $Percent}
function Native([string[]]$Arguments,[int]$Limit,[string]$Label,[string]$Executable=$docker){
    $v=Invoke-PaperCatalogProcess $Executable $Arguments $root $Limit
    $report.steps+=@{stage=$Label;exitCode=$v.exitCode;timedOut=$v.timedOut;elapsedSeconds=$v.elapsedSeconds};Save
    if($v.exitCode -ne 0 -or $v.timedOut -or $v.stdout.Length -gt 65536){throw 'HBA_STAGE_NATIVE_FAILED'}
    return $v.stdout.Trim()
}
function Metadata([string]$Label){
    $report.databaseContacted=$true
    $v=Invoke-PaperInstallerPsql $psql 'marketbrain' 5432 $admin $password (New-PaperHbaMetadataSql)
    $report.steps+=@{stage=$Label;exitCode=$v.exitCode;timedOut=$v.timedOut;elapsedSeconds=$v.elapsedSeconds;sqlStates=$v.sqlStates};Save
    if($v.exitCode -ne 0 -or $v.timedOut -or $v.stdout.Length -gt 65536){throw 'HBA_STAGE_METADATA_QUERY_FAILED'}
    $rows=@($v.stdout.Trim() -split '\r?\n'|Where-Object {$_.Trim()});if($rows.Count -ne 1){throw 'HBA_STAGE_METADATA_RESPONSE_INVALID'}
    $value=$rows[0]|ConvertFrom-Json;Assert-PaperHbaMetadata $value
    return $value|Select-Object version,database,databaseOid,clusterId,serverPort,serverVersion,serverStartEpoch,adminSuperuser,writerCount,writerLoginEnabled,hbaPath,hbaBytes,hbaHash,hbaRuleCount,hbaErrorCount,readOnly
}
function Route($Metadata,[string]$Label){
    $value=(Native @('exec',$containerId,'java','-Xmx64m','-cp',$containerPath,'in.marketbrain.paper.PaperApplicationRouteProbe','marketbrain','5432',$id) 55 $Label)|ConvertFrom-Json
    $value=$value|Select-Object version,status,database,databaseOid,applicationUser,sessionUser,clientAddress,serverAddress,serverPort,serverStartEpoch,applicationName,readOnly,databaseWritesPerformed,writerLoginAttempted,actionExecutionEnabled
    Assert-PaperHbaRoute $value $Metadata $id;return $value
}
try {
    Stage 0 'PREFLIGHT' 'Purpose: protect and apply only the reviewed writer rules. Writer stays NOLOGIN; no trading or firewall change.'
    $principal=[Security.Principal.WindowsPrincipal]::new([Security.Principal.WindowsIdentity]::GetCurrent())
    if(-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)){throw 'HBA_STAGE_WINDOWS_ADMIN_REQUIRED'}
    $mutex=[Threading.Mutex]::new($false,'Global\MarketBrainPaperHbaRestrictionV1')
    try {$held=$mutex.WaitOne(0)}catch [Threading.AbandonedMutexException]{$held=$true;throw 'HBA_STAGE_INTERRUPTED_RUN_REQUIRES_RECOVERY'}
    if(-not $held){throw 'HBA_STAGE_ANOTHER_RUN_ACTIVE'}
    $accepted=Read-PaperHbaAcceptedPlan $ReviewedPlanPath;$report.sourceHash=(Get-FileHash -LiteralPath $ReviewedPlanPath).Hash
    $dirty=@(git -C $root status --porcelain);if($LASTEXITCODE -ne 0 -or $dirty.Count){throw 'HBA_STAGE_WORKTREE_REQUIRES_REVIEW'}
    $report.revision=(git -C $root rev-parse HEAD|Out-String).Trim();if($LASTEXITCODE -ne 0){throw 'HBA_STAGE_REVISION_UNAVAILABLE'}
    foreach($file in @('SetPaperWriterHbaRestriction.ps1','PaperWriterHbaStage.ps1','PaperWriterHbaPlan.ps1','PaperWriterRestriction.ps1','PaperWriterInstallation.ps1','PaperWriterAccessReview.ps1','PaperWriterPreflight.ps1','PaperWriterCustody.ps1','PaperStorageKey.ps1','NumericalHistoryEvidence.ps1')){$report.manifest[$file]=(Get-FileHash -LiteralPath (Join-Path $PSScriptRoot $file)).Hash}
    $docker=(Get-Command docker.exe -CommandType Application -ErrorAction Stop|Select-Object -First 1).Source
    $javac=(Get-Command javac -CommandType Application -ErrorAction Stop|Select-Object -First 1).Source
    $psql=Join-Path (Assert-PaperCustodyPath $PostgreSqlBin) 'psql.exe';if(-not(Test-Path -LiteralPath $psql -PathType Leaf)){throw 'HBA_STAGE_PSQL_MISSING'}
    Stage 10 'CONTAINER' 'Checking that exactly one application container is running before compiling.'
    $ids=@((Native @('ps','--filter','label=com.docker.compose.service=marketbrain-service','--format','{{.ID}}') 15 'LOCATE_APPLICATION') -split '\r?\n'|Where-Object {$_})
    if($ids.Count -eq 0){throw 'HBA_STAGE_APPLICATION_NOT_RUNNING'}
    if($ids.Count -ne 1){throw 'HBA_STAGE_MULTIPLE_APPLICATION_CONTAINERS'}
    $containerId=$ids[0];if($containerId -cnotmatch '^[a-f0-9]{12,64}$'){throw 'HBA_STAGE_CONTAINER_RESPONSE_INVALID'}
    [void][IO.Directory]::CreateDirectory($fixture)
    $probe=Join-Path $root 'marketbrain-service/src/main/java/in/marketbrain/paper/PaperApplicationRouteProbe.java';$report.manifest['PaperApplicationRouteProbe.java']=(Get-FileHash -LiteralPath $probe).Hash
    $null=Native @('--release','21','-d',$fixture,$probe) 60 'COMPILE_DIAGNOSTIC' $javac
    $null=Native @('exec',$containerId,'mkdir','-m','700',$containerPath) 15 'CREATE_TEMP_DIRECTORY';$created=$true
    $copied=$true;$null=Native @('cp',($fixture+'\.'),($containerId+':'+$containerPath)) 15 'COPY_DIAGNOSTIC'
    Stage 25 'FRESH_PREFLIGHT' 'Reading fresh PostgreSQL, file and application identity. Administrator password stays local.'
    if((Read-Host 'Confirm target database: type marketbrain') -cne 'marketbrain'){throw 'HBA_STAGE_TARGET_NOT_CONFIRMED'}
    $admin=Read-Host 'PostgreSQL administrator username (not Windows login)'
    if($admin -cnotmatch '^[A-Za-z_][A-Za-z0-9_]{0,62}$'){throw 'HBA_STAGE_ADMIN_NAME_INVALID'}
    $secure=Read-Host 'PostgreSQL administrator password (local only)' -AsSecureString
    $password=[Net.NetworkCredential]::new('', $secure).Password;if(-not $password){throw 'HBA_STAGE_PASSWORD_REQUIRED'}
    $before=Metadata 'METADATA_BEFORE';$report.metadataBefore=$before
    foreach($property in $before.PSObject.Properties){if($property.Value -cne $accepted.metadata.($property.Name)){throw 'HBA_STAGE_REVIEWED_METADATA_CHANGED'}}
    $report.routeBefore=Route $before 'APPLICATION_BEFORE'
    $plan=Read-PaperHbaLocalPlan $before
    foreach($field in @('originalHash','originalBytes','candidateHash','candidateBytes','aclFingerprint','addedBlock')){if($plan.$field -cne $accepted.filePlan.$field){throw 'HBA_STAGE_REVIEWED_FILE_CHANGED'}}
    if(-not $Apply){$report.status='HBA_STAGE_PREFLIGHT_PASSED_APPLY_NOT_REQUESTED'}
    else {
        Write-Host 'This changes pg_hba.conf for subsequent connections. Do not edit PostgreSQL configuration or restart services during this run.' -ForegroundColor Yellow
        if((Read-Host 'Type APPLY WRITER RESTRICTION to create a protected backup and apply the reviewed rules') -cne 'APPLY WRITER RESTRICTION'){throw 'HBA_STAGE_APPLY_NOT_CONFIRMED'}
        Stage 45 'BACKUP' 'Saving and verifying original bytes, candidate and permissions in a private local recovery directory.'
        $report.backupDirectory=New-PaperHbaBackup ($before.hbaPath.Replace('/','\')) $plan 'C:\MarketBrainData\Secrets\PaperWriterHba' $id;Save
        $fresh=Metadata 'METADATA_PRE_REPLACE'
        if(($before|ConvertTo-Json -Compress) -cne ($fresh|ConvertTo-Json -Compress)){throw 'HBA_STAGE_PREFLIGHT_DRIFT'}
        $null=Route $fresh 'APPLICATION_PRE_REPLACE'
        Stage 60 'REPLACE_AND_VERIFY' 'Applying the exact prefix; independently checking PostgreSQL parsing, NOLOGIN and fresh application access.'
        Invoke-PaperHbaTransaction $report.backupDirectory {
            $after=Metadata 'METADATA_AFTER';$report.metadataAfter=$after
            foreach($property in $before.PSObject.Properties){if($property.Name -notin @('hbaHash','hbaBytes','hbaRuleCount') -and $property.Value -cne $after.($property.Name)){throw 'HBA_STAGE_POST_METADATA_DRIFT'}}
            if($after.hbaHash -cne $plan.candidateHash -or $after.hbaBytes -ne $plan.candidateBytes -or $after.hbaRuleCount -ne ($before.hbaRuleCount+4)){throw 'HBA_STAGE_POST_RULES_MISMATCH'}
            $report.routeAfter=Route $after 'APPLICATION_AFTER'
            $journal=Read-PaperHbaBackup $report.backupDirectory
            Assert-PaperHbaFileState $journal.target $plan.candidateHash $journal.originalSddl
        } $report
        $report.status='HBA_RESTRICTION_STAGED_WRITER_DISABLED'
        Stage 90 'COMPLETE' 'Rules staged and verified. Backup retained. Writer activation and effective firewall access review remain pending.'
    }
}catch {
    $report.status='FAILED';$report.failureCode='HBA_STAGE_FAILED'
    $report.failureDetails=@{exceptionType=$_.Exception.GetType().FullName;hresult=$_.Exception.HResult;line=$_.InvocationInfo.ScriptLineNumber}
    if($_.Exception.Data.Contains('fileState')){$report.failureDetails.fileState=$_.Exception.Data['fileState']}
    if($_.Exception.Message -cmatch '^(HBA_STAGE|HBA_PLAN|RESTRICTION|CUSTODY)_[A-Z_]+$'){$report.failureCode=$_.Exception.Message}
    if($report.rollbackFileVerified){
        try {$restored=Metadata 'METADATA_AFTER_ROLLBACK';if(($before|ConvertTo-Json -Compress) -cne ($restored|ConvertTo-Json -Compress)){throw 'HBA_STAGE_ROLLBACK_METADATA_CHANGED'};$null=Route $restored 'APPLICATION_AFTER_ROLLBACK';$report.rollbackConnectionsVerified=$true;$report.status='FAILED_ROLLED_BACK'}
        catch {$report.status='FAILED_RECOVERY_REVIEW_REQUIRED'}
    }
}finally {
    $password=$null;if($secure){$secure.Dispose()}
    try {
        if($created -and $containerId -cmatch '^[a-f0-9]{12,64}$' -and $containerPath -ceq ('/tmp/mb-hba-stage-'+$id)){
            if($copied){$null=Native @('exec',$containerId,'rm','-f','--',($containerPath+'/in/marketbrain/paper/PaperApplicationRouteProbe.class')) 15 'REMOVE_DIAGNOSTIC_CLASS';$null=Native @('exec',$containerId,'rmdir',($containerPath+'/in/marketbrain/paper'),($containerPath+'/in/marketbrain'),($containerPath+'/in')) 15 'REMOVE_DIAGNOSTIC_PACKAGES'}
            $null=Native @('exec',$containerId,'rmdir',$containerPath) 15 'REMOVE_DIAGNOSTIC_DIRECTORY'
        }
        if(Test-Path -LiteralPath $fixture){$null=Assert-PaperCustodyPath $fixture;$class=Join-Path $fixture 'in\marketbrain\paper\PaperApplicationRouteProbe.class';if(Test-Path -LiteralPath $class){$null=Assert-PaperCustodyPath $class;Remove-Item -LiteralPath $class};foreach($suffix in @('in\marketbrain\paper','in\marketbrain','in')){$dir=Join-Path $fixture $suffix;if(Test-Path -LiteralPath $dir){$null=Assert-PaperCustodyPath $dir;[IO.Directory]::Delete($dir,$false)}};[IO.Directory]::Delete($fixture,$false)}
        $report.cleanupComplete=$true
    }catch{$report.cleanupFailureCode='HBA_STAGE_DIAGNOSTIC_CLEANUP_REQUIRED';if($report.status -notlike 'FAILED*'){$report.status='STAGED_CLEANUP_REVIEW_REQUIRED'}}
    if($held){$mutex.ReleaseMutex()};if($mutex){$mutex.Dispose()}
    Save;Write-Progress -Activity 'Writer authentication restriction' -Completed
    Write-Host ('[100%] '+$report.status+'; elapsed='+[math]::Round($report.elapsedSeconds,2)+'s');Write-Host "Share this ONE file: $path"
    if($report.backupDirectory){Write-Host ('Private recovery directory (do not share): '+$report.backupDirectory)}
}
if($report.status -notin @('HBA_RESTRICTION_STAGED_WRITER_DISABLED','HBA_STAGE_PREFLIGHT_PASSED_APPLY_NOT_REQUESTED')){throw ('HBA stage stopped: '+$report.failureCode+'; recovery='+$report.recoveryStatus)}
