#Requires -Version 7.0
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'PaytmApplicationRoute.ps1')
$tokens=$null;$errors=$null
$ast=[Management.Automation.Language.Parser]::ParseFile((Join-Path $PSScriptRoot 'TestPaperRuntimeDeploymentWorkflow.ps1'),[ref]$tokens,[ref]$errors)
foreach($f in $ast.FindAll({param($a)$a -is [Management.Automation.Language.FunctionDefinitionAst] -and $a.Name -eq 'Container'},$true)){. ([scriptblock]::Create($f.Extent.Text))}
$repo=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../..'));$route=@{Root=$repo};$application=@{Docker='fixture'};$checks=0
function Check($Ok,$Name){if(-not $Ok){throw "DISCOVERY_TEST_$Name"};$script:checks++}
function Save-Report {}
function Invoke-PaperRuntimeProcess($Executable,$Arguments,$Directory,$LimitSeconds){
 if($Arguments[0] -eq 'ps'){
  if($Arguments -notcontains '--all' -or $Arguments -notcontains '--no-trunc'){throw 'TEST_DISCOVERY_NOT_ALL'}
  $out=if($scenario -eq 'malformed'){'do-not-record-secret-output'}else{(@($containers|ForEach-Object {$_.Id}) -join "`r`n")}
 }elseif($Arguments[0] -eq 'inspect'){
  if($scenario -eq 'inspect_failure'){return @{exitCode=1;stdout='do-not-record-secret-output';elapsedSeconds=0}}
  $out=($containers|Where-Object Id -CEQ $Arguments[1]|ConvertTo-Json -Depth 12)
 }else{throw 'TEST_UNEXPECTED_DOCKER_MUTATION'}
 @{exitCode=0;stdout=$out;elapsedSeconds=0}
}
foreach($scenario in @('single','other_workspace','empty','wrong_workspace','stopped','paused','restarting','duplicate','malformed','inspect_failure','unsafe_config')){
 $report=[ordered]@{applicationCommands=[Collections.Generic.List[object]]::new()}
 $one=Container -Memory;$one.State|Add-Member Restarting $false;$one.State|Add-Member ExitCode 0;$one.State|Add-Member OOMKilled $false
 $containers=@($one);$expected=$null
 switch($scenario){
  other_workspace {$other=Container -Memory;$other.Id='c'*64;$other.Config.Labels.'com.docker.compose.project.working_dir'='C:/other';$containers+=@($other)}
  empty {$containers=@();$expected='APP_ROUTE_APPLICATION_NOT_FOUND'}
  wrong_workspace {$one.Config.Labels.'com.docker.compose.project.working_dir'='C:/other';$expected='APP_ROUTE_APPLICATION_NOT_FOUND'}
  stopped {$one.State.Running=$false;$one.State.ExitCode=255;$expected='APP_ROUTE_APPLICATION_NOT_RUNNING'}
  paused {$one.State.Paused=$true;$expected='APP_ROUTE_APPLICATION_NOT_RUNNING'}
  restarting {$one.State.Restarting=$true;$expected='APP_ROUTE_APPLICATION_NOT_RUNNING'}
  duplicate {$other=Container -Memory;$other.Id='c'*64;$containers+=@($other);$expected='APP_ROUTE_MULTIPLE_WORKSPACE_CONTAINERS'}
  malformed {$expected='APP_ROUTE_CONTAINER_LIST_INVALID'}
  inspect_failure {$expected='APP_ROUTE_NATIVE_FAILED_PRIVATE_INSPECT'}
  unsafe_config {$one.HostConfig.Privileged=$true;$expected='DEPLOY_UNSAFE_CONTAINER'}
 }
 foreach($container in $containers){foreach($field in @('Restarting','ExitCode','OOMKilled')){if(-not $container.State.PSObject.Properties[$field]){$container.State|Add-Member $field $(if($field -eq 'ExitCode'){0}else{$false})}}}
 $actual=$null;$selected=$null
 try{$selected=Get-PaytmApplicationContainer}catch{$actual=$_.Exception.Message}
 if($actual -cne $expected){throw "DISCOVERY_CLASSIFY_${scenario}: expected '$expected', actual '$actual'"}
 Check $true ('CLASSIFY_'+$scenario)
 if(-not $expected){Check ($selected.Id -ceq ('b'*64) -and $report.applicationDiscovery.result -ceq 'VERIFIED') 'EXACT_WORKSPACE'}
 if($scenario -eq 'stopped'){Check ($report.applicationDiscovery.candidates[0].exitCode -eq 255 -and -not $report.applicationDiscovery.candidates[0].running) 'STOPPED_EVIDENCE'}
 $json=$report|ConvertTo-Json -Depth 12
 Check ($json -notmatch 'never-record-this-password|do-not-record-secret-output|MARKETBRAIN_PAPER_READ_TOKEN') 'SECRET_FREE'
}
[pscustomobject]@{status='APPLICATION_DISCOVERY_PASSED';assertions=$checks;scenarios=11;dockerAndRuntimeMocked=$true;realDiscoveryAndConfigurationValidation=$true}|ConvertTo-Json
