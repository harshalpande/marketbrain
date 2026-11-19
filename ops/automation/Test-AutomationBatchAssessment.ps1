#requires -Version 7.2
$ErrorActionPreference='Stop'
Set-StrictMode -Version Latest
. (Join-Path $PSScriptRoot 'Automation.BatchAssessment.ps1')
$base=@{state='SUCCEEDED';result=@{ordersEnabled=$false;paytmObservation=@{loopbackTcpConnected=$true;elevated=$true;windowsStatus=@{exitCode=0;stdout='Last Sync Error: 0'};windowsSource=@{exitCode=0};gatewaySupervisor=@{files=@{'status.json'=@{state='READ';fields=@{phase='TRANSPORT_READY'}}}};proxyObservations=@(@{observation=@{exitCode=0;timedOut=$false;stdout='503|200|127.0.0.1|0|0|0'}},@{observation=@{exitCode=0;timedOut=$false;stdout='503|200|127.0.0.1|0|0|0'}})}}}
$json=$base|ConvertTo-Json -Depth 12
$count=0
foreach($case in @('pass','transport','permission','clock','unavailable','failed','malformed','scope')){
 $job=$json|ConvertFrom-Json;$p=$job.result.paytmObservation
 switch($case){
  transport {$p.proxyObservations[0].observation.exitCode=28}
  permission {$p.elevated=$false;$p.windowsSource.exitCode=-2147024891}
  clock {$p.windowsStatus.stdout='Last Sync Error: 2'}
  unavailable {$p.gatewaySupervisor.files.'status.json'.state='UNAVAILABLE'}
  failed {$job.state='FAILED'}
  malformed {$job=[pscustomobject]@{state='SUCCEEDED'}}
  scope {$job.result.ordersEnabled=$true}
 }
 $r=Get-AutomationBatchAssessment $job
 $expected=@{pass='';transport='TRANSPORT_FAILED';permission='WINDOWS_TIME_QUERY_FAILED';clock='WINDOWS_SYNC_NOT_CONFIRMED';unavailable='SUPERVISOR_STATUS_UNAVAILABLE';failed='JOB_NOT_SUCCEEDED';malformed='MALFORMED_DIAGNOSTIC';scope='SCOPE_UNCONFIRMED'}[$case]
 if(($case -eq 'pass' -and $r.findings.Count -ne 0) -or ($expected -and $expected -notin $r.findings)){throw "Unexpected assessment: $case"}
 if($case -in @('failed','malformed','transport') -and $r.transportPassed){throw 'False transport pass'}
 if($r.ContainsKey('applicationHealthAccepted') -and $r.applicationHealthAccepted){throw 'False application acceptance'}
 $count++
}
Write-Host "PASS: $count diagnostic batch classification cases; transport and readiness separated"
