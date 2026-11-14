#Requires -Version 7.0
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'PaytmSecurityProbes.ps1')
$source=Get-Content -LiteralPath (Join-Path $PSScriptRoot 'TestPaytmSecurityProbeBundle.ps1') -Raw
$start=$source.IndexOf('foreach($name in @(');$end=$source.IndexOf('$watch=', $start)
$source=$source.Remove($start,$end-$start)
$source=$source.Replace(". (Join-Path `$PSScriptRoot 'PaytmSshNegativeProbes.ps1')",'')
$source=$source.Replace('$PSScriptRoot',("'"+$PSScriptRoot.Replace("'","''")+"'"))
$fixture=Join-Path ([IO.Path]::GetTempPath()) ('paytm-security-fixture-'+[guid]::NewGuid().ToString('N'))
$null=New-Item -ItemType Directory $fixture
function Assert-PaytmAccountPath($p){$p}
function Assert-PaytmCustodyController {}
function Import-Module {}
function Get-PaytmAccountContract {@{root=$fixture}}
function Get-FileHash {param($LiteralPath) @{Hash='078A34DB0A46951EB98C5A08063F9FC76DB6EC75C175A3572CEE3D65DA4FAB4B'}}
function Read-PaytmHostJson {@{}}
function Assert-PaytmTransportAcceptance {}
function Assert-PaytmInstalledTransport {
 $script:installCalls++
 if($script:mode -eq 'FINAL_DRIFT' -and $script:installCalls -gt 1){throw 'FIXTURE_DRIFT'}
 @{installationId='fixture'}
}
function Wait-PaytmManagedHost {param($Id,$Phase,$TimeoutSeconds)
 $script:sequence++
 @{instanceId='same';sequence=$script:sequence;phase='TRANSPORT_READY'}
}
function Assert-PaytmHostAdvance($a,$b){if($b.sequence -le $a.sequence){throw 'NO_ADVANCE'}}
function Write-PaytmSessionReport($Path,$Value){[IO.File]::WriteAllText($Path,($Value|ConvertTo-Json -Depth 16))}
function Invoke-PaperRuntimeProcess {param($Executable,$Arguments,$Directory,$LimitSeconds)
 if($script:mode -eq 'TIMEOUT'){throw 'RUNTIME_PROCESS_TIMEOUT'}
 if($script:mode -eq 'WRONG_ACCEPT') {return @{exitCode=0;stdout='200|0|503';elapsedSeconds=1}}
 if($Arguments -contains '--pinnedpubkey'){$code=90;$m='200|0|000'}
 elseif($Arguments[-1] -in @('https://example.com/','https://developer.paytmmoney.com:444/')){$code=56;$m='403|0|000'}
 elseif($Arguments[-1] -eq 'http://developer.paytmmoney.com/'){$code=0;$m='000|0|403'}
 else{$code=0;$m='200|0|503'}
 @{exitCode=$code;stdout=$m;elapsedSeconds=1}
}
function Invoke-PaytmSshNegativeBatch($Directory,$Record){
 & $Record @{name='WRONG_HOST';passed=$true}
 if($script:mode -eq 'SSH_FAIL'){throw 'FIXTURE_SSH_DENIED_INCORRECTLY'}
 & $Record @{name='WRONG_KEY';passed=$true}
 & $Record @{name='DISPOSABLE_FILES_REMOVED';passed=$true}
}
$checks=0
foreach($mode in @('PASS','TIMEOUT','WRONG_ACCEPT','FINAL_DRIFT','SSH_PASS','SSH_FAIL')){
 $script:mode=$mode;$script:installCalls=0;$script:sequence=0
 $dir=Join-Path $fixture $mode;$threw=$false
 try{& ([scriptblock]::Create($source)) -OutputDirectory $dir -TransportReportPath (Join-Path $fixture 'receipt.json') -SshNegative:($mode -like 'SSH_*')}catch{$threw=$true}
 $files=@(Get-ChildItem -LiteralPath $dir -Filter '*.json')
 if($files.Count -ne 1){throw 'CONTROLLER_REPORT_COUNT'}
 $r=Get-Content -LiteralPath $files[0].FullName -Raw|ConvertFrom-Json
 if($mode -eq 'PASS'){
  if($threw -or $r.status -ne 'SECURITY_PROBES_PASSED_SSH_AND_HEALTH_TESTS_PENDING' -or $r.checks.Count -ne 6){throw 'CONTROLLER_PASS'}
 }elseif($mode -eq 'SSH_PASS'){
  if($threw -or $r.status -ne 'SSH_REJECTIONS_PASSED_LISTENER_AND_HEALTH_PENDING' -or $r.checks.Count -ne 3){throw 'CONTROLLER_SSH_PASS'}
 }elseif(-not $threw -or $r.status -ne 'REVIEW_REQUIRED'){throw 'CONTROLLER_FAIL_CLOSED'}
 if($mode -eq 'TIMEOUT' -and $r.failure -ne 'RUNTIME_PROCESS_TIMEOUT'){throw 'CONTROLLER_ROOT_CAUSE'}
 if($mode -eq 'FINAL_DRIFT' -and $r.cleanupFailure -ne 'FIXTURE_DRIFT'){throw 'CONTROLLER_FINAL_DRIFT'}
 if($r.credentialsUsed -or $r.ordersEnabled -or $r.checkpointCompleted){throw 'CONTROLLER_SCOPE'}
 $checks++
}
# Delete only the explicit files created in this unique fixture; no recursive removal.
Get-ChildItem -LiteralPath $fixture -Directory | ForEach-Object {
 Get-ChildItem -LiteralPath $_.FullName -File | Remove-Item
 Remove-Item -LiteralPath $_.FullName
}
Remove-Item -LiteralPath (Join-Path $fixture 'supervisor-install.lock')
Remove-Item -LiteralPath $fixture
@{status='SECURITY_CONTROLLER_WORKFLOWS_PASSED';workflows=$checks;runtimeApisMocked=$true}|ConvertTo-Json
