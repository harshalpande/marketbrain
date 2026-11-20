#Requires -Version 7.2
param([switch]$WithCompose)
$ErrorActionPreference='Stop'
. "$PSScriptRoot/PaytmSupervisedDeployment.ps1"
$count=0
function Check([bool]$Value,[string]$Name){if(-not $Value){throw "FAILED: $Name"};$script:count++}
function Reject([scriptblock]$Action,[string]$Expected){try{& $Action}catch{Check ($_.Exception.Message -ceq $Expected) $Expected;return};throw "Expected rejection: $Expected"}
$before=[pscustomobject]@{
 Config=[pscustomobject]@{Env=@('MARKETBRAIN_EXECUTION_MODE=PAPER','MARKETBRAIN_DB_PASSWORD=fixture-only=with-equals','MARKETBRAIN_PAPER_READ_TOKEN=fixture-only','MARKETBRAIN_PAPER_REVIEW_DATABASE_OID=123');Labels=[pscustomobject]@{'com.docker.compose.project'='marketbrain'}}
 Mounts=@([pscustomobject]@{Destination='/run/secrets/paper-approval.key';Type='bind';Source='/run/desktop/mnt/host/c/ProgramData/MarketBrain/key';RW=$false},[pscustomobject]@{Destination='/marketbrain-review';Type='bind';Source='/host_mnt/c/MarketBrainData/Review';RW=$true})
 HostConfig=[pscustomobject]@{Tmpfs=[pscustomobject]@{'/run/marketbrain-writer'='rw,noexec,nosuid,nodev,size=65536,mode=0700,uid=0,gid=0'}}
}
$v=Get-SupervisedDeploymentEnvironment $before 'fixture:review'
Check ($v.MARKETBRAIN_PAPER_APPROVAL_KEY_HOST_FILE -ceq 'c:/programdata/marketbrain/key') 'Existing secret mount recovered'
Check ($v.MARKETBRAIN_REVIEW_HOST_DIRECTORY -ceq 'c:/marketbraindata/review') 'Existing review mount recovered'
Check ($v.MARKETBRAIN_PAPER_REVIEW_IMAGE -ceq 'fixture:review') 'Image variable resolved'
Check ($v.MARKETBRAIN_DB_PASSWORD -ceq 'fixture-only=with-equals') 'Environment value preserved'
Check ($v.MARKETBRAIN_PAPER_REVIEW_DATABASE_OID -ceq '123') 'Database identity retained'
$desired=ConvertTo-PaperRuntimeEnvironment $before.Config.Env
$desired.MARKETBRAIN_PAYTM_SUPERVISED_ENABLED='true';$desired.MARKETBRAIN_PAYTM_AUTH_REHEARSAL_ENABLED='false'
$plan=[pscustomobject]@{name='marketbrain';services=[pscustomobject]@{'marketbrain-service'=[pscustomobject]@{
 image='fixture:review';environment=[pscustomobject]$desired
 ports=@([pscustomobject]@{host_ip='127.0.0.1';published='8080';target=8080})
 volumes=@([pscustomobject]@{type='bind';source=$v.MARKETBRAIN_PAPER_APPROVAL_KEY_HOST_FILE;target='/run/secrets/paper-approval.key';read_only=$true},[pscustomobject]@{type='bind';source=$v.MARKETBRAIN_REVIEW_HOST_DIRECTORY;target='/marketbrain-review';read_only=$false})
 tmpfs=@('/run/marketbrain-writer:rw,noexec,nosuid,nodev,size=65536,mode=0700,uid=0,gid=0')
}}}
Assert-SupervisedComposePlan $plan $before 'fixture:review';Check $true 'Resolved plan accepted'
$desired.MARKETBRAIN_DB_PASSWORD='changed'
Reject {Assert-SupervisedDeploymentEnvironment $before $desired} 'SUPERVISED_DEPLOY_ENVIRONMENT_DRIFT'
$plan.services.'marketbrain-service'.volumes[0].read_only=$false
Reject {Assert-SupervisedComposePlan $plan $before 'fixture:review'} 'SUPERVISED_DEPLOY_MOUNT_DRIFT'
$plan.services.'marketbrain-service'.volumes[0].read_only=$true
$plan.services.'marketbrain-service'.ports[0].host_ip='0.0.0.0'
Reject {Assert-SupervisedComposePlan $plan $before 'fixture:review'} 'SUPERVISED_DEPLOY_PORT'
$before.Mounts[0].RW=$true
Reject {Get-SupervisedDeploymentEnvironment $before 'fixture:review'} 'SUPERVISED_DEPLOY_MOUNT_INVALID'
$saved=@{};$key='MARKETBRAIN_TEST_SUPERVISED_FIXTURE';$prior=[Environment]::GetEnvironmentVariable($key,'Process')
try{
 Set-SupervisedProcessEnvironment @{$key='fixture-only'} $saved
 Check ([Environment]::GetEnvironmentVariable($key,'Process') -ceq 'fixture-only') 'Process override set'
 Restore-SupervisedProcessEnvironment $saved
 Check ([Environment]::GetEnvironmentVariable($key,'Process') -ceq $prior) 'Process override restored'
}finally{[Environment]::SetEnvironmentVariable($key,$prior,'Process')}
if($WithCompose){
 $repo=(Resolve-Path "$PSScriptRoot/../..").Path
 $docker=(Get-Command docker.exe -CommandType Application|Select-Object -First 1).Source
 $empty=[IO.Path]::GetTempFileName();$savedCompose=@{}
 try{
  Set-SupervisedProcessEnvironment @{MARKETBRAIN_DB_PASSWORD='fixture-only';MARKETBRAIN_PAPER_APPROVAL_KEY_HOST_FILE='C:/fixture/key';MARKETBRAIN_REVIEW_HOST_DIRECTORY='C:/fixture/review';MARKETBRAIN_PAPER_REVIEW_IMAGE='fixture:old';MARKETBRAIN_PAPER_REVIEW_DATABASE_OID='123';MARKETBRAIN_PAPER_READ_TOKEN=('a'*40)} $savedCompose
  $compose=@('compose','--env-file',$empty,'--project-name','marketbrain','-f','compose.yaml','-f','compose.paper-storage.yaml','-f','compose.paper-review-memory.yaml')
  $native=Invoke-PaperRuntimeProcess $docker ($compose+@('config','--format','json')) $repo 30
  Check ($native.exitCode -eq 0) 'Existing real Compose overlays resolve with fixtures'
  $oldService=($native.stdout|ConvertFrom-Json).services.'marketbrain-service'
  $fixture=[pscustomobject]@{Config=[pscustomobject]@{Env=@($oldService.environment.PSObject.Properties|ForEach-Object {$_.Name+'='+[string]$_.Value});Labels=[pscustomobject]@{'com.docker.compose.project'='marketbrain'}};Mounts=@($oldService.volumes|ForEach-Object {[pscustomobject]@{Type=$_.type;Source=$_.source;Destination=$_.target;RW=(-not [bool]$_.read_only)}});HostConfig=[pscustomobject]@{Tmpfs=$before.HostConfig.Tmpfs}}
  Set-SupervisedProcessEnvironment (Get-SupervisedDeploymentEnvironment $fixture 'fixture:new') $savedCompose
  $native=Invoke-PaperRuntimeProcess $docker ($compose+@('-f','compose.paytm-supervised.yaml','config','--format','json')) $repo 30
  Check ($native.exitCode -eq 0) 'Supervised real Compose overlays resolve'
  Assert-SupervisedComposePlan ($native.stdout|ConvertFrom-Json) $fixture 'fixture:new'
  Check $true 'Resolved real Compose preserves settings and mounts'
 }finally{Restore-SupervisedProcessEnvironment $savedCompose;Remove-Item -LiteralPath $empty -Force}
}
Write-Host "SUPERVISED_DEPLOYMENT_FIXTURES_PASSED: $count checks"
