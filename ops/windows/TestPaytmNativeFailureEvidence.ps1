#Requires -Version 7.0
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'ReadPaytmNativeFailure.ps1') -LibraryOnly
. (Join-Path $PSScriptRoot 'PaytmSupervisorHost.ps1')
. (Join-Path $PSScriptRoot 'PaytmGatewaySession.ps1')
$checks=@{count=0};$mode='empty'
function Check($Ok,$Label){if(-not $Ok){throw "NATIVE_EVIDENCE_TEST_$Label"};$checks.count++}
function Event($Id=8004){
 $e=[pscustomobject]@{Id=$Id;RecordId=10;TimeCreated=[DateTime]::UtcNow}
 $e|Add-Member -MemberType ScriptMethod -Name ToXml -Value {return '<Event><EventData><Data Name="FileName">C:\Windows\System32\curl.exe</Data><Data Name="CommandLine">powershell.exe PRIVATE_TOKEN</Data><Data Name="User">PRIVATE_USER</Data><Data Name="Status">0xC0000022</Data><Data Name="ProcessId">123</Data><Data Name="ErrorCode">PRIVATE_SECRET</Data></EventData></Event>'}
 $e
}
$v=ConvertTo-PaytmNativeEvent (Event)
Check ($v.id -eq 8004 -and $v.matchedFileNames.Count -eq 2 -and $v.numericCodes[0] -eq '0xC0000022' -and $v.processIds[0] -eq '123') 'EVENT_PROJECTION'
Check (-not ($v|ConvertTo-Json -Depth 4).Contains('PRIVATE_')) 'EVENT_REDACTION'
function Get-WinEvent {
 [CmdletBinding()]param($ListLog,$FilterHashtable,$MaxEvents)
 if($ListLog){
  if($mode -eq 'missing'){throw [UnauthorizedAccessException]::new('PRIVATE_LOG_ERROR')}
  return @{IsEnabled=($mode -ne 'disabled')}
 }
 if($MaxEvents -ne 32 -or ($FilterHashtable.EndTime-$FilterHashtable.StartTime).TotalMinutes -ne 10 -or $FilterHashtable.Id.Count -lt 2){throw 'TEST_QUERY_NOT_BOUNDED'}
 if($mode -eq 'empty'){Write-Error -Message 'PRIVATE_NO_EVENTS' -ErrorId NoMatchingEventsFound -Category ObjectNotFound;return}
 if($mode -eq 'query_denied'){Write-Error -Message 'PRIVATE_QUERY_DENIED' -ErrorId AccessDenied;return}
 if($mode -eq 'limit'){1..32|ForEach-Object {Event};return}
 Event
}
foreach($mode in @('empty','disabled','missing','query_denied','limit','match')){
 $rows=@(Get-PaytmNativePolicyEvents '2026-11-05T09:40:13Z' '2026-11-05T09:50:13Z')
 Check ($rows.Count -eq 3) 'THREE_CHANNELS'
 foreach($r in $rows){
  Check ($r.querySucceeded -eq ($mode -in @('empty','limit','match'))) 'QUERY_STATUS'
  Check ($r.limitReached -eq ($mode -eq 'limit')) 'TRUNCATION_STATUS'
 }
 Check (-not ($rows|ConvertTo-Json -Depth 6).Contains('PRIVATE_')) 'QUERY_REDACTION'
}
foreach($end in @('2026-11-05T09:40:13Z','2026-11-05T10:50:13Z','broken')){
 $failed=$false;try{Get-PaytmNativePolicyEvents '2026-11-05T09:40:13Z' $end}catch{$failed=$true};Check $failed 'INVALID_WINDOW'
}
# Local smoke: this exact probe runs curl --version only, without a gateway or URL.
$version=Invoke-PaytmNativeVersionProbe
Check ($version.started -and $version.stage -eq 'COMPLETE' -and $version.exitCode -eq 0 -and $null -eq $version.errorType) 'ACTUAL_NATIVE_CURL_VERSION'
Check ($version.identityScope -eq 'CONTROLLER_NOT_GATEWAY_ACCOUNT' -and $version.arguments -eq '--version') 'IDENTITY_LIMIT_EXPLICIT'
# Real PS7 -> inbox PS5 boundary with module discovery deliberately unavailable.
. (Join-Path $PSScriptRoot 'PaperRuntimeReview.ps1')
$readerPath=(Join-Path $PSScriptRoot 'ReadPaytmNativeFailure.ps1').Replace("'","''")
$child=@'
$ErrorActionPreference='Stop'
$env:PSModulePath='C:\__MarketBrain_no_module_discovery__'
$PSModuleAutoLoadingPreference='None'
. 'READER_PATH' -LibraryOnly
foreach($path in @('C:\Windows\System32\curl.exe','C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe')){
 $r=Get-PaytmNativeFileMetadata $path
 if($r.stage -cne 'COMPLETE' -or $r.errorType -or $r.sha256 -cnotmatch '^[A-F0-9]{64}$' -or -not $r.signatureStatus -or -not $r.accessSddl){exit 31}
}
$r=Get-PaytmNativeFileMetadata 'C:\__MarketBrain_missing_executable__.exe'
if($r.present -or $r.stage -ceq 'COMPLETE'){exit 32}
exit 0
'@
$child=$child.Replace('READER_PATH',$readerPath)
$encoded=[Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($child))
$native=Invoke-PaperRuntimeProcess 'C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe' @('-NoLogo','-NoProfile','-NonInteractive','-EncodedCommand',$encoded) $PSScriptRoot 90
Check ($native.exitCode -eq 0) 'REAL_PS5_METADATA_WITHOUT_MODULE_DISCOVERY'
$temp=Join-Path ([IO.Path]::GetTempPath()) ('mb-native-evidence-'+[guid]::NewGuid().ToString('N'));$null=New-Item -ItemType Directory -Path $temp
$fixture=@{}
function Assert-PaytmAccountPath($Path){$Path}
function Assert-PaytmCustodyController {}
function Assert-PaytmAccountAcl {}
function Get-Acl {}
function Import-Module {}
function Get-PaytmHostContract {@{root=$fixture.root;work=$fixture.root}}
function Get-PaytmAccountContract {@{root=$fixture.root}}
function Get-PaytmKeyContract {@{accountSid='fixture'}}
function Get-PaytmEvidenceProperty($Value,$Name){$Value.$Name}
function Get-PaytmWorkerFailureEvidence {@{readOnly=$true;files=@{};currentHealthEstablished=$false}}
function Get-FileHash($LiteralPath){if($LiteralPath -eq $fixture.input){@{Hash=$(if($fixture.case -eq 'wrong_receipt'){'F'*64}else{'1AC0D72016F9BF053F94C8C99B40CCB717351A4A0411ED892BACA014C9524106'})}}else{Microsoft.PowerShell.Utility\Get-FileHash -LiteralPath $LiteralPath}}
function Invoke-PaperRuntimeProcess($Executable,$Arguments,$Directory,$LimitSeconds){
 Check ($Executable -ceq 'C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe' -and $LimitSeconds -eq 90) 'NATIVE_QUERY_CONTRACT'
 $text=[Text.Encoding]::Unicode.GetString([Convert]::FromBase64String($Arguments[-1]))
 Check ($text.Contains("-StartUtc '2026-11-05T09:40:13.6603845+00:00'") -and $text.Contains("-EndUtc '2026-11-05T09:50:13.6603845+00:00'")) 'RECEIPT_TIME_NORMALIZED'
 if($fixture.case -eq 'timeout'){throw 'RUNTIME_PROCESS_TIMEOUT'}
 $metadata=@('curl.exe','powershell.exe'|ForEach-Object {@{fileName=$_;present=$true;stage='COMPLETE';sha256=('A'*64);signatureStatus='Valid';accessSddl='D:fixture';errorType=$null}})
 if($fixture.case -eq 'partial_metadata'){$metadata[0].stage='HASH';$metadata[0].errorType='CommandNotFoundException';$metadata[0].sha256=$null}
 $json=@{version=1;readOnly=$true;files=$metadata;policyEvents=@();versionProbe=@{identityScope='CONTROLLER_NOT_GATEWAY_ACCOUNT'}}|ConvertTo-Json -Depth 5 -Compress
 @{exitCode=$(if($fixture.case -eq 'native_failed'){1}else{0});stdout=$json;stderr='PRIVATE_NATIVE_ERROR';elapsedSeconds=1}
}
try{
 foreach($case in @('pass','wrong_receipt','native_failed','timeout','partial_metadata')){
  $base=Join-Path $temp $case;$root=Join-Path $base 'root';$out=Join-Path $base 'out';$source=Join-Path $base 'ops/windows';$null=New-Item -ItemType Directory -Path $root,$out,$source -Force
  $fixture=@{case=$case;root=$root;input=(Join-Path $base 'receipt.json')}
  Write-PaytmHostJson $fixture.input @{runId=('b'*32);workerDiagnostics=@{files=@{'startup-failure.json'=@{lastWriteUtc='2026-11-05T09:45:13.6603845Z'}}}}
  $hashes=@{}
  foreach($name in @('native.dll','runner.ps1','transport.ps1')){[IO.File]::WriteAllText((Join-Path $root $name),'fixture');$hashes[$name]=(Get-FileHash -LiteralPath (Join-Path $root $name)).Hash}
  Write-PaytmHostJson (Join-Path $root 'manifest.json') @{hashes=$hashes}
  $hashes['manifest.json']=(Get-FileHash -LiteralPath (Join-Path $root 'manifest.json')).Hash
  $inputHash=(Microsoft.PowerShell.Utility\Get-FileHash -LiteralPath $fixture.input).Hash
  foreach($name in @('PaytmGatewayAccount.ps1','PaytmGatewayKeyCustody.ps1','PaytmGatewayScheduledProbe.ps1','PaytmSupervisorHost.ps1','PaytmSupervisorInstallation.ps1','PaytmGatewaySession.ps1','PaytmGatewayFailureEvidence.ps1','PaperRuntimeReview.ps1','ReadPaytmNativeFailure.ps1')){[IO.File]::WriteAllText((Join-Path $source $name),'# fixture')}
  $script=Join-Path $source 'GetPaytmNativeFailureEvidence.ps1';Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'GetPaytmNativeFailureEvidence.ps1') -Destination $script
  $failed=$false;try{& $script -DiagnosticReportPath $fixture.input -OutputDirectory $out 6>$null}catch{$failed=$true}
  Check ($failed -eq ($case -ne 'pass')) 'COLLECTOR_OUTCOME'
  $files=@(Get-ChildItem -LiteralPath $out -Filter '*.json');Check ($files.Count -eq 1) 'ONE_REPORT'
  $r=Read-PaytmHostJson $files[0].FullName 65536
  Check ($r.status -eq $(if($case -eq 'pass'){'NATIVE_FAILURE_EVIDENCE_CAPTURED'}else{'REVIEW_REQUIRED'})) 'REPORT_OUTCOME'
  Check (-not $r.gatewayChanged -and -not $r.taskStarted -and -not $r.credentialsUsed -and -not $r.applicationAccessed -and -not $r.underlyingOperationEstablished) 'SCOPE_AND_UNCERTAINTY'
  Check (-not ([IO.File]::ReadAllText($files[0].FullName)).Contains('PRIVATE_')) 'COLLECTOR_REDACTION'
  foreach($name in $hashes.Keys){Check ((Get-FileHash -LiteralPath (Join-Path $root $name)).Hash -ceq $hashes[$name]) 'INSTALLED_BYTES_PRESERVED'}
  Check ((Microsoft.PowerShell.Utility\Get-FileHash -LiteralPath $fixture.input).Hash -ceq $inputHash) 'INPUT_PRESERVED'
  if($case -eq 'partial_metadata'){Check ($r.failure -ceq 'NATIVE_FILE_METADATA_INCOMPLETE' -and -not $r.metadataComplete -and $r.nativeEvidence.files.Count -eq 2) 'PARTIAL_CAPTURE_NEVER_COMPLETE'}
  if($case -in @('native_failed','timeout')){Check ($r.workerDiagnostics.readOnly -and $r.installedFiles.Count -eq 3) 'PARTIAL_DIAGNOSTICS_PRESERVED'}
 }
 [pscustomobject]@{status='NATIVE_FAILURE_EVIDENCE_TESTS_PASSED';assertions=$checks.count;collectorWorkflows=5;eventQueryScenarios=6;realPs5MetadataWithDiscoveryDisabled=$true;nativeLocalCurlVersion=$true;privilegedApisMocked=$true}|ConvertTo-Json
}finally{
 $resolved=[IO.Path]::GetFullPath($temp);$parent=[IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\')+'\'
 if(-not $resolved.StartsWith($parent,[StringComparison]::OrdinalIgnoreCase) -or [IO.Path]::GetFileName($resolved) -notmatch '^mb-native-evidence-[a-f0-9]{32}$'){throw 'UNSAFE_NATIVE_FIXTURE_CLEANUP'}
 Remove-Item -LiteralPath $resolved -Recurse -Force
}
