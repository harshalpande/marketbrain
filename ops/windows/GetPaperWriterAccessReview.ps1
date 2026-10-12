#Requires -Version 7.0
[CmdletBinding()]
param([Parameter(Mandatory)][string]$InstallationReportPath,
      [Parameter(Mandatory)][string]$FoundationReportPath,
      [string]$PostgreSqlBin='C:\Program Files\PostgreSQL\18\bin',
      [string]$OutputDirectory='C:\MarketBrainData\Review')
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'NumericalHistoryEvidence.ps1')
. (Join-Path $PSScriptRoot 'PaperWriterInstallation.ps1')
. (Join-Path $PSScriptRoot 'PaperWriterConnectionReview.ps1')
. (Join-Path $PSScriptRoot 'PaperWriterPreflight.ps1')
. (Join-Path $PSScriptRoot 'PaperWriterCustody.ps1')
. (Join-Path $PSScriptRoot 'PaperWriterAccessReview.ps1')
$root=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../..'));$id=[Guid]::NewGuid().ToString('N')
$out=Assert-PaperCustodyPath $OutputDirectory
[void](New-Item -ItemType Directory -Path $out -Force)
$path=Join-Path $out ('paper-writer-access-{0}-{1}.json' -f (Get-Date -Format 'yyyyMMdd-HHmmss'),$id.Substring(0,12))
$fixture=Join-Path $out ('route-probe-'+$id);$containerPath='/tmp/mb-route-'+$id
$timer=[Diagnostics.Stopwatch]::StartNew();$password=$null;$secure=$null;$containerId=$null;$copied=$false;$containerCreated=$false;$phase='PREFLIGHT'
$report=[ordered]@{version='PAPER_WRITER_ACCESS_V1';status='RUNNING';runId=$id;revision=$null;manifest=@{};inputHashes=@{};events=@();steps=@();route=$null;firewall=$null;inventory=$null;verification=$null;findings=@();failureCode=$null;cleanupFailureCode=$null;diagnosticFailureCode=$null;elapsedSeconds=0;diagnosticCleanupComplete=$false;existingApplicationLoginProbed=$false;writerLoginAttempted=$false;configurationChanged=$false;databaseWritesPerformed=$false;credentialsSaved=$false;applicationWriterActivated=$false;actionExecutionEnabled=$false;externalReachabilityTested=$false;transportPolicy='PRIVATE_SAME_MACHINE_TLS_DEFERRED'}
function Save {$report.elapsedSeconds=$timer.Elapsed.TotalSeconds;Save-NumericalHistoryReport $report $path -Compact}
function Stage([int]$Percent,[string]$Message){$report.events+=@{percent=$Percent;message=$Message};Save;Write-Host "[$Percent%] $Message";Write-Progress -Activity 'Paper writer access review' -Status $Message -PercentComplete $Percent}
function Native([string]$Executable,[string[]]$Arguments,[int]$Limit,[string]$Label){
    $r=Invoke-PaperCatalogProcess $Executable $Arguments $root $Limit
    $report.steps+=@{stage=$Label;exitCode=$r.exitCode;timedOut=$r.timedOut;elapsedSeconds=$r.elapsedSeconds};Save
    if($r.exitCode -ne 0 -or $r.timedOut -or $r.stdout.Length -gt 2MB){
        if($Label -in @('APPLICATION_ROUTE_PROBE','FIREWALL_METADATA') -and $r.stdout.Length -lt 65536){
            try{$diagnostic=$r.stdout|ConvertFrom-Json;if($diagnostic.status -ceq 'FAILED' -and $diagnostic.failureCode -cmatch '^(PROBE|FIREWALL)_[A-Z_]+$'){$report.diagnosticFailureCode=$diagnostic.failureCode}}catch{}
        }
        throw 'ACCESS_NATIVE_STAGE_FAILED'
    }
    return $r.stdout.Trim()
}
try {
    Stage 0 'Purpose: explain the database listening boundary and observe a read-only session from the running app. No activation.'
    $principal=[Security.Principal.WindowsPrincipal]::new([Security.Principal.WindowsIdentity]::GetCurrent())
    if(-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)){throw 'ACCESS_RUN_POWERSHELL_AS_WINDOWS_ADMINISTRATOR'}
    foreach($file in @($InstallationReportPath,$FoundationReportPath)){if((Get-Item -LiteralPath $file).Length -gt 2MB){throw 'ACCESS_INPUT_TOO_LARGE'}}
    $saved=Get-Content -LiteralPath $InstallationReportPath -Raw|ConvertFrom-Json;Assert-PaperInstalledReport $saved
    $foundation=Get-Content -LiteralPath $FoundationReportPath -Raw|ConvertFrom-Json;Assert-PaperFoundationEvidence $foundation
    $report.inputHashes=@{installation=(Get-FileHash -LiteralPath $InstallationReportPath).Hash;foundation=(Get-FileHash -LiteralPath $FoundationReportPath).Hash}
    $dirty=@(git -C $root status --porcelain);if($LASTEXITCODE -ne 0 -or $dirty.Count){throw 'ACCESS_WORKTREE_REQUIRES_REVIEW'}
    $report.revision=(git -C $root rev-parse HEAD|Out-String).Trim();if($LASTEXITCODE -ne 0){throw 'ACCESS_REVISION_UNAVAILABLE'}
    foreach($file in @('ops/windows/GetPaperWriterAccessReview.ps1','ops/windows/PaperWriterAccessReview.ps1','ops/windows/PaperWriterFirewallSnapshot.ps1','ops/windows/PaperWriterInstallation.ps1','ops/windows/PaperWriterConnectionReview.ps1','ops/windows/PaperWriterPreflight.ps1','ops/windows/PaperWriterCustody.ps1','ops/windows/PaperStorageKey.ps1','ops/windows/NumericalHistoryEvidence.ps1','marketbrain-service/src/main/java/in/marketbrain/paper/PaperApplicationRouteProbe.java','marketbrain-service/src/main/resources/paper/writer-connection-review-v1.sql','marketbrain-service/src/main/resources/paper/writer-install-plan-v1.sql','marketbrain-service/src/main/resources/paper/writer-install-verify-v1.sql','marketbrain-service/src/main/resources/paper/approval-writer-v1.sql')){$report.manifest[$file]=(Get-FileHash -LiteralPath (Join-Path $root $file)).Hash}
    $docker=(Get-Command docker.exe -CommandType Application -ErrorAction Stop|Select-Object -First 1).Source
    $javac=(Get-Command javac -CommandType Application -ErrorAction Stop|Select-Object -First 1).Source
    $psql=Join-Path $PostgreSqlBin 'psql.exe';if(-not(Test-Path -LiteralPath $psql -PathType Leaf)){throw 'ACCESS_PSQL_MISSING'}
    $phase='FIREWALL'
    Stage 15 'Reading effective Windows firewall profile/rule metadata relevant to port 5432; no firewall changes.'
    $firewallResult=Invoke-PaperCatalogProcess (Join-Path $PSHOME 'pwsh.exe') @('-NoLogo','-NoProfile','-NonInteractive','-File',(Join-Path $PSScriptRoot 'PaperWriterFirewallSnapshot.ps1')) $root 210
    $report.steps+=@{stage='FIREWALL_METADATA';exitCode=$firewallResult.exitCode;timedOut=$firewallResult.timedOut;elapsedSeconds=$firewallResult.elapsedSeconds}
    $report.firewall=Read-PaperFirewallOutput $firewallResult.stdout $firewallResult.timedOut
    $report.diagnosticFailureCode=$report.firewall.failureCode;Save
    if($firewallResult.exitCode -ne 0 -or $firewallResult.timedOut -or $report.firewall.status -cne 'METADATA_CAPTURED_REVIEW_REQUIRED' -or $report.firewall.truncated){throw 'ACCESS_FIREWALL_INCOMPLETE'}
    $phase='ROUTE_PROBE'
    Stage 35 'Compiling a temporary diagnostic class with native JDK 21+; application rebuild is not needed.'
    [void](New-Item -ItemType Directory -Path $fixture)
    $null=Native $javac @('--release','21','-d',$fixture,(Join-Path $root 'marketbrain-service/src/main/java/in/marketbrain/paper/PaperApplicationRouteProbe.java')) 60 'COMPILE_DIAGNOSTIC'
    $containerId=Native $docker @('ps','--filter','label=com.docker.compose.service=marketbrain-service','--format','{{.ID}}') 15 'LOCATE_APPLICATION'
    if($containerId -cnotmatch '^[a-f0-9]{12,64}$'){throw 'ACCESS_CONTAINER_MISSING_OR_AMBIGUOUS'}
    $null=Native $docker @('exec',$containerId,'mkdir','-m','700',$containerPath) 15 'CREATE_TEMP_DIAGNOSTIC_DIRECTORY';$containerCreated=$true
    $null=Native $docker @('cp',($fixture+'\.'),($containerId+':'+$containerPath)) 15 'COPY_DIAGNOSTIC';$copied=$true
    Stage 50 'Opening one read-only session inside the existing container using its existing credentials; no writer login.'
    $report.existingApplicationLoginProbed=$false
    $routeText=Native $docker @('exec',$containerId,'java','-Xmx64m','-cp',$containerPath,'in.marketbrain.paper.PaperApplicationRouteProbe',$saved.target.database,[string]$saved.target.port,$id) 55 'APPLICATION_ROUTE_PROBE'
    # Never retain unexpected fields from a diagnostic response.
    $report.route=$routeText|ConvertFrom-Json|Select-Object version,status,database,databaseOid,applicationUser,sessionUser,clientAddress,serverAddress,serverPort,serverStartEpoch,applicationName,readOnly,databaseWritesPerformed,writerLoginAttempted,actionExecutionEnabled
    $phase='ADMIN_METADATA'
    Stage 65 'Confirming database identity and reading current authentication rules using a local administrator connection.'
    Write-Host "Target: 127.0.0.1:$($saved.target.port) / $($saved.target.database)"
    if((Read-Host 'Confirm database name') -cne $saved.target.database){throw 'ACCESS_TARGET_NOT_CONFIRMED'}
    $admin=Read-Host 'PostgreSQL administrator username (not Windows login)'
    if($admin -cnotmatch '^[A-Za-z_][A-Za-z0-9_]{0,62}$'){throw 'ACCESS_ADMIN_NAME_INVALID'}
    $secure=Read-Host 'PostgreSQL administrator password (local only)' -AsSecureString
    $password=[Net.NetworkCredential]::new('', $secure).Password;if(-not $password){throw 'ACCESS_PASSWORD_REQUIRED'}
    $result=Invoke-PaperInstallerPsql $psql $saved.target.database $saved.target.port $admin $password (New-PaperAccessReviewSql $saved.plan)
    $report.steps+=@{stage='ADMIN_METADATA';exitCode=$result.exitCode;timedOut=$result.timedOut;elapsedSeconds=$result.elapsedSeconds;sqlStates=$result.sqlStates;assertionFailures=$result.assertionFailures}
    if($result.exitCode -ne 0 -or $result.timedOut -or $result.stdout.Length -gt 2MB){throw 'ACCESS_DATABASE_METADATA_FAILED'}
    $rows=@($result.stdout.Trim() -split '\r?\n'|Where-Object {$_.Trim().Length});if($rows.Count -ne 3){throw 'ACCESS_DATABASE_RESPONSE_INVALID'}
    $receipt=$rows[0]|ConvertFrom-Json;$inventory=$rows[1]|ConvertFrom-Json;$server=$rows[2]|ConvertFrom-Json
    Assert-PaperWriterInstallReceipt $receipt 'Verify' $saved.plan.planHash
    Assert-PaperConnectionReview $inventory $saved.plan $saved.target.port
    Assert-PaperApplicationRoute $report.route $inventory $server $id
    $report.existingApplicationLoginProbed=$true
    $report.verification=$receipt;$report.inventory=$inventory
    $report.findings=@(Get-PaperAccessFindings $inventory $report.firewall $report.route)
    Stage 90 'Read-only session correlated with the inspected database; preserving findings for credential/access preparation.'
    $report.status='ACCESS_EVIDENCE_CAPTURED_REVIEW_REQUIRED'
}catch{$report.status='FAILED';$report.failureCode=$phase+'_FAILED';if($_.Exception.Message -cmatch '^ACCESS_[A-Z_]+$'){$report.failureCode=$_.Exception.Message}}
finally {
    $password=$null;if($secure){$secure.Dispose()}
    try {
        # Only the generated diagnostic's exact paths; no recursive delete and no application files.
        if($containerCreated -and $containerId -cmatch '^[a-f0-9]{12,64}$' -and $containerPath -ceq ('/tmp/mb-route-'+$id)){
            if($copied){$null=Native $docker @('exec',$containerId,'rm','--',($containerPath+'/in/marketbrain/paper/PaperApplicationRouteProbe.class')) 15 'REMOVE_DIAGNOSTIC_CLASS'
                $null=Native $docker @('exec',$containerId,'rmdir',($containerPath+'/in/marketbrain/paper'),($containerPath+'/in/marketbrain'),($containerPath+'/in')) 15 'REMOVE_DIAGNOSTIC_PACKAGES'}
            $null=Native $docker @('exec',$containerId,'rmdir',$containerPath) 15 'REMOVE_DIAGNOSTIC_DIRECTORY'
        }
        if(Test-Path -LiteralPath $fixture){
            if((Assert-PaperCustodyPath $fixture) -cne [IO.Path]::GetFullPath((Join-Path $out ('route-probe-'+$id)))){throw 'ACCESS_CLEANUP_SCOPE_INVALID'}
            $class=Join-Path $fixture 'in\marketbrain\paper\PaperApplicationRouteProbe.class'
            if(Test-Path -LiteralPath $class){$null=Assert-PaperCustodyPath $class;Remove-Item -LiteralPath $class}
            foreach($suffix in @('in\marketbrain\paper','in\marketbrain','in')){$dir=Join-Path $fixture $suffix;if(Test-Path -LiteralPath $dir){$null=Assert-PaperCustodyPath $dir;[IO.Directory]::Delete($dir,$false)}}
            [IO.Directory]::Delete($fixture,$false)
        }
        $report.diagnosticCleanupComplete=$true
    }catch{$report.status='FAILED';$report.cleanupFailureCode='ACCESS_DIAGNOSTIC_CLEANUP_REQUIRES_REVIEW';if(-not $report.failureCode){$report.failureCode=$report.cleanupFailureCode}}
    Save;Write-Progress -Activity 'Paper writer access review' -Completed
    Write-Host ('[100%] '+$report.status+'; elapsed='+[math]::Round($report.elapsedSeconds,2)+'s')
    Write-Host "Share this ONE file: $path"
}
if($report.status -ceq 'FAILED'){throw ('Access review stopped: '+$report.failureCode)}
