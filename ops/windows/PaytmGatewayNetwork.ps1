#Requires -Version 7.0
# One temporary program/destination/port block. Never change a profile or existing rule.
function Assert-PaytmCancellationReceipt([string]$Path){
 $null=Assert-PaytmAccountPath $Path
 if((Get-FileHash -LiteralPath $Path).Hash -cne '8A5F02400003D32C46A892F9BEADAB0E5C109034E44B4AEF0C0EFA8645B0875D'){throw 'NETWORK_CANCELLATION_RECEIPT_NOT_ACCEPTED'}
 $v=Read-PaytmHostJson $Path 65536
 if($v.runId -cne '1eebaa9b8dec4b9b82d8fa9f66b26859' -or $v.status -cne 'GATEWAY_CANCELLATION_AND_APPLICATION_RECOVERY_PASSED' -or $v.failure -or $v.cleanupFailure){throw 'NETWORK_CANCELLATION_RECEIPT_INVALID'}
 foreach($n in @('cancellationPassed','recoveryPassed','noAutomaticRearmPassed','accountPreserved','finalApplicationLockVerified')){if($v.$n -ne $true){throw 'NETWORK_CANCELLATION_PROOF_MISSING'}}
 Assert-PaytmManagedStatus $v.recovered $v.before.installationId TRANSPORT_READY
 if($v.before.instanceId -ceq $v.recovered.instanceId -or -not (Test-PaytmCancellationExit $v.cancelled) -or $v.quietSeconds -lt 10 -or @($v.applicationRouteChecks|Where-Object passed -NE $true).Count -or @($v.applicationRouteChecks).Count -ne 3){throw 'NETWORK_CANCELLATION_PROOF_INVALID'}
}
function Get-PaytmNetworkRule([string]$Name,[string]$Store='PersistentStore'){
 @(Get-NetFirewallRule -PolicyStore $Store -ErrorAction Stop|Where-Object Name -CEQ $Name)
}
function Assert-PaytmNetworkRule($Rule,[string]$RunId,[bool]$Enabled){
 if($Rule.Name -cne ('MarketBrain-Network-Test-'+$RunId) -or $Rule.Group -cne 'MarketBrain bounded network test' -or $Rule.Description -cne $RunId -or [string]$Rule.Direction -cne 'Outbound' -or [string]$Rule.Action -cne 'Block' -or [string]$Rule.Profile -cne 'Any' -or [string]$Rule.Enabled -ine [string]$Enabled){throw 'NETWORK_RULE_SHAPE'}
 $app=@($Rule|Get-NetFirewallApplicationFilter -ErrorAction Stop);$port=@($Rule|Get-NetFirewallPortFilter -ErrorAction Stop);$addr=@($Rule|Get-NetFirewallAddressFilter -ErrorAction Stop)
 if($app.Count -ne 1 -or $app[0].Program -ine 'C:\Windows\System32\OpenSSH\ssh.exe' -or $port.Count -ne 1 -or [string]$port[0].Protocol -cnotin @('TCP','6') -or [string]$port[0].RemotePort -cne '22' -or [string]$port[0].LocalPort -cne 'Any' -or $addr.Count -ne 1 -or [string]$addr[0].RemoteAddress -cne '130.250.191.137' -or [string]$addr[0].LocalAddress -cne 'Any'){throw 'NETWORK_RULE_FILTERS'}
}
function New-PaytmNetworkGuard([string]$SourceDirectory,[bool]$Rehearsal){
 $run=[guid]::NewGuid().ToString('N');$c=Get-PaytmHostContract
 $g=[ordered]@{runId=$run;name=('MarketBrain-Network-Test-'+$run);root=(Join-Path $c.root ('network-'+$run));seconds=$(if($Rehearsal){5}else{180});registered=$false;ruleCreated=$false;removed=$false;taskRemoved=$false}
 # Attach intent before any scheduled-task creation so finally can clean partial setup.
 $report.networkGuards.Add($g);Save-Report
 $null=Assert-PaytmAccountPath $g.root;$null=New-Item -ItemType Directory -Path $g.root
 Set-PaytmAccountDirectoryAcl $g.root (Get-PaytmKeyContract).accountSid
 $source=Join-Path $SourceDirectory 'RunPaytmNetworkCleanup.ps1';$dest=Join-Path $g.root 'cleanup.ps1'
 Copy-Item -LiteralPath $source -Destination $dest
 $hash=(Get-FileHash -LiteralPath $source).Hash
 if((Get-FileHash -LiteralPath $dest).Hash -cne $hash){throw 'NETWORK_CLEANUP_SOURCE_DRIFT'}
 $code='$ErrorActionPreference="Stop"; $p='''+$dest+'''; if((Get-FileHash -LiteralPath $p).Hash -cne '''+$hash+'''){throw ''NETWORK_CLEANUP_HASH''}; & ([scriptblock]::Create([IO.File]::ReadAllText($p))) -RunId '''+$run+''' -WindowSeconds '+$g.seconds
 $g.arguments='-NoLogo -NoProfile -NonInteractive -WindowStyle Hidden -EncodedCommand '+[Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($code))
 if(@(Get-PaytmProbeTask $g.name).Count -or @(Get-PaytmNetworkRule $g.name).Count){throw 'NETWORK_GUARD_ALREADY_EXISTS'}
 $action=New-ScheduledTaskAction -Execute $c.executable -Argument $g.arguments -WorkingDirectory $g.root
 $principal=New-ScheduledTaskPrincipal -UserId 'S-1-5-18' -LogonType ServiceAccount -RunLevel Highest
 $settings=New-ScheduledTaskSettingsSet -MultipleInstances IgnoreNew -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries
 $settings.ExecutionTimeLimit='PT5M'
 $task=New-ScheduledTask -Action $action -Principal $principal -Settings $settings -Trigger (New-ScheduledTaskTrigger -AtStartup) -Description $run
 $null=Register-ScheduledTask -TaskName $g.name -TaskPath '\' -InputObject $task -ErrorAction Stop
 $g.registered=$true;$report.cleanupTasksRegistered++;Save-Report
 $null=Assert-PaytmNetworkGuardTask $g
 # Rehearsal creates a DISABLED rule; independent SYSTEM worker must remove it.
 if($Rehearsal){Add-PaytmNetworkRule $g $false}
 Start-ScheduledTask -TaskName $g.name -TaskPath '\' -ErrorAction Stop
 if($Rehearsal){Wait-PaytmNetworkGuard $g 'REMOVED'}else{Wait-PaytmNetworkGuard $g 'READY'}
 $g
}
function Assert-PaytmNetworkGuardTask($Guard){
 $tasks=@(Get-PaytmProbeTask $Guard.name)
 if($tasks.Count -ne 1){throw 'NETWORK_GUARD_TASK_MISSING'}
 $t=$tasks[0];$a=@($t.Actions);$tr=@($t.Triggers)
 if($t.Description -cne $Guard.runId -or $a.Count -ne 1 -or $a[0].Execute -ine (Get-PaytmHostContract).executable -or $a[0].Arguments -cne $Guard.arguments -or $a[0].WorkingDirectory -ine $Guard.root -or [string]$t.Principal.UserId -cnotin @('SYSTEM','S-1-5-18') -or [string]$t.Principal.LogonType -cne 'ServiceAccount' -or [string]$t.Principal.RunLevel -cne 'Highest' -or $tr.Count -ne 1 -or $tr[0].CimClass.CimClassName -cne 'MSFT_TaskBootTrigger' -or -not $tr[0].Enabled -or -not $t.Settings.Enabled -or [string]$t.Settings.MultipleInstances -cne 'IgnoreNew' -or [Xml.XmlConvert]::ToTimeSpan($t.Settings.ExecutionTimeLimit).TotalSeconds -ne 300){throw 'NETWORK_GUARD_TASK_DRIFT'}
 $t
}
function Wait-PaytmNetworkGuard($Guard,[string]$Phase){
 $clock=[Diagnostics.Stopwatch]::StartNew()
 do{
  $t=Assert-PaytmNetworkGuardTask $Guard;$p=Join-Path $Guard.root 'cleanup.json'
  if(Test-Path -LiteralPath $p){
   $v=Read-PaytmHostJson $p
   if($v.runId -cne $Guard.runId -or $v.systemIdentity -ne $true -or $v.failure){throw 'NETWORK_GUARD_FAILED'}
   if($v.phase -ceq $Phase){
    if($Phase -ceq 'READY'){
     if([string]$t.State -ceq 'Running' -and $v.elapsedSeconds -lt 20){$Guard.ready=$v;return}
    }elseif([string]$t.State -cnotin @('Running','Queued') -and (Get-ScheduledTaskInfo -TaskName $Guard.name -TaskPath '\').LastTaskResult -eq 0 -and $v.ruleRemoved){$Guard.result=$v;return}
   }
  }
  Write-Progress -Activity 'Gateway network recovery' -Status ("Cleanup guard: $Phase, $([int]$clock.Elapsed.TotalSeconds)/30 seconds") -PercentComplete 30
  Start-Sleep -Milliseconds 500
 }while($clock.Elapsed.TotalSeconds -lt 30)
 throw 'NETWORK_GUARD_TIMEOUT'
}
function Add-PaytmNetworkRule($Guard,[bool]$Enabled){
 $lease=[IO.File]::Open((Join-Path $Guard.root 'rule.lock'),'OpenOrCreate','ReadWrite','None')
 try{
 if($Enabled){Wait-PaytmNetworkGuard $Guard READY}
 $report.networkInterruptionAttempted=$report.networkInterruptionAttempted -or $Enabled;Save-Report
 $null=New-NetFirewallRule -PolicyStore PersistentStore -Name $Guard.name -DisplayName $Guard.name -Group 'MarketBrain bounded network test' -Description $Guard.runId -Direction Outbound -Action Block -Enabled $(if($Enabled){'True'}else{'False'}) -Profile Any -Protocol TCP -RemotePort 22 -RemoteAddress '130.250.191.137' -Program 'C:\Windows\System32\OpenSSH\ssh.exe' -ErrorAction Stop
 $Guard.ruleCreated=$true
 foreach($store in @('PersistentStore','ActiveStore')){
  $r=@(Get-PaytmNetworkRule $Guard.name $store)
  if($r.Count -ne 1){throw 'NETWORK_RULE_NOT_EFFECTIVE'}
  Assert-PaytmNetworkRule $r[0] $Guard.runId $Enabled
 }
 }finally{$lease.Dispose()}
}
function Close-PaytmNetworkGuard($Guard){
 $lease=$null;$clock=[Diagnostics.Stopwatch]::StartNew()
 # Serialize manual removal with the independent worker's deadline cleanup.
 if(Test-Path -LiteralPath $Guard.root){
  do{try{$lease=[IO.File]::Open((Join-Path $Guard.root 'rule.lock'),'OpenOrCreate','ReadWrite','None')}catch [IO.IOException]{if($clock.Elapsed.TotalSeconds -gt 30){throw 'NETWORK_CLEANUP_LEASE_TIMEOUT'};Start-Sleep -Milliseconds 250}}while(-not $lease)
 }
 try{
 $rules=@(Get-PaytmNetworkRule $Guard.name)
 foreach($r in $rules){
  if($r.Group -cne 'MarketBrain bounded network test' -or $r.Description -cne $Guard.runId){throw 'NETWORK_RULE_CLEANUP_OWNERSHIP'}
  Remove-NetFirewallRule -InputObject $r -ErrorAction Stop
 }
 if(@(Get-PaytmNetworkRule $Guard.name).Count -or @(Get-PaytmNetworkRule $Guard.name ActiveStore).Count){throw 'NETWORK_RULE_NOT_REMOVED'}
 $Guard.removed=$true
 }finally{if($lease){$lease.Dispose()}}
 if(@(Get-PaytmProbeTask $Guard.name).Count){
  $task=Assert-PaytmNetworkGuardTask $Guard
  [IO.File]::WriteAllText((Join-Path $Guard.root 'release'),'release')
  if([string]$task.State -cnotin @('Running','Queued') -and -not (Test-Path -LiteralPath (Join-Path $Guard.root 'cleanup.json'))){Start-ScheduledTask -TaskName $Guard.name -TaskPath '\' -ErrorAction Stop}
  try{Wait-PaytmNetworkGuard $Guard REMOVED}catch{
   # A failed rehearsal must still release its exact idle task after rule removal.
   # Preserve the failed result; this cleanup does not turn the test into a pass.
   $t=Assert-PaytmNetworkGuardTask $Guard
   $v=Read-PaytmHostJson (Join-Path $Guard.root 'cleanup.json')
   if([string]$t.State -cin @('Running','Queued') -or $v.runId -cne $Guard.runId -or $v.systemIdentity -ne $true -or -not $v.failure){throw}
   $Guard.cleanupWorkerFailure=$v
   $report.cleanupFailure='NETWORK_GUARD_WORKER_FAILED'
  }
  $null=Assert-PaytmNetworkGuardTask $Guard
  Unregister-ScheduledTask -TaskName $Guard.name -TaskPath '\' -Confirm:$false -ErrorAction Stop
  if(@(Get-PaytmProbeTask $Guard.name).Count){throw 'NETWORK_GUARD_TASK_NOT_REMOVED'}
 }
 $Guard.taskRemoved=$true
}
function Wait-PaytmNetworkBackoff($Before,[ValidateRange(1,75)][int]$TimeoutSeconds=75){
 $clock=[Diagnostics.Stopwatch]::StartNew();$first=$null;$ready=$null;$lastKey=''
 $report.networkObservations=[Collections.Generic.List[object]]::new()
 do{
  $task=Get-PaytmOwnedHostTask $Before.installationId
  if([string]$task.State -cne 'Running'){throw 'NETWORK_WORKER_NOT_RUNNING'}
  $v=Read-PaytmHostJson (Join-Path (Get-PaytmHostContract).work 'status.json')
  $ssh=Get-PaytmEvidenceProperty $v lastSshObservation
  $safe=ConvertTo-PaytmWorkerEvidence $v
  $sample=[ordered]@{waitSeconds=[math]::Round($clock.Elapsed.TotalSeconds,3);phase=$v.phase;sequence=$v.sequence;attempts=$v.transportState.attempts;failures=$v.transportState.failures;ssh=(Get-PaytmEvidenceProperty $safe lastSshObservation);sshAttempt=(Get-PaytmEvidenceProperty $safe lastSshAttempt)}
  $report.networkLastObservation=$sample
  $key=$v.phase+':'+$v.transportState.attempts+':'+$v.transportState.failures
  if($key -cne $lastKey){if($report.networkObservations.Count -ge 24){$report.networkObservations.RemoveAt(0)};$report.networkObservations.Add($sample);$lastKey=$key;Save-Report}
  if($v.instanceId -cne $Before.instanceId -or $v.processId -ne $Before.processId -or $v.phase -ceq 'BLOCKED' -or $v.failure -or $v.brokerReady -or $v.ordersEnabled){throw 'NETWORK_WORKER_CHANGED_OR_BLOCKED'}
  # A real replacement connection must fail before authentication. The deliberate
  # kill alone is not network-loss evidence, even if it produces BACKOFF.
  $tcpFailure=(Get-PaytmEvidenceProperty $ssh exited) -eq $true -and (Get-PaytmEvidenceProperty $ssh stderrDrained) -eq $true -and (Get-PaytmEvidenceProperty $ssh authenticated) -eq $false -and (Get-PaytmEvidenceProperty $ssh reason) -ceq 'NETWORK_UNAVAILABLE' -and $sample.sshAttempt -eq $v.transportState.attempts
  if($v.phase -ceq 'BACKOFF' -and $v.transportState.attempts -gt $Before.transportState.attempts -and $v.transportState.failures -gt $Before.transportState.failures -and $tcpFailure){
   Assert-PaytmTransportListener (Get-PaytmTransportListeners)
   if($first -and $v.sequence -gt $first.sequence){Assert-PaytmHostAdvance $first $v;return $v};$first=$v
  }
  if($v.phase -ceq 'TRANSPORT_READY' -and $v.transportState.attempts -gt $Before.transportState.attempts){
   if($ready -and $v.sequence -gt $ready.sequence){Assert-PaytmHostAdvance $ready $v;throw 'NETWORK_BLOCK_INEFFECTIVE'};$ready=$v
  }else{$ready=$null}
  Write-Progress -Activity 'Gateway network recovery' -Status ("$($v.phase), attempts=$($v.transportState.attempts), waiting $([int]$clock.Elapsed.TotalSeconds)/$TimeoutSeconds seconds") -PercentComplete 50
  Start-Sleep -Milliseconds 500
 }while($clock.Elapsed.TotalSeconds -lt $TimeoutSeconds)
 throw 'NETWORK_BACKOFF_NOT_OBSERVED'
}
function Invoke-PaytmNetworkBatch([string]$Id,[string]$SourceDirectory){
 Import-Module NetSecurity -ErrorAction Stop
 $profiles=@(Get-NetFirewallProfile -PolicyStore ActiveStore -ErrorAction Stop)
 if($profiles.Count -ne 3 -or @($profiles|Where-Object {[string]$_.Enabled -cne 'True'}).Count){throw 'NETWORK_FIREWALL_PROFILE_NOT_ENABLED'}
 if(@(Get-ScheduledTask -ErrorAction Stop|Where-Object TaskName -Like 'MarketBrain-Network-Test-*').Count -or @(Get-NetFirewallRule -PolicyStore PersistentStore -ErrorAction Stop|Where-Object Name -Like 'MarketBrain-Network-Test-*').Count){throw 'NETWORK_PREVIOUS_GUARD_REVIEW_REQUIRED'}
 $report.networkGuards=[Collections.Generic.List[object]]::new()
 try{
  Cancellation-Step 'REHEARSE_INDEPENDENT_CLEANUP_WITH_DISABLED_RULE' 25
  $rehearsal=New-PaytmNetworkGuard $SourceDirectory $true;Close-PaytmNetworkGuard $rehearsal
  $report.networkCleanupRehearsalPassed=$true
  $report.before=Wait-PaytmManagedHost $Id TRANSPORT_READY
  Invoke-PaytmApplicationHead 'Before network interruption' $true
  Cancellation-Step 'BLOCK_ONLY_OPENSSH_TO_VPS_AND_OBSERVE_RETRY' 40
  $guard=New-PaytmNetworkGuard $SourceDirectory $false
  Add-PaytmNetworkRule $guard $true
  # Block new outbound TCP connections; inbound rules do not establish this fault.
  # End only the verified existing SSH child so new connections encounter the block.
  Stop-PaytmReviewedChild $report.before
  $report.networkBackoff=Wait-PaytmNetworkBackoff $report.before
  $report.networkLossObserved=$true;Save-Report
  Invoke-PaytmApplicationHead 'Network outage rejects application request' $false
  $active=@(Get-PaytmNetworkRule $guard.name ActiveStore)
  if($active.Count -ne 1){throw 'NETWORK_BLOCK_EXPIRED_BEFORE_OBSERVATION'}
  Assert-PaytmNetworkRule $active[0] $guard.runId $true
  Cancellation-Step 'REMOVE_BLOCK_AND_VERIFY_AUTOMATIC_RECONNECT' 70
  Close-PaytmNetworkGuard $guard
  $report.recovered=Wait-PaytmManagedHost $Id TRANSPORT_READY '' $report.before.childProcessId
  if($report.recovered.instanceId -cne $report.before.instanceId -or $report.recovered.processId -ne $report.before.processId -or $report.recovered.transportState.attempts -le $report.before.transportState.attempts){throw 'NETWORK_RECOVERY_NOT_SAME_WORKER'}
  $v=Invoke-PaytmApplicationHttp 'head'
  if($v.status -cne 'LOCKED' -or $v.bootId -cne $application.BootId){throw 'NETWORK_APPLICATION_AUTHORITY_REPLAYED'}
  $report.noAutomaticRearmPassed=$true
  Invoke-PaytmApplicationHead 'Explicit rearm after network recovery' $true
  $report.networkRecoveryPassed=$true
 }finally{
  foreach($g in $report.networkGuards){if(-not $g.taskRemoved){try{Close-PaytmNetworkGuard $g}catch{$report.cleanupFailure='NETWORK_GUARD_CLEANUP_REVIEW_REQUIRED'}}}
  Save-Report
 }
}
