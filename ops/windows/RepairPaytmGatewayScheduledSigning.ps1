#Requires -Version 7.0
[CmdletBinding()]param(
 [string]$LaunchReportPath='C:\MarketBrainData\Review\paytm-scheduled-signing-20261102-130045-8d26b08689d940ce8798fd4095b302c5.json',
 [string]$CustodyReportPath='C:\MarketBrainData\Review\paytm-key-custody-20261102-112446-29cb6394513a47f687351825698006d5.json',
 [string]$OutputDirectory='C:\MarketBrainData\Review')
$ErrorActionPreference='Stop'
foreach($name in @('PaytmGatewayAccount.ps1','PaytmGatewayAccountRepair.ps1','PaytmGatewayKeyCustody.ps1','PaytmGatewayScheduledProbe.ps1','PaytmGatewayBatchLogon.ps1')){. (Join-Path $PSScriptRoot $name)}
$report=[ordered]@{version=1;runId=[guid]::NewGuid().ToString('N');status='REVIEW_REQUIRED';stage='PREFLIGHT';failure=$null;failureDetails=$null;
 taskRunId='6b3bcee5eac24157aa38b858b96ae253';sourceHashes=[ordered]@{};acceptedProgress=@();prerequisites=$null;
 policyBefore=$null;policyAfter=$null;grantAttempted=$false;rightVerified=$false;startRequested=$false;signingPassed=$false;
 lastTaskResult=$null;taskState=$null;worker=$null;taskDisabled=$false;taskRemoved=$false;cleanupFailure=$null;launchEvidence=$null;
 keyImported=$false;passwordChanged=$false;networkContacted=$false;ordersEnabled=$false;elapsedSeconds=0}
$timer=[Diagnostics.Stopwatch]::StartNew();$stream=$null;$lastStage=''
$null=Assert-PaytmAccountPath $OutputDirectory;$null=New-Item -ItemType Directory -Path $OutputDirectory -Force
$path=Join-Path $OutputDirectory ('paytm-batch-logon-repair-'+(Get-Date -Format 'yyyyMMdd-HHmmss')+'-'+$report.runId+'.json')
function Save-BatchCheckpoint {
 $report.elapsedSeconds=[math]::Round($timer.Elapsed.TotalSeconds,3)
 $data=[Text.Encoding]::UTF8.GetBytes(($report|ConvertTo-Json -Depth 12));$stream.Position=0;$stream.SetLength(0);$stream.Write($data,0,$data.Length);$stream.Flush($true)
 if($script:lastStage -cne $report.stage){
  $script:lastStage=$report.stage;$p=switch($report.stage){PREFLIGHT{0} REVALIDATE{15} GRANT_ACCOUNT_BATCH_LOGON{40} RUN_RETAINED_SIGNING_PROBE{65} COMPLETE{100} default{90}}
  Write-Host "[$p%] $($report.stage)";Write-Progress -Activity 'Gateway batch logon correction' -Status $report.stage -PercentComplete $p
 }
}
try {
 $stream=[IO.File]::Open($path,'CreateNew','Write','Read');Save-BatchCheckpoint
 foreach($name in @('RepairPaytmGatewayScheduledSigning.ps1','PaytmGatewayBatchLogon.ps1','PaytmGatewayScheduledProbe.ps1','PaytmGatewayAccount.ps1','PaytmGatewayAccountRepair.ps1','PaytmGatewayKeyCustody.ps1')){$report.sourceHashes[$name]=(Get-FileHash -LiteralPath (Join-Path $PSScriptRoot $name)).Hash}
 Assert-PaytmCustodyController;Import-Module ScheduledTasks -ErrorAction Stop;Import-Module Microsoft.PowerShell.LocalAccounts -ErrorAction Stop
 $report.acceptedProgress=@(Get-PaytmReadinessProgress)
 Write-Host 'Adds only gateway account batch-logon allow right if missing; preserves deny rules and other accounts. Runs the reviewed retained task once using its stored credential.'
 Invoke-PaytmBatchRecovery $report {Save-BatchCheckpoint} $CustodyReportPath $LaunchReportPath
 if($report.cleanupFailure -or -not $report.signingPassed -or -not $report.taskRemoved){throw 'SCHEDULE_RECOVERY_NOT_COMPLETE'}
 $report.stage='COMPLETE';$report.status='BATCH_LOGON_AND_SIGNING_PASSED_SUPERVISOR_PENDING'
}catch{
 $report.failure=if($_.Exception.Message -cmatch '^(SCHEDULE|ACCOUNT|KEY)_[A-Z_]+$'){$_.Exception.Message}else{'SCHEDULE_BATCH_REPAIR_FAILED'}
 $base=$_.Exception.GetBaseException();$report.failureDetails=[pscustomobject]@{type=$base.GetType().Name;hresult=$base.HResult;nativeErrorCode=if($base -is [ComponentModel.Win32Exception]){$base.NativeErrorCode}else{$null};line=$_.InvocationInfo.ScriptLineNumber}
}finally{
 if($report.startRequested -and -not $report.signingPassed){try{$report.launchEvidence=Get-PaytmProbeLaunchEvidence $report.taskRunId}catch{}}
 $timer.Stop();if($null -ne $stream){try{Save-BatchCheckpoint}finally{$stream.Dispose()}}
 Write-Progress -Activity 'Gateway batch logon correction' -Completed;Write-Progress -Activity 'Scheduled gateway signing' -Completed
 Write-Host "[100%] $($report.status); elapsed=$($report.elapsedSeconds)s"
 Write-Host "Share this ONE file: $path"
 Write-Host 'Any added batch-logon right is retained and documented. No account/password/key reset or automatic retry.'
}
if($report.failure -or $report.cleanupFailure){throw 'Batch logon/signing requires review; share the printed JSON.'}
