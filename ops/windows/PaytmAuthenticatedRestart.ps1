. "$PSScriptRoot/PaperRuntimeReview.ps1"
function Invoke-SupervisedRestartDocker([string[]]$Arguments,[int]$Limit=15){
 $exe=(Get-Command docker.exe -CommandType Application|Select-Object -First 1).Source
 $v=Invoke-PaperRuntimeProcess $exe (@('--host','npipe:////./pipe/docker_engine')+$Arguments) $PSScriptRoot $Limit
 if($v.exitCode -ne 0){throw 'SUPERVISED_RESTART_DOCKER_FAILED'}
 if($v.stdout.Length -gt 4096){throw 'SUPERVISED_RESTART_OUTPUT_REJECTED'}
 return $v.stdout.Trim()
}
function Test-PaytmAuthenticatedRestart {
 param([Parameter(Mandatory)][scriptblock]$Request,[Parameter(Mandatory)][int]$SecurityId,[Parameter(Mandatory)][scriptblock]$Checkpoint,
 [scriptblock]$Pause={param($seconds) Start-Sleep -Seconds $seconds})
 $watch=[Diagnostics.Stopwatch]::StartNew()
 $r=[ordered]@{status='RUNNING';passed=$false;authenticatedBeforeRestart=$false;restartAttempted=$false;sameContainer=$false;startChanged=$false;lockedAfterRestart=$false;quoteRejected=$false;elapsedSeconds=0;failure=$null;ordersEnabled=$false}
 try{
  $s=& $Request 'status' $null
  if($s.status -ne 'READ_ACCESS_VERIFIED' -or $s.readAccessVerified -ne $true -or $s.ordersEnabled -ne $false){throw 'SUPERVISED_RESTART_AUTH_REQUIRED'}
  $r.authenticatedBeforeRestart=$true
  $id=Invoke-SupervisedRestartDocker -Arguments @('ps','-q','--filter','label=com.docker.compose.service=marketbrain-service','--filter','status=running')
  if($id -cnotmatch '^[a-f0-9]{12,64}$'){throw 'SUPERVISED_RESTART_CONTAINER_NOT_UNIQUE'}
  $before=Invoke-SupervisedRestartDocker -Arguments @('inspect','--format','{{.Id}} {{.State.StartedAt}}',$id)
  if($before -cnotmatch '^[a-f0-9]{64} [0-9TZ:.-]+$'){throw 'SUPERVISED_RESTART_IDENTITY_REJECTED'}
  $r.restartAttempted=$true;& $Checkpoint $r
  Write-Host '[95%] Restarting only the existing MarketBrain container; checking startup for 120 seconds (a final bounded request may finish later).'
  $null=Invoke-SupervisedRestartDocker -Arguments @('restart','--time','20',$id) -Limit 60
  $ready=$false;$startup=[Diagnostics.Stopwatch]::StartNew()
  for($i=0;$i -lt 24 -and $startup.Elapsed.TotalSeconds -lt 120;$i++){
   try{$s=& $Request 'status' $null;$ready=$true;break}catch{}
   Write-Progress -Activity 'Authenticated restart' -PercentComplete ([int](100*$i/24)) -Status "Application startup check $($i+1)/24"
   & $Pause 5
  }
  if(-not $ready){throw 'SUPERVISED_RESTART_APPLICATION_TIMEOUT'}
  if($s.status -ne 'LOCKED' -or $s.readAccessVerified -ne $false -or $s.ordersEnabled -ne $false){throw 'SUPERVISED_RESTART_SESSION_SURVIVED'}
  $r.lockedAfterRestart=$true
  $after=Invoke-SupervisedRestartDocker -Arguments @('inspect','--format','{{.Id}} {{.State.StartedAt}}',$id)
  if($after -cnotmatch '^[a-f0-9]{64} [0-9TZ:.-]+$'){throw 'SUPERVISED_RESTART_IDENTITY_REJECTED'}
  $r.sameContainer=($before.Split(' ')[0] -ceq $after.Split(' ')[0]);$r.startChanged=($before.Split(' ')[1] -cne $after.Split(' ')[1])
  if(-not $r.sameContainer -or -not $r.startChanged){throw 'SUPERVISED_RESTART_NOT_VERIFIED'}
  $q=& $Request 'quote' @{securityId=$SecurityId}
  if($q.status -ne 'SUPERVISED_SESSION_LOCKED' -or $q.fresh -ne $false -or $q.ordersEnabled -ne $false){throw 'SUPERVISED_RESTART_QUOTE_NOT_REJECTED'}
  $r.quoteRejected=$true;$r.passed=$true;$r.status='AUTHENTICATED_RESTART_PASSED_RELOGIN_PENDING'
 }catch{$r.status='REVIEW_REQUIRED';$r.failure=if($_.Exception.Message -cmatch '^SUPERVISED_[A-Z_]+$'){$_.Exception.Message}else{'SUPERVISED_RESTART_FAILED'}}
 finally{$r.elapsedSeconds=$watch.Elapsed.TotalSeconds;& $Checkpoint $r;Write-Progress -Activity 'Authenticated restart' -Completed}
 return $r
}
