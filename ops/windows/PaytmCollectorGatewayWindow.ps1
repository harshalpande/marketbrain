# Definitions and fixed dependencies only. No startup on import.
. (Join-Path $PSScriptRoot '../automation/DenialRecovery.Core.ps1')
. (Join-Path $PSScriptRoot '../automation/PostRecovery.Core.ps1')
. (Join-Path $PSScriptRoot 'PaytmTimeObservation.ps1')
function Read-BoundedJson([string]$Path) {
 $s=$null;$reader=$null
 try{
  $s=[IO.File]::Open($Path,'Open','Read',([IO.FileShare]::ReadWrite -bor [IO.FileShare]::Delete))
  if($s.Length -gt 65536){throw 'SCHEDULE_GATEWAY_STATE_SIZE'}
  $reader=[IO.StreamReader]::new($s);$buffer=[char[]]::new(65537);$n=$reader.ReadBlock($buffer,0,$buffer.Length)
  if($n -gt 65536){throw 'SCHEDULE_GATEWAY_STATE_SIZE'}
  ([string]::new($buffer,0,$n))|ConvertFrom-Json
 }finally{if($reader){$reader.Dispose()};if($s){$s.Dispose()}}
}
function New-CollectorGatewayContext([string]$RunId) {
 if($RunId -cnotmatch '^[a-f0-9]{32}$'){throw 'SCHEDULE_GATEWAY_RUN'}
 @{root='C:\ProgramData\MarketBrainPaytmGateway\supervisor-v1';work='C:\ProgramData\MarketBrainPaytmGateway\supervisor-work-v1';taskName='MarketBrain-Gateway-Supervisor-v1';runId=$RunId;guardName=('MarketBrain-Collector-Guard-'+$RunId);archive=('C:\ProgramData\MarketBrainPaytmGateway\supervisor-v1\collector-window-'+$RunId);guardXmlHash=$null;startAttempted=$false;stopped=$false;guardRemoved=$false}
}
function Get-CollectorGatewayPreflight($Context) {
 $receipt=Get-Content -LiteralPath (Join-Path $PSScriptRoot '../../docs/evidence/queued-recovery-preflight-20261120.json') -Raw|ConvertFrom-Json -AsHashtable
 $r=Get-PostRecoveryPreflight $Context $receipt.result.evidence.recoveryPreflight -CollectorPreflight
 if(-not $r.passed){throw $r.failure}
 if((Read-BoundedJson (Join-Path $Context.root 'control.json')).mode -cne 'LOCKED'){throw 'SCHEDULE_GATEWAY_SCOPE'}
 $task=Get-ScheduledTask -TaskName $Context.taskName -TaskPath '\'
 if($task.Description -cne 'MarketBrain locked supervisor ea8b91471cf048aa97a0f6b939b355c7'){throw 'SCHEDULE_GATEWAY_IDENTITY'}
 if(-not (Get-ApplicationHealthInventory).applicationUp){throw 'SCHEDULE_APPLICATION_NOT_UP'}
 $null=Read-TimeObservation
 return $r
}
function Test-CollectorGatewaySample($Value,[string]$PreviousInstance) {
 if($Value.installationId -cne 'ea8b91471cf048aa97a0f6b939b355c7' -or $Value.ordersEnabled -ne $false -or $Value.brokerReady -ne $false){throw 'SCHEDULE_GATEWAY_SCOPE'}
 if($Value.instanceId -ceq $PreviousInstance){return $false}
 if($Value.instanceId -cnotmatch '^[a-f0-9]{32}$' -or $Value.failure -or $Value.phase -ceq 'BLOCKED'){throw 'SCHEDULE_GATEWAY_FAILED'}
 if($Value.phase -cne 'TRANSPORT_READY'){return $false}
 $tls=$Value.lastTlsObservation
 if($Value.denialsVerified -ne $true -or -not $tls -or $tls.exitCode -ne 0 -or $tls.timedOut -ne $false -or $tls.connectStatus -ne 200 -or $tls.tlsVerifyCode -ne 0){throw 'SCHEDULE_GATEWAY_TLS'}
 return $true
}
function Start-CollectorGatewayWindow($Context) {
 $before=Get-CollectorGatewayPreflight $Context
 if(Test-Path -LiteralPath $Context.archive){throw 'SCHEDULE_GATEWAY_COLLISION'}
 $null=New-Item -ItemType Directory -Path $Context.archive
 # Fixed independent three-minute stop survives terminal/process loss.
 $Context.guardAttempted=$true
 Register-DenialRecoveryGuard $Context $before.hashes['manifest.json']
 $again=Get-CollectorGatewayPreflight $Context
 if($again.hashes['status.json'] -cne $before.hashes['status.json']){throw 'SCHEDULE_GATEWAY_CHANGED'}
 $Context.startAttempted=$true
 $null=Enable-ScheduledTask -TaskName $Context.taskName -TaskPath '\'
 Start-ScheduledTask -TaskName $Context.taskName -TaskPath '\'
 $watch=[Diagnostics.Stopwatch]::StartNew();$first=$null
 do{
  Start-Sleep -Seconds 1
  if((Read-BoundedJson (Join-Path $Context.root 'control.json')).mode -cne 'LOCKED'){throw 'SCHEDULE_GATEWAY_SCOPE'}
  $v=Read-BoundedJson (Join-Path $Context.work 'status.json')
  if(Test-CollectorGatewaySample $v $before.currentStatus.instanceId){
   $listeners=@([Net.NetworkInformation.IPGlobalProperties]::GetIPGlobalProperties().GetActiveTcpListeners()|Where-Object Port -EQ 18889)
   if(-not $listeners.Count -or @($listeners|Where-Object {$_.Address.ToString() -notin @('127.0.0.1','::1')}).Count){throw 'SCHEDULE_GATEWAY_LISTENER'}
   if($first -and $v.instanceId -ceq $first.instanceId -and $v.sequence -gt $first.sequence){$Context.readyInstance=$v.instanceId;return}
   if($first -and $v.instanceId -cne $first.instanceId){throw 'SCHEDULE_GATEWAY_CHANGED'}
   $first=$v
  }
  Write-Progress -Activity 'Collector gateway window' -Status ('Waiting for fresh transport: '+[int]$watch.Elapsed.TotalSeconds+' / 45 seconds') -PercentComplete 50
 }while($watch.Elapsed.TotalSeconds -lt 45)
 throw 'SCHEDULE_GATEWAY_TIMEOUT'
}
function Stop-CollectorGatewayWindow($Context) {
 if($Context.startAttempted){Stop-DenialRecoveryTask $Context;$Context.stopped=$true}
 if($Context.guardAttempted -and -not $Context.guardXmlHash){throw 'SCHEDULE_GATEWAY_GUARD_REVIEW_REQUIRED'}
 if($Context.guardXmlHash){Remove-DenialRecoveryGuard $Context;$Context.guardRemoved=$true}
 Write-Progress -Activity 'Collector gateway window' -Completed
}
function Save-CollectorAutomaticSummary($Report,[string]$ReportPath,$Context) {
 $root='C:\ProgramData\MarketBrainPaytmHealth\time-observer-v1';Assert-TimeObservationAcl $root
 $summary=@{runId=$Report.runId;observedUtc=[DateTimeOffset]::UtcNow.ToString('o');status=$Report.status;failure=$Report.failure;cleanupFailure=$Report.cleanupFailure;stage=$Report.stage;taskRemoved=$Report.taskRemoved;lastTaskResult=$Report.lastTaskResult;reportPath=$ReportPath;reportSha256=(Get-FileHash -LiteralPath $ReportPath).Hash;ordersEnabled=$false;gatewayStarted=$Context.startAttempted;gatewayStopped=$Context.stopped;guardRemoved=$Context.guardRemoved;worker=@{}}
 foreach($name in @('failure','stage','identityVerified','nonAdmin','nonInteractiveSession','signingChecks','clockVerified','tokenAuthenticated','tokenDecrypted','finalHealthRevoked','applicationLocked')){$summary.worker[$name]=$Report.worker.$name}
 $summary.worker.rounds=@($Report.worker.collectorRounds|Where-Object {$null -ne $_}|ForEach-Object {@{accepted=$_.accepted;healthySubmitted=$_.healthySubmitted;findings=$_.findings;failedPhase=$_.failedPhase}})
 $json=$summary|ConvertTo-Json -Depth 7;if([Text.Encoding]::UTF8.GetByteCount($json) -gt 16384){throw 'SCHEDULE_SUMMARY_SIZE'}
 $path=Join-Path $root 'collector-batch-result.json';if(Test-Path -LiteralPath $path){Assert-TimeObservationAcl $path}
 $temp=Join-Path $root ('collector-'+[guid]::NewGuid().ToString('N')+'.new')
 [IO.File]::WriteAllText($temp,$json,[Text.UTF8Encoding]::new($false));Assert-TimeObservationAcl $temp
 if(Test-Path -LiteralPath $path){[IO.File]::Replace($temp,$path,[Management.Automation.Language.NullString]::Value)}else{[IO.File]::Move($temp,$path)}
}
