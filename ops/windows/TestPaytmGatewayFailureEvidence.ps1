#Requires -Version 7.0
$ErrorActionPreference='Stop'
# Load the real production imports, including PaperAccountReadReview's strict
# mode. Only OS boundaries below are substituted; the JSON readers remain real.
foreach($n in @('PaytmGatewayAccount.ps1','PaytmGatewayKeyCustody.ps1','PaytmGatewayScheduledProbe.ps1','PaytmSupervisorHost.ps1','PaytmSupervisorInstallation.ps1','PaytmSupervisorTransport.ps1','PaytmApplicationRoute.ps1','PaytmManagedTransport.ps1','PaytmGatewayRestart.ps1','PaytmGatewayCancellation.ps1','PaytmGatewayFailureEvidence.ps1')){. (Join-Path $PSScriptRoot $n)}
$temp=Join-Path ([IO.Path]::GetTempPath()) ('mb-failure-test-'+[guid]::NewGuid().ToString('N'));$null=New-Item -ItemType Directory -Path $temp
$checks=0;$advance=$false;$taskFailure=$false;$processFailure=$false;$disposed=0
function Check($Ok,$Name){if(-not $Ok){throw "FAILURE_EVIDENCE_$Name"};$script:checks++}
function Assert-PaytmAccountPath($Path){$Path}
function Get-PaytmHostContract {@{root=$temp;work=$temp;name='fixture';executable='fixture-exe'}}
function Get-PaytmProbeTask {@{State='Ready';Settings=@{Enabled=$true}}}
function Assert-PaytmHostTask {if($taskFailure){throw 'Task unknown'}}
function Get-ScheduledTaskInfo {@{LastTaskResult=1;LastRunTime=[DateTime]::UtcNow}}
function Get-Process {
 if($processFailure){throw [UnauthorizedAccessException]::new('PRIVATE_EXCEPTION_TEXT')}
 $v=[pscustomobject]@{SessionId=0;Path='fixture-exe';StartTime=[DateTime]::UtcNow}
 $v|Add-Member -MemberType ScriptMethod -Name Dispose -Value {$script:disposed++};$v
}
function Start-Sleep {
 if($advance){$v=Read-PaytmHostJson (Join-Path $temp 'status.json');$v.sequence++;Write-PaytmHostJson (Join-Path $temp 'status.json') $v}
}
try{
 $raw=@{version=1;processId=100;instanceId=('a'*32);phase='BLOCKED';failure='TRANSPORT_UNKNOWN';sequence=9;observedUtc='2026-11-04T05:00:00Z';ordersEnabled=$false;
  password='DO_NOT_COPY_SECRET';stderr='DO_NOT_COPY_SECRET';details=@{type='RuntimeException';outerType='RuntimeException';line=71;hresult=-1;message='DO_NOT_COPY_SECRET'};
  transportState=@{phase='BLOCKED';reason='UNKNOWN';attempts=15;closedOutageSeconds=452;raw='DO_NOT_COPY_SECRET'}}
 $v=ConvertTo-PaytmWorkerEvidence $raw;$json=$v|ConvertTo-Json -Depth 8
 Check (-not $json.Contains('DO_NOT_COPY_SECRET')) 'UNKNOWN_FIELDS_OMITTED'
 Check ($v.failure -eq 'TRANSPORT_UNKNOWN' -and $v.details.line -eq 71 -and $v.transportState.attempts -eq 15) 'STRUCTURED_CAUSE_RETAINED'
 $raw.details.nativeOperation='TIMEOUT_STOP';$raw.details.cleanupOperation='CLEANUP_STOP';$raw.details.cleanupNativeErrorCode=5
 $v=ConvertTo-PaytmWorkerEvidence $raw
 Check ($v.details.nativeOperation -ceq 'TIMEOUT_STOP' -and $v.details.cleanupOperation -ceq 'CLEANUP_STOP' -and $v.details.cleanupNativeErrorCode -eq 5) 'NATIVE_OPERATION_RETAINED'
 $raw.failure='some URL or password';Check ((ConvertTo-PaytmWorkerEvidence $raw).failure -eq 'UNRECOGNIZED_VALUE_REDACTED') 'UNSAFE_FAILURE_REDACTED';$raw.failure='TRANSPORT_UNKNOWN'
 $file=Join-Path $temp 'status.json'
 $missing=Get-PaytmWorkerEvidenceFile $file;Check ($missing.present -eq $false -and -not $missing.readSucceeded) 'MISSING_DISTINCT'
 [IO.File]::WriteAllText($file,'{broken');$bad=Get-PaytmWorkerEvidenceFile $file;Check ($bad.present -and -not $bad.readSucceeded -and $bad.errorType) 'MALFORMED_DISTINCT'
 [IO.File]::WriteAllText($file,('x'*16385));$bad=Get-PaytmWorkerEvidenceFile $file;Check (-not $bad.readSucceeded -and $bad.length -eq 16385) 'BOUNDED_READ'
 Write-PaytmHostJson $file $raw;Write-PaytmHostJson (Join-Path $temp 'blocked.json') @{failure='TRANSPORT_UNKNOWN';instanceId=('a'*32)}
 Write-PaytmHostJson (Join-Path $temp 'startup-failure.json') @{stage='OBSERVATION_LOOP';failure='HOST_STARTUP_FAILED';details=@{type='RuntimeException';line=119}}
 Write-PaytmHostJson (Join-Path $temp 'control.json') @{mode='LOCKED'};Write-PaytmHostJson (Join-Path $temp 'transport-control.json') @{mode='ENABLED'}
 $before=(Get-FileHash -LiteralPath $file).Hash
 $v=Get-PaytmWorkerFailureEvidence
 Check ($v.readOnly -and -not $v.heartbeatAdvanced -and -not $v.currentHealthEstablished) 'STALE_NOT_HEALTHY'
 Check ($v.files.'blocked.json'.value.failure -eq 'TRANSPORT_UNKNOWN' -and $v.files.'startup-failure.json'.value.details.line -eq 119) 'BOTH_MARKERS'
 Check ($v.controls.'transport-control.json'.value.mode -eq 'ENABLED' -and $v.task.lastResult -eq 1 -and $v.process.exists) 'CONTROL_TASK_PROCESS'
 Check ((Get-FileHash -LiteralPath $file).Hash -eq $before -and $disposed -eq 1) 'PRESERVED_AND_DISPOSED'
 $advance=$true;$v=Get-PaytmWorkerFailureEvidence
 Check ($v.heartbeatAdvanced -and -not $v.currentHealthEstablished) 'ADVANCE_NOT_TLS_ACCEPTANCE'
 $taskFailure=$true;$processFailure=$true;$v=Get-PaytmWorkerFailureEvidence
 Check ($v.task.errorType -and $v.process.errorType -and $null -eq $v.process.exists) 'INACCESSIBLE_NOT_ABSENT'
 Check (-not ($v|ConvertTo-Json -Depth 10).Contains('PRIVATE_EXCEPTION_TEXT')) 'EXCEPTION_TEXT_OMITTED'
 $out=Join-Path $temp 'report.json';Write-PaytmHostJson $out @{workerDiagnostics=$v}
 Check ((Read-PaytmHostJson $out).workerDiagnostics.readOnly) 'BOUNDED_REPORT_ROUNDTRIP'
 $advance=$false;$taskFailure=$false;$processFailure=$false
 # Each collection must keep valid failure markers even when the optional status
 # is missing, broken, sparse or not an object. Exercise actual deserialization.
 $safeFile=[IO.Path]::GetFullPath($file)
 if([IO.Path]::GetDirectoryName($safeFile) -cne [IO.Path]::GetFullPath($temp)){throw 'UNSAFE_STATUS_FIXTURE'}
 Remove-Item -LiteralPath $safeFile
 $v=Get-PaytmWorkerFailureEvidence
 Check (-not $v.files.'status.json'.present -and $null -eq $v.files.'status.json'.value -and $v.files.'blocked.json'.value.failure -eq 'TRANSPORT_UNKNOWN') 'STRICT_MISSING_STATUS_PRESERVES_MARKER'
 foreach($payload in @('{broken','null','42','"scalar"','[]','{}','{"phase":"BLOCKED"}','{"instanceId":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"}','{"processId":100}','{"details":null,"transportState":null}')){
  [IO.File]::WriteAllText($file,$payload)
  $v=Get-PaytmWorkerFailureEvidence
  Check ($v.files.'blocked.json'.readSucceeded -and $v.files.'startup-failure.json'.readSucceeded -and -not $v.heartbeatAdvanced) 'STRICT_PARTIAL_STATUS_DOES_NOT_ABORT'
 }
 $strictStillOn=$false;try{$null=([pscustomobject]@{}).missingProperty}catch{$strictStillOn=$true}
 Check $strictStillOn 'PRODUCTION_STRICT_MODE_REMAINS_ENABLED'
 $minimal='{"failure":"TRANSPORT_UNKNOWN","instanceId":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"}'|ConvertFrom-Json
 Check ((ConvertTo-PaytmWorkerEvidence $minimal).failure -eq 'TRANSPORT_UNKNOWN') 'STRICT_MINIMAL_MARKER'
 Check ($null -eq (Get-PaytmEvidenceProperty $null absent) -and $null -eq (Get-PaytmEvidenceProperty ([pscustomobject]@{}) absent) -and $null -eq (Get-PaytmEvidenceProperty @{} absent)) 'NULL_SAFE_LOOKUPS'
 $ssh=ConvertTo-PaytmWorkerEvidence @{lastSshAttempt=4;lastSshElapsedSeconds=5166;lastSshObservation=@{version=1;exited=$true;stderrDrained=$true;authenticated=$false;reason='NETWORK_UNAVAILABLE';stderrCharacters=101;stderrSha256=('A'*64);tags=@('TCP_CONNECT_UNKNOWN','PRIVATE_TOKEN');raw='PRIVATE_NATIVE_TEXT'}}
 Check ($ssh.lastSshObservation.stderrDrained -and $ssh.lastSshAttempt -eq 4 -and $ssh.lastSshObservation.tags.Count -eq 1) 'SSH_STRUCTURED_EVIDENCE_RETAINED'
 Check (-not ($ssh|ConvertTo-Json -Depth 5).Contains('PRIVATE_')) 'SSH_ARBITRARY_FIELDS_AND_TAGS_DROPPED'
 [pscustomobject]@{status='WORKER_FAILURE_EVIDENCE_PASSED';assertions=$checks;runtimeApisMocked=$true;realBoundedFileReads=$true}|ConvertTo-Json
}finally{
 $resolved=[IO.Path]::GetFullPath($temp);$base=[IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\')+'\'
 if(-not $resolved.StartsWith($base,[StringComparison]::OrdinalIgnoreCase) -or [IO.Path]::GetFileName($resolved) -notmatch '^mb-failure-test-[a-f0-9]{32}$'){throw 'UNSAFE_FIXTURE_CLEANUP'}
 Remove-Item -LiteralPath $resolved -Recurse -Force
}
