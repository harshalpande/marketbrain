#Requires -Version 7.0
[CmdletBinding()]param(
 [string]$DiagnosticReportPath='C:\MarketBrainData\Review\paytm-gateway-session-8b38588d74bb4729812fd773a7fd7f0b.json',
 [string]$OutputDirectory='C:\MarketBrainData\Review')
$ErrorActionPreference='Stop'
foreach($name in @('PaytmGatewayAccount.ps1','PaytmGatewayKeyCustody.ps1','PaytmGatewayScheduledProbe.ps1','PaytmSupervisorHost.ps1','PaytmSupervisorInstallation.ps1','PaytmGatewaySession.ps1','PaytmGatewayFailureEvidence.ps1','PaperRuntimeReview.ps1')){. (Join-Path $PSScriptRoot $name)}
$watch=[Diagnostics.Stopwatch]::StartNew();$c=Get-PaytmHostContract
$report=[ordered]@{version=1;runId=[guid]::NewGuid().ToString('N');status='REVIEW_REQUIRED';stage='PREFLIGHT';failure=$null;elapsedSeconds=0;readOnly=$true;gatewayChanged=$false;taskStarted=$false;credentialsUsed=$false;ordersEnabled=$false;applicationAccessed=$false;historicalCauseEstablished=$false;sourceHashes=@{}}
$null=Assert-PaytmAccountPath $OutputDirectory;$null=New-Item -ItemType Directory -Path $OutputDirectory -Force
$script:agentReportPath=Join-Path $OutputDirectory ('paytm-agent-failure-'+$report.runId+'.json')
try{
 Assert-PaytmCustodyController;Import-Module ScheduledTasks
 $null=Assert-PaytmAccountPath $DiagnosticReportPath
 if((Get-FileHash -LiteralPath $DiagnosticReportPath).Hash -cne '72B5F4016330C6B4D45AC917DDA533CE6E329B2BB3A7B86BE91E562B84ADEBCA'){throw 'AGENT_REVIEWED_REPORT_MISMATCH'}
 $inputReport=Read-PaytmHostJson $DiagnosticReportPath 65536
 $report.reviewedRunId=$inputReport.runId
 $from=([DateTimeOffset]$inputReport.baseline.collectorStartUtc).AddMinutes(-2).ToUniversalTime()
 $to=([DateTimeOffset]$inputReport.workerDiagnostics.files.'startup-failure.json'.lastWriteUtc).AddMinutes(2).ToUniversalTime()
 if($to -le $from -or ($to-$from).TotalMinutes -gt 30){throw 'AGENT_EVENT_WINDOW_INVALID'}
 $report.windowStart=$from.ToString('o');$report.windowEnd=$to.ToString('o')
 foreach($name in @('GetPaytmAgentFailureEvidence.ps1','ReadPaytmAgentFailure.ps1','PaytmGatewayFailureEvidence.ps1','PaytmGatewaySession.ps1')){$report.sourceHashes[$name]=(Get-FileHash -LiteralPath (Join-Path $PSScriptRoot $name)).Hash}
 $report.stage='READ_CURRENT_WORKER_AND_CHECKPOINT'
 Write-Host '[20%] Reading saved gateway state; no service restart, task start or key import.'
 Write-Progress -Activity 'SSH agent failure evidence' -Status $report.stage -PercentComplete 20
 $checkpoint=Assert-PaytmAccountPath (Join-Path $c.root 'session-checkpoint.json')
 $report.checkpointBefore=@{present=[IO.File]::Exists($checkpoint);sha256=$null}
 if($report.checkpointBefore.present){$report.checkpointBefore.sha256=(Get-FileHash -LiteralPath $checkpoint).Hash}
 $report.workerDiagnostics=Get-PaytmWorkerFailureEvidence
 Write-PaytmSessionReport $script:agentReportPath $report
 $report.stage='READ_AGENT_SERVICE_AND_FAILURE_WINDOW_EVENTS'
 Write-Host '[50%] Reading current ssh-agent service and bounded historical events (90-second query limit).'
 Write-Progress -Activity 'SSH agent failure evidence' -Status $report.stage -PercentComplete 50
 $body=[IO.File]::ReadAllText((Join-Path $PSScriptRoot 'ReadPaytmAgentFailure.ps1'))
 $code="& {`n"+$body+"`n} -StartUtc '"+$from.ToString('o')+"' -EndUtc '"+$to.ToString('o')+"'"
 $encoded=[Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($code))
 $result=Invoke-PaperRuntimeProcess 'C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe' @('-NoLogo','-NoProfile','-NonInteractive','-EncodedCommand',$encoded) (Resolve-Path (Join-Path $PSScriptRoot '../..')).Path 90
 $report.nativeQuery=@{exitCode=$result.exitCode;elapsedSeconds=$result.elapsedSeconds;stderrCharacters=$result.stderr.Length}
 if($result.exitCode -ne 0 -or $result.stdout.Length -gt 40000){throw 'AGENT_QUERY_FAILED_OR_OVERSIZE'}
 $report.agentEvidence=$result.stdout|ConvertFrom-Json -ErrorAction Stop
 $report.checkpointAfter=@{present=[IO.File]::Exists($checkpoint);sha256=$null}
 if($report.checkpointAfter.present){$report.checkpointAfter.sha256=(Get-FileHash -LiteralPath $checkpoint).Hash}
 $report.checkpointUnchanged=($report.checkpointBefore.present -eq $report.checkpointAfter.present -and $report.checkpointBefore.sha256 -ceq $report.checkpointAfter.sha256)
 if(-not $report.checkpointUnchanged){throw 'AGENT_CHECKPOINT_CHANGED_DURING_CAPTURE'}
 $report.serviceQueriesComplete=($report.agentEvidence.serviceBefore.querySucceeded -and $report.agentEvidence.serviceAfter.querySucceeded)
 $report.eventQueriesComplete=@($report.agentEvidence.events|Where-Object {-not $_.querySucceeded -or $_.limitReached}).Count -eq 0
 if(-not $report.serviceQueriesComplete){throw 'AGENT_SERVICE_QUERY_INCOMPLETE'}
 # Missing/disabled/expired event logs remain explicit gaps, not a reason to rerun or enable logging blindly.
 $report.status='AGENT_EVIDENCE_CAPTURED_GATEWAY_RECOVERY_PENDING';$report.stage='COMPLETE'
}catch{
 $report.failure=if($_.Exception.Message -cin @('RUNTIME_PROCESS_TIMEOUT','RUNTIME_OUTPUT_TIMEOUT','RUNTIME_START_FAILED')){$_.Exception.Message}elseif($_.Exception.Message -cmatch '^(AGENT|HOST|KEY|ACCOUNT)_[A-Z_]+$'){$_.Exception.Message}else{'AGENT_DIAGNOSTIC_FAILED'}
 $report.failureDetails=@{type=$_.Exception.GetBaseException().GetType().Name;line=$_.InvocationInfo.ScriptLineNumber;script=[IO.Path]::GetFileName($_.InvocationInfo.ScriptName)}
}finally{
 $report.elapsedSeconds=[math]::Round($watch.Elapsed.TotalSeconds,3)
 Write-PaytmSessionReport $script:agentReportPath $report
 Write-Progress -Activity 'SSH agent failure evidence' -Completed
 Write-Host "[100%] $($report.status); elapsed=$($report.elapsedSeconds)s"
 Write-Host "Share this ONE file: $script:agentReportPath"
 Write-Host 'Keep the existing session checkpoint. Do not repeat sign-out or proceed to shutdown yet.'
}
if($report.status -ceq 'REVIEW_REQUIRED'){throw 'Agent diagnostic needs review. Share its JSON; do not reset the gateway.'}
