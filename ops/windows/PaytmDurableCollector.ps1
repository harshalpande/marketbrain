# PS5.1-compatible runtime. Diagnostic health only; never arms a route.
function Read-DurableCollectorControl([string]$Path,[string]$Installation) {
 $v=Read-TimeObservationFile $Path
 if($v.version -ne 1 -or $v.installationId -cne $Installation -or $v.enabled -isnot [bool]){throw 'COLLECTOR_CONTROL_INVALID'}
 return $v.enabled
}
function Write-DurableCollectorStatus([string]$Path,$Value) {
 $json=$Value|ConvertTo-Json -Depth 5 -Compress
 if([Text.Encoding]::UTF8.GetByteCount($json) -gt 8192){throw 'COLLECTOR_STATUS_SIZE'}
 $temp=$Path+'.'+[guid]::NewGuid().ToString('N')+'.new'
 [IO.File]::WriteAllText($temp,$json,[Text.UTF8Encoding]::new($false))
 if([IO.File]::Exists($Path)){[IO.File]::Replace($temp,$Path,[Management.Automation.Language.NullString]::Value)}else{[IO.File]::Move($temp,$Path)}
}
function Invoke-DurableCollectorLoop([string]$Token,[string[]]$SshArguments,[string]$Boot,[scriptblock]$Enabled,[scriptblock]$Save) {
 $r=@{version=1;instanceId=[guid]::NewGuid().ToString('N');processId=$PID;sequence=0;acceptedCount=0;consecutiveFailures=0;phase='STARTING';failure=$null;finalHealthRevoked=$false;ordersEnabled=$false}
 try{
  while((& $Enabled)){
   $r.sequence++;$r.observedUtc=[DateTimeOffset]::UtcNow.ToString('o')
   try{
    $v=Invoke-CollectorCycle $Token $SshArguments $Boot
    if(-not $v.accepted -or -not $v.healthySubmitted){throw 'COLLECTOR_SAMPLE_REJECTED'}
    $r.acceptedCount++;$r.consecutiveFailures=0;$r.phase='HEALTH_RECORDED';$r.failure=$null
   }catch{
    $r.consecutiveFailures++;$r.phase='BACKOFF';$r.failure='COLLECTOR_SAMPLE_FAILED'
    # Best-effort immediate revocation; TTL remains authoritative if Java is unavailable.
    try{$null=Invoke-CollectorCycle $Token $SshArguments $Boot -Revoke}catch{}
   }
   & $Save $r
   if($r.consecutiveFailures -ge 3){throw 'COLLECTOR_FAILURE_LIMIT'}
   Start-Sleep -Seconds ([int][math]::Min(8,2*[math]::Pow(2,$r.consecutiveFailures)))
  }
  $r.phase='STOPPED';$r.failure=$null
 }catch{$r.phase='FAILED';$r.failure=if($_.Exception.Message -cmatch '^COLLECTOR_[A-Z_]+$'){$_.Exception.Message}else{'COLLECTOR_RUNTIME_FAILED'}}
 finally{
  try{$v=Invoke-CollectorCycle $Token $SshArguments $Boot -Revoke;$r.finalHealthRevoked=($v.revoked -eq $true)}catch{$r.finalHealthRevoked=$false}
  if(-not $r.finalHealthRevoked){$r.phase='FAILED';$r.failure='COLLECTOR_REVOCATION_UNCONFIRMED'}
  $r.observedUtc=[DateTimeOffset]::UtcNow.ToString('o');& $Save $r
 }
 return $r
}
