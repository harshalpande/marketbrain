#Requires -Version 7.2
[CmdletBinding()]param([string]$OutputDirectory='C:\MarketBrainData\Review')
$ErrorActionPreference='Stop'
$root=(Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
Set-Location $root
$run=[guid]::NewGuid().ToString('N');$timer=[Diagnostics.Stopwatch]::StartNew();$saved=@{}
$null=New-Item -ItemType Directory -Path $OutputDirectory -Force
$path=Join-Path $OutputDirectory "paytm-supervised-deployment-$run.json"
$report=[ordered]@{version=1;runId=$run;status='REVIEW_REQUIRED';stage='PREPARATION';failure=$null;cleanup=@();elapsedSeconds=0;clockSource='VPS_ANCHORED_MONOTONIC';vpsAccuracyAssumed=$true;windowsClockGate=$false;readAccessVerified=$false;quotesTested=$false;ordersEnabled=$false;deploymentAttempted=$false;commands=@()}
function Save-DeploymentReport {$report.elapsedSeconds=$timer.Elapsed.TotalSeconds;[IO.File]::WriteAllText($path,($report|ConvertTo-Json -Depth 5))}
function Invoke-SupervisedDocker([string[]]$Arguments,[string]$Stage,[int]$Limit=30) {
 $report.stage=$Stage;Save-DeploymentReport
 # inspect/config can contain secrets: never print or persist their output.
 $v=Invoke-PaperRuntimeProcess $docker $Arguments $root $Limit
 $report.commands+=@{stage=$Stage;exitCode=$v.exitCode;elapsedSeconds=$v.elapsedSeconds}
 if($v.exitCode -ne 0){throw "SUPERVISED_DEPLOY_NATIVE_$Stage"}
 return $v.stdout.Trim()
}
try{
 Save-DeploymentReport
 . "$PSScriptRoot/PaytmSupervisedDeployment.ps1"
 $docker=(Get-Command docker.exe -CommandType Application|Select-Object -First 1).Source
 if(-not $docker){throw 'SUPERVISED_DEPLOY_DOCKER_MISSING'}
 if($env:DOCKER_HOST -or $env:DOCKER_CONTEXT){throw 'SUPERVISED_DEPLOY_LOCAL_DOCKER_REQUIRED'}
 $context=Invoke-SupervisedDocker @('context','show') 'CONTEXT'
 if((Invoke-SupervisedDocker @('context','inspect',$context,'--format','{{.Endpoints.docker.Host}}') 'ENDPOINT') -notmatch '^npipe://'){throw 'SUPERVISED_DEPLOY_LOCAL_DOCKER_REQUIRED'}
 Write-Host '[10%] Resolving deployment and preserving existing environment and protected mounts.'
 $ids=@((Invoke-SupervisedDocker @('ps','-aq','--filter','label=com.docker.compose.service=marketbrain-service') 'DISCOVERY') -split '\r?\n'|Where-Object {$_})
 if($ids.Count -ne 1){throw 'SUPERVISED_DEPLOY_CONTAINER_AMBIGUOUS'}
 $before=@((Invoke-SupervisedDocker @('inspect',$ids[0]) 'INSPECT')|ConvertFrom-Json)[0]
 $labels=$before.Config.Labels
 if((ConvertTo-PaperHostMount $labels.'com.docker.compose.project.working_dir') -cne (ConvertTo-PaperHostMount $root)){throw 'SUPERVISED_DEPLOY_WORKSPACE'}
 $files=@($labels.'com.docker.compose.project.config_files' -split ',')
 $override=Join-Path $root 'compose.paytm-supervised.yaml'
 if(@($files|Where-Object {(ConvertTo-PaperHostMount $_) -ceq (ConvertTo-PaperHostMount $override)}).Count -eq 0){$files+=$override}
 $composeArgs=@('compose','--project-name',[string]$labels.'com.docker.compose.project')
 foreach($file in $files){
  $full=[IO.Path]::GetFullPath($file)
  if(-not $full.StartsWith($root+[IO.Path]::DirectorySeparatorChar,[StringComparison]::OrdinalIgnoreCase) -or -not (Test-Path -LiteralPath $full -PathType Leaf)){throw 'SUPERVISED_DEPLOY_COMPOSE_FILE'}
  $composeArgs+=@('-f',$full)
 }
 $image="marketbrain-supervised-${run}:review"
 $values=Get-SupervisedDeploymentEnvironment $before $image
 if(-not (Test-Path -LiteralPath $values.MARKETBRAIN_PAPER_APPROVAL_KEY_HOST_FILE -PathType Leaf) -or -not (Test-Path -LiteralPath $values.MARKETBRAIN_REVIEW_HOST_DIRECTORY -PathType Container)){throw 'SUPERVISED_DEPLOY_EXISTING_MOUNT_MISSING'}
 Set-SupervisedProcessEnvironment $values $saved
 $plan=(Invoke-SupervisedDocker ($composeArgs+@('config','--format','json')) 'PLAN')|ConvertFrom-Json
 Assert-SupervisedComposePlan $plan $before $image
 Write-Host '[30%] Configuration verified. Building a separate image; existing service remains running.'
 $null=Invoke-SupervisedDocker @('build','-f','marketbrain-service/Dockerfile','-t',$image,'marketbrain-service') 'BUILD' 1800
 $imageId=Invoke-SupervisedDocker @('image','inspect','--format','{{.Id}}',$image) 'IMAGE'
 $current=@((Invoke-SupervisedDocker @('inspect',$before.Id) 'BASELINE')|ConvertFrom-Json)[0]
 if($current.Image -cne $before.Image -or $current.State.StartedAt -cne $before.State.StartedAt){throw 'SUPERVISED_DEPLOY_BASELINE_CHANGED'}
 Write-Host '[75%] Recreating only the application service with its existing mounts.'
 $report.deploymentAttempted=$true;Save-DeploymentReport
 $null=Invoke-SupervisedDocker ($composeArgs+@('up','-d','--no-deps','--no-build','--pull','never','marketbrain-service')) 'DEPLOY' 180
 $newId=Invoke-SupervisedDocker ($composeArgs+@('ps','-q','marketbrain-service')) 'NEW_CONTAINER'
 $after=@((Invoke-SupervisedDocker @('inspect',$newId) 'VERIFY')|ConvertFrom-Json)[0]
 if($after.Image -cne $imageId){throw 'SUPERVISED_DEPLOY_IMAGE_MISMATCH'}
 Assert-SupervisedDeploymentEnvironment $before (ConvertTo-PaperRuntimeEnvironment $after.Config.Env)
 $baseline=$before|ConvertTo-Json -Depth 50|ConvertFrom-Json
 $baseline.Config.Env=@($baseline.Config.Env|Where-Object {$_ -notmatch '^MARKETBRAIN_PAYTM_(SUPERVISED_ENABLED|AUTH_REHEARSAL_ENABLED)='})
 Assert-PaperRuntimePreserved $baseline $after
 $report.stage='HEALTH';Save-DeploymentReport
 $watch=[Diagnostics.Stopwatch]::StartNew();$ready=$false
 do{
  try{$r=Invoke-RestMethod 'http://127.0.0.1:8080/actuator/health' -NoProxy -TimeoutSec 5;if($r.status -eq 'UP'){$ready=$true;break}}catch{}
  Write-Progress -Activity 'Application startup' -PercentComplete 90 -Status "$([int]$watch.Elapsed.TotalSeconds)/180 seconds"
  Start-Sleep -Seconds 3
 }while($watch.Elapsed.TotalSeconds -lt 180)
 if(-not $ready){throw 'SUPERVISED_DEPLOY_HEALTH_TIMEOUT'}
 $report.status='SUPERVISED_DEPLOYMENT_PASSED_LOGIN_PENDING'
}catch{$report.failure=if($_.Exception.Message -cmatch '^[A-Z][A-Z0-9_]+$'){$_.Exception.Message}else{'SUPERVISED_DEPLOY_STEP_FAILED'};$report.failureLine=$_.InvocationInfo.ScriptLineNumber}
finally{
 if($saved.Count){Restore-SupervisedProcessEnvironment $saved}
 $report.cleanup+='PROCESS_ENVIRONMENT_RESTORED'
 Save-DeploymentReport;Write-Progress -Activity 'Application startup' -Completed
 Write-Host "[100%] $($report.status). Automatic collection report: $path"
}
if($report.failure){throw "Deployment stopped at $($report.stage): $($report.failure). Existing service replaced only if deploymentAttempted=true in the report."}
