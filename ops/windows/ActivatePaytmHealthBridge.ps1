#Requires -Version 7.0
[CmdletBinding()]param([string]$EvidencePath='C:\MarketBrainData\Review\paytm-health-deployment-preflight-deeca536524746189bda5a0823e43daa.json',[string]$OutputDirectory='C:\MarketBrainData\Review',[string]$ClockUpgradeReport='')
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'PaytmApplicationRoute.ps1')
. (Join-Path $PSScriptRoot 'PaytmHealthDeploymentPreflight.ps1')
. (Join-Path $PSScriptRoot 'PaytmHealthPublisher.ps1')
. (Join-Path $PSScriptRoot 'PaytmHealthActivation.ps1')
$root=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..'));$run=[guid]::NewGuid().ToString('N');$timer=[Diagnostics.Stopwatch]::StartNew()
$route=@{Root=$root};$application=@{Docker=$null;Id=$null;Token=$null};$saved=@{};$jar=$null;$before=$null;$compose=$null;$healthToken=$null;$oldHealth='';$account=$null;$project=$null
$report=[ordered]@{version=1;runId=$run;status='REVIEW_REQUIRED';failure=$null;rollbackFailure=$null;cleanupFailure=$null;elapsedSeconds=0;applicationCommands=[Collections.Generic.List[object]]::new();applicationDiscovery=$null;sourceHashes=@{};rollbackImageId=$null;newImageId=$null;deploymentAttempted=$false;rollbackAttempted=$false;rollbackVerified=$false;boundaryVerified=$false;restartVerified=$false;accountPreserved=$false;writerLocked=$false;finalRouteLocked=$false;healthyEvidencePublished=$false;diagnosticTokenConfigured=$false;unattendedPublisherInstalled=$false;ordersEnabled=$false}
$null=New-Item -ItemType Directory $OutputDirectory -Force;$path=Join-Path $OutputDirectory ('paytm-health-activation-'+$run+'.json')
function Save-Report {$report.elapsedSeconds=$timer.Elapsed.TotalSeconds;[IO.File]::WriteAllText($path,($report|ConvertTo-Json -Depth 12),[Text.UTF8Encoding]::new($false))}
function Set-ActivationEnvironment([string]$Image,[string]$Token){
 [Environment]::SetEnvironmentVariable('MARKETBRAIN_PAPER_REVIEW_IMAGE',$Image,'Process')
 [Environment]::SetEnvironmentVariable('MARKETBRAIN_PAYTM_HEALTH_TOKEN',$Token,'Process')
 $plan=ConvertFrom-PaytmPrivateJson (Invoke-PaytmPrivateDocker ($compose+@('config','--format','json')) 'PRIVATE_COMPOSE_COMPARE')
 Assert-PaytmHealthCompose $plan $before $Image $Token
}
try{
 Save-Report
 if($ClockUpgradeReport){
  $EvidencePath=$ClockUpgradeReport
  if((Get-FileHash -LiteralPath $EvidencePath).Hash -cne '2556897BC07D9C3258EA627A1580B8FCF550C8B5F96BA79E0E63BCE5A5930B9E'){throw 'HEALTH_ACTIVATION_CLOCK_EVIDENCE_MISMATCH'}
  $report['clockUpgrade']=$true
 }elseif((Get-FileHash -LiteralPath $EvidencePath).Hash -cne 'DFF50F8D473456A69A8D650074EBA5B46AE4B935E5C281982582360B2CF26F71'){throw 'HEALTH_ACTIVATION_EVIDENCE_MISMATCH'}
 $accepted=Get-Content -LiteralPath $EvidencePath -Raw|ConvertFrom-Json
 $dirty=& git -C $root status --porcelain
 if($LASTEXITCODE -ne 0 -or $dirty){throw 'HEALTH_ACTIVATION_CLEAN_CHECKOUT_REQUIRED'}
 $revision=& git -C $root rev-parse HEAD
 if($LASTEXITCODE -ne 0){throw 'HEALTH_ACTIVATION_REVISION'}
 foreach($name in @('ActivatePaytmHealthBridge.ps1','PaytmHealthActivation.ps1','PaytmHealthDeploymentPreflight.ps1','PaytmHealthPublisher.ps1','PaytmApplicationRoute.ps1','PaperRuntimeDeployment.ps1','PaperRuntimeReview.ps1','PaperAccountReadReview.ps1')){$report.sourceHashes[$name]=(Get-FileHash -LiteralPath (Join-Path $PSScriptRoot $name)).Hash}
 $report.sourceHashes['revision']=$revision
 Write-Host '[5%] Guarded service activation. Alerts briefly pause during recreation/restart. No live trades.'
 if($env:DOCKER_HOST -or $env:DOCKER_CONTEXT){throw 'HEALTH_ACTIVATION_DOCKER_OVERRIDE'}
 $application.Docker=(Get-Command docker.exe -CommandType Application -ErrorAction Stop|Select-Object -First 1).Source
 $context=Invoke-PaytmPrivateDocker @('context','show') 'CONTEXT'
 if((Invoke-PaytmPrivateDocker @('context','inspect',$context,'--format','{{.Endpoints.docker.Host}}') 'ENDPOINT') -notmatch '^npipe://'){throw 'HEALTH_ACTIVATION_LOCAL_DOCKER_REQUIRED'}
 $before=Get-PaytmApplicationContainer;$application.Id=$before.Id
 if(-not $ClockUpgradeReport -and ($before.Id -cne $accepted.containerId -or $before.Image -cne $accepted.rollbackImageId)){throw 'HEALTH_ACTIVATION_BASELINE_CHANGED'}
 $envMap=ConvertTo-PaperRuntimeEnvironment $before.Config.Env
 if($envMap.MARKETBRAIN_PAYTM_ENABLED -cne 'false' -or $envMap.MARKETBRAIN_PAYTM_ACCESS_TOKEN -or (-not $ClockUpgradeReport -and $envMap['MARKETBRAIN_PAYTM_HEALTH_TOKEN'])){throw 'HEALTH_ACTIVATION_PAYTM_CONFIGURATION_CHANGED'}
 foreach($key in @('JAVA_TOOL_OPTIONS','JDK_JAVA_OPTIONS','_JAVA_OPTIONS')){if($envMap[$key]){throw 'HEALTH_ACTIVATION_JAVA_OVERRIDE'}}
 $application.Token=$envMap.MARKETBRAIN_PAPER_READ_TOKEN
 if($ClockUpgradeReport){
  $oldHealth=$envMap['MARKETBRAIN_PAYTM_HEALTH_TOKEN']
  if($oldHealth -cnotmatch '^[A-Za-z0-9_-]{32,128}$' -or $oldHealth -ceq $application.Token){throw 'HEALTH_ACTIVATION_EXISTING_TOKEN_REQUIRED'}
  $state=Invoke-PaytmHealthActivationRoute 'status'
  if($state.bootId -cne $accepted.worker.applicationBootId){throw 'HEALTH_ACTIVATION_BASELINE_BOOT_CHANGED'}
 }
 Assert-PaytmWriterLocked;$account=Read-PaytmHealthPreflightAccount $application.Token
 $report.rollbackImageId=Invoke-PaytmPrivateDocker @('image','inspect','--format','{{.Id}}',$before.Image) 'ROLLBACK_IMAGE'
 if($report.rollbackImageId -cne $before.Image){throw 'HEALTH_ACTIVATION_ROLLBACK_IMAGE_MISSING'}
 $jar=[IO.Path]::GetTempFileName();$null=Invoke-PaytmPrivateDocker @('cp',($before.Id+':/app/app.jar'),$jar) 'MIGRATION_BASELINE' 60
 if(-not (Compare-PaytmPackagedMigrations $jar (Join-Path $root 'marketbrain-service/src/main/resources/db/migration')).matched){throw 'HEALTH_ACTIVATION_MIGRATIONS_DIFFER'}
 $healthToken=if($ClockUpgradeReport){$oldHealth}else{[Convert]::ToHexString([Security.Cryptography.RandomNumberGenerator]::GetBytes(32))}
 if($healthToken -ceq $application.Token){throw 'HEALTH_ACTIVATION_TOKEN_COLLISION'}
 $project=$before.Config.Labels.'com.docker.compose.project';$image='marketbrain-health-'+$run+':review'
 $overrides=@{};foreach($key in $envMap.Keys){if($key -clike 'MARKETBRAIN_*'){$overrides[$key]=$envMap[$key]}}
 $overrides.MARKETBRAIN_PAPER_APPROVAL_KEY_HOST_FILE=ConvertTo-PaperHostMount (@($before.Mounts|Where-Object Destination -CEQ '/run/secrets/paper-approval.key')[0].Source)
 $overrides.MARKETBRAIN_REVIEW_HOST_DIRECTORY=ConvertTo-PaperHostMount (@($before.Mounts|Where-Object Destination -CEQ '/marketbrain-review')[0].Source)
 $overrides.MARKETBRAIN_PAPER_REVIEW_IMAGE=$image;$overrides.MARKETBRAIN_PAYTM_HEALTH_TOKEN=$healthToken
 foreach($key in $overrides.Keys){$saved[$key]=[Environment]::GetEnvironmentVariable($key,'Process');[Environment]::SetEnvironmentVariable($key,$overrides[$key],'Process')}
 $compose=@('compose','--project-name',$project,'--env-file','.env','-f','compose.yaml','-f','compose.paper-storage.yaml','-f','compose.paper-review-memory.yaml')
 Set-ActivationEnvironment $image $healthToken
 Write-Host '[25%] Build the new service image; current service continues running.'
 Write-Progress -Activity 'Health activation' -PercentComplete 25 -Status 'Build image'
 $null=Invoke-PaytmPrivateDocker @('build','-f','marketbrain-service/Dockerfile','-t',$image,'marketbrain-service') 'BUILD' 1800
 $report.newImageId=Invoke-PaytmPrivateDocker @('image','inspect','--format','{{.Id}}',$image) 'NEW_IMAGE'
 if($report.newImageId -cnotmatch '^sha256:[a-f0-9]{64}$'){throw 'HEALTH_ACTIVATION_IMAGE_INVALID'}
 $currentRevision=& git -C $root rev-parse HEAD;$dirty=& git -C $root status --porcelain
 if($LASTEXITCODE -ne 0 -or $currentRevision -cne $revision -or $dirty){throw 'HEALTH_ACTIVATION_SOURCE_CHANGED'}
 $current=Get-PaytmApplicationContainer
 if($current.Id -cne $before.Id -or $current.Image -cne $before.Image -or $current.State.StartedAt -cne $before.State.StartedAt -or (Read-PaytmHealthPreflightAccount $application.Token) -cne $account){throw 'HEALTH_ACTIVATION_PRE_DEPLOY_DRIFT'}
 Assert-PaytmWriterLocked
 Write-Host '[60%] Recreate only marketbrain-service; retain previous image for rollback.'
 Write-Progress -Activity 'Health activation' -PercentComplete 60 -Status 'Service recreation'
 $report.deploymentAttempted=$true;Save-Report
 $null=Invoke-PaytmPrivateDocker ($compose+@('up','-d','--no-deps','--no-build','--pull','never','--force-recreate','marketbrain-service')) 'DEPLOY' 180
 Wait-PaytmApplicationHealth
 $after=Get-PaytmApplicationContainer;Assert-PaytmHealthPreserved $before $after $healthToken
 if($after.Image -cne $report.newImageId -or $after.Id -ceq $before.Id){throw 'HEALTH_ACTIVATION_NEW_IMAGE_REQUIRED'}
 $application.Id=$after.Id;$report.diagnosticTokenConfigured=$true;Assert-PaytmWriterLocked
 Write-Host '[75%] Actual HTTP authentication, unhealthy-input, replay and expiry checks; no healthy evidence submitted.'
 Write-Progress -Activity 'Health activation' -PercentComplete 75 -Status 'Application boundary'
 $boot=Test-PaytmHealthActivationBoundary $healthToken;$report.boundaryVerified=$true;Save-Report
 if($ClockUpgradeReport){$report['clockBeforeRestart']=Test-PaytmHealthClockBoundary $healthToken $boot}
 $stale=Invoke-PaytmHealthHttp 'challenge' $healthToken $null
 Write-Host '[90%] Restart once; verify new boot, locked route and rejection of previous-boot evidence.'
 $null=Invoke-PaytmPrivateDocker @('restart','--time','30',$application.Id) 'RESTART' 90
 Wait-PaytmApplicationHealth
 $final=Get-PaytmApplicationContainer;Assert-PaytmHealthPreserved $before $final $healthToken
 if($final.Id -cne $after.Id -or $final.Image -cne $after.Image -or $final.State.StartedAt -ceq $after.State.StartedAt){throw 'HEALTH_ACTIVATION_RESTART_IDENTITY'}
 $state=Invoke-PaytmHealthActivationRoute 'status'
 if($state.bootId -ceq $boot){throw 'HEALTH_ACTIVATION_RESTART_BOOT'}
 if($ClockUpgradeReport){$report['clockAfterRestart']=Test-PaytmHealthClockBoundary $healthToken $state.bootId}
 $body=@{challenge=$stale.challenge;bootId=$stale.bootId;synchronizedClock=$false;transportHealthy=$false;lowerOffsetSeconds=0;upperOffsetSeconds=0}
 Assert-PaytmHealthActivationReceipt (Invoke-PaytmHealthHttp 'submit' $healthToken $body) 'REJECTED_AND_LOCKED' $state.bootId
 $report.restartVerified=$true
 Assert-PaytmWriterLocked;$report.writerLocked=$true
 if((Read-PaytmHealthPreflightAccount $application.Token) -cne $account){throw 'HEALTH_ACTIVATION_ACCOUNT_CHANGED'}
 $report.accountPreserved=$true;$null=Invoke-PaytmHealthActivationRoute 'lock';$report.finalRouteLocked=$true
 $report.status='HEALTH_BRIDGE_DEPLOYED_LOCKED_LIVE_PUBLICATION_PENDING'
 if($ClockUpgradeReport){$report.status='HEALTH_CLOCK_DEPLOYED_LOCKED_COLLECTOR_PENDING';$report['existingHealthTokenPreserved']=$true}
}catch{
 $report.failure=if($_.Exception.Message -cmatch '^[A-Z][A-Z0-9_]+$'){$_.Exception.Message}else{'HEALTH_ACTIVATION_FAILED'}
 if($report.deploymentAttempted){
  $report.rollbackAttempted=$true;Save-Report
  try{
   Write-Host 'Activation failed. Attempting rollback to the recorded image; no image or volume pruning.'
   Assert-PaytmHealthRollbackOwnership $project $report.rollbackImageId $report.newImageId
   Set-ActivationEnvironment $report.rollbackImageId $oldHealth
   $null=Invoke-PaytmPrivateDocker ($compose+@('up','-d','--no-deps','--no-build','--pull','never','--force-recreate','marketbrain-service')) 'ROLLBACK' 180
   Wait-PaytmApplicationHealth
   $restored=Get-PaytmApplicationContainer;Assert-PaytmHealthPreserved $before $restored $oldHealth
   if($restored.Image -cne $report.rollbackImageId){throw 'HEALTH_ACTIVATION_ROLLBACK_IMAGE'}
   $application.Id=$restored.Id;Assert-PaytmWriterLocked
   if((Read-PaytmHealthPreflightAccount $application.Token) -cne $account){throw 'HEALTH_ACTIVATION_ROLLBACK_ACCOUNT'}
   $report.diagnosticTokenConfigured=[bool]$oldHealth;$report.rollbackVerified=$true;$report.status='ACTIVATION_FAILED_ROLLBACK_VERIFIED'
  }catch{$report.rollbackFailure='HEALTH_ACTIVATION_ROLLBACK_FAILED_REVIEW_REQUIRED';$report.status='REVIEW_REQUIRED'}
 }
}finally{
 foreach($key in $saved.Keys){[Environment]::SetEnvironmentVariable($key,$saved[$key],'Process')}
 $healthToken=$null;$oldHealth=$null;$application.Token=$null;$envMap=$null;$overrides=$null;$before=$null;$after=$null;$final=$null;$restored=$null;$current=$null
 try{if($jar){[IO.File]::Delete($jar)}}catch{$report.cleanupFailure='HEALTH_ACTIVATION_TEMP_JAR_CLEANUP';$report.status='REVIEW_REQUIRED'}
 Save-Report;Write-Progress -Activity 'Health activation' -Completed
 Write-Host "[100%] $($report.status)";Write-Host "Share this ONE file: $path"
}
if($report.failure -or $report.cleanupFailure){throw 'Share the report; do not rerun activation or manually prune images.'}
