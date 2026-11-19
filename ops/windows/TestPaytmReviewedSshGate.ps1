#Requires -Version 7.0
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'PaytmReviewedSshRecovery.ps1')
$root=Join-Path ([IO.Path]::GetTempPath()) ('mb-ssh-gate-'+[guid]::NewGuid().ToString('N'))
$work=Join-Path $root 'work'
function Assert-PaytmAccountPath($p){$p}
function Get-PaytmHostContract {@{root=$root;work=$work;name='fixture'}}
function Get-PaytmOwnedHostTask($id){@{State=$script:taskState}}
function Get-ScheduledTaskInfo {param($TaskName,$TaskPath,$ErrorAction) @{LastTaskResult=1;LastRunTime=[datetime]'2026-11-19T07:00:00Z'}}
function Assert-PaytmHostControl($v,$id){}
function Read-PaytmTransportControl($r,$id){'ENABLED'}
function Read-PaytmHostJson($p){Get-Content -LiteralPath $p -Raw|ConvertFrom-Json}
$checks=0
try {
 $null=New-Item -ItemType Directory -Path $work -Force
 foreach($case in @('pass','instance','sshHash','authenticated','newTag','sequence','taskRunning','control')){
  $script:taskState=if($case -eq 'taskRunning'){'Running'}else{'Ready'}
  $v=@{instanceId='75ecfd57f6874744a83611a856a8b161';failure='TRANSPORT_UNKNOWN';installationId='ea8b91471cf048aa97a0f6b939b355c7';processId=8716;ordersEnabled=$false;phase='BLOCKED';sequence=9319;sessionId=0;lastSshAttempt=13;lastSshObservation=@{reason='UNKNOWN';exited=$true;authenticated=$false;stderrDrained=$true;stderrCharacters=557;tags=@();stderrSha256='4A39CFA7D3593D41AB4AADC1A24976E7F67E6E404FE2CCD8AF68FF9A35F56E8D'}}
  switch($case){
   'instance' {$v.instanceId='new'}
   'sshHash' {$v.lastSshObservation.stderrSha256='changed'}
   'authenticated' {$v.lastSshObservation.authenticated=$true}
   'newTag' {$v.lastSshObservation.tags=@('KEY_DENIED')}
   'sequence' {$v.sequence++}
  }
  foreach($name in @('startup-failure.json','blocked.json','status.json')){$v|ConvertTo-Json -Depth 5|Set-Content -LiteralPath (Join-Path $work $name)}
  @{mode=if($case -eq 'control'){'STOP'}else{'LOCKED'}}|ConvertTo-Json|Set-Content (Join-Path $root 'control.json')
  foreach($name in @('manifest.json','transport-control.json')){'{}'|Set-Content (Join-Path $root $name)}
  $failed=$false
  try{$null=Get-PaytmCurrentRecoverySnapshot}catch{$failed=$true}
  if($failed -ne ($case -ne 'pass')){throw "Unexpected gate outcome: $case"}
  $checks++
 }
 Write-Host "PASS: $checks reviewed incident gate cases"
}finally{
 $full=[IO.Path]::GetFullPath($root);$parent=[IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\')+'\'
 if(-not $full.StartsWith($parent,[StringComparison]::OrdinalIgnoreCase) -or [IO.Path]::GetFileName($full) -notmatch '^mb-ssh-gate-[a-f0-9]{32}$'){throw 'UNSAFE_FIXTURE_CLEANUP'}
 if(Test-Path -LiteralPath $full){Remove-Item -LiteralPath $full -Recurse -Force}
}
