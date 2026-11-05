#Requires -Version 5.1
[CmdletBinding()]param([string]$StartUtc,[string]$EndUtc,[switch]$LibraryOnly)
$ErrorActionPreference='Stop'
function Get-PaytmAgentService {
 $r=[ordered]@{observedUtc=[DateTime]::UtcNow.ToString('o');querySucceeded=$false;present=$null;state=$null;startMode=$null;processId=$null;exitCode=$null;serviceSpecificExitCode=$null;runsAsLocalSystem=$null;expectedExecutable=$null;errorType=$null}
 try{
  $rows=@(Get-CimInstance -ClassName Win32_Service -Filter "Name='ssh-agent'" -OperationTimeoutSec 10 -ErrorAction Stop)
  if($rows.Count -gt 1){throw 'AGENT_SERVICE_AMBIGUOUS'}
  $r.present=$rows.Count -eq 1
  if($r.present){
   $s=$rows[0]
   $r.state=if($s.State -in @('Running','Stopped','Start Pending','Stop Pending','Paused','Pause Pending','Continue Pending','Unknown')){[string]$s.State}else{'OTHER'}
   $r.startMode=if($s.StartMode -in @('Auto','Manual','Disabled','Boot','System')){[string]$s.StartMode}else{'OTHER'}
   $r.processId=[long]$s.ProcessId;$r.exitCode=[long]$s.ExitCode;$r.serviceSpecificExitCode=[long]$s.ServiceSpecificExitCode
   $r.runsAsLocalSystem=$s.StartName -ieq 'LocalSystem'
   $r.expectedExecutable=([string]$s.PathName).Trim().Trim('"') -ieq 'C:\Windows\System32\OpenSSH\ssh-agent.exe'
   # Used only for exact service-event filtering, never returned as arbitrary text.
   $script:agentDisplayName=[string]$s.DisplayName
  }
  $r.querySucceeded=$true
 }catch{$r.errorType=$_.Exception.GetBaseException().GetType().Name}
 [pscustomobject]$r
}
function ConvertTo-PaytmAgentEvent($Event,[bool]$ServiceOnly){
 $r=[ordered]@{id=[int]$Event.Id;recordId=[long]$Event.RecordId;utc=$Event.TimeCreated.ToUniversalTime().ToString('o')}
 if($ServiceOnly){
  $xml=[xml]$Event.ToXml();$matched=$false;$values=@()
  foreach($node in $xml.SelectNodes('//*[local-name()="EventData"]/*[local-name()="Data"]')){
   $field=[string]$node.GetAttribute('Name');$value=[string]$node.InnerText
   if($field -in @('param1','ServiceName') -and $value -and $value -in @('ssh-agent','OpenSSH Authentication Agent',$script:agentDisplayName)){$matched=$true}
   if($field -in @('param2','param3','ErrorCode','Status')){
    if($value -in @('running','stopped','automatic','demand start','disabled')){$values+=$value.ToLowerInvariant()}
    elseif($value -cmatch '^(?:%%)?[0-9]{1,10}$|^0x[0-9A-Fa-f]{1,8}$'){$values+=$value}
   }
  }
  if(-not $matched){return}
  $r.approvedValues=@($values|Select-Object -Unique)
 }
 # Other channels expose only event ID/time, never messages, paths, users or keys.
 [pscustomobject]$r
}
function Get-PaytmAgentEvents([string]$Start,[string]$End){
 $from=[DateTimeOffset]::Parse($Start,[Globalization.CultureInfo]::InvariantCulture)
 $to=[DateTimeOffset]::Parse($End,[Globalization.CultureInfo]::InvariantCulture)
 if($to -le $from -or ($to-$from).TotalMinutes -gt 30){throw 'AGENT_EVENT_WINDOW_INVALID'}
 foreach($spec in @(
  @{channel='System';provider='Service Control Manager';ids=@(7000,7001,7009,7011,7023,7024,7031,7034,7036,7040);limit=128;service=$true},
  @{channel='OpenSSH/Admin';limit=32;service=$false},
  @{channel='OpenSSH/Operational';limit=32;service=$false},
  @{channel='System';provider='Microsoft-Windows-Kernel-Power';ids=@(42,107,506,507);limit=16;service=$false},
  @{channel='System';provider='Microsoft-Windows-Power-Troubleshooter';ids=@(1);limit=16;service=$false},
  @{channel='System';provider='Microsoft-Windows-Kernel-General';ids=@(1);limit=16;service=$false})){
  $r=[ordered]@{channel=$spec.channel;provider=$spec.provider;enabled=$null;querySucceeded=$false;candidateCount=0;limit=$spec.limit;limitReached=$false;events=@();errorType=$null}
  try{
   $log=Get-WinEvent -ListLog $spec.channel -ErrorAction Stop;$r.enabled=[bool]$log.IsEnabled
   if($r.enabled){
    $filter=@{LogName=$spec.channel;StartTime=$from.UtcDateTime;EndTime=$to.UtcDateTime}
    if($spec.provider){$filter.ProviderName=$spec.provider};if($spec.ids){$filter.Id=$spec.ids}
    $queryErrors=@()
    $events=@(Get-WinEvent -FilterHashtable $filter -MaxEvents $spec.limit -ErrorAction SilentlyContinue -ErrorVariable queryErrors)
    $bad=@($queryErrors|Where-Object {$_.FullyQualifiedErrorId -notlike 'NoMatchingEventsFound,*'})
    if($bad.Count){$r.errorType=$bad[0].Exception.GetBaseException().GetType().Name}else{$r.querySucceeded=$true}
    $r.candidateCount=$events.Count;$r.limitReached=$events.Count -eq $spec.limit
    $r.events=@($events|ForEach-Object {ConvertTo-PaytmAgentEvent $_ $spec.service})
   }
  }catch{$r.errorType=$_.Exception.GetBaseException().GetType().Name}
  [pscustomobject]$r
 }
}
$script:agentDisplayName=$null
if($LibraryOnly){return}
# Do not inherit a PS7-only module path into the inbox PS5 reader.
foreach($name in @('Microsoft.PowerShell.Management','Microsoft.PowerShell.Utility','Microsoft.PowerShell.Diagnostics','CimCmdlets')){
 Import-Module ([IO.Path]::Combine($PSHOME,'Modules',$name,($name+'.psd1'))) -ErrorAction Stop
}
$report=[ordered]@{version=1;readOnly=$true;windowStart=$StartUtc;windowEnd=$EndUtc;serviceBefore=$null;events=@();serviceAfter=$null;historicalCauseEstablished=$false;gatewayAccountSigningTested=$false}
$report.serviceBefore=Get-PaytmAgentService
$report.events=@(Get-PaytmAgentEvents $StartUtc $EndUtc)
$report.serviceAfter=Get-PaytmAgentService
$report|ConvertTo-Json -Depth 8 -Compress
