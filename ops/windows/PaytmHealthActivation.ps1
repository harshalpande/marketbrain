# Definitions only. Activation controller owns all mutations and rollback decisions.
function Assert-PaytmHealthCompose($Plan,$Before,[string]$Image,[string]$HealthToken) {
 $property=$Plan.services.'marketbrain-service'.environment.PSObject.Properties['MARKETBRAIN_PAYTM_HEALTH_TOKEN']
 if($null -eq $property -or [string]$property.Value -cne $HealthToken){throw 'HEALTH_ACTIVATION_TOKEN_PLAN_MISMATCH'}
 # Compare every pre-existing contract using private copies; only this one new field is allowed.
 $p=$Plan|ConvertTo-Json -Depth 100|ConvertFrom-Json
 $b=$Before|ConvertTo-Json -Depth 100|ConvertFrom-Json
 $p.services.'marketbrain-service'.environment.PSObject.Properties.Remove('MARKETBRAIN_PAYTM_HEALTH_TOKEN')
 $b.Config.Env=@($b.Config.Env|Where-Object {$_ -cnotlike 'MARKETBRAIN_PAYTM_HEALTH_TOKEN=*'})
 $map=ConvertTo-PaperRuntimeEnvironment $b.Config.Env
 Assert-PaperRuntimeCompose $p $b $map.MARKETBRAIN_PAPER_REVIEW_DATABASE_OID $Image
}
function Assert-PaytmHealthPreserved($Before,$After,[string]$HealthToken) {
 $map=ConvertTo-PaperRuntimeEnvironment $After.Config.Env
 if([string]$map['MARKETBRAIN_PAYTM_HEALTH_TOKEN'] -cne $HealthToken){throw 'HEALTH_ACTIVATION_TOKEN_APPLIED_MISMATCH'}
 $b=$Before|ConvertTo-Json -Depth 100|ConvertFrom-Json
 $b.Config.Env=@($b.Config.Env|Where-Object {$_ -cnotlike 'MARKETBRAIN_PAYTM_HEALTH_TOKEN=*'})
 Assert-PaperRuntimePreserved $b $After
}
function Invoke-PaytmHealthActivationRoute([ValidateSet('status','head','lock')][string]$Command) {
 try{
  $r=Invoke-WebRequest ('http://127.0.0.1:8080/api/v1/paytm/route/'+$Command) -Method Post -Headers @{'X-MarketBrain-Paper-Read-Token'=$application.Token;'X-MarketBrain-Paytm-Route'='credential-free'} -NoProxy -TimeoutSec 5 -MaximumRedirection 0 -SkipHttpErrorCheck
  if($r.StatusCode -ne 200 -or ($r.Headers['Cache-Control'] -join ',') -notmatch 'no-store'){throw 'contract'}
  $v=$r.Content|ConvertFrom-Json
  if($v.version -cne 'PAYTM_APPLICATION_ROUTE_V1' -or $v.state -cne 'LOCKED' -or $v.ordersEnabled -isnot [bool] -or $v.ordersEnabled -or $v.credentialsUsed -isnot [bool] -or $v.credentialsUsed -or $v.tlsVerified -or $v.remainingRequests -ne 0){throw 'contract'}
  return $v
 }catch{throw 'HEALTH_ACTIVATION_ROUTE_NOT_LOCKED'}
}
function Assert-PaytmHealthActivationReceipt($Value,[string]$Status,[string]$Boot) {
 if($Value.healthContractVersion -cne 'SERVER_TRANSPORT_V2' -or $Value.status -cne $Status -or $Value.accepted -isnot [bool] -or $Value.accepted -or $Value.ordersEnabled -isnot [bool] -or $Value.ordersEnabled -or $Value.bootId -cne $Boot){throw 'HEALTH_ACTIVATION_RECEIPT'}
}
function Test-PaytmHealthActivationBoundary([string]$HealthToken) {
 foreach($token in @('',('0'*64))){
  if($token -ceq $HealthToken){throw 'HEALTH_ACTIVATION_FIXTURE_TOKEN_COLLISION'}
  try{$r=Invoke-WebRequest 'http://127.0.0.1:8080/api/v1/paytm/route-health/challenge' -Method Post -Headers @{'X-MarketBrain-Paytm-Health'='diagnostic-health';'X-MarketBrain-Paytm-Health-Token'=$token} -NoProxy -TimeoutSec 5 -MaximumRedirection 0 -SkipHttpErrorCheck}catch{throw 'HEALTH_ACTIVATION_AUTH_HTTP_FAILED'}
  if($r.StatusCode -ne 401){throw 'HEALTH_ACTIVATION_AUTH_NOT_REJECTED'}
 }
 $state=Invoke-PaytmHealthActivationRoute 'status';$null=Invoke-PaytmHealthActivationRoute 'head'
 $c=Invoke-PaytmHealthHttp 'challenge' $HealthToken $null
 Assert-PaytmHealthActivationReceipt $c 'CHALLENGE' $state.bootId
 if($c.challenge -cnotmatch '^[a-f0-9-]{36}$' -or $c.validForSeconds -ne 10){throw 'HEALTH_ACTIVATION_CHALLENGE'}
 $body=@{challenge=$c.challenge;bootId=$c.bootId;synchronizedClock=$false;transportHealthy=$false;lowerOffsetSeconds=0;upperOffsetSeconds=0}
 Assert-PaytmHealthActivationReceipt (Invoke-PaytmHealthHttp 'submit' $HealthToken $body) 'UNHEALTHY_AND_LOCKED' $state.bootId
 Assert-PaytmHealthActivationReceipt (Invoke-PaytmHealthHttp 'submit' $HealthToken $body) 'REJECTED_AND_LOCKED' $state.bootId
 $c=Invoke-PaytmHealthHttp 'challenge' $HealthToken $null
 Assert-PaytmHealthActivationReceipt $c 'CHALLENGE' $state.bootId
 $body.challenge=$c.challenge
 $wait=[Diagnostics.Stopwatch]::StartNew()
 while($wait.Elapsed.TotalSeconds -lt 11){Write-Progress -Activity 'Health activation' -PercentComplete 85 -Status ('Expiry check {0:N0}/11 seconds' -f $wait.Elapsed.TotalSeconds);Start-Sleep -Seconds 1}
 Assert-PaytmHealthActivationReceipt (Invoke-PaytmHealthHttp 'submit' $HealthToken $body) 'REJECTED_AND_LOCKED' $state.bootId
 $null=Invoke-PaytmHealthActivationRoute 'lock'
 return $state.bootId
}
function Assert-PaytmHealthRollbackOwnership([string]$Project,[string]$OldImage,[string]$NewImage) {
 $text=Invoke-PaytmPrivateDocker @('ps','-a','--no-trunc','--filter',('label=com.docker.compose.project='+$Project),'--filter','label=com.docker.compose.service=marketbrain-service','--format','{{.ID}}') 'ROLLBACK_OWNERSHIP'
 $ids=@($text -split '\r?\n'|Where-Object {$_})
 if($ids.Count -gt 1){throw 'HEALTH_ACTIVATION_ROLLBACK_AMBIGUOUS'}
 if($ids.Count -eq 1){
  if($ids[0] -cnotmatch '^[a-f0-9]{64}$'){throw 'HEALTH_ACTIVATION_ROLLBACK_ID'}
  $v=@(ConvertFrom-PaytmPrivateJson (Invoke-PaytmPrivateDocker @('inspect',$ids[0]) 'ROLLBACK_PRIVATE_INSPECT'))
  if($v.Count -ne 1 -or $v[0].Image -cnotin @($OldImage,$NewImage) -or (ConvertTo-PaperHostMount $v[0].Config.Labels.'com.docker.compose.project.working_dir') -cne (ConvertTo-PaperHostMount $route.Root)){throw 'HEALTH_ACTIVATION_ROLLBACK_FOREIGN_CONTAINER'}
 }
}
