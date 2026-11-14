#Requires -Version 7.0
[CmdletBinding()]param([string]$EvidencePath='C:\MarketBrainData\Review\paytm-timed-route-0b186b03d92f4f26b55bbc63406f1139.json',[string]$OutputDirectory='C:\MarketBrainData\Review')
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'PaytmApplicationRoute.ps1')
. (Join-Path $PSScriptRoot 'PaytmHealthDeploymentPreflight.ps1')
$root=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..'));$run=[guid]::NewGuid().ToString('N');$timer=[Diagnostics.Stopwatch]::StartNew()
$route=@{Root=$root};$application=@{Docker=$null;Id=$null;Token=$null};$saved=@{};$jar=$null
$report=[ordered]@{version=1;runId=$run;status='REVIEW_REQUIRED';failure=$null;cleanupFailure=$null;elapsedSeconds=0;applicationCommands=[Collections.Generic.List[object]]::new();applicationDiscovery=$null;sourceHashes=@{};rollbackImageId=$null;containerId=$null;migrations=$null;composeMatches=$false;accountPreserved=$false;writerLocked=$false;containerUnchanged=$false;temporaryJarRemoved=$false;applicationChanged=$false;credentialsProvisioned=$false;ordersEnabled=$false}
$null=New-Item -ItemType Directory $OutputDirectory -Force;$path=Join-Path $OutputDirectory ('paytm-health-deployment-preflight-'+$run+'.json')
function Save-Report {$report.elapsedSeconds=$timer.Elapsed.TotalSeconds;[IO.File]::WriteAllText($path,($report|ConvertTo-Json -Depth 12),[Text.UTF8Encoding]::new($false))}
try{
 Save-Report
 if((Get-FileHash -LiteralPath $EvidencePath).Hash -cne 'C24D4B26B4A85CAF760F0BB05E7E9DD8DC13B664888E4E7DB88DD61D579F8235'){throw 'HEALTH_PREFLIGHT_EVIDENCE_MISMATCH'}
 foreach($name in @('TestPaytmHealthDeploymentPreflight.ps1','PaytmHealthDeploymentPreflight.ps1','PaytmApplicationRoute.ps1','PaperRuntimeDeployment.ps1','PaperRuntimeReview.ps1','PaperAccountReadReview.ps1')){$report.sourceHashes[$name]=(Get-FileHash -LiteralPath (Join-Path $PSScriptRoot $name)).Hash}
 foreach($name in @('compose.yaml','compose.paper-storage.yaml','compose.paper-review-memory.yaml')){$report.sourceHashes[$name]=(Get-FileHash -LiteralPath (Join-Path $root $name)).Hash}
 Write-Host '[10%] Read-only running deployment and rollback-image checks. No rebuild/restart.'
 Write-Progress -Activity 'Health deployment preflight' -PercentComplete 10 -Status 'Existing deployment'
 if($env:DOCKER_HOST -or $env:DOCKER_CONTEXT){throw 'HEALTH_PREFLIGHT_DOCKER_OVERRIDE'}
 $application.Docker=(Get-Command docker.exe -CommandType Application -ErrorAction Stop|Select-Object -First 1).Source
 $context=Invoke-PaytmPrivateDocker @('context','show') 'CONTEXT'
 if((Invoke-PaytmPrivateDocker @('context','inspect',$context,'--format','{{.Endpoints.docker.Host}}') 'ENDPOINT') -notmatch '^npipe://'){throw 'HEALTH_PREFLIGHT_LOCAL_DOCKER_REQUIRED'}
 $before=Get-PaytmApplicationContainer;$application.Id=$before.Id;$report.containerId=$before.Id
 $envMap=ConvertTo-PaperRuntimeEnvironment $before.Config.Env
 if($envMap.MARKETBRAIN_PAYTM_ENABLED -cne 'false' -or $envMap.MARKETBRAIN_PAYTM_ACCESS_TOKEN -or $envMap['MARKETBRAIN_PAYTM_HEALTH_TOKEN']){throw 'HEALTH_PREFLIGHT_PAYTM_CONFIGURATION_CHANGED'}
 $application.Token=$envMap.MARKETBRAIN_PAPER_READ_TOKEN
 Assert-PaytmWriterLocked;$report.writerLocked=$true
 $account=Read-PaytmHealthPreflightAccount $application.Token
 $image=Invoke-PaytmPrivateDocker @('image','inspect','--format','{{.Id}}',$before.Image) 'ROLLBACK_IMAGE'
 if($image -cne $before.Image -or $image -cnotmatch '^sha256:[a-f0-9]{64}$'){throw 'HEALTH_PREFLIGHT_ROLLBACK_IMAGE_MISSING'}
 $report.rollbackImageId=$image;Save-Report
 Write-Host '[35%] Compare deployed migration resources with source; no SQL is executed.'
 Write-Progress -Activity 'Health deployment preflight' -PercentComplete 35 -Status 'Migration resources'
 $jar=[IO.Path]::GetTempFileName()
 $null=Invoke-PaytmPrivateDocker @('cp',($before.Id+':/app/app.jar'),$jar) 'READ_APPLICATION_JAR' 60
 $report.migrations=Compare-PaytmPackagedMigrations $jar (Join-Path $root 'marketbrain-service/src/main/resources/db/migration');Save-Report
 if(-not $report.migrations.matched){throw 'HEALTH_PREFLIGHT_MIGRATIONS_DIFFER'}
 Write-Host '[60%] Render existing Compose configuration privately and verify preservation.'
 Write-Progress -Activity 'Health deployment preflight' -PercentComplete 60 -Status 'Compose preservation'
 $overrides=@{};foreach($key in $envMap.Keys){if($key -clike 'MARKETBRAIN_*'){$overrides[$key]=$envMap[$key]}}
 $overrides.MARKETBRAIN_PAPER_APPROVAL_KEY_HOST_FILE=ConvertTo-PaperHostMount (@($before.Mounts|Where-Object Destination -CEQ '/run/secrets/paper-approval.key')[0].Source)
 $overrides.MARKETBRAIN_REVIEW_HOST_DIRECTORY=ConvertTo-PaperHostMount (@($before.Mounts|Where-Object Destination -CEQ '/marketbrain-review')[0].Source)
 $overrides.MARKETBRAIN_PAPER_REVIEW_IMAGE=$image
 foreach($key in $overrides.Keys){$saved[$key]=[Environment]::GetEnvironmentVariable($key,'Process');[Environment]::SetEnvironmentVariable($key,$overrides[$key],'Process')}
 $compose=@('compose','--project-name',$before.Config.Labels.'com.docker.compose.project','--env-file','.env','-f','compose.yaml','-f','compose.paper-storage.yaml','-f','compose.paper-review-memory.yaml')
 $plan=ConvertFrom-PaytmPrivateJson (Invoke-PaytmPrivateDocker ($compose+@('config','--format','json')) 'PRIVATE_COMPOSE_COMPARE')
 Assert-PaperRuntimeCompose $plan $before $envMap.MARKETBRAIN_PAPER_REVIEW_DATABASE_OID $image
 $report.composeMatches=$true;Save-Report
 Write-Host '[85%] Verify account, writer lock and container identity remain unchanged.'
 Write-Progress -Activity 'Health deployment preflight' -PercentComplete 85 -Status 'Final preservation checks'
 $after=Get-PaytmApplicationContainer;Assert-PaperRuntimePreserved $before $after
 if($after.Id -cne $before.Id -or $after.State.StartedAt -cne $before.State.StartedAt -or $after.Image -cne $before.Image){throw 'HEALTH_PREFLIGHT_CONTAINER_CHANGED'}
 $report.containerUnchanged=$true
 Assert-PaytmWriterLocked
 if((Read-PaytmHealthPreflightAccount $application.Token) -cne $account){throw 'HEALTH_PREFLIGHT_ACCOUNT_CHANGED'}
 $report.accountPreserved=$true;$report.status='HEALTH_DEPLOYMENT_PREFLIGHT_PASSED_ACTIVATION_PENDING'
}catch{$report.failure=if($_.Exception.Message -cmatch '^[A-Z][A-Z0-9_]+$'){$_.Exception.Message}else{'HEALTH_PREFLIGHT_FAILED_REVIEW_REQUIRED'}}
finally{
 foreach($key in $saved.Keys){[Environment]::SetEnvironmentVariable($key,$saved[$key],'Process')}
 $application.Token=$null;$envMap=$null;$overrides=$null;$plan=$null;$before=$null;$after=$null
 try{if($jar){[IO.File]::Delete($jar)};$report.temporaryJarRemoved=$true}catch{$report.cleanupFailure='HEALTH_PREFLIGHT_TEMPORARY_JAR_CLEANUP_FAILED'}
 if($report.failure -or $report.cleanupFailure){$report.status='REVIEW_REQUIRED'}
 Save-Report;Write-Progress -Activity 'Health deployment preflight' -Completed
 Write-Host "[100%] $($report.status)";Write-Host "Share this ONE file: $path"
}
if($report.status -eq 'REVIEW_REQUIRED'){throw 'Share the report; do not rebuild or change credentials.'}
