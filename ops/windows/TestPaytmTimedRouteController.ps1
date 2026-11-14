#Requires -Version 7.0
# Mock only Docker/process boundary; execute the real controller and JSON writer.
$ErrorActionPreference='Stop'
$src=Get-Content (Join-Path $PSScriptRoot 'TestPaytmTimedRouteBundle.ps1') -Raw
$src=$src.Replace(". (Join-Path `$PSScriptRoot 'NumericalEvaluationEngineering.ps1')",'')
$src=$src.Replace('$PSScriptRoot',("'"+$PSScriptRoot.Replace("'","''")+"'"))
# Scriptblock has no PSCommandPath use fixed real runner hash input already explicit.
$root=Join-Path ([IO.Path]::GetTempPath()) ('mb-timed-route-'+[guid]::NewGuid().ToString('N'));$null=New-Item -ItemType Directory $root
$e=Join-Path $root 'receipt.json';'{}'|Set-Content $e
$src=$src.Replace('FAED8C8AB1FE465A274D8CE08A17D893F8F9DF38A547D08726CA070676DC2C4D',(Get-FileHash $e).Hash)
function Get-Command {param($Name,$CommandType,$ErrorAction) [pscustomobject]@{Source='mock-docker'}}
function Invoke-EvaluationProcess($Executable,$Arguments,$TimeoutSeconds){
 $v=@{exitCode=0;timedOut=$false;stdout='';stderr='';elapsedSeconds=0.01}
 switch($Arguments[0]){
 'context'{$v.stdout=if($Arguments[1] -eq 'show'){'fixture'}else{'npipe://fixture'}}
 'build'{if($script:scenario -eq 'buildfail'){$v.exitCode=1}}
 'run'{
  if($Arguments -notcontains 'none' -or $Arguments -contains '-v' -or $Arguments -contains '-p'){throw 'Container isolation regression'}
  $script:label=($Arguments|Where-Object {$_ -like 'marketbrain.verification.run=*'}).Split('=')[1]
  $v.stdout='{"status":"JAVA_HEALTH_TRANSPORT_TESTS_PASSED_DEPLOYMENT_PENDING","junitTests":35,"guardAssertions":39,"liveHealthProviderConnected":false,"runningApplicationChanged":false,"ordersEnabled":false}'
  if($script:scenario -eq 'runfail'){$v.exitCode=1}
 }
 'ps'{if($script:scenario -in @('runfail','cleanupfail')){$v.stdout='owned-container'}}
 'inspect'{$v.stdout=$script:label}
 'rm'{if($script:scenario -eq 'cleanupfail'){$v.exitCode=1}}
 default{throw 'Unexpected Docker command'}
 };$v
}
$count=0
foreach($script:scenario in @('pass','buildfail','runfail','cleanupfail')){
 $out=Join-Path $root $script:scenario;$err=$null
 try{& ([scriptblock]::Create($src)) -EvidencePath $e -OutputDirectory $out}catch{$err=$_.Exception.Message}
 $r=Get-Content (Get-ChildItem $out -Filter '*.json').FullName -Raw|ConvertFrom-Json
 if($script:scenario -eq 'pass'){if($err -or -not $r.containerRemoved -or $r.status -ne 'JAVA_HEALTH_TRANSPORT_TESTS_PASSED_DEPLOYMENT_PENDING'){throw 'Pass fixture'}}else{if(-not $err -or $r.status -ne 'REVIEW_REQUIRED'){throw 'Failure fixture'}}
 if($r.runningApplicationChanged -or $r.ordersEnabled){throw 'Authority regression'};$count++
}
Write-Host "PASS: $count isolated Docker controller fixtures; no Docker calls made."
