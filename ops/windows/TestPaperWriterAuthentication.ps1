#Requires -Version 7.0
[CmdletBinding()]param(
 [Parameter(Mandatory)][string]$InstallationReportPath,
 [Parameter(Mandatory)][string]$CredentialReportPath,
 [ValidateSet('Test','Recover')][string]$Mode='Test',
 [string]$RecoveryReportPath,
 [string]$PostgreSqlBin='C:\Program Files\PostgreSQL\18\bin',
 [string]$OutputDirectory='C:\MarketBrainData\Review'
)
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'PaperWriterAuthentication.ps1')
. (Join-Path $PSScriptRoot 'PaperWriterPreflight.ps1')
. (Join-Path $PSScriptRoot 'PaperWriterAccessReview.ps1')
. (Join-Path $PSScriptRoot 'PaperWriterHbaPlan.ps1')
. (Join-Path $PSScriptRoot 'NumericalHistoryEvidence.ps1')
$repo=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../..'));$id=[Guid]::NewGuid().ToString('N')
$out=Assert-PaperCustodyPath $OutputDirectory;[void][IO.Directory]::CreateDirectory($out)
$path=Join-Path $out ('paper-writer-authentication-'+(Get-Date -Format 'yyyyMMdd-HHmmss')+'-'+$id.Substring(0,12)+'.json')
$fixture=Join-Path $out ('writer-auth-probe-'+$id);$containerPath='/tmp/mb-writer-auth-'+$id
$timer=[Diagnostics.Stopwatch]::StartNew();$payload=$null;$secretBytes=$null;$entropy=$null;$password=$null;$secure=$null;$verifier=$null;$lock=$null;$container=$null;$created=$false;$copied=$false
$report=[ordered]@{version='PAPER_WRITER_AUTHENTICATION_V1';status='RUNNING';mode=$Mode;runId=$id;leaseRunId=$id;revision=$null;manifest=@{};installationReportSha256=$null;credentialReportSha256=$null;steps=@();events=@();probes=@();failureCode=$null;recoveryFailureCode=$null;cleanupFailureCode=$null;leaseAttempted=$false;revocationVerified=$false;cleanupComplete=$false;writerLoginEnabled=$null;helperLoginEnabled=$null;writerSessions=$null;applicationWriterActivated=$false;accountRowsWritten=$false;actionExecutionEnabled=$false;elapsedSeconds=0}
$phase='PREFLIGHT'
function Save {$report.elapsedSeconds=$timer.Elapsed.TotalSeconds;Save-NumericalHistoryReport $report $path -Compact}
function Stage([int]$Percent,[string]$Message){$report.events+=@{percent=$Percent;message=$Message};Save;Write-Host "[$Percent%] $Message";Write-Progress -Activity 'Bounded writer authentication' -PercentComplete $Percent -Status $Message}
function Native([string[]]$Arguments,[int]$Limit,[string]$Label,[string]$Executable=$docker){
 $v=Invoke-PaperCatalogProcess $Executable $Arguments $repo $Limit
 $report.steps+=@{phase=$Label;exitCode=$v.exitCode;timedOut=$v.timedOut;elapsedSeconds=$v.elapsedSeconds};Save
 if($v.exitCode -ne 0 -or $v.timedOut -or $v.stdout.Length -gt 65536){throw 'AUTH_NATIVE_FAILED'};return $v.stdout.Trim()
}
function Database([string]$Operation){
 $sql=if($Operation -ceq 'Verify'){New-PaperCredentialSql 'Verify' $saved.plan $verifier}else{New-PaperAuthenticationSql $Operation $saved.plan $verifier $report.leaseRunId}
 try{$v=Invoke-PaperInstallerPsql $psql $saved.target.database $saved.target.port $admin $password $sql}finally{$sql=$null}
 $report.steps+=@{phase=$Operation;exitCode=$v.exitCode;timedOut=$v.timedOut;elapsedSeconds=$v.elapsedSeconds;sqlStates=$v.sqlStates;assertionFailures=$v.assertionFailures;stderrCharacters=$v.stderrCharacters};Save
 if($v.exitCode -ne 0 -or $v.timedOut -or $v.stdout.Length -gt 8192){throw 'AUTH_DATABASE_FAILED'}
 $value=$v.stdout.Trim()|ConvertFrom-Json
 if($Operation -ceq 'Verify'){Assert-PaperCredentialReceipt $value 'Verify' $saved.plan.planHash}
 else{Assert-PaperAuthenticationReceipt $value $Operation $report.leaseRunId}
 $report.writerLoginEnabled=$value.writerLoginEnabled;$report.helperLoginEnabled=$value.helperLoginEnabled
 if($Operation -cne 'Verify'){$report.writerSessions=$value.writerSessions}
 return $value
}
function Probe([string]$Operation){
 $arguments=@('exec','-i',$container,'java','-Xmx64m','-cp',$containerPath,'in.marketbrain.paper.PaperWriterAuthenticationProbe',$Operation,'marketbrain','5432',[string]$saved.plan.plan.databaseOid,$id,[string]$report.serverStartEpoch)
 $v=Invoke-PaperAuthenticationProcess $docker $arguments $repo $secretBytes 55
 $report.steps+=@{phase=('PROBE_'+$Operation);exitCode=$v.exitCode;elapsedSeconds=$v.elapsedSeconds;stderrCharacters=$v.stderrCharacters};Save
 if($v.stdout.Length -gt 8192){throw 'AUTH_PROBE_FAILED'}
 $value=$v.stdout.Trim()|ConvertFrom-Json
 if($v.exitCode -ne 0){if($value.failureCode -cmatch '^AUTH_[A-Z_]{1,90}$'){throw $value.failureCode};throw 'AUTH_PROBE_FAILED'}
 Assert-PaperAuthenticationProbe $value $Operation $id
 if($report.probes.Count -and ($value.connectorSha256 -cne $report.probes[0].connectorSha256 -or $value.driverSha256 -cne $report.probes[0].driverSha256)){throw 'AUTH_DEPLOYED_ARTIFACT_CHANGED'}
 $report.probes+=($value|Select-Object version,phase,status,runId,connectorSha256,driverSha256,accountRowsWritten,applicationWriterActivated,actionExecutionEnabled);Save
}
function Restore {
 # Disable and commit before session cleanup, so a later failure cannot roll back NOLOGIN.
 $null=Database 'Revoke';$null=Database 'Drain';$null=Database 'Readback'
 $report.revocationVerified=$true;Save
}
try {
 Stage 0 'One temporary writer login test; no messages, proposals or account writes. Preserve all existing secrets.'
 foreach($input in @(@($InstallationReportPath,'E213A645E4CD39D16E63BA69097E1D32B45E60DC49BF08EBE0B4B52DBD95B33D'),@($CredentialReportPath,'392C6ADB2BC0CD792ED86EBA3E0321E248F687F27FF439C1DD95DA607D99FE16'))){
  $inputPath=Assert-PaperCustodyPath $input[0]
  if((Get-Item -LiteralPath $inputPath).Length -gt 2MB -or (Get-FileHash -LiteralPath $inputPath).Hash -cne $input[1]){throw 'AUTH_ACCEPTED_REPORT_MISMATCH'}
 }
 $report.installationReportSha256=(Get-FileHash -LiteralPath $InstallationReportPath).Hash;$report.credentialReportSha256=(Get-FileHash -LiteralPath $CredentialReportPath).Hash
 $saved=Get-Content -LiteralPath $InstallationReportPath -Raw|ConvertFrom-Json;Assert-PaperInstalledReport $saved
 $credentialReport=Get-Content -LiteralPath $CredentialReportPath -Raw|ConvertFrom-Json
 if($credentialReport.status -cne 'WRITER_CREDENTIAL_STAGED_LOGIN_DISABLED'){throw 'AUTH_CREDENTIAL_REPORT_INVALID'}
 if($Mode -ceq 'Recover'){
  $recovery=Assert-PaperCustodyPath $RecoveryReportPath
  if((Get-Item -LiteralPath $recovery).Length -gt 2MB){throw 'AUTH_RECOVERY_REPORT_SIZE'}
  $prior=Get-Content -LiteralPath $recovery -Raw|ConvertFrom-Json
  if($prior.version -cne $report.version -or $prior.leaseRunId -cnotmatch '^[a-f0-9]{32}$' -or $prior.leaseAttempted -isnot [bool] -or -not $prior.leaseAttempted -or $prior.installationReportSha256 -cne $report.installationReportSha256 -or $prior.credentialReportSha256 -cne $report.credentialReportSha256){throw 'AUTH_RECOVERY_REPORT_INVALID'}
  $report.leaseRunId=$prior.leaseRunId;$report.priorDiagnosticCleanupVerified=$false
 } elseif($RecoveryReportPath){throw 'AUTH_UNEXPECTED_RECOVERY_PATH'}
 $report.revision=(& git -C $repo rev-parse HEAD|Out-String).Trim();if($LASTEXITCODE -ne 0){throw 'AUTH_REVISION_UNAVAILABLE'}
 $dirty=@(& git -C $repo status --porcelain);if($LASTEXITCODE -ne 0 -or $dirty.Count){throw 'AUTH_WORKTREE_NOT_CLEAN'}
 foreach($file in @('ops/windows/TestPaperWriterAuthentication.ps1','ops/windows/PaperWriterAuthentication.ps1','ops/windows/PaperWriterCredential.ps1','ops/windows/PaperWriterCustody.ps1','ops/windows/PaperWriterHbaStage.ps1','ops/windows/PaperStorageKey.ps1','ops/windows/PaperWriterInstallation.ps1','ops/windows/PaperWriterConnectionReview.ps1','ops/windows/PaperWriterPreflight.ps1','ops/windows/PaperWriterAccessReview.ps1','ops/windows/PaperWriterHbaPlan.ps1','ops/windows/NumericalHistoryEvidence.ps1','marketbrain-service/src/main/resources/paper/writer-install-plan-v1.sql','marketbrain-service/src/main/resources/paper/writer-install-verify-v1.sql','marketbrain-service/src/main/resources/paper/approval-writer-v1.sql','marketbrain-service/src/main/java/in/marketbrain/paper/PaperWriterAuthenticationProbe.java','marketbrain-service/src/main/java/in/marketbrain/paper/PaperApplicationRouteProbe.java')){$report.manifest[$file]=(Get-FileHash -LiteralPath (Join-Path $repo $file)).Hash}
 $psql=Join-Path (Assert-PaperCustodyPath $PostgreSqlBin) 'psql.exe';if(-not(Test-Path -LiteralPath $psql -PathType Leaf)){throw 'AUTH_PSQL_MISSING'}
 $phase='CUSTODY';$credential='C:\MarketBrainData\Secrets\PaperReviewWriter\writer.dpapi';$null=Assert-PaperCustodyPath $credential
 Assert-PaperPrivateAcl ([IO.Path]::GetDirectoryName($credential))
 $lockPath=Assert-PaperCustodyPath (Join-Path ([IO.Path]::GetDirectoryName($credential)) 'credential.lock');$lock=[IO.File]::Open($lockPath,'Open','ReadWrite','None')
 $entropy=Get-PaperCredentialEntropy $saved;$payload=Read-PaperCredential $credential $entropy;$verifier=New-PaperCredentialVerifier $payload
 $secretBytes=[Text.Encoding]::ASCII.GetBytes(([BitConverter]::ToString($payload,0,32)).Replace('-','').ToLowerInvariant())
 $phase='CONFIRMATION'
 if((Read-Host 'Confirm database name') -cne 'marketbrain'){throw 'AUTH_TARGET_NOT_CONFIRMED'}
 if($Mode -ceq 'Test' -and (Read-Host 'Keep other writer work stopped. Type TEST_TEMPORARY_LOGIN to allow a 120-second writer-password lease') -cne 'TEST_TEMPORARY_LOGIN'){throw 'AUTH_TEST_NOT_CONFIRMED'}
 if($Mode -ceq 'Recover' -and (Read-Host 'Type RESTORE_NOLOGIN to close only the saved writer lease') -cne 'RESTORE_NOLOGIN'){throw 'AUTH_RECOVERY_NOT_CONFIRMED'}
 $admin=Read-Host 'PostgreSQL administrator username (not Windows login)';if($admin -cnotmatch '^[A-Za-z_][A-Za-z0-9_]{0,62}$'){throw 'AUTH_ADMIN_INVALID'}
 $secure=Read-Host 'PostgreSQL administrator password (local only)' -AsSecureString;$password=[Net.NetworkCredential]::new('',$secure).Password;if(-not $password){throw 'AUTH_ADMIN_PASSWORD_REQUIRED'}
 if($Mode -ceq 'Recover'){
  $phase='RECOVERY';Stage 30 'Recovery only: commit NOLOGIN, close remaining writer sessions, verify the unchanged grants.'
  $report.leaseAttempted=$true;Save;Restore;$null=Database 'Verify';$report.status='WRITER_NOLOGIN_RECOVERED_RETEST_PENDING'
 } else {
  $phase='PREPARE';Stage 15 'Compile diagnostics and verify the deployed application before any LOGIN change.'
  $docker=(Get-Command docker.exe -CommandType Application -ErrorAction Stop|Select-Object -First 1).Source
  $javac=(Get-Command javac -CommandType Application -ErrorAction Stop|Select-Object -First 1).Source
  [void][IO.Directory]::CreateDirectory($fixture)
  $null=Native @('--release','21','-d',$fixture,(Join-Path $repo 'marketbrain-service/src/main/java/in/marketbrain/paper/PaperWriterAuthenticationProbe.java'),(Join-Path $repo 'marketbrain-service/src/main/java/in/marketbrain/paper/PaperApplicationRouteProbe.java')) 60 'COMPILE' $javac
  $container=Native @('ps','--filter','label=com.docker.compose.service=marketbrain-service','--format','{{.ID}}') 15 'LOCATE_APPLICATION'
  if($container -cnotmatch '^[a-f0-9]{12,64}$'){throw 'AUTH_CONTAINER_AMBIGUOUS'};$report.containerId=$container
  $null=Native @('exec',$container,'mkdir','-m','700',$containerPath) 15 'CREATE_DIAGNOSTIC_DIRECTORY';$created=$true
  $copied=$true;$null=Native @('cp',($fixture+'\.'),($container+':'+$containerPath)) 15 'COPY_DIAGNOSTIC'
  $null=Database 'Verify';$before=Database 'Readback';$report.serverStartEpoch=$before.serverStartEpoch
  Stage 35 'Prove that the staged password cannot log in while NOLOGIN is set.';Probe 'Disabled'
  $phase='WINDOW';Stage 50 'Temporary LOGIN, correct-secret/permission checks, wrong-secret and other-database rejection, then immediate revocation.'
  Invoke-PaperAuthenticationWindow -Checkpoint {$report.leaseAttempted=$true;$report.writerLoginEnabled=$null;Save} -Lease {$lease=Database 'Lease';$report.leaseSecondsRemainingAtReadback=$lease.leaseSecondsRemaining;Save;if($lease.serverStartEpoch -cne $report.serverStartEpoch){throw 'AUTH_SERVER_RESTARTED'}} -Probe {Probe 'Active'} -Revoke {$null=Database 'Revoke'} -Drain {$null=Database 'Drain'} -Readback {$null=Database 'Readback';$report.revocationVerified=$true;Save}
  $phase='FINAL_VERIFY';Stage 80 'Verify NOLOGIN, zero writer sessions, unchanged grants and continued application access.'
  $null=Database 'Verify';Probe 'Disabled'
  $routeText=Native @('exec',$container,'java','-Xmx64m','-cp',$containerPath,'in.marketbrain.paper.PaperApplicationRouteProbe','marketbrain','5432',$id) 55 'EXISTING_APPLICATION_ROUTE'
  $route=$routeText|ConvertFrom-Json
  $identity=[pscustomobject]@{database='marketbrain';databaseOid=$saved.plan.plan.databaseOid;serverPort=5432;serverStartEpoch=$report.serverStartEpoch}
  Assert-PaperHbaRoute $route $identity $id
  $report.applicationRoute=$route|Select-Object version,status,database,databaseOid,applicationUser,sessionUser,clientAddress,serverAddress,serverPort,serverStartEpoch,applicationName,readOnly,databaseWritesPerformed,writerLoginAttempted,actionExecutionEnabled
  $report.status='WRITER_AUTHENTICATION_PASSED_LOGIN_DISABLED'
 }
} catch {
 $report.status='STOPPED_REVIEW_REQUIRED';$report.failureCode=$phase+'_FAILED'
 if($_.Exception.Message -cmatch '^(AUTH|CREDENTIAL|CUSTODY)_[A-Z_]+$'){$report.failureCode=$_.Exception.Message}
} finally {
 # An uncertain lease or restoration must be retried as recovery, not as another activation.
 if($report.leaseAttempted -and -not $report.revocationVerified -and $password -and $verifier){
  try{Restore}catch{$report.recoveryFailureCode='AUTH_RESTORE_NOT_VERIFIED';$report.status='RECOVERY_REQUIRED_DO_NOT_RETEST'}
 }
 try {
  if($created -and $container -cmatch '^[a-f0-9]{12,64}$' -and $containerPath -ceq ('/tmp/mb-writer-auth-'+$id)){
   if($copied){foreach($name in @('PaperWriterAuthenticationProbe','PaperApplicationRouteProbe')){$null=Native @('exec',$container,'rm','-f','--',($containerPath+'/in/marketbrain/paper/'+$name+'.class')) 15 'REMOVE_DIAGNOSTIC_CLASS'}
    $null=Native @('exec',$container,'rmdir',($containerPath+'/in/marketbrain/paper'),($containerPath+'/in/marketbrain'),($containerPath+'/in')) 15 'REMOVE_DIAGNOSTIC_PACKAGES'}
   $null=Native @('exec',$container,'rmdir',$containerPath) 15 'REMOVE_DIAGNOSTIC_DIRECTORY'
  }
  if(Test-Path -LiteralPath $fixture){
   $null=Assert-PaperCustodyPath $fixture
   foreach($name in @('PaperWriterAuthenticationProbe','PaperApplicationRouteProbe')){$class=Join-Path $fixture ('in\marketbrain\paper\'+$name+'.class');if(Test-Path -LiteralPath $class){$null=Assert-PaperCustodyPath $class;Remove-Item -LiteralPath $class}}
   foreach($suffix in @('in\marketbrain\paper','in\marketbrain','in')){$dir=Join-Path $fixture $suffix;if(Test-Path -LiteralPath $dir){$null=Assert-PaperCustodyPath $dir;[IO.Directory]::Delete($dir,$false)}}
   [IO.Directory]::Delete($fixture,$false)
  };$report.cleanupComplete=$true
 }catch{$report.cleanupFailureCode='AUTH_DIAGNOSTIC_CLEANUP_REQUIRED';if($report.status -cne 'RECOVERY_REQUIRED_DO_NOT_RETEST'){$report.status='STOPPED_REVIEW_REQUIRED'}}
 if($lock){$lock.Dispose()};foreach($bytes in @($payload,$secretBytes,$entropy)){if($null -ne $bytes){[Array]::Clear($bytes,0,$bytes.Length)}}
 $password=$null;$verifier=$null;if($secure){$secure.Dispose()};Save
 Write-Progress -Activity 'Bounded writer authentication' -Completed
 Write-Host ('[100%] '+$report.status+'; elapsed='+[math]::Round($report.elapsedSeconds,2)+'s');Write-Host "Share this ONE file: $path"
 if($report.leaseAttempted -and -not $report.revocationVerified){Write-Warning 'Recovery required. Password expiry does not close existing sessions. Use -Mode Recover with this report; do not repeat Test.'}
}
if($report.status -cnotin @('WRITER_AUTHENTICATION_PASSED_LOGIN_DISABLED','WRITER_NOLOGIN_RECOVERED_RETEST_PENDING')){throw ('Authentication stopped: '+$report.failureCode+' '+$report.recoveryFailureCode+' '+$report.cleanupFailureCode)}
