#Requires -Version 7.2
# Fixed read-only job: return only the compact supervised login report, never credentials.
param([Parameter(Mandatory)][string]$ResultPath,[ValidateSet('Observe','Apply','FailureFixture')][string]$Mode='Observe')
$ErrorActionPreference='Stop'
$result=[ordered]@{version=1;test='SUPERVISED_LOGIN_REPORT_COLLECTION';passed=$false;ordersEnabled=$false;failure=$null}
try{
 if($Mode -ne 'Observe'){throw 'REPORT_OBSERVE_ONLY'}
 $files=@(Get-ChildItem -LiteralPath 'C:\MarketBrainData\Review' -Filter 'paytm-supervised-*.json' -File|Where-Object {$_.Name -match '^paytm-supervised-(login|deployment)-[a-f0-9]{32}\.json$'}|Sort-Object LastWriteTimeUtc -Descending|Select-Object -First 1)
 if($files.Count -ne 1){throw 'SUPERVISED_REPORT_NOT_CREATED_YET'}
 $file=$files[0]
 if($file.Length -gt 16384 -or $file.Attributes -band [IO.FileAttributes]::ReparsePoint){throw 'REPORT_FILE_REJECTED'}
 $stream=$null;$reader=$null
 try{
  $stream=[IO.File]::Open($file.FullName,'Open','Read',([IO.FileShare]::ReadWrite -bor [IO.FileShare]::Delete))
  if($stream.Length -gt 16384){throw 'REPORT_FILE_REJECTED'}
  $reader=[IO.StreamReader]::new($stream)
  $v=$reader.ReadToEnd()|ConvertFrom-Json
 }finally{if($reader){$reader.Dispose()};if($stream){$stream.Dispose()}}
 if($v.version -ne 1 -or $v.runId -cnotmatch '^[a-f0-9]{32}$' -or $v.ordersEnabled -ne $false){throw 'REPORT_SCOPE_REJECTED'}
 $safe=[ordered]@{runId=$v.runId;ordersEnabled=$false}
 foreach($name in @('status','stage','failure','providerFailure','clockSource','applicationState')){
  $text=[string]$v.$name
  if($text -and $text -cnotmatch '^[A-Z0-9_]{1,100}$'){throw 'REPORT_FIELD_REJECTED'}
  $safe[$name]=$text
 }
 foreach($name in @('readAccessVerified','quotesTested','windowsClockGate','vpsAccuracyAssumed')){
  if($v.$name -isnot [bool]){throw 'REPORT_FIELD_REJECTED'};$safe[$name]=$v.$name
 }
 $safe.cleanup=@($v.cleanup|ForEach-Object {if($_ -cnotmatch '^[A-Z_]{1,80}$'){throw 'REPORT_FIELD_REJECTED'};$_})
 $safe.elapsedSeconds=[double]$v.elapsedSeconds
 if($v.PSObject.Properties['quoteSamples']){
  if(@($v.quoteSamples).Count -gt 3){throw 'REPORT_FIELD_REJECTED'}
  $safe.quoteSamples=@($v.quoteSamples|ForEach-Object {
   $q=$_;$s=[ordered]@{}
   foreach($n in @('status','exchange','scripType','timestampEpoch')){
    if($q.PSObject.Properties[$n]){if([string]$q.$n -cnotmatch '^[A-Z0-9_]{1,100}$'){throw 'REPORT_FIELD_REJECTED'};$s[$n]=[string]$q.$n}
   }
   foreach($n in @('securityId','observedEpochMilliseconds','rawTradeTime','tradeEpochMilliseconds','ageMilliseconds','lastPrice')){
    if($q.PSObject.Properties[$n]){if($q.$n -is [string] -or $q.$n -is [bool] -or $null -eq $q.$n){throw 'REPORT_FIELD_REJECTED'};$s[$n]=[decimal]$q.$n}
   }
   foreach($n in @('fresh','mappingVerified','ordersEnabled')){if($q.$n -isnot [bool]){throw 'REPORT_FIELD_REJECTED'};$s[$n]=$q.$n}
   if($q.ordersEnabled -ne $false -or $q.mappingVerified -ne $false){throw 'REPORT_SCOPE_REJECTED'}
   $s
  })
 }
 if($v.PSObject.Properties['failureLine']){$safe.failureLine=[int]$v.failureLine}
 if($v.PSObject.Properties['deploymentAttempted']){$safe.deploymentAttempted=($v.deploymentAttempted -eq $true)}
 if($v.PSObject.Properties['commands']){
  $safe.commands=@($v.commands|ForEach-Object {
   if($_.stage -cnotmatch '^[A-Z_]{1,60}$'){throw 'REPORT_FIELD_REJECTED'}
   @{stage=$_.stage;exitCode=[int]$_.exitCode;elapsedSeconds=[double]$_.elapsedSeconds}
  })
 }
 $result.report=$safe;$result.sourceFile=$file.Name;$result.passed=$true
 $result.status='REPORT_COLLECTED_NOT_AUTOMATICALLY_ACCEPTED'
}catch{$result.failure=if($_.Exception.Message -cmatch '^[A-Z_]+$'){$_.Exception.Message}else{'REPORT_COLLECTION_FAILED'}}
[IO.File]::WriteAllText($ResultPath,($result|ConvertTo-Json -Depth 6))
if(-not $result.passed){exit 1}
