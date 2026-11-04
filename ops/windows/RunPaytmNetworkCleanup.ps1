#Requires -Version 5.1
param([Parameter(Mandatory=$true)][ValidatePattern('^[a-f0-9]{32}$')][string]$RunId,
      [ValidateRange(5,180)][int]$WindowSeconds=180)
$ErrorActionPreference='Stop'
if([Security.Principal.WindowsIdentity]::GetCurrent().User.Value -cne 'S-1-5-18'){throw 'NETWORK_CLEANUP_SYSTEM_REQUIRED'}
Import-Module NetSecurity -ErrorAction Stop
$root='C:\ProgramData\MarketBrainPaytmGateway\supervisor-v1\network-'+$RunId
$name='MarketBrain-Network-Test-'+$RunId
function Publish($Value){
 $p=Join-Path $root 'cleanup.json';$tmp=$p+'.'+[guid]::NewGuid().ToString('N')+'.tmp'
 [IO.File]::WriteAllText($tmp,($Value|ConvertTo-Json -Compress),[Text.UTF8Encoding]::new($false))
 if([IO.File]::Exists($p)){[IO.File]::Replace($tmp,$p,[Management.Automation.Language.NullString]::Value)}else{[IO.File]::Move($tmp,$p)}
}
$result=@{runId=$RunId;processId=$PID;systemIdentity=$true;phase='STARTING';elapsedSeconds=0;failure=$null;ruleRemoved=$false}
try{
 # A second launch/boot removes the rule immediately; it never grants a fresh window.
 $marker=Join-Path $root 'started'
 if(-not [IO.File]::Exists($marker)){
  $f=[IO.File]::Open($marker,'CreateNew','Write','None');$f.Dispose()
  $clock=[Diagnostics.Stopwatch]::StartNew()
  do{
   $result.phase='READY';$result.elapsedSeconds=[int]$clock.Elapsed.TotalSeconds;Publish $result
   if([IO.File]::Exists((Join-Path $root 'release'))){break}
   Start-Sleep -Milliseconds 500
  }while($clock.Elapsed.TotalSeconds -lt $WindowSeconds)
 }
 $result.phase='REMOVING';Publish $result
 $lease=$null;$acquire=[Diagnostics.Stopwatch]::StartNew()
 while(-not $lease){
  try{$lease=[IO.File]::Open((Join-Path $root 'rule.lock'),'OpenOrCreate','ReadWrite','None')}catch [IO.IOException]{if($acquire.Elapsed.TotalSeconds -gt 60){throw 'NETWORK_CLEANUP_LEASE_TIMEOUT'};Start-Sleep -Milliseconds 250}
 }
 try{
 $rules=@(Get-NetFirewallRule -PolicyStore PersistentStore -ErrorAction Stop|Where-Object Name -CEQ $name)
 foreach($rule in $rules){
  if($rule.Group -cne 'MarketBrain bounded network test' -or $rule.Description -cne $RunId){throw 'NETWORK_CLEANUP_OWNERSHIP'}
  Remove-NetFirewallRule -InputObject $rule -ErrorAction Stop
 }
 if(@(Get-NetFirewallRule -PolicyStore PersistentStore -ErrorAction Stop|Where-Object Name -CEQ $name).Count){throw 'NETWORK_CLEANUP_RULE_REMAINS'}
 $result.ruleRemoved=$true;$result.phase='REMOVED';Publish $result
 }finally{$lease.Dispose()}
}catch{
 $result.failure=$_.Exception.GetBaseException().GetType().Name;$result.phase='FAILED';Publish $result;exit 1
}
