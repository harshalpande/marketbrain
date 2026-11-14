#Requires -Version 7.0
$ErrorActionPreference='Stop';Set-StrictMode -Version Latest
. (Join-Path $PSScriptRoot 'PaytmHealthActivation.ps1')
$count=0
function ConvertTo-PaperRuntimeEnvironment($Entries){$m=@{};foreach($e in $Entries){$s=$e.Split('=',2);$m[$s[0]]=$s[1]};return $m}
function Assert-PaperRuntimeCompose($Plan,$Before,$Oid,$Image){
 if($Plan.services.'marketbrain-service'.environment.PSObject.Properties['MARKETBRAIN_PAYTM_HEALTH_TOKEN'] -or @($Before.Config.Env|Where-Object {$_ -like 'MARKETBRAIN_PAYTM_HEALTH_TOKEN=*'}).Count){throw 'Wrapper failed to isolate new field'}
 if($Plan.services.'marketbrain-service'.environment.OTHER -cne 'preserved'){throw 'Existing contract changed'}
}
$plan='{"services":{"marketbrain-service":{"environment":{"MARKETBRAIN_PAYTM_HEALTH_TOKEN":"fixture","OTHER":"preserved"}}}}'|ConvertFrom-Json
$before='{"Config":{"Env":["MARKETBRAIN_PAPER_REVIEW_DATABASE_OID=1"]}}'|ConvertFrom-Json
Assert-PaytmHealthCompose $plan $before 'image' 'fixture';$count++
$rejected=$false;try{Assert-PaytmHealthCompose $plan $before 'image' 'different'}catch{$rejected=$true};if(-not $rejected){throw 'Token mismatch not rejected'};$count++
$plan.services.'marketbrain-service'.environment.OTHER='changed';$rejected=$false;try{Assert-PaytmHealthCompose $plan $before 'image' 'fixture'}catch{$rejected=$true};if(-not $rejected){throw 'Underlying check skipped'};$count++
# Exercise the actual bounded HTTP boundary sequence with mock HTTP responses (11-second expiry wait).
$application=@{Token='READ_FIXTURE'};$script:submissions=0;$script:challengeNumber=0
$fixtureBoot='22222222-2222-2222-2222-222222222222'
function Invoke-WebRequest {
 param($Uri,$Method,$Headers,[switch]$NoProxy,$TimeoutSec,$MaximumRedirection,[switch]$SkipHttpErrorCheck)
 if(-not $NoProxy -or $MaximumRedirection -ne 0){throw 'HTTP boundary'}
 if($Uri -like '*/route-health/challenge'){return @{StatusCode=401}}
 if($Headers['X-MarketBrain-Paper-Read-Token'] -cne 'READ_FIXTURE'){throw 'Read authority'}
 @{StatusCode=200;Headers=@{'Cache-Control'='no-store'};Content=(@{version='PAYTM_APPLICATION_ROUTE_V1';state='LOCKED';bootId=$fixtureBoot;ordersEnabled=$false;credentialsUsed=$false;tlsVerified=$false;remainingRequests=0}|ConvertTo-Json)}
}
function Invoke-PaytmHealthHttp($Command,$Token,$Body){
 if($Command -eq 'challenge'){$script:challengeNumber++;return @{healthContractVersion='SERVER_TRANSPORT_V2';status='CHALLENGE';bootId=$fixtureBoot;challenge='11111111-1111-1111-1111-111111111111';validForSeconds=10;accepted=$false;ordersEnabled=$false}}
 if($Body.synchronizedClock -or $Body.transportHealthy){throw 'Healthy evidence must not be published'}
 $script:submissions++;@{healthContractVersion='SERVER_TRANSPORT_V2';status=$(if($script:submissions -eq 1){'UNHEALTHY_AND_LOCKED'}else{'REJECTED_AND_LOCKED'});bootId=$fixtureBoot;accepted=$false;ordersEnabled=$false}
}
if((Test-PaytmHealthActivationBoundary ('F'*64)) -cne $fixtureBoot -or $script:submissions -ne 3 -or $script:challengeNumber -ne 2){throw 'HTTP sequence'};$count++
foreach($bad in @(@{healthContractVersion='OLD';status='REJECTED_AND_LOCKED';bootId=$fixtureBoot;accepted=$false;ordersEnabled=$false},@{healthContractVersion='SERVER_TRANSPORT_V2';status='REJECTED_AND_LOCKED';bootId=$fixtureBoot;accepted=$false;ordersEnabled=$true})){
 $rejected=$false;try{Assert-PaytmHealthActivationReceipt $bad 'REJECTED_AND_LOCKED' $fixtureBoot}catch{$rejected=$true}
 if(-not $rejected){throw 'Unsafe receipt accepted'};$count++
}
# Real controller with all Docker/HTTP/build boundaries replaced. No service changes.
$src=Get-Content (Join-Path $PSScriptRoot 'ActivatePaytmHealthBridge.ps1') -Raw
foreach($n in @('PaytmApplicationRoute.ps1','PaytmHealthDeploymentPreflight.ps1','PaytmHealthPublisher.ps1','PaytmHealthActivation.ps1')){$src=$src.Replace(". (Join-Path `$PSScriptRoot '$n')",'')}
$src=$src.Replace('$PSScriptRoot',("'"+$PSScriptRoot.Replace("'","''")+"'"))
$work=Join-Path ([IO.Path]::GetTempPath()) ('mb-health-activation-'+[guid]::NewGuid().ToString('N'));$null=New-Item -ItemType Directory $work
$oldId='a'*64;$newId='c'*64;$oldImage='sha256:'+('b'*64);$newImage='sha256:'+('d'*64)
$e=Join-Path $work 'receipt.json';@{containerId=$oldId;rollbackImageId=$oldImage}|ConvertTo-Json|Set-Content $e
$src=$src.Replace('DFF50F8D473456A69A8D650074EBA5B46AE4B935E5C281982582360B2CF26F71',(Get-FileHash $e).Hash)
function git {param([Parameter(ValueFromRemainingArguments=$true)]$Arguments) $global:LASTEXITCODE=0;if($Arguments -contains 'rev-parse'){'e'*40}}
function Get-Command {param($Name,$CommandType,$ErrorAction) @{Source='mock-docker'}}
function Get-PaytmApplicationContainer {
 $isNew=$script:phase -eq 'new'
 [pscustomobject]@{Id=$(if($isNew){$newId}else{$oldId});Image=$(if($isNew){$newImage}else{$oldImage});State=@{StartedAt=$(if($isNew){'new'+$script:restarted}else{'old'})};Config=@{Labels=@{'com.docker.compose.project'='fixture'};Env=@('MARKETBRAIN_PAYTM_ENABLED=false','MARKETBRAIN_PAYTM_ACCESS_TOKEN=','MARKETBRAIN_PAPER_READ_TOKEN=SECRET_READ_FIXTURE','MARKETBRAIN_PAPER_REVIEW_DATABASE_OID=1')};Mounts=@(@{Destination='/run/secrets/paper-approval.key';Source='C:/fixture/key'},@{Destination='/marketbrain-review';Source='C:/fixture/review'})}
}
function ConvertTo-PaperHostMount($Path){$Path}
function Assert-PaytmWriterLocked {}
function Read-PaytmHealthPreflightAccount($Token){if($Token -cne 'SECRET_READ_FIXTURE'){throw 'Read token'};'account'}
function Compare-PaytmPackagedMigrations($Jar,$Directory){@{matched=$true}}
function ConvertFrom-PaytmPrivateJson($Text){$Text|ConvertFrom-Json}
function Assert-PaytmHealthCompose($Plan,$Before,$Image,$HealthToken){if($env:MARKETBRAIN_PAYTM_HEALTH_TOKEN -cne $HealthToken){throw 'Token environment'};if($HealthToken){$script:observedToken=$HealthToken}}
function Assert-PaytmHealthPreserved($Before,$After,$HealthToken){if([string]$env:MARKETBRAIN_PAYTM_HEALTH_TOKEN -cne $HealthToken){throw 'Applied token mismatch'}}
function Wait-PaytmApplicationHealth {}
function Test-PaytmHealthActivationBoundary($HealthToken){if($script:scenario -eq 'boundaryfail'){throw 'HEALTH_ACTIVATION_BOUNDARY_FAILURE'};if($HealthToken -cnotmatch '^[A-F0-9]{64}$'){throw 'Random token format'};'oldboot'}
function Invoke-PaytmHealthHttp($Command,$Token,$Body){if($Command -eq 'challenge'){@{challenge='nonce';bootId='oldboot'}}else{@{}}}
function Invoke-PaytmHealthActivationRoute($Command){@{bootId='newboot'}}
function Assert-PaytmHealthActivationReceipt($Value,$Status,$Boot){}
function Assert-PaytmHealthRollbackOwnership($Project,$OldImage,$NewImage){if($script:scenario -eq 'rollbackfail'){throw 'HEALTH_ACTIVATION_FOREIGN_CONTAINER'}}
function Invoke-PaytmPrivateDocker($Arguments,$Phase,$Limit=30){
 $script:operations+=,$Phase
 switch($Phase){
  'CONTEXT'{'fixture'} 'ENDPOINT'{'npipe://fixture'} 'ROLLBACK_IMAGE'{$oldImage}
  'MIGRATION_BASELINE'{[IO.File]::WriteAllText($Arguments[-1],'fixture');''}
  'PRIVATE_COMPOSE_COMPARE'{'{}'}
  'BUILD'{if($script:scenario -eq 'buildfail'){throw 'HEALTH_ACTIVATION_BUILD_FAILED'};''}
  'NEW_IMAGE'{$newImage}
  'DEPLOY'{$script:phase='new';if($script:scenario -in @('deployfail','rollbackfail')){throw 'HEALTH_ACTIVATION_DEPLOY_FAILED'};''}
  'RESTART'{$script:restarted=$true;''}
  'ROLLBACK'{$script:phase='old';''}
  default{throw 'Unexpected command'}
 }
}
$original=[string][Environment]::GetEnvironmentVariable('MARKETBRAIN_PAYTM_HEALTH_TOKEN','Process')
foreach($script:scenario in @('pass','buildfail','deployfail','boundaryfail','rollbackfail')){
 $script:phase='old';$script:restarted=$false;$script:operations=@();$script:observedToken=$null;$out=Join-Path $work $script:scenario;$errorText=$null
 try{& ([scriptblock]::Create($src)) -EvidencePath $e -OutputDirectory $out}catch{$errorText=$_.Exception.Message}
 $raw=Get-Content (Get-ChildItem $out -Filter '*.json').FullName -Raw;$r=$raw|ConvertFrom-Json
 $expected=switch($script:scenario){'pass'{'HEALTH_BRIDGE_DEPLOYED_LOCKED_LIVE_PUBLICATION_PENDING'} {$_ -in @('deployfail','boundaryfail')}{'ACTIVATION_FAILED_ROLLBACK_VERIFIED'} default{'REVIEW_REQUIRED'}}
 if($r.status -cne $expected){throw "Unexpected $script:scenario status: $($r.failure) / $errorText"}
 if($script:scenario -eq 'pass' -and (-not $r.boundaryVerified -or -not $r.restartVerified -or -not $r.accountPreserved -or -not $r.writerLocked -or -not $r.finalRouteLocked -or $errorText)){throw 'Pass flags'}
 if($script:scenario -eq 'buildfail' -and $r.rollbackAttempted){throw 'Premature rollback'}
 if($script:scenario -eq 'rollbackfail' -and ($r.rollbackVerified -or $script:operations -contains 'ROLLBACK')){throw 'Foreign rollback permitted'}
 if($raw.Contains('SECRET_READ_FIXTURE') -or ($script:observedToken -and $raw.Contains($script:observedToken)) -or $r.ordersEnabled -or $r.healthyEvidencePublished){throw 'Secret/authority leak'}
 if([string][Environment]::GetEnvironmentVariable('MARKETBRAIN_PAYTM_HEALTH_TOKEN','Process') -cne $original){throw 'Environment restoration'}
 $count++
}
Write-Host "PASS: $count activation/rollback fixtures; no Docker, network or application calls."
