# Read-only sampling and interpretation. No actions on import.
function Get-PaytmClockHealthAssessment($Rounds){
 $reasons=@();$offsets=@()
 if(@($Rounds).Count -ne 3){$reasons+='INCOMPLETE_ROUNDS'}
 foreach($r in $Rounds){
  if($r.service.state -cne 'Running' -or $r.service.startType -ne 2){$reasons+='SERVICE_NOT_RUNNING_AUTOMATIC'}
  if(-not $r.sync.synchronizedReported){$reasons+='SYNC_STATUS_UNCONFIRMED'}
  foreach($c in $r.commands){if($null -eq $c.exitCode -or $c.exitCode -ne 0 -or $c.failure){$reasons+='COMMAND_INCOMPLETE'}}
  $strip=@($r.commands|Where-Object {$_.arguments -like '/stripchart *'})
  $values=@();if($strip.Count -eq 1){$values=@([regex]::Matches([string]$strip[0].output,'(?m)^\s*\d{1,2}:\d{2}:\d{2},\s*([+-]\d+\.\d+)s\s*$')|ForEach-Object {[double]::Parse($_.Groups[1].Value,[Globalization.CultureInfo]::InvariantCulture)})}
  if($values.Count -ne 3){$reasons+='PEER_SAMPLES_INCOMPLETE'}
  foreach($v in $values){$offsets+=,$v;if([math]::Abs($v) -gt 5){$reasons+='PEER_OUTSIDE_DIAGNOSTIC_SCREEN'}}
 }
 if(@($Rounds).Count -eq 3 -and ($Rounds[2].elapsedSeconds-$Rounds[0].elapsedSeconds) -lt 60){$reasons+='OBSERVATION_TOO_SHORT'}
 [pscustomobject]@{boundedObservationPassed=($reasons.Count -eq 0);findings=@($reasons|Select-Object -Unique);peerOffsetsSeconds=$offsets;diagnosticScreenSeconds=5;durableSynchronizationProven=$false;quoteTimingApproved=$false;releaseApproved=$false}
}
function Invoke-PaytmClockHealthBatch($Report,[scriptblock]$Save,[scriptblock]$Wait,[scriptblock]$Elapsed){
 $Report.before=Get-PaytmTimeRepairSnapshot
 if($Report.before.state -cne 'Running' -or $Report.before.startType -ne 2 -or $Report.before.ntpServer -ine 'time.windows.com,0x9'){throw 'CLOCK_HEALTH_BASELINE_CHANGED'}
 for($i=0;$i -lt 3;$i++){
  if($i -gt 0){& $Wait}
  Write-Host ('[{0}%] Read-only clock-health round {1}/3' -f (10+$i*30),($i+1))
  $row=@{round=$i+1;elapsedSeconds=(& $Elapsed);service=(Get-PaytmTimeRepairSnapshot);commands=@();sync=$null}
  Assert-PaytmTimeRepairPreserved $Report.before $row.service
  foreach($arg in @('/query /status /verbose','/query /source','/query /peers /verbose','/stripchart /computer:time.windows.com /dataonly /samples:3 /period:2')){
   try{$row.commands+=,(Invoke-PaytmTimeRepairNative 'w32tm.exe' $arg 20)}catch{$row.commands+=,@{arguments=$arg;exitCode=$null;output='';failure=$_.Exception.Message}}
  }
  $row.sync=Get-PaytmTimeSyncAssessment $row.commands[0] $row.commands[1]
  $Report.rounds+=,$row;& $Save
 }
 $Report.after=Get-PaytmTimeRepairSnapshot;Assert-PaytmTimeRepairPreserved $Report.before $Report.after
 if($Report.after.state -cne 'Running' -or $Report.after.startType -ne 2){throw 'CLOCK_HEALTH_FINAL_STATE_CHANGED'}
 $Report.assessment=Get-PaytmClockHealthAssessment $Report.rounds
 $Report.status=if($Report.assessment.boundedObservationPassed){'CLOCK_HEALTH_OBSERVATION_PASSED_POLICY_PENDING'}else{'CLOCK_HEALTH_CAPTURED_WITH_FINDINGS'}
}
