#Requires -Version 7.0
[CmdletBinding()]param(
    [Parameter(Mandatory)][string]$PreparationReportPath,
    [string]$PostgreSqlBin='C:\Program Files\PostgreSQL\18\bin',
    [string]$OutputDirectory='C:\MarketBrainData\Review'
)
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'NumericalHistoryEvidence.ps1')
. (Join-Path $PSScriptRoot 'PaperWriterCustody.ps1')
. (Join-Path $PSScriptRoot 'PaperWriterPreflight.ps1')
. (Join-Path $PSScriptRoot 'PaperWriterInstallation.ps1')
. (Join-Path $PSScriptRoot 'PaperWriterAccessReview.ps1')
. (Join-Path $PSScriptRoot 'PaperWriterRestriction.ps1')
. (Join-Path $PSScriptRoot 'PaperWriterHbaPlan.ps1')
$root=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../..'));$id=[Guid]::NewGuid().ToString('N')
$out=Assert-PaperCustodyPath $OutputDirectory;[void][IO.Directory]::CreateDirectory($out)
$path=Join-Path $out ('paper-writer-hba-plan-'+(Get-Date -Format 'yyyyMMdd-HHmmss')+'-'+$id.Substring(0,12)+'.json')
$fixture=Join-Path $out ('hba-probe-'+$id);$containerPath='/tmp/mb-hba-'+$id
$timer=[Diagnostics.Stopwatch]::StartNew();$password=$null;$secure=$null;$containerId=$null;$created=$false;$copied=$false
$report=[ordered]@{version='PAPER_WRITER_HBA_PLAN_V1';status='RUNNING';runId=$id;revision=$null;sourceHash=$null;manifest=@{};events=@();steps=@();phase='PREFLIGHT';metadata=$null;route=$null;filePlan=$null;planFingerprint=$null;failureCode=$null;cleanupFailureCode=$null;cleanupComplete=$false;databaseContacted=$false;databaseWritesPerformed=$false;realHbaRead=$false;hbaChanged=$false;firewallChanged=$false;writerLoginAttempted=$false;credentialsSaved=$false;applicationWriterActivated=$false;actionExecutionEnabled=$false;elapsedSeconds=0}
function Save {$report.elapsedSeconds=$timer.Elapsed.TotalSeconds;Save-NumericalHistoryReport $report $path -Compact}
function Stage([int]$Percent,[string]$Phase,[string]$Message){$report.phase=$Phase;$report.events+=@{percent=$Percent;message=$Message};Save;Write-Host "[$Percent%] $Message";Write-Progress -Activity 'Writer authentication file plan' -Status $Message -PercentComplete $Percent}
function Native([string[]]$Arguments,[int]$Limit,[string]$Label,[string]$Executable=$docker){
    $v=Invoke-PaperCatalogProcess $Executable $Arguments $root $Limit
    $report.steps+=@{stage=$Label;exitCode=$v.exitCode;timedOut=$v.timedOut;elapsedSeconds=$v.elapsedSeconds};Save
    if($v.exitCode -ne 0 -or $v.timedOut -or $v.stdout.Length -gt 65536){throw 'HBA_PLAN_NATIVE_STAGE_FAILED'}
    return $v.stdout.Trim()
}
function Metadata([string]$Label){
    $report.databaseContacted=$true
    $v=Invoke-PaperInstallerPsql $psql 'marketbrain' 5432 $admin $password (New-PaperHbaMetadataSql)
    $report.steps+=@{stage=$Label;exitCode=$v.exitCode;timedOut=$v.timedOut;elapsedSeconds=$v.elapsedSeconds;sqlStates=$v.sqlStates};Save
    if($v.exitCode -ne 0 -or $v.timedOut -or $v.stdout.Length -gt 65536){throw 'HBA_PLAN_METADATA_QUERY_FAILED'}
    $rows=@($v.stdout.Trim() -split '\r?\n'|Where-Object {$_.Trim()})
    if($rows.Count -ne 1){throw 'HBA_PLAN_METADATA_RESPONSE_INVALID'}
    $value=$rows[0]|ConvertFrom-Json
    Assert-PaperHbaMetadata $value
    return $value|Select-Object version,database,databaseOid,clusterId,serverPort,serverVersion,serverStartEpoch,adminSuperuser,writerCount,writerLoginEnabled,hbaPath,hbaBytes,hbaHash,hbaRuleCount,hbaErrorCount,readOnly
}
try {
    Stage 0 'PREFLIGHT' 'Purpose: read current database/file identity and prepare a diff. No authentication-file edits or writer login.'
    $principal=[Security.Principal.WindowsPrincipal]::new([Security.Principal.WindowsIdentity]::GetCurrent())
    if(-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)){throw 'HBA_PLAN_WINDOWS_ADMIN_REQUIRED'}
    $inputPath=Assert-PaperCustodyPath $PreparationReportPath;$null=Read-PaperHbaPreparation $inputPath
    $report.sourceHash=(Get-FileHash -LiteralPath $inputPath).Hash
    $dirty=@(git -C $root status --porcelain);if($LASTEXITCODE -ne 0 -or $dirty.Count){throw 'HBA_PLAN_WORKTREE_REQUIRES_REVIEW'}
    $report.revision=(git -C $root rev-parse HEAD|Out-String).Trim();if($LASTEXITCODE -ne 0){throw 'HBA_PLAN_REVISION_UNAVAILABLE'}
    foreach($file in @('ops/windows/GetPaperWriterHbaPlan.ps1','ops/windows/PaperWriterHbaPlan.ps1','ops/windows/PaperWriterRestriction.ps1','ops/windows/PaperWriterInstallation.ps1','ops/windows/PaperWriterAccessReview.ps1','ops/windows/PaperWriterPreflight.ps1','ops/windows/PaperWriterCustody.ps1','ops/windows/PaperStorageKey.ps1','ops/windows/NumericalHistoryEvidence.ps1','marketbrain-service/src/main/java/in/marketbrain/paper/PaperApplicationRouteProbe.java')){$report.manifest[$file]=(Get-FileHash -LiteralPath (Join-Path $root $file)).Hash}
    $docker=(Get-Command docker.exe -CommandType Application -ErrorAction Stop|Select-Object -First 1).Source
    $javac=(Get-Command javac -CommandType Application -ErrorAction Stop|Select-Object -First 1).Source
    $psql=Join-Path (Assert-PaperCustodyPath $PostgreSqlBin) 'psql.exe'
    if(-not(Test-Path -LiteralPath $psql -PathType Leaf)){throw 'HBA_PLAN_PSQL_MISSING'}
    Stage 15 'COMPILE_PROBE' 'Compiling the existing read-only application probe. No rebuild or restart.'
    [void][IO.Directory]::CreateDirectory($fixture)
    $null=Native @('--release','21','-d',$fixture,(Join-Path $root 'marketbrain-service/src/main/java/in/marketbrain/paper/PaperApplicationRouteProbe.java')) 60 'COMPILE_DIAGNOSTIC' $javac
    $containerId=Native @('ps','--filter','label=com.docker.compose.service=marketbrain-service','--format','{{.ID}}') 15 'LOCATE_APPLICATION'
    if($containerId -cnotmatch '^[a-f0-9]{12,64}$'){throw 'HBA_PLAN_CONTAINER_AMBIGUOUS'}
    $null=Native @('exec',$containerId,'mkdir','-m','700',$containerPath) 15 'CREATE_TEMP_DIRECTORY';$created=$true
    $copied=$true;$null=Native @('cp',($fixture+'\.'),($containerId+':'+$containerPath)) 15 'COPY_DIAGNOSTIC'
    Stage 30 'ADMIN_METADATA' 'Reading bounded PostgreSQL identity and authentication-file metadata. Password stays local.'
    if((Read-Host 'Confirm read-only target database: type marketbrain') -cne 'marketbrain'){throw 'HBA_PLAN_TARGET_NOT_CONFIRMED'}
    $admin=Read-Host 'PostgreSQL administrator username (not Windows login)'
    if($admin -cnotmatch '^[A-Za-z_][A-Za-z0-9_]{0,62}$'){throw 'HBA_PLAN_ADMIN_NAME_INVALID'}
    $secure=Read-Host 'PostgreSQL administrator password (local only)' -AsSecureString
    $password=[Net.NetworkCredential]::new('', $secure).Password;if(-not $password){throw 'HBA_PLAN_PASSWORD_REQUIRED'}
    $report.realHbaRead=$true;$before=Metadata 'METADATA_BEFORE';$report.metadata=$before;Save
    Stage 50 'APPLICATION_ROUTE' 'Opening a fresh read-only application connection; writer remains NOLOGIN.'
    $routeText=Native @('exec',$containerId,'java','-Xmx64m','-cp',$containerPath,'in.marketbrain.paper.PaperApplicationRouteProbe','marketbrain','5432',$id) 55 'APPLICATION_ROUTE_PROBE'
    $route=$routeText|ConvertFrom-Json|Select-Object version,status,database,databaseOid,applicationUser,sessionUser,clientAddress,serverAddress,serverPort,serverStartEpoch,applicationName,readOnly,databaseWritesPerformed,writerLoginAttempted,actionExecutionEnabled
    Assert-PaperHbaRoute $route $before $id;$report.route=$route
    Stage 65 'LOCAL_FILE_PLAN' 'Matching local file bytes to the server hash; calculating proposed prefix and ACL fingerprint in memory.'
    $plan=Read-PaperHbaLocalPlan $before;$report.filePlan=$plan;Save
    Stage 80 'DRIFT_RECHECK' 'Rechecking database, file hash and ACL before publishing the plan. No apply operation.'
    $after=Metadata 'METADATA_AFTER'
    if(($before|ConvertTo-Json -Compress) -cne ($after|ConvertTo-Json -Compress)){throw 'HBA_PLAN_METADATA_CHANGED'}
    $rechecked=Read-PaperHbaLocalPlan $after
    if(($plan|ConvertTo-Json -Depth 5 -Compress) -cne ($rechecked|ConvertTo-Json -Depth 5 -Compress)){throw 'HBA_PLAN_FILE_OR_ACL_CHANGED'}
    $material=([ordered]@{metadata=$before;filePlan=$plan;clientAddress=$route.clientAddress;applicationUser=$route.applicationUser;sourceHash=$report.sourceHash}|ConvertTo-Json -Depth 6 -Compress)
    $report.planFingerprint=Get-PaperRestrictionHash ([Text.Encoding]::UTF8.GetBytes($material))
    Stage 90 'COMPLETE' 'Plan captured. Protected backup, live staging, credential activation and trading remain blocked.'
    $report.status='HBA_PLAN_CAPTURED_APPLY_BLOCKED'
}catch{
    $report.status='FAILED';$report.failureCode='HBA_PLAN_STAGE_FAILED'
    if($_.Exception.Message -cmatch '^(HBA_PLAN|RESTRICTION|CUSTODY)_[A-Z_]+$'){$report.failureCode=$_.Exception.Message}
}finally{
    $password=$null;if($secure){$secure.Dispose()}
    try {
        if($created -and $containerId -cmatch '^[a-f0-9]{12,64}$' -and $containerPath -ceq ('/tmp/mb-hba-'+$id)){
            if($copied){$null=Native @('exec',$containerId,'rm','-f','--',($containerPath+'/in/marketbrain/paper/PaperApplicationRouteProbe.class')) 15 'REMOVE_DIAGNOSTIC_CLASS'
                $null=Native @('exec',$containerId,'rmdir',($containerPath+'/in/marketbrain/paper'),($containerPath+'/in/marketbrain'),($containerPath+'/in')) 15 'REMOVE_DIAGNOSTIC_PACKAGES'}
            $null=Native @('exec',$containerId,'rmdir',$containerPath) 15 'REMOVE_DIAGNOSTIC_DIRECTORY'
        }
        if(Test-Path -LiteralPath $fixture){
            $null=Assert-PaperCustodyPath $fixture
            $class=Join-Path $fixture 'in\marketbrain\paper\PaperApplicationRouteProbe.class'
            if(Test-Path -LiteralPath $class){$null=Assert-PaperCustodyPath $class;Remove-Item -LiteralPath $class}
            foreach($suffix in @('in\marketbrain\paper','in\marketbrain','in')){$dir=Join-Path $fixture $suffix;if(Test-Path -LiteralPath $dir){$null=Assert-PaperCustodyPath $dir;[IO.Directory]::Delete($dir,$false)}}
            [IO.Directory]::Delete($fixture,$false)
        }
        $report.cleanupComplete=$true
    }catch{$report.status='FAILED';$report.cleanupFailureCode='HBA_PLAN_DIAGNOSTIC_CLEANUP_REQUIRED';if(-not $report.failureCode){$report.failureCode=$report.cleanupFailureCode}}
    Save;Write-Progress -Activity 'Writer authentication file plan' -Completed
    Write-Host ('[100%] '+$report.status+'; elapsed='+[math]::Round($report.elapsedSeconds,2)+'s');Write-Host "Share this ONE file: $path"
}
if($report.status -ceq 'FAILED'){throw ('HBA plan stopped: '+$report.failureCode)}
