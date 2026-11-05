#Requires -Version 7.0
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'PaytmSupervisorHost.ps1')
. (Join-Path $PSScriptRoot 'PaytmManagedTransport.ps1')
. (Join-Path $PSScriptRoot 'PaytmGatewayRestart.ps1')
. (Join-Path $PSScriptRoot 'PaytmGatewaySession.ps1')
# Exercise the real collector, checkpoint writer/reader and boundary assertions.
# Native privileged runtime APIs are fixtures; native session query is separately tested.
$temp=Join-Path ([IO.Path]::GetTempPath()) ('mb-session-test-'+[guid]::NewGuid().ToString('N'))
$null=New-Item -ItemType Directory -Path $temp
$count=@{checks=0};$fixture=@{}
function Check($Ok,$Name){if(-not $Ok){throw "SESSION_TEST_$Name"};$count.checks++}
function Assert-PaytmCustodyController {}
function Assert-PaytmAccountPath($Path){$Path}
function Assert-PaytmAccountAcl {}
function Get-Acl {}
function Import-Module {}
function Get-PaytmHostContract {@{root=$fixture.root;work=$fixture.root}}
function Get-PaytmAccountContract {@{root=$fixture.root}}
function Get-PaytmKeyContract {@{accountSid='fixture'}}
function Get-FileHash($LiteralPath){
 if($LiteralPath -eq $fixture.network){@{Hash='860F63E79D86A6460EA87C2C492B84FEA342FD919E85019E6C26D2B8CA5C3773'}}
 elseif($LiteralPath -eq $fixture.receipt){@{Hash='078A34DB0A46951EB98C5A08063F9FC76DB6EC75C175A3572CEE3D65DA4FAB4B'}}
 else{Microsoft.PowerShell.Utility\Get-FileHash -LiteralPath $LiteralPath}
}
function Assert-PaytmTransportAcceptance {}
function Assert-PaytmInstalledTransport {
 $hash=if($fixture.scenario -eq 'install_drift' -and $Phase -ne 'Before'){'changed'}else{'same'}
 [pscustomobject]@{installationId='fixture';hashes=@{'runner.ps1'=$hash;'host.ps1'='2';'native.dll'='3';'gateway.ps1'='4';'transport.ps1'='5';'transport.dll'='6'}}
}
function Get-PaytmRestartObservation {
 $boot=if($Phase -eq 'AfterBoot' -and $fixture.scenario -ne 'no_boot'){'2026-11-06T10:00:00Z'}else{'2026-11-05T10:00:00Z'}
 $instance=if($Phase -eq 'AfterBoot'){'b'*32}else{'a'*32}
 if($fixture.scenario -eq 'worker_restarted' -and $Phase -eq 'AfterLogoff'){$instance='c'*32}
 $seq=if($Phase -eq 'Before'){10}else{30}
 $v=[pscustomobject]@{machineHash=('A'*64);bootUtc=$boot;workerStartUtc=$boot;collectorStartUtc=([DateTimeOffset]::Parse($boot).AddHours(1).ToString('o'));taskLastRunUtc=$boot;
  worker=@{version=1;installationId='fixture';instanceId=$instance;processId=100;sessionId=0;sequence=$seq;elapsedSeconds=$seq;phase='TRANSPORT_READY';failure=$null;identityVerified=$true;jobContained=$true}}
 if($fixture.scenario -eq 'machine_drift' -and $Phase -ne 'Before'){$v.machineHash='B'*64}
 if($fixture.scenario -eq 'boot_at_logoff' -and $Phase -eq 'AfterLogoff'){$v.bootUtc='2026-11-06T10:00:00Z'}
 if($fixture.scenario -eq 'no_advance' -and $Phase -eq 'AfterLogoff'){$v.worker.sequence=10}
 $v
}
function Get-PaytmInteractiveSession {
 $auth=if($Phase -eq 'Before' -or $fixture.scenario -eq 'same_logon'){'0000000000000001'}else{'0000000000000002'}
 @{userSidHash=$(if($fixture.scenario -eq 'different_user' -and $Phase -ne 'Before'){'B'*64}else{'A'*64});sessionId=1;authenticationId=$auth}
}
function Initialize-PaytmManagedApplication {
 if($fixture.scenario -eq 'unlocked' -and $Phase -ne 'Before'){throw 'APP_ROUTE_EXPECTED_LOCKED'}
 if($fixture.scenario -eq 'docker_stopped' -and $Phase -eq 'AfterBoot'){throw 'APP_ROUTE_CONTAINER_NOT_RUNNING'}
 $application.BeforeAccount='{"cash":100000}';$application.Id='container';$application.Before=@{Id='container';Image='image';State=@{StartedAt='unchanged'}}
 $application.BootId=if($Phase -eq 'AfterBoot' -and $fixture.scenario -ne 'same_app_boot'){'after-app'}else{'before-app'}
 if($fixture.scenario -eq 'account_drift' -and $Phase -ne 'Before'){$application.BeforeAccount='{"cash":99999}'}
 $application.Ready=$true;$application.Token='SECRET_NEVER_REPORT'
}
function Invoke-PaytmApplicationHead {
 if($fixture.scenario -eq 'tls_failure' -and $Phase -eq 'AfterBoot'){throw 'APP_ROUTE_TLS_EXPECTED'}
 $report.applicationRouteChecks.Add(@{passed=$true;expectedTls=$true})
}
function Invoke-PaytmApplicationHttp {
 if($fixture.scenario -eq 'final_lock_failure' -and $Phase -eq 'AfterBoot'){throw 'APP_ROUTE_FINAL_LOCK_FAILED'}
 @{state='LOCKED';bootId=$application.BootId}
}
function Get-PaytmApplicationContainer {$application.Before}
function Assert-PaytmWriterLocked {}
function Read-PaytmPaperAccount {$application.BeforeAccount}
function Start-ScheduledTask {throw 'SESSION_TEST_MUST_NOT_START_TASK'}
function Set-PaytmHostControl {throw 'SESSION_TEST_MUST_NOT_CHANGE_CONTROL'}
function Read-Result {Read-PaytmHostJson @(Get-ChildItem -LiteralPath $fixture.out -Filter '*.json')[0].FullName}
function Run-Phase($Name){
 $options=@{Phase=$Name;OutputDirectory=$fixture.out;NetworkReportPath=$fixture.network;TransportReportPath=$fixture.receipt}
 if($Name -ne 'Before'){$options.ConfirmNoManualGatewayStart=$fixture.scenario -ne 'no_confirmation'}
 if($Name -eq 'AfterLogoff'){$options.ConfirmSignedOut=$fixture.scenario -ne 'no_signout_confirmation'}
 if($Name -eq 'AfterBoot'){$options.ConfirmFullShutdown=$fixture.scenario -ne 'no_shutdown_confirmation'}
 & $fixture.script @options 6>$null
}
$scenarios=@('pass','same_logon','different_user','worker_restarted','machine_drift','boot_at_logoff','no_advance','install_drift','unlocked','account_drift','no_confirmation','no_signout_confirmation','no_boot','same_app_boot','docker_stopped','tls_failure','final_lock_failure','no_shutdown_confirmation','source_drift')
try{
 foreach($scenario in $scenarios){
  $base=Join-Path $temp $scenario;$root=Join-Path $base 'root';$out=Join-Path $base 'out';$source=Join-Path $base 'ops/windows'
  $null=New-Item -ItemType Directory -Path $root,$out,$source -Force
  $fixture=@{scenario=$scenario;root=$root;out=$out;network=(Join-Path $base 'network.json');receipt=(Join-Path $base 'transport.json');script=(Join-Path $source 'TestPaytmGatewaySession.ps1')}
  [IO.File]::WriteAllText($fixture.network,'{"input":"immutable-network"}');[IO.File]::WriteAllText($fixture.receipt,'{}')
  $inputHash=(Microsoft.PowerShell.Utility\Get-FileHash -LiteralPath $fixture.network).Hash
  foreach($name in @('PaytmGatewayAccount.ps1','PaytmGatewayKeyCustody.ps1','PaytmGatewayScheduledProbe.ps1','PaytmSupervisorHost.ps1','PaytmSupervisorInstallation.ps1','PaytmSupervisorTransport.ps1','PaytmApplicationRoute.ps1','PaytmManagedTransport.ps1','PaytmGatewayRestart.ps1','ReadPaytmInteractiveSession.ps1','PaytmGatewaySession.ps1')){[IO.File]::WriteAllText((Join-Path $source $name),'# fixture')}
  Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'TestPaytmGatewaySession.ps1') -Destination $fixture.script
  Run-Phase Before
  $baseline=Read-Result;Check ($baseline.status -ceq 'BASELINE_SAVED_AWAITING_SIGNOUT') 'BASELINE'
  $checkpoint=Join-Path $root 'session-checkpoint.json'
  $beforeHash=(Microsoft.PowerShell.Utility\Get-FileHash -LiteralPath $checkpoint).Hash
  if($scenario -eq 'source_drift'){Add-Content -LiteralPath (Join-Path $source 'PaytmGatewaySession.ps1') -Value '# drift'}
  $failed=$false;try{Run-Phase AfterLogoff}catch{$failed=$true}
  $logoffExpected=$scenario -in @('pass','no_boot','same_app_boot','docker_stopped','tls_failure','final_lock_failure','no_shutdown_confirmation')
  if($failed -ne (-not $logoffExpected)){Write-Host ($scenario+': '+((Read-Result)|ConvertTo-Json -Depth 10 -Compress))}
  Check ($failed -eq (-not $logoffExpected)) 'LOGOFF_OUTCOME'
  if(-not $logoffExpected){Check ((Microsoft.PowerShell.Utility\Get-FileHash -LiteralPath $checkpoint).Hash -ceq $beforeHash) 'FAILED_LOGOFF_PRESERVES_CHECKPOINT'}
  else{
   $v=Read-Result;Check ($v.status -ceq 'LOGOFF_PASSED_AWAITING_FULL_SHUTDOWN') 'LOGOFF_PASS'
   $logoffHash=(Microsoft.PowerShell.Utility\Get-FileHash -LiteralPath $checkpoint).Hash
   $failed=$false;try{Run-Phase AfterBoot}catch{$failed=$true}
   if($failed -ne ($scenario -ne 'pass')){Write-Host ($scenario+': '+((Read-Result)|ConvertTo-Json -Depth 10 -Compress))}
   Check ($failed -eq ($scenario -ne 'pass')) 'BOOT_OUTCOME'
   if($scenario -ne 'pass'){
    Check ((Microsoft.PowerShell.Utility\Get-FileHash -LiteralPath $checkpoint).Hash -ceq $logoffHash) 'FAILED_BOOT_PRESERVES_CHECKPOINT'
    $fixture.scenario='pass';Run-Phase AfterBoot
   }
   $v=Read-Result;Check ($v.status -ceq 'GATEWAY_LOGOFF_AND_FULL_BOOT_PASSED' -and $v.runId -ceq $baseline.runId -and $v.nextPhase -ceq 'Complete') 'FINAL_PASS_SAME_RUN'
   Check ($v.phaseProofs.Before.finalApplicationLockVerified -and $v.phaseProofs.AfterLogoff.finalApplicationLockVerified -and $v.phaseProofs.AfterBoot.finalApplicationLockVerified) 'THREE_PHASE_LOCKS_RETAINED'
   if($scenario -eq 'pass'){
    $doneHash=(Microsoft.PowerShell.Utility\Get-FileHash -LiteralPath $checkpoint).Hash
    $reportHash=(Microsoft.PowerShell.Utility\Get-FileHash -LiteralPath @(Get-ChildItem -LiteralPath $out -Filter '*.json')[0].FullName).Hash
    Run-Phase Before
    Check ((Microsoft.PowerShell.Utility\Get-FileHash -LiteralPath $checkpoint).Hash -ceq $doneHash) 'COMPLETED_BASELINE_CANNOT_RESET'
    Check ((Microsoft.PowerShell.Utility\Get-FileHash -LiteralPath @(Get-ChildItem -LiteralPath $out -Filter '*.json')[0].FullName).Hash -ceq $reportHash) 'COMPLETED_REPORT_PRESERVED'
   }
  }
  Check (@(Get-ChildItem -LiteralPath $out -Filter '*.json').Count -eq 1) 'ONE_REPORT'
  Check ((Microsoft.PowerShell.Utility\Get-FileHash -LiteralPath $fixture.network).Hash -ceq $inputHash) 'INPUT_BYTES_UNCHANGED'
  $v=Read-Result;$raw=$v|ConvertTo-Json -Depth 12
  Check (-not $raw.Contains('SECRET_NEVER_REPORT') -and -not $v.taskStartedByCollector -and -not $v.configurationChanged -and -not $v.ordersEnabled) 'SCOPE'
 }
 [pscustomobject]@{status='GATEWAY_SESSION_WORKFLOWS_PASSED';assertions=$count.checks;workflows=$scenarios.Count;realCheckpointFiles=$true;runtimeApisMocked=$true}|ConvertTo-Json
}finally{
 $resolved=[IO.Path]::GetFullPath($temp);$parent=[IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\')+'\'
 if(-not $resolved.StartsWith($parent,[StringComparison]::OrdinalIgnoreCase) -or [IO.Path]::GetFileName($resolved) -notmatch '^mb-session-test-[a-f0-9]{32}$'){throw 'UNSAFE_SESSION_TEST_CLEANUP'}
 Remove-Item -LiteralPath $resolved -Recurse -Force
}
