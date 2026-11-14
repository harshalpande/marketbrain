# Disposable, unregistered key only. Never uses the installed signing identity.
function Get-PaytmNegativeSshArguments([string]$KnownHosts,[string]$Key) {
 $a=@('-F','none','-N','-T','-4','-v','-p','22','-l','marketbrain-gateway')
 foreach($o in @('BatchMode=yes','StrictHostKeyChecking=yes','IdentitiesOnly=yes','IdentityAgent=none',
 'PasswordAuthentication=no','KbdInteractiveAuthentication=no','PreferredAuthentications=publickey',
 'ForwardAgent=no','ForwardX11=no','ClearAllForwardings=yes','ConnectTimeout=8','ConnectionAttempts=1',
 'UpdateHostKeys=no','VerifyHostKeyDNS=no','GlobalKnownHostsFile=none','ProxyCommand=none','ProxyJump=none',
 'ControlMaster=no','ControlPath=none','PermitLocalCommand=no','RequestTTY=no','NumberOfPasswordPrompts=0',
 'AddKeysToAgent=no','HostKeyAlgorithms=rsa-sha2-512,rsa-sha2-256',
 ('UserKnownHostsFile='+$KnownHosts.Replace('\','/')),('IdentityFile='+$Key.Replace('\','/')))){$a+=@('-o',$o)}
 $a+='130.250.191.137'
 return ,$a
}
function Test-PaytmNegativeSshResult([string]$Kind,$Result,[string]$Fingerprint) {
 if($Result.exitCode -ne 255 -or $Result.stderr -match 'Authenticated to |Authentication succeeded'){return $false}
 if($Kind -ceq 'WRONG_HOST'){
  return ($Result.stderr -match 'REMOTE HOST IDENTIFICATION HAS CHANGED' -and
   $Result.stderr -match 'Host key verification failed' -and $Result.stderr -notmatch 'Offering public key:')
 }
 if($Kind -ceq 'WRONG_KEY'){
  return ($Result.stderr -match ('(?m)^debug1: Offering public key:.*'+[regex]::Escape($Fingerprint)) -and
   $Result.stderr -match 'Permission denied \(publickey\)' -and
   $Result.stderr -notmatch 'Host key verification failed|Load key .*:|bad permissions|UNPROTECTED PRIVATE KEY')
 }
 return $false
}
function Invoke-PaytmSshNegativeBatch([string]$Directory,[scriptblock]$Record) {
 $k=Get-PaytmKeyContract
 $fixture=Join-Path $Directory ('ssh-negative-'+[guid]::NewGuid().ToString('N'))
 $null=Assert-PaytmAccountPath $fixture
 $null=New-Item -ItemType Directory -Path $fixture
 $cleanupFailed=$false;$primaryFailure=$null
 try{
  Set-PaytmAccountDirectoryAcl $fixture $k.accountSid
  $key=Join-Path $fixture 'unregistered';$good=Join-Path $fixture 'known_hosts';$bad=Join-Path $fixture 'wrong_hosts'
  $hostFile=Assert-PaytmAccountPath (Join-Path $k.root 'known_hosts')
  $hostLine=[IO.File]::ReadAllText($hostFile).Trim()
  if($hostLine -cnotmatch '^130\.250\.191\.137 ssh-rsa ([A-Za-z0-9+/=]+)$'){throw 'NEGATIVE_HOST_FORMAT'}
  if((Get-PaytmKeyFingerprint ([Convert]::FromBase64String($Matches[1]))) -cne $k.hostPin){throw 'NEGATIVE_HOST_PIN'}
  Write-Host '[20%] Generate disposable unregistered SSH key (no agent import)'
  $r=Invoke-PaperRuntimeProcess 'C:\Windows\System32\OpenSSH\ssh-keygen.exe' @('-q','-t','rsa','-b','2048','-N','','-C','marketbrain-negative-only','-f',$key) $fixture 20
  if($r.exitCode -ne 0){throw 'NEGATIVE_KEY_GENERATION'}
  Set-PaytmPrivateKeyAcl $key $k.accountSid
  $pub=[IO.File]::ReadAllText($key+'.pub').Trim()
  if($pub -cnotmatch '^ssh-rsa ([A-Za-z0-9+/=]+)(?: .*)?$'){throw 'NEGATIVE_PUBLIC_FORMAT'}
  $blob=$Matches[1];$fingerprint=Get-PaytmKeyFingerprint ([Convert]::FromBase64String($blob))
  if($fingerprint -ceq $k.hostPin -or $fingerprint -ceq $k.fingerprint){throw 'NEGATIVE_KEY_COLLISION'}
  [IO.File]::WriteAllText($good,$hostLine+"`n",[Text.UTF8Encoding]::new($false))
  [IO.File]::WriteAllText($bad,('130.250.191.137 ssh-rsa '+$blob+"`n"),[Text.UTF8Encoding]::new($false))
  foreach($case in @(@('WRONG_HOST',$bad),@('WRONG_KEY',$good))){
   Write-Host "[50%] $($case[0]): one bounded SSH attempt"
   Write-Progress -Activity 'SSH rejection verification' -Status $case[0] -PercentComplete 50
   $r=Invoke-PaperRuntimeProcess 'C:\Windows\System32\OpenSSH\ssh.exe' (Get-PaytmNegativeSshArguments $case[1] $key) $fixture 12
   $passed=Test-PaytmNegativeSshResult $case[0] $r $fingerprint
   & $Record ([ordered]@{name=$case[0];passed=$passed;exitCode=$r.exitCode;elapsedSeconds=$r.elapsedSeconds;rawOutputRetained=$false})
   if(-not $passed){throw ('NEGATIVE_SSH_FAILED_'+$case[0])}
  }
 }catch{$primaryFailure=$_}finally{
  # Only these four generated files in the unique validated fixture; no recursive deletion.
  foreach($name in @('unregistered','unregistered.pub','known_hosts','wrong_hosts')){
   try{$p=Assert-PaytmAccountPath (Join-Path $fixture $name);if(Test-Path -LiteralPath $p){Remove-Item -LiteralPath $p -Force -ErrorAction Stop}}catch{$cleanupFailed=$true}
  }
  try{[IO.Directory]::Delete((Assert-PaytmAccountPath $fixture),$false)}catch{$cleanupFailed=$true}
  & $Record ([ordered]@{name='DISPOSABLE_FILES_REMOVED';passed=(-not $cleanupFailed)})
  Write-Progress -Activity 'SSH rejection verification' -Completed
 }
 if($primaryFailure){throw $primaryFailure}
 if($cleanupFailed){throw 'NEGATIVE_SSH_CLEANUP_FAILED'}
}
