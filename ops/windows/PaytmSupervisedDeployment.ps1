# Definitions only. Reuse guarded environment and Docker Desktop mount conversion.
. (Join-Path $PSScriptRoot 'PaperRuntimeDeployment.ps1')
function Get-SupervisedDeploymentEnvironment($Before,[string]$Image) {
 $old=ConvertTo-PaperRuntimeEnvironment $Before.Config.Env
 if($old.MARKETBRAIN_EXECUTION_MODE -cne 'PAPER'){throw 'SUPERVISED_DEPLOY_PAPER_REQUIRED'}
 $result=@{}
 foreach($key in $old.Keys){if($key -clike 'MARKETBRAIN_*'){$result[$key]=$old[$key]}}
 foreach($pair in @(@('/run/secrets/paper-approval.key','MARKETBRAIN_PAPER_APPROVAL_KEY_HOST_FILE',$false),@('/marketbrain-review','MARKETBRAIN_REVIEW_HOST_DIRECTORY',$true))){
  $mount=@($Before.Mounts|Where-Object Destination -CEQ $pair[0])
  if($mount.Count -ne 1 -or $mount[0].Type -cne 'bind' -or $mount[0].RW -ne $pair[2]){throw 'SUPERVISED_DEPLOY_MOUNT_INVALID'}
  $result[$pair[1]]=ConvertTo-PaperHostMount $mount[0].Source
 }
 $result.MARKETBRAIN_PAPER_REVIEW_IMAGE=$Image
 $result.MARKETBRAIN_PAYTM_SUPERVISED_ENABLED='true'
 $result.MARKETBRAIN_PAYTM_AUTH_REHEARSAL_ENABLED='false'
 return $result
}
function Assert-SupervisedDeploymentEnvironment($Before,$Desired) {
 $old=ConvertTo-PaperRuntimeEnvironment $Before.Config.Env
 $expected=@{};foreach($key in $old.Keys){if($key -clike 'MARKETBRAIN_*'){$expected[$key]=$old[$key]}}
 $expected.MARKETBRAIN_PAYTM_SUPERVISED_ENABLED='true';$expected.MARKETBRAIN_PAYTM_AUTH_REHEARSAL_ENABLED='false'
 foreach($key in $expected.Keys){if(-not $Desired.ContainsKey($key) -or $Desired[$key] -cne $expected[$key]){throw 'SUPERVISED_DEPLOY_ENVIRONMENT_DRIFT'}}
 if(@($Desired.Keys|Where-Object {$_ -clike 'MARKETBRAIN_*'}).Count -ne $expected.Count){throw 'SUPERVISED_DEPLOY_ENVIRONMENT_DRIFT'}
}
function Assert-SupervisedComposePlan($Plan,$Before,[string]$Image) {
 $service=$Plan.services.'marketbrain-service'
 $desired=@{};foreach($p in $service.environment.PSObject.Properties){$desired[$p.Name]=[string]$p.Value}
 Assert-SupervisedDeploymentEnvironment $Before $desired
 if($Plan.name -cne $Before.Config.Labels.'com.docker.compose.project' -or $service.image -cne $Image){throw 'SUPERVISED_DEPLOY_IMAGE_OR_PROJECT'}
 $ports=@($service.ports)
 if($ports.Count -ne 1 -or $ports[0].host_ip -cne '127.0.0.1' -or [string]$ports[0].published -cne '8080' -or [string]$ports[0].target -cne '8080'){throw 'SUPERVISED_DEPLOY_PORT'}
 $mounts=@($service.volumes);$oldMounts=@($Before.Mounts|Where-Object Type -CEQ 'bind')
 if($mounts.Count -ne $oldMounts.Count){throw 'SUPERVISED_DEPLOY_MOUNT_DRIFT'}
 foreach($m in $mounts){
  $old=@($oldMounts|Where-Object Destination -CEQ $m.target)
  if($old.Count -ne 1 -or $m.type -cne 'bind' -or (ConvertTo-PaperHostMount $m.source) -cne (ConvertTo-PaperHostMount $old[0].Source) -or [bool]$m.read_only -eq [bool]$old[0].RW){throw 'SUPERVISED_DEPLOY_MOUNT_DRIFT'}
 }
 $expectedTmpfs=@($Before.HostConfig.Tmpfs.PSObject.Properties|ForEach-Object {$_.Name+':'+$_.Value})
 if(($expectedTmpfs|Sort-Object|ConvertTo-Json -Compress) -cne (@($service.tmpfs|Where-Object {$_})|Sort-Object|ConvertTo-Json -Compress)){throw 'SUPERVISED_DEPLOY_TMPFS_DRIFT'}
}
function Set-SupervisedProcessEnvironment([hashtable]$Values,[hashtable]$Saved) {
 foreach($key in $Values.Keys){
  if(-not $Saved.ContainsKey($key)){$Saved[$key]=[Environment]::GetEnvironmentVariable($key,'Process')}
  [Environment]::SetEnvironmentVariable($key,[string]$Values[$key],'Process')
 }
}
function Restore-SupervisedProcessEnvironment([hashtable]$Saved) {
 foreach($key in $Saved.Keys){
  $value=if($null -eq $Saved[$key]){[NullString]::Value}else{$Saved[$key]}
  [Environment]::SetEnvironmentVariable($key,$value,'Process')
 }
}
