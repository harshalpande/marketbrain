#Requires -Version 7.2
$ErrorActionPreference='Stop'
. "$PSScriptRoot/SupervisedLifecycleProbe.ps1"
function Invoke-UniverseDocker([string[]]$Arguments){if($Arguments[0] -eq 'ps'){return 'abcdef123456'};return ('t'*40)}
function Invoke-LifecycleHttp($Client,[string]$Path,[string]$Token,[string]$Body,[string]$Cookie){
 $script:requests++
 $r=@{code=200;content='{}';noStore=$true;cookies=@()}
 switch -Regex ($Path){
  '/status$' {$r.content=(@{status=$script:state;ordersEnabled=$false;readAccessVerified=$false}|ConvertTo-Json)}
  '/start$' {
   $script:starts++;$script:state='AWAITING_BROWSER';$script:code=if($script:starts -eq 1){'C'*43}else{'D'*43}
   $r.content=(@{browserUrl=('http://127.0.0.1:8080/paytm/supervised/browser?code='+$script:code);ordersEnabled=$false}|ConvertTo-Json)
  }
  '/browser\?' {
   if($script:scenario -eq 'network'){throw 'PRIVATE_TOKEN_DO_NOT_REPORT'}
   if($Path.Split('=')[-1] -ceq $script:code -and $script:state -eq 'AWAITING_BROWSER'){$script:state='AWAITING_CALLBACK';$r.code=303;$r.cookies=@(('marketbrain_paytm_supervised='+('E'*43)+'; Path=/paytm; HttpOnly'))}else{$r.code=400}
  }
  '/callback\?' {
   if($Path -cnotmatch '^/paytm/callback\?success=false&state=[CD]{43}$'){throw 'UNSAFE_CALLBACK'}
   $r.code=400;if($Cookie -ceq ('E'*43)){$script:state='LOCKED'}
  }
  '/lock$' {if($script:scenario -eq 'cleanup'){throw 'cleanup failure'};$script:state='LOCKED'}
  default {throw 'UNEXPECTED_PATH'}
 }
 return $r
}
foreach($scenario in @('good','busy','network','cleanup')){
 $script:scenario=$scenario;$script:state=if($scenario -eq 'busy'){'READ_ACCESS_VERIFIED'}else{'LOCKED'};$script:starts=0;$script:requests=0
 $r=Invoke-SupervisedLifecycleProbe
 if(($r|ConvertTo-Json -Depth 8) -match 'PRIVATE_TOKEN_DO_NOT_REPORT|EEEEEEEE|CCCCCCCC|not-a-broker-secret'){throw 'REPORT_LEAK'}
 if($scenario -eq 'good'){if(-not $r.passed -or -not $r.finalLocked -or $r.checks.Count -ne 14){throw 'SUCCESS_FIXTURE_FAILED'}}
 else {if($r.passed){throw 'FAILURE_NOT_CAUGHT'}}
 if($scenario -eq 'busy' -and ($script:requests -ne 1 -or $script:starts -ne 0)){throw 'ACTIVE_SESSION_TOUCHED'}
 if($scenario -eq 'network' -and -not $r.finalLocked){throw 'FAILURE_CLEANUP_MISSING'}
 if($scenario -eq 'cleanup' -and $r.failure -ne 'LIFECYCLE_CLEANUP_NOT_VERIFIED'){throw 'CLEANUP_FAILURE_MISSING'}
}
Write-Host 'SUPERVISED_LIFECYCLE_4_FIXTURES_PASSED'
