#Requires -Version 5.1
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'PaytmHealthCollectorCore.ps1')
$boot='aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'
function Invoke-CollectorHttp($Token,$Command,$Body,[switch]$ExpectUnauthorized){
 if($ExpectUnauthorized){
  if($Token -cne 'FIXTURE_SECRET-invalid' -or $Command -cne 'clock'){throw 'Unexpected token probe'}
  if($script:case -eq 'http'){throw 'COLLECTOR_HTTP_FAILED'}
  return @{status=$(if($script:case -eq 'auth'){'ACCEPTED'}else{'UNAUTHORIZED'});ordersEnabled=$false}
 }
 $r=@{healthContractVersion='SERVER_TRANSPORT_V2';bootId=$boot;ordersEnabled=$false;accepted=$false}
 if($Command -eq 'challenge'){
  $script:used=$false;$script:expired=$false;$r.status='CHALLENGE';$r.validForSeconds=10;$r.challenge='bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb'
  if($script:case -eq 'challenge'){$r.validForSeconds=1};return $r
 }
 if($Body.synchronizedClock -or $Body.transportHealthy){throw 'Negative test asserted healthy state'}
 $r.status=if($script:used -or $script:expired -or $Body.bootId -cne $boot){'REJECTED_AND_LOCKED'}else{'UNHEALTHY_AND_LOCKED'}
 $script:used=$true
 if($script:case -eq 'accept'){$r.accepted=$true}
 if($script:case -eq 'status'){$r.status='UNKNOWN'}
 return $r
}
function Start-Sleep {param($Seconds) if($Seconds -ne 11){throw 'Wrong expiry wait'};$script:expired=$true}
function Invoke-CollectorCycle($Token,$SshArguments,$Boot,[switch]$Revoke){
 if($Revoke){$script:revocations++;return @{revoked=($script:case -ne 'revoke')}}
 return @{accepted=($script:case -ne 'recovery');healthySubmitted=$true}
}
foreach($script:case in @('valid','http','auth','challenge','accept','status','recovery','revoke')){
 $script:used=$false;$script:expired=$false;$script:revocations=0
 $v=Invoke-CollectorLifecycleCases 'FIXTURE_SECRET' @() $boot
 if($v.passed -ne ($case -eq 'valid') -or $script:revocations -ne 1 -or ($v|ConvertTo-Json -Depth 6) -match 'FIXTURE_SECRET'){throw "Lifecycle case failed: $case"}
 if($case -eq 'valid' -and (($v.cases.name -join ',') -cne 'INVALID_TOKEN,REPLAY,WRONG_BOOT,EXPIRED_CHALLENGE,FRESH_RECOVERY')){throw 'Case coverage incomplete'}
}
Write-Host 'COLLECTOR_LIFECYCLE_FIXTURES_PASSED: 8 cases, revocation on all paths, no secret export; mocked HTTP/time.'
