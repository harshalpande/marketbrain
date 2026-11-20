# One explicit resync of the existing provider; never changes time policy or starts trading tasks.
$r=@{passed=$false;status='REVIEW_REQUIRED';failure=$null;ordersEnabled=$false;policyChanged=$false;resyncRequested=$false;commands=@()}
try{
 foreach($name in @('MarketBrain-Health-Collector-v1','MarketBrain-Gateway-Supervisor-v1')){
  $t=Get-ScheduledTask -TaskName $name -TaskPath '\'
  if($t.Settings.Enabled -or [string]$t.State -cne 'Disabled'){throw 'CLOCK_REFRESH_TASK_ACTIVE'}
 }
 $before=Read-TimeObservation
 $r.before=@{status=$before.status;source=$before.source;sequence=$before.sequence}
 $a=Get-PaytmTimeSyncAssessment $before.status $before.source
 if(-not $a.synchronizedReported){throw 'CLOCK_REFRESH_SOURCE_UNCONFIRMED'}
 if($Mode -ceq 'Apply'){
  $r.resyncRequested=$true
  $c=Invoke-PaytmTimeRepairNative 'w32tm.exe' '/resync /rediscover' 40;$r.commands+=,$c
  if($c.exitCode -ne 0 -or $c.output -notmatch '(?im)^The command completed successfully\.\s*$'){throw 'CLOCK_REFRESH_NOT_ACCEPTED'}
 }elseif($Mode -cne 'Observe'){throw 'CLOCK_REFRESH_MODE'}
 $watch=[Diagnostics.Stopwatch]::StartNew()
 do{
  $v=Read-TimeObservation
  $m=[regex]::Match($v.status.output,'(?im)^Time since Last Good Sync Time:\s*([0-9]+(?:\.[0-9]+)?)s\s*$')
  $assessment=Get-PaytmTimeSyncAssessment $v.status $v.source
  if($m.Success -and $assessment.synchronizedReported -and $v.sequence -gt $before.sequence -and [double]::Parse($m.Groups[1].Value,[Globalization.CultureInfo]::InvariantCulture) -le 60){$r.after=@{status=$v.status;source=$v.source;sequence=$v.sequence};$r.passed=$true;break}
  Start-Sleep -Seconds 1
 }while($watch.Elapsed.TotalSeconds -lt 20)
 if(-not $r.passed){throw 'CLOCK_REFRESH_FRESH_SYNC_UNCONFIRMED'}
 $r.status='CLOCK_REFRESH_VERIFIED_POLLING_POLICY_REVIEW_PENDING'
}catch{$r.failure=if($_.Exception.Message -cmatch '^[A-Z_]+$'){$_.Exception.Message}else{'CLOCK_REFRESH_FAILED'}}
[IO.File]::WriteAllText($ResultPath,($r|ConvertTo-Json -Depth 8),[Text.UTF8Encoding]::new($false))
if(-not $r.passed){exit 1}
