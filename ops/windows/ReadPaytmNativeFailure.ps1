#Requires -Version 5.1
[CmdletBinding()]param([string]$StartUtc,[string]$EndUtc,[switch]$LibraryOnly)
$ErrorActionPreference='Stop'
function ConvertTo-PaytmNativeEvent($Event){
 $xml=[xml]$Event.ToXml()
 # Never copy event messages, command lines, arbitrary paths or identity data.
 $labels=@();$codes=@();$processIds=@()
 foreach($node in $xml.SelectNodes('//*[local-name()="EventData"]/*[local-name()="Data"]')){
  $text=[string]$node.InnerText
  foreach($name in @('curl.exe','powershell.exe','ssh.exe','native.dll')){
   if($text -match ('(?i)(?:^|[\\/\s"''])(?:'+[regex]::Escape($name)+')(?:$|[\s"''])')){$labels+=$name}
  }
  $field=[string]$node.GetAttribute('Name')
  if($field -cin @('Status','ErrorCode','StatusCode') -and $text -cmatch '^(0x[0-9A-Fa-f]{1,8}|[0-9]{1,10})$'){$codes+=$text}
  if($field -cin @('ProcessId','ProcessID') -and $text -cmatch '^[0-9]{1,10}$'){$processIds+=$text}
 }
 [pscustomobject]@{id=[int]$Event.Id;recordId=[long]$Event.RecordId;utc=$Event.TimeCreated.ToUniversalTime().ToString('o');
  matchedFileNames=@($labels|Select-Object -Unique);numericCodes=@($codes|Select-Object -Unique);processIds=@($processIds|Select-Object -Unique)}
}
function Get-PaytmNativePolicyEvents([string]$Start,[string]$End){
 $from=[DateTimeOffset]::Parse($Start);$to=[DateTimeOffset]::Parse($End)
 if($to -le $from -or ($to-$from).TotalMinutes -gt 10){throw 'NATIVE_EVENT_WINDOW_INVALID'}
 $results=@()
 foreach($spec in @(
  @{channel='Microsoft-Windows-AppLocker/EXE and DLL';ids=@(8003,8004)},
  @{channel='Microsoft-Windows-CodeIntegrity/Operational';ids=@(3033,3076,3077)},
  @{channel='Microsoft-Windows-Windows Defender/Operational';ids=@(1116,1117,1121,1122)})){
  $row=[ordered]@{channel=$spec.channel;enabled=$null;querySucceeded=$false;limit=32;limitReached=$false;events=@();errorType=$null}
  try{
   $log=Get-WinEvent -ListLog $spec.channel -ErrorAction Stop;$row.enabled=[bool]$log.IsEnabled
   if($row.enabled){
    $queryErrors=@()
    $events=@(Get-WinEvent -FilterHashtable @{LogName=$spec.channel;Id=$spec.ids;StartTime=$from.UtcDateTime;EndTime=$to.UtcDateTime} -MaxEvents 32 -ErrorAction SilentlyContinue -ErrorVariable queryErrors)
    $bad=@($queryErrors|Where-Object {$_.FullyQualifiedErrorId -notlike 'NoMatchingEventsFound,*'})
    if($bad.Count){$row.errorType=$bad[0].Exception.GetBaseException().GetType().Name}
    else{$row.querySucceeded=$true}
    $row.limitReached=$events.Count -eq 32
    $row.events=@($events|ForEach-Object {ConvertTo-PaytmNativeEvent $_})
   }
  }catch{$row.errorType=$_.Exception.GetBaseException().GetType().Name}
  $results+=[pscustomobject]$row
 }
 $results
}
function Initialize-PaytmNativeModules {
 # A PS7 parent can supply a PSModulePath unsuitable for Windows PowerShell.
 # Resolve inbox manifests from this child runtime, never from inherited search paths.
 foreach($name in @('Microsoft.PowerShell.Management','Microsoft.PowerShell.Utility','Microsoft.PowerShell.Security')){
  Import-Module -Name ([IO.Path]::Combine($PSHOME,'Modules',$name,($name+'.psd1'))) -ErrorAction Stop -Scope Global
 }
}
function Get-PaytmNativeFileMetadata([string]$Path){
 $r=[ordered]@{fileName=[IO.Path]::GetFileName($Path);present=$false;sha256=$null;length=$null;version=$null;signatureStatus=$null;accessSddl=$null;stage='MODULE_IMPORT';errorType=$null}
 try{
  Initialize-PaytmNativeModules
  $r.stage='FILE_LOOKUP'
  $r.present=Test-Path -LiteralPath $Path -PathType Leaf
  if($r.present){
   $item=Get-Item -LiteralPath $Path;$r.length=$item.Length;$r.stage='HASH';$r.sha256=(Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash
   $r.stage='VERSION'
   $version=[string]$item.VersionInfo.FileVersion;if($version -cmatch '^[A-Za-z0-9 ._()-]{1,80}$'){$r.version=$version}
   $r.stage='SIGNATURE'
   $r.signatureStatus=[string](Get-AuthenticodeSignature -LiteralPath $Path).Status
   $r.stage='ACCESS_DESCRIPTOR'
   $sddl=(Get-Acl -LiteralPath $Path).GetSecurityDescriptorSddlForm([Security.AccessControl.AccessControlSections]::Access)
   if($sddl.Length -le 8192){$r.accessSddl=$sddl}else{throw 'NATIVE_ACL_TOO_LARGE'}
   $r.stage='COMPLETE'
  }
 }catch{$r.errorType=$_.Exception.GetBaseException().GetType().Name}
 [pscustomobject]$r
}
function Invoke-PaytmNativeVersionProbe {
 # This is only the controller identity, not the gateway task identity.
 # --version neither opens the gateway nor contacts a broker.
 $r=[ordered]@{identityScope='CONTROLLER_NOT_GATEWAY_ACCOUNT';arguments='--version';stage='START';started=$false;exitCode=$null;timedOut=$false;errorType=$null;nativeErrorCode=$null;outputCharacters=0;stderrCharacters=0}
 $p=[Diagnostics.Process]::new()
 try{
  $p.StartInfo.FileName='C:\Windows\System32\curl.exe';$p.StartInfo.Arguments='--version';$p.StartInfo.UseShellExecute=$false;$p.StartInfo.CreateNoWindow=$true
  $p.StartInfo.RedirectStandardOutput=$true;$p.StartInfo.RedirectStandardError=$true
  $r.started=$p.Start();if(-not $r.started){throw 'NATIVE_VERSION_NOT_STARTED'}
  $out=$p.StandardOutput.ReadToEndAsync();$err=$p.StandardError.ReadToEndAsync();$r.stage='WAIT'
  if(-not $p.WaitForExit(5000)){$r.timedOut=$true;$r.stage='STOP';$p.Kill();if(-not $p.WaitForExit(3000)){throw 'NATIVE_VERSION_STOP_FAILED'}}
  $r.stage='DRAIN';if(-not $out.Wait(3000) -or -not $err.Wait(3000)){throw 'NATIVE_VERSION_OUTPUT_TIMEOUT'}
  $r.outputCharacters=$out.Result.Length;$r.stderrCharacters=$err.Result.Length;$r.exitCode=$p.ExitCode;$r.stage='COMPLETE'
 }catch{
  $base=$_.Exception.GetBaseException();$r.errorType=$base.GetType().Name
  if($base -is [ComponentModel.Win32Exception]){$r.nativeErrorCode=$base.NativeErrorCode}
 }finally{
  if($r.started){try{if(-not $p.HasExited){$p.Kill();$null=$p.WaitForExit(3000)}}catch{}}
  $p.Dispose()
 }
 [pscustomobject]$r
}
if($LibraryOnly){return}
$report=[ordered]@{version=1;readOnly=$true;windowStart=$StartUtc;windowEnd=$EndUtc;policyEvents=@();files=@();versionProbe=$null}
$report.policyEvents=@(Get-PaytmNativePolicyEvents $StartUtc $EndUtc)
foreach($path in @('C:\Windows\System32\curl.exe','C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe')){$report.files+=Get-PaytmNativeFileMetadata $path}
$report.versionProbe=Invoke-PaytmNativeVersionProbe
$report|ConvertTo-Json -Depth 8 -Compress
