#Requires -Version 7.0
[CmdletBinding()]param([string]$CheckpointPath,[string]$OutputDirectory='C:\MarketBrainData\Review')
$ErrorActionPreference='Stop'
foreach($name in @('PaytmGatewayAccount.ps1','PaytmGatewayKeyCustody.ps1','PaytmGatewayScheduledProbe.ps1','PaytmSupervisorHost.ps1','PaytmSupervisorInstallation.ps1','PaytmGatewaySession.ps1','PaytmGatewayFailureEvidence.ps1','PaperRuntimeReview.ps1')){. (Join-Path $PSScriptRoot $name)}
$report=[ordered]@{version=1;runId=[guid]::NewGuid().ToString('N');status='REVIEW_REQUIRED';failure=$null;readOnly=$true;gatewayChanged=$false;taskStarted=$false;brokerCredentialsUsed=$false;ordersEnabled=$false}
$null=Assert-PaytmAccountPath $OutputDirectory
$null=New-Item -ItemType Directory -Path $OutputDirectory -Force
$destination=Join-Path $OutputDirectory ('paytm-tls-capture-state-'+$report.runId+'.json')
try{
 Assert-PaytmCustodyController;Import-Module ScheduledTasks
 $report.sourceHashes=@{}
 foreach($n in @('GetPaytmTlsCaptureState.ps1','PaytmGatewayFailureEvidence.ps1','PaytmGatewaySession.ps1')){$report.sourceHashes[$n]=(Get-FileHash -LiteralPath (Join-Path $PSScriptRoot $n)).Hash}
 if(-not $CheckpointPath){
  $latest=Get-ChildItem -LiteralPath $OutputDirectory -Filter 'paytm-native-recovery-*.json' -File | Where-Object Name -NotLike '*.final.json' | Sort-Object LastWriteTimeUtc -Descending | Select-Object -First 1
  if(-not $latest){throw 'HOST_TLS_CAPTURE_CHECKPOINT_NOT_FOUND'}
  $CheckpointPath=$latest.FullName
 }
 $null=Assert-PaytmAccountPath $CheckpointPath
 $saved=Read-PaytmHostJson $CheckpointPath 65536
 if($saved.recoveryMode -cne 'TLS_PHASE_DIAGNOSTIC_STOP_AFTER_CAPTURE' -or $saved.runId -cnotmatch '^[a-f0-9]{32}$'){throw 'HOST_TLS_CAPTURE_WRONG_CHECKPOINT'}
 Write-Host "[25%] Reading checkpoint: $CheckpointPath"
 $report.checkpoint=[ordered]@{path=$CheckpointPath;sha256=(Get-FileHash -LiteralPath $CheckpointPath).Hash;runId=$saved.runId;status=$saved.status;stage=$saved.stage;failure=$saved.failure;cleanupFailure=$saved.cleanupFailure;failureStopVerified=$saved.failureStopVerified;finalApplicationLockVerified=$saved.finalApplicationLockVerified;accountPreserved=$saved.accountPreserved;sourceHashes=$saved.sourceHashes}
 $d=$saved.diagnostic
 if($d){
  $rows=@($d.samples)
  $report.checkpoint.capture=@{captureCompleted=$d.captureCompleted;elapsedSeconds=$d.elapsedSeconds;healthySamples=$d.healthySamples;outageSamples=$d.outageSamples;storedSamples=$rows.Count;first=$(if($rows.Count){$rows[0]}else{$null});last=$(if($rows.Count){$rows[-1]}else{$null})}
 }
 Write-Host '[60%] Read current worker, task and controls. No start, stop or reset.'
 $report.current=Get-PaytmWorkerFailureEvidence
 if((Get-FileHash -LiteralPath $CheckpointPath).Hash -cne $report.checkpoint.sha256){throw 'HOST_TLS_CAPTURE_CHECKPOINT_CHANGED'}
 $report.status='TLS_CAPTURE_STATE_COLLECTED_REVIEW_REQUIRED'
}catch{
 $report.failure=if($_.Exception.Message -cmatch '^(HOST|KEY|ACCOUNT)_[A-Z_]+$'){$_.Exception.Message}else{'HOST_TLS_CAPTURE_STATE_FAILED'}
 $report.failureType=$_.Exception.GetBaseException().GetType().Name
}finally{
 Write-PaytmSessionReport $destination $report
 Write-Host "[100%] $($report.status). Share this ONE file: $destination"
}
if($report.failure){throw 'State collection incomplete. Share the JSON; do not restart the gateway.'}
