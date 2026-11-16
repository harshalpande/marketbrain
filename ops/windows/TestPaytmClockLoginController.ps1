#Requires -Version 7.0
$ErrorActionPreference='Stop'
. "$PSScriptRoot/PaytmGatewayKeyCustody.ps1"
$public=[IO.File]::ReadAllText("$PSScriptRoot/paytm-vps-host-rsa.pub").Trim()
$pins=ConvertFrom-PaytmHostPublicKey $public
if($pins.fingerprint -cne 'SHA256:YTQ8GV8J4qOQkY4j3dGGyCTAzyR2iX/KSJoGK0p2dKI'){throw 'public pin failed'}
$rejected=$false
try{ConvertFrom-PaytmHostPublicKey ($pins.wrongHost.Trim() -replace '^130\.250\.191\.137 ','')|Out-Null}catch{$rejected=$true}
if(-not $rejected){throw 'wrong public pin accepted'}
$root=Join-Path ([IO.Path]::GetTempPath()) ('mb-clock-login-fixtures-'+[guid]::NewGuid().ToString('N'))
$null=New-Item -ItemType Directory $root
$count=2
foreach($case in @('success','authFailure','unsynchronized','wrongHost')){
 $dir=Join-Path $root $case;$null=New-Item -ItemType Directory $dir
 foreach($f in @('TestPaytmClockLogin.ps1','PaytmClockLogin.ps1','PaytmGatewayKeyCustody.ps1','paytm-vps-host-rsa.pub')){Copy-Item -LiteralPath "$PSScriptRoot/$f" -Destination $dir}
 if($case -eq 'wrongHost'){[IO.File]::WriteAllText((Join-Path $dir 'paytm-vps-host-rsa.pub'),($pins.wrongHost.Trim() -replace '^130\.250\.191\.137 ',''))}
 Add-Content -LiteralPath "$dir/PaytmGatewayKeyCustody.ps1" -Value @'
function Test-PaytmEncryptedKeyFile { [pscustomobject]@{encrypted=$true} }
function Get-FileHash([string]$LiteralPath){
 if($LiteralPath.EndsWith('authorization.json')){return [pscustomobject]@{Hash='A4D85CC3D9BF6F88978F5BCE881E5088810E9205B04E4061EB759F9B47543329'}}
 if($LiteralPath.EndsWith('preparation.json')){return [pscustomobject]@{Hash='6DDEB3B0B3DAFC9F67E4D6FFF8DAD671D57860B3ECD944778E489FBE4400D2DE'}}
 Microsoft.PowerShell.Utility\Get-FileHash -LiteralPath $LiteralPath
}
'@
 Add-Content -LiteralPath "$dir/PaytmClockLogin.ps1" -Value @'
function Invoke-ClockLoginNative([string]$Executable,[string[]]$Arguments,[int]$Seconds){
 $global:clockFixtureCalls++
 if(-not $Executable.EndsWith('/ssh.exe') -or $Arguments -notcontains 'StrictHostKeyChecking=yes' -or $Arguments -notcontains 'IdentityAgent=none' -or $Arguments -notcontains 'ClearAllForwardings=yes'){throw 'FIXTURE_UNSAFE_CLIENT_OR_SCAN'}
 $command=$Arguments[-1]
 if($command -ceq 'marketbrain-clock INVALID'){
  if($global:clockFixtureCase -ceq 'authFailure'){return [pscustomobject]@{exitCode=255;stdout='';stderr='Permission denied'}}
  return [pscustomobject]@{exitCode=1;stdout='';stderr='CLOCK_READ_DENIED_OR_UNAVAILABLE'}
 }
 $nonce=$command.Split(' ')[1];$sync=if($global:clockFixtureCase -ceq 'unsynchronized'){'no'}else{'yes'}
 [pscustomobject]@{exitCode=0;stdout="MB_CLOCK_V1|$nonce|1794800000000|$sync";stderr=''}
}
'@
 $prep=Join-Path $dir 'preparation.json';[IO.File]::WriteAllText($prep,'{"privateKeyPath":"fixture-only"}')
 $global:clockFixtureCalls=0;$global:clockFixtureCase=$case;$caught=$false
 try{& "$dir/TestPaytmClockLogin.ps1" -PreparationPath $prep -EvidencePath (Join-Path $dir 'authorization.json') -OutputDirectory $dir}catch{$caught=$true}
 $file=Get-ChildItem -LiteralPath $dir -Filter 'paytm-clock-login-*.json'
 $r=Get-Content -LiteralPath $file.FullName -Raw|ConvertFrom-Json
 if($case -eq 'success'){
  if($caught -or $r.status -cne 'CLOCK_SSH_LOGIN_AND_COMMAND_DENIAL_PASSED_CUSTODY_PENDING' -or $global:clockFixtureCalls -ne 3){throw 'controller success fixture failed'}
 }else{
  $expected=switch($case){authFailure{'CLOCK_LOGIN_DENIAL_NOT_PROVEN'} unsynchronized{'CLOCK_LOGIN_VPS_NTP_UNSYNCHRONIZED'} wrongHost{'KEY_HOST_PIN_MISMATCH'}}
  if(-not $caught -or $r.failure -cne $expected){throw "controller $case fixture failed: $($r.failure)"}
  if($case -eq 'wrongHost' -and $global:clockFixtureCalls -ne 0){throw 'connection attempted after wrong pin'}
 }
 $count++
}
Write-Host "$count public-pin and controller regression tests passed; no SSH connections made"
