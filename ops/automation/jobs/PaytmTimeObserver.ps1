#requires -Version 7.5
param([Parameter(Mandatory)][string]$ResultPath,[ValidateSet('Observe','Apply','FailureFixture')][string]$Mode='Observe')
$timeAccountContract = 'IyBQUzUtY29tcGF0aWJsZSByZWFkLW9ubHkgdGltZSBvYnNlcnZhdGlvbiBjb250cmFjdC4gTm8gYWN0aW9ucyBvbiBpbXBvcnQuDQpmdW5jdGlvbiBHZXQtVGltZU9ic2VydmF0aW9uQm9vdElkIHsNCiAgICAjIFN0YWJsZSBhY3Jvc3MgdXNlcnMvcHJvY2Vzc2VzOyBjaGFuZ2VzIGFmdGVyIGEgV2luZG93cyByZXN0YXJ0Lg0KICAgIChHZXQtQ2ltSW5zdGFuY2UgV2luMzJfT3BlcmF0aW5nU3lzdGVtIC1FcnJvckFjdGlvbiBTdG9wKS5MYXN0Qm9vdFVwVGltZS5Ub1VuaXZlcnNhbFRpbWUoKS5Ub1N0cmluZygnbycpDQp9DQpmdW5jdGlvbiBBc3NlcnQtVGltZU9ic2VydmF0aW9uQWNsKFtzdHJpbmddJFBhdGgpIHsNCiAgICBpZigoR2V0LUl0ZW0gLUxpdGVyYWxQYXRoICRQYXRoIC1Gb3JjZSkuQXR0cmlidXRlcyAtYmFuZCBbSU8uRmlsZUF0dHJpYnV0ZXNdOjpSZXBhcnNlUG9pbnQpe3Rocm93ICdUSU1FX09CU0VSVkVSX1JFUEFSU0UnfQ0KICAgICRhY2w9R2V0LUFjbCAtTGl0ZXJhbFBhdGggJFBhdGgNCiAgICAkdHJ1c3RlZD1AKCdTLTEtNS0xOCcsJ1MtMS01LTMyLTU0NCcpDQogICAgaWYoJGFjbC5HZXRPd25lcihbU2VjdXJpdHkuUHJpbmNpcGFsLlNlY3VyaXR5SWRlbnRpZmllcl0pLlZhbHVlIC1ub3RpbiAkdHJ1c3RlZCl7dGhyb3cgJ1RJTUVfT0JTRVJWRVJfT1dORVInfQ0KICAgICR3cml0ZT1bU2VjdXJpdHkuQWNjZXNzQ29udHJvbC5GaWxlU3lzdGVtUmlnaHRzXTo6V3JpdGUgLWJvciBbU2VjdXJpdHkuQWNjZXNzQ29udHJvbC5GaWxlU3lzdGVtUmlnaHRzXTo6RGVsZXRlIC1ib3IgW1NlY3VyaXR5LkFjY2Vzc0NvbnRyb2wuRmlsZVN5c3RlbVJpZ2h0c106OkRlbGV0ZVN1YmRpcmVjdG9yaWVzQW5kRmlsZXMgLWJvciBbU2VjdXJpdHkuQWNjZXNzQ29udHJvbC5GaWxlU3lzdGVtUmlnaHRzXTo6Q2hhbmdlUGVybWlzc2lvbnMgLWJvciBbU2VjdXJpdHkuQWNjZXNzQ29udHJvbC5GaWxlU3lzdGVtUmlnaHRzXTo6VGFrZU93bmVyc2hpcA0KICAgIGZvcmVhY2goJGFjZSBpbiAkYWNsLkdldEFjY2Vzc1J1bGVzKCR0cnVlLCR0cnVlLFtTZWN1cml0eS5QcmluY2lwYWwuU2VjdXJpdHlJZGVudGlmaWVyXSkpew0KICAgICAgICBpZigkYWNlLkFjY2Vzc0NvbnRyb2xUeXBlIC1lcSAnQWxsb3cnIC1hbmQgKCRhY2UuRmlsZVN5c3RlbVJpZ2h0cyAtYmFuZCAkd3JpdGUpIC1hbmQgJGFjZS5JZGVudGl0eVJlZmVyZW5jZS5WYWx1ZSAtbm90aW4gJHRydXN0ZWQpe3Rocm93ICdUSU1FX09CU0VSVkVSX1dSSVRBQkxFJ30NCiAgICB9DQp9DQpmdW5jdGlvbiBDb252ZXJ0RnJvbS1UaW1lT2JzZXJ2YXRpb24oJFZhbHVlLFtzdHJpbmddJEJvb3RJZCxbbG9uZ10kTm93VGlja3MsW2xvbmddJEZyZXF1ZW5jeSkgew0KICAgIGlmKCRWYWx1ZS52ZXJzaW9uIC1uZSAxIC1vciAkVmFsdWUuYm9vdElkIC1jbmUgJEJvb3RJZCAtb3IgJFZhbHVlLmZyZXF1ZW5jeSAtbmUgJEZyZXF1ZW5jeSAtb3IgJFZhbHVlLnNlcXVlbmNlIC1sdCAxKXt0aHJvdyAnVElNRV9PQlNFUlZFUl9JREVOVElUWSd9DQogICAgaWYoJFZhbHVlLnN0YXJ0VGlja3MgLWlzbm90IFtsb25nXSAtb3IgJFZhbHVlLmVuZFRpY2tzIC1pc25vdCBbbG9uZ10gLW9yICRWYWx1ZS5zdGFydFRpY2tzIC1ndCAkVmFsdWUuZW5kVGlja3MgLW9yICRWYWx1ZS5lbmRUaWNrcyAtZ3QgJE5vd1RpY2tzKXt0aHJvdyAnVElNRV9PQlNFUlZFUl9USU1JTkcnfQ0KICAgICRhZ2U9KCROb3dUaWNrcy0kVmFsdWUuc3RhcnRUaWNrcykvW2RvdWJsZV0kRnJlcXVlbmN5DQogICAgaWYoJGFnZSAtbHQgMCAtb3IgJGFnZSAtZ3QgOCl7dGhyb3cgJ1RJTUVfT0JTRVJWRVJfU1RBTEUnfQ0KICAgIGlmKCRWYWx1ZS5zdGF0dXMuZXhpdENvZGUgLW5lIDAgLW9yICRWYWx1ZS5zb3VyY2UuZXhpdENvZGUgLW5lIDAgLW9yICRWYWx1ZS5zZXJ2aWNlLnN0YXRlIC1jbmUgJ1J1bm5pbmcnIC1vciAkVmFsdWUuc2VydmljZS5zdGFydFR5cGUgLW5lIDIpe3Rocm93ICdUSU1FX09CU0VSVkVSX1VOSEVBTFRIWSd9DQogICAgaWYoJFZhbHVlLnN0YXR1cy5vdXRwdXQgLWlzbm90IFtzdHJpbmddIC1vciAkVmFsdWUuc291cmNlLm91dHB1dCAtaXNub3QgW3N0cmluZ10gLW9yICRWYWx1ZS5zdGF0dXMub3V0cHV0Lkxlbmd0aCAtZ3QgMTIwMDAgLW9yICRWYWx1ZS5zb3VyY2Uub3V0cHV0Lkxlbmd0aCAtZ3QgMTAyNCl7dGhyb3cgJ1RJTUVfT0JTRVJWRVJfRk9STUFUJ30NCiAgICAjIEFkZCBzbmFwc2hvdCBhZ2UgdG8gdGhlIHJlcG9ydGVkIHN5bmMgYWdlOyBuZXZlciBtYWtlIG9sZCBldmlkZW5jZSB5b3VuZ2VyLg0KICAgICRwYXR0ZXJuPScoP2ltKV4oVGltZSBzaW5jZSBMYXN0IEdvb2QgU3luYyBUaW1lOlxzKikoWzAtOV0rKD86XC5bMC05XSspPykoc1xzKikkJw0KICAgICRtPVtyZWdleF06Ok1hdGNoKCRWYWx1ZS5zdGF0dXMub3V0cHV0LCRwYXR0ZXJuKQ0KICAgIGlmKC1ub3QgJG0uU3VjY2Vzcyl7dGhyb3cgJ1RJTUVfT0JTRVJWRVJfU1lOQ19BR0UnfQ0KICAgICRzZWNvbmRzPVtkb3VibGVdOjpQYXJzZSgkbS5Hcm91cHNbMl0uVmFsdWUsW0dsb2JhbGl6YXRpb24uQ3VsdHVyZUluZm9dOjpJbnZhcmlhbnRDdWx0dXJlKSskYWdlDQogICAgJG91dHB1dD0kVmFsdWUuc3RhdHVzLm91dHB1dC5SZW1vdmUoJG0uR3JvdXBzWzJdLkluZGV4LCRtLkdyb3Vwc1syXS5MZW5ndGgpLkluc2VydCgkbS5Hcm91cHNbMl0uSW5kZXgsJHNlY29uZHMuVG9TdHJpbmcoJ0Y2JyxbR2xvYmFsaXphdGlvbi5DdWx0dXJlSW5mb106OkludmFyaWFudEN1bHR1cmUpKQ0KICAgIFtwc2N1c3RvbW9iamVjdF1Ae3N0YXR1cz1Ae2V4aXRDb2RlPTA7b3V0cHV0PSRvdXRwdXR9O3NvdXJjZT0kVmFsdWUuc291cmNlO3NlcnZpY2U9JFZhbHVlLnNlcnZpY2U7YWdlU2Vjb25kcz0kYWdlO3NlcXVlbmNlPSRWYWx1ZS5zZXF1ZW5jZX0NCn0NCmZ1bmN0aW9uIENvbnZlcnRGcm9tLVRpbWVPYnNlcnZhdGlvbkpzb24oW3N0cmluZ10kSnNvbikgew0KICAgICMgUFM3IG90aGVyd2lzZSBjb2VyY2VzIElTTyBib290IElEcyBpbnRvIERhdGVUaW1lLCB1bmxpa2UgdGhlIFBTNSBwcm9kdWNlci4NCiAgICBpZigkUFNWZXJzaW9uVGFibGUuUFNWZXJzaW9uIC1nZSBbdmVyc2lvbl0nNy41Jyl7Q29udmVydEZyb20tSnNvbiAtSW5wdXRPYmplY3QgJEpzb24gLURhdGVLaW5kIFN0cmluZ31lbHNle0NvbnZlcnRGcm9tLUpzb24gLUlucHV0T2JqZWN0ICRKc29ufQ0KfQ0KZnVuY3Rpb24gUmVhZC1UaW1lT2JzZXJ2YXRpb25GaWxlT25jZShbc3RyaW5nXSRQYXRoKSB7DQogICAgQXNzZXJ0LVRpbWVPYnNlcnZhdGlvbkFjbCAkUGF0aA0KICAgICRzdHJlYW09W0lPLkZpbGVdOjpPcGVuKCRQYXRoLCdPcGVuJywnUmVhZCcsKFtJTy5GaWxlU2hhcmVdOjpSZWFkV3JpdGUgLWJvciBbSU8uRmlsZVNoYXJlXTo6RGVsZXRlKSkNCiAgICB0cnl7aWYoJHN0cmVhbS5MZW5ndGggLWd0IDE2Mzg0KXt0aHJvdyAnVElNRV9PQlNFUlZFUl9TSVpFJ307JHJlYWRlcj1bSU8uU3RyZWFtUmVhZGVyXTo6bmV3KCRzdHJlYW0pO3RyeXskYnVmZmVyPVtjaGFyW11dOjpuZXcoMTYzODUpOyRuPSRyZWFkZXIuUmVhZEJsb2NrKCRidWZmZXIsMCwxNjM4NSk7aWYoJG4gLWd0IDE2Mzg0KXt0aHJvdyAnVElNRV9PQlNFUlZFUl9TSVpFJ307cmV0dXJuIENvbnZlcnRGcm9tLVRpbWVPYnNlcnZhdGlvbkpzb24gKFtzdHJpbmddOjpuZXcoJGJ1ZmZlciwwLCRuKSl9ZmluYWxseXskcmVhZGVyLkRpc3Bvc2UoKX19ZmluYWxseXskc3RyZWFtLkRpc3Bvc2UoKX0NCn0NCmZ1bmN0aW9uIFJlYWQtVGltZU9ic2VydmF0aW9uRmlsZShbc3RyaW5nXSRQYXRoKSB7DQogICAgZm9yKCRhdHRlbXB0PTA7JGF0dGVtcHQgLWx0IDM7JGF0dGVtcHQrKyl7DQogICAgICAgIHRyeXtyZXR1cm4gUmVhZC1UaW1lT2JzZXJ2YXRpb25GaWxlT25jZSAkUGF0aH1jYXRjaHsNCiAgICAgICAgICAgICRjYXVzZT0kXy5FeGNlcHRpb24uR2V0QmFzZUV4Y2VwdGlvbigpDQogICAgICAgICAgICBpZigoJGNhdXNlIC1pc25vdCBbSU8uSU9FeGNlcHRpb25dIC1hbmQgJGNhdXNlIC1pc25vdCBbTWFuYWdlbWVudC5BdXRvbWF0aW9uLkl0ZW1Ob3RGb3VuZEV4Y2VwdGlvbl0pIC1vciAkYXR0ZW1wdCAtZXEgMil7dGhyb3d9DQogICAgICAgICAgICBTdGFydC1TbGVlcCAtTWlsbGlzZWNvbmRzIDI1DQogICAgICAgIH0NCiAgICB9DQp9DQpmdW5jdGlvbiBSZWFkLVRpbWVPYnNlcnZhdGlvbk9uY2Ugew0KICAgICRyb290PSdDOlxQcm9ncmFtRGF0YVxNYXJrZXRCcmFpblBheXRtSGVhbHRoXHRpbWUtb2JzZXJ2ZXItdjEnOyRwYXRoPUpvaW4tUGF0aCAkcm9vdCAnc25hcHNob3QuanNvbicNCiAgICBmb3JlYWNoKCRwIGluIEAoJ0M6XFByb2dyYW1EYXRhXE1hcmtldEJyYWluUGF5dG1IZWFsdGgnLCRyb290KSl7QXNzZXJ0LVRpbWVPYnNlcnZhdGlvbkFjbCAkcH0NCiAgICAkdj1SZWFkLVRpbWVPYnNlcnZhdGlvbkZpbGVPbmNlICRwYXRoDQogICAgQ29udmVydEZyb20tVGltZU9ic2VydmF0aW9uICR2IChHZXQtVGltZU9ic2VydmF0aW9uQm9vdElkKSAoW0RpYWdub3N0aWNzLlN0b3B3YXRjaF06OkdldFRpbWVzdGFtcCgpKSAoW0RpYWdub3N0aWNzLlN0b3B3YXRjaF06OkZyZXF1ZW5jeSkNCn0NCg0KZnVuY3Rpb24gUmVhZC1UaW1lT2JzZXJ2YXRpb24gew0KICAgICMgU25hcHNob3QgcmVwbGFjZW1lbnQgY2FuIGJyaWVmbHkgaW52YWxpZGF0ZSBhIHBhdGggbG9va3VwLiBSZXRyeSBvbmx5IEkvTw0KICAgICMgbG9va3VwIGZhaWx1cmVzLCBuZXZlciBBQ0wgcG9saWN5LCBpZGVudGl0eSwgYWdlIG9yIG1hbGZvcm1lZC1kYXRhIGZhaWx1cmVzLg0KICAgIGZvcigkYXR0ZW1wdD0wOyRhdHRlbXB0IC1sdCAzOyRhdHRlbXB0Kyspew0KICAgICAgICB0cnl7cmV0dXJuIFJlYWQtVGltZU9ic2VydmF0aW9uT25jZX1jYXRjaHsNCiAgICAgICAgICAgICRjYXVzZT0kXy5FeGNlcHRpb24uR2V0QmFzZUV4Y2VwdGlvbigpDQogICAgICAgICAgICAkdHJhbnNpZW50PSRjYXVzZSAtaXMgW0lPLklPRXhjZXB0aW9uXSAtb3IgJGNhdXNlIC1pcyBbTWFuYWdlbWVudC5BdXRvbWF0aW9uLkl0ZW1Ob3RGb3VuZEV4Y2VwdGlvbl0NCiAgICAgICAgICAgIGlmKC1ub3QgJHRyYW5zaWVudCAtb3IgJGF0dGVtcHQgLWVxIDIpe3Rocm93fQ0KICAgICAgICAgICAgU3RhcnQtU2xlZXAgLU1pbGxpc2Vjb25kcyAyNQ0KICAgICAgICB9DQogICAgfQ0KfQ0K'
# Local-only probe; registration password stays local. No network or token decryption.
function Get-TimeAccountProbeSource([string]$RunId,[string]$OutputPath,[string]$ContractSource) {
 if($RunId -cnotmatch '^[a-f0-9]{32}$' -or $OutputPath.Contains("'")){throw 'TIME_ACCOUNT_ARGUMENT'}
 $body=@'
$ErrorActionPreference='Stop'
$r=@{runId='__RUN__';passed=$false;failure=$null;ordersEnabled=$false;credentialsUsed=$false}
try{
 $id=[Security.Principal.WindowsIdentity]::GetCurrent()
 try{$r.sid=$id.User.Value;$r.admin=([Security.Principal.WindowsPrincipal]::new($id)).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)}finally{$id.Dispose()}
 $r.sessionId=[Diagnostics.Process]::GetCurrentProcess().SessionId
 if($r.sid -cne 'S-1-5-21-3041730714-102984520-3202743044-1011' -or $r.admin -or $r.sessionId -ne 0){throw 'TIME_ACCOUNT_IDENTITY'}
 $r.samples=@()
 for($i=0;$i -lt 3;$i++){$v=Read-TimeObservation;$r.samples+=@{sequence=$v.sequence;ageSeconds=$v.ageSeconds};if($i -lt 2){Start-Sleep -Milliseconds 1500}}
 if($r.samples[2].sequence -le $r.samples[0].sequence){throw 'TIME_ACCOUNT_NOT_ADVANCING'}
 $r.writeDenied=@()
 foreach($name in @('worker.ps1','snapshot.json')){
  $denied=$false;$handle=$null
  try{$handle=[IO.File]::Open(('C:\ProgramData\MarketBrainPaytmHealth\time-observer-v1\'+$name),'Open','Write',([IO.FileShare]::ReadWrite -bor [IO.FileShare]::Delete))}
  catch{if($_.Exception.GetBaseException() -is [UnauthorizedAccessException]){$denied=$true}else{throw}}
  finally{if($handle){$handle.Dispose()}}
  if(-not $denied){throw 'TIME_ACCOUNT_WRITE_ALLOWED'};$r.writeDenied+=$name
 }
 $r.passed=$true
}catch{$r.failure=if($_.Exception.Message -cmatch '^(TIME_ACCOUNT|TIME_OBSERVER)_[A-Z_]+$'){$_.Exception.Message}else{'TIME_ACCOUNT_'+$_.Exception.GetBaseException().GetType().Name};$r.failureLine=$_.InvocationInfo.ScriptLineNumber}
[IO.File]::WriteAllText('__OUTPUT__',($r|ConvertTo-Json -Depth 5),[Text.UTF8Encoding]::new($false))
if(-not $r.passed){exit 1}
'@
 return $ContractSource+"`n"+$body.Replace('__RUN__',$RunId).Replace('__OUTPUT__',$OutputPath)
}
function Assert-TimeAccountProbeResult($Value,[string]$RunId) {
 if($Value.runId -cne $RunId -or $Value.passed -ne $true -or $Value.failure -or $Value.sid -cne 'S-1-5-21-3041730714-102984520-3202743044-1011' -or $Value.admin -ne $false -or $Value.sessionId -ne 0 -or @($Value.samples).Count -ne 3 -or (@($Value.writeDenied) -join ',') -cne 'worker.ps1,snapshot.json'){throw 'TIME_ACCOUNT_RESULT_INVALID'}
 $previous=0L
 foreach($sample in $Value.samples){if($null -eq $sample.sequence -or $null -eq $sample.ageSeconds -or [double]::IsNaN([double]$sample.ageSeconds) -or $sample.sequence -le $previous -or $sample.ageSeconds -lt 0 -or $sample.ageSeconds -gt 8){throw 'TIME_ACCOUNT_SAMPLE_INVALID'};$previous=$sample.sequence}
}
function Resolve-TimeAccountTaskSid([string]$Identity) {
 if([string]::IsNullOrWhiteSpace($Identity)){throw 'TIME_ACCOUNT_PRINCIPAL_MISSING'}
 if($Identity.StartsWith('S-1-', [StringComparison]::OrdinalIgnoreCase)){
  return [Security.Principal.SecurityIdentifier]::new($Identity).Value
 }
 return ([Security.Principal.NTAccount]::new($Identity)).Translate([Security.Principal.SecurityIdentifier]).Value
}
function ConvertFrom-TimeAccountLogonEvent([string]$Xml) {
 $document=[xml]$Xml;$data=@{}
 foreach($item in $document.Event.EventData.Data){$data[[string]$item.Name]=[string]$item.'#text'}
 if($data.TargetUserName -ine 'marketbrain-health'){return $null}
 return @{targetUser=$data.TargetUserName;targetDomain=$data.TargetDomainName;status=$data.Status;subStatus=$data.SubStatus;logonType=$data.LogonType}
}
function Get-TimeAccountIdentityEvidence($Account,$LocalReport) {
 $configured=$env:COMPUTERNAME+'\marketbrain-health'
 $r=@{configuredUser=$configured;machineName=[Environment]::MachineName;accountSid=$Account.SID.Value;enabled=[bool]$Account.Enabled;identityMatches=$false;events=@();eventQuery='NOT_REQUESTED'}
 try{$r.resolvedSid=Resolve-TimeAccountTaskSid $configured;$r.identityMatches=$r.resolvedSid -ceq $Account.SID.Value}catch{$r.identityFailure=$_.Exception.GetType().Name}
 if($Account.PasswordLastSet){$r.passwordLastSetUtc=$Account.PasswordLastSet.ToUniversalTime().ToString('o')}
 if($LocalReport -and $LocalReport.observedUtc){
  try{
   $end=[DateTimeOffset]::Parse([string]$LocalReport.observedUtc).UtcDateTime.AddSeconds(10)
   $start=$end.AddMinutes(-3)
   $events=@(Get-WinEvent -FilterHashtable @{LogName='Security';Id=4625;StartTime=$start;EndTime=$end} -MaxEvents 50 -ErrorAction Stop)
   foreach($event in $events){$value=ConvertFrom-TimeAccountLogonEvent $event.ToXml();if($value){$value.observedUtc=$event.TimeCreated.ToUniversalTime().ToString('o');$r.events+=$value}}
   $r.eventQuery='COMPLETED_BOUNDED_50'
  }catch{$r.eventQuery='UNAVAILABLE_OR_NO_EVENTS';$r.eventFailure=$_.Exception.GetType().Name}
 }
 return $r
}
function Get-TimeAccountExecutionEvidence($LocalReport) {
 $r=@{query='NOT_REQUESTED';events=@()}
 if(-not $LocalReport -or [string]$LocalReport.runId -cnotmatch '^[a-f0-9]{32}$' -or -not $LocalReport.observedUtc){return $r}
 $task='\MarketBrain-Time-Read-Probe-'+$LocalReport.runId
 try{
  $end=[DateTimeOffset]::Parse([string]$LocalReport.observedUtc).UtcDateTime.AddSeconds(10)
  $events=@(Get-WinEvent -FilterHashtable @{LogName='Microsoft-Windows-TaskScheduler/Operational';StartTime=$end.AddMinutes(-3);EndTime=$end} -MaxEvents 200 -ErrorAction Stop)
  foreach($event in $events){
   $xml=[xml]$event.ToXml();$data=@{}
   foreach($item in $xml.Event.EventData.Data){$data[[string]$item.Name]=[string]$item.'#text'}
   if($data.TaskName -cne $task){continue}
   $entry=@{id=[int]$event.Id;observedUtc=$event.TimeCreated.ToUniversalTime().ToString('o');codes=@{}}
   foreach($name in @('ResultCode','ErrorCode','ProcessId','EnginePID')){
    $number=0L;if($data.ContainsKey($name) -and [long]::TryParse($data[$name],[ref]$number)){$entry.codes[$name]=$number}
   }
   $r.events+=$entry
  }
  $r.query='COMPLETED_BOUNDED_200'
 }catch{$r.query='UNAVAILABLE_OR_NO_EVENTS';$r.failureType=$_.Exception.GetType().Name}
 return $r
}
function Test-TimeAccountTask($Task,[string]$Executable,[string]$Arguments) {
 $reasons=@();$sid=$null
 try{$sid=Resolve-TimeAccountTaskSid ([string]$Task.Principal.UserId)}catch{$reasons+='PRINCIPAL_UNRESOLVED'}
 if($sid -cne 'S-1-5-21-3041730714-102984520-3202743044-1011'){$reasons+='PRINCIPAL_SID'}
 if([string]$Task.Principal.LogonType -cne 'Password'){$reasons+='LOGON_TYPE'}
 if([string]$Task.Principal.RunLevel -cne 'Limited'){$reasons+='RUN_LEVEL'}
 # CIM may represent an absent collection as null, not an empty array.
 $actions=@($Task.Actions | Where-Object {$null -ne $_})
 $triggers=@($Task.Triggers | Where-Object {$null -ne $_})
 $argumentsMatch=$false;$executableMatch=$false
 if($actions.Count -ne 1){$reasons+='ACTION_COUNT'}else{
  $argumentsMatch=$actions[0].Arguments -ceq $Arguments
  $executableMatch=$actions[0].Execute -ieq $Executable
  if(-not $argumentsMatch){$reasons+='ACTION_ARGUMENTS'}
  if(-not $executableMatch){$reasons+='ACTION_EXECUTABLE'}
 }
 if($triggers.Count -ne 0){$reasons+='UNEXPECTED_TRIGGER'}
 return @{valid=($reasons.Count -eq 0);reasons=$reasons;principalSid=$sid;logonType=[string]$Task.Principal.LogonType;runLevel=[string]$Task.Principal.RunLevel;actionCount=$actions.Count;triggerCount=$triggers.Count;argumentsMatch=$argumentsMatch;executableMatch=$executableMatch}
}
function Get-TimeAccountNativeFailure($ErrorRecord) {
 # Retain numeric diagnostics only: never serialize the ErrorRecord, command,
 # exception message, bound parameters, or CIM message text containing arguments.
 $items=@();$exception=$ErrorRecord.Exception
 for($depth=0;$null -ne $exception -and $depth -lt 4;$depth++){
  foreach($name in @('HResult','NativeErrorCode')){
   $property=$exception.PSObject.Properties[$name]
   if($property -and $null -ne $property.Value){$number=0L;if([long]::TryParse([string]$property.Value,[ref]$number)){$items+=@{source="exception.$depth.$name";value=$number}}}
  }
  $data=$exception.PSObject.Properties['ErrorData']
  if($data -and $data.Value){
   foreach($name in @('Error_Code','ErrorCode','CIMStatusCode','MessageID')){
    $property=$data.Value.CimInstanceProperties[$name]
    if($property -and $null -ne $property.Value){$number=0L;if([long]::TryParse([string]$property.Value,[ref]$number)){$items+=@{source="cim.$depth.$name";value=$number}}}
   }
  }
  # CIM often embeds HRESULT in its message while HResult is generic CLR.
  foreach($match in @([regex]::Matches([string]$exception.Message,'(?i)\b0x[89a-f][0-9a-f]{7}\b') | Select-Object -First 4)){
   $items+=@{source="messageHResult.$depth";value=[Convert]::ToInt64($match.Value.Substring(2),16)}
  }
  $exception=$exception.InnerException
 }
 $win32=@()
 foreach($item in $items){
  $unsigned=$item.value -band 4294967295L
  if(($unsigned -band 4294901760L) -eq 2147942400L){$win32+=($unsigned -band 65535L)}
 }
 $win32=@($win32|Sort-Object -Unique)
 $findings=@()
 foreach($code in $win32){$findings+=switch($code){5{'ACCESS_DENIED'}1326{'USERNAME_OR_PASSWORD_REJECTED'}1330{'PASSWORD_EXPIRED'}1331{'ACCOUNT_DISABLED'}1385{'LOGON_TYPE_NOT_GRANTED'}1909{'ACCOUNT_LOCKED'}default{'UNCLASSIFIED_WIN32_ERROR'}}}
 return @{numericDiagnostics=$items;win32Codes=$win32;findings=$findings;passwordCorrectness='NOT_ESTABLISHED'}
}
function Test-TimeAccountCredential([Security.SecureString]$Password) {
 if(-not ('MarketBrainTimeCredentialV1' -as [type])){
  Add-Type -TypeDefinition @'
using System;
using System.Security;
using System.Security.Principal;
using System.Runtime.InteropServices;
public static class MarketBrainTimeCredentialV1 {
 [DllImport("advapi32.dll", CharSet=CharSet.Unicode, ExactSpelling=true, SetLastError=true)]
 static extern bool LogonUserW(string user, string domain, IntPtr password, int type, int provider, out IntPtr token);
 [DllImport("kernel32.dll", ExactSpelling=true)] static extern bool CloseHandle(IntPtr handle);
 public static int Check(SecureString secret, out string sid) {
  sid=null; IntPtr password=IntPtr.Zero, token=IntPtr.Zero;
  try {
   password=Marshal.SecureStringToGlobalAllocUnicode(secret);
   if(!LogonUserW("marketbrain-health", Environment.MachineName, password, 4, 0, out token)) return Marshal.GetLastWin32Error();
   using(var identity=new WindowsIdentity(token)) { sid=identity.User.Value; }
   return 0;
  } finally { if(token!=IntPtr.Zero) CloseHandle(token); if(password!=IntPtr.Zero) Marshal.ZeroFreeGlobalAllocUnicode(password); }
 }
}
'@
 }
 $sid=$null;$code=[MarketBrainTimeCredentialV1]::Check($Password,[ref]$sid)
 return @{accepted=($code -eq 0 -and $sid -ceq 'S-1-5-21-3041730714-102984520-3202743044-1011');win32Code=$code;resolvedSid=$sid;attempts=1;logonType='BATCH'}
}
function Invoke-TimeAccountProbe([string]$ContractSource,[Security.SecureString]$Password) {
 if(-not $Password -or $Password.Length -eq 0){throw 'TIME_ACCOUNT_LOCAL_PASSWORD_REQUIRED'}
 $run=[guid]::NewGuid().ToString('N');$task='MarketBrain-Time-Read-Probe-'+$run
 $parent='C:\ProgramData\MarketBrainPaytmHealth\time-observer-v1'
 $dir=Join-Path $parent ('probe-'+$run);$outputDir=Join-Path $dir 'result';$output=Join-Path $outputDir 'report.json'
 $r=@{passed=$false;runId=$run;taskName=$task;taskCreated=$false;taskRemoved=$false;cleanupFailure=$null;failure=$null;authenticationTested=$false;healthPublicationTested=$false}
 try{
  $r.stage='PARENT_ACL';Assert-TimeObservationAcl $parent
  $r.stage='SNAPSHOT_READ';$null=Read-TimeObservation
  $r.stage='WINDOWS_CREDENTIAL_CHECK';$r.credentialCheck=Test-TimeAccountCredential $Password
  if(-not $r.credentialCheck.accepted){throw 'TIME_ACCOUNT_WINDOWS_CREDENTIAL_NOT_ACCEPTED'}
  if((Test-Path -LiteralPath $dir) -or @(Get-ScheduledTask|Where-Object {$_.TaskName -ceq $task -and $_.TaskPath -ceq '\'}).Count){throw 'TIME_ACCOUNT_COLLISION'}
  $r.stage='CREATE_PROBE';$null=New-Item -ItemType Directory -Path $dir
  $r.stage='PROBE_ACL';Assert-TimeObservationAcl $dir
  $null=New-Item -ItemType Directory -Path $outputDir
  $r.stage='RESULT_ACL';$acl=Get-Acl -LiteralPath $outputDir
  $acl.AddAccessRule([Security.AccessControl.FileSystemAccessRule]::new([Security.Principal.SecurityIdentifier]::new('S-1-5-21-3041730714-102984520-3202743044-1011'),'Modify','ContainerInherit,ObjectInherit','None','Allow'))
  Set-Acl -LiteralPath $outputDir -AclObject $acl
  $r.stage='WORKER';$worker=Join-Path $dir 'probe.ps1';$source=Get-TimeAccountProbeSource $run $output $ContractSource
  [IO.File]::WriteAllText($worker,$source,[Text.UTF8Encoding]::new($false));Assert-TimeObservationAcl $worker
  $hash=(Get-FileHash -LiteralPath $worker).Hash
  $command="if((Get-FileHash -LiteralPath '$worker').Hash -cne '$hash'){exit 9};&([scriptblock]::Create([IO.File]::ReadAllText('$worker')))"
  $arguments='-NoLogo -NoProfile -NonInteractive -EncodedCommand '+[Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($command))
  $exe=Join-Path $env:WINDIR 'System32\WindowsPowerShell\v1.0\powershell.exe'
  $action=New-ScheduledTaskAction -Execute $exe -Argument $arguments
  $principal=New-ScheduledTaskPrincipal -UserId 'S-1-5-21-3041730714-102984520-3202743044-1011' -LogonType Password -RunLevel Limited
  $settings=New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -ExecutionTimeLimit ([TimeSpan]::FromMinutes(1)) -MultipleInstances IgnoreNew
  $definition=New-ScheduledTask -Action $action -Principal $principal -Settings $settings
  $r.stage='REGISTER';$plain=$null
  try{$plain=[Net.NetworkCredential]::new('', $Password).Password;$null=Register-ScheduledTask -TaskName $task -TaskPath '\' -InputObject $definition -User ($env:COMPUTERNAME+'\marketbrain-health') -Password $plain}finally{$plain=$null}
  $r.taskCreated=$true
  $r.stage='VERIFY_REGISTERED_TASK'
  $t=Get-ScheduledTask -TaskName $task -TaskPath '\'
  $r.taskValidation=Test-TimeAccountTask $t $exe $arguments
  if(-not $r.taskValidation.valid){throw 'TIME_ACCOUNT_TASK_DRIFT'}
  $r.stage='START';Start-ScheduledTask -TaskName $task -TaskPath '\'
  $timer=[Diagnostics.Stopwatch]::StartNew()
  do{Start-Sleep -Seconds 1;$t=Get-ScheduledTask -TaskName $task -TaskPath '\'}while($timer.Elapsed.TotalSeconds -lt 40 -and (-not (Test-Path -LiteralPath $output) -or [string]$t.State -eq 'Running'))
  $info=Get-ScheduledTaskInfo -TaskName $task -TaskPath '\'
  $r.taskExecution=@{state=[string]$t.State;lastTaskResult=[long]$info.LastTaskResult}
  if($info.LastRunTime){$r.taskExecution.lastRunTimeUtc=$info.LastRunTime.ToUniversalTime().ToString('o')}
  if([string]$t.State -eq 'Running'){throw 'TIME_ACCOUNT_TIMEOUT'}
  if(-not (Test-Path -LiteralPath $output)){throw 'TIME_ACCOUNT_NO_REPORT'}
  if((Get-Item -LiteralPath $output).Length -gt 8192){throw 'TIME_ACCOUNT_REPORT_SIZE'}
  $r.worker=Get-Content -LiteralPath $output -Raw|ConvertFrom-Json
  Assert-TimeAccountProbeResult $r.worker $run
  if($r.taskExecution.lastTaskResult -ne 0){throw 'TIME_ACCOUNT_EXIT'}
  $r.passed=$true
 }catch{$r.failure=if($_.Exception.Message -cmatch '^(TIME_ACCOUNT|TIME_OBSERVER)_[A-Z_]+$'){$_.Exception.Message}else{'TIME_ACCOUNT_'+$_.Exception.GetBaseException().GetType().Name};$r.failureLine=$_.InvocationInfo.ScriptLineNumber;$r.nativeHResult=$_.Exception.HResult;$r.nativeFailure=Get-TimeAccountNativeFailure $_;$message=$_.Exception.Message;$r.failureDetail=if($r.stage -eq 'REGISTER'){'Scheduler registration failed; password omitted'}else{$message.Substring(0,[Math]::Min(512,$message.Length))};$target=[string]$_.TargetObject;if($target.StartsWith($parent,[StringComparison]::OrdinalIgnoreCase)){$r.failureTarget=$target.Substring($parent.Length)}}
 finally{
  if($r.taskCreated){try{
   $null=Disable-ScheduledTask -TaskName $task -TaskPath '\';Stop-ScheduledTask -TaskName $task -TaskPath '\'
   $t=Get-ScheduledTask -TaskName $task -TaskPath '\';if([string]$t.State -eq 'Running'){throw 'TIME_ACCOUNT_STILL_RUNNING'}
   Unregister-ScheduledTask -TaskName $task -TaskPath '\' -Confirm:$false
   if(@(Get-ScheduledTask|Where-Object {$_.TaskName -ceq $task -and $_.TaskPath -ceq '\'}).Count){throw 'TIME_ACCOUNT_TASK_REMAINS'}
   $r.taskRemoved=$true
  }catch{$r.cleanupFailure='TIME_ACCOUNT_CLEANUP';$r.passed=$false}}
 }
 return $r
}

# PS5-compatible read-only time observation contract. No actions on import.
function Get-TimeObservationBootId {
    # Stable across users/processes; changes after a Windows restart.
    (Get-CimInstance Win32_OperatingSystem -ErrorAction Stop).LastBootUpTime.ToUniversalTime().ToString('o')
}
function Assert-TimeObservationAcl([string]$Path) {
    if((Get-Item -LiteralPath $Path -Force).Attributes -band [IO.FileAttributes]::ReparsePoint){throw 'TIME_OBSERVER_REPARSE'}
    $acl=Get-Acl -LiteralPath $Path
    $trusted=@('S-1-5-18','S-1-5-32-544')
    if($acl.GetOwner([Security.Principal.SecurityIdentifier]).Value -notin $trusted){throw 'TIME_OBSERVER_OWNER'}
    $write=[Security.AccessControl.FileSystemRights]::Write -bor [Security.AccessControl.FileSystemRights]::Delete -bor [Security.AccessControl.FileSystemRights]::DeleteSubdirectoriesAndFiles -bor [Security.AccessControl.FileSystemRights]::ChangePermissions -bor [Security.AccessControl.FileSystemRights]::TakeOwnership
    foreach($ace in $acl.GetAccessRules($true,$true,[Security.Principal.SecurityIdentifier])){
        if($ace.AccessControlType -eq 'Allow' -and ($ace.FileSystemRights -band $write) -and $ace.IdentityReference.Value -notin $trusted){throw 'TIME_OBSERVER_WRITABLE'}
    }
}
function ConvertFrom-TimeObservation($Value,[string]$BootId,[long]$NowTicks,[long]$Frequency) {
    if($Value.version -ne 1 -or $Value.bootId -cne $BootId -or $Value.frequency -ne $Frequency -or $Value.sequence -lt 1){throw 'TIME_OBSERVER_IDENTITY'}
    if($Value.startTicks -isnot [long] -or $Value.endTicks -isnot [long] -or $Value.startTicks -gt $Value.endTicks -or $Value.endTicks -gt $NowTicks){throw 'TIME_OBSERVER_TIMING'}
    $age=($NowTicks-$Value.startTicks)/[double]$Frequency
    if($age -lt 0 -or $age -gt 8){throw 'TIME_OBSERVER_STALE'}
    if($Value.status.exitCode -ne 0 -or $Value.source.exitCode -ne 0 -or $Value.service.state -cne 'Running' -or $Value.service.startType -ne 2){throw 'TIME_OBSERVER_UNHEALTHY'}
    if($Value.status.output -isnot [string] -or $Value.source.output -isnot [string] -or $Value.status.output.Length -gt 12000 -or $Value.source.output.Length -gt 1024){throw 'TIME_OBSERVER_FORMAT'}
    # Add snapshot age to the reported sync age; never make old evidence younger.
    $pattern='(?im)^(Time since Last Good Sync Time:\s*)([0-9]+(?:\.[0-9]+)?)(s\s*)$'
    $m=[regex]::Match($Value.status.output,$pattern)
    if(-not $m.Success){throw 'TIME_OBSERVER_SYNC_AGE'}
    $seconds=[double]::Parse($m.Groups[2].Value,[Globalization.CultureInfo]::InvariantCulture)+$age
    $output=$Value.status.output.Remove($m.Groups[2].Index,$m.Groups[2].Length).Insert($m.Groups[2].Index,$seconds.ToString('F6',[Globalization.CultureInfo]::InvariantCulture))
    [pscustomobject]@{status=@{exitCode=0;output=$output};source=$Value.source;service=$Value.service;ageSeconds=$age;sequence=$Value.sequence}
}
function ConvertFrom-TimeObservationJson([string]$Json) {
    # PS7 otherwise coerces ISO boot IDs into DateTime, unlike the PS5 producer.
    if($PSVersionTable.PSVersion -ge [version]'7.5'){ConvertFrom-Json -InputObject $Json -DateKind String}else{ConvertFrom-Json -InputObject $Json}
}
function Read-TimeObservationFileOnce([string]$Path) {
    Assert-TimeObservationAcl $Path
    $stream=[IO.File]::Open($Path,'Open','Read',([IO.FileShare]::ReadWrite -bor [IO.FileShare]::Delete))
    try{if($stream.Length -gt 16384){throw 'TIME_OBSERVER_SIZE'};$reader=[IO.StreamReader]::new($stream);try{$buffer=[char[]]::new(16385);$n=$reader.ReadBlock($buffer,0,16385);if($n -gt 16384){throw 'TIME_OBSERVER_SIZE'};return ConvertFrom-TimeObservationJson ([string]::new($buffer,0,$n))}finally{$reader.Dispose()}}finally{$stream.Dispose()}
}
function Read-TimeObservationFile([string]$Path) {
    for($attempt=0;$attempt -lt 3;$attempt++){
        try{return Read-TimeObservationFileOnce $Path}catch{
            $cause=$_.Exception.GetBaseException()
            if(($cause -isnot [IO.IOException] -and $cause -isnot [Management.Automation.ItemNotFoundException]) -or $attempt -eq 2){throw}
            Start-Sleep -Milliseconds 25
        }
    }
}
function Read-TimeObservationOnce {
    $root='C:\ProgramData\MarketBrainPaytmHealth\time-observer-v1';$path=Join-Path $root 'snapshot.json'
    foreach($p in @('C:\ProgramData\MarketBrainPaytmHealth',$root)){Assert-TimeObservationAcl $p}
    $v=Read-TimeObservationFileOnce $path
    ConvertFrom-TimeObservation $v (Get-TimeObservationBootId) ([Diagnostics.Stopwatch]::GetTimestamp()) ([Diagnostics.Stopwatch]::Frequency)
}

function Read-TimeObservation {
    # Snapshot replacement can briefly invalidate a path lookup. Retry only I/O
    # lookup failures, never ACL policy, identity, age or malformed-data failures.
    for($attempt=0;$attempt -lt 3;$attempt++){
        try{return Read-TimeObservationOnce}catch{
            $cause=$_.Exception.GetBaseException()
            $transient=$cause -is [IO.IOException] -or $cause -is [Management.Automation.ItemNotFoundException]
            if(-not $transient -or $attempt -eq 2){throw}
            Start-Sleep -Milliseconds 25
        }
    }
}

$timeObserverWorker = 'I1JlcXVpcmVzIC1WZXJzaW9uIDUuMQokRXJyb3JBY3Rpb25QcmVmZXJlbmNlPSdTdG9wJwokcm9vdD0nQzpcUHJvZ3JhbURhdGFcTWFya2V0QnJhaW5QYXl0bUhlYWx0aFx0aW1lLW9ic2VydmVyLXYxJwppZihbU2VjdXJpdHkuUHJpbmNpcGFsLldpbmRvd3NJZGVudGl0eV06OkdldEN1cnJlbnQoKS5Vc2VyLlZhbHVlIC1jbmUgJ1MtMS01LTE4Jyl7dGhyb3cgJ1RJTUVfT0JTRVJWRVJfU1lTVEVNX1JFUVVJUkVEJ30KJHBhdGg9Sm9pbi1QYXRoICRyb290ICdzbmFwc2hvdC5qc29uJzskc2VxdWVuY2U9MEwKZnVuY3Rpb24gUmVhZC1GaXhlZFRpbWVRdWVyeShbVmFsaWRhdGVTZXQoJy9xdWVyeSAvc3RhdHVzIC92ZXJib3NlJywnL3F1ZXJ5IC9zb3VyY2UnKV1bc3RyaW5nXSRBcmd1bWVudHMpewogICAgJHA9W0RpYWdub3N0aWNzLlByb2Nlc3NdOjpuZXcoKTskcC5TdGFydEluZm8uRmlsZU5hbWU9Sm9pbi1QYXRoICRlbnY6V0lORElSICdTeXN0ZW0zMlx3MzJ0bS5leGUnOyRwLlN0YXJ0SW5mby5Bcmd1bWVudHM9JEFyZ3VtZW50cwogICAgJHAuU3RhcnRJbmZvLlVzZVNoZWxsRXhlY3V0ZT0kZmFsc2U7JHAuU3RhcnRJbmZvLkNyZWF0ZU5vV2luZG93PSR0cnVlOyRwLlN0YXJ0SW5mby5SZWRpcmVjdFN0YW5kYXJkT3V0cHV0PSR0cnVlOyRwLlN0YXJ0SW5mby5SZWRpcmVjdFN0YW5kYXJkRXJyb3I9JHRydWUKICAgIHRyeXtpZigtbm90ICRwLlN0YXJ0KCkpe3Rocm93ICdUSU1FX09CU0VSVkVSX1NUQVJUJ307JG89JHAuU3RhbmRhcmRPdXRwdXQuUmVhZFRvRW5kQXN5bmMoKTskZT0kcC5TdGFuZGFyZEVycm9yLlJlYWRUb0VuZEFzeW5jKCk7aWYoLW5vdCAkcC5XYWl0Rm9yRXhpdCgyMDAwKSl7dGhyb3cgJ1RJTUVfT0JTRVJWRVJfVElNRU9VVCd9O2lmKC1ub3QgJG8uV2FpdCg1MDApIC1vciAtbm90ICRlLldhaXQoNTAwKSl7dGhyb3cgJ1RJTUVfT0JTRVJWRVJfRFJBSU4nfTtpZigkby5SZXN1bHQuTGVuZ3RoIC1ndCAxMjAwMCl7dGhyb3cgJ1RJTUVfT0JTRVJWRVJfU0laRSd9O0B7ZXhpdENvZGU9JHAuRXhpdENvZGU7b3V0cHV0PSRvLlJlc3VsdH19ZmluYWxseXt0cnl7aWYoLW5vdCAkcC5IYXNFeGl0ZWQpeyRwLktpbGwoKTskbnVsbD0kcC5XYWl0Rm9yRXhpdCgxMDAwKX19Y2F0Y2h7fTskcC5EaXNwb3NlKCl9Cn0KJGJvb3Q9KEdldC1DaW1JbnN0YW5jZSBXaW4zMl9PcGVyYXRpbmdTeXN0ZW0pLkxhc3RCb290VXBUaW1lLlRvVW5pdmVyc2FsVGltZSgpLlRvU3RyaW5nKCdvJykKd2hpbGUoJHRydWUpewogICAgJHN0YXJ0PVtEaWFnbm9zdGljcy5TdG9wd2F0Y2hdOjpHZXRUaW1lc3RhbXAoKQogICAgdHJ5ewogICAgICAgICRzdGF0dXM9UmVhZC1GaXhlZFRpbWVRdWVyeSAnL3F1ZXJ5IC9zdGF0dXMgL3ZlcmJvc2UnOyRzb3VyY2U9UmVhZC1GaXhlZFRpbWVRdWVyeSAnL3F1ZXJ5IC9zb3VyY2UnCiAgICAgICAgJHNlcnZpY2U9R2V0LVNlcnZpY2UgVzMyVGltZTskc3RhcnRUeXBlPShHZXQtSXRlbVByb3BlcnR5ICdIS0xNOlxTWVNURU1cQ3VycmVudENvbnRyb2xTZXRcU2VydmljZXNcVzMyVGltZScgLU5hbWUgU3RhcnQpLlN0YXJ0CiAgICAgICAgJHNlcXVlbmNlKysKICAgICAgICAkdj1Ae3ZlcnNpb249MTtib290SWQ9JGJvb3Q7c2VxdWVuY2U9JHNlcXVlbmNlO3N0YXJ0VGlja3M9JHN0YXJ0O2VuZFRpY2tzPVtEaWFnbm9zdGljcy5TdG9wd2F0Y2hdOjpHZXRUaW1lc3RhbXAoKTtmcmVxdWVuY3k9W0RpYWdub3N0aWNzLlN0b3B3YXRjaF06OkZyZXF1ZW5jeTtzdGF0dXM9JHN0YXR1cztzb3VyY2U9JHNvdXJjZTtzZXJ2aWNlPUB7c3RhdGU9W3N0cmluZ10kc2VydmljZS5TdGF0dXM7c3RhcnRUeXBlPSRzdGFydFR5cGV9fQogICAgICAgICRqc29uPSR2fENvbnZlcnRUby1Kc29uIC1EZXB0aCA1IC1Db21wcmVzcztpZihbVGV4dC5FbmNvZGluZ106OlVURjguR2V0Qnl0ZUNvdW50KCRqc29uKSAtZ3QgMTYzODQpe3Rocm93ICdUSU1FX09CU0VSVkVSX1NJWkUnfQogICAgICAgICR0ZW1wPSRwYXRoKycubmV3JztbSU8uRmlsZV06OldyaXRlQWxsVGV4dCgkdGVtcCwkanNvbixbVGV4dC5VVEY4RW5jb2RpbmddOjpuZXcoJGZhbHNlKSkKICAgICAgICBpZihbSU8uRmlsZV06OkV4aXN0cygkcGF0aCkpe1tJTy5GaWxlXTo6UmVwbGFjZSgkdGVtcCwkcGF0aCxbTWFuYWdlbWVudC5BdXRvbWF0aW9uLkxhbmd1YWdlLk51bGxTdHJpbmddOjpWYWx1ZSl9ZWxzZXtbSU8uRmlsZV06Ok1vdmUoJHRlbXAsJHBhdGgpfQogICAgfWNhdGNoe2lmKFtJTy5GaWxlXTo6RXhpc3RzKCRwYXRoKSl7W0lPLkZpbGVdOjpEZWxldGUoJHBhdGgpfTt0aHJvd30KICAgIFN0YXJ0LVNsZWVwIC1TZWNvbmRzIDEKfQo='
# Controller helpers; staging remains disabled and does not start gateway or collector.
function Get-DurableCollectorDefinition([string]$WorkerHash) {
 if($WorkerHash -cnotmatch '^[A-F0-9]{64}$'){throw 'COLLECTOR_WORKER_HASH'}
 $root='C:\ProgramData\MarketBrainPaytmHealth\collector-v1'
 $command="if((Get-FileHash -LiteralPath '$root\worker.ps1').Hash -cne '$WorkerHash'){exit 9};&([scriptblock]::Create([IO.File]::ReadAllText('$root\worker.ps1')))"
 @{name='MarketBrain-Health-Collector-v1';root=$root;work='C:\ProgramData\MarketBrainPaytmHealth\collector-work-v1';exe='C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe';arguments=('-NoLogo -NoProfile -NonInteractive -EncodedCommand '+[Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($command)))}
}
function Assert-DurableCollectorTask($Task,$Definition) {
 $sid=Resolve-TimeAccountTaskSid ([string]$Task.Principal.UserId)
 if($Task.TaskName -cne $Definition.name -or $Task.TaskPath -cne '\' -or $sid -cne 'S-1-5-21-3041730714-102984520-3202743044-1011' -or [string]$Task.Principal.LogonType -cne 'Password' -or [string]$Task.Principal.RunLevel -cne 'Limited'){throw 'COLLECTOR_TASK_IDENTITY'}
 if($Task.Actions.Count -ne 1 -or $Task.Actions[0].Execute -ine $Definition.exe -or $Task.Actions[0].Arguments -cne $Definition.arguments -or $Task.Actions[0].WorkingDirectory -cne $Definition.root){throw 'COLLECTOR_TASK_ACTION'}
 if($Task.Settings.Enabled -or [string]$Task.State -cne 'Disabled' -or $Task.Triggers.Count -ne 1 -or $Task.Triggers[0].CimClass.CimClassName -cne 'MSFT_TaskBootTrigger' -or -not $Task.Triggers[0].Enabled){throw 'COLLECTOR_TASK_STARTUP'}
 if([string]$Task.Settings.MultipleInstances -cne 'IgnoreNew' -or $Task.Settings.RestartCount -ne 0 -or [Xml.XmlConvert]::ToTimeSpan($Task.Settings.ExecutionTimeLimit).TotalSeconds -ne 0 -or $Task.Settings.DisallowStartIfOnBatteries -or $Task.Settings.StopIfGoingOnBatteries -or -not $Task.Settings.StartWhenAvailable){throw 'COLLECTOR_TASK_SETTINGS'}
}
function New-DurableCollectorSource([string]$Installation) {
 if($Installation -cnotmatch '^[a-f0-9]{32}$'){throw 'COLLECTOR_INSTALLATION_ID'}
 $root='C:\ProgramData\MarketBrainPaytmHealth\collector-v1';$work='C:\ProgramData\MarketBrainPaytmHealth\collector-work-v1'
 $preamble=[IO.File]::ReadAllText((Join-Path $PSScriptRoot 'PaytmTimeObservation.ps1'))+"`n"+[IO.File]::ReadAllText((Join-Path $PSScriptRoot 'PaytmDurableCollector.ps1'))+"`n"
 $preamble+="if(-not (Read-DurableCollectorControl '$root\control.json' '$Installation')){exit 0}`n"
 $preamble+="`$collectorLease=[IO.File]::Open('$work\instance.lock','Open','ReadWrite','None')`n"
 $source=[IO.File]::ReadAllText((Join-Path $PSScriptRoot 'PaytmHealthScheduledWorker.ps1'))
 $token=Get-HealthScheduledTokenSource
 foreach($name in @('PaytmTimeServiceRepair.ps1','PaytmLiveHealthCollector.ps1','PaytmHealthCollectorCore.ps1')){$token+="`n"+[IO.File]::ReadAllText((Join-Path $PSScriptRoot $name))}
 $token+=@'

 $token=$null
 try{
  $token=Unprotect-HealthToken ([IO.File]::ReadAllBytes($tokenRoot+'\health-token.dpapi'))
  $r['collector']=Invoke-DurableCollectorLoop $token $a $r.applicationBootId {Read-DurableCollectorControl '__ROOT__\control.json' '__RUN__'} {param($v) Write-DurableCollectorStatus '__WORK__\status.json' $v}
  if($r.collector.failure -or -not $r.collector.finalHealthRevoked){throw 'COLLECTOR_RUNTIME_FAILED'}
 }finally{$token=$null}
'@
 $source=$source.Replace('__TOKEN_CHECK__',$token)
 # One final report is atomically replaced, not an unbounded history of files.
 $start=$source.IndexOf(' $bytes=[Text.Encoding]::UTF8.GetBytes')
 $end=$source.IndexOf("`n}",$start)
 if($start -lt 0 -or $end -lt 0){throw 'COLLECTOR_TEMPLATE_CHANGED'}
 $source=$source.Substring(0,$start)+" Write-DurableCollectorStatus '__WORK__\final.json' `$r`n `$collectorLease.Dispose()"+$source.Substring($end)
 return ($preamble+$source).Replace('__RUN__',$Installation).Replace('__ROOT__',$root).Replace('__WORK__',$work).Replace('__KNOWN__',($root.Replace('\','/')+'/known_hosts'))
}

# Read-only verification of the accepted spare-machine installation.
function Assert-DurableCollectorReceipt($Receipt) {
 if($Receipt.version -ne 1 -or $Receipt.runId -cne 'ab47639ee8d74da69a9466c0f59e601e' -or $Receipt.status -cne 'DURABLE_COLLECTOR_STAGED_DISABLED_ACTIVATION_PENDING' -or $Receipt.failure -or $Receipt.taskRegistered -ne $true -or $Receipt.disabledVerified -ne $true -or $Receipt.workerStarted -ne $false -or $Receipt.ordersEnabled -ne $false){throw 'COLLECTOR_RECEIPT_STATE'}
 if($Receipt.workerSha256 -cne '25CFF7A9A54184DC0B5F43A094B331B14C4D288448C8BA8A01975A9F29053B99' -or $Receipt.knownHostsSha256 -cne 'C8D0896753936BC7AB4B47E755516BF253A973F8E65CC8B8CF249B9476CC924D' -or $Receipt.taskXmlSha256 -cne '4D5EFBB0271BF6EB937050E89B5118CBDCE89FF9AC30AF1FD7F8C10EC8E6B730'){throw 'COLLECTOR_RECEIPT_PINS'}
 if($Receipt.credentialCheck.accepted -ne $true -or $Receipt.credentialCheck.win32Code -ne 0 -or $Receipt.credentialCheck.logonType -cne 'BATCH' -or $Receipt.credentialCheck.resolvedSid -cne 'S-1-5-21-3041730714-102984520-3202743044-1011'){throw 'COLLECTOR_RECEIPT_IDENTITY'}
}
function Get-DurableCollectorStagingPreflight($Receipt) {
 Assert-DurableCollectorReceipt $Receipt
 $d=Get-DurableCollectorDefinition $Receipt.workerSha256
 foreach($path in @('C:\ProgramData\MarketBrainPaytmHealth',$d.root,(Join-Path $d.root 'worker.ps1'),(Join-Path $d.root 'known_hosts'),(Join-Path $d.root 'control.json'))){Assert-TimeObservationAcl $path}
 if((Get-FileHash -LiteralPath (Join-Path $d.root 'worker.ps1')).Hash -cne $Receipt.workerSha256 -or (Get-FileHash -LiteralPath (Join-Path $d.root 'known_hosts')).Hash -cne $Receipt.knownHostsSha256){throw 'COLLECTOR_INSTALLED_FILE_DRIFT'}
 $control=Read-TimeObservationFile (Join-Path $d.root 'control.json')
 if($control.version -ne 1 -or $control.installationId -cne $Receipt.runId -or $control.enabled -isnot [bool] -or $control.enabled){throw 'COLLECTOR_CONTROL_DRIFT'}
 $task=Get-ScheduledTask -TaskName $d.name -TaskPath '\' -ErrorAction Stop
 Assert-DurableCollectorTask $task $d
 if($task.Description -cne ('MarketBrain diagnostic collector '+$Receipt.runId)){throw 'COLLECTOR_TASK_OWNERSHIP'}
 $sha=[Security.Cryptography.SHA256]::Create()
 try{$xmlHash=([BitConverter]::ToString($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes((Export-ScheduledTask -TaskName $d.name -TaskPath '\'))))).Replace('-','')}finally{$sha.Dispose()}
 if($xmlHash -cne $Receipt.taskXmlSha256){throw 'COLLECTOR_TASK_XML_DRIFT'}
 $snapshot=Read-TimeObservation
 return @{status='DURABLE_COLLECTOR_STAGING_VERIFIED_ACTIVATION_PENDING';installationId=$Receipt.runId;taskDisabled=$true;controlDisabled=$true;workerHashVerified=$true;hostHashVerified=$true;taskXmlVerified=$true;timeSnapshotAgeSeconds=$snapshot.ageSeconds;observedUtc=[DateTime]::UtcNow.ToString('o');ordersEnabled=$false;runtimeStarted=$false}
}

# Embedded by Build-TimeObserverJob.ps1. Fixed installation; no supplied commands.
$ErrorActionPreference='Stop'
$r=@{version=1;passed=$false;mode=$Mode;failure=$null;ordersEnabled=$false;credentialsUsed=$false;taskCreated=$false;healthAccountAcceptance=$false}
$root='C:\ProgramData\MarketBrainPaytmHealth\time-observer-v1';$task='MarketBrain-Time-Observer-v1';$watch=[Diagnostics.Stopwatch]::StartNew()
try{
 if($Mode -ceq 'FailureFixture'){throw 'TIME_OBSERVER_DELIBERATE_FIXTURE'}
 $id=[Security.Principal.WindowsIdentity]::GetCurrent()
 try{if(-not ([Security.Principal.WindowsPrincipal]::new($id)).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)){throw 'TIME_OBSERVER_ADMIN_REQUIRED'}}finally{$id.Dispose()}
 Assert-TimeObservationAcl 'C:\ProgramData\MarketBrainPaytmHealth'
 $account=Get-LocalUser -Name 'marketbrain-health'
 if($account.SID.Value -cne 'S-1-5-21-3041730714-102984520-3202743044-1011' -or -not $account.Enabled){throw 'TIME_OBSERVER_ACCOUNT_DRIFT'}
 $existing=@(Get-ScheduledTask|Where-Object {$_.TaskPath -ceq '\' -and $_.TaskName -ceq $task})
 if($Mode -ceq 'Observe'){
  $r.directoryPresent=Test-Path -LiteralPath $root;$r.taskPresent=($existing.Count -gt 0)
  if($r.directoryPresent){$snapshot=Join-Path $root 'snapshot.json';if(Test-Path -LiteralPath $snapshot){$v=Read-TimeObservationFile $snapshot;$r.snapshotIdentity=@{bootId=$v.bootId;expectedBootId=(Get-TimeObservationBootId);frequency=$v.frequency;expectedFrequency=[Diagnostics.Stopwatch]::Frequency;sequence=$v.sequence;version=$v.version}};$r.workerSha256=(Get-FileHash -LiteralPath (Join-Path $root 'worker.ps1')).Hash};if($existing.Count -eq 1){$r.taskState=[string]$existing[0].State}
  $localResult=Join-Path $root 'account-probe-result.json'
  if(Test-Path -LiteralPath $localResult){$r.localAccountProbe=Read-TimeObservationFile $localResult}
  $collectorResult=Join-Path $root 'collector-batch-result.json'
  if(Test-Path -LiteralPath $collectorResult){$r.collectorBatch=Read-TimeObservationFile $collectorResult}
  $installResult=Join-Path $root 'collector-install-result.json'
  if(Test-Path -LiteralPath $installResult){$r.collectorInstallation=Read-TimeObservationFile $installResult;$r.collectorStaging=Get-DurableCollectorStagingPreflight $r.collectorInstallation}
  $r.accountIdentity=Get-TimeAccountIdentityEvidence $account $r.localAccountProbe
  $r.accountExecution=Get-TimeAccountExecutionEvidence $r.localAccountProbe
  $r.status='TIME_OBSERVER_INVENTORY_ONLY';$r.passed=$true;return
 }
 if($existing.Count -eq 1 -and [string]$existing[0].State -ceq 'Running'){throw 'TIME_ACCOUNT_LOCAL_PASSWORD_REQUIRED'}
 $recover=(Test-Path -LiteralPath $root) -or $existing.Count
 if($recover){
  if(-not (Test-Path -LiteralPath $root) -or $existing.Count -ne 1 -or [string]$existing[0].State -cne 'Disabled'){throw 'TIME_OBSERVER_EXISTING_INSTALL_REVIEW_REQUIRED'}
  Assert-TimeObservationAcl $root
  $path=Join-Path $root 'worker.ps1';Assert-TimeObservationAcl $path
  if((Get-FileHash -LiteralPath $path).Hash -cne '7129B3D3844D8E60F039ACE5F9701B100B2A849BB25AB3E5E653B18486BCFBE0'){throw 'TIME_OBSERVER_RECOVERY_WORKER_DRIFT'}
  $r.recovery=$true
 }else{
 $null=New-Item -ItemType Directory -Path $root
 $acl=[Security.AccessControl.DirectorySecurity]::new();$acl.SetAccessRuleProtection($true,$false)
 $acl.SetOwner([Security.Principal.SecurityIdentifier]::new('S-1-5-32-544'))
 foreach($sid in @('S-1-5-18','S-1-5-32-544',$account.SID.Value)){
  $rights=if($sid -ceq $account.SID.Value){[Security.AccessControl.FileSystemRights]::ReadAndExecute}else{[Security.AccessControl.FileSystemRights]::FullControl}
  $acl.AddAccessRule([Security.AccessControl.FileSystemAccessRule]::new([Security.Principal.SecurityIdentifier]::new($sid),$rights,'ContainerInherit,ObjectInherit','None','Allow'))
 }
 Set-Acl -LiteralPath $root -AclObject $acl;Assert-TimeObservationAcl $root
 $path=Join-Path $root 'worker.ps1';$bytes=[Convert]::FromBase64String($timeObserverWorker)
 [IO.File]::WriteAllBytes($path,$bytes);Assert-TimeObservationAcl $path
 }
 $hash=(Get-FileHash -LiteralPath $path).Hash
 $command="if((Get-FileHash -LiteralPath '$path').Hash -cne '$hash'){exit 9};&([scriptblock]::Create([IO.File]::ReadAllText('$path')))"
 $arguments='-NoLogo -NoProfile -NonInteractive -EncodedCommand '+[Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($command))
 $exe=Join-Path $env:WINDIR 'System32\WindowsPowerShell\v1.0\powershell.exe'
 $action=New-ScheduledTaskAction -Execute $exe -Argument $arguments
 $trigger=New-ScheduledTaskTrigger -AtStartup
 $principal=New-ScheduledTaskPrincipal -UserId 'S-1-5-18' -LogonType ServiceAccount -RunLevel Highest
 $settings=New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable -MultipleInstances IgnoreNew -ExecutionTimeLimit ([TimeSpan]::Zero)
 if(-not $recover){
 $null=Register-ScheduledTask -TaskName $task -TaskPath '\' -Description 'MarketBrain fixed read-only Windows time observer v1' -Action $action -Trigger $trigger -Principal $principal -Settings $settings
 $r.taskCreated=$true
 }
 $t=Get-ScheduledTask -TaskName $task -TaskPath '\'
 if($t.Actions.Count -ne 1 -or $t.Actions[0].Arguments -cne $arguments -or $t.Actions[0].Execute -ine $exe -or $t.Principal.UserId -notin @('SYSTEM','S-1-5-18') -or [string]$t.Principal.LogonType -ne 'ServiceAccount' -or $t.Triggers.Count -ne 1 -or $t.Triggers[0].CimClass.CimClassName -cne 'MSFT_TaskBootTrigger'){throw 'TIME_OBSERVER_TASK_VERIFY'}
 $r.workerSha256=$hash
 if($recover){$r.recoveryStartAttempted=$true;$null=Enable-ScheduledTask -TaskName $task -TaskPath '\'}
 Start-ScheduledTask -TaskName $task -TaskPath '\'
 $first=$null;$last=$null;$startedTicks=[Diagnostics.Stopwatch]::GetTimestamp()
 for($i=0;$i -lt 15;$i++){
  Start-Sleep -Seconds 1
  if(Test-Path -LiteralPath (Join-Path $root 'snapshot.json')){
   $snapshotPath=Join-Path $root 'snapshot.json';Assert-TimeObservationAcl $snapshotPath
   $snapshot=ConvertFrom-TimeObservationJson ([IO.File]::ReadAllText($snapshotPath))
   if($snapshot.endTicks -lt $startedTicks){continue}
   $last=Read-TimeObservation
   if($first -and $last.sequence -gt $first.sequence){break}
   $first=$last
  }
 }
 if(-not $last -or -not $first -or $last.sequence -le $first.sequence){throw 'TIME_OBSERVER_NO_FRESH_SEQUENCE'}
 $r.firstSequence=$first.sequence;$r.lastSequence=$last.sequence;$r.ageSeconds=$last.ageSeconds
 $r.status='TIME_OBSERVER_SYSTEM_PASSED_HEALTH_ACCOUNT_PENDING';$r.passed=$true
}catch{
 $r.failure=if($_.Exception.Message -cmatch '^(TIME_OBSERVER|TIME_ACCOUNT|COLLECTOR)_[A-Z_]+$'){$_.Exception.Message}else{'TIME_OBSERVER_'+$_.Exception.GetBaseException().GetType().Name}
 $r.failureLine=$_.InvocationInfo.ScriptLineNumber
 if($r.taskCreated -or $r.recoveryStartAttempted){try{$null=Disable-ScheduledTask -TaskName $task -TaskPath '\';Stop-ScheduledTask -TaskName $task -TaskPath '\';$r.failureStopRequested=$true}catch{$r.cleanupFailure='TIME_OBSERVER_STOP_REVIEW_REQUIRED'}}
}finally{
 $r.elapsedSeconds=$watch.Elapsed.TotalSeconds
 [IO.File]::WriteAllText($ResultPath,($r|ConvertTo-Json -Depth 6),[Text.UTF8Encoding]::new($false))
}
if(-not $r.passed){exit 1}
