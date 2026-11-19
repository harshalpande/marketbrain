#Requires -Version 7.0
[CmdletBinding()]param([switch]$IncidentRecoveryFixture,[switch]$TlsPhaseFixture,[switch]$TlsResumeFixture,[switch]$TlsStabilityFixture,[switch]$HealthResumeFixture,[switch]$ReviewedSshFixture)
if($ReviewedSshFixture){$HealthResumeFixture=$true}
if($TlsResumeFixture){$TlsPhaseFixture=$true}
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'PaytmSupervisorHost.ps1')
. (Join-Path $PSScriptRoot 'PaytmGatewaySession.ps1')
. (Join-Path $PSScriptRoot 'PaytmTransportHealthResume.ps1')
Set-StrictMode -Version Latest
$tmp=Join-Path ([IO.Path]::GetTempPath()) ('mb-native-controller-'+[guid]::NewGuid().ToString('N'))
$global:mbNativeControllerFixture=@{};$checks=0
function Check($Ok,$Name){if(-not $Ok){throw "NATIVE_CONTROLLER_$Name"};$script:checks++}
function Assert-PaytmAccountPath($Path){$Path}
function Assert-PaytmCustodyController {}
function Assert-PaytmAccountAcl {}
function Get-Acl {}
function Import-Module {}
function Get-PaytmHostContract {@{root=$global:mbNativeControllerFixture.root;work=$global:mbNativeControllerFixture.root}}
function Get-PaytmAccountContract {@{root=$global:mbNativeControllerFixture.root}}
function Get-PaytmKeyContract {@{accountSid='fixture'}}
function Assert-PaytmNativeReceipt {if($global:mbNativeControllerFixture.case -eq 'preflight'){throw 'HOST_NATIVE_RECEIPT_NOT_REVIEWED'}}
function Get-FileHash($LiteralPath){
 if($LiteralPath -eq $global:mbNativeControllerFixture.receipt){@{Hash='078A34DB0A46951EB98C5A08063F9FC76DB6EC75C175A3572CEE3D65DA4FAB4B'}}
 else{Microsoft.PowerShell.Utility\Get-FileHash -LiteralPath $LiteralPath}
}
function Assert-PaytmTransportAcceptance {}
function Assert-PaytmTransportInstallationSources {@{installationId=('a'*32)}}
function Initialize-PaytmManagedApplication {
 Save-Report # Exercise the real route helper callback name.
 if($global:mbNativeControllerFixture.case -eq 'application_unavailable'){throw 'APP_ROUTE_NOT_READY'}
 $application.Ready=$true;$application.BootId='boot';$application.Id='container'
 $application.Before=@{Image='image';State=@{StartedAt='start'}};$application.BeforeAccount='same';$application.Token='PRIVATE_TOKEN'
}
function Invoke-PaytmNativeRecovery {
 if($global:mbNativeControllerFixture.case -eq 'build_failed'){throw 'HOST_NATIVE_BUILD_FAILED'}
 $report.nativeRecoveryAttempted=$true
 if($global:mbNativeControllerFixture.case -eq 'start_failed'){throw 'HOST_NATIVE_START_FAILED'}
 $report.nativeRecovery=@{first=@{installationId=('a'*32);sequence=1;processId=1;instanceId=('b'*32)}}
}
function Invoke-PaytmApplicationHead {if($HealthResumeFixture){throw 'Unexpected route arming in transport-only test'};Save-Report}
function Wait-PaytmManagedHost {
 if($global:mbNativeControllerFixture.case -ne 'pass'){throw 'TRANSPORT_WORKER_BLOCKED'}
 $global:mbNativeControllerFixture.sequence++
 @{installationId=('a'*32);instanceId=('b'*32);processId=1;sequence=$global:mbNativeControllerFixture.sequence;elapsedSeconds=10;transportState=@{lastHealthSeconds=10};httpStatus=503}
}
function Assert-PaytmNativeSoakSample($First,$Current){if($Current.sequence -le $First.sequence){throw 'HOST_NATIVE_SAMPLE_STALE'}}
function Invoke-PaytmTlsDiagnosticCapture {
 if($global:mbNativeControllerFixture.case -eq 'report_oversize'){$report.oversizedFixture='X'*70000}
 if($global:mbNativeControllerFixture.case -in @('soak_failed','stop_failed')){throw 'HOST_TLS_CAPTURE_FAILED'}
 $report.diagnostic=@{captureCompleted=$true}
}
function Invoke-PaytmApplicationHttp {param($Command);if($HealthResumeFixture -and $Command -eq 'arm'){throw 'Unexpected arm'};if($global:mbNativeControllerFixture.case -eq 'lock_failed'){throw 'APP_ROUTE_FINAL_LOCK_FAILED'};@{state='LOCKED';bootId='boot';ordersEnabled=$false;credentialsUsed=$false;status='LOCKED';httpStatus=0;tlsVerified=$false}}
function Assert-PaytmWriterLocked {}
function Get-PaytmApplicationContainer {@{Id='container';Image='image';State=@{StartedAt='start'}}}
function Read-PaytmPaperAccount {'same'}
function Get-PaytmWorkerFailureEvidence {@{readOnly=$true;files=@{}}}
function Stop-PaytmFailedManagedHost {$global:mbNativeControllerFixture.stops++;if($global:mbNativeControllerFixture.case -eq 'stop_failed'){throw 'HOST_STOP_FAILED'}}
try{
 $cases=@('pass','preflight','application_unavailable','build_failed','start_failed','soak_failed','lock_failed','stop_failed')
 if($TlsPhaseFixture){$cases+='report_oversize'}
 foreach($case in $cases){
  $base=Join-Path $tmp $case;$root=Join-Path $base root;$ops=Join-Path $base 'ops/windows';$out=Join-Path $base out
  $null=New-Item -ItemType Directory -Path $root,$ops,$out -Force
  $global:mbNativeControllerFixture=@{case=$case;root=$root;receipt=(Join-Path $base receipt.json);stops=0;sequence=1}
  Write-PaytmHostJson $global:mbNativeControllerFixture.receipt @{fixture=$true}
  foreach($n in @('PaytmGatewayAccount.ps1','PaytmGatewayKeyCustody.ps1','PaytmGatewayScheduledProbe.ps1','PaytmSupervisorHost.ps1','PaytmSupervisorInstallation.ps1','PaytmSupervisorTransport.ps1','PaytmApplicationRoute.ps1','PaytmManagedTransport.ps1','PaytmGatewayRestart.ps1','PaytmGatewaySession.ps1','PaytmGatewayFailureEvidence.ps1','PaytmNativeRecovery.ps1','PaytmSupervisorNative.cs','RunPaytmGatewaySupervisor.ps1')){[IO.File]::WriteAllText((Join-Path $ops $n),'# fixture')}
  $file=Join-Path $ops 'RepairPaytmNativeProcess.ps1';Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'RepairPaytmNativeProcess.ps1') -Destination $file
  $extra=@{}
  if($HealthResumeFixture){$extra.HealthBlockedTransportResume=$true;[IO.File]::WriteAllText((Join-Path $ops 'PaytmTransportHealthResume.ps1'),'# adapter mocked separately')}
  if($ReviewedSshFixture){$extra.Remove('HealthBlockedTransportResume');$extra.ReviewedSshRecovery=$true;[IO.File]::WriteAllText((Join-Path $ops 'PaytmReviewedSshRecovery.ps1'),'# adapter mocked separately')}
  if($IncidentRecoveryFixture){
   [IO.File]::WriteAllText((Join-Path $ops 'PaytmIncidentRecovery.ps1'),'# adapter mocked separately')
   $extra.IncidentRecovery=$true
  }
  if($TlsPhaseFixture){
   foreach($n in @('PaytmTlsPhaseRecovery.ps1','PaytmTlsDiagnosticCapture.ps1')){[IO.File]::WriteAllText((Join-Path $ops $n),'# adapter mocked separately')}
   $extra.TlsPhaseDiagnostic=$true
  }
  if($TlsResumeFixture){
   $extra.Remove('TlsPhaseDiagnostic')
   $extra.TlsCaptureResume=$true
   [IO.File]::WriteAllText((Join-Path $ops 'PaytmTlsCaptureResume.ps1'),'# mocked adapter')
  }
  if($TlsStabilityFixture){
   $extra.TlsStabilityRecovery=$true
   [IO.File]::WriteAllText((Join-Path $ops 'PaytmTlsStabilityRecovery.ps1'),'# mocked adapter')
  }
  if($case -eq 'pass'){
   # Test controller completion only with a shortened local copy; production has
   # no duration switch. The 30-minute spare observation is explicitly pending.
   $text=[IO.File]::ReadAllText($file).Replace('1800','0')
   [IO.File]::WriteAllText($file,$text)
  }
  $failed=$false;try{& $file @extra -DiagnosticReportPath $global:mbNativeControllerFixture.receipt -TransportReportPath $global:mbNativeControllerFixture.receipt -OutputDirectory $out 6>$null}catch{$failed=$true;$caught=$_}
  Check ($failed -eq ($case -ne 'pass')) ($case+'_OUTCOME')
  $files=@(Get-ChildItem -LiteralPath $out -Filter '*.json')
  if($case -eq 'report_oversize'){
   Check ($files.Count -eq 2 -and $global:mbNativeControllerFixture.stops -eq 1) 'OVERSIZE_STOP_AND_FALLBACK'
   $fallback=@($files|Where-Object Name -Like '*.final.json')
   $small=Read-PaytmHostJson $fallback[0].FullName 65536
   Check ($small.failureStopVerified -and $small.finalApplicationLockVerified -and $small.accountPreserved -and $small.status -ceq 'REVIEW_REQUIRED') 'FALLBACK_PRESERVES_CLEANUP_RESULTS'
   continue
  }
  if($files.Count -ne 1){throw $caught};Check ($files.Count -eq 1) 'ONE_REPORT'
  $v=Read-PaytmHostJson $files[0].FullName 65536
  if($TlsResumeFixture){Check ($v.recoveryMode -ceq 'TLS_CAPTURE_RESUME_NO_CODE_REPLACEMENT') 'RESUME_MODE_WIRED'}
  if($TlsStabilityFixture){Check ($v.recoveryMode -ceq 'TLS_STABILITY_AFTER_ACCEPTED_CAPTURE_NO_CODE_REPLACEMENT') 'STABILITY_MODE_WIRED'}
  if($TlsPhaseFixture -and $case -eq 'pass'){
   Check ($v.status -ceq 'TLS_DIAGNOSTICS_CAPTURED_GATEWAY_STOPPED_REVIEW_REQUIRED' -and -not $v.soakPassed -and $v.failureStopVerified -and $v.diagnostic.captureCompleted -and $global:mbNativeControllerFixture.stops -eq 1) 'DIAGNOSTIC_SUCCESS_STOPS_WITHOUT_HEALTH_CREDIT'
   continue
  }
  if($IncidentRecoveryFixture){Check ($v.recoveryMode -ceq 'AFTER_SSH_INCIDENT_NO_CODE_REPLACEMENT') 'INCIDENT_MODE_WIRED'}
  if($case -eq 'pass'){
   $expectedStatus=if($HealthResumeFixture){'TRANSPORT_STABILITY_PASSED_APPLICATION_HEALTH_PENDING'}else{'NATIVE_RECOVERY_AND_30_MINUTE_OBSERVATION_PASSED'}
   if($HealthResumeFixture){Check ($v.applicationHealthPending -and $v.applicationRouteChecks.Count -eq 2) 'HEALTH_PENDING_AND_LOCK_CHECKS'}
   Check ($v.status -ceq $expectedStatus -and $v.soakPassed -and $v.accountPreserved -and $v.finalApplicationLockVerified -and $v.soak.observations -eq 2 -and $global:mbNativeControllerFixture.stops -eq 0) 'COMPLETION_AND_FINAL_SAMPLE'
   continue
  }
  Check ($v.status -eq 'REVIEW_REQUIRED' -and -not $v.soakPassed) 'NO_FALSE_SUCCESS'
  $attempted=$case -in @('start_failed','soak_failed','lock_failed','stop_failed')
  Check ($v.nativeRecoveryAttempted -eq $attempted -and $global:mbNativeControllerFixture.stops -eq [int]$attempted) 'ONLY_OWNED_RECOVERY_STOPPED'
  Check (-not ([IO.File]::ReadAllText($files[0].FullName)).Contains('PRIVATE_TOKEN')) 'TOKEN_NOT_RECORDED'
  Check ($v.workerDiagnostics.readOnly) 'FAILURE_DIAGNOSTICS_PRESERVED'
  if($case -eq 'stop_failed'){Check ($v.cleanupFailure -eq 'HOST_NATIVE_FAILURE_STOP_REVIEW_REQUIRED' -and -not $v.failureStopVerified) 'STOP_FAILURE_VISIBLE'}
  if($case -eq 'soak_failed'){$expectedFailure=if($TlsPhaseFixture){'HOST_TLS_CAPTURE_FAILED'}else{'TRANSPORT_WORKER_BLOCKED'};Check ($v.failure -eq $expectedFailure -and $v.finalApplicationLockVerified -and $v.accountPreserved) 'SOAK_FAILURE_LOCKS_AND_ACCOUNT'}
 }
 [pscustomobject]@{status='NATIVE_CONTROLLER_FAILURES_PASSED';assertions=$checks;workflows=$cases.Count;acceleratedSuccessFixtureOnly=$true;runtimeApisMocked=$true}|ConvertTo-Json
}finally{
 $full=[IO.Path]::GetFullPath($tmp);$parent=[IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\')+'\'
 if(-not $full.StartsWith($parent,[StringComparison]::OrdinalIgnoreCase) -or [IO.Path]::GetFileName($full) -notmatch '^mb-native-controller-[a-f0-9]{32}$'){throw 'UNSAFE_NATIVE_CONTROLLER_CLEANUP'}
 if(Test-Path -LiteralPath $full){Remove-Item -LiteralPath $full -Recurse -Force}
 Remove-Variable mbNativeControllerFixture -Scope Global
}
