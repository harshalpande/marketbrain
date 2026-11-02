#Requires -Version 7.0
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'PaytmManagedProxy.ps1')
$fixture=Join-Path ([IO.Path]::GetTempPath()) ('marketbrain-managed-controller-'+[guid]::NewGuid().ToString('N'))
$null=New-Item -ItemType Directory -Path (Join-Path $fixture 'windows'),(Join-Path $fixture 'linux') -Force
$controller=Join-Path $fixture 'windows\InstallPaytmManagedProxy.ps1'
Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'InstallPaytmManagedProxy.ps1') -Destination $controller
foreach($name in @('PaytmGatewayAccount.ps1','PaytmGatewayAccountRepair.ps1','PaytmGatewayKeyCustody.ps1','PaytmGatewayScheduledProbe.ps1','PaytmSupervisorHost.ps1','PaytmSupervisorInstallation.ps1','PaytmTunnelVerification.ps1','PaytmManagedProxy.ps1')){[IO.File]::WriteAllText((Join-Path $fixture ('windows\'+$name)),'# fixture dependency; runtime APIs substituted')}
foreach($name in @('InstallPaytmTunnelIdentity.sh','StagePaytmLoopbackProxy.sh','ManagePaytmProxyLifecycle.sh')){[IO.File]::WriteAllText((Join-Path $fixture ('linux\'+$name)),'# fixture source')}
$receiptPath=Join-Path $fixture 'receipt.json';[IO.File]::WriteAllText($receiptPath,'{}')
$script:checks=0
$managedFixture=@{case=$null;waits=0;clipboard=$null;run=$null}
function Check([bool]$Value,[string]$Name){if(-not $Value){throw "CONTROLLER_TEST_$Name"};$script:checks++}
function Assert-PaytmAccountPath($Path){$Path}
function Assert-PaytmCustodyController {}
function Get-FileHash {
 param([string]$LiteralPath)
 if($LiteralPath -eq $receiptPath){[pscustomobject]@{Hash=if($managedFixture.case -eq 'bad_receipt'){'BAD'}else{'865A6286E03385CC4BAE5E484DE03A7EF658FFF020BE6522192CE8E044675E2A'}}}
 else{Microsoft.PowerShell.Utility\Get-FileHash -LiteralPath $LiteralPath}
}
function Read-PaytmRepairJson($Path,$Limit){[pscustomobject]@{installationId='fixture-installation';final=[pscustomobject]@{state='LOCKED'}}}
function Assert-PaytmHostStatus($Value,$Id){if($Value.state -ne 'LOCKED'){throw 'HOST_STATUS_INVALID'}}
function Import-Module {param($Name,$ErrorAction) if($Name -ne 'ScheduledTasks'){throw 'UNEXPECTED_IMPORT'}}
function Wait-PaytmHost($Id,$State){$managedFixture.waits++;[pscustomobject]@{state='LOCKED';sequence=$managedFixture.waits;instanceId=if($managedFixture.case -eq 'host_changed' -and $managedFixture.waits -eq 2){'new'}else{'same'}}}
function Assert-PaytmHostAdvance($First,$Second){if($First.instanceId -ne $Second.instanceId -or $Second.sequence -le $First.sequence){throw 'HOST_INSTANCE_CHANGED'}}
function Get-PaytmReadinessProgress {[pscustomobject]@{id='G2';percent=60}}
function Get-PaytmManagedProxyPayload($RunId){$managedFixture.run=$RunId;'fixture command'}
function Set-Clipboard {param($Value) $managedFixture.clipboard=$Value}
function Read-Host {param($Prompt) if($managedFixture.case -eq 'wrong_confirmation'){'OTHER'}else{'REPORT-COPIED'}}
function Get-Clipboard {
 param([switch]$Raw)
 $id=if($managedFixture.case -eq 'wrong_run'){'b'*32}else{$managedFixture.run}
 $value=[ordered]@{version=1;runId=$id;success=$true;stage='COMPLETE';exitCode=0;failureLine=0;elapsedSeconds=45;baselineVerified=$true;backupVerified=$true;effectivePolicyVerified=$true;crashRestartVerified=$true;disableVerified=$true;conditionBlocksStart=$true;tlsVerified=$true;httpStatus=503;denialsVerified=$true;bootEnabled=$true;finalRunning=$true;cleanupPassed=$true;credentialsUsed=$false;ordersEnabled=$false}
 if($managedFixture.case -eq 'server_failure'){$value.success=$false;$value.exitCode=1;$value.bootEnabled=$false;$value.finalRunning=$false}
 "BEGIN_MANAGED_REPORT_$id`n"+($value|ConvertTo-Json -Compress)+"`nEND_MANAGED_REPORT_$id"
}
try{
 foreach($caseName in @('success','bad_receipt','server_failure','wrong_run','wrong_confirmation','host_changed')){
  $managedFixture.case=$caseName
  $managedFixture.waits=0;$managedFixture.clipboard=$null;$managedFixture.run=$null;$failed=$false
  $output=Join-Path $fixture $managedFixture.case
  try{& $controller -SupervisorReportPath $receiptPath -OutputDirectory $output 6>$null}catch{$failed=$true}
  $files=@(Get-ChildItem -LiteralPath $output -Filter '*.json');Check ($files.Count -eq 1) 'ONE_REPORT'
  $r=Get-Content -LiteralPath $files[0].FullName -Raw|ConvertFrom-Json
  Check (-not $r.windowsTaskChanged -and -not $r.windowsTunnelStarted -and -not $r.credentialsUsed -and -not $r.ordersEnabled) 'SCOPE'
  if($managedFixture.case -eq 'success'){
   Check (-not $failed -and $r.status -eq 'VPS_MANAGED_PROXY_PASSED_WINDOWS_TRANSPORT_PENDING') 'SUCCESS'
   Check ($r.lockedAfter.sequence -gt $r.lockedBefore.sequence -and $managedFixture.waits -eq 2) 'HOST_BEFORE_AFTER'
  }else{
   Check ($failed -and $r.status -eq 'REVIEW_REQUIRED' -and $null -ne $r.failureDetails) 'FAILURE_EVIDENCE'
   if($managedFixture.case -eq 'bad_receipt'){Check ($null -eq $managedFixture.clipboard -and $managedFixture.waits -eq 0) 'PREMUTATION_GUARD'}
   if($managedFixture.case -eq 'server_failure'){Check ($null -ne $r.server -and -not $r.server.success -and $managedFixture.waits -eq 1) 'FAILED_SERVER_PRESERVED'}
   if($managedFixture.case -eq 'host_changed'){Check ($r.server.success -and $r.failure -eq 'HOST_INSTANCE_CHANGED') 'REMOTE_SUCCESS_LOCAL_FAILURE'}
  }
 }
 [pscustomobject]@{status='MANAGED_PROXY_CONTROLLER_PASSED';assertions=$script:checks;workflows=6;runtimeApisMocked=$true;networkContacted=$false}|ConvertTo-Json
}finally{
 $resolved=[IO.Path]::GetFullPath($fixture)
 $temp=[IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\')+'\'
 if(-not $resolved.StartsWith($temp,[StringComparison]::OrdinalIgnoreCase) -or [IO.Path]::GetFileName($resolved) -notmatch '^marketbrain-managed-controller-[a-f0-9]{32}$'){throw 'UNSAFE_FIXTURE_CLEANUP'}
 Remove-Item -LiteralPath $resolved -Recurse -Force
}
