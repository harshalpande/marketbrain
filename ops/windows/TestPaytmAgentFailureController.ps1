#Requires -Version 7.0
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'PaytmSupervisorHost.ps1')
. (Join-Path $PSScriptRoot 'PaytmGatewaySession.ps1')
Set-StrictMode -Version Latest
$tmp=Join-Path ([IO.Path]::GetTempPath()) ('mb-agent-controller-'+[guid]::NewGuid().ToString('N'))
$global:mbAgentFixture=@{};$checks=@{count=0}
function Check($Ok,$Name){if(-not $Ok){throw "AGENT_CONTROLLER_$Name"};$checks.count++}
function Assert-PaytmAccountPath($Path){$Path}
function Assert-PaytmCustodyController {}
function Import-Module {}
function Get-PaytmHostContract {@{root=$global:mbAgentFixture.root}}
function Get-FileHash($LiteralPath){
 if($LiteralPath -eq $global:mbAgentFixture.receipt){@{Hash=$(if($global:mbAgentFixture.case -eq 'wrongReceipt'){'0'*64}else{'72B5F4016330C6B4D45AC917DDA533CE6E329B2BB3A7B86BE91E562B84ADEBCA'})}}
 else{Microsoft.PowerShell.Utility\Get-FileHash -LiteralPath $LiteralPath}
}
function Get-PaytmWorkerFailureEvidence {@{readOnly=$true;files=@{}}}
function Invoke-PaperRuntimeProcess($Executable,$Arguments,$Directory,$LimitSeconds){
 Check ($Executable -eq 'C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe' -and $LimitSeconds -eq 90 -and $Arguments[3] -eq '-EncodedCommand') 'BOUNDED_PS5'
 if($global:mbAgentFixture.case -eq 'timeout'){throw 'RUNTIME_PROCESS_TIMEOUT'}
 if($global:mbAgentFixture.case -eq 'exitFailure'){return @{exitCode=1;elapsedSeconds=1;stdout='';stderr='PRIVATE_STDERR'}}
 if($global:mbAgentFixture.case -eq 'badJson'){return @{exitCode=0;elapsedSeconds=1;stdout='PRIVATE_INVALID_JSON';stderr=''}}
 if($global:mbAgentFixture.case -eq 'drift'){[IO.File]::WriteAllText((Join-Path $global:mbAgentFixture.root 'session-checkpoint.json'),'fixture drift')}
 $v=@{version=1;serviceBefore=@{querySucceeded=($global:mbAgentFixture.case -ne 'serviceFailure')};serviceAfter=@{querySucceeded=$true};events=@(@{querySucceeded=($global:mbAgentFixture.case -ne 'eventGap');limitReached=$false})}
 @{exitCode=0;elapsedSeconds=1;stdout=($v|ConvertTo-Json -Depth 6);stderr=''}
}
try{
 foreach($case in @('pass','eventGap','wrongReceipt','timeout','exitFailure','badJson','serviceFailure','drift')){
  $base=Join-Path $tmp $case;$root=Join-Path $base root;$ops=Join-Path $base 'ops/windows';$out=Join-Path $base out
  $null=New-Item -ItemType Directory -Path $root,$ops,$out -Force
  $global:mbAgentFixture=@{case=$case;root=$root;receipt=(Join-Path $base 'receipt.json')}
  Write-PaytmHostJson $global:mbAgentFixture.receipt @{runId=('a'*32);baseline=@{collectorStartUtc='2026-11-05T18:35:55Z'};workerDiagnostics=@{files=@{'startup-failure.json'=@{lastWriteUtc='2026-11-05T18:46:04Z'}}}}
  $checkpoint=Join-Path $root 'session-checkpoint.json';[IO.File]::WriteAllText($checkpoint,'existing checkpoint')
  foreach($n in @('PaytmGatewayAccount.ps1','PaytmGatewayKeyCustody.ps1','PaytmGatewayScheduledProbe.ps1','PaytmSupervisorHost.ps1','PaytmSupervisorInstallation.ps1','PaytmGatewaySession.ps1','PaytmGatewayFailureEvidence.ps1','PaperRuntimeReview.ps1','ReadPaytmAgentFailure.ps1')){[IO.File]::WriteAllText((Join-Path $ops $n),'# fixture')}
  $file=Join-Path $ops 'GetPaytmAgentFailureEvidence.ps1';Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'GetPaytmAgentFailureEvidence.ps1') -Destination $file
  $failed=$false;try{& $file -DiagnosticReportPath $global:mbAgentFixture.receipt -OutputDirectory $out 6>$null}catch{$failed=$true;$caught=$_}
  if($failed -and $case -in @('pass','eventGap')){Get-ChildItem -LiteralPath $out -Filter '*.json'|ForEach-Object {Get-Content -LiteralPath $_.FullName};throw $caught}
  Check ($failed -eq ($case -notin @('pass','eventGap'))) ($case+'_OUTCOME')
  $files=@(Get-ChildItem -LiteralPath $out -Filter '*.json');Check ($files.Count -eq 1) 'ONE_REPORT'
  $v=Read-PaytmHostJson $files[0].FullName 65536
  Check ($v.readOnly -and -not $v.gatewayChanged -and -not $v.taskStarted -and -not $v.credentialsUsed -and -not $v.ordersEnabled) 'NO_MUTATIONS_OR_AUTHORITY'
  Check (-not ([IO.File]::ReadAllText($files[0].FullName)).Contains('PRIVATE_')) 'ERROR_REDACTION'
  if($case -ne 'drift'){Check ([IO.File]::ReadAllText($checkpoint) -ceq 'existing checkpoint') 'CHECKPOINT_PRESERVED'}
  if($case -eq 'pass'){Check ($v.checkpointUnchanged -and $v.eventQueriesComplete -and $v.serviceQueriesComplete) 'COMPLETE_CAPTURE'}
  if($case -eq 'eventGap'){Check (-not $v.eventQueriesComplete -and $v.serviceQueriesComplete) 'EVENT_GAP_VISIBLE_WITHOUT_FALSE_FAILURE'}
  if($case -eq 'drift'){Check ($v.failure -eq 'AGENT_CHECKPOINT_CHANGED_DURING_CAPTURE') 'CONCURRENT_CHANGE_DETECTED'}
  if($case -eq 'timeout'){Check ($v.failure -eq 'RUNTIME_PROCESS_TIMEOUT') 'TIMEOUT_REASON_PRESERVED'}
 }
 [pscustomobject]@{status='AGENT_CONTROLLER_TESTS_PASSED';assertions=$checks.count;workflows=8;runtimeApisMocked=$true}|ConvertTo-Json
}finally{
 $full=[IO.Path]::GetFullPath($tmp);$parent=[IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\')+'\'
 if(-not $full.StartsWith($parent,[StringComparison]::OrdinalIgnoreCase) -or [IO.Path]::GetFileName($full) -notmatch '^mb-agent-controller-[a-f0-9]{32}$'){throw 'UNSAFE_AGENT_CONTROLLER_CLEANUP'}
 if(Test-Path -LiteralPath $full){Remove-Item -LiteralPath $full -Recurse -Force}
 Remove-Variable mbAgentFixture -Scope Global
}
