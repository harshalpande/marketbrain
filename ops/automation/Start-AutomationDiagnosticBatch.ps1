#requires -Version 7.2
[CmdletBinding()]
param([ValidateRange(30,45)][int]$DurationMinutes=30,[ValidateRange(60,300)][int]$IntervalSeconds=120)
. (Join-Path $PSScriptRoot 'Automation.Common.ps1')
. (Join-Path $PSScriptRoot 'Automation.BatchAssessment.ps1')
$root=Join-Path $env:LOCALAPPDATA 'MarketBrainAutomation'
$config=Get-AutomationConfig (Join-Path $root 'controller.dpapi')
if($config.role -ne 'controller'){throw 'Controller configuration required'}
$directory=Join-Path $root 'reports';$null=New-Item -ItemType Directory -Path $directory -Force
$run=[guid]::NewGuid().ToString('N');$path=Join-Path $directory ('batch-'+$run+'.json')
$batch=@{runId=$run;status='RUNNING';startedUtc=[DateTimeOffset]::UtcNow.ToString('o');durationMinutes=$DurationMinutes;intervalSeconds=$IntervalSeconds;jobs=@();pendingJobId=$null;connectionErrors=0;ordersEnabled=$false}
$watch=[Diagnostics.Stopwatch]::StartNew();$next=0;$lastProgress=-60;$submitted=$false
Write-Host "BATCH_REPORT: $path"
try{
 do {
  if($null -eq $batch.pendingJobId -and $watch.Elapsed.TotalSeconds -ge $next){
   $batch.pendingJobId=[guid]::NewGuid().ToString();$submitted=$false
   Write-AutomationState $path $batch
  }
  if($batch.pendingJobId){
   try {
    # Replay only the same idempotent submission after a lost response. Never
    # enqueue another job while one is pending, and never execute repair code.
    if(-not $submitted){$null=Invoke-AutomationApi $config '/submit' @{id=$batch.pendingJobId;kind='diagnostic'};$submitted=$true;Write-Host "SUBMITTED: $($batch.pendingJobId)"}
    $job=(Invoke-AutomationApi $config '/result' @{id=$batch.pendingJobId}).job
    if($job -and $job.state -in @('SUCCEEDED','FAILED','INTERRUPTED','CANCELLED')){
     if($job.id -cne $batch.pendingJobId -or $job.kind -cne 'diagnostic'){throw 'Unexpected result identity'}
     Write-AutomationState (Join-Path $directory ($job.id+'.json')) $job
     $assessment=Get-AutomationBatchAssessment $job
     $batch.jobs+=@{id=$job.id;seconds=$watch.Elapsed.TotalSeconds;assessment=$assessment}
     Write-Host ("RESULT: {0}; transport={1}; findings={2}" -f $job.id,$assessment.transportPassed,($assessment.findings -join ','))
     $batch.pendingJobId=$null;$next=$watch.Elapsed.TotalSeconds+$IntervalSeconds
    }
   }catch{
    $batch.connectionErrors++;$batch.lastErrorType=$_.Exception.GetBaseException().GetType().Name
    # Do not print exception text, headers or the pairing token.
    Write-Host "RETRY_SAME_JOB: $($batch.pendingJobId); $($batch.lastErrorType)"
   }
  }
  $batch.elapsedSeconds=$watch.Elapsed.TotalSeconds;Write-AutomationState $path $batch
  if($watch.Elapsed.TotalSeconds-$lastProgress -ge 30){
   $lastProgress=$watch.Elapsed.TotalSeconds
   Write-Host ("PROGRESS: {0:n0}/{1} seconds; completed={2}; pending={3}" -f $lastProgress,($DurationMinutes*60),$batch.jobs.Count,$batch.pendingJobId)
  }
  Write-Progress -Activity 'Automated diagnostic observation batch' -Status "$($batch.jobs.Count) results collected" -PercentComplete ([math]::Min(99,100*$watch.Elapsed.TotalSeconds/($DurationMinutes*60)))
  Start-Sleep -Seconds 5
 }while($watch.Elapsed.TotalMinutes -lt $DurationMinutes)
 $batch.status=if($batch.pendingJobId){'WINDOW_ENDED_JOB_PENDING'}else{'OBSERVATION_COMPLETE_REVIEW_FINDINGS'}
}finally{
 $batch.elapsedSeconds=$watch.Elapsed.TotalSeconds
 if($batch.status -eq 'RUNNING'){$batch.status='CONTROLLER_INTERRUPTED_REVIEW_PENDING_JOB'}
 Write-AutomationState $path $batch
 Write-Progress -Activity 'Automated diagnostic observation batch' -Completed
 Write-Host "BATCH_END: $($batch.status); $path"
}
