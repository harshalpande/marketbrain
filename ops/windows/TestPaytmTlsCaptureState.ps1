#Requires -Version 7.0
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'PaytmSupervisorHost.ps1')
. (Join-Path $PSScriptRoot 'PaytmGatewaySession.ps1')
function Assert-PaytmAccountPath($p){$p}
function Assert-PaytmCustodyController {}
function Import-Module {}
function Get-PaytmWorkerFailureEvidence {@{task=@{state='Disabled'};controls=@{mode='STOP'}}}
$tmp=Join-Path ([IO.Path]::GetTempPath()) ('mb-capture-state-'+[guid]::NewGuid().ToString('N'))
try{
 $ops=Join-Path $tmp ops;$null=New-Item -ItemType Directory -Path $ops -Force
 foreach($n in @('PaytmGatewayAccount.ps1','PaytmGatewayKeyCustody.ps1','PaytmGatewayScheduledProbe.ps1','PaytmSupervisorHost.ps1','PaytmSupervisorInstallation.ps1','PaytmGatewaySession.ps1','PaytmGatewayFailureEvidence.ps1','PaperRuntimeReview.ps1')){[IO.File]::WriteAllText((Join-Path $ops $n),'# mocked privileged API')}
 $collector=Join-Path $ops 'GetPaytmTlsCaptureState.ps1';Copy-Item (Join-Path $PSScriptRoot 'GetPaytmTlsCaptureState.ps1') $collector
 foreach($case in @('explicit','auto','wrongMode','missing','currentOnly')){
  $out=Join-Path $tmp $case;$null=New-Item -ItemType Directory -Path $out
  $inputFile=Join-Path $out 'paytm-native-recovery-fixture.json'
  $v=@{version=1;runId=('a'*32);recoveryMode=$(if($case -eq 'wrongMode'){'OTHER'}else{'TLS_PHASE_DIAGNOSTIC_STOP_AFTER_CAPTURE'});status='REVIEW_REQUIRED';diagnostic=@{captureCompleted=$false;elapsedSeconds=228;healthySamples=43;outageSamples=0;samples=@(@{sequence=1},@{sequence=43})}}
  if($case -notin @('missing','currentOnly')){Write-PaytmSessionReport $inputFile $v;$before=(Get-FileHash $inputFile).Hash}
  $args=@{OutputDirectory=$out};if($case -in @('explicit','wrongMode')){$args.CheckpointPath=$inputFile}
  if($case -eq 'currentOnly'){$args.CurrentStateOnly=$true}
  $failed=$false;try{& $collector @args 6>$null}catch{$failed=$true}
  if($failed -ne ($case -eq 'wrongMode')){throw "OUTCOME_$case"}
  if($case -notin @('missing','currentOnly') -and (Get-FileHash $inputFile).Hash -cne $before){throw 'SOURCE_CHANGED'}
  $files=@(Get-ChildItem $out -Filter 'paytm-tls-capture-state-*.json')
  if($files.Count -ne 1){throw 'SINGLE_REPORT_REQUIRED'}
  $result=Read-PaytmHostJson $files[0].FullName 65536
  if($result.gatewayChanged -or $result.taskStarted){throw 'UNEXPECTED_MUTATION'}
  if($result.current.task.state -cne 'Disabled'){throw 'CURRENT_STATE_NOT_CAPTURED'}
  if($case -in @('missing','currentOnly')){
   if(-not $result.checkpoint.availability -or $result.status -cne 'TLS_CAPTURE_STATE_COLLECTED_REVIEW_REQUIRED'){throw 'MISSING_CHECKPOINT_HANDLING'}
  }elseif(-not $failed -and $result.checkpoint.capture.storedSamples -ne 2){throw 'STATE_NOT_CAPTURED'}
 }
 Write-Host 'PASS: five read-only collector workflows, including no checkpoint and current-state-only collection.'
}finally{
 $full=[IO.Path]::GetFullPath($tmp);$parent=[IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\')+'\'
 if(-not $full.StartsWith($parent,[StringComparison]::OrdinalIgnoreCase) -or [IO.Path]::GetFileName($full) -notmatch '^mb-capture-state-[a-f0-9]{32}$'){throw 'UNSAFE_FIXTURE_CLEANUP'}
 if(Test-Path -LiteralPath $full){Remove-Item -LiteralPath $full -Recurse -Force}
}
