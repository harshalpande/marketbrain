#Requires -Version 7.0
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'PaytmSupervisorHost.ps1')
. (Join-Path $PSScriptRoot 'PaytmManagedTransport.ps1')
. (Join-Path $PSScriptRoot 'PaytmGatewayRestart.ps1')
. (Join-Path $PSScriptRoot 'PaytmGatewaySession.ps1')
. (Join-Path $PSScriptRoot 'PaytmGatewayFailureEvidence.ps1')
# Load the actual route subprocess/checkpoint boundary without its unrelated imports.
$tokens=$null;$parseErrors=$null
$ast=[Management.Automation.Language.Parser]::ParseFile((Join-Path $PSScriptRoot 'PaytmApplicationRoute.ps1'),[ref]$tokens,[ref]$parseErrors)
$boundary=$ast.Find({param($node) $node -is [Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq 'Invoke-PaytmPrivateDocker'},$true)
. ([scriptblock]::Create($boundary.Extent.Text))
function Invoke-PaperRuntimeProcess { @{exitCode=0;stdout='PRIVATE_NATIVE_STDOUT';stderr='';elapsedSeconds=0} }
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
function Get-PaytmHostContract {@{root=$fixture.root;work=$fixture.root;name='fixture-task';executable='fixture-exe'}}
function Get-PaytmProbeTask {@{State='Ready';Settings=@{Enabled=$true}}}
function Assert-PaytmHostTask {}
function Get-ScheduledTaskInfo {@{LastTaskResult=1;LastRunTime=[DateTime]::UtcNow}}
function Start-Sleep {}
function Get-PaytmAccountContract {@{root=$fixture.root}}
function Get-PaytmKeyContract {@{accountSid='fixture'}}
function Get-FileHash($LiteralPath){
 if($LiteralPath -eq $fixture.network){@{Hash='860F63E79D86A6460EA87C2C492B84FEA342FD919E85019E6C26D2B8CA5C3773'}}
 elseif($LiteralPath -eq $fixture.receipt){@{Hash='078A34DB0A46951EB98C5A08063F9FC76DB6EC75C175A3572CEE3D65DA4FAB4B'}}
 else{Microsoft.PowerShell.Utility\Get-FileHash -LiteralPath $LiteralPath}
}
function Assert-PaytmTransportAcceptance {}
function Assert-PaytmInstalledTransport {
 if($fixture.scenario -eq 'blocked_baseline'){throw 'STARTUP_WORKER_FAILURE_PRESENT'}
 if($fixture.scenario -like 'inspect_*'){throw 'INSPECTION_MUST_NOT_VALIDATE_INSTALLATION'}
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
 $application.Docker='fixture-docker'
 $null=Invoke-PaytmPrivateDocker @('context','show') 'SESSION_ROUTE_CHECKPOINT'
 if($fixture.scenario -in @('blocked_baseline','inspect_absent','inspect_existing')){throw 'INSPECTION_MUST_NOT_ACCESS_APPLICATION'}
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
$scenarios=@('pass','missing_callback','same_logon','different_user','worker_restarted','machine_drift','boot_at_logoff','no_advance','install_drift','unlocked','account_drift','no_confirmation','no_signout_confirmation','no_boot','same_app_boot','docker_stopped','tls_failure','final_lock_failure','no_shutdown_confirmation','source_drift','blocked_baseline','inspect_absent','inspect_existing')
try{
 $largeReport=Join-Path $temp 'report-size.json'
 Write-PaytmSessionReport $largeReport @{payload=('x'*20000)}
 Check ((Read-PaytmHostJson $largeReport 65536).payload.Length -eq 20000) 'COMBINED_DIAGNOSTICS_OVER_16_KIB'
 $largeHash=(Microsoft.PowerShell.Utility\Get-FileHash -LiteralPath $largeReport).Hash
 $failed=$false;try{Write-PaytmSessionReport $largeReport @{payload=('x'*65536)}}catch{$failed=$true}
 Check ($failed -and (Microsoft.PowerShell.Utility\Get-FileHash -LiteralPath $largeReport).Hash -ceq $largeHash) 'OVERSIZE_PRESERVES_PRIOR_REPORT'
 Check (@(Get-ChildItem -LiteralPath $temp -Filter '*.tmp').Count -eq 0) 'REPORT_TEMP_CLEANUP'
 foreach($scenario in $scenarios){
  $base=Join-Path $temp $scenario;$root=Join-Path $base 'root';$out=Join-Path $base 'out';$source=Join-Path $base 'ops/windows'
  $null=New-Item -ItemType Directory -Path $root,$out,$source -Force
  $fixture=@{scenario=$scenario;root=$root;out=$out;network=(Join-Path $base 'network.json');receipt=(Join-Path $base 'transport.json');script=(Join-Path $source 'TestPaytmGatewaySession.ps1')}
  [IO.File]::WriteAllText($fixture.network,'{"input":"immutable-network"}');[IO.File]::WriteAllText($fixture.receipt,'{}')
  $inputHash=(Microsoft.PowerShell.Utility\Get-FileHash -LiteralPath $fixture.network).Hash
  foreach($name in @('PaytmGatewayAccount.ps1','PaytmGatewayKeyCustody.ps1','PaytmGatewayScheduledProbe.ps1','PaytmSupervisorHost.ps1','PaytmSupervisorInstallation.ps1','PaytmSupervisorTransport.ps1','PaytmApplicationRoute.ps1','PaytmManagedTransport.ps1','PaytmGatewayRestart.ps1','ReadPaytmInteractiveSession.ps1','PaytmGatewaySession.ps1','PaytmGatewayFailureEvidence.ps1')){[IO.File]::WriteAllText((Join-Path $source $name),'# fixture')}
  Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'TestPaytmGatewaySession.ps1') -Destination $fixture.script
  if($scenario -in @('blocked_baseline','inspect_absent','inspect_existing')){
   $checkpoint=Join-Path $root 'session-checkpoint.json'
   if($scenario -eq 'inspect_existing'){[IO.File]::WriteAllText($checkpoint,'EXISTING_CHECKPOINT_NOT_PARSED_OR_REPLACED')}
   foreach($name in @('blocked.json','startup-failure.json','status.json','control.json','transport-control.json')){
    Write-PaytmHostJson (Join-Path $root $name) @{version=1;failure='TRANSPORT_UNKNOWN';stage='OBSERVATION_LOOP';phase='BLOCKED';instanceId=('d'*32);sequence=5;mode='LOCKED';privateText='SECRET_NEVER_REPORT';lastSshObservation=@{version=1;exited=$true;stderrDrained=$true;authenticated=$false;reason='NETWORK_UNAVAILABLE';stderrCharacters=245;stderrSha256=('A'*64);tags=@('TCP_CONNECT_DENIED')}}
   }
   $hashes=@{};foreach($file in Get-ChildItem -LiteralPath $root -Filter '*.json'){$hashes[$file.FullName]=(Microsoft.PowerShell.Utility\Get-FileHash -LiteralPath $file.FullName).Hash}
   if($scenario -eq 'blocked_baseline'){
    $failed=$false;try{Run-Phase Before}catch{$failed=$true}
    Check $failed 'BLOCKED_BASELINE_REJECTED'
   }else{
    # Inspection must not need any old receipt or a readable session checkpoint.
    & $fixture.script -InspectOnly -OutputDirectory $out -NetworkReportPath (Join-Path $base 'absent-network.json') -TransportReportPath (Join-Path $base 'absent-transport.json') 6>$null
   }
   $v=Read-Result
   Check ($v.workerDiagnostics.files.'startup-failure.json'.value.failure -eq 'TRANSPORT_UNKNOWN') 'REAL_MARKER_CAUSE_CAPTURED'
   Check ($v.workerDiagnostics.files.'status.json'.value.lastSshObservation.stderrSha256 -ceq ('A'*64)) 'NATIVE_DIAGNOSTIC_CAPTURED'
   Check ($v.workerDiagnostics.readOnly -and -not $v.workerDiagnostics.currentHealthEstablished -and -not $v.accountPreserved -and -not $v.finalApplicationLockVerified) 'UNOBSERVED_HEALTH_NOT_INFERRED'
   Check ($v.applicationCommands.Count -eq 0 -and $v.applicationObservations.Count -eq 0 -and -not $v.taskStartedByCollector -and -not $v.configurationChanged) 'READ_ONLY_SCOPE'
   if($scenario -eq 'blocked_baseline'){Check ($v.failure -eq 'STARTUP_WORKER_FAILURE_PRESENT' -and $v.status -eq 'REVIEW_REQUIRED') 'ORIGINAL_ERROR_PRESERVED'}
   else{Check ($v.status -eq 'SESSION_WORKER_DIAGNOSTICS_CAPTURED' -and $v.inspectionOnly -and $v.checkpointPresent -eq ($scenario -eq 'inspect_existing')) 'INSPECTION_COMPLETE'}
   foreach($file in $hashes.Keys){Check ((Microsoft.PowerShell.Utility\Get-FileHash -LiteralPath $file).Hash -ceq $hashes[$file]) 'STATE_BYTES_UNCHANGED'}
   Check ((Test-Path -LiteralPath $checkpoint) -eq ($scenario -eq 'inspect_existing')) 'NO_NEW_BASELINE'
   Check (-not ((Read-Result)|ConvertTo-Json -Depth 12).Contains('SECRET_NEVER_REPORT')) 'DIAGNOSTIC_REDACTION'
   Check (@(Get-ChildItem -LiteralPath $out -Filter '*.json').Count -eq 1) 'ONE_DIAGNOSTIC_REPORT'
   continue
  }
  if($scenario -eq 'missing_callback'){
   $old=[IO.File]::ReadAllText($fixture.script).Replace('function Save-Report {Save-SessionReport}','')
   [IO.File]::WriteAllText($fixture.script,$old)
   $failed=$false;try{Run-Phase Before}catch{$failed=$true}
   $v=Read-Result
   Check ($failed -and $v.failureDetails.type -ceq 'CommandNotFoundException') 'MISSING_ROUTE_CALLBACK_REPRODUCED'
   Check ($v.status -ceq 'REVIEW_REQUIRED' -and -not (Test-Path -LiteralPath (Join-Path $root 'session-checkpoint.json'))) 'NO_BASELINE_ON_CALLBACK_FAILURE'
   Check ($v.applicationCommands.Count -eq 1 -and $v.applicationCommands[0].phase -ceq 'SESSION_ROUTE_CHECKPOINT') 'REAL_ROUTE_BOUNDARY_REACHED'
   continue
  }
  Run-Phase Before
  $baseline=Read-Result;Check ($baseline.status -ceq 'BASELINE_SAVED_AWAITING_SIGNOUT') 'BASELINE'
  Check ($baseline.applicationCommands.Count -eq 1 -and $baseline.applicationCommands[0].phase -ceq 'SESSION_ROUTE_CHECKPOINT') 'BASELINE_REAL_ROUTE_CHECKPOINT'
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
   Check ($v.applicationCommands.Count -eq 1 -and $v.applicationCommands[0].phase -ceq 'SESSION_ROUTE_CHECKPOINT') 'FINAL_REAL_ROUTE_CHECKPOINT'
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
  Check (-not $raw.Contains('SECRET_NEVER_REPORT') -and -not $raw.Contains('PRIVATE_NATIVE_STDOUT') -and -not $v.taskStartedByCollector -and -not $v.configurationChanged -and -not $v.ordersEnabled) 'SCOPE'
 }
 [pscustomobject]@{status='GATEWAY_SESSION_WORKFLOWS_PASSED';assertions=$count.checks;workflows=$scenarios.Count;realCheckpointFiles=$true;runtimeApisMocked=$true}|ConvertTo-Json
}finally{
 $resolved=[IO.Path]::GetFullPath($temp);$parent=[IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\')+'\'
 if(-not $resolved.StartsWith($parent,[StringComparison]::OrdinalIgnoreCase) -or [IO.Path]::GetFileName($resolved) -notmatch '^mb-session-test-[a-f0-9]{32}$'){throw 'UNSAFE_SESSION_TEST_CLEANUP'}
 Remove-Item -LiteralPath $resolved -Recurse -Force
}
