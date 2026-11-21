#Requires -Version 7.2
$ErrorActionPreference='Stop'
. "$PSScriptRoot/PaytmAuthenticatedRestart.ps1"
function Invoke-SupervisedRestartDocker([string[]]$Arguments,[int]$Limit=15){
 if($Arguments[0] -eq 'ps'){return 'abcdef123456'}
 if($Arguments[0] -eq 'restart'){$script:restarts++;if($case -eq 'nativeFailure'){throw 'private native detail'};return 'abcdef123456'}
 if($Arguments[0] -eq 'inspect'){$stamp=if($script:restarts -gt 0 -and $case -ne 'unchanged'){'2026-11-21T10:01:00Z'}else{'2026-11-21T10:00:00Z'};return (('a'*64)+' '+$stamp)}
 throw 'unexpected native operation'
}
foreach($case in @('good','unauthenticated','survived','unchanged','nativeFailure')){
 $script:restarts=0;$script:saved=0
 $request={param($command,$body)
  if($command -eq 'status'){
   $locked=($case -eq 'unauthenticated' -or ($script:restarts -gt 0 -and $case -ne 'survived'))
   return @{status=$(if($locked){'LOCKED'}else{'READ_ACCESS_VERIFIED'});readAccessVerified=(-not $locked);ordersEnabled=$false}
  }
  if($command -ne 'quote' -or $body.securityId -ne 2885){throw 'unexpected request'}
  return @{status='SUPERVISED_SESSION_LOCKED';fresh=$false;ordersEnabled=$false}
 }
 $r=Test-PaytmAuthenticatedRestart -SecurityId 2885 -Request $request -Checkpoint {param($v) $script:saved++} -Pause {}
 if($case -eq 'good'){if(-not $r.passed -or -not $r.quoteRejected -or -not $r.startChanged){throw 'RESTART_SUCCESS_FAILED'}}
 elseif($r.passed -or -not $r.failure){throw 'RESTART_FAILURE_NOT_CAUGHT'}
 if($case -eq 'unauthenticated' -and $script:restarts -gt 0){throw 'UNAUTHENTICATED_RESTART'}
 if(($r|ConvertTo-Json) -match 'private native detail' -or $script:saved -lt 1){throw 'RESTART_REPORT_FAILED'}
}
Write-Host 'AUTHENTICATED_RESTART_5_FIXTURES_PASSED'
