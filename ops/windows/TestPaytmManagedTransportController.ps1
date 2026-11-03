#Requires -Version 7.0
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'PaytmSupervisorHost.ps1')
. (Join-Path $PSScriptRoot 'PaytmManagedTransport.ps1')
. (Join-Path $PSScriptRoot 'PaytmApplicationRoute.ps1')
$temp=Join-Path ([IO.Path]::GetTempPath()) ('mb-managed-controller-'+[guid]::NewGuid().ToString('N'));$null=New-Item -ItemType Directory -Path $temp
$checks=0;$fixture=@{}
function Check($Value,$Name){if(-not $Value){throw "MANAGED_CONTROLLER_TEST_$Name"};$script:checks++}
function Assert-PaytmCustodyController {}
function Assert-PaytmAccountPath($Path){$Path}
function Set-PaytmAccountDirectoryAcl {}
function Import-Module {}
function Add-Type {}
function Get-PaytmAccountContract {[pscustomobject]@{root=$fixture.root}}
function Get-PaytmKeyContract {[pscustomobject]@{accountSid='fixture'}}
function Get-PaytmHostContract {[pscustomobject]@{root=$fixture.root;work=$fixture.work;name='fixture-task';executable='fixture-compiler'}}
function Get-PaytmReadinessProgress {[pscustomobject]@{id='G2';percent=60}}
function Get-FileHash {
 param($LiteralPath)
 if($LiteralPath -eq 'fixture-vps.json'){[pscustomobject]@{Hash='4E0EBE1E69C11EA11455DC5EA40B30C07C9644E314A9667ECC572C0A32B8A4D5'}}
 else{Microsoft.PowerShell.Utility\Get-FileHash -LiteralPath $LiteralPath}
}
function Read-PaytmRepairJson {[pscustomobject]@{server=@{}}}
function Assert-PaytmManagedProxyPassed {}
function Assert-PaytmScheduledPrerequisites {[pscustomobject]@{sid='fixture'}}
function Assert-PaytmTransportUpgrade {Read-PaytmHostJson (Join-Path $fixture.root 'manifest.json')}
function Wait-PaytmHost($Id,$Phase){[pscustomobject]@{phase=$Phase;instanceId='a'*32}}
function Set-PaytmHostControl($Id,$Mode){Write-PaytmHostJson (Join-Path $fixture.root 'control.json') @{version=1;installationId=$Id;mode=$Mode}}
function Initialize-PaytmManagedApplication {
 $application.Id='fixture-container';$application.Ready=$true;$application.Token='PRIVATE_TOKEN_NEVER_REPORT'
 $application.BeforeAccount='{"cash":100000}';$application.Before=[pscustomobject]@{Id=$application.Id;Image='fixture-image';State=@{StartedAt='unchanged'}};$application.BootId='fixture-boot'
}
function Start-TunnelProcess($Tool,$Arguments){$fixture.compileArgs=$Arguments;'fixture-compile-handle'}
function Complete-TunnelProcess {
 $stage=@(Get-ChildItem -LiteralPath $fixture.root -Directory -Filter 'transport-update-*')[0].FullName
 [IO.File]::WriteAllText((Join-Path $stage 'transport.dll'),'fixture-dll')
 [pscustomobject]@{StoppedByRunner=$false;ExitCode=$(if($fixture.case -eq 'compile_failure'){1}else{0});Stdout='';Stderr='fixture compile error'}
}
function Get-PaytmTransportListeners {@()}
function Assert-PaytmTransportListener {}
function Start-ScheduledTask {
 if($fixture.phase -eq 'STOPPED'){$fixture.instance++;$fixture.unsignedStop=$true}
}
function Get-PaytmOwnedHostTask($Id,[bool]$Enabled=$true){
 if($Enabled -eq $fixture.disabled){throw 'FIXTURE_TASK_ENABLED_MISMATCH'}
 [pscustomobject]@{State=if($fixture.stopped){'Disabled'}else{'Running'}}
}
function Disable-ScheduledTask {$fixture.disabled=$true}
function Stop-ScheduledTask {$fixture.stopped=$true}
function Wait-PaytmManagedHost($Id,$Phase,$PreviousInstance='', $PreviousChild=0){
 $fixture.sequence++;$fixture.phase=$Phase
 if($Phase -eq 'TRANSPORT_READY' -and $fixture.lastReadyPhase -ne 'TRANSPORT_READY'){$fixture.child++};$fixture.lastReadyPhase=$Phase
 if($PreviousChild){$fixture.child++}
 $value=[pscustomobject]@{installationId=$Id;phase=$Phase;instanceId=('{0:x32}' -f $fixture.instance);processId=(100+$fixture.instance);sequence=$fixture.sequence;elapsedSeconds=$fixture.sequence;
 childProcessId=$(if($Phase -eq 'TRANSPORT_READY'){$fixture.child}else{0});networkContacted=($Phase -ne 'STOPPED');signingVerified=($Phase -ne 'STOPPED');transportState=@{attempts=$fixture.child}}
 Write-PaytmHostJson (Join-Path $fixture.work 'status.json') $value
 $value
}
function Stop-PaytmReviewedChild {$fixture.kills++}
function Invoke-PaytmApplicationHttp($Command){
 if($Command -eq 'arm'){$fixture.app='ARMED'}
 if($Command -eq 'lock'){$fixture.app='LOCKED'}
 $status=$fixture.app;$tls=$false;$http=0;$failure='NONE'
 if($Command -eq 'head' -and $fixture.app -eq 'ARMED'){
  $mode=(Read-PaytmHostJson (Join-Path $fixture.root 'transport-control.json')).mode
  if($mode -eq 'DISABLED' -or $fixture.case -eq 'route_failure'){$status='TRANSPORT_FAILED';$fixture.app='LOCKED';$failure='ConnectException'}
  else{$status='TLS_RESPONSE';$tls=$true;$http=503}
 }
 [pscustomobject]@{bootId='fixture-boot';state=$fixture.app;status=$status;tlsVerified=$tls;httpStatus=$http;failureType=$failure}
}
function Assert-PaytmWriterLocked {}
function Get-PaytmApplicationContainer {$application.Before}
function Read-PaytmPaperAccount {if($fixture.case -eq 'account_changed'){'{"cash":99999}'}else{$application.BeforeAccount}}
try{
 foreach($caseName in @('success','compile_failure','route_failure','account_changed')){
  $caseRoot=Join-Path $temp $caseName;$source=Join-Path $caseRoot 'ops\windows';$null=New-Item -ItemType Directory -Path $source -Force
  $fixture=@{case=$caseName;root=(Join-Path $caseRoot 'host');work=(Join-Path $caseRoot 'work');phase='LOCKED';instance=1;sequence=0;child=200;lastReadyPhase='';app='LOCKED';kills=0;disabled=$false;stopped=$false}
  $null=New-Item -ItemType Directory -Path $fixture.root,$fixture.work
  foreach($name in @('runner.ps1','host.ps1','native.dll','instance.lock')){[IO.File]::WriteAllText((Join-Path $(if($name -eq 'instance.lock'){$fixture.work}else{$fixture.root}) $name),'old fixture')}
  Write-PaytmHostJson (Join-Path $fixture.root 'manifest.json') @{version=1;installationId='ea8b91471cf048aa97a0f6b939b355c7';hashes=@{'runner.ps1'='old';'host.ps1'='old';'native.dll'='old'}}
  Write-PaytmHostJson (Join-Path $fixture.root 'control.json') @{version=1;installationId='ea8b91471cf048aa97a0f6b939b355c7';mode='LOCKED'}
  foreach($name in @('PaytmGatewayAccount.ps1','PaytmGatewayAccountRepair.ps1','PaytmGatewayKeyCustody.ps1','PaytmGatewayScheduledProbe.ps1','PaytmTunnelVerification.ps1','PaytmSupervisorHost.ps1','PaytmSupervisorInstallation.ps1','PaytmSupervisorTransport.ps1','PaytmManagedProxy.ps1','PaytmApplicationRoute.ps1','PaytmManagedTransport.ps1','PaytmTransportNative.cs','RunPaytmGatewaySupervisor.ps1','PaytmGatewaySupervisor.ps1')){[IO.File]::WriteAllText((Join-Path $source $name),'# fixture')}
  Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'InstallPaytmManagedTransport.ps1') -Destination (Join-Path $source 'InstallPaytmManagedTransport.ps1')
  $out=Join-Path $caseRoot 'out';$failed=$false
  try{& (Join-Path $source 'InstallPaytmManagedTransport.ps1') -VpsEvidencePath fixture-vps.json -OutputDirectory $out 6>$null}catch{$failed=$true}
  $files=@(Get-ChildItem -LiteralPath $out -Filter '*.json');Check ($files.Count -eq 1) 'ONE_REPORT'
  $raw=[IO.File]::ReadAllText($files[0].FullName);$result=$raw|ConvertFrom-Json
  Check (-not $raw.Contains('PRIVATE_TOKEN_NEVER_REPORT')) 'NO_TOKEN_LEAK'
  Check (-not $result.ordersEnabled -and -not $result.vpsChanged -and -not $result.taskReRegistered -and -not $result.keyImported) 'SCOPE'
  if($caseName -eq 'success'){
   Check (-not $failed -and $result.status -eq 'MANAGED_WINDOWS_TRANSPORT_AND_APPLICATION_ROUTE_PASSED_BOOT_PENDING') 'SUCCESS'
   Check ($result.duplicateStartPassed -and $result.disabledRoutePassed -and $result.childRecoveryPassed -and $result.persistentStopPassed -and $result.restartPassed) 'LIFECYCLE'
   Check ($result.applicationRouteChecks.Count -eq 4 -and $result.accountPreserved -and $result.finalApplicationLockVerified) 'APPLICATION'
   Check ($fixture.kills -eq 1 -and -not $fixture.disabled) 'ONE_CHILD_FAULT'
   Check ((Read-PaytmHostJson (Join-Path $fixture.root 'manifest.json')).transportVersion -eq 1) 'UPGRADE_FILES'
  }else{
   Check ($failed -and $result.status -eq 'REVIEW_REQUIRED') 'FAIL_CLOSED'
   if($caseName -eq 'compile_failure'){Check (-not $fixture.disabled -and -not $result.upgradeApplied -and (Read-PaytmHostJson (Join-Path $fixture.root 'control.json')).mode -eq 'LOCKED') 'PREMUTATION_FAILURE'}
   else{Check ($fixture.disabled -and $fixture.stopped -and $result.failureStopVerified -and (Read-PaytmHostJson (Join-Path $fixture.root 'control.json')).mode -eq 'STOP') 'PERSISTENT_FAILURE_STOP'}
  }
 }
 [pscustomobject]@{status='MANAGED_TRANSPORT_CONTROLLER_PASSED';assertions=$checks;workflows=4;runtimeApisMocked=$true;realBackupAndReplacement=$true}|ConvertTo-Json
}finally{
 $resolved=[IO.Path]::GetFullPath($temp);$base=[IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\')+'\'
 if(-not $resolved.StartsWith($base,[StringComparison]::OrdinalIgnoreCase) -or [IO.Path]::GetFileName($resolved) -notmatch '^mb-managed-controller-[a-f0-9]{32}$'){throw 'UNSAFE_FIXTURE_CLEANUP'}
 Remove-Item -LiteralPath $resolved -Recurse -Force
}
