#Requires -Version 7.0
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'PaytmSshNegativeProbes.ps1')
$checks=0
function Check($ok,$label){if(-not $ok){throw "SSH_NEGATIVE_TEST_$label"};$script:checks++}
. (Join-Path $PSScriptRoot 'PaperRuntimeReview.ps1')
$nativeDir=Join-Path ([IO.Path]::GetTempPath()) ('paytm-keygen-test-'+[guid]::NewGuid().ToString('N'))
$null=New-Item -ItemType Directory -Path $nativeDir
$nativeKey=Join-Path $nativeDir 'testkey'
try{
 $native=Invoke-PaperRuntimeProcess 'C:\Windows\System32\OpenSSH\ssh-keygen.exe' @('-q','-t','rsa','-b','2048','-N','','-C','negative-local-only','-f',$nativeKey) $nativeDir 20
 Check ($native.exitCode -eq 0 -and (Test-Path -LiteralPath $nativeKey)) 'REAL_KEYGEN_EMPTY_PASSPHRASE_ARGUMENT'
 Check (([IO.File]::ReadAllText($nativeKey+'.pub')) -cmatch '^ssh-rsa ') 'REAL_PUBLIC_KEY'
}finally{
 foreach($p in @($nativeKey,($nativeKey+'.pub'))){if(Test-Path -LiteralPath $p){Remove-Item -LiteralPath $p -Force}}
 Remove-Item -LiteralPath $nativeDir
}
$pin='SHA256:TESTONLY'
$hostError='WARNING: REMOTE HOST IDENTIFICATION HAS CHANGED! Host key verification failed.'
$keyError="debug1: Offering public key: C:/temporary RSA $pin explicit`nmarketbrain-gateway@130.250.191.137: Permission denied (publickey)."
Check (Test-PaytmNegativeSshResult WRONG_HOST @{exitCode=255;stderr=$hostError} $pin) 'HOST_REJECTION'
Check (Test-PaytmNegativeSshResult WRONG_KEY @{exitCode=255;stderr=$keyError} $pin) 'KEY_REJECTION'
foreach($kind in @('WRONG_HOST','WRONG_KEY')){
 foreach($r in @(@{exitCode=0;stderr=$hostError+$keyError},@{exitCode=255;stderr='Connection timed out'},@{exitCode=255;stderr='Permission denied (publickey).'},@{exitCode=255;stderr=$hostError+$keyError+'Authenticated to host using publickey'})){
  Check (-not (Test-PaytmNegativeSshResult $kind $r $pin)) 'FALSE_FAILURE_REJECTED'
 }
}
Check (-not (Test-PaytmNegativeSshResult WRONG_KEY @{exitCode=255;stderr=$keyError.Replace('TESTONLY','OTHER')} $pin)) 'EXACT_OFFERED_FINGERPRINT'
Check (-not (Test-PaytmNegativeSshResult WRONG_KEY @{exitCode=255;stderr=$keyError+'Load key x: bad permissions'} $pin)) 'LOCAL_KEY_ERROR_NOT_SERVER_DENIAL'
Check (-not (Test-PaytmNegativeSshResult WRONG_HOST @{exitCode=255;stderr=$hostError+$keyError} $pin)) 'NO_KEY_OFFER_BEFORE_HOST_REJECTION'
$a=Get-PaytmNegativeSshArguments 'C:\space dir\hosts' 'C:\space dir\key'
foreach($o in @('IdentityAgent=none','IdentitiesOnly=yes','ClearAllForwardings=yes','PasswordAuthentication=no','StrictHostKeyChecking=yes','ProxyCommand=none','ProxyJump=none','GlobalKnownHostsFile=none','AddKeysToAgent=no')){Check ($a -contains $o) 'ISOLATED_CLIENT_OPTIONS'}
Check ($a[-1] -ceq '130.250.191.137' -and $a -contains 'IdentityFile=C:/space dir/key') 'FIXED_DESTINATION_AND_PATH'
# Exercise actual helper lifecycle with substituted OS boundaries and disposable files.
. (Join-Path $PSScriptRoot 'PaytmGatewayKeyCustody.ps1')
$fixture=Join-Path ([IO.Path]::GetTempPath()) ('paytm-negative-fixture-'+[guid]::NewGuid().ToString('N'))
$null=New-Item -ItemType Directory -Path $fixture
$blob=[Convert]::ToBase64String([byte[]](1,2,3));$fakeHost=[Convert]::ToBase64String([byte[]](4,5,6))
[IO.File]::WriteAllText((Join-Path $fixture 'known_hosts'),('130.250.191.137 ssh-rsa '+$fakeHost))
function Get-PaytmKeyContract {@{root=$fixture;hostPin=(Get-PaytmKeyFingerprint ([byte[]](4,5,6)));fingerprint='not-our-key';accountSid='fixture'}}
function Assert-PaytmAccountPath($p){$p}
function Set-PaytmAccountDirectoryAcl {}
function Set-PaytmPrivateKeyAcl {}
function Invoke-PaperRuntimeProcess {param($Executable,$Arguments,$Directory,$LimitSeconds)
 if($Executable.EndsWith('ssh-keygen.exe')){
  [IO.File]::WriteAllText($Arguments[-1],'SYNTHETIC_NOT_A_KEY')
  [IO.File]::WriteAllText(($Arguments[-1]+'.pub'),('ssh-rsa '+$blob))
  return @{exitCode=0}
 }
 if($script:mode -eq 'TIMEOUT'){throw 'RUNTIME_PROCESS_TIMEOUT'}
 if(($Arguments -join ' ') -match 'wrong_hosts'){$text=$hostError}else{$text=$keyError.Replace($pin,(Get-PaytmKeyFingerprint ([byte[]](1,2,3))))}
 @{exitCode=255;stderr=$text;elapsedSeconds=0.1}
}
foreach($mode in @('PASS','TIMEOUT')){
 $script:mode=$mode;$script:rows=@();$failed=$false
 try{Invoke-PaytmSshNegativeBatch $fixture {param($r)$script:rows+=,$r}}catch{$failed=$true}
 Check ($failed -eq ($mode -eq 'TIMEOUT')) 'LIFECYCLE_RESULT'
 Check ($rows[-1].name -eq 'DISPOSABLE_FILES_REMOVED' -and $rows[-1].passed) 'CLEANUP_EVIDENCE'
 Check (@(Get-ChildItem -LiteralPath $fixture -Directory).Count -eq 0) 'NO_DISPOSABLE_KEY_LEFT'
}
Remove-Item -LiteralPath (Join-Path $fixture 'known_hosts')
Remove-Item -LiteralPath $fixture
@{status='SSH_NEGATIVE_LOCAL_TESTS_PASSED';assertions=$checks;realSshAuthenticationTested=$false}|ConvertTo-Json
