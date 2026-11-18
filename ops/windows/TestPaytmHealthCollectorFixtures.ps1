#Requires -Version 5.1
$ErrorActionPreference='Stop';Set-StrictMode -Version Latest
foreach($n in @('PaytmTimeServiceRepair.ps1','PaytmLiveHealthCollector.ps1','PaytmHealthCollectorCore.ps1')){. (Join-Path $PSScriptRoot $n)}
$script:case='good';$script:submits=@();$count=0;$boot='aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'
function Check([bool]$Ok){if(-not $Ok){throw ('COLLECTOR_FIXTURE_FAILED_'+$script:case)};$script:count++}
function Get-CollectorWindowsService {@{state='Running';startType=2}}
function Invoke-PaytmTimeRepairNative($Tool,$Arguments,$Seconds){
 if($script:case -eq 'accessDenied'){return @{exitCode=5;output='Access denied (0x80070005).'}}
 if($Arguments -eq '/query /source'){return @{output='time.windows.com';exitCode=0}}
 $age=if($script:case -eq 'stale'){99999}else{1}
 @{exitCode=0;output="Leap Indicator: 0`nStratum: 3`nLast Sync Error: 0`nTime since Last Good Sync Time: ${age}s`nPoll Interval: 6 (64s)"}
}
function Invoke-PaytmCustodyNative($Tool,$Arguments,$Seconds){
 if($Tool -ne 'ssh.exe' -or $Seconds -ne 3 -or $Arguments -notcontains 'ConnectTimeout=2'){throw 'UNBOUNDED_SSH'}
 $nonce=$Arguments[-1].Split(' ')[1];if($script:case -eq 'nonce'){$nonce='bad'}
 @{ExitCode=0;StoppedByRunner=$false;Stdout=('MB_CLOCK_V1|'+$nonce+'|'+[DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()+'|yes')}
}
function Invoke-CollectorTransport {@{tlsVerified=($script:case -ne 'tls');httpStatus=503;diagnostic=@{exitCode=$(if($script:case -eq 'tls'){7}else{0});stderr=$(if($script:case -eq 'tls'){'Failed to connect to proxy'}else{''});stdout='503|127.0.0.1';timedOut=$false}}}
function Invoke-CollectorHttp($Token,$Command,$Body){
 if($Command -eq 'clock'){return @{clockContractVersion='HEALTH_CLOCK_V1';bootId=$(if($script:case -eq 'boot'){'wrong'}else{$boot});observedEpochMillis=[DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds();accepted=$false;ordersEnabled=$false}}
 if($Command -eq 'challenge'){return @{healthContractVersion='SERVER_TRANSPORT_V2';bootId=$boot;ordersEnabled=$false;accepted=$false;status='CHALLENGE';validForSeconds=10;challenge='bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb'}}
 $script:submits+=,$Body
 $accepted=[bool]($Body.synchronizedClock -and $Body.transportHealthy -and $script:case -ne 'serverReject')
 @{healthContractVersion='SERVER_TRANSPORT_V2';bootId=$boot;ordersEnabled=$false;accepted=$accepted;status=$(if($accepted){'HEALTH_RECORDED_EXPLICIT_ARM_REQUIRED'}else{'UNHEALTHY_AND_LOCKED'})}
}
$sshArgs=@('ConnectTimeout=15','marketbrain-health@130.250.191.137','marketbrain-clock placeholder')
foreach($script:case in @('good','stale','nonce','tls','boot','serverReject','accessDenied')){
 $r=Invoke-CollectorCycle 'fixture' $sshArgs $boot
 Check ($r.accepted -eq ($script:case -eq 'good'))
 if($script:case -notin @('good','serverReject')){Check (-not $r.healthySubmitted -and $script:submits[-1].lowerOffsetSeconds -eq 0 -and $script:submits[-1].upperOffsetSeconds -eq 0)}
 if($script:case -eq 'accessDenied'){Check ($r.diagnostics.windowsStatus.exitCode -eq 5 -and $r.diagnostics.windowsStatus.output -match 'Access denied')}
 if($script:case -eq 'tls'){Check ($r.diagnostics.transport.diagnostic.exitCode -eq 7 -and $r.diagnostics.transport.diagnostic.stderr -match 'proxy')}
 if($script:case -eq 'good'){Check ($r.diagnostics.vpsBounds.elapsedSeconds -ge 0 -and $r.diagnostics.javaBounds.wallMovementSeconds -ge 0)}
}
Check ((Limit-CollectorDiagnostic ('x'*5000)).Length -eq 512)
$script:case='tls';$saved=Invoke-CollectorCycle 'fixture' $sshArgs $boot
$wire=@{worker=@{collectorRounds=@($saved)}}|ConvertTo-Json -Depth 12 -Compress
$decoded=$wire|ConvertFrom-Json
Check ($decoded.worker.collectorRounds[0].diagnostics.transport.diagnostic.exitCode -eq 7)
# Worst escaped native excerpts fit the collector read limit with 8 KiB spare
# for existing identity/clock/task metadata. Do not revert to unbounded report reads.
$worst=([string][char]0)*512
$diag=@{windowsStatus=@{output=$worst};windowsSource=@{output=$worst};transport=@{diagnostic=@{stdout=$worst;stderr=$worst}}}
$wire=@{collectorRounds=@(@{diagnostics=$diag},@{diagnostics=$diag},@{diagnostics=$diag})}|ConvertTo-Json -Depth 8 -Compress
Check (([Text.Encoding]::UTF8.GetByteCount($wire)+8192) -lt 49152)
$r=Invoke-CollectorCycle 'fixture' $sshArgs $boot -Revoke;Check ($r.revoked -and -not $r.healthySubmitted)
$now=[DateTimeOffset]::UtcNow
Check (-not (Get-CollectorBounds $now $now 3 $now.ToUnixTimeMilliseconds()).usable)
Check (-not (Get-CollectorBounds $now ($now.AddSeconds(-1)) 0 $now.ToUnixTimeMilliseconds()).usable)
Check (-not (Test-PaytmFinite ([double]::NaN)))
Check (-not (Test-PaytmFinite ([double]::PositiveInfinity)))
$bad=@{healthContractVersion='SERVER_TRANSPORT_V2';bootId=$boot;ordersEnabled=$true;accepted=$false};$caught=$false
try{Assert-CollectorReceipt $bad $boot}catch{$caught=$true};Check $caught
Write-Host "PASS: $count collector checks; real assessment and cycle orchestration, mocked OS/SSH/HTTP. No publication or external calls."
