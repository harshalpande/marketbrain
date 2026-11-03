#Requires -Version 7.0
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'PaytmSupervisorHost.ps1')
. (Join-Path $PSScriptRoot 'PaytmGatewayRestart.ps1')
$tokens=$null;$errors=$null
$ast=[Management.Automation.Language.Parser]::ParseFile((Join-Path $PSScriptRoot 'TestPaytmGatewayRestartRules.ps1'),[ref]$tokens,[ref]$errors)
foreach($f in $ast.FindAll({param($a)$a -is [Management.Automation.Language.FunctionDefinitionAst] -and $a.Name -in @('Worker','Observation')},$true)){. ([scriptblock]::Create($f.Extent.Text))}
$temp=Join-Path ([IO.Path]::GetTempPath()) ('mb-restart-test-'+[guid]::NewGuid().ToString('N'));$null=New-Item -ItemType Directory -Path $temp
$checks=0;$fixture=@{}
function Check($Ok,$Name){if(-not $Ok){throw "RESTART_WORKFLOW_$Name"};$script:checks++}
function Assert-PaytmCustodyController {}
function Assert-PaytmAccountPath($Path){$Path}
function Assert-PaytmAccountAcl {}
function Get-Acl {}
function Import-Module {}
function Get-PaytmHostContract {[pscustomobject]@{root=$fixture.root;work=$fixture.root}}
function Get-PaytmKeyContract {@{accountSid='fixture'}}
function Get-PaytmAccountContract {@{root=$fixture.root}}
function Get-FileHash($LiteralPath){if($LiteralPath -eq $fixture.receipt){@{Hash='078A34DB0A46951EB98C5A08063F9FC76DB6EC75C175A3572CEE3D65DA4FAB4B'}}else{Microsoft.PowerShell.Utility\Get-FileHash -LiteralPath $LiteralPath}}
function Assert-PaytmTransportAcceptance {}
function Assert-PaytmInstalledTransport {[pscustomobject]@{installationId='fixture';hashes=@{'runner.ps1'='1';'host.ps1'='2';'native.dll'='3';'gateway.ps1'='4';'transport.ps1'='5';'transport.dll'='6'}}}
function Get-PaytmRestartObservation {
 if($Phase -eq 'After' -and $fixture.scenario -ne 'no_restart'){Observation $true}else{Observation}
}
function Initialize-PaytmManagedApplication {
 if($fixture.scenario -eq 'unlocked' -and $Phase -eq 'After'){throw 'APP_ROUTE_EXPECTED_LOCKED'}
 $application.BeforeAccount='{"cash":100000}';$application.Id='fixture-container';$application.Before=@{Id=$application.Id;Image='fixture-image';State=@{StartedAt='unchanged'}}
 $application.BootId=if($Phase -eq 'Before'){'before-app'}else{'after-app'}
 if($Phase -eq 'After' -and $fixture.scenario -eq 'account_drift'){$application.BeforeAccount='{"cash":99999}'}
 if($Phase -eq 'After' -and $fixture.scenario -eq 'image_drift'){$application.Before.Image='different-image'}
 $application.Ready=$true;$application.Token='PRIVATE_TOKEN_NEVER_REPORT'
}
function Invoke-PaytmApplicationHead {$report.applicationRouteChecks.Add(@{passed=$true})}
function Invoke-PaytmApplicationHttp {@{state='LOCKED';bootId=$application.BootId}}
function Get-PaytmApplicationContainer {
 if($fixture.scenario -eq 'mid_phase_restart' -and $Phase -eq 'After'){@{Id=$application.Id;Image=$application.Before.Image;State=@{StartedAt='changed'}}}
 else{$application.Before}
}
function Assert-PaytmWriterLocked {}
function Read-PaytmPaperAccount {$application.BeforeAccount}
function Start-ScheduledTask {throw 'TEST_COLLECTOR_MUST_NOT_START_TASK'}
function Set-PaytmHostControl {throw 'TEST_COLLECTOR_MUST_NOT_CHANGE_CONTROL'}
try{
 foreach($scenario in @('pass','no_restart','account_drift','image_drift','unlocked','missing_confirmation','mid_phase_restart')){
  $base=Join-Path $temp $scenario;$root=Join-Path $base 'host';$out=Join-Path $base 'out';$source=Join-Path $base 'ops/windows';$null=New-Item -ItemType Directory -Path $root,$out,$source -Force
  $fixture=@{root=$root;out=$out;scenario=$scenario;receipt=(Join-Path $base 'receipt.json')};[IO.File]::WriteAllText($fixture.receipt,'{}')
  foreach($name in @('PaytmGatewayAccount.ps1','PaytmGatewayKeyCustody.ps1','PaytmGatewayScheduledProbe.ps1','PaytmSupervisorHost.ps1','PaytmSupervisorInstallation.ps1','PaytmSupervisorTransport.ps1','PaytmApplicationRoute.ps1','PaytmManagedTransport.ps1','PaytmGatewayRestart.ps1')){[IO.File]::WriteAllText((Join-Path $source $name),'# fixture')}
  $scriptPath=Join-Path $source 'TestPaytmGatewayRestart.ps1'
  $body=[IO.File]::ReadAllText((Join-Path $PSScriptRoot 'TestPaytmGatewayRestart.ps1')).Replace("'C:\MarketBrainData\Review'",("'"+$out.Replace("'","''")+"'"))
  [IO.File]::WriteAllText($scriptPath,$body)
  & $scriptPath -Phase Before -TransportReportPath $fixture.receipt 6>$null
  $file=@(Get-ChildItem -LiteralPath $out -Filter '*.json');Check ($file.Count -eq 1) 'ONE_BASELINE_REPORT'
  $before=Read-PaytmHostJson $file[0].FullName;Check ($before.status -eq 'BASELINE_SAVED_AWAITING_WINDOWS_RESTART') 'BEFORE_SUCCESS'
  $failed=$false
  try{& $scriptPath -Phase After -ConfirmNoManualGatewayStart:($scenario -ne 'missing_confirmation') -TransportReportPath $fixture.receipt 6>$null}catch{$failed=$true}
  $after=Read-PaytmHostJson $file[0].FullName
  Check ($failed -eq ($scenario -ne 'pass')) 'EXPECTED_OUTCOME'
  $state=Read-PaytmHostJson (Join-Path $root 'restart-checkpoint.json')
  if($scenario -eq 'pass'){
   Check ($after.status -eq 'WINDOWS_RESTART_TRANSPORT_AND_APPLICATION_ROUTE_PASSED' -and $state.completed -and $after.applicationRouteChecks.Count -eq 1) 'AFTER_SUCCESS'
   Check ($state.after.worker.instanceId -ne $state.before.worker.instanceId) 'PROTECTED_AFTER_PROOF'
  }else{Check ($after.status -eq 'REVIEW_REQUIRED' -and -not $state.completed) 'FAILED_AFTER_RETRYABLE_WITHOUT_BASELINE_REPLAY'}
  Check (@(Get-ChildItem -LiteralPath $out -Filter '*.json').Count -eq 1) 'SAME_REPORT'
  $raw=[IO.File]::ReadAllText($file[0].FullName)
  Check (-not $raw.Contains('PRIVATE_TOKEN_NEVER_REPORT') -and -not $after.taskStartedByCollector -and -not $after.configurationChanged -and -not $after.ordersEnabled) 'SCOPE'
 }
 [pscustomobject]@{status='GATEWAY_RESTART_WORKFLOWS_PASSED';assertions=$checks;twoPhaseWorkflows=7;runtimeApisMocked=$true;realAtomicCheckpointFiles=$true}|ConvertTo-Json
}finally{
 $resolved=[IO.Path]::GetFullPath($temp);$base=[IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\')+'\'
 if(-not $resolved.StartsWith($base,[StringComparison]::OrdinalIgnoreCase) -or [IO.Path]::GetFileName($resolved) -notmatch '^mb-restart-test-[a-f0-9]{32}$'){throw 'UNSAFE_FIXTURE_CLEANUP'}
 Remove-Item -LiteralPath $resolved -Recurse -Force
}
