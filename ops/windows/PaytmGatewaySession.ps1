#Requires -Version 7.0
# Read-only session observations. No sign-out, power, task or credential changes.
function Write-PaytmSessionReport([string]$Destination,$Value){
 # Combined prior-phase observations plus failure diagnostics may exceed the
 # 16 KiB checkpoint writer. Keep the shareable report separately bounded.
 $bytes=[Text.Encoding]::UTF8.GetBytes(($Value|ConvertTo-Json -Depth 12 -Compress))
 if($bytes.Length -gt 65536){throw 'SESSION_REPORT_TOO_LARGE'}
 $temporary=$Destination+'.'+[guid]::NewGuid().ToString('N')+'.tmp'
 try{
  $f=[IO.File]::Open($temporary,'CreateNew','Write','None')
  try{$f.Write($bytes,0,$bytes.Length);$f.Flush($true)}finally{$f.Dispose()}
  if([IO.File]::Exists($Destination)){[IO.File]::Replace($temporary,$Destination,[Management.Automation.Language.NullString]::Value)}else{[IO.File]::Move($temporary,$Destination)}
 }finally{if([IO.File]::Exists($temporary)){[IO.File]::Delete($temporary)}}
}
function Get-PaytmInteractiveSession {
 # Native PS5 has the .NET Framework compiler even in minimal PS7 distributions.
 $code=[IO.File]::ReadAllText((Join-Path $PSScriptRoot 'ReadPaytmInteractiveSession.ps1'))
 $encoded=[Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($code))
 $v=Invoke-PaperRuntimeProcess 'C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe' @('-NoLogo','-NoProfile','-NonInteractive','-EncodedCommand',$encoded) $route.Root 25
 if($v.exitCode -ne 0 -or $v.stdout.Length -gt 1024){throw 'SESSION_NATIVE_QUERY_FAILED'}
 $value=$v.stdout|ConvertFrom-Json -ErrorAction Stop
 if($value.userSidHash -cnotmatch '^[A-F0-9]{64}$' -or $value.authenticationId -cnotmatch '^[A-F0-9]{16}$' -or $value.sessionId -le 0){throw 'SESSION_NATIVE_QUERY_INVALID'}
 $value
}
function Assert-PaytmSessionBoundary($Before,$After){
 if($Before.machineHash -cne $After.machineHash -or [DateTimeOffset]$Before.bootUtc -ne [DateTimeOffset]$After.bootUtc){throw 'SESSION_MACHINE_OR_BOOT_CHANGED'}
 if($Before.interactive.userSidHash -cne $After.interactive.userSidHash){throw 'SESSION_DIFFERENT_USER'}
 if($After.interactive.authenticationId -cnotmatch '^[A-F0-9]{16}$' -or $Before.interactive.authenticationId -ceq $After.interactive.authenticationId){throw 'SESSION_NEW_LOGON_NOT_OBSERVED'}
 if($Before.worker.instanceId -cne $After.worker.instanceId -or $Before.worker.processId -ne $After.worker.processId -or [DateTimeOffset]$Before.workerStartUtc -ne [DateTimeOffset]$After.workerStartUtc){throw 'SESSION_BACKGROUND_WORKER_RESTARTED'}
 Assert-PaytmHostAdvance $Before.worker $After.worker
}
function Assert-PaytmSessionCheckpoint($Value){
 if($Value.version -ne 1 -or $Value.runId -cnotmatch '^[a-f0-9]{32}$' -or $Value.nextPhase -cnotin @('AfterLogoff','AfterBoot','Complete')){throw 'SESSION_CHECKPOINT_INVALID'}
 if($Value.reportName -cne ('paytm-gateway-session-'+$Value.runId+'.json')){throw 'SESSION_CHECKPOINT_REPORT_PATH'}
 if($Value.nextPhase -cne 'AfterLogoff' -and $null -eq $Value.afterLogoff){throw 'SESSION_LOGOFF_PROOF_MISSING'}
}
function Assert-PaytmSessionBootBoundary($Before,$After){
 # PS7 JSON can deserialize ISO values to DateTime. Pass invariant UTC strings
 # to the older restart validator instead of culture-dependent implicit text.
 $left=$Before.PSObject.Copy();$right=$After.PSObject.Copy()
 foreach($value in @($left,$right)){
  foreach($field in @('bootUtc','workerStartUtc','collectorStartUtc','taskLastRunUtc')){
   $value.$field=([DateTimeOffset]$value.$field).ToUniversalTime().ToString('o')
  }
 }
 Assert-PaytmRestartBoundary $left $right
 $After|Add-Member taskToWorkerStartSeconds $right.taskToWorkerStartSeconds -Force
}
